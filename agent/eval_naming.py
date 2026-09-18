#!/usr/bin/env python3
"""
eval_naming.py —— 用 net_meta 的真名事后评估 LLM 命名质量

诚实性: 真名只在**这里**用于打分, 绝不进入 prompt (semantic_naming 喂的是
匿名布尔函数)。这个脚本读 mech 的 net_meta 只为了当标尺。

按"信号族"评估而非逐信号 (踩过的坑): DANA/LLM 会把寄存器堆 32 个寄存器的同一
位号聚成一组, 真名是 cpuregs[3](0), cpuregs[4](0)... 各 1 位。按信号名算纯度
只有 1/31, 但 LLM 识别为 "register_file_bit_slice" 是**完全正确**的。
所以把 cpuregs[N] → cpuregs、genblk1.pcpi_mul.rd(21) → pcpi_mul.rd 归族。

用法: python3 eval_naming.py <mech.json> <names.json> [--min-width 2]
"""
import sys, json, re, argparse
from collections import Counter
from pathlib import Path


def family(raw: str) -> str:
    """真名 → 信号族。剥掉位下标与层级前缀里的 genblk 包装。"""
    if not raw:
        return "?"
    s = re.sub(r"\((\d+)\)$", "", raw)      # pcpi_rs1(0) → pcpi_rs1
    s = re.sub(r"\[(\d+)\]$", "", s)        # cpuregs[3]  → cpuregs
    s = re.sub(r"\[\d+\]", "", s)           # cpuregs[3](0) 之类
    parts = [p for p in s.split(".") if not re.fullmatch(r"genblk\d*", p)]
    return ".".join(parts) if parts else s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech"); ap.add_argument("names")
    ap.add_argument("--min-width", type=int, default=2,
                    help="只统计宽度 >= 此值的 bus (1 位的没有分组信息可评)")
    ap.add_argument("--show", type=int, default=14)
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    nm = {int(k): v.get("name", "") for k, v in m["net_meta"].items()}
    plan = json.loads(Path(args.names).read_text())
    buses = plan.get("buses", [])

    wide = [b for b in buses if len(b.get("bits", [])) >= args.min_width]
    print(f"bus 总数 {len(buses)}   宽度>={args.min_width} 的 {len(wide)}")
    if plan.get("errors"):
        print(f"命名阶段错误批次: {len(plan['errors'])}")

    pure, rows = 0, []
    for b in wide:
        fams = Counter(family(nm.get(int(x), "")) for x in b["bits"])
        top, cnt = fams.most_common(1)[0]
        p = cnt / len(b["bits"])
        if p >= 0.8:
            pure += 1
        rows.append((p, b.get("name", "?"), b.get("role", "?"),
                     len(b["bits"]), top, len(fams)))

    print(f"\n同族纯度 >=0.8 的: {pure}/{len(wide)} "
          f"({pure/len(wide)*100:.0f}%)" if wide else "")

    # 角色分布
    roles = Counter(b.get("role", "?") for b in buses)
    print(f"角色分布: {dict(roles.most_common())}")
    other = roles.get("other", 0)
    print(f"'other' 占比: {other}/{len(buses)} ({other/max(len(buses),1)*100:.0f}%)"
          "   ← 越低越好, 高说明 LLM 看不懂")

    rows.sort(reverse=True)
    print(f"\n{'纯度':>5}  {'LLM 命名':26} {'role':10} {'位宽':>4}  真名(主族)")
    for p, name, role, w, top, nf in rows[:args.show]:
        print(f"{p*100:4.0f}%  {name[:26]:26} {role[:10]:10} {w:4}  {top}"
              + (f"  (+{nf-1} 族)" if nf > 1 else ""))
    if len(rows) > args.show:
        print("  ...")
        for p, name, role, w, top, nf in rows[-4:]:
            print(f"{p*100:4.0f}%  {name[:26]:26} {role[:10]:10} {w:4}  {top}"
                  + (f"  (+{nf-1} 族)" if nf > 1 else ""))


if __name__ == "__main__":
    main()
