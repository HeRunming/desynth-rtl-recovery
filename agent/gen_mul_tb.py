#!/usr/bin/env python3
"""Generate a deterministic PicoRV32 MUL-family equivalence testbench.

The generated testbench supplies a small instruction ROM to two instances
and compares their interfaces and stores.  It deliberately executes MUL,
MULH, MULHSU and MULHU with signed-boundary operands; random mem_rdata is
unlikely to reach these PCPI paths.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int = 0x13) -> int:
    if not -2048 <= imm < 2048:
        raise ValueError(f"I immediate out of range: {imm}")
    return ((imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


def s_type(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    if not 0 <= imm < 4096 or imm & 3:
        raise ValueError(f"S immediate must be an aligned unsigned 12-bit value: {imm}")
    return (((imm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1f) << 7) | 0x23


def jal(imm: int, rd: int = 0) -> int:
    if imm & 1 or not -(1 << 20) <= imm < (1 << 20):
        raise ValueError(f"J immediate out of range: {imm}")
    u = imm & 0x1fffff
    return (((u >> 20) & 1) << 31) | (((u >> 1) & 0x3ff) << 21) | (((u >> 11) & 1) << 20) | (((u >> 12) & 0xff) << 12) | (rd << 7) | 0x6f


CASES = [
    (0, -1, 2), (1, -1, 2), (2, -1, 2), (3, -1, 2),
    (1, -2048, -1), (2, -2048, -1), (3, 2047, 2), (0, 0, -1),
]
SEED = 0


def program() -> list[int]:
    # Values include negative, zero, and positive signed-boundary cases.
    # Each tuple is (operation funct3, rs1 immediate, rs2 immediate).
    out: list[int] = []
    for i, (funct3, a, b) in enumerate(CASES):
        out.extend((i_type(a, 0, 0, 1), i_type(b, 0, 0, 2),
                    r_type(1, 2, 1, funct3, 3), s_type(0x100 + 4 * i, 3, 0, 2)))
    # Stay in a tight loop after all stores so the testbench can observe idle.
    out.append(jal(0))
    return out


def generate(gold: str, dut: str, cycles: int = 1500, tb: str = "tb_mul_directed") -> str:
    words = program()
    lines = ["`timescale 1ns/1ps", f"module {tb};", "  reg clk=0, resetn=0;",
             "  reg mem_ready=1;", "  reg [31:0] irq=0;",
             "  reg g_pcpi_wr=0, g_pcpi_wait=0, g_pcpi_ready=0;",
             "  reg d_pcpi_wr=0, d_pcpi_wait=0, d_pcpi_ready=0;",
             "  reg [31:0] g_pcpi_rd=0, d_pcpi_rd=0;",
             "  wire g_mem_valid, g_mem_instr, d_mem_valid, d_mem_instr;",
             "  wire [31:0] g_mem_addr, d_mem_addr, g_mem_wdata, d_mem_wdata;",
             "  wire [3:0] g_mem_wstrb, d_mem_wstrb;",
             "  wire [31:0] mem_rdata;", ""]
    for pre in ("g", "d"):
        lines.append(f"  wire {pre}_trap, {pre}_mem_la_read, {pre}_mem_la_write, {pre}_pcpi_valid, {pre}_trace_valid;")
        lines.append(f"  wire [31:0] {pre}_mem_la_addr, {pre}_mem_la_wdata, {pre}_pcpi_insn, {pre}_pcpi_rs1, {pre}_pcpi_rs2, {pre}_eoi;")
        lines.append(f"  wire [3:0] {pre}_mem_la_wstrb;")
        lines.append(f"  wire [35:0] {pre}_trace_data;")
    lines.append("")
    for pre, mod in (("g", gold), ("d", dut)):
        lines.append(f"  {mod} {pre} ( .clk(clk), .resetn(resetn), .trap({pre}_trap), .mem_valid({pre}_mem_valid), .mem_instr({pre}_mem_instr), .mem_ready(mem_ready), .mem_addr({pre}_mem_addr), .mem_wdata({pre}_mem_wdata), .mem_wstrb({pre}_mem_wstrb), .mem_rdata(mem_rdata), .mem_la_read({pre}_mem_la_read), .mem_la_write({pre}_mem_la_write), .mem_la_addr({pre}_mem_la_addr), .mem_la_wdata({pre}_mem_la_wdata), .mem_la_wstrb({pre}_mem_la_wstrb), .pcpi_valid({pre}_pcpi_valid), .pcpi_insn({pre}_pcpi_insn), .pcpi_rs1({pre}_pcpi_rs1), .pcpi_rs2({pre}_pcpi_rs2), .pcpi_wr({pre}_pcpi_wr), .pcpi_rd({pre}_pcpi_rd), .pcpi_wait({pre}_pcpi_wait), .pcpi_ready({pre}_pcpi_ready), .irq(irq), .eoi({pre}_eoi), .trace_valid({pre}_trace_valid), .trace_data({pre}_trace_data) );")
    lines += ["", "  always #5 clk = ~clk;", "", "  function [31:0] rom(input [31:0] addr);", "    begin", "      case (addr[31:2])"]
    for i, word in enumerate(words):
        lines.append(f"        30'd{i}: rom = 32'h{word:08x};")
    lines += ["        default: rom = 32'h00000013;", "      endcase", "    end", "  endfunction", "  assign mem_rdata = rom(g_mem_addr);", "", "  integer cyc=0, errors=0, stores=0, dstores=0;", "  integer op_seen [0:3], dop_seen [0:3];", "  integer oi;", "  always @(posedge clk) begin", "    #1;", "    if (resetn) begin", "      cyc = cyc + 1;", "      if (g_mem_valid !== d_mem_valid || g_mem_instr !== d_mem_instr || g_mem_addr !== d_mem_addr || g_mem_wdata !== d_mem_wdata || g_mem_wstrb !== d_mem_wstrb) begin", "        errors = errors + 1;", "        if (errors <= 8) $display(\"IFACE_MISMATCH cyc=%0d g=(%b,%b,%h,%h,%h) d=(%b,%b,%h,%h,%h)\", cyc, g_mem_valid,g_mem_instr,g_mem_addr,g_mem_wdata,g_mem_wstrb,d_mem_valid,d_mem_instr,d_mem_addr,d_mem_wdata,d_mem_wstrb);", "      end", "      if (g_pcpi_valid && g_pcpi_insn[6:0] === 7'b0110011 && g_pcpi_insn[31:25] === 7'b0000001) op_seen[g_pcpi_insn[14:12]] = op_seen[g_pcpi_insn[14:12]] + 1;", "      if (d_pcpi_valid && d_pcpi_insn[6:0] === 7'b0110011 && d_pcpi_insn[31:25] === 7'b0000001) dop_seen[d_pcpi_insn[14:12]] = dop_seen[d_pcpi_insn[14:12]] + 1;", "      if (g_mem_valid && !g_mem_instr && g_mem_wstrb != 0) begin", "        stores = stores + 1;", "        $display(\"MUL_STORE cyc=%0d addr=%h gold=%h dut=%h wstrb=%h\", cyc, g_mem_addr, g_mem_wdata, d_mem_wdata, g_mem_wstrb);", "        if (g_mem_addr !== d_mem_addr || g_mem_wdata !== d_mem_wdata || g_mem_wstrb !== d_mem_wstrb) errors = errors + 1;", "      end", "      if (d_mem_valid && !d_mem_instr && d_mem_wstrb != 0) dstores = dstores + 1;", "    end", "  end", "  initial begin", "    for (oi=0; oi<4; oi=oi+1) begin op_seen[oi]=0; dop_seen[oi]=0; end", "    repeat (5) @(posedge clk);", "    @(negedge clk); resetn = 1;", f"    repeat ({cycles}) @(posedge clk);", f"    $display(\"MUL_DIRECTED seed=%0d errors=%0d stores_gold=%0d stores_dut=%0d cycles=%0d\", {SEED}, errors, stores, dstores, cyc);", "    for (oi=0; oi<4; oi=oi+1) $display(\"MUL_OPCODE funct3=%0d gold_pcpi_valid_cycles=%0d dut_pcpi_valid_cycles=%0d\", oi, op_seen[oi], dop_seen[oi]);", "    $finish;", "  end", "endmodule"]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("gold")
    ap.add_argument("dut")
    ap.add_argument("-o", required=True)
    ap.add_argument("--cycles", type=int, default=1500)
    ap.add_argument("--tb", default="tb_mul_directed")
    ap.add_argument("--manifest", default=None, help="write JSON with seed, cases and instruction words")
    a = ap.parse_args()
    Path(a.o).write_text(generate(a.gold, a.dut, a.cycles, a.tb))
    if a.manifest:
        Path(a.manifest).write_text(json.dumps({"seed": SEED, "cases": [list(x) for x in CASES], "instruction_words": [f"0x{x:08x}" for x in program()], "cycles": a.cycles}, indent=2) + "\n")
    print(f"wrote {a.o} ({len(program())} instruction words)")
