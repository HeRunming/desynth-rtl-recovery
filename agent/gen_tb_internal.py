#!/usr/bin/env python3
"""
gen_tb_internal.py —— 生成"内部寄存器交叉验证" testbench

用法:
  python3 gen_tb_internal.py <netlist.v> <raw.v> <lift.v> \
      --raw-mod picorv32_raw --lift-mod picorv32_lift [--cycles N] [-o tb.v]

端口级等价 (gen_tb.py) 只看输出脚, 内部状态错了但没传到输出就查不出来。
这里逐周期比对两个版本的**每一个寄存器**, 能把分歧定位到第一次出错的周期。

寄存器名直接从生成的 RTL 里抓 (而不是从 names.json 重算), 这样必然与
assemble_lifted 实际发射的名字一致 —— 去重后缀/unnamed_<nid> 补丁都不会错位。
"""
import sys, re, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ports import parse as parse_ports

REG = re.compile(r"^\s*reg\s+(?:\[\s*(\d+)\s*:\s*(\d+)\s*\]\s+)?([A-Za-z_]\w*)\s*;",
                 re.MULTILINE)


def regs_of(text: str) -> dict:
    """RTL 文本 → {reg名: 宽度}。"""
    out = {}
    for hi, lo, nm in REG.findall(text):
        out[nm] = (int(hi) - int(lo) + 1) if hi else 1
    return out


def gen(netlist_text, raw_text, lift_text, raw_mod, lift_mod,
        cycles=3000, clk="clk", rst="resetn", tb="tb_rl_all", skip=10):
    a, b = regs_of(raw_text), regs_of(lift_text)
    common = sorted(n for n in set(a) & set(b) if a[n] == b[n])
    if not common:
        raise SystemExit("两侧没有同名同宽的寄存器, 无法比对")
    only_a, only_b = sorted(set(a) - set(b)), sorted(set(b) - set(a))

    p = parse_ports(netlist_text)
    drive = [(n, w) for n, w in p["inputs"].items() if n not in (clk, rst)]
    N = len(common)

    L = ["`timescale 1ns/1ps",
         f"// 自动生成: 内部寄存器交叉验证 ({N} 个寄存器)",
         f"module {tb};",
         f"  reg {clk}=0, {rst}=0;"]
    for n, w in drive:
        L.append(f"  reg {f'[{w[0]}:{w[1]}] ' if w else ''}{n}=0;")

    # 只接输入脚: 输出留空, 本测试只关心内部状态
    conn = ", ".join([f".{clk}({clk})", f".{rst}({rst})"] +
                     [f".{n}({n})" for n, _ in drive])
    L += [f"  {raw_mod}  R({conn});",
          f"  {lift_mod} L({conn});",
          "",
          f"  always #5 {clk} = ~{clk};",
          "",
          f"  integer first_cyc [0:{N-1}];",
          "  integer i, k, nbad;",
          "  initial begin",
          f"    for (k=0;k<{N};k=k+1) first_cyc[k] = -1;",
          f"    {rst} = 0;",
          f"    repeat ({skip}) @(posedge {clk});",
          f"    {rst} = 1;",
          f"    for (i=0; i<{cycles}; i=i+1) begin",
          f"      @(negedge {clk});"]
    for n, w in drive:
        L.append(f"      {n} = $random;")
    L += [f"      @(posedge {clk});",
          "      #1;"]
    for idx, nm in enumerate(common):
        L.append(f"      if (first_cyc[{idx}] < 0 && R.{nm} !== L.{nm}) "
                 f"first_cyc[{idx}] = i;")
    L += ["    end",
          "",
          "    nbad = 0;",
          f"    for (k=0;k<{N};k=k+1) if (first_cyc[k] >= 0) nbad = nbad + 1;",
          f'    $display("INTERNAL {lift_mod}: %0d/%0d regs diverged '
          f'(%0d cycles)", nbad, {N}, {cycles});']
    # 分歧明细 (只在出错时打印, 避免刷屏)
    for idx, nm in enumerate(common):
        L.append(f'    if (first_cyc[{idx}] >= 0) $display("  DIVERGE cyc%0d  '
                 f'{nm}  raw=%h lift=%h", first_cyc[{idx}], R.{nm}, L.{nm});')
    L += ['    if (nbad == 0) $display("ALL INTERNAL REGS MATCH");',
          "    $finish;",
          "  end",
          "endmodule"]

    meta = {"n_common": N, "only_raw": only_a, "only_lift": only_b}
    return "\n".join(L), meta


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("netlist"); ap.add_argument("raw"); ap.add_argument("lift")
    ap.add_argument("--raw-mod", default="picorv32_raw")
    ap.add_argument("--lift-mod", default="picorv32_lift")
    ap.add_argument("--cycles", type=int, default=3000)
    ap.add_argument("--clk", default="clk"); ap.add_argument("--rst", default="resetn")
    ap.add_argument("--tb", default="tb_rl_all")
    ap.add_argument("-o", default=None)
    args = ap.parse_args()

    txt, meta = gen(Path(args.netlist).read_text(),
                    Path(args.raw).read_text(),
                    Path(args.lift).read_text(),
                    args.raw_mod, args.lift_mod,
                    cycles=args.cycles, clk=args.clk, rst=args.rst, tb=args.tb)
    if args.o:
        Path(args.o).write_text(txt)
        print(f"wrote {args.o}  ({len(txt.splitlines())} lines)")
    else:
        print(txt)
    print(f"比对寄存器: {meta['n_common']}")
    if meta["only_raw"]:
        print(f"仅 raw 侧有 ({len(meta['only_raw'])}): {meta['only_raw'][:5]}")
    if meta["only_lift"]:
        print(f"仅 lift 侧有 ({len(meta['only_lift'])}): {meta['only_lift'][:5]}")
