#!/usr/bin/env python3
"""
probe_assemble_gap.py —— 查 assemble 阶段对 CSE 形式 mech 的兼容性缺口

assemble_lifted.py 完全不认识 cse_wires。两条路径会直接发射 mech 里的 func:
  1. 未提升的 bus  → E[f"{nm}#R{nid}"] = to_v(ff["func"])
  2. 组合输出      → E[f"@out{oid}"]    = to_v(od["func"])
如果这些 func 里有 _cN 引用, 发射出的 RTL 就会引用**未声明的 wire** → iverilog 报错。

而且 _cN 是**每个函数独立编号**的 (mech_cse 逐函数做 CSE), A 的 _c0 与 B 的 _c0
是完全不同的表达式 —— 不能当全局 wire 发射, 必须按 FF 加前缀或就地展开。

这个脚本量化缺口有多大, 以决定用哪种修法。
"""
import sys, json, re, argparse
from pathlib import Path

CREF = re.compile(r"_c\d+")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech"); ap.add_argument("names"); ap.add_argument("lift")
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    names = json.loads(Path(args.names).read_text())
    lift = json.loads(Path(args.lift).read_text())

    ff = {int(f["q_id"]): f for f in m["ff_defs"]}
    print(f"cse_prefix={m.get('cse_prefix')!r}")

    # 未提升的 bus → 走 raw 逐位路径
    unlifted = [b for b in names["buses"]
                if not (lift.get(b["name"], {}) or {}).get("lifted")]
    print(f"\n未提升的 bus: {len(unlifted)}/{len(names['buses'])}")

    bad_bits, tot_bits, expand_chars = 0, 0, 0
    worst = []
    for b in unlifted:
        for nid in b.get("bits", []):
            f = ff.get(int(nid))
            if not f:
                continue
            tot_bits += 1
            body = f.get("func") or ""
            ws = f.get("cse_wires") or []
            if CREF.search(body):
                bad_bits += 1
                # 就地展开后会有多大
                exp = sum(len(e) for _, e in ws)
                expand_chars += exp
                worst.append((exp, int(nid), len(ws), len(body)))

    print(f"其中会发射未声明 _cN 的位: {bad_bits}/{tot_bits}"
          f"  {'❌ 必须修' if bad_bits else '✅ 无缺口'}")
    if worst:
        worst.sort(reverse=True)
        print(f"\n就地展开的代价 (最大的几位):")
        for exp, nid, nw, blen in worst[:6]:
            print(f"  net_{nid}: func {blen:,} 字符 + {nw} wires "
                  f"→ 展开约 {exp/1e6:.2f}M 字符")
        print(f"  合计展开约 {expand_chars/1e6:.1f}M 字符")

    # 组合输出
    out_bad, out_tot = 0, 0
    for od in m.get("out_defs", []):
        if od.get("direct_ff"):
            continue
        out_tot += 1
        if CREF.search(od.get("func") or ""):
            out_bad += 1
    print(f"\n组合输出: {out_bad}/{out_tot} 含 _cN 引用")

    # _cN 命名是否跨函数冲突 (确认不能当全局 wire)
    sample = [f for f in m["ff_defs"] if f.get("cse_wires")][:2]
    if len(sample) == 2:
        a = dict(sample[0]["cse_wires"]).get("_c0")
        b = dict(sample[1]["cse_wires"]).get("_c0")
        print(f"\n_c0 在两个不同 FF 里的定义:")
        print(f"  net_{sample[0]['q_id']}: {str(a)[:70]}")
        print(f"  net_{sample[1]['q_id']}: {str(b)[:70]}")
        print(f"  → {'不同, 确认必须按 FF 加前缀' if a != b else '相同(巧合)'}")


if __name__ == "__main__":
    main()
