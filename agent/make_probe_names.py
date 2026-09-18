#!/usr/bin/env python3
"""
make_probe_names.py —— 造一份"管道测试用"的 names 文件

目的: 验证 lift 阶段能否吃 CSE 形式的 mech, 这一步不需要 LLM。
选的 bus 刻意包含**爆炸源头**(乘法器累加器 net_27090..27105, 连号且带 _cN wire),
再加一组未被压缩的普通 FF 作对照 —— 两条路径都要过。

用法: python3 make_probe_names.py <mech_cse.json> <out_names.json> [--lo 27090] [--hi 27106]
"""
import sys, json, argparse
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech"); ap.add_argument("out")
    ap.add_argument("--lo", type=int, default=27090)
    ap.add_argument("--hi", type=int, default=27106)
    ap.add_argument("--n-plain", type=int, default=12)
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    ff = {int(f["q_id"]): f for f in m["ff_defs"]}
    qids = {int(x) for x in m["ff_q_ids"]}
    print(f"cse_prefix: {m.get('cse_prefix')!r}")

    mul = [q for q in range(args.lo, args.hi) if q in qids]
    plain = [q for q in sorted(qids) if not ff[q].get("cse_wires")][:args.n_plain]

    buses = []
    if mul:
        buses.append({"name": "mul_accumulator", "role": "data_reg", "bits": mul})
    if plain:
        buses.append({"name": "plain_ctrl", "role": "other", "bits": plain})
    names = {"buses": buses, "n_ff": len(qids), "errors": []}
    Path(args.out).write_text(json.dumps(names))

    print(f"mul bits   : {len(mul)}  {mul[:4]} ...")
    print(f"plain bits : {len(plain)}  {plain[:4]}")
    for q in mul[:4]:
        nch = len(ff[q].get("func") or "")
        nw = len(ff[q].get("cse_wires") or [])
        print(f"  net_{q}: func {nch:,} 字符, {nw} wires")
    for q in plain[:2]:
        nch = len(ff[q].get("func") or "")
        print(f"  net_{q}: func {nch:,} 字符, 0 wires (未压缩)")
    print(f"写出 {args.out}")


if __name__ == "__main__":
    main()
