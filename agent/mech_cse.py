#!/usr/bin/env python3
"""
mech_cse.py —— 对 hal_mechanical 的提取结果做 CSE 预处理 (命名之前)

动机: Config A (ENABLE_FAST_MUL=1) 的 HAL 输出 566M 字符, 其中 19 个 FF
(0.8%) 占了 97.1% —— 乘法器累加器的每一位都把共享的部分积求和树抄了一遍。
这会让语义命名阶段没法跑 (塞不进 LLM), 整个 Config A 因此卡住。

CONFIG_A_POSTMORTEM.md 把"命名前做 CSE"列为正解之一, 但判断为"工程量大,
且解析 87M 字符本身就是瓶颈"而没做。实测证伪了后半句 (probe_cse_scale.py):
17MB 函数解析仅 4.6s, CSE 4.3s, 压缩 552×, 且 yosys miter+SAT 证明等价。

做法: 逐函数独立 CSE (不做跨函数共享)。理由是这一步的下游是**语义命名**,
LLM 需要每个函数自成一体地可读; 跨函数共享的 wire 会让单个函数变成一堆
悬空引用。最终 RTL 的跨函数共享由 assemble_lifted 里的全局 CSE 负责。

输出格式: 在每个 ff_def / out_def 上加 `cse_wires` 字段 (拓扑序的
[(名,表达式)] 列表), `func` 换成压缩后的主体。wire 名统一前缀 `_c`,
与 assemble 阶段的 `w` 前缀不冲突。

用法:
  python3 mech_cse.py <in_mech.json> <out_mech.json> [--workers 16]
                      [--min-chars 20000] [--verify N]
"""
import sys, json, re, time, argparse, os
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
sys.path.insert(0, str(Path(__file__).parent))
from artifact_contract import attach_contract

PREFIX = "_c"


def hal_to_v(func: str) -> str:
    """HAL 函数串 → CSE 可解析的 Verilog (与 assemble_lifted.hal_to_v 一致)。"""
    if func is None:
        return ""
    v = func.replace("0b1", "1'b1").replace("0b0", "1'b0")
    v = re.sub(r"net_(\d+)", r"n\1", v)
    return v.replace("!", "~")


def _one(payload):
    """压缩单个函数。返回 (key, 新func, wires, 原长, 新长)。"""
    import threading
    key, raw, min_chars, min_size, min_uses, max_wires = payload
    v = hal_to_v(raw)
    n0 = len(v)
    if n0 < min_chars:
        return key, v, [], n0, n0

    out = {}

    def work():
        from cse import cse_expressions
        E, wires = cse_expressions({"@f": v}, min_size=min_size,
                                   min_uses=min_uses, max_wires=max_wires)
        out["body"], out["wires"] = E["@f"], wires

    # 大栈线程: 递归下降解析深嵌套表达式会爆 C 栈 (segfault 抓不到)
    sys.setrecursionlimit(400_000)
    threading.stack_size(1024 * 1024 * 1024)
    th = threading.Thread(target=work, daemon=True)
    th.start(); th.join()
    if "body" not in out:
        return key, v, [], n0, n0          # 失败则保持原样, 不阻塞整条流水
    body, wires = out["body"], out["wires"]
    # wire 名加前缀, 避免与 net 名 (nNNN) 及 assemble 的 wN 撞车
    if wires:
        ren = {w: f"{PREFIX}{i}" for i, (w, _) in enumerate(wires)}
        pat = re.compile(r"\b(" + "|".join(sorted(ren, key=len, reverse=True)) + r")\b")
        sub = lambda s: pat.sub(lambda m: ren[m.group(1)], s)
        wires = [(ren[w], sub(e)) for w, e in wires]
        body = sub(body)
    n1 = len(body) + sum(len(w) + len(e) + 4 for w, e in wires)
    return key, body, wires, n0, n1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp"); ap.add_argument("out")
    ap.add_argument("--workers", type=int, default=min(16, os.cpu_count() or 4))
    ap.add_argument("--min-chars", type=int, default=20000,
                    help="小于此长度的函数不动 (CSE 反而增加噪声)")
    ap.add_argument("--min-size", type=int, default=3)
    ap.add_argument("--min-uses", type=int, default=2)
    ap.add_argument("--max-wires", type=int, default=20000)
    args = ap.parse_args()

    t0 = time.time()
    m = json.load(open(args.inp))
    print(f"读入 {args.inp}  ({time.time()-t0:.1f}s)")

    jobs = []
    for i, f in enumerate(m.get("ff_defs", [])):
        jobs.append((("ff", i), f.get("func"), args.min_chars,
                     args.min_size, args.min_uses, args.max_wires))
    for i, o in enumerate(m.get("out_defs", [])):
        if not o.get("direct_ff"):
            jobs.append((("out", i), o.get("func"), args.min_chars,
                         args.min_size, args.min_uses, args.max_wires))
    print(f"待处理 {len(jobs)} 个函数, {args.workers} workers, "
          f"阈值 {args.min_chars:,} 字符")

    tot0 = tot1 = 0
    touched = 0
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        for k, (key, body, wires, n0, n1) in enumerate(
                ex.map(_one, jobs, chunksize=4), 1):
            kind, i = key
            tgt = m["ff_defs"][i] if kind == "ff" else m["out_defs"][i]
            tgt["func"] = body
            if wires:
                tgt["cse_wires"] = wires
                touched += 1
            tot0 += n0; tot1 += n1
            if k % 200 == 0 or k == len(jobs):
                print(f"  {k}/{len(jobs)}  {tot0/1e6:.1f}M → {tot1/1e6:.1f}M  "
                      f"({time.time()-t0:.0f}s)", flush=True)

    m["cse_prefix"] = PREFIX
    attach_contract(
        m, stage="mech_cse", input_paths={"mechanical": args.inp},
        counts={
            "ffs": len(m.get("ff_defs", [])),
            "outputs": len(m.get("out_defs", [])),
            "cse_touched": touched,
            "skipped": sum(1 for x in m.get("ff_defs", []) if x.get("skipped")),
            "missing_func": sum(1 for x in m.get("ff_defs", []) if not x.get("func")),
        },
        status="partial" if any(x.get("skipped") for x in m.get("ff_defs", [])) else "ok",
    )
    with open(args.out, "w") as fh:
        json.dump(m, fh)
    print(f"\n压缩 {touched} 个函数 (其余低于阈值未动)")
    print(f"总字符 {tot0/1e6:.1f}M → {tot1/1e6:.1f}M  "
          f"({tot0/max(tot1,1):.1f}×)   用时 {time.time()-t0:.0f}s")
    print(f"写出 {args.out}  ({Path(args.out).stat().st_size/1e6:.1f}M)")


if __name__ == "__main__":
    main()
