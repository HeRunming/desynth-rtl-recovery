#!/usr/bin/env python3
"""
hybrid_pipeline.py —— HAL + LLM 混合反综合 pipeline

对比两种模式, 量化 HAL 带来的增益:
  A. baseline : 纯 LLM (只给网表)
  B. hybrid   : HAL 提取结构事实 -> 作为线索喂给 LLM

流程 (hybrid):
  网表 --HAL--> 结构事实(端口/寄存器分组/门统计)
       --LLM(带线索)--> 可读RTL --Yosys--> 等价性验证 --反馈重试-->

用法:
  export LLM_BASE=... LLM_KEY=...
  export PATH=".../oss-cad-suite/bin:$PATH"
  python3 hybrid_pipeline.py --netlist ../pipeline/uart_tx_hal_netlist.v --top uart_tx --mode hybrid
"""
import argparse, json, os, re, subprocess, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from backends import OpenAICompatBackend
from verifier import check_equivalence
from artifact_contract import attach_contract

HAL_PY = "/usr/bin/python3"
HAL_EXTRACT = str(Path(__file__).parent / "hal_extract.py")
DEFAULT_GATELIB = "/Users/blackbox/try_hai/hal/plugins/gate_libraries/definitions/example_library.hgl"


def run_hal_extract(netlist, gatelib):
    """独立进程调用 HAL 提取结构事实(因 HAL 需要特殊 python 环境)。"""
    env = dict(os.environ, HAL_BASE_PATH="/Users/blackbox/try_hai/hal/build")
    r = subprocess.run([HAL_PY, HAL_EXTRACT, netlist, gatelib],
                       capture_output=True, text=True, env=env, timeout=120)
    out = r.stdout
    if "###JSON_START###" in out:
        js = out.split("###JSON_START###", 1)[1].strip()
        try:
            return json.loads(js)
        except Exception as e:
            return {"error": f"JSON解析失败: {e}"}
    return {"error": "HAL提取无输出", "stderr_tail": r.stderr[-300:]}


SYSTEM = """你是硬件逆向工程专家, 擅长反综合: 读门级网表, 恢复出功能等价的可读高层 Verilog RTL。
要求: 识别数据路径(加法器/计数器/移位/比较)和控制逻辑(状态机); 用有意义的命名、高层运算符、case结构;
顶层模块名和端口(名+位宽)必须与网表一致(会做形式化等价性检查); 只输出一个```verilog代码块。"""

USER_BASE = """请把下面的门级网表反综合成可读的高层 Verilog RTL。

模块名: {top}

网表:
```verilog
{netlist}
```"""

HAL_HINTS = """

=== HAL 静态分析提供的结构线索(精确, 可信赖) ===
- 顶层端口: 输入 {inputs}; 输出 {outputs}
- 触发器总数: {nff} 个
- 门类型统计: {hist}
- DANA 自动识别的寄存器分组(可能需你结合语义修正边界):
{groups}

请利用这些精确线索(尤其寄存器位宽和端口), 但用你的语义理解判断它们的真实含义(如哪个是状态寄存器、哪个是计数器/移位寄存器)。"""

RETRY = """你上次生成的 RTL 未通过形式化等价性验证。
错误: {reason}
你上次的输出:
```verilog
{last}
```
请修正后重新输出完整的功能等价 Verilog RTL(只输出一个```verilog代码块)。"""


def extract_verilog(text):
    m = re.search(r"```(?:verilog|systemverilog)?\s*\n(.*?)```", text, re.DOTALL)
    return (m.group(1) if m else text).strip()


def build_hints(facts):
    """把 HAL 事实格式化成 prompt 线索。"""
    groups_str = ""
    for g in facts.get("register_groups", []):
        groups_str += f"    * {g['width']}位寄存器组 (触发器: {', '.join(g['flip_flops'][:4])}{'...' if g['width']>4 else ''})\n"
    return HAL_HINTS.format(
        inputs=", ".join(facts.get("top_ports", {}).get("inputs", [])),
        outputs=", ".join(facts.get("top_ports", {}).get("outputs", [])),
        nff=facts.get("num_flip_flops", "?"),
        hist=facts.get("gate_type_histogram", {}),
        groups=groups_str or "    (无)",
    )


