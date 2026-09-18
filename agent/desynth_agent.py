#!/usr/bin/env python3
"""
desynth_agent.py —— Phase 1 反综合 Agent 最小闭环

流程:
  门级网表 → 构造prompt → LLM生成RTL → 提取代码 → 等价性验证
                ↑                                      │
                └────── 带错误反馈重试 (最多N轮) ◄──────┘

用法:
  export LLM_BASE="..."; export LLM_KEY="..."
  export PATH="/Users/blackbox/try_hai/oss-cad-suite/bin:$PATH"
  python3 desynth_agent.py --netlist ../examples/traffic_fsm/traffic_netlist.v --top traffic
"""
import argparse, re, sys, os, json, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from backends import OpenAICompatBackend
from verifier import check_equivalence

SYSTEM_PROMPT = """你是一个硬件逆向工程专家, 擅长"反综合"(de-synthesis):
读懂门级网表(一堆无名的逻辑门和连线), 恢复出人类可读、功能等价的高层 Verilog RTL。

要求:
1. 识别数据路径结构(加法器/计数器/移位/比较等)和控制逻辑(状态机/条件转移)。
2. 用有意义的信号名、注释、高层运算符(如 count+1 而非展开的进位链)重建 RTL。
3. 顶层模块的端口名和位宽必须与网表完全一致(会做形式化等价性检查)。
4. 只输出一个 ```verilog 代码块, 不要多余解释。"""

USER_TMPL = """下面是一个门级网表, 请反综合成可读的高层 Verilog RTL。

模块名: {top}

网表:
```verilog
{netlist}
```

请输出功能等价的高层 RTL。"""

RETRY_TMPL = """你上一次生成的 RTL 没有通过形式化等价性验证。

错误信息: {reason}

你上次的输出:
```verilog
{last}
```

请修正后重新输出完整的、功能等价的 Verilog RTL (只输出一个 ```verilog 代码块)。"""


def extract_verilog(text: str) -> str:
    """从 LLM 输出里提取 verilog 代码块。"""
    m = re.search(r"```(?:verilog|systemverilog)?\s*\n(.*?)```", text, re.DOTALL)
    if m:
        return m.group(1).strip()
    # 没有围栏就假定整段都是代码
    return text.strip()


def desynthesize(netlist: str, top: str, backend, max_retries=3, verbose=True):
    """反综合闭环: 生成→验证→重试, 直到等价或用尽次数。"""
    def log(*a):
        if verbose: print(*a, flush=True)

    history = {"top": top, "attempts": []}
    last_rtl = None
    last_reason = None

    for attempt in range(1, max_retries + 1):
        log(f"\n─── 第 {attempt}/{max_retries} 轮 ───")
        # 构造 prompt: 首轮用原始网表, 重试轮带上错误反馈
        if attempt == 1:
            user = USER_TMPL.format(top=top, netlist=netlist)
        else:
            user = RETRY_TMPL.format(reason=last_reason, last=last_rtl)

        t0 = time.time()
        raw = backend.complete(SYSTEM_PROMPT, user)
        dt = time.time() - t0
        rtl = extract_verilog(raw)
        log(f"  LLM 生成完毕 ({dt:.1f}s, {len(rtl)} 字符), 开始等价性验证...")

        result = check_equivalence(rtl, netlist, top)
        history["attempts"].append({
            "attempt": attempt, "rtl": rtl,
            "verified": result["ok"], "status": result.get("status", "unknown"),
            "reason": result["reason"], "log": result.get("log", ""),
            "log_tail": result.get("log_tail", ""),
            "llm_seconds": round(dt, 1),
        })

        if result["ok"]:
            log(f"  ✅ 等价性验证通过! (第 {attempt} 轮成功)")
            history["success"] = True
            history["verdict"] = result.get("status", "proven")
            history["final_rtl"] = rtl
            history["attempts_used"] = attempt
            return history
        else:
            log(f"  ❌ 未通过: {result['reason']}")
            last_rtl = rtl
            last_reason = result["reason"]

    history["success"] = False
    history["verdict"] = (history["attempts"][-1].get("status", "unknown")
                           if history["attempts"] else "unknown")
    history["final_rtl"] = last_rtl
    history["attempts_used"] = max_retries
    return history


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--netlist", required=True, help="门级网表 .v 文件")
    ap.add_argument("--top", required=True, help="顶层模块名")
    ap.add_argument("--model", default="gpt-5.5")
    ap.add_argument("--max-retries", type=int, default=3)
    ap.add_argument("--save", help="把轨迹保存为 JSON (供 Phase2 训练用)")
    args = ap.parse_args()

    netlist = Path(args.netlist).read_text()
    backend = OpenAICompatBackend(model=args.model)

    print(f"=== 反综合 Agent ===")
    print(f"输入网表: {args.netlist}  (top={args.top}, 模型={args.model})")

    result = desynthesize(netlist, args.top, backend,
                          max_retries=args.max_retries)

    print("\n" + "=" * 60)
    if result["success"]:
        print(f"✅ 成功 (用了 {result['attempts_used']} 轮)  恢复出的 RTL:\n")
        print(result["final_rtl"])
    else:
        print(f"❌ {args.max_retries} 轮内未能恢复出等价 RTL")

    if args.save:
        Path(args.save).write_text(
            json.dumps(result, ensure_ascii=False, indent=2))
        print(f"\n轨迹已保存: {args.save}")


if __name__ == "__main__":
    main()
