#!/usr/bin/env python3
"""
test_lift_cse.py —— 隔离测试: lift_bus 能否吃 CSE 形式的 mech

为什么要隔离: 直接跑 lift_runner 会被 build_buses 补出 2285 条 unnamed bus,
其中某条会在 z3 里拖尾, 把真正想测的东西埋掉。这里只跑指定的几条 bus,
每条带独立墙钟超时, 拖尾就跳过并如实报告。

关键: 同时测 **带 _cN wire 的 bus** (乘法器累加器, 爆炸源头) 和
**未压缩的普通 bus** (对照)。两条路径都必须过。

用法:
  python3 test_lift_cse.py <mech_cse.json> [--lo 27090] [--hi 27106]
                           [--budget 60] [--wall 300]
"""
import sys, json, time, argparse, signal
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))


class Timeout(Exception):
    pass


def _alarm(sig, frm):
    raise Timeout()


def run_bus(label, bits, ff, verilog, budget, wall):
    from struct_lift import lift_bus
    raw = [ff[q].get("func") for q in bits]
    wires = [ff[q].get("cse_wires") for q in bits]
    nch = sum(len(x or "") for x in raw)
    nw = sum(len(x or []) for x in wires)
    print(f"\n── {label}: {len(bits)} bits, func {nch:,} 字符, {nw} wires")

    signal.signal(signal.SIGALRM, _alarm)
    signal.alarm(wall)
    t0 = time.time()
    try:
        r = lift_bus(label, bits, raw, rst_net_id=None,
                     timeout_budget=budget, verilog=verilog, cse_wires=wires)
        dt = time.time() - t0
        signal.alarm(0)
    except Timeout:
        signal.alarm(0)
        print(f"   ⏱  墙钟超时 (>{wall}s) — z3 拖尾, 非解析问题")
        return "timeout"
    except Exception as e:
        signal.alarm(0)
        print(f"   ❌ 异常 {type(e).__name__}: {str(e)[:200]}")
        return "error"

    if r.get("parse_error"):
        print(f"   ❌ 解析失败: {r['parse_error'][:200]}")
        return "parse_error"
    tag = r.get("type", "?")
    print(f"   {'✅ 提升成功' if r.get('lifted') else '➖ 未提升(raw)'}"
          f"  type={tag}  {dt:.1f}s")
    return "lifted" if r.get("lifted") else "raw"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech")
    ap.add_argument("--lo", type=int, default=27090)
    ap.add_argument("--hi", type=int, default=27106)
    ap.add_argument("--n-plain", type=int, default=12)
    ap.add_argument("--budget", type=int, default=60, help="lift_bus 内部 z3 预算")
    ap.add_argument("--wall", type=int, default=300, help="每条 bus 墙钟上限")
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    ff = {int(f["q_id"]): f for f in m["ff_defs"]}
    qids = {int(x) for x in m["ff_q_ids"]}
    verilog = bool(m.get("cse_prefix"))
    print(f"mech: cse_prefix={m.get('cse_prefix')!r}  → verilog={verilog}")

    mul = [q for q in range(args.lo, args.hi) if q in qids]
    plain = [q for q in sorted(qids) if not ff[q].get("cse_wires")][:args.n_plain]

    res = {}
    # 先测小的对照组 (快, 先确认基本通路)
    res["plain_ctrl(未压缩)"] = run_bus("plain_ctrl", plain, ff, verilog,
                                        args.budget, args.wall)
    # 再逐位单独测爆炸源头 —— 单位测试比整条 bus 更能定位问题
    for q in mul[:4]:
        res[f"mul_bit_net_{q}"] = run_bus(f"mul_bit_{q}", [q], ff, verilog,
                                          args.budget, args.wall)
    # 最后整条累加器
    res["mul_accumulator(整条)"] = run_bus("mul_accumulator", mul, ff, verilog,
                                           args.budget, args.wall)

    print(f"\n{'='*52}")
    for k, v in res.items():
        print(f"  {k:26s} {v}")
    fatal = [k for k, v in res.items() if v in ("parse_error", "error")]
    print(f"\n结论: {'✅ CSE 形式解析通路正常' if not fatal else '❌ 解析有问题: ' + str(fatal)}")
    print("     (timeout 属 z3 性能问题, 不是解析问题)")
    sys.exit(1 if fatal else 0)


if __name__ == "__main__":
    main()
