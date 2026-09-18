#!/usr/bin/env python3
"""
gen_tb.py —— 从网表端口自动生成等价性验证 testbench

用法:
  python3 gen_tb.py <netlist.v> <gold_mod> <dut_mod> [--cycles N] [--rst-active-low]

生成的 tb 对比 gold 与 dut 的所有输出端口, 每周期在时钟低电平期驱动随机输入。
"""
import sys, argparse
from pathlib import Path
from parse_ports import parse


def gen(netlist_text, gold_mod, dut_mod, cycles=20000,
        rst_low=True, clk="clk", rst="resetn", tb="tb_eq", skip=10):
    p = parse(netlist_text)
    ins, outs = p["inputs"], p["outputs"]
    drive = [(n, w) for n, w in ins.items() if n not in (clk, rst)]

    L = ["`timescale 1ns/1ps", f"module {tb};"]
    L.append(f"  reg {clk}=0;")
    L.append(f"  reg {rst}={'0' if rst_low else '1'};")
    for n, w in drive:
        L.append(f"  reg {f'[{w[0]}:{w[1]}] ' if w else ''}{n}=0;")
    for pre in ("g", "d"):
        for n, w in outs.items():
            L.append(f"  wire {f'[{w[0]}:{w[1]}] ' if w else ''}{pre}_{n};")
    L.append("")

    def inst(mod, name, pre):
        conns = [f".{clk}({clk})", f".{rst}({rst})"]
        conns += [f".{n}({n})" for n, _ in drive]
        conns += [f".{n}({pre}_{n})" for n in outs]
        body = ",\n    ".join(conns)
        return f"  {mod} {name}(\n    {body});"

    L.append(inst(gold_mod, "gold", "g"))
    L.append(inst(dut_mod, "dut", "d"))
    L.append("")
    L.append(f"  always #5 {clk} = ~{clk};")
    L.append("")
    L.append("  integer i, errors=0, checks=0, xskip=0, bi;")
    L.append("  reg shown=0;")
    NO = len(outs)
    L.append(f"  integer sig_err [0:{NO-1}];   // 每个输出端口的错误计数")
    L.append(f"  integer sig_first [0:{NO-1}];  // 首次失配周期")
    L.append("  integer k;")
    L.append("")
    W = max((w[0] - w[1] + 1) if w else 1 for w in outs.values())
    L.append(f"  reg [{W-1}:0] mask;")
    L.append(f"  task chk(input integer idx, input [255:0] nm, "
             f"input [{W-1}:0] a, input [{W-1}:0] b);")
    L.append("    begin")
    L.append("      // gold 侧含 X 的位视为 don't-care: 逐位用 === 判定")
    L.append(f"      for (bi = 0; bi < {W}; bi = bi + 1)")
    L.append("        mask[bi] = !((a[bi] === 1'bx) || (a[bi] === 1'bz));")
    L.append("      if (mask === 0) begin")
    L.append("        xskip = xskip + 1;")
    L.append("      end else begin")
    L.append("      checks = checks + 1;")
    L.append("      if ((a & mask) !== (b & mask)) begin")
    L.append("        errors = errors + 1;")
    L.append("        sig_err[idx] = sig_err[idx] + 1;")
    L.append("        if (sig_first[idx] < 0) sig_first[idx] = i;")
    L.append("        if (!shown) begin")
    L.append('          $display("FIRST MISMATCH cyc%0d %0s: gold=%h dut=%h mask=%h",')
    L.append("                   i, nm, a, b, mask);")
    L.append("          shown = 1;")
    L.append("        end")
    L.append("      end")
    L.append("      end")
    L.append("    end")
    L.append("  endtask")
    L.append("")
    L.append("  initial begin")
    L.append(f"    for (k = 0; k < {NO}; k = k + 1) begin")
    L.append("      sig_err[k] = 0; sig_first[k] = -1;")
    L.append("    end")
    L.append(f"    repeat(5) @(posedge {clk});")
    L.append(f"    #1 {rst} = {'1' if rst_low else '0'};")
    L.append(f"    for (i = 0; i < {cycles}; i = i + 1) begin")
    L.append(f"      @(negedge {clk});")
    for n, w in drive:
        L.append(f"      {n} = $random;")
    L.append(f"      @(posedge {clk}); #2;")
    L.append(f"      if (i >= {skip}) begin  // 跳过复位传播周期")
    for idx, (n, w) in enumerate(outs.items()):
        width = (w[0] - w[1] + 1) if w else 1
        pad = f"{{{W-width}'b0, " if width < W else ""
        cl = "}" if width < W else ""
        L.append(f'        chk({idx}, "{n}", {pad}g_{n}{cl}, {pad}d_{n}{cl});')
    L.append("      end")
    L.append("    end")
    L.append(f'    $display("EQUIV {dut_mod}: %0d mismatches / %0d checks '
             f'(%0d cycles, %0d all-X checks skipped)",')
    L.append("             errors, checks, i, xskip);")
    L.append('    $display("---- per-signal breakdown ----");')
    for idx, n in enumerate(outs):
        L.append(f'    if (sig_err[{idx}]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", '
                 f'"{n}", sig_err[{idx}], sig_first[{idx}]);')
        L.append(f'    else $display("  ok   %-14s", "{n}");')
    L.append("    $finish;")
    L.append("  end")
    L.append("endmodule")
    return "\n".join(L)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("netlist"); ap.add_argument("gold"); ap.add_argument("dut")
    ap.add_argument("--cycles", type=int, default=20000)
    ap.add_argument("--rst-active-high", action="store_true")
    ap.add_argument("--clk", default="clk"); ap.add_argument("--rst", default="resetn")
    ap.add_argument("--tb", default="tb_eq")
    ap.add_argument("--skip", type=int, default=10,
                    help="复位传播期跳过的周期数")
    ap.add_argument("-o", default=None)
    a = ap.parse_args()
    txt = gen(Path(a.netlist).read_text(), a.gold, a.dut, a.cycles,
              not a.rst_active_high, a.clk, a.rst, a.tb, a.skip)
    if a.o:
        Path(a.o).write_text(txt); print(f"wrote {a.o}")
    else:
        print(txt)
