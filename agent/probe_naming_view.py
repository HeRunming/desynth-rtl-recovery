#!/usr/bin/env python3
"""
probe_naming_view.py —— 检查"LLM 在命名阶段实际看到什么"

动机: mech_cse.py 把爆炸函数压下去了, 但它把结构证据从 func 搬进了 cse_wires。
semantic_naming.build_prompt 只喂 func 字段 → LLM 可能只看到 `(_c355 | _c342)`
这种不透明引用, 进位链/XOR/使能保持这些判断线索全在它看不见的地方。
那样命名质量会静默退化成一堆 "other", 而且**不报任何错**。

这个脚本如实打印 LLM 视角, 用来证实/证伪上述担忧。

用法: python3 probe_naming_view.py <mech.json> [--cap 600] [--n 4]
"""
import sys, json, argparse, re
from pathlib import Path


def opacity(text: str) -> float:
    """不透明度: 表达式里 _cN 引用占全部叶子引用的比例。越高 LLM 越看不懂。"""
    wires = re.findall(r"\b_c\d+\b", text)
    nets = re.findall(r"\bn\d+\b", text)
    tot = len(wires) + len(nets)
    return (len(wires) / tot) if tot else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech")
    ap.add_argument("--cap", type=int, default=600, help="命名阶段的截断长度")
    ap.add_argument("--n", type=int, default=4)
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    ff = {int(f["q_id"]): f for f in m["ff_defs"]}
    pfx = m.get("cse_prefix")
    print(f"mech: cse_prefix={pfx!r}")

    comp = [q for q in sorted(ff) if ff[q].get("cse_wires")]
    plain = [q for q in sorted(ff) if not ff[q].get("cse_wires")]
    print(f"压缩过的 FF: {len(comp)}   未压缩: {len(plain)}\n")

    print("=" * 66)
    print(f"压缩过的函数 —— LLM 在 cap={args.cap} 下看到的内容")
    print("=" * 66)
    for q in comp[:args.n]:
        body = ff[q].get("func") or ""
        nw = len(ff[q].get("cse_wires") or [])
        seen = body[:args.cap]
        print(f"\nnet_{q}  ({nw} wires, func {len(body)} 字符)")
        print(f"  不透明度 (_cN 占叶子引用): {opacity(seen)*100:.0f}%")
        print(f"  LLM 看到: {seen[:300]}")

    print("\n" + "=" * 66)
    print("未压缩的函数 (对照: 结构线索直接可见)")
    print("=" * 66)
    shown = 0
    for q in plain:
        body = ff[q].get("func") or ""
        if len(body) < 300:
            continue
        print(f"\nnet_{q}  (func {len(body)} 字符)")
        print(f"  不透明度: {opacity(body[:args.cap])*100:.0f}%")
        print(f"  LLM 看到: {body[:300]}")
        shown += 1
        if shown >= 2:
            break

    # 汇总: 压缩过的函数整体不透明度
    ops = [opacity((ff[q].get("func") or "")[:args.cap]) for q in comp]
    if ops:
        hi = sum(1 for o in ops if o > 0.5)
        print("\n" + "=" * 66)
        print(f"压缩函数平均不透明度: {sum(ops)/len(ops)*100:.0f}%")
        print(f"其中 >50% 不透明的: {hi}/{len(ops)} "
              f"({hi/len(ops)*100:.0f}%) —— 这些 LLM 基本看不懂")


if __name__ == "__main__":
    main()