def run(netlist_path, top, mode, gatelib, backend, max_retries=4, verbose=True):
    def log(*a):
        if verbose: print(*a, flush=True)

    netlist = Path(netlist_path).read_text()
    trace = {"top": top, "mode": mode, "attempts": []}

    # hybrid 模式: 先用 HAL 提取结构事实
    hints = ""
    if mode == "hybrid":
        log("=== [HAL] 提取结构事实 ===")
        facts = run_hal_extract(netlist_path, gatelib)
        if "error" in facts:
            log(f"  HAL 提取失败: {facts['error']} (降级为纯LLM)")
        else:
            log(f"  端口: {len(facts['top_ports']['inputs'])}入/{len(facts['top_ports']['outputs'])}出, "
                f"触发器: {facts['num_flip_flops']}, 寄存器组: {len(facts['register_groups'])}")
            trace["hal_facts"] = facts
            hints = build_hints(facts)

    last_rtl, last_reason = None, None
    for attempt in range(1, max_retries + 1):
        log(f"\n─── 第 {attempt}/{max_retries} 轮 ({mode}) ───")
        if attempt == 1:
            user = USER_BASE.format(top=top, netlist=netlist) + hints
        else:
            user = RETRY.format(reason=last_reason, last=last_rtl)

        t0 = time.time()
        raw = backend.complete(SYSTEM, user)
        dt = time.time() - t0
        rtl = extract_verilog(raw)
        log(f"  LLM 生成 ({dt:.1f}s, {len(rtl)}字符), 验证中...")

        result = check_equivalence(rtl, netlist, top)
        trace["attempts"].append({
            "attempt": attempt, "verified": result["ok"],
            "status": result.get("status", "unknown"),
            "reason": result["reason"], "log": result.get("log", ""),
            "log_tail": result.get("log_tail", ""),
            "rtl": rtl, "llm_seconds": round(dt, 1)})

        if result["ok"]:
            log(f"  ✅ 等价性验证通过! (第{attempt}轮)")
            trace.update(success=True, verdict=result.get("status", "proven"),
                         final_rtl=rtl, attempts_used=attempt)
            return trace
        log(f"  ❌ {result['reason']}")
        last_rtl, last_reason = rtl, result["reason"]

    trace.update(success=False, verdict=(trace["attempts"][-1].get("status", "unknown")
                                        if trace["attempts"] else "unknown"),
                 final_rtl=last_rtl, attempts_used=max_retries)
    return trace


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--netlist", required=True)
    ap.add_argument("--top", required=True)
    ap.add_argument("--mode", choices=["baseline", "hybrid"], default="hybrid")
    ap.add_argument("--gatelib", default=DEFAULT_GATELIB)
    ap.add_argument("--model", default="gpt-5.5")
    ap.add_argument("--max-retries", type=int, default=4)
    ap.add_argument("--save")
    args = ap.parse_args()

    backend = OpenAICompatBackend(model=args.model)
    print(f"=== 混合 pipeline [{args.mode}] netlist={Path(args.netlist).name} top={args.top} ===")
    trace = run(args.netlist, args.top, args.mode, args.gatelib, backend, args.max_retries)

    print("\n" + "=" * 60)
    print(f"{'✅ 成功' if trace['success'] else '❌ 失败'} "
          f"(模式={args.mode}, 用了{trace['attempts_used']}轮)")
    if args.save:
        # Traces are artifacts too: retain the same versioned port/manifest
        # contract as the mechanical pipeline, while keeping old fields.
        if trace.get("hal_facts", {}).get("top_ports"):
            trace["top_ports"] = trace["hal_facts"]["top_ports"]
        attach_contract(trace, stage="hybrid_pipeline",
                        input_paths={"netlist": args.netlist},
                        counts={"attempts": len(trace.get("attempts", [])),
                                "errors": sum(1 for a in trace.get("attempts", [])
                                               if not a.get("verified"))},
                        status="ok" if trace.get("success") else "partial")
        Path(args.save).write_text(json.dumps(trace, ensure_ascii=False, indent=2))
        print(f"轨迹保存: {args.save}")


if __name__ == "__main__":
    main()
