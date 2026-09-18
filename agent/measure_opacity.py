#!/usr/bin/env python3
"""
measure_opacity.py —— 量化"内联修复"对 LLM 可见度的实际效果

probe_naming_view.py 测出修复前: 压缩函数平均不透明度 56%, 71% 的函数过半引用
是不透明的 _cN。这个脚本对同一批函数跑修复后的 build_prompt 路径, 对比前后。

不透明度 = 表达式里 _cN 引用数 / (所有 _cN + net 引用数)。
修复后仍不为 0 是**预期的**: 长定义刻意保留具名引用 + where 块, 那比把同一大段
抄很多遍更可读。所以这里额外报告"where 块是否给出了定义"(有定义的引用不算看不懂)。

用法: python3 measure_opacity.py <mech_cse.json> [--cap 600]
"""
import sys, json, re, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from semantic_naming import _inline_small_wires, _CREF

NET = re.compile(r"\bn\d+\b")


def opacity(text: str) -> float:
    w, n = len(_CREF.findall(text)), len(NET.findall(text))
    return (w / (w + n)) if (w + n) else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech"); ap.add_argument("--cap", type=int, default=600)
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    comp = [f for f in m["ff_defs"] if f.get("cse_wires")]
    print(f"压缩过的 FF: {len(comp)}   cap={args.cap}\n")

    before, after, undef, wire_lines = [], [], 0, []
    for f in comp:
        body = f.get("func") or ""
        wires = f["cse_wires"]
        before.append(opacity(body[:args.cap]))

        nb, rest = _inline_small_wires(body, wires)
        shown = nb[:args.cap] if args.cap else nb
        after.append(opacity(shown))
        # where 块是否覆盖了 shown 里所有 _cN 引用
        defined = {w for w, _ in rest}
        refs = set(_CREF.findall(shown))
        if refs - defined:
            undef += 1
        wire_lines.append(len(rest))

    def stat(xs):
        return sum(xs) / len(xs) if xs else 0.0

    hi_b = sum(1 for o in before if o > 0.5)
    hi_a = sum(1 for o in after if o > 0.5)
    zero_a = sum(1 for o in after if o == 0.0)

    print(f"{'':22} {'修复前':>10} {'修复后':>10}")
    print(f"{'平均不透明度':22} {stat(before)*100:9.0f}% {stat(after)*100:9.0f}%")
    print(f"{'>50% 不透明的函数':22} {hi_b:6}/{len(before)} {hi_a:6}/{len(after)}")
    print(f"{'完全透明(0%)的函数':22} {'-':>10} {zero_a:6}/{len(after)}")
    print()
    print(f"where 块里出现未定义 _cN 的函数: {undef}  "
          f"({'✅ 无' if undef == 0 else '❌ 有, 说明闭包算错'})")
    print(f"where 块平均列出 {stat(wire_lines):.1f} 个共享子表达式 "
          f"(最多 {max(wire_lines) if wire_lines else 0})")


if __name__ == "__main__":
    main()
