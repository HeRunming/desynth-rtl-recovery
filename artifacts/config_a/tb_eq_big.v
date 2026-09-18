`timescale 1ns/1ps
module tb_eq_big;
  reg clk=0;
  reg resetn=0;
  reg mem_ready=0;
  reg [31:0] mem_rdata=0;
  reg pcpi_wr=0;
  reg [31:0] pcpi_rd=0;
  reg pcpi_wait=0;
  reg pcpi_ready=0;
  reg [31:0] irq=0;
  wire g_trap;
  wire g_mem_valid;
  wire g_mem_instr;
  wire [31:0] g_mem_addr;
  wire [31:0] g_mem_wdata;
  wire [3:0] g_mem_wstrb;
  wire g_mem_la_read;
  wire g_mem_la_write;
  wire [31:0] g_mem_la_addr;
  wire [31:0] g_mem_la_wdata;
  wire [3:0] g_mem_la_wstrb;
  wire g_pcpi_valid;
  wire [31:0] g_pcpi_insn;
  wire [31:0] g_pcpi_rs1;
  wire [31:0] g_pcpi_rs2;
  wire [31:0] g_eoi;
  wire g_trace_valid;
  wire [35:0] g_trace_data;
  wire d_trap;
  wire d_mem_valid;
  wire d_mem_instr;
  wire [31:0] d_mem_addr;
  wire [31:0] d_mem_wdata;
  wire [3:0] d_mem_wstrb;
  wire d_mem_la_read;
  wire d_mem_la_write;
  wire [31:0] d_mem_la_addr;
  wire [31:0] d_mem_la_wdata;
  wire [3:0] d_mem_la_wstrb;
  wire d_pcpi_valid;
  wire [31:0] d_pcpi_insn;
  wire [31:0] d_pcpi_rs1;
  wire [31:0] d_pcpi_rs2;
  wire [31:0] d_eoi;
  wire d_trace_valid;
  wire [35:0] d_trace_data;

  picorv32 gold(
    .clk(clk),
    .resetn(resetn),
    .mem_ready(mem_ready),
    .mem_rdata(mem_rdata),
    .pcpi_wr(pcpi_wr),
    .pcpi_rd(pcpi_rd),
    .pcpi_wait(pcpi_wait),
    .pcpi_ready(pcpi_ready),
    .irq(irq),
    .trap(g_trap),
    .mem_valid(g_mem_valid),
    .mem_instr(g_mem_instr),
    .mem_addr(g_mem_addr),
    .mem_wdata(g_mem_wdata),
    .mem_wstrb(g_mem_wstrb),
    .mem_la_read(g_mem_la_read),
    .mem_la_write(g_mem_la_write),
    .mem_la_addr(g_mem_la_addr),
    .mem_la_wdata(g_mem_la_wdata),
    .mem_la_wstrb(g_mem_la_wstrb),
    .pcpi_valid(g_pcpi_valid),
    .pcpi_insn(g_pcpi_insn),
    .pcpi_rs1(g_pcpi_rs1),
    .pcpi_rs2(g_pcpi_rs2),
    .eoi(g_eoi),
    .trace_valid(g_trace_valid),
    .trace_data(g_trace_data));
  picorv32_lift dut(
    .clk(clk),
    .resetn(resetn),
    .mem_ready(mem_ready),
    .mem_rdata(mem_rdata),
    .pcpi_wr(pcpi_wr),
    .pcpi_rd(pcpi_rd),
    .pcpi_wait(pcpi_wait),
    .pcpi_ready(pcpi_ready),
    .irq(irq),
    .trap(d_trap),
    .mem_valid(d_mem_valid),
    .mem_instr(d_mem_instr),
    .mem_addr(d_mem_addr),
    .mem_wdata(d_mem_wdata),
    .mem_wstrb(d_mem_wstrb),
    .mem_la_read(d_mem_la_read),
    .mem_la_write(d_mem_la_write),
    .mem_la_addr(d_mem_la_addr),
    .mem_la_wdata(d_mem_la_wdata),
    .mem_la_wstrb(d_mem_la_wstrb),
    .pcpi_valid(d_pcpi_valid),
    .pcpi_insn(d_pcpi_insn),
    .pcpi_rs1(d_pcpi_rs1),
    .pcpi_rs2(d_pcpi_rs2),
    .eoi(d_eoi),
    .trace_valid(d_trace_valid),
    .trace_data(d_trace_data));

  always #5 clk = ~clk;

  integer i, errors=0, checks=0, xskip=0, bi;
  reg shown=0;
  integer sig_err [0:17];   // 每个输出端口的错误计数
  integer sig_first [0:17];  // 首次失配周期
  integer k;

  reg [35:0] mask;
  task chk(input integer idx, input [255:0] nm, input [35:0] a, input [35:0] b);
    begin
      // gold 侧含 X 的位视为 don't-care: 逐位用 === 判定
      for (bi = 0; bi < 36; bi = bi + 1)
        mask[bi] = !((a[bi] === 1'bx) || (a[bi] === 1'bz));
      if (mask === 0) begin
        xskip = xskip + 1;
      end else begin
      checks = checks + 1;
      if ((a & mask) !== (b & mask)) begin
        errors = errors + 1;
        sig_err[idx] = sig_err[idx] + 1;
        if (sig_first[idx] < 0) sig_first[idx] = i;
        if (!shown) begin
          $display("FIRST MISMATCH cyc%0d %0s: gold=%h dut=%h mask=%h",
                   i, nm, a, b, mask);
          shown = 1;
        end
      end
      end
    end
  endtask

  initial begin
    for (k = 0; k < 18; k = k + 1) begin
      sig_err[k] = 0; sig_first[k] = -1;
    end
    repeat(5) @(posedge clk);
    #1 resetn = 1;
    for (i = 0; i < 50000; i = i + 1) begin
      @(negedge clk);
      mem_ready = $random;
      mem_rdata = $random;
      pcpi_wr = $random;
      pcpi_rd = $random;
      pcpi_wait = $random;
      pcpi_ready = $random;
      irq = $random;
      @(posedge clk); #2;
      if (i >= 10) begin  // 跳过复位传播周期
        chk(0, "trap", {35'b0, g_trap}, {35'b0, d_trap});
        chk(1, "mem_valid", {35'b0, g_mem_valid}, {35'b0, d_mem_valid});
        chk(2, "mem_instr", {35'b0, g_mem_instr}, {35'b0, d_mem_instr});
        chk(3, "mem_addr", {4'b0, g_mem_addr}, {4'b0, d_mem_addr});
        chk(4, "mem_wdata", {4'b0, g_mem_wdata}, {4'b0, d_mem_wdata});
        chk(5, "mem_wstrb", {32'b0, g_mem_wstrb}, {32'b0, d_mem_wstrb});
        chk(6, "mem_la_read", {35'b0, g_mem_la_read}, {35'b0, d_mem_la_read});
        chk(7, "mem_la_write", {35'b0, g_mem_la_write}, {35'b0, d_mem_la_write});
        chk(8, "mem_la_addr", {4'b0, g_mem_la_addr}, {4'b0, d_mem_la_addr});
        chk(9, "mem_la_wdata", {4'b0, g_mem_la_wdata}, {4'b0, d_mem_la_wdata});
        chk(10, "mem_la_wstrb", {32'b0, g_mem_la_wstrb}, {32'b0, d_mem_la_wstrb});
        chk(11, "pcpi_valid", {35'b0, g_pcpi_valid}, {35'b0, d_pcpi_valid});
        chk(12, "pcpi_insn", {4'b0, g_pcpi_insn}, {4'b0, d_pcpi_insn});
        chk(13, "pcpi_rs1", {4'b0, g_pcpi_rs1}, {4'b0, d_pcpi_rs1});
        chk(14, "pcpi_rs2", {4'b0, g_pcpi_rs2}, {4'b0, d_pcpi_rs2});
        chk(15, "eoi", {4'b0, g_eoi}, {4'b0, d_eoi});
        chk(16, "trace_valid", {35'b0, g_trace_valid}, {35'b0, d_trace_valid});
        chk(17, "trace_data", g_trace_data, d_trace_data);
      end
    end
    $display("EQUIV picorv32_lift: %0d mismatches / %0d checks (%0d cycles, %0d all-X checks skipped)",
             errors, checks, i, xskip);
    $display("---- per-signal breakdown ----");
    if (sig_err[0]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "trap", sig_err[0], sig_first[0]);
    else $display("  ok   %-14s", "trap");
    if (sig_err[1]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_valid", sig_err[1], sig_first[1]);
    else $display("  ok   %-14s", "mem_valid");
    if (sig_err[2]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_instr", sig_err[2], sig_first[2]);
    else $display("  ok   %-14s", "mem_instr");
    if (sig_err[3]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_addr", sig_err[3], sig_first[3]);
    else $display("  ok   %-14s", "mem_addr");
    if (sig_err[4]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_wdata", sig_err[4], sig_first[4]);
    else $display("  ok   %-14s", "mem_wdata");
    if (sig_err[5]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_wstrb", sig_err[5], sig_first[5]);
    else $display("  ok   %-14s", "mem_wstrb");
    if (sig_err[6]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_la_read", sig_err[6], sig_first[6]);
    else $display("  ok   %-14s", "mem_la_read");
    if (sig_err[7]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_la_write", sig_err[7], sig_first[7]);
    else $display("  ok   %-14s", "mem_la_write");
    if (sig_err[8]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_la_addr", sig_err[8], sig_first[8]);
    else $display("  ok   %-14s", "mem_la_addr");
    if (sig_err[9]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_la_wdata", sig_err[9], sig_first[9]);
    else $display("  ok   %-14s", "mem_la_wdata");
    if (sig_err[10]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "mem_la_wstrb", sig_err[10], sig_first[10]);
    else $display("  ok   %-14s", "mem_la_wstrb");
    if (sig_err[11]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "pcpi_valid", sig_err[11], sig_first[11]);
    else $display("  ok   %-14s", "pcpi_valid");
    if (sig_err[12]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "pcpi_insn", sig_err[12], sig_first[12]);
    else $display("  ok   %-14s", "pcpi_insn");
    if (sig_err[13]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "pcpi_rs1", sig_err[13], sig_first[13]);
    else $display("  ok   %-14s", "pcpi_rs1");
    if (sig_err[14]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "pcpi_rs2", sig_err[14], sig_first[14]);
    else $display("  ok   %-14s", "pcpi_rs2");
    if (sig_err[15]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "eoi", sig_err[15], sig_first[15]);
    else $display("  ok   %-14s", "eoi");
    if (sig_err[16]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "trace_valid", sig_err[16], sig_first[16]);
    else $display("  ok   %-14s", "trace_valid");
    if (sig_err[17]) $display("  BAD  %-14s errs=%0d first_cyc=%0d", "trace_data", sig_err[17], sig_first[17]);
    else $display("  ok   %-14s", "trace_data");
    $finish;
  end
endmodule