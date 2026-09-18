`timescale 1ns/1ps
module tb_source_internal;
integer ff_errors=0, ff_checks=0;
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
    for (i = 0; i < 3000; i = i + 1) begin
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
    $display("SOURCE_INTERNAL bits=2313 cycles=3000 errors=%0d checks=%0d", ff_errors, ff_checks);
    if (ff_errors != 0 || ff_checks < 2313*3000) $fatal(1,"internal mismatch or incomplete run");
    $finish;
  end
always @(posedge clk) begin
#1;
if (resetn) begin
ff_checks=ff_checks+1;
if (gold._49806_.Q !== dut.status_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=414 gold=%b dut=%b", gold._49806_.Q, dut.status_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50167_.Q !== dut.control_word_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=621 gold=%b dut=%b", gold._50167_.Q, dut.control_word_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50168_.Q !== dut.control_word_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=622 gold=%b dut=%b", gold._50168_.Q, dut.control_word_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50169_.Q !== dut.control_word_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=623 gold=%b dut=%b", gold._50169_.Q, dut.control_word_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50170_.Q !== dut.control_word_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=624 gold=%b dut=%b", gold._50170_.Q, dut.control_word_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50171_.Q !== dut.control_word_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=625 gold=%b dut=%b", gold._50171_.Q, dut.control_word_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50172_.Q !== dut.control_word_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=626 gold=%b dut=%b", gold._50172_.Q, dut.control_word_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50173_.Q !== dut.control_word_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=627 gold=%b dut=%b", gold._50173_.Q, dut.control_word_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50174_.Q !== dut.control_word_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=628 gold=%b dut=%b", gold._50174_.Q, dut.control_word_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50175_.Q !== dut.control_word_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=629 gold=%b dut=%b", gold._50175_.Q, dut.control_word_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50176_.Q !== dut.control_word_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=630 gold=%b dut=%b", gold._50176_.Q, dut.control_word_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50177_.Q !== dut.control_word_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=631 gold=%b dut=%b", gold._50177_.Q, dut.control_word_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50178_.Q !== dut.control_word_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=632 gold=%b dut=%b", gold._50178_.Q, dut.control_word_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50179_.Q !== dut.control_word_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=633 gold=%b dut=%b", gold._50179_.Q, dut.control_word_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50180_.Q !== dut.control_word_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=634 gold=%b dut=%b", gold._50180_.Q, dut.control_word_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50181_.Q !== dut.control_word_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=635 gold=%b dut=%b", gold._50181_.Q, dut.control_word_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50182_.Q !== dut.control_word_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=636 gold=%b dut=%b", gold._50182_.Q, dut.control_word_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50183_.Q !== dut.control_word_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=637 gold=%b dut=%b", gold._50183_.Q, dut.control_word_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50184_.Q !== dut.control_word_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=638 gold=%b dut=%b", gold._50184_.Q, dut.control_word_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50185_.Q !== dut.control_word_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=639 gold=%b dut=%b", gold._50185_.Q, dut.control_word_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50186_.Q !== dut.control_word_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=640 gold=%b dut=%b", gold._50186_.Q, dut.control_word_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50187_.Q !== dut.control_word_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=641 gold=%b dut=%b", gold._50187_.Q, dut.control_word_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50188_.Q !== dut.control_word_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=642 gold=%b dut=%b", gold._50188_.Q, dut.control_word_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50189_.Q !== dut.control_word_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=643 gold=%b dut=%b", gold._50189_.Q, dut.control_word_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50190_.Q !== dut.control_word_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=644 gold=%b dut=%b", gold._50190_.Q, dut.control_word_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50191_.Q !== dut.control_word_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=645 gold=%b dut=%b", gold._50191_.Q, dut.control_word_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50192_.Q !== dut.control_word_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=646 gold=%b dut=%b", gold._50192_.Q, dut.control_word_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50193_.Q !== dut.control_word_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=647 gold=%b dut=%b", gold._50193_.Q, dut.control_word_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50194_.Q !== dut.control_word_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=648 gold=%b dut=%b", gold._50194_.Q, dut.control_word_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50195_.Q !== dut.control_word_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=649 gold=%b dut=%b", gold._50195_.Q, dut.control_word_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50196_.Q !== dut.control_word_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=650 gold=%b dut=%b", gold._50196_.Q, dut.control_word_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50197_.Q !== dut.control_word_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=651 gold=%b dut=%b", gold._50197_.Q, dut.control_word_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50166_.Q !== dut.status_flag_1) begin
if(ff_errors<8) $display("FF_MISMATCH qid=652 gold=%b dut=%b", gold._50166_.Q, dut.status_flag_1);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50129_.Q !== dut.small_selected_data_word[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=653 gold=%b dut=%b", gold._50129_.Q, dut.small_selected_data_word[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50130_.Q !== dut.small_selected_data_word[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=654 gold=%b dut=%b", gold._50130_.Q, dut.small_selected_data_word[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50131_.Q !== dut.small_selected_data_word[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=655 gold=%b dut=%b", gold._50131_.Q, dut.small_selected_data_word[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50132_.Q !== dut.small_selected_data_word[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=656 gold=%b dut=%b", gold._50132_.Q, dut.small_selected_data_word[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50133_.Q !== dut.small_selected_data_word[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=657 gold=%b dut=%b", gold._50133_.Q, dut.small_selected_data_word[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50134_.Q !== dut.small_selected_data_word[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=658 gold=%b dut=%b", gold._50134_.Q, dut.small_selected_data_word[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50135_.Q !== dut.small_selected_data_word[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=659 gold=%b dut=%b", gold._50135_.Q, dut.small_selected_data_word[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50136_.Q !== dut.small_selected_data_word[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=660 gold=%b dut=%b", gold._50136_.Q, dut.small_selected_data_word[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50137_.Q !== dut.small_selected_data_word[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=661 gold=%b dut=%b", gold._50137_.Q, dut.small_selected_data_word[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50138_.Q !== dut.small_selected_data_word[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=662 gold=%b dut=%b", gold._50138_.Q, dut.small_selected_data_word[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50139_.Q !== dut.small_selected_data_word[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=663 gold=%b dut=%b", gold._50139_.Q, dut.small_selected_data_word[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50140_.Q !== dut.small_selected_data_word[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=664 gold=%b dut=%b", gold._50140_.Q, dut.small_selected_data_word[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50141_.Q !== dut.small_selected_data_word[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=665 gold=%b dut=%b", gold._50141_.Q, dut.small_selected_data_word[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50142_.Q !== dut.small_selected_data_word[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=666 gold=%b dut=%b", gold._50142_.Q, dut.small_selected_data_word[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50143_.Q !== dut.small_selected_data_word[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=667 gold=%b dut=%b", gold._50143_.Q, dut.small_selected_data_word[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50144_.Q !== dut.small_selected_data_word[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=668 gold=%b dut=%b", gold._50144_.Q, dut.small_selected_data_word[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50145_.Q !== dut.small_selected_data_word[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=669 gold=%b dut=%b", gold._50145_.Q, dut.small_selected_data_word[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50146_.Q !== dut.small_selected_data_word[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=670 gold=%b dut=%b", gold._50146_.Q, dut.small_selected_data_word[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50147_.Q !== dut.small_selected_data_word[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=671 gold=%b dut=%b", gold._50147_.Q, dut.small_selected_data_word[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50148_.Q !== dut.small_selected_data_word[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=672 gold=%b dut=%b", gold._50148_.Q, dut.small_selected_data_word[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50149_.Q !== dut.small_selected_data_word[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=673 gold=%b dut=%b", gold._50149_.Q, dut.small_selected_data_word[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50150_.Q !== dut.small_selected_data_word[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=674 gold=%b dut=%b", gold._50150_.Q, dut.small_selected_data_word[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50151_.Q !== dut.small_selected_data_word[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=675 gold=%b dut=%b", gold._50151_.Q, dut.small_selected_data_word[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50152_.Q !== dut.small_selected_data_word[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=676 gold=%b dut=%b", gold._50152_.Q, dut.small_selected_data_word[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50153_.Q !== dut.small_selected_data_word[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=677 gold=%b dut=%b", gold._50153_.Q, dut.small_selected_data_word[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50154_.Q !== dut.small_selected_data_word[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=678 gold=%b dut=%b", gold._50154_.Q, dut.small_selected_data_word[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50155_.Q !== dut.small_selected_data_word[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=679 gold=%b dut=%b", gold._50155_.Q, dut.small_selected_data_word[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50156_.Q !== dut.small_selected_data_word[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=680 gold=%b dut=%b", gold._50156_.Q, dut.small_selected_data_word[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50157_.Q !== dut.small_selected_data_word[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=681 gold=%b dut=%b", gold._50157_.Q, dut.small_selected_data_word[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50158_.Q !== dut.small_selected_data_word[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=682 gold=%b dut=%b", gold._50158_.Q, dut.small_selected_data_word[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50159_.Q !== dut.small_selected_data_word[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=683 gold=%b dut=%b", gold._50159_.Q, dut.small_selected_data_word[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50160_.Q !== dut.small_selected_data_word[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=684 gold=%b dut=%b", gold._50160_.Q, dut.small_selected_data_word[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50424_.Q !== dut.data_word[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=752 gold=%b dut=%b", gold._50424_.Q, dut.data_word[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50425_.Q !== dut.data_word[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=753 gold=%b dut=%b", gold._50425_.Q, dut.data_word[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50426_.Q !== dut.data_word[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=754 gold=%b dut=%b", gold._50426_.Q, dut.data_word[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50427_.Q !== dut.data_word[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=755 gold=%b dut=%b", gold._50427_.Q, dut.data_word[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50428_.Q !== dut.data_word[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=756 gold=%b dut=%b", gold._50428_.Q, dut.data_word[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50429_.Q !== dut.data_word[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=757 gold=%b dut=%b", gold._50429_.Q, dut.data_word[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50430_.Q !== dut.data_word[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=758 gold=%b dut=%b", gold._50430_.Q, dut.data_word[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50431_.Q !== dut.data_word[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=759 gold=%b dut=%b", gold._50431_.Q, dut.data_word[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50432_.Q !== dut.data_word[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=760 gold=%b dut=%b", gold._50432_.Q, dut.data_word[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50433_.Q !== dut.data_word[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=761 gold=%b dut=%b", gold._50433_.Q, dut.data_word[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50434_.Q !== dut.data_word[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=762 gold=%b dut=%b", gold._50434_.Q, dut.data_word[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50435_.Q !== dut.data_word[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=763 gold=%b dut=%b", gold._50435_.Q, dut.data_word[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50436_.Q !== dut.data_word[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=764 gold=%b dut=%b", gold._50436_.Q, dut.data_word[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50437_.Q !== dut.data_word[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=765 gold=%b dut=%b", gold._50437_.Q, dut.data_word[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50438_.Q !== dut.data_word[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=766 gold=%b dut=%b", gold._50438_.Q, dut.data_word[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50439_.Q !== dut.data_word[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=767 gold=%b dut=%b", gold._50439_.Q, dut.data_word[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50440_.Q !== dut.data_word[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=768 gold=%b dut=%b", gold._50440_.Q, dut.data_word[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50441_.Q !== dut.data_word[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=769 gold=%b dut=%b", gold._50441_.Q, dut.data_word[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50442_.Q !== dut.data_word[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=770 gold=%b dut=%b", gold._50442_.Q, dut.data_word[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50443_.Q !== dut.data_word[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=771 gold=%b dut=%b", gold._50443_.Q, dut.data_word[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50444_.Q !== dut.data_word[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=772 gold=%b dut=%b", gold._50444_.Q, dut.data_word[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50445_.Q !== dut.data_word[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=773 gold=%b dut=%b", gold._50445_.Q, dut.data_word[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50446_.Q !== dut.data_word[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=774 gold=%b dut=%b", gold._50446_.Q, dut.data_word[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50447_.Q !== dut.data_word[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=775 gold=%b dut=%b", gold._50447_.Q, dut.data_word[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50448_.Q !== dut.data_word[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=776 gold=%b dut=%b", gold._50448_.Q, dut.data_word[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50449_.Q !== dut.data_word[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=777 gold=%b dut=%b", gold._50449_.Q, dut.data_word[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50450_.Q !== dut.data_word[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=778 gold=%b dut=%b", gold._50450_.Q, dut.data_word[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50451_.Q !== dut.data_word[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=779 gold=%b dut=%b", gold._50451_.Q, dut.data_word[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50452_.Q !== dut.data_word[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=780 gold=%b dut=%b", gold._50452_.Q, dut.data_word[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50453_.Q !== dut.data_word[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=781 gold=%b dut=%b", gold._50453_.Q, dut.data_word[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50454_.Q !== dut.data_word[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=782 gold=%b dut=%b", gold._50454_.Q, dut.data_word[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50455_.Q !== dut.data_word[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=783 gold=%b dut=%b", gold._50455_.Q, dut.data_word[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49296_.Q !== dut.status_flag_2) begin
if(ff_errors<8) $display("FF_MISMATCH qid=784 gold=%b dut=%b", gold._49296_.Q, dut.status_flag_2);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50388_.Q !== dut.write_data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=785 gold=%b dut=%b", gold._50388_.Q, dut.write_data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50389_.Q !== dut.write_data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=786 gold=%b dut=%b", gold._50389_.Q, dut.write_data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50390_.Q !== dut.write_data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=787 gold=%b dut=%b", gold._50390_.Q, dut.write_data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50391_.Q !== dut.write_data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=788 gold=%b dut=%b", gold._50391_.Q, dut.write_data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50392_.Q !== dut.write_data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=789 gold=%b dut=%b", gold._50392_.Q, dut.write_data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50393_.Q !== dut.write_data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=790 gold=%b dut=%b", gold._50393_.Q, dut.write_data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50394_.Q !== dut.write_data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=791 gold=%b dut=%b", gold._50394_.Q, dut.write_data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50395_.Q !== dut.write_data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=792 gold=%b dut=%b", gold._50395_.Q, dut.write_data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50396_.Q !== dut.write_data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=793 gold=%b dut=%b", gold._50396_.Q, dut.write_data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50397_.Q !== dut.write_data_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=794 gold=%b dut=%b", gold._50397_.Q, dut.write_data_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50398_.Q !== dut.write_data_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=795 gold=%b dut=%b", gold._50398_.Q, dut.write_data_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50399_.Q !== dut.write_data_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=796 gold=%b dut=%b", gold._50399_.Q, dut.write_data_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50400_.Q !== dut.write_data_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=797 gold=%b dut=%b", gold._50400_.Q, dut.write_data_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50401_.Q !== dut.write_data_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=798 gold=%b dut=%b", gold._50401_.Q, dut.write_data_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50402_.Q !== dut.write_data_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=799 gold=%b dut=%b", gold._50402_.Q, dut.write_data_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50403_.Q !== dut.write_data_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=800 gold=%b dut=%b", gold._50403_.Q, dut.write_data_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50404_.Q !== dut.write_data_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=801 gold=%b dut=%b", gold._50404_.Q, dut.write_data_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50405_.Q !== dut.write_data_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=802 gold=%b dut=%b", gold._50405_.Q, dut.write_data_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50406_.Q !== dut.write_data_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=803 gold=%b dut=%b", gold._50406_.Q, dut.write_data_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50407_.Q !== dut.write_data_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=804 gold=%b dut=%b", gold._50407_.Q, dut.write_data_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50408_.Q !== dut.write_data_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=805 gold=%b dut=%b", gold._50408_.Q, dut.write_data_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50409_.Q !== dut.write_data_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=806 gold=%b dut=%b", gold._50409_.Q, dut.write_data_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50410_.Q !== dut.write_data_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=807 gold=%b dut=%b", gold._50410_.Q, dut.write_data_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50411_.Q !== dut.write_data_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=808 gold=%b dut=%b", gold._50411_.Q, dut.write_data_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50412_.Q !== dut.write_data_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=809 gold=%b dut=%b", gold._50412_.Q, dut.write_data_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50413_.Q !== dut.write_data_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=810 gold=%b dut=%b", gold._50413_.Q, dut.write_data_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50414_.Q !== dut.write_data_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=811 gold=%b dut=%b", gold._50414_.Q, dut.write_data_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50415_.Q !== dut.write_data_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=812 gold=%b dut=%b", gold._50415_.Q, dut.write_data_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50416_.Q !== dut.write_data_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=813 gold=%b dut=%b", gold._50416_.Q, dut.write_data_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50417_.Q !== dut.write_data_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=814 gold=%b dut=%b", gold._50417_.Q, dut.write_data_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50418_.Q !== dut.write_data_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=815 gold=%b dut=%b", gold._50418_.Q, dut.write_data_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50419_.Q !== dut.write_data_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=816 gold=%b dut=%b", gold._50419_.Q, dut.write_data_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50420_.Q !== dut.write_data_register[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=817 gold=%b dut=%b", gold._50420_.Q, dut.write_data_register[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50421_.Q !== dut.write_data_register[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=818 gold=%b dut=%b", gold._50421_.Q, dut.write_data_register[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50422_.Q !== dut.transfer_status[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=819 gold=%b dut=%b", gold._50422_.Q, dut.transfer_status[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50423_.Q !== dut.transfer_status[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=820 gold=%b dut=%b", gold._50423_.Q, dut.transfer_status[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48417_.Q !== dut.control_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=935 gold=%b dut=%b", gold._48417_.Q, dut.control_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48418_.Q !== dut.control_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=936 gold=%b dut=%b", gold._48418_.Q, dut.control_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48419_.Q !== dut.control_state[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=937 gold=%b dut=%b", gold._48419_.Q, dut.control_state[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48420_.Q !== dut.control_state[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=938 gold=%b dut=%b", gold._48420_.Q, dut.control_state[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48421_.Q !== dut.control_state[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=939 gold=%b dut=%b", gold._48421_.Q, dut.control_state[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48262_.Q !== dut.control_state[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=940 gold=%b dut=%b", gold._48262_.Q, dut.control_state[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48263_.Q !== dut.control_state[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=941 gold=%b dut=%b", gold._48263_.Q, dut.control_state[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48264_.Q !== dut.control_state[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=942 gold=%b dut=%b", gold._48264_.Q, dut.control_state[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48265_.Q !== dut.control_state[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=943 gold=%b dut=%b", gold._48265_.Q, dut.control_state[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48266_.Q !== dut.control_state[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=944 gold=%b dut=%b", gold._48266_.Q, dut.control_state[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48267_.Q !== dut.control_state[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=945 gold=%b dut=%b", gold._48267_.Q, dut.control_state[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48351_.Q !== dut.alu_result_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25421 gold=%b dut=%b", gold._48351_.Q, dut.alu_result_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48352_.Q !== dut.alu_result_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25422 gold=%b dut=%b", gold._48352_.Q, dut.alu_result_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48353_.Q !== dut.alu_result_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25423 gold=%b dut=%b", gold._48353_.Q, dut.alu_result_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48354_.Q !== dut.alu_result_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25424 gold=%b dut=%b", gold._48354_.Q, dut.alu_result_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48355_.Q !== dut.alu_result_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25425 gold=%b dut=%b", gold._48355_.Q, dut.alu_result_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48356_.Q !== dut.alu_result_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25426 gold=%b dut=%b", gold._48356_.Q, dut.alu_result_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48357_.Q !== dut.alu_result_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25427 gold=%b dut=%b", gold._48357_.Q, dut.alu_result_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48358_.Q !== dut.alu_result_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25428 gold=%b dut=%b", gold._48358_.Q, dut.alu_result_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48359_.Q !== dut.alu_result_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25429 gold=%b dut=%b", gold._48359_.Q, dut.alu_result_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48360_.Q !== dut.alu_result_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25430 gold=%b dut=%b", gold._48360_.Q, dut.alu_result_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48361_.Q !== dut.alu_result_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25431 gold=%b dut=%b", gold._48361_.Q, dut.alu_result_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48362_.Q !== dut.alu_result_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25432 gold=%b dut=%b", gold._48362_.Q, dut.alu_result_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48363_.Q !== dut.alu_result_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25433 gold=%b dut=%b", gold._48363_.Q, dut.alu_result_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48364_.Q !== dut.alu_result_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25434 gold=%b dut=%b", gold._48364_.Q, dut.alu_result_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48365_.Q !== dut.alu_result_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25435 gold=%b dut=%b", gold._48365_.Q, dut.alu_result_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48366_.Q !== dut.alu_result_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25436 gold=%b dut=%b", gold._48366_.Q, dut.alu_result_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48367_.Q !== dut.alu_result_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25437 gold=%b dut=%b", gold._48367_.Q, dut.alu_result_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48368_.Q !== dut.alu_result_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25438 gold=%b dut=%b", gold._48368_.Q, dut.alu_result_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48369_.Q !== dut.alu_result_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25439 gold=%b dut=%b", gold._48369_.Q, dut.alu_result_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48370_.Q !== dut.alu_result_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25440 gold=%b dut=%b", gold._48370_.Q, dut.alu_result_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48371_.Q !== dut.alu_result_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25441 gold=%b dut=%b", gold._48371_.Q, dut.alu_result_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48372_.Q !== dut.alu_result_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25442 gold=%b dut=%b", gold._48372_.Q, dut.alu_result_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48373_.Q !== dut.alu_result_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25443 gold=%b dut=%b", gold._48373_.Q, dut.alu_result_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48374_.Q !== dut.alu_result_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25444 gold=%b dut=%b", gold._48374_.Q, dut.alu_result_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48375_.Q !== dut.alu_result_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25445 gold=%b dut=%b", gold._48375_.Q, dut.alu_result_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48376_.Q !== dut.alu_result_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25446 gold=%b dut=%b", gold._48376_.Q, dut.alu_result_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48377_.Q !== dut.alu_result_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25447 gold=%b dut=%b", gold._48377_.Q, dut.alu_result_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48378_.Q !== dut.alu_result_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25448 gold=%b dut=%b", gold._48378_.Q, dut.alu_result_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48379_.Q !== dut.alu_result_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25449 gold=%b dut=%b", gold._48379_.Q, dut.alu_result_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48380_.Q !== dut.alu_result_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25450 gold=%b dut=%b", gold._48380_.Q, dut.alu_result_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48381_.Q !== dut.alu_result_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25451 gold=%b dut=%b", gold._48381_.Q, dut.alu_result_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48382_.Q !== dut.control_flag_25452) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25452 gold=%b dut=%b", gold._48382_.Q, dut.control_flag_25452);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48272_.Q !== dut.sticky_hold_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25454 gold=%b dut=%b", gold._48272_.Q, dut.sticky_hold_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50466_.Q !== dut.datapath_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25455 gold=%b dut=%b", gold._50466_.Q, dut.datapath_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50324_.Q !== dut.enabled_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25456 gold=%b dut=%b", gold._50324_.Q, dut.enabled_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50325_.Q !== dut.enabled_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25457 gold=%b dut=%b", gold._50325_.Q, dut.enabled_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50326_.Q !== dut.enabled_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25458 gold=%b dut=%b", gold._50326_.Q, dut.enabled_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50327_.Q !== dut.enabled_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25459 gold=%b dut=%b", gold._50327_.Q, dut.enabled_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50328_.Q !== dut.enabled_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25460 gold=%b dut=%b", gold._50328_.Q, dut.enabled_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50329_.Q !== dut.enabled_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25461 gold=%b dut=%b", gold._50329_.Q, dut.enabled_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50330_.Q !== dut.enabled_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25462 gold=%b dut=%b", gold._50330_.Q, dut.enabled_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50331_.Q !== dut.enabled_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25463 gold=%b dut=%b", gold._50331_.Q, dut.enabled_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50332_.Q !== dut.enabled_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25464 gold=%b dut=%b", gold._50332_.Q, dut.enabled_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50333_.Q !== dut.enabled_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25465 gold=%b dut=%b", gold._50333_.Q, dut.enabled_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50334_.Q !== dut.enabled_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25466 gold=%b dut=%b", gold._50334_.Q, dut.enabled_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50335_.Q !== dut.enabled_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25467 gold=%b dut=%b", gold._50335_.Q, dut.enabled_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50336_.Q !== dut.enabled_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25468 gold=%b dut=%b", gold._50336_.Q, dut.enabled_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50337_.Q !== dut.enabled_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25469 gold=%b dut=%b", gold._50337_.Q, dut.enabled_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50338_.Q !== dut.enabled_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25470 gold=%b dut=%b", gold._50338_.Q, dut.enabled_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50339_.Q !== dut.enabled_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25471 gold=%b dut=%b", gold._50339_.Q, dut.enabled_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50340_.Q !== dut.enabled_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25472 gold=%b dut=%b", gold._50340_.Q, dut.enabled_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50341_.Q !== dut.enabled_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25473 gold=%b dut=%b", gold._50341_.Q, dut.enabled_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50342_.Q !== dut.enabled_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25474 gold=%b dut=%b", gold._50342_.Q, dut.enabled_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50343_.Q !== dut.enabled_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25475 gold=%b dut=%b", gold._50343_.Q, dut.enabled_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50344_.Q !== dut.enabled_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25476 gold=%b dut=%b", gold._50344_.Q, dut.enabled_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50345_.Q !== dut.enabled_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25477 gold=%b dut=%b", gold._50345_.Q, dut.enabled_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50346_.Q !== dut.enabled_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25478 gold=%b dut=%b", gold._50346_.Q, dut.enabled_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50347_.Q !== dut.enabled_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25479 gold=%b dut=%b", gold._50347_.Q, dut.enabled_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50348_.Q !== dut.enabled_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25480 gold=%b dut=%b", gold._50348_.Q, dut.enabled_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50349_.Q !== dut.enabled_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25481 gold=%b dut=%b", gold._50349_.Q, dut.enabled_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50350_.Q !== dut.enabled_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25482 gold=%b dut=%b", gold._50350_.Q, dut.enabled_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50351_.Q !== dut.enabled_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25483 gold=%b dut=%b", gold._50351_.Q, dut.enabled_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50352_.Q !== dut.enabled_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25484 gold=%b dut=%b", gold._50352_.Q, dut.enabled_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50353_.Q !== dut.enabled_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25485 gold=%b dut=%b", gold._50353_.Q, dut.enabled_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50354_.Q !== dut.enabled_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25486 gold=%b dut=%b", gold._50354_.Q, dut.enabled_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50355_.Q !== dut.enabled_counter[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25487 gold=%b dut=%b", gold._50355_.Q, dut.enabled_counter[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50356_.Q !== dut.enabled_counter[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25488 gold=%b dut=%b", gold._50356_.Q, dut.enabled_counter[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50357_.Q !== dut.enabled_counter[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25489 gold=%b dut=%b", gold._50357_.Q, dut.enabled_counter[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50358_.Q !== dut.enabled_counter[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25490 gold=%b dut=%b", gold._50358_.Q, dut.enabled_counter[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50359_.Q !== dut.enabled_counter[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25491 gold=%b dut=%b", gold._50359_.Q, dut.enabled_counter[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50360_.Q !== dut.enabled_counter[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25492 gold=%b dut=%b", gold._50360_.Q, dut.enabled_counter[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50361_.Q !== dut.enabled_counter[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25493 gold=%b dut=%b", gold._50361_.Q, dut.enabled_counter[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50362_.Q !== dut.enabled_counter[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25494 gold=%b dut=%b", gold._50362_.Q, dut.enabled_counter[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50363_.Q !== dut.enabled_counter[39]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25495 gold=%b dut=%b", gold._50363_.Q, dut.enabled_counter[39]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50364_.Q !== dut.enabled_counter[40]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25496 gold=%b dut=%b", gold._50364_.Q, dut.enabled_counter[40]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50365_.Q !== dut.enabled_counter[41]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25497 gold=%b dut=%b", gold._50365_.Q, dut.enabled_counter[41]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50366_.Q !== dut.enabled_counter[42]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25498 gold=%b dut=%b", gold._50366_.Q, dut.enabled_counter[42]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50367_.Q !== dut.enabled_counter[43]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25499 gold=%b dut=%b", gold._50367_.Q, dut.enabled_counter[43]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50368_.Q !== dut.enabled_counter[44]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25500 gold=%b dut=%b", gold._50368_.Q, dut.enabled_counter[44]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50369_.Q !== dut.enabled_counter[45]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25501 gold=%b dut=%b", gold._50369_.Q, dut.enabled_counter[45]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50370_.Q !== dut.enabled_counter[46]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25502 gold=%b dut=%b", gold._50370_.Q, dut.enabled_counter[46]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50371_.Q !== dut.enabled_counter[47]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25503 gold=%b dut=%b", gold._50371_.Q, dut.enabled_counter[47]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50372_.Q !== dut.enabled_counter[48]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25504 gold=%b dut=%b", gold._50372_.Q, dut.enabled_counter[48]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50373_.Q !== dut.enabled_counter[49]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25505 gold=%b dut=%b", gold._50373_.Q, dut.enabled_counter[49]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50374_.Q !== dut.enabled_counter[50]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25506 gold=%b dut=%b", gold._50374_.Q, dut.enabled_counter[50]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50375_.Q !== dut.enabled_counter[51]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25507 gold=%b dut=%b", gold._50375_.Q, dut.enabled_counter[51]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50376_.Q !== dut.enabled_counter[52]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25508 gold=%b dut=%b", gold._50376_.Q, dut.enabled_counter[52]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50377_.Q !== dut.enabled_counter[53]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25509 gold=%b dut=%b", gold._50377_.Q, dut.enabled_counter[53]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50378_.Q !== dut.enabled_counter[54]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25510 gold=%b dut=%b", gold._50378_.Q, dut.enabled_counter[54]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50379_.Q !== dut.enabled_counter[55]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25511 gold=%b dut=%b", gold._50379_.Q, dut.enabled_counter[55]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50380_.Q !== dut.enabled_counter[56]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25512 gold=%b dut=%b", gold._50380_.Q, dut.enabled_counter[56]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50381_.Q !== dut.enabled_counter[57]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25513 gold=%b dut=%b", gold._50381_.Q, dut.enabled_counter[57]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50382_.Q !== dut.enabled_counter[58]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25514 gold=%b dut=%b", gold._50382_.Q, dut.enabled_counter[58]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50383_.Q !== dut.enabled_counter[59]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25515 gold=%b dut=%b", gold._50383_.Q, dut.enabled_counter[59]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50384_.Q !== dut.enabled_counter[60]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25516 gold=%b dut=%b", gold._50384_.Q, dut.enabled_counter[60]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50385_.Q !== dut.enabled_counter[61]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25517 gold=%b dut=%b", gold._50385_.Q, dut.enabled_counter[61]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50386_.Q !== dut.enabled_counter[62]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25518 gold=%b dut=%b", gold._50386_.Q, dut.enabled_counter[62]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50387_.Q !== dut.enabled_counter[63]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25519 gold=%b dut=%b", gold._50387_.Q, dut.enabled_counter[63]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50260_.Q !== dut.small_event_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25520 gold=%b dut=%b", gold._50260_.Q, dut.small_event_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50261_.Q !== dut.small_event_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25521 gold=%b dut=%b", gold._50261_.Q, dut.small_event_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50262_.Q !== dut.small_event_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25522 gold=%b dut=%b", gold._50262_.Q, dut.small_event_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50263_.Q !== dut.small_event_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25523 gold=%b dut=%b", gold._50263_.Q, dut.small_event_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50264_.Q !== dut.small_event_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25524 gold=%b dut=%b", gold._50264_.Q, dut.small_event_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50265_.Q !== dut.small_event_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25525 gold=%b dut=%b", gold._50265_.Q, dut.small_event_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50266_.Q !== dut.small_event_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25526 gold=%b dut=%b", gold._50266_.Q, dut.small_event_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50267_.Q !== dut.small_event_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25527 gold=%b dut=%b", gold._50267_.Q, dut.small_event_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50268_.Q !== dut.small_event_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25528 gold=%b dut=%b", gold._50268_.Q, dut.small_event_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50269_.Q !== dut.small_event_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25529 gold=%b dut=%b", gold._50269_.Q, dut.small_event_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50270_.Q !== dut.small_event_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25530 gold=%b dut=%b", gold._50270_.Q, dut.small_event_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50271_.Q !== dut.small_event_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25531 gold=%b dut=%b", gold._50271_.Q, dut.small_event_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50272_.Q !== dut.small_event_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25532 gold=%b dut=%b", gold._50272_.Q, dut.small_event_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50273_.Q !== dut.small_event_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25533 gold=%b dut=%b", gold._50273_.Q, dut.small_event_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50274_.Q !== dut.small_event_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25534 gold=%b dut=%b", gold._50274_.Q, dut.small_event_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50275_.Q !== dut.small_event_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25535 gold=%b dut=%b", gold._50275_.Q, dut.small_event_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50276_.Q !== dut.small_event_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25536 gold=%b dut=%b", gold._50276_.Q, dut.small_event_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50277_.Q !== dut.small_event_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25537 gold=%b dut=%b", gold._50277_.Q, dut.small_event_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50278_.Q !== dut.small_event_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25538 gold=%b dut=%b", gold._50278_.Q, dut.small_event_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50279_.Q !== dut.small_event_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25539 gold=%b dut=%b", gold._50279_.Q, dut.small_event_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50280_.Q !== dut.small_event_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25540 gold=%b dut=%b", gold._50280_.Q, dut.small_event_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50281_.Q !== dut.small_event_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25541 gold=%b dut=%b", gold._50281_.Q, dut.small_event_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50282_.Q !== dut.small_event_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25542 gold=%b dut=%b", gold._50282_.Q, dut.small_event_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50283_.Q !== dut.small_event_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25543 gold=%b dut=%b", gold._50283_.Q, dut.small_event_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50284_.Q !== dut.small_event_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25544 gold=%b dut=%b", gold._50284_.Q, dut.small_event_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50285_.Q !== dut.small_event_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25545 gold=%b dut=%b", gold._50285_.Q, dut.small_event_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50286_.Q !== dut.small_event_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25546 gold=%b dut=%b", gold._50286_.Q, dut.small_event_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50287_.Q !== dut.small_event_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25547 gold=%b dut=%b", gold._50287_.Q, dut.small_event_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50288_.Q !== dut.small_event_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25548 gold=%b dut=%b", gold._50288_.Q, dut.small_event_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50289_.Q !== dut.small_event_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25549 gold=%b dut=%b", gold._50289_.Q, dut.small_event_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50290_.Q !== dut.small_event_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25550 gold=%b dut=%b", gold._50290_.Q, dut.small_event_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50291_.Q !== dut.small_event_counter[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25551 gold=%b dut=%b", gold._50291_.Q, dut.small_event_counter[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50292_.Q !== dut.small_event_counter[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25552 gold=%b dut=%b", gold._50292_.Q, dut.small_event_counter[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50293_.Q !== dut.small_event_counter[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25553 gold=%b dut=%b", gold._50293_.Q, dut.small_event_counter[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50294_.Q !== dut.small_event_counter[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25554 gold=%b dut=%b", gold._50294_.Q, dut.small_event_counter[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50295_.Q !== dut.small_event_counter[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25555 gold=%b dut=%b", gold._50295_.Q, dut.small_event_counter[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50296_.Q !== dut.small_event_counter[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25556 gold=%b dut=%b", gold._50296_.Q, dut.small_event_counter[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50297_.Q !== dut.small_event_counter[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25557 gold=%b dut=%b", gold._50297_.Q, dut.small_event_counter[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50298_.Q !== dut.small_event_counter[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25558 gold=%b dut=%b", gold._50298_.Q, dut.small_event_counter[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50299_.Q !== dut.small_event_counter[39]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25559 gold=%b dut=%b", gold._50299_.Q, dut.small_event_counter[39]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50300_.Q !== dut.small_event_counter[40]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25560 gold=%b dut=%b", gold._50300_.Q, dut.small_event_counter[40]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50301_.Q !== dut.small_event_counter[41]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25561 gold=%b dut=%b", gold._50301_.Q, dut.small_event_counter[41]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50302_.Q !== dut.control_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25562 gold=%b dut=%b", gold._50302_.Q, dut.control_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50303_.Q !== dut.control_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25563 gold=%b dut=%b", gold._50303_.Q, dut.control_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50304_.Q !== dut.control_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25564 gold=%b dut=%b", gold._50304_.Q, dut.control_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50305_.Q !== dut.control_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25565 gold=%b dut=%b", gold._50305_.Q, dut.control_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50306_.Q !== dut.control_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25566 gold=%b dut=%b", gold._50306_.Q, dut.control_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50307_.Q !== dut.control_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25567 gold=%b dut=%b", gold._50307_.Q, dut.control_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50308_.Q !== dut.control_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25568 gold=%b dut=%b", gold._50308_.Q, dut.control_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50309_.Q !== dut.control_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25569 gold=%b dut=%b", gold._50309_.Q, dut.control_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50310_.Q !== dut.control_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25570 gold=%b dut=%b", gold._50310_.Q, dut.control_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50311_.Q !== dut.control_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25571 gold=%b dut=%b", gold._50311_.Q, dut.control_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50312_.Q !== dut.control_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25572 gold=%b dut=%b", gold._50312_.Q, dut.control_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50313_.Q !== dut.control_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25573 gold=%b dut=%b", gold._50313_.Q, dut.control_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50314_.Q !== dut.control_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25574 gold=%b dut=%b", gold._50314_.Q, dut.control_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50315_.Q !== dut.control_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25575 gold=%b dut=%b", gold._50315_.Q, dut.control_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50316_.Q !== dut.control_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25576 gold=%b dut=%b", gold._50316_.Q, dut.control_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50317_.Q !== dut.control_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25577 gold=%b dut=%b", gold._50317_.Q, dut.control_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50318_.Q !== dut.control_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25578 gold=%b dut=%b", gold._50318_.Q, dut.control_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50319_.Q !== dut.control_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25579 gold=%b dut=%b", gold._50319_.Q, dut.control_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50320_.Q !== dut.control_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25580 gold=%b dut=%b", gold._50320_.Q, dut.control_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50321_.Q !== dut.control_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25581 gold=%b dut=%b", gold._50321_.Q, dut.control_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50322_.Q !== dut.control_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25582 gold=%b dut=%b", gold._50322_.Q, dut.control_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50323_.Q !== dut.control_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25583 gold=%b dut=%b", gold._50323_.Q, dut.control_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48311_.Q !== dut.control_state_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25584 gold=%b dut=%b", gold._48311_.Q, dut.control_state_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48312_.Q !== dut.control_state_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25585 gold=%b dut=%b", gold._48312_.Q, dut.control_state_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48313_.Q !== dut.control_state_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25586 gold=%b dut=%b", gold._48313_.Q, dut.control_state_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48314_.Q !== dut.control_state_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25587 gold=%b dut=%b", gold._48314_.Q, dut.control_state_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48315_.Q !== dut.control_state_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25588 gold=%b dut=%b", gold._48315_.Q, dut.control_state_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48316_.Q !== dut.control_state_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25589 gold=%b dut=%b", gold._48316_.Q, dut.control_state_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48317_.Q !== dut.control_state_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25590 gold=%b dut=%b", gold._48317_.Q, dut.control_state_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48318_.Q !== dut.control_state_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25591 gold=%b dut=%b", gold._48318_.Q, dut.control_state_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49640_.Q !== dut.hold_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25592 gold=%b dut=%b", gold._49640_.Q, dut.hold_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49641_.Q !== dut.hold_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25593 gold=%b dut=%b", gold._49641_.Q, dut.hold_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49642_.Q !== dut.hold_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25594 gold=%b dut=%b", gold._49642_.Q, dut.hold_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49643_.Q !== dut.hold_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25595 gold=%b dut=%b", gold._49643_.Q, dut.hold_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49644_.Q !== dut.hold_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25596 gold=%b dut=%b", gold._49644_.Q, dut.hold_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49645_.Q !== dut.hold_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25597 gold=%b dut=%b", gold._49645_.Q, dut.hold_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49646_.Q !== dut.hold_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25598 gold=%b dut=%b", gold._49646_.Q, dut.hold_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49647_.Q !== dut.hold_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25599 gold=%b dut=%b", gold._49647_.Q, dut.hold_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49648_.Q !== dut.hold_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25600 gold=%b dut=%b", gold._49648_.Q, dut.hold_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49649_.Q !== dut.hold_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25601 gold=%b dut=%b", gold._49649_.Q, dut.hold_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49650_.Q !== dut.hold_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25602 gold=%b dut=%b", gold._49650_.Q, dut.hold_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49651_.Q !== dut.hold_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25603 gold=%b dut=%b", gold._49651_.Q, dut.hold_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49652_.Q !== dut.hold_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25604 gold=%b dut=%b", gold._49652_.Q, dut.hold_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49653_.Q !== dut.hold_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25605 gold=%b dut=%b", gold._49653_.Q, dut.hold_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49654_.Q !== dut.hold_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25606 gold=%b dut=%b", gold._49654_.Q, dut.hold_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49655_.Q !== dut.hold_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25607 gold=%b dut=%b", gold._49655_.Q, dut.hold_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49656_.Q !== dut.hold_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25608 gold=%b dut=%b", gold._49656_.Q, dut.hold_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49657_.Q !== dut.hold_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25609 gold=%b dut=%b", gold._49657_.Q, dut.hold_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49658_.Q !== dut.hold_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25610 gold=%b dut=%b", gold._49658_.Q, dut.hold_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49659_.Q !== dut.hold_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25611 gold=%b dut=%b", gold._49659_.Q, dut.hold_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49660_.Q !== dut.hold_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25612 gold=%b dut=%b", gold._49660_.Q, dut.hold_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49661_.Q !== dut.hold_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25613 gold=%b dut=%b", gold._49661_.Q, dut.hold_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49662_.Q !== dut.hold_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25614 gold=%b dut=%b", gold._49662_.Q, dut.hold_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49663_.Q !== dut.hold_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25615 gold=%b dut=%b", gold._49663_.Q, dut.hold_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49664_.Q !== dut.hold_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25616 gold=%b dut=%b", gold._49664_.Q, dut.hold_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49665_.Q !== dut.hold_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25617 gold=%b dut=%b", gold._49665_.Q, dut.hold_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49666_.Q !== dut.hold_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25618 gold=%b dut=%b", gold._49666_.Q, dut.hold_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49667_.Q !== dut.hold_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25619 gold=%b dut=%b", gold._49667_.Q, dut.hold_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49668_.Q !== dut.hold_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25620 gold=%b dut=%b", gold._49668_.Q, dut.hold_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49669_.Q !== dut.hold_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25621 gold=%b dut=%b", gold._49669_.Q, dut.hold_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49670_.Q !== dut.hold_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25622 gold=%b dut=%b", gold._49670_.Q, dut.hold_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49671_.Q !== dut.hold_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25623 gold=%b dut=%b", gold._49671_.Q, dut.hold_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49287_.Q !== dut.write_data_register_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25624 gold=%b dut=%b", gold._49287_.Q, dut.write_data_register_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49288_.Q !== dut.write_data_register_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25625 gold=%b dut=%b", gold._49288_.Q, dut.write_data_register_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49289_.Q !== dut.write_data_register_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25626 gold=%b dut=%b", gold._49289_.Q, dut.write_data_register_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49290_.Q !== dut.write_data_register_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25627 gold=%b dut=%b", gold._49290_.Q, dut.write_data_register_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49291_.Q !== dut.write_data_register_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25628 gold=%b dut=%b", gold._49291_.Q, dut.write_data_register_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49292_.Q !== dut.write_data_register_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25629 gold=%b dut=%b", gold._49292_.Q, dut.write_data_register_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49293_.Q !== dut.write_data_register_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25630 gold=%b dut=%b", gold._49293_.Q, dut.write_data_register_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49294_.Q !== dut.write_data_register_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25631 gold=%b dut=%b", gold._49294_.Q, dut.write_data_register_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49298_.Q !== dut.write_data_register_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25632 gold=%b dut=%b", gold._49298_.Q, dut.write_data_register_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49299_.Q !== dut.write_data_register_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25633 gold=%b dut=%b", gold._49299_.Q, dut.write_data_register_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49306_.Q !== dut.data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25634 gold=%b dut=%b", gold._49306_.Q, dut.data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49317_.Q !== dut.data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25635 gold=%b dut=%b", gold._49317_.Q, dut.data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49328_.Q !== dut.data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25636 gold=%b dut=%b", gold._49328_.Q, dut.data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49333_.Q !== dut.data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25637 gold=%b dut=%b", gold._49333_.Q, dut.data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49334_.Q !== dut.data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25638 gold=%b dut=%b", gold._49334_.Q, dut.data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49335_.Q !== dut.data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25639 gold=%b dut=%b", gold._49335_.Q, dut.data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49336_.Q !== dut.data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25640 gold=%b dut=%b", gold._49336_.Q, dut.data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49337_.Q !== dut.data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25641 gold=%b dut=%b", gold._49337_.Q, dut.data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49338_.Q !== dut.data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25642 gold=%b dut=%b", gold._49338_.Q, dut.data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49339_.Q !== dut.data_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25643 gold=%b dut=%b", gold._49339_.Q, dut.data_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49340_.Q !== dut.data_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25644 gold=%b dut=%b", gold._49340_.Q, dut.data_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49341_.Q !== dut.data_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25645 gold=%b dut=%b", gold._49341_.Q, dut.data_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49342_.Q !== dut.data_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25646 gold=%b dut=%b", gold._49342_.Q, dut.data_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49343_.Q !== dut.data_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25647 gold=%b dut=%b", gold._49343_.Q, dut.data_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49344_.Q !== dut.data_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25648 gold=%b dut=%b", gold._49344_.Q, dut.data_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49345_.Q !== dut.data_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25649 gold=%b dut=%b", gold._49345_.Q, dut.data_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49346_.Q !== dut.data_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25650 gold=%b dut=%b", gold._49346_.Q, dut.data_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49347_.Q !== dut.data_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25651 gold=%b dut=%b", gold._49347_.Q, dut.data_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49348_.Q !== dut.data_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25652 gold=%b dut=%b", gold._49348_.Q, dut.data_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49349_.Q !== dut.data_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25653 gold=%b dut=%b", gold._49349_.Q, dut.data_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49350_.Q !== dut.data_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25654 gold=%b dut=%b", gold._49350_.Q, dut.data_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49351_.Q !== dut.data_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25655 gold=%b dut=%b", gold._49351_.Q, dut.data_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49255_.Q !== dut.narrow_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25656 gold=%b dut=%b", gold._49255_.Q, dut.narrow_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49256_.Q !== dut.narrow_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25657 gold=%b dut=%b", gold._49256_.Q, dut.narrow_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49257_.Q !== dut.narrow_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25658 gold=%b dut=%b", gold._49257_.Q, dut.narrow_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49258_.Q !== dut.narrow_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25659 gold=%b dut=%b", gold._49258_.Q, dut.narrow_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49259_.Q !== dut.narrow_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25660 gold=%b dut=%b", gold._49259_.Q, dut.narrow_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49260_.Q !== dut.narrow_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25661 gold=%b dut=%b", gold._49260_.Q, dut.narrow_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49261_.Q !== dut.narrow_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25662 gold=%b dut=%b", gold._49261_.Q, dut.narrow_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49262_.Q !== dut.cycle_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25663 gold=%b dut=%b", gold._49262_.Q, dut.cycle_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49263_.Q !== dut.cycle_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25664 gold=%b dut=%b", gold._49263_.Q, dut.cycle_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49264_.Q !== dut.cycle_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25665 gold=%b dut=%b", gold._49264_.Q, dut.cycle_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49265_.Q !== dut.cycle_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25666 gold=%b dut=%b", gold._49265_.Q, dut.cycle_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49266_.Q !== dut.cycle_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25667 gold=%b dut=%b", gold._49266_.Q, dut.cycle_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49267_.Q !== dut.cycle_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25668 gold=%b dut=%b", gold._49267_.Q, dut.cycle_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49268_.Q !== dut.cycle_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25669 gold=%b dut=%b", gold._49268_.Q, dut.cycle_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49269_.Q !== dut.cycle_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25670 gold=%b dut=%b", gold._49269_.Q, dut.cycle_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49270_.Q !== dut.cycle_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25671 gold=%b dut=%b", gold._49270_.Q, dut.cycle_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49271_.Q !== dut.cycle_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25672 gold=%b dut=%b", gold._49271_.Q, dut.cycle_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49272_.Q !== dut.cycle_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25673 gold=%b dut=%b", gold._49272_.Q, dut.cycle_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49273_.Q !== dut.cycle_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25674 gold=%b dut=%b", gold._49273_.Q, dut.cycle_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49274_.Q !== dut.cycle_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25675 gold=%b dut=%b", gold._49274_.Q, dut.cycle_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49275_.Q !== dut.cycle_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25676 gold=%b dut=%b", gold._49275_.Q, dut.cycle_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49276_.Q !== dut.cycle_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25677 gold=%b dut=%b", gold._49276_.Q, dut.cycle_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49277_.Q !== dut.cycle_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25678 gold=%b dut=%b", gold._49277_.Q, dut.cycle_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49278_.Q !== dut.cycle_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25679 gold=%b dut=%b", gold._49278_.Q, dut.cycle_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49279_.Q !== dut.cycle_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25680 gold=%b dut=%b", gold._49279_.Q, dut.cycle_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49280_.Q !== dut.cycle_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25681 gold=%b dut=%b", gold._49280_.Q, dut.cycle_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49281_.Q !== dut.cycle_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25682 gold=%b dut=%b", gold._49281_.Q, dut.cycle_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49282_.Q !== dut.cycle_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25683 gold=%b dut=%b", gold._49282_.Q, dut.cycle_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49283_.Q !== dut.cycle_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25684 gold=%b dut=%b", gold._49283_.Q, dut.cycle_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49284_.Q !== dut.cycle_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25685 gold=%b dut=%b", gold._49284_.Q, dut.cycle_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49285_.Q !== dut.cycle_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25686 gold=%b dut=%b", gold._49285_.Q, dut.cycle_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49286_.Q !== dut.cycle_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25687 gold=%b dut=%b", gold._49286_.Q, dut.cycle_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49223_.Q !== dut.wide_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25688 gold=%b dut=%b", gold._49223_.Q, dut.wide_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49224_.Q !== dut.wide_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25689 gold=%b dut=%b", gold._49224_.Q, dut.wide_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49225_.Q !== dut.wide_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25690 gold=%b dut=%b", gold._49225_.Q, dut.wide_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49226_.Q !== dut.wide_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25691 gold=%b dut=%b", gold._49226_.Q, dut.wide_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49227_.Q !== dut.wide_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25692 gold=%b dut=%b", gold._49227_.Q, dut.wide_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49228_.Q !== dut.wide_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25693 gold=%b dut=%b", gold._49228_.Q, dut.wide_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49229_.Q !== dut.wide_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25694 gold=%b dut=%b", gold._49229_.Q, dut.wide_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49230_.Q !== dut.wide_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25695 gold=%b dut=%b", gold._49230_.Q, dut.wide_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49231_.Q !== dut.wide_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25696 gold=%b dut=%b", gold._49231_.Q, dut.wide_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49232_.Q !== dut.wide_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25697 gold=%b dut=%b", gold._49232_.Q, dut.wide_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49233_.Q !== dut.wide_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25698 gold=%b dut=%b", gold._49233_.Q, dut.wide_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49234_.Q !== dut.wide_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25699 gold=%b dut=%b", gold._49234_.Q, dut.wide_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49235_.Q !== dut.wide_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25700 gold=%b dut=%b", gold._49235_.Q, dut.wide_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49236_.Q !== dut.wide_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25701 gold=%b dut=%b", gold._49236_.Q, dut.wide_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49237_.Q !== dut.wide_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25702 gold=%b dut=%b", gold._49237_.Q, dut.wide_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49238_.Q !== dut.wide_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25703 gold=%b dut=%b", gold._49238_.Q, dut.wide_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49239_.Q !== dut.wide_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25704 gold=%b dut=%b", gold._49239_.Q, dut.wide_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49240_.Q !== dut.wide_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25705 gold=%b dut=%b", gold._49240_.Q, dut.wide_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49241_.Q !== dut.wide_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25706 gold=%b dut=%b", gold._49241_.Q, dut.wide_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49242_.Q !== dut.wide_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25707 gold=%b dut=%b", gold._49242_.Q, dut.wide_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49243_.Q !== dut.wide_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25708 gold=%b dut=%b", gold._49243_.Q, dut.wide_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49244_.Q !== dut.wide_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25709 gold=%b dut=%b", gold._49244_.Q, dut.wide_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49245_.Q !== dut.wide_data_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25710 gold=%b dut=%b", gold._49245_.Q, dut.wide_data_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49246_.Q !== dut.wide_data_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25711 gold=%b dut=%b", gold._49246_.Q, dut.wide_data_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49247_.Q !== dut.wide_data_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25712 gold=%b dut=%b", gold._49247_.Q, dut.wide_data_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49248_.Q !== dut.wide_data_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25713 gold=%b dut=%b", gold._49248_.Q, dut.wide_data_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49249_.Q !== dut.wide_data_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25714 gold=%b dut=%b", gold._49249_.Q, dut.wide_data_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49250_.Q !== dut.wide_data_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25715 gold=%b dut=%b", gold._49250_.Q, dut.wide_data_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49251_.Q !== dut.wide_data_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25716 gold=%b dut=%b", gold._49251_.Q, dut.wide_data_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49252_.Q !== dut.wide_data_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25717 gold=%b dut=%b", gold._49252_.Q, dut.wide_data_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49253_.Q !== dut.wide_data_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25718 gold=%b dut=%b", gold._49253_.Q, dut.wide_data_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49254_.Q !== dut.wide_data_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25719 gold=%b dut=%b", gold._49254_.Q, dut.wide_data_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49191_.Q !== dut.wide_data_reg[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25720 gold=%b dut=%b", gold._49191_.Q, dut.wide_data_reg[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49192_.Q !== dut.wide_data_reg[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25721 gold=%b dut=%b", gold._49192_.Q, dut.wide_data_reg[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49193_.Q !== dut.wide_data_reg[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25722 gold=%b dut=%b", gold._49193_.Q, dut.wide_data_reg[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49194_.Q !== dut.wide_data_reg[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25723 gold=%b dut=%b", gold._49194_.Q, dut.wide_data_reg[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49195_.Q !== dut.wide_data_reg[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25724 gold=%b dut=%b", gold._49195_.Q, dut.wide_data_reg[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49196_.Q !== dut.wide_data_reg[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25725 gold=%b dut=%b", gold._49196_.Q, dut.wide_data_reg[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49197_.Q !== dut.wide_data_reg[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25726 gold=%b dut=%b", gold._49197_.Q, dut.wide_data_reg[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49198_.Q !== dut.wide_data_reg[39]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25727 gold=%b dut=%b", gold._49198_.Q, dut.wide_data_reg[39]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49199_.Q !== dut.wide_data_reg[40]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25728 gold=%b dut=%b", gold._49199_.Q, dut.wide_data_reg[40]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49200_.Q !== dut.wide_data_reg[41]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25729 gold=%b dut=%b", gold._49200_.Q, dut.wide_data_reg[41]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49201_.Q !== dut.wide_data_reg[42]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25730 gold=%b dut=%b", gold._49201_.Q, dut.wide_data_reg[42]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49202_.Q !== dut.wide_data_reg[43]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25731 gold=%b dut=%b", gold._49202_.Q, dut.wide_data_reg[43]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49203_.Q !== dut.wide_data_reg[44]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25732 gold=%b dut=%b", gold._49203_.Q, dut.wide_data_reg[44]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49204_.Q !== dut.wide_data_reg[45]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25733 gold=%b dut=%b", gold._49204_.Q, dut.wide_data_reg[45]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49205_.Q !== dut.wide_data_reg[46]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25734 gold=%b dut=%b", gold._49205_.Q, dut.wide_data_reg[46]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49206_.Q !== dut.wide_data_reg[47]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25735 gold=%b dut=%b", gold._49206_.Q, dut.wide_data_reg[47]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49207_.Q !== dut.wide_data_reg[48]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25736 gold=%b dut=%b", gold._49207_.Q, dut.wide_data_reg[48]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49208_.Q !== dut.wide_data_reg[49]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25737 gold=%b dut=%b", gold._49208_.Q, dut.wide_data_reg[49]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49209_.Q !== dut.wide_data_reg[50]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25738 gold=%b dut=%b", gold._49209_.Q, dut.wide_data_reg[50]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49210_.Q !== dut.wide_data_reg[51]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25739 gold=%b dut=%b", gold._49210_.Q, dut.wide_data_reg[51]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49211_.Q !== dut.wide_data_reg[52]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25740 gold=%b dut=%b", gold._49211_.Q, dut.wide_data_reg[52]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49212_.Q !== dut.wide_data_reg[53]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25741 gold=%b dut=%b", gold._49212_.Q, dut.wide_data_reg[53]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49213_.Q !== dut.wide_data_reg[54]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25742 gold=%b dut=%b", gold._49213_.Q, dut.wide_data_reg[54]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49214_.Q !== dut.wide_data_reg[55]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25743 gold=%b dut=%b", gold._49214_.Q, dut.wide_data_reg[55]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49215_.Q !== dut.wide_data_reg[56]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25744 gold=%b dut=%b", gold._49215_.Q, dut.wide_data_reg[56]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49216_.Q !== dut.wide_data_reg[57]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25745 gold=%b dut=%b", gold._49216_.Q, dut.wide_data_reg[57]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49217_.Q !== dut.wide_data_reg[58]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25746 gold=%b dut=%b", gold._49217_.Q, dut.wide_data_reg[58]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49218_.Q !== dut.wide_data_reg[59]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25747 gold=%b dut=%b", gold._49218_.Q, dut.wide_data_reg[59]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49219_.Q !== dut.wide_data_reg[60]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25748 gold=%b dut=%b", gold._49219_.Q, dut.wide_data_reg[60]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49220_.Q !== dut.wide_data_reg[61]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25749 gold=%b dut=%b", gold._49220_.Q, dut.wide_data_reg[61]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49221_.Q !== dut.wide_data_reg[62]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25750 gold=%b dut=%b", gold._49221_.Q, dut.wide_data_reg[62]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49222_.Q !== dut.control_state_2) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25751 gold=%b dut=%b", gold._49222_.Q, dut.control_state_2);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49159_.Q !== dut.data_word_lo[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25752 gold=%b dut=%b", gold._49159_.Q, dut.data_word_lo[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49160_.Q !== dut.data_word_lo[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25753 gold=%b dut=%b", gold._49160_.Q, dut.data_word_lo[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49161_.Q !== dut.data_word_lo[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25754 gold=%b dut=%b", gold._49161_.Q, dut.data_word_lo[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49162_.Q !== dut.data_word_lo[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25755 gold=%b dut=%b", gold._49162_.Q, dut.data_word_lo[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49163_.Q !== dut.data_word_lo[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25756 gold=%b dut=%b", gold._49163_.Q, dut.data_word_lo[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49164_.Q !== dut.data_word_lo[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25757 gold=%b dut=%b", gold._49164_.Q, dut.data_word_lo[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49165_.Q !== dut.data_word_lo[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25758 gold=%b dut=%b", gold._49165_.Q, dut.data_word_lo[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49166_.Q !== dut.data_word_lo[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25759 gold=%b dut=%b", gold._49166_.Q, dut.data_word_lo[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49167_.Q !== dut.data_word_lo[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25760 gold=%b dut=%b", gold._49167_.Q, dut.data_word_lo[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49168_.Q !== dut.data_word_lo[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25761 gold=%b dut=%b", gold._49168_.Q, dut.data_word_lo[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49169_.Q !== dut.data_word_lo[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25762 gold=%b dut=%b", gold._49169_.Q, dut.data_word_lo[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49170_.Q !== dut.data_word_lo[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25763 gold=%b dut=%b", gold._49170_.Q, dut.data_word_lo[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49171_.Q !== dut.data_word_lo[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25764 gold=%b dut=%b", gold._49171_.Q, dut.data_word_lo[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49172_.Q !== dut.data_word_lo[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25765 gold=%b dut=%b", gold._49172_.Q, dut.data_word_lo[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49173_.Q !== dut.data_word_lo[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25766 gold=%b dut=%b", gold._49173_.Q, dut.data_word_lo[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49174_.Q !== dut.data_word_lo[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25767 gold=%b dut=%b", gold._49174_.Q, dut.data_word_lo[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49175_.Q !== dut.data_word_lo[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25768 gold=%b dut=%b", gold._49175_.Q, dut.data_word_lo[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49176_.Q !== dut.data_word_lo[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25769 gold=%b dut=%b", gold._49176_.Q, dut.data_word_lo[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49177_.Q !== dut.data_word_lo[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25770 gold=%b dut=%b", gold._49177_.Q, dut.data_word_lo[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49178_.Q !== dut.data_word_lo[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25771 gold=%b dut=%b", gold._49178_.Q, dut.data_word_lo[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49179_.Q !== dut.data_word_lo[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25772 gold=%b dut=%b", gold._49179_.Q, dut.data_word_lo[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49180_.Q !== dut.data_word_lo[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25773 gold=%b dut=%b", gold._49180_.Q, dut.data_word_lo[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49181_.Q !== dut.data_word_lo[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25774 gold=%b dut=%b", gold._49181_.Q, dut.data_word_lo[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49182_.Q !== dut.wide_data_reg[63]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25775 gold=%b dut=%b", gold._49182_.Q, dut.wide_data_reg[63]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49183_.Q !== dut.wide_data_reg[64]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25776 gold=%b dut=%b", gold._49183_.Q, dut.wide_data_reg[64]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49184_.Q !== dut.wide_data_reg[65]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25777 gold=%b dut=%b", gold._49184_.Q, dut.wide_data_reg[65]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49185_.Q !== dut.wide_data_reg[66]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25778 gold=%b dut=%b", gold._49185_.Q, dut.wide_data_reg[66]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49186_.Q !== dut.wide_data_reg[67]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25779 gold=%b dut=%b", gold._49186_.Q, dut.wide_data_reg[67]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49187_.Q !== dut.wide_data_reg[68]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25780 gold=%b dut=%b", gold._49187_.Q, dut.wide_data_reg[68]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49188_.Q !== dut.wide_data_reg[69]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25781 gold=%b dut=%b", gold._49188_.Q, dut.wide_data_reg[69]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49189_.Q !== dut.wide_data_reg[70]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25782 gold=%b dut=%b", gold._49189_.Q, dut.wide_data_reg[70]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49190_.Q !== dut.wide_data_reg[71]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25783 gold=%b dut=%b", gold._49190_.Q, dut.wide_data_reg[71]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49127_.Q !== dut.datapath_reg_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25784 gold=%b dut=%b", gold._49127_.Q, dut.datapath_reg_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49128_.Q !== dut.datapath_reg_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25785 gold=%b dut=%b", gold._49128_.Q, dut.datapath_reg_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49129_.Q !== dut.datapath_reg_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25786 gold=%b dut=%b", gold._49129_.Q, dut.datapath_reg_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49130_.Q !== dut.datapath_reg_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25787 gold=%b dut=%b", gold._49130_.Q, dut.datapath_reg_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49131_.Q !== dut.datapath_reg_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25788 gold=%b dut=%b", gold._49131_.Q, dut.datapath_reg_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49132_.Q !== dut.datapath_reg_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25789 gold=%b dut=%b", gold._49132_.Q, dut.datapath_reg_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49133_.Q !== dut.datapath_reg_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25790 gold=%b dut=%b", gold._49133_.Q, dut.datapath_reg_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49134_.Q !== dut.datapath_reg_0[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25791 gold=%b dut=%b", gold._49134_.Q, dut.datapath_reg_0[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49135_.Q !== dut.datapath_reg_0[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25792 gold=%b dut=%b", gold._49135_.Q, dut.datapath_reg_0[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49136_.Q !== dut.datapath_reg_0[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25793 gold=%b dut=%b", gold._49136_.Q, dut.datapath_reg_0[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49137_.Q !== dut.datapath_reg_0[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25794 gold=%b dut=%b", gold._49137_.Q, dut.datapath_reg_0[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49138_.Q !== dut.datapath_reg_0[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25795 gold=%b dut=%b", gold._49138_.Q, dut.datapath_reg_0[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49139_.Q !== dut.datapath_reg_0[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25796 gold=%b dut=%b", gold._49139_.Q, dut.datapath_reg_0[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49140_.Q !== dut.datapath_reg_0[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25797 gold=%b dut=%b", gold._49140_.Q, dut.datapath_reg_0[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49141_.Q !== dut.datapath_reg_0[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25798 gold=%b dut=%b", gold._49141_.Q, dut.datapath_reg_0[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49142_.Q !== dut.datapath_reg_0[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25799 gold=%b dut=%b", gold._49142_.Q, dut.datapath_reg_0[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49143_.Q !== dut.datapath_reg_0[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25800 gold=%b dut=%b", gold._49143_.Q, dut.datapath_reg_0[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49144_.Q !== dut.datapath_reg_0[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25801 gold=%b dut=%b", gold._49144_.Q, dut.datapath_reg_0[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49145_.Q !== dut.datapath_reg_0[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25802 gold=%b dut=%b", gold._49145_.Q, dut.datapath_reg_0[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49146_.Q !== dut.datapath_reg_0[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25803 gold=%b dut=%b", gold._49146_.Q, dut.datapath_reg_0[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49147_.Q !== dut.datapath_reg_0[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25804 gold=%b dut=%b", gold._49147_.Q, dut.datapath_reg_0[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49148_.Q !== dut.datapath_reg_0[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25805 gold=%b dut=%b", gold._49148_.Q, dut.datapath_reg_0[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49149_.Q !== dut.datapath_reg_0[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25806 gold=%b dut=%b", gold._49149_.Q, dut.datapath_reg_0[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49150_.Q !== dut.datapath_reg_0[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25807 gold=%b dut=%b", gold._49150_.Q, dut.datapath_reg_0[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49151_.Q !== dut.datapath_reg_0[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25808 gold=%b dut=%b", gold._49151_.Q, dut.datapath_reg_0[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49152_.Q !== dut.datapath_reg_0[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25809 gold=%b dut=%b", gold._49152_.Q, dut.datapath_reg_0[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49153_.Q !== dut.datapath_reg_0[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25810 gold=%b dut=%b", gold._49153_.Q, dut.datapath_reg_0[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49154_.Q !== dut.datapath_reg_0[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25811 gold=%b dut=%b", gold._49154_.Q, dut.datapath_reg_0[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49155_.Q !== dut.datapath_reg_0[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25812 gold=%b dut=%b", gold._49155_.Q, dut.datapath_reg_0[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49156_.Q !== dut.datapath_reg_0[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25813 gold=%b dut=%b", gold._49156_.Q, dut.datapath_reg_0[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49157_.Q !== dut.datapath_reg_0[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25814 gold=%b dut=%b", gold._49157_.Q, dut.datapath_reg_0[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49158_.Q !== dut.datapath_reg_0[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25815 gold=%b dut=%b", gold._49158_.Q, dut.datapath_reg_0[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49095_.Q !== dut.narrow_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25816 gold=%b dut=%b", gold._49095_.Q, dut.narrow_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49096_.Q !== dut.narrow_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25817 gold=%b dut=%b", gold._49096_.Q, dut.narrow_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49097_.Q !== dut.narrow_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25818 gold=%b dut=%b", gold._49097_.Q, dut.narrow_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49098_.Q !== dut.narrow_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25819 gold=%b dut=%b", gold._49098_.Q, dut.narrow_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49099_.Q !== dut.narrow_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25820 gold=%b dut=%b", gold._49099_.Q, dut.narrow_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49100_.Q !== dut.narrow_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25821 gold=%b dut=%b", gold._49100_.Q, dut.narrow_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49101_.Q !== dut.narrow_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25822 gold=%b dut=%b", gold._49101_.Q, dut.narrow_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49102_.Q !== dut.datapath_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25823 gold=%b dut=%b", gold._49102_.Q, dut.datapath_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49103_.Q !== dut.datapath_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25824 gold=%b dut=%b", gold._49103_.Q, dut.datapath_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49104_.Q !== dut.datapath_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25825 gold=%b dut=%b", gold._49104_.Q, dut.datapath_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49105_.Q !== dut.datapath_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25826 gold=%b dut=%b", gold._49105_.Q, dut.datapath_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49106_.Q !== dut.datapath_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25827 gold=%b dut=%b", gold._49106_.Q, dut.datapath_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49107_.Q !== dut.datapath_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25828 gold=%b dut=%b", gold._49107_.Q, dut.datapath_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49108_.Q !== dut.datapath_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25829 gold=%b dut=%b", gold._49108_.Q, dut.datapath_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49109_.Q !== dut.datapath_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25830 gold=%b dut=%b", gold._49109_.Q, dut.datapath_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49110_.Q !== dut.datapath_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25831 gold=%b dut=%b", gold._49110_.Q, dut.datapath_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49111_.Q !== dut.datapath_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25832 gold=%b dut=%b", gold._49111_.Q, dut.datapath_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49112_.Q !== dut.datapath_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25833 gold=%b dut=%b", gold._49112_.Q, dut.datapath_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49113_.Q !== dut.datapath_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25834 gold=%b dut=%b", gold._49113_.Q, dut.datapath_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49114_.Q !== dut.datapath_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25835 gold=%b dut=%b", gold._49114_.Q, dut.datapath_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49115_.Q !== dut.datapath_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25836 gold=%b dut=%b", gold._49115_.Q, dut.datapath_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49116_.Q !== dut.datapath_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25837 gold=%b dut=%b", gold._49116_.Q, dut.datapath_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49117_.Q !== dut.datapath_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25838 gold=%b dut=%b", gold._49117_.Q, dut.datapath_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49118_.Q !== dut.datapath_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25839 gold=%b dut=%b", gold._49118_.Q, dut.datapath_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49119_.Q !== dut.datapath_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25840 gold=%b dut=%b", gold._49119_.Q, dut.datapath_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49120_.Q !== dut.datapath_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25841 gold=%b dut=%b", gold._49120_.Q, dut.datapath_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49121_.Q !== dut.datapath_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25842 gold=%b dut=%b", gold._49121_.Q, dut.datapath_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49122_.Q !== dut.datapath_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25843 gold=%b dut=%b", gold._49122_.Q, dut.datapath_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49123_.Q !== dut.datapath_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25844 gold=%b dut=%b", gold._49123_.Q, dut.datapath_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49124_.Q !== dut.datapath_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25845 gold=%b dut=%b", gold._49124_.Q, dut.datapath_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49125_.Q !== dut.datapath_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25846 gold=%b dut=%b", gold._49125_.Q, dut.datapath_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49126_.Q !== dut.datapath_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25847 gold=%b dut=%b", gold._49126_.Q, dut.datapath_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49063_.Q !== dut.wide_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25848 gold=%b dut=%b", gold._49063_.Q, dut.wide_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49064_.Q !== dut.wide_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25849 gold=%b dut=%b", gold._49064_.Q, dut.wide_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49065_.Q !== dut.wide_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25850 gold=%b dut=%b", gold._49065_.Q, dut.wide_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49066_.Q !== dut.wide_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25851 gold=%b dut=%b", gold._49066_.Q, dut.wide_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49067_.Q !== dut.wide_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25852 gold=%b dut=%b", gold._49067_.Q, dut.wide_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49068_.Q !== dut.wide_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25853 gold=%b dut=%b", gold._49068_.Q, dut.wide_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49069_.Q !== dut.wide_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25854 gold=%b dut=%b", gold._49069_.Q, dut.wide_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49070_.Q !== dut.wide_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25855 gold=%b dut=%b", gold._49070_.Q, dut.wide_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49071_.Q !== dut.wide_data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25856 gold=%b dut=%b", gold._49071_.Q, dut.wide_data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49072_.Q !== dut.wide_data_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25857 gold=%b dut=%b", gold._49072_.Q, dut.wide_data_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49073_.Q !== dut.wide_data_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25858 gold=%b dut=%b", gold._49073_.Q, dut.wide_data_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49074_.Q !== dut.wide_data_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25859 gold=%b dut=%b", gold._49074_.Q, dut.wide_data_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49075_.Q !== dut.wide_data_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25860 gold=%b dut=%b", gold._49075_.Q, dut.wide_data_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49076_.Q !== dut.wide_data_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25861 gold=%b dut=%b", gold._49076_.Q, dut.wide_data_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49077_.Q !== dut.wide_data_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25862 gold=%b dut=%b", gold._49077_.Q, dut.wide_data_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49078_.Q !== dut.wide_data_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25863 gold=%b dut=%b", gold._49078_.Q, dut.wide_data_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49079_.Q !== dut.wide_data_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25864 gold=%b dut=%b", gold._49079_.Q, dut.wide_data_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49080_.Q !== dut.wide_data_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25865 gold=%b dut=%b", gold._49080_.Q, dut.wide_data_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49081_.Q !== dut.wide_data_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25866 gold=%b dut=%b", gold._49081_.Q, dut.wide_data_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49082_.Q !== dut.wide_data_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25867 gold=%b dut=%b", gold._49082_.Q, dut.wide_data_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49083_.Q !== dut.wide_data_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25868 gold=%b dut=%b", gold._49083_.Q, dut.wide_data_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49084_.Q !== dut.wide_data_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25869 gold=%b dut=%b", gold._49084_.Q, dut.wide_data_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49085_.Q !== dut.wide_data_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25870 gold=%b dut=%b", gold._49085_.Q, dut.wide_data_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49086_.Q !== dut.wide_data_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25871 gold=%b dut=%b", gold._49086_.Q, dut.wide_data_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49087_.Q !== dut.wide_data_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25872 gold=%b dut=%b", gold._49087_.Q, dut.wide_data_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49088_.Q !== dut.wide_data_reg_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25873 gold=%b dut=%b", gold._49088_.Q, dut.wide_data_reg_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49089_.Q !== dut.wide_data_reg_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25874 gold=%b dut=%b", gold._49089_.Q, dut.wide_data_reg_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49090_.Q !== dut.wide_data_reg_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25875 gold=%b dut=%b", gold._49090_.Q, dut.wide_data_reg_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49091_.Q !== dut.wide_data_reg_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25876 gold=%b dut=%b", gold._49091_.Q, dut.wide_data_reg_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49092_.Q !== dut.wide_data_reg_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25877 gold=%b dut=%b", gold._49092_.Q, dut.wide_data_reg_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49093_.Q !== dut.wide_data_reg_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25878 gold=%b dut=%b", gold._49093_.Q, dut.wide_data_reg_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49094_.Q !== dut.narrow_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25879 gold=%b dut=%b", gold._49094_.Q, dut.narrow_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49031_.Q !== dut.data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25880 gold=%b dut=%b", gold._49031_.Q, dut.data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49032_.Q !== dut.data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25881 gold=%b dut=%b", gold._49032_.Q, dut.data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49033_.Q !== dut.data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25882 gold=%b dut=%b", gold._49033_.Q, dut.data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49034_.Q !== dut.data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25883 gold=%b dut=%b", gold._49034_.Q, dut.data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49035_.Q !== dut.data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25884 gold=%b dut=%b", gold._49035_.Q, dut.data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49036_.Q !== dut.data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25885 gold=%b dut=%b", gold._49036_.Q, dut.data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49037_.Q !== dut.data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25886 gold=%b dut=%b", gold._49037_.Q, dut.data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49038_.Q !== dut.data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25887 gold=%b dut=%b", gold._49038_.Q, dut.data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49039_.Q !== dut.data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25888 gold=%b dut=%b", gold._49039_.Q, dut.data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49040_.Q !== dut.data_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25889 gold=%b dut=%b", gold._49040_.Q, dut.data_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49041_.Q !== dut.data_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25890 gold=%b dut=%b", gold._49041_.Q, dut.data_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49042_.Q !== dut.data_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25891 gold=%b dut=%b", gold._49042_.Q, dut.data_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49043_.Q !== dut.data_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25892 gold=%b dut=%b", gold._49043_.Q, dut.data_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49044_.Q !== dut.data_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25893 gold=%b dut=%b", gold._49044_.Q, dut.data_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49045_.Q !== dut.data_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25894 gold=%b dut=%b", gold._49045_.Q, dut.data_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49046_.Q !== dut.data_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25895 gold=%b dut=%b", gold._49046_.Q, dut.data_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49047_.Q !== dut.data_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25896 gold=%b dut=%b", gold._49047_.Q, dut.data_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49048_.Q !== dut.data_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25897 gold=%b dut=%b", gold._49048_.Q, dut.data_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49049_.Q !== dut.data_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25898 gold=%b dut=%b", gold._49049_.Q, dut.data_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49050_.Q !== dut.data_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25899 gold=%b dut=%b", gold._49050_.Q, dut.data_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49051_.Q !== dut.data_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25900 gold=%b dut=%b", gold._49051_.Q, dut.data_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49052_.Q !== dut.data_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25901 gold=%b dut=%b", gold._49052_.Q, dut.data_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49053_.Q !== dut.data_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25902 gold=%b dut=%b", gold._49053_.Q, dut.data_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49054_.Q !== dut.data_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25903 gold=%b dut=%b", gold._49054_.Q, dut.data_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49055_.Q !== dut.data_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25904 gold=%b dut=%b", gold._49055_.Q, dut.data_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49056_.Q !== dut.data_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25905 gold=%b dut=%b", gold._49056_.Q, dut.data_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49057_.Q !== dut.data_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25906 gold=%b dut=%b", gold._49057_.Q, dut.data_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49058_.Q !== dut.data_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25907 gold=%b dut=%b", gold._49058_.Q, dut.data_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49059_.Q !== dut.data_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25908 gold=%b dut=%b", gold._49059_.Q, dut.data_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49060_.Q !== dut.data_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25909 gold=%b dut=%b", gold._49060_.Q, dut.data_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49061_.Q !== dut.data_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25910 gold=%b dut=%b", gold._49061_.Q, dut.data_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49062_.Q !== dut.wide_data_reg_1[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25911 gold=%b dut=%b", gold._49062_.Q, dut.wide_data_reg_1[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48999_.Q !== dut.address_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25912 gold=%b dut=%b", gold._48999_.Q, dut.address_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49000_.Q !== dut.address_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25913 gold=%b dut=%b", gold._49000_.Q, dut.address_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49001_.Q !== dut.address_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25914 gold=%b dut=%b", gold._49001_.Q, dut.address_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49002_.Q !== dut.address_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25915 gold=%b dut=%b", gold._49002_.Q, dut.address_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49003_.Q !== dut.address_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25916 gold=%b dut=%b", gold._49003_.Q, dut.address_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49004_.Q !== dut.address_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25917 gold=%b dut=%b", gold._49004_.Q, dut.address_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49005_.Q !== dut.address_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25918 gold=%b dut=%b", gold._49005_.Q, dut.address_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49006_.Q !== dut.address_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25919 gold=%b dut=%b", gold._49006_.Q, dut.address_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49007_.Q !== dut.address_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25920 gold=%b dut=%b", gold._49007_.Q, dut.address_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49008_.Q !== dut.address_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25921 gold=%b dut=%b", gold._49008_.Q, dut.address_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49009_.Q !== dut.address_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25922 gold=%b dut=%b", gold._49009_.Q, dut.address_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49010_.Q !== dut.address_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25923 gold=%b dut=%b", gold._49010_.Q, dut.address_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49011_.Q !== dut.address_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25924 gold=%b dut=%b", gold._49011_.Q, dut.address_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49012_.Q !== dut.address_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25925 gold=%b dut=%b", gold._49012_.Q, dut.address_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49013_.Q !== dut.address_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25926 gold=%b dut=%b", gold._49013_.Q, dut.address_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49014_.Q !== dut.address_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25927 gold=%b dut=%b", gold._49014_.Q, dut.address_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49015_.Q !== dut.address_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25928 gold=%b dut=%b", gold._49015_.Q, dut.address_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49016_.Q !== dut.address_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25929 gold=%b dut=%b", gold._49016_.Q, dut.address_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49017_.Q !== dut.address_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25930 gold=%b dut=%b", gold._49017_.Q, dut.address_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49018_.Q !== dut.address_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25931 gold=%b dut=%b", gold._49018_.Q, dut.address_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49019_.Q !== dut.address_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25932 gold=%b dut=%b", gold._49019_.Q, dut.address_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49020_.Q !== dut.address_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25933 gold=%b dut=%b", gold._49020_.Q, dut.address_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49021_.Q !== dut.address_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25934 gold=%b dut=%b", gold._49021_.Q, dut.address_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49022_.Q !== dut.address_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25935 gold=%b dut=%b", gold._49022_.Q, dut.address_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49023_.Q !== dut.address_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25936 gold=%b dut=%b", gold._49023_.Q, dut.address_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49024_.Q !== dut.address_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25937 gold=%b dut=%b", gold._49024_.Q, dut.address_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49025_.Q !== dut.address_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25938 gold=%b dut=%b", gold._49025_.Q, dut.address_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49026_.Q !== dut.address_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25939 gold=%b dut=%b", gold._49026_.Q, dut.address_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49027_.Q !== dut.address_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25940 gold=%b dut=%b", gold._49027_.Q, dut.address_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49028_.Q !== dut.address_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25941 gold=%b dut=%b", gold._49028_.Q, dut.address_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49029_.Q !== dut.address_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25942 gold=%b dut=%b", gold._49029_.Q, dut.address_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49030_.Q !== dut.control_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25943 gold=%b dut=%b", gold._49030_.Q, dut.control_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49608_.Q !== dut.data_register_b[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25944 gold=%b dut=%b", gold._49608_.Q, dut.data_register_b[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49609_.Q !== dut.data_register_b[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25945 gold=%b dut=%b", gold._49609_.Q, dut.data_register_b[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49610_.Q !== dut.data_register_b[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25946 gold=%b dut=%b", gold._49610_.Q, dut.data_register_b[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49611_.Q !== dut.data_register_b[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25947 gold=%b dut=%b", gold._49611_.Q, dut.data_register_b[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49612_.Q !== dut.data_register_b[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25948 gold=%b dut=%b", gold._49612_.Q, dut.data_register_b[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49613_.Q !== dut.data_register_b[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25949 gold=%b dut=%b", gold._49613_.Q, dut.data_register_b[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49614_.Q !== dut.data_register_b[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25950 gold=%b dut=%b", gold._49614_.Q, dut.data_register_b[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49615_.Q !== dut.data_register_b[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25951 gold=%b dut=%b", gold._49615_.Q, dut.data_register_b[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49616_.Q !== dut.data_register_b[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25952 gold=%b dut=%b", gold._49616_.Q, dut.data_register_b[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49617_.Q !== dut.data_register_b[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25953 gold=%b dut=%b", gold._49617_.Q, dut.data_register_b[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49618_.Q !== dut.data_register_b[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25954 gold=%b dut=%b", gold._49618_.Q, dut.data_register_b[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49619_.Q !== dut.data_register_b[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25955 gold=%b dut=%b", gold._49619_.Q, dut.data_register_b[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49620_.Q !== dut.data_register_b[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25956 gold=%b dut=%b", gold._49620_.Q, dut.data_register_b[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49621_.Q !== dut.data_register_b[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25957 gold=%b dut=%b", gold._49621_.Q, dut.data_register_b[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49622_.Q !== dut.data_register_b[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25958 gold=%b dut=%b", gold._49622_.Q, dut.data_register_b[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49623_.Q !== dut.data_register_b[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25959 gold=%b dut=%b", gold._49623_.Q, dut.data_register_b[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49624_.Q !== dut.data_register_b[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25960 gold=%b dut=%b", gold._49624_.Q, dut.data_register_b[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49625_.Q !== dut.data_register_b[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25961 gold=%b dut=%b", gold._49625_.Q, dut.data_register_b[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49626_.Q !== dut.data_register_b[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25962 gold=%b dut=%b", gold._49626_.Q, dut.data_register_b[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49627_.Q !== dut.data_register_b[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25963 gold=%b dut=%b", gold._49627_.Q, dut.data_register_b[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49628_.Q !== dut.data_register_b[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25964 gold=%b dut=%b", gold._49628_.Q, dut.data_register_b[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49629_.Q !== dut.data_register_b[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25965 gold=%b dut=%b", gold._49629_.Q, dut.data_register_b[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49630_.Q !== dut.data_register_b[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25966 gold=%b dut=%b", gold._49630_.Q, dut.data_register_b[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49631_.Q !== dut.data_register_b[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25967 gold=%b dut=%b", gold._49631_.Q, dut.data_register_b[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49632_.Q !== dut.data_register_b[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25968 gold=%b dut=%b", gold._49632_.Q, dut.data_register_b[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49633_.Q !== dut.data_register_b[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25969 gold=%b dut=%b", gold._49633_.Q, dut.data_register_b[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49634_.Q !== dut.data_register_b[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25970 gold=%b dut=%b", gold._49634_.Q, dut.data_register_b[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49635_.Q !== dut.data_register_b[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25971 gold=%b dut=%b", gold._49635_.Q, dut.data_register_b[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49636_.Q !== dut.data_register_b[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25972 gold=%b dut=%b", gold._49636_.Q, dut.data_register_b[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49637_.Q !== dut.data_register_b[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25973 gold=%b dut=%b", gold._49637_.Q, dut.data_register_b[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49638_.Q !== dut.data_register_b[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25974 gold=%b dut=%b", gold._49638_.Q, dut.data_register_b[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49639_.Q !== dut.data_register_b[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25975 gold=%b dut=%b", gold._49639_.Q, dut.data_register_b[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48967_.Q !== dut.data_reg_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25976 gold=%b dut=%b", gold._48967_.Q, dut.data_reg_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48968_.Q !== dut.data_reg_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25977 gold=%b dut=%b", gold._48968_.Q, dut.data_reg_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48969_.Q !== dut.data_reg_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25978 gold=%b dut=%b", gold._48969_.Q, dut.data_reg_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48970_.Q !== dut.data_reg_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25979 gold=%b dut=%b", gold._48970_.Q, dut.data_reg_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48971_.Q !== dut.data_reg_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25980 gold=%b dut=%b", gold._48971_.Q, dut.data_reg_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48972_.Q !== dut.data_reg_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25981 gold=%b dut=%b", gold._48972_.Q, dut.data_reg_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48973_.Q !== dut.data_reg_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25982 gold=%b dut=%b", gold._48973_.Q, dut.data_reg_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48974_.Q !== dut.data_reg_0[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25983 gold=%b dut=%b", gold._48974_.Q, dut.data_reg_0[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48975_.Q !== dut.data_reg_0[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25984 gold=%b dut=%b", gold._48975_.Q, dut.data_reg_0[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48976_.Q !== dut.data_reg_0[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25985 gold=%b dut=%b", gold._48976_.Q, dut.data_reg_0[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48977_.Q !== dut.data_reg_0[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25986 gold=%b dut=%b", gold._48977_.Q, dut.data_reg_0[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48978_.Q !== dut.data_reg_0[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25987 gold=%b dut=%b", gold._48978_.Q, dut.data_reg_0[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48979_.Q !== dut.data_reg_0[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25988 gold=%b dut=%b", gold._48979_.Q, dut.data_reg_0[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48980_.Q !== dut.data_reg_0[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25989 gold=%b dut=%b", gold._48980_.Q, dut.data_reg_0[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48981_.Q !== dut.data_reg_0[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25990 gold=%b dut=%b", gold._48981_.Q, dut.data_reg_0[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48982_.Q !== dut.data_reg_0[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25991 gold=%b dut=%b", gold._48982_.Q, dut.data_reg_0[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48983_.Q !== dut.data_reg_0[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25992 gold=%b dut=%b", gold._48983_.Q, dut.data_reg_0[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48984_.Q !== dut.data_reg_0[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25993 gold=%b dut=%b", gold._48984_.Q, dut.data_reg_0[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48985_.Q !== dut.data_reg_0[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25994 gold=%b dut=%b", gold._48985_.Q, dut.data_reg_0[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48986_.Q !== dut.data_reg_0[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25995 gold=%b dut=%b", gold._48986_.Q, dut.data_reg_0[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48987_.Q !== dut.data_reg_0[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25996 gold=%b dut=%b", gold._48987_.Q, dut.data_reg_0[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48988_.Q !== dut.data_reg_0[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25997 gold=%b dut=%b", gold._48988_.Q, dut.data_reg_0[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48989_.Q !== dut.data_reg_0[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25998 gold=%b dut=%b", gold._48989_.Q, dut.data_reg_0[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48990_.Q !== dut.data_reg_0[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25999 gold=%b dut=%b", gold._48990_.Q, dut.data_reg_0[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48991_.Q !== dut.data_reg_0[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26000 gold=%b dut=%b", gold._48991_.Q, dut.data_reg_0[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48992_.Q !== dut.data_reg_0[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26001 gold=%b dut=%b", gold._48992_.Q, dut.data_reg_0[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48993_.Q !== dut.data_reg_0[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26002 gold=%b dut=%b", gold._48993_.Q, dut.data_reg_0[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48994_.Q !== dut.data_reg_0[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26003 gold=%b dut=%b", gold._48994_.Q, dut.data_reg_0[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48995_.Q !== dut.data_reg_0[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26004 gold=%b dut=%b", gold._48995_.Q, dut.data_reg_0[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48996_.Q !== dut.data_reg_0[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26005 gold=%b dut=%b", gold._48996_.Q, dut.data_reg_0[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48997_.Q !== dut.data_reg_0[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26006 gold=%b dut=%b", gold._48997_.Q, dut.data_reg_0[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48998_.Q !== dut.data_reg_0[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26007 gold=%b dut=%b", gold._48998_.Q, dut.data_reg_0[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48935_.Q !== dut.narrow_data_reg_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26008 gold=%b dut=%b", gold._48935_.Q, dut.narrow_data_reg_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48936_.Q !== dut.narrow_data_reg_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26009 gold=%b dut=%b", gold._48936_.Q, dut.narrow_data_reg_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48937_.Q !== dut.narrow_data_reg_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26010 gold=%b dut=%b", gold._48937_.Q, dut.narrow_data_reg_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48938_.Q !== dut.narrow_data_reg_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26011 gold=%b dut=%b", gold._48938_.Q, dut.narrow_data_reg_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48939_.Q !== dut.narrow_data_reg_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26012 gold=%b dut=%b", gold._48939_.Q, dut.narrow_data_reg_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48940_.Q !== dut.narrow_data_reg_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26013 gold=%b dut=%b", gold._48940_.Q, dut.narrow_data_reg_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48941_.Q !== dut.narrow_data_reg_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26014 gold=%b dut=%b", gold._48941_.Q, dut.narrow_data_reg_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48942_.Q !== dut.narrow_data_reg_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26015 gold=%b dut=%b", gold._48942_.Q, dut.narrow_data_reg_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48943_.Q !== dut.narrow_data_reg_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26016 gold=%b dut=%b", gold._48943_.Q, dut.narrow_data_reg_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48944_.Q !== dut.narrow_data_reg_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26017 gold=%b dut=%b", gold._48944_.Q, dut.narrow_data_reg_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48945_.Q !== dut.narrow_data_reg_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26018 gold=%b dut=%b", gold._48945_.Q, dut.narrow_data_reg_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48946_.Q !== dut.narrow_data_reg_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26019 gold=%b dut=%b", gold._48946_.Q, dut.narrow_data_reg_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48947_.Q !== dut.narrow_data_reg_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26020 gold=%b dut=%b", gold._48947_.Q, dut.narrow_data_reg_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48948_.Q !== dut.narrow_data_reg_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26021 gold=%b dut=%b", gold._48948_.Q, dut.narrow_data_reg_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48949_.Q !== dut.narrow_data_reg_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26022 gold=%b dut=%b", gold._48949_.Q, dut.narrow_data_reg_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48950_.Q !== dut.narrow_data_reg_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26023 gold=%b dut=%b", gold._48950_.Q, dut.narrow_data_reg_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48951_.Q !== dut.narrow_data_reg_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26024 gold=%b dut=%b", gold._48951_.Q, dut.narrow_data_reg_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48952_.Q !== dut.narrow_data_reg_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26025 gold=%b dut=%b", gold._48952_.Q, dut.narrow_data_reg_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48953_.Q !== dut.narrow_data_reg_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26026 gold=%b dut=%b", gold._48953_.Q, dut.narrow_data_reg_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48954_.Q !== dut.narrow_data_reg_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26027 gold=%b dut=%b", gold._48954_.Q, dut.narrow_data_reg_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48955_.Q !== dut.narrow_data_reg_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26028 gold=%b dut=%b", gold._48955_.Q, dut.narrow_data_reg_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48956_.Q !== dut.narrow_data_reg_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26029 gold=%b dut=%b", gold._48956_.Q, dut.narrow_data_reg_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48957_.Q !== dut.narrow_data_reg_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26030 gold=%b dut=%b", gold._48957_.Q, dut.narrow_data_reg_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48958_.Q !== dut.narrow_data_reg_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26031 gold=%b dut=%b", gold._48958_.Q, dut.narrow_data_reg_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48959_.Q !== dut.narrow_data_reg_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26032 gold=%b dut=%b", gold._48959_.Q, dut.narrow_data_reg_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48960_.Q !== dut.narrow_data_reg_2[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26033 gold=%b dut=%b", gold._48960_.Q, dut.narrow_data_reg_2[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48961_.Q !== dut.narrow_data_reg_2[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26034 gold=%b dut=%b", gold._48961_.Q, dut.narrow_data_reg_2[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48962_.Q !== dut.narrow_data_reg_2[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26035 gold=%b dut=%b", gold._48962_.Q, dut.narrow_data_reg_2[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48963_.Q !== dut.narrow_data_reg_2[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26036 gold=%b dut=%b", gold._48963_.Q, dut.narrow_data_reg_2[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48964_.Q !== dut.narrow_data_reg_2[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26037 gold=%b dut=%b", gold._48964_.Q, dut.narrow_data_reg_2[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48965_.Q !== dut.narrow_data_reg_2[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26038 gold=%b dut=%b", gold._48965_.Q, dut.narrow_data_reg_2[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48966_.Q !== dut.narrow_data_reg_2[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26039 gold=%b dut=%b", gold._48966_.Q, dut.narrow_data_reg_2[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48903_.Q !== dut.wide_data_reg_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26040 gold=%b dut=%b", gold._48903_.Q, dut.wide_data_reg_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48904_.Q !== dut.wide_data_reg_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26041 gold=%b dut=%b", gold._48904_.Q, dut.wide_data_reg_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48905_.Q !== dut.wide_data_reg_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26042 gold=%b dut=%b", gold._48905_.Q, dut.wide_data_reg_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48906_.Q !== dut.wide_data_reg_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26043 gold=%b dut=%b", gold._48906_.Q, dut.wide_data_reg_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48907_.Q !== dut.wide_data_reg_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26044 gold=%b dut=%b", gold._48907_.Q, dut.wide_data_reg_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48908_.Q !== dut.wide_data_reg_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26045 gold=%b dut=%b", gold._48908_.Q, dut.wide_data_reg_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48909_.Q !== dut.wide_data_reg_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26046 gold=%b dut=%b", gold._48909_.Q, dut.wide_data_reg_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48910_.Q !== dut.wide_data_reg_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26047 gold=%b dut=%b", gold._48910_.Q, dut.wide_data_reg_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48911_.Q !== dut.wide_data_reg_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26048 gold=%b dut=%b", gold._48911_.Q, dut.wide_data_reg_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48912_.Q !== dut.wide_data_reg_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26049 gold=%b dut=%b", gold._48912_.Q, dut.wide_data_reg_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48913_.Q !== dut.wide_data_reg_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26050 gold=%b dut=%b", gold._48913_.Q, dut.wide_data_reg_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48914_.Q !== dut.wide_data_reg_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26051 gold=%b dut=%b", gold._48914_.Q, dut.wide_data_reg_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48915_.Q !== dut.wide_data_reg_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26052 gold=%b dut=%b", gold._48915_.Q, dut.wide_data_reg_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48916_.Q !== dut.wide_data_reg_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26053 gold=%b dut=%b", gold._48916_.Q, dut.wide_data_reg_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48917_.Q !== dut.wide_data_reg_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26054 gold=%b dut=%b", gold._48917_.Q, dut.wide_data_reg_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48918_.Q !== dut.wide_data_reg_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26055 gold=%b dut=%b", gold._48918_.Q, dut.wide_data_reg_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48919_.Q !== dut.wide_data_reg_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26056 gold=%b dut=%b", gold._48919_.Q, dut.wide_data_reg_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48920_.Q !== dut.wide_data_reg_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26057 gold=%b dut=%b", gold._48920_.Q, dut.wide_data_reg_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48921_.Q !== dut.wide_data_reg_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26058 gold=%b dut=%b", gold._48921_.Q, dut.wide_data_reg_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48922_.Q !== dut.wide_data_reg_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26059 gold=%b dut=%b", gold._48922_.Q, dut.wide_data_reg_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48923_.Q !== dut.wide_data_reg_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26060 gold=%b dut=%b", gold._48923_.Q, dut.wide_data_reg_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48924_.Q !== dut.wide_data_reg_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26061 gold=%b dut=%b", gold._48924_.Q, dut.wide_data_reg_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48925_.Q !== dut.wide_data_reg_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26062 gold=%b dut=%b", gold._48925_.Q, dut.wide_data_reg_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48926_.Q !== dut.wide_data_reg_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26063 gold=%b dut=%b", gold._48926_.Q, dut.wide_data_reg_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48927_.Q !== dut.wide_data_reg_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26064 gold=%b dut=%b", gold._48927_.Q, dut.wide_data_reg_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48928_.Q !== dut.wide_data_reg_2[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26065 gold=%b dut=%b", gold._48928_.Q, dut.wide_data_reg_2[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48929_.Q !== dut.wide_data_reg_2[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26066 gold=%b dut=%b", gold._48929_.Q, dut.wide_data_reg_2[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48930_.Q !== dut.wide_data_reg_2[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26067 gold=%b dut=%b", gold._48930_.Q, dut.wide_data_reg_2[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48931_.Q !== dut.wide_data_reg_2[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26068 gold=%b dut=%b", gold._48931_.Q, dut.wide_data_reg_2[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48932_.Q !== dut.wide_data_reg_2[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26069 gold=%b dut=%b", gold._48932_.Q, dut.wide_data_reg_2[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48933_.Q !== dut.wide_data_reg_2[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26070 gold=%b dut=%b", gold._48933_.Q, dut.wide_data_reg_2[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48934_.Q !== dut.wide_data_reg_2[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26071 gold=%b dut=%b", gold._48934_.Q, dut.wide_data_reg_2[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48871_.Q !== dut.arithmetic_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26072 gold=%b dut=%b", gold._48871_.Q, dut.arithmetic_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48872_.Q !== dut.arithmetic_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26073 gold=%b dut=%b", gold._48872_.Q, dut.arithmetic_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48873_.Q !== dut.arithmetic_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26074 gold=%b dut=%b", gold._48873_.Q, dut.arithmetic_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48874_.Q !== dut.arithmetic_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26075 gold=%b dut=%b", gold._48874_.Q, dut.arithmetic_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48875_.Q !== dut.arithmetic_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26076 gold=%b dut=%b", gold._48875_.Q, dut.arithmetic_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48876_.Q !== dut.arithmetic_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26077 gold=%b dut=%b", gold._48876_.Q, dut.arithmetic_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48877_.Q !== dut.arithmetic_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26078 gold=%b dut=%b", gold._48877_.Q, dut.arithmetic_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48878_.Q !== dut.arithmetic_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26079 gold=%b dut=%b", gold._48878_.Q, dut.arithmetic_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48879_.Q !== dut.arithmetic_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26080 gold=%b dut=%b", gold._48879_.Q, dut.arithmetic_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48880_.Q !== dut.arithmetic_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26081 gold=%b dut=%b", gold._48880_.Q, dut.arithmetic_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48881_.Q !== dut.arithmetic_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26082 gold=%b dut=%b", gold._48881_.Q, dut.arithmetic_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48882_.Q !== dut.arithmetic_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26083 gold=%b dut=%b", gold._48882_.Q, dut.arithmetic_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48883_.Q !== dut.arithmetic_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26084 gold=%b dut=%b", gold._48883_.Q, dut.arithmetic_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48884_.Q !== dut.arithmetic_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26085 gold=%b dut=%b", gold._48884_.Q, dut.arithmetic_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48885_.Q !== dut.arithmetic_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26086 gold=%b dut=%b", gold._48885_.Q, dut.arithmetic_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48886_.Q !== dut.arithmetic_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26087 gold=%b dut=%b", gold._48886_.Q, dut.arithmetic_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48887_.Q !== dut.arithmetic_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26088 gold=%b dut=%b", gold._48887_.Q, dut.arithmetic_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48888_.Q !== dut.arithmetic_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26089 gold=%b dut=%b", gold._48888_.Q, dut.arithmetic_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48889_.Q !== dut.arithmetic_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26090 gold=%b dut=%b", gold._48889_.Q, dut.arithmetic_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48890_.Q !== dut.arithmetic_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26091 gold=%b dut=%b", gold._48890_.Q, dut.arithmetic_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48891_.Q !== dut.arithmetic_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26092 gold=%b dut=%b", gold._48891_.Q, dut.arithmetic_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48892_.Q !== dut.arithmetic_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26093 gold=%b dut=%b", gold._48892_.Q, dut.arithmetic_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48893_.Q !== dut.arithmetic_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26094 gold=%b dut=%b", gold._48893_.Q, dut.arithmetic_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48894_.Q !== dut.arithmetic_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26095 gold=%b dut=%b", gold._48894_.Q, dut.arithmetic_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48895_.Q !== dut.arithmetic_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26096 gold=%b dut=%b", gold._48895_.Q, dut.arithmetic_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48896_.Q !== dut.arithmetic_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26097 gold=%b dut=%b", gold._48896_.Q, dut.arithmetic_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48897_.Q !== dut.arithmetic_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26098 gold=%b dut=%b", gold._48897_.Q, dut.arithmetic_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48898_.Q !== dut.arithmetic_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26099 gold=%b dut=%b", gold._48898_.Q, dut.arithmetic_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48899_.Q !== dut.arithmetic_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26100 gold=%b dut=%b", gold._48899_.Q, dut.arithmetic_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48900_.Q !== dut.arithmetic_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26101 gold=%b dut=%b", gold._48900_.Q, dut.arithmetic_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48901_.Q !== dut.arithmetic_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26102 gold=%b dut=%b", gold._48901_.Q, dut.arithmetic_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48902_.Q !== dut.status_flag_3) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26103 gold=%b dut=%b", gold._48902_.Q, dut.status_flag_3);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48839_.Q !== dut.cycle_counter_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26104 gold=%b dut=%b", gold._48839_.Q, dut.cycle_counter_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48840_.Q !== dut.cycle_counter_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26105 gold=%b dut=%b", gold._48840_.Q, dut.cycle_counter_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48841_.Q !== dut.cycle_counter_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26106 gold=%b dut=%b", gold._48841_.Q, dut.cycle_counter_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48842_.Q !== dut.cycle_counter_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26107 gold=%b dut=%b", gold._48842_.Q, dut.cycle_counter_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48843_.Q !== dut.cycle_counter_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26108 gold=%b dut=%b", gold._48843_.Q, dut.cycle_counter_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48844_.Q !== dut.cycle_counter_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26109 gold=%b dut=%b", gold._48844_.Q, dut.cycle_counter_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48845_.Q !== dut.cycle_counter_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26110 gold=%b dut=%b", gold._48845_.Q, dut.cycle_counter_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48846_.Q !== dut.cycle_counter_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26111 gold=%b dut=%b", gold._48846_.Q, dut.cycle_counter_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48847_.Q !== dut.cycle_counter_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26112 gold=%b dut=%b", gold._48847_.Q, dut.cycle_counter_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48848_.Q !== dut.cycle_counter_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26113 gold=%b dut=%b", gold._48848_.Q, dut.cycle_counter_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48849_.Q !== dut.cycle_counter_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26114 gold=%b dut=%b", gold._48849_.Q, dut.cycle_counter_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48850_.Q !== dut.cycle_counter_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26115 gold=%b dut=%b", gold._48850_.Q, dut.cycle_counter_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48851_.Q !== dut.cycle_counter_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26116 gold=%b dut=%b", gold._48851_.Q, dut.cycle_counter_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48852_.Q !== dut.cycle_counter_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26117 gold=%b dut=%b", gold._48852_.Q, dut.cycle_counter_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48853_.Q !== dut.mode_data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26118 gold=%b dut=%b", gold._48853_.Q, dut.mode_data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48854_.Q !== dut.mode_data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26119 gold=%b dut=%b", gold._48854_.Q, dut.mode_data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48855_.Q !== dut.mode_data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26120 gold=%b dut=%b", gold._48855_.Q, dut.mode_data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48856_.Q !== dut.mode_data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26121 gold=%b dut=%b", gold._48856_.Q, dut.mode_data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48857_.Q !== dut.mode_data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26122 gold=%b dut=%b", gold._48857_.Q, dut.mode_data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48858_.Q !== dut.mode_data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26123 gold=%b dut=%b", gold._48858_.Q, dut.mode_data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48859_.Q !== dut.mode_data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26124 gold=%b dut=%b", gold._48859_.Q, dut.mode_data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48860_.Q !== dut.mode_data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26125 gold=%b dut=%b", gold._48860_.Q, dut.mode_data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48861_.Q !== dut.mode_data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26126 gold=%b dut=%b", gold._48861_.Q, dut.mode_data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48862_.Q !== dut.control_state_3[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26127 gold=%b dut=%b", gold._48862_.Q, dut.control_state_3[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48863_.Q !== dut.control_state_3[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26128 gold=%b dut=%b", gold._48863_.Q, dut.control_state_3[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48864_.Q !== dut.control_state_3[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26129 gold=%b dut=%b", gold._48864_.Q, dut.control_state_3[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48865_.Q !== dut.control_state_3[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26130 gold=%b dut=%b", gold._48865_.Q, dut.control_state_3[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48866_.Q !== dut.control_state_3[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26131 gold=%b dut=%b", gold._48866_.Q, dut.control_state_3[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48867_.Q !== dut.control_state_3[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26132 gold=%b dut=%b", gold._48867_.Q, dut.control_state_3[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48868_.Q !== dut.control_state_3[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26133 gold=%b dut=%b", gold._48868_.Q, dut.control_state_3[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48869_.Q !== dut.control_state_3[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26134 gold=%b dut=%b", gold._48869_.Q, dut.control_state_3[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48870_.Q !== dut.control_state_3[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26135 gold=%b dut=%b", gold._48870_.Q, dut.control_state_3[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48807_.Q !== dut.adder_result_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26136 gold=%b dut=%b", gold._48807_.Q, dut.adder_result_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48808_.Q !== dut.adder_result_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26137 gold=%b dut=%b", gold._48808_.Q, dut.adder_result_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48809_.Q !== dut.adder_result_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26138 gold=%b dut=%b", gold._48809_.Q, dut.adder_result_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48810_.Q !== dut.adder_result_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26139 gold=%b dut=%b", gold._48810_.Q, dut.adder_result_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48811_.Q !== dut.adder_result_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26140 gold=%b dut=%b", gold._48811_.Q, dut.adder_result_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48812_.Q !== dut.adder_result_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26141 gold=%b dut=%b", gold._48812_.Q, dut.adder_result_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48813_.Q !== dut.adder_result_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26142 gold=%b dut=%b", gold._48813_.Q, dut.adder_result_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48814_.Q !== dut.adder_result_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26143 gold=%b dut=%b", gold._48814_.Q, dut.adder_result_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48815_.Q !== dut.adder_result_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26144 gold=%b dut=%b", gold._48815_.Q, dut.adder_result_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48816_.Q !== dut.adder_result_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26145 gold=%b dut=%b", gold._48816_.Q, dut.adder_result_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48817_.Q !== dut.adder_result_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26146 gold=%b dut=%b", gold._48817_.Q, dut.adder_result_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48818_.Q !== dut.adder_result_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26147 gold=%b dut=%b", gold._48818_.Q, dut.adder_result_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48819_.Q !== dut.adder_result_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26148 gold=%b dut=%b", gold._48819_.Q, dut.adder_result_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48820_.Q !== dut.adder_result_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26149 gold=%b dut=%b", gold._48820_.Q, dut.adder_result_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48821_.Q !== dut.adder_result_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26150 gold=%b dut=%b", gold._48821_.Q, dut.adder_result_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48822_.Q !== dut.cycle_counter_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26151 gold=%b dut=%b", gold._48822_.Q, dut.cycle_counter_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48823_.Q !== dut.cycle_counter_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26152 gold=%b dut=%b", gold._48823_.Q, dut.cycle_counter_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48824_.Q !== dut.cycle_counter_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26153 gold=%b dut=%b", gold._48824_.Q, dut.cycle_counter_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48825_.Q !== dut.cycle_counter_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26154 gold=%b dut=%b", gold._48825_.Q, dut.cycle_counter_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48826_.Q !== dut.cycle_counter_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26155 gold=%b dut=%b", gold._48826_.Q, dut.cycle_counter_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48827_.Q !== dut.cycle_counter_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26156 gold=%b dut=%b", gold._48827_.Q, dut.cycle_counter_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48828_.Q !== dut.cycle_counter_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26157 gold=%b dut=%b", gold._48828_.Q, dut.cycle_counter_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48829_.Q !== dut.cycle_counter_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26158 gold=%b dut=%b", gold._48829_.Q, dut.cycle_counter_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48830_.Q !== dut.cycle_counter_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26159 gold=%b dut=%b", gold._48830_.Q, dut.cycle_counter_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48831_.Q !== dut.cycle_counter_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26160 gold=%b dut=%b", gold._48831_.Q, dut.cycle_counter_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48832_.Q !== dut.cycle_counter_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26161 gold=%b dut=%b", gold._48832_.Q, dut.cycle_counter_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48833_.Q !== dut.cycle_counter_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26162 gold=%b dut=%b", gold._48833_.Q, dut.cycle_counter_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48834_.Q !== dut.cycle_counter_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26163 gold=%b dut=%b", gold._48834_.Q, dut.cycle_counter_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48835_.Q !== dut.cycle_counter_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26164 gold=%b dut=%b", gold._48835_.Q, dut.cycle_counter_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48836_.Q !== dut.cycle_counter_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26165 gold=%b dut=%b", gold._48836_.Q, dut.cycle_counter_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48837_.Q !== dut.cycle_counter_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26166 gold=%b dut=%b", gold._48837_.Q, dut.cycle_counter_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48838_.Q !== dut.control_flag_1) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26167 gold=%b dut=%b", gold._48838_.Q, dut.control_flag_1);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48775_.Q !== dut.fsm_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26168 gold=%b dut=%b", gold._48775_.Q, dut.fsm_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48776_.Q !== dut.fsm_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26169 gold=%b dut=%b", gold._48776_.Q, dut.fsm_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48777_.Q !== dut.fsm_state[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26170 gold=%b dut=%b", gold._48777_.Q, dut.fsm_state[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48778_.Q !== dut.fsm_state[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26171 gold=%b dut=%b", gold._48778_.Q, dut.fsm_state[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48779_.Q !== dut.fsm_state[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26172 gold=%b dut=%b", gold._48779_.Q, dut.fsm_state[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48780_.Q !== dut.fsm_state[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26173 gold=%b dut=%b", gold._48780_.Q, dut.fsm_state[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48781_.Q !== dut.fsm_state[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26174 gold=%b dut=%b", gold._48781_.Q, dut.fsm_state[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48782_.Q !== dut.pipeline_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26175 gold=%b dut=%b", gold._48782_.Q, dut.pipeline_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48783_.Q !== dut.pipeline_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26176 gold=%b dut=%b", gold._48783_.Q, dut.pipeline_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48784_.Q !== dut.pipeline_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26177 gold=%b dut=%b", gold._48784_.Q, dut.pipeline_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48785_.Q !== dut.pipeline_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26178 gold=%b dut=%b", gold._48785_.Q, dut.pipeline_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48786_.Q !== dut.pipeline_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26179 gold=%b dut=%b", gold._48786_.Q, dut.pipeline_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48787_.Q !== dut.pipeline_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26180 gold=%b dut=%b", gold._48787_.Q, dut.pipeline_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48788_.Q !== dut.pipeline_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26181 gold=%b dut=%b", gold._48788_.Q, dut.pipeline_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48789_.Q !== dut.pipeline_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26182 gold=%b dut=%b", gold._48789_.Q, dut.pipeline_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48790_.Q !== dut.pipeline_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26183 gold=%b dut=%b", gold._48790_.Q, dut.pipeline_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48791_.Q !== dut.pipeline_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26184 gold=%b dut=%b", gold._48791_.Q, dut.pipeline_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48792_.Q !== dut.pipeline_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26185 gold=%b dut=%b", gold._48792_.Q, dut.pipeline_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48793_.Q !== dut.pipeline_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26186 gold=%b dut=%b", gold._48793_.Q, dut.pipeline_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48794_.Q !== dut.pipeline_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26187 gold=%b dut=%b", gold._48794_.Q, dut.pipeline_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48795_.Q !== dut.pipeline_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26188 gold=%b dut=%b", gold._48795_.Q, dut.pipeline_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48796_.Q !== dut.pipeline_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26189 gold=%b dut=%b", gold._48796_.Q, dut.pipeline_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48797_.Q !== dut.pipeline_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26190 gold=%b dut=%b", gold._48797_.Q, dut.pipeline_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48798_.Q !== dut.pipeline_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26191 gold=%b dut=%b", gold._48798_.Q, dut.pipeline_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48799_.Q !== dut.pipeline_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26192 gold=%b dut=%b", gold._48799_.Q, dut.pipeline_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48800_.Q !== dut.pipeline_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26193 gold=%b dut=%b", gold._48800_.Q, dut.pipeline_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48801_.Q !== dut.pipeline_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26194 gold=%b dut=%b", gold._48801_.Q, dut.pipeline_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48802_.Q !== dut.pipeline_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26195 gold=%b dut=%b", gold._48802_.Q, dut.pipeline_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48803_.Q !== dut.pipeline_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26196 gold=%b dut=%b", gold._48803_.Q, dut.pipeline_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48804_.Q !== dut.pipeline_data_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26197 gold=%b dut=%b", gold._48804_.Q, dut.pipeline_data_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48805_.Q !== dut.pipeline_data_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26198 gold=%b dut=%b", gold._48805_.Q, dut.pipeline_data_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48806_.Q !== dut.pipeline_data_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26199 gold=%b dut=%b", gold._48806_.Q, dut.pipeline_data_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48743_.Q !== dut.wide_data_reg_3[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26200 gold=%b dut=%b", gold._48743_.Q, dut.wide_data_reg_3[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48744_.Q !== dut.wide_data_reg_3[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26201 gold=%b dut=%b", gold._48744_.Q, dut.wide_data_reg_3[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48745_.Q !== dut.wide_data_reg_3[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26202 gold=%b dut=%b", gold._48745_.Q, dut.wide_data_reg_3[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48746_.Q !== dut.wide_data_reg_3[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26203 gold=%b dut=%b", gold._48746_.Q, dut.wide_data_reg_3[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48747_.Q !== dut.wide_data_reg_3[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26204 gold=%b dut=%b", gold._48747_.Q, dut.wide_data_reg_3[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48748_.Q !== dut.wide_data_reg_3[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26205 gold=%b dut=%b", gold._48748_.Q, dut.wide_data_reg_3[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48749_.Q !== dut.wide_data_reg_3[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26206 gold=%b dut=%b", gold._48749_.Q, dut.wide_data_reg_3[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48750_.Q !== dut.wide_data_reg_3[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26207 gold=%b dut=%b", gold._48750_.Q, dut.wide_data_reg_3[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48751_.Q !== dut.wide_data_reg_3[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26208 gold=%b dut=%b", gold._48751_.Q, dut.wide_data_reg_3[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48752_.Q !== dut.wide_data_reg_3[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26209 gold=%b dut=%b", gold._48752_.Q, dut.wide_data_reg_3[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48753_.Q !== dut.wide_data_reg_3[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26210 gold=%b dut=%b", gold._48753_.Q, dut.wide_data_reg_3[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48754_.Q !== dut.wide_data_reg_3[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26211 gold=%b dut=%b", gold._48754_.Q, dut.wide_data_reg_3[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48755_.Q !== dut.wide_data_reg_3[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26212 gold=%b dut=%b", gold._48755_.Q, dut.wide_data_reg_3[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48756_.Q !== dut.wide_data_reg_3[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26213 gold=%b dut=%b", gold._48756_.Q, dut.wide_data_reg_3[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48757_.Q !== dut.wide_data_reg_3[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26214 gold=%b dut=%b", gold._48757_.Q, dut.wide_data_reg_3[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48758_.Q !== dut.wide_data_reg_3[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26215 gold=%b dut=%b", gold._48758_.Q, dut.wide_data_reg_3[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48759_.Q !== dut.wide_data_reg_3[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26216 gold=%b dut=%b", gold._48759_.Q, dut.wide_data_reg_3[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48760_.Q !== dut.wide_data_reg_3[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26217 gold=%b dut=%b", gold._48760_.Q, dut.wide_data_reg_3[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48761_.Q !== dut.wide_data_reg_3[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26218 gold=%b dut=%b", gold._48761_.Q, dut.wide_data_reg_3[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48762_.Q !== dut.wide_data_reg_3[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26219 gold=%b dut=%b", gold._48762_.Q, dut.wide_data_reg_3[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48763_.Q !== dut.wide_data_reg_3[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26220 gold=%b dut=%b", gold._48763_.Q, dut.wide_data_reg_3[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48764_.Q !== dut.wide_data_reg_3[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26221 gold=%b dut=%b", gold._48764_.Q, dut.wide_data_reg_3[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48765_.Q !== dut.wide_data_reg_3[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26222 gold=%b dut=%b", gold._48765_.Q, dut.wide_data_reg_3[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48766_.Q !== dut.wide_data_reg_3[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26223 gold=%b dut=%b", gold._48766_.Q, dut.wide_data_reg_3[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48767_.Q !== dut.wide_data_reg_3[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26224 gold=%b dut=%b", gold._48767_.Q, dut.wide_data_reg_3[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48768_.Q !== dut.wide_data_reg_3[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26225 gold=%b dut=%b", gold._48768_.Q, dut.wide_data_reg_3[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48769_.Q !== dut.wide_data_reg_3[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26226 gold=%b dut=%b", gold._48769_.Q, dut.wide_data_reg_3[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48770_.Q !== dut.wide_data_reg_3[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26227 gold=%b dut=%b", gold._48770_.Q, dut.wide_data_reg_3[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48771_.Q !== dut.wide_data_reg_3[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26228 gold=%b dut=%b", gold._48771_.Q, dut.wide_data_reg_3[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48772_.Q !== dut.wide_data_reg_3[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26229 gold=%b dut=%b", gold._48772_.Q, dut.wide_data_reg_3[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48773_.Q !== dut.wide_data_reg_3[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26230 gold=%b dut=%b", gold._48773_.Q, dut.wide_data_reg_3[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48774_.Q !== dut.wide_data_reg_3[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26231 gold=%b dut=%b", gold._48774_.Q, dut.wide_data_reg_3[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48711_.Q !== dut.data_register_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26232 gold=%b dut=%b", gold._48711_.Q, dut.data_register_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48712_.Q !== dut.data_register_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26233 gold=%b dut=%b", gold._48712_.Q, dut.data_register_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48713_.Q !== dut.data_register_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26234 gold=%b dut=%b", gold._48713_.Q, dut.data_register_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48714_.Q !== dut.data_register_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26235 gold=%b dut=%b", gold._48714_.Q, dut.data_register_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48715_.Q !== dut.data_register_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26236 gold=%b dut=%b", gold._48715_.Q, dut.data_register_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48716_.Q !== dut.data_register_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26237 gold=%b dut=%b", gold._48716_.Q, dut.data_register_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48717_.Q !== dut.data_register_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26238 gold=%b dut=%b", gold._48717_.Q, dut.data_register_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48718_.Q !== dut.data_register_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26239 gold=%b dut=%b", gold._48718_.Q, dut.data_register_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48719_.Q !== dut.data_register_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26240 gold=%b dut=%b", gold._48719_.Q, dut.data_register_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48720_.Q !== dut.data_register_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26241 gold=%b dut=%b", gold._48720_.Q, dut.data_register_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48721_.Q !== dut.data_register_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26242 gold=%b dut=%b", gold._48721_.Q, dut.data_register_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48722_.Q !== dut.data_register_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26243 gold=%b dut=%b", gold._48722_.Q, dut.data_register_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48723_.Q !== dut.data_register_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26244 gold=%b dut=%b", gold._48723_.Q, dut.data_register_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48724_.Q !== dut.data_register_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26245 gold=%b dut=%b", gold._48724_.Q, dut.data_register_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48725_.Q !== dut.data_register_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26246 gold=%b dut=%b", gold._48725_.Q, dut.data_register_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48726_.Q !== dut.data_register_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26247 gold=%b dut=%b", gold._48726_.Q, dut.data_register_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48727_.Q !== dut.data_register_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26248 gold=%b dut=%b", gold._48727_.Q, dut.data_register_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48728_.Q !== dut.data_register_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26249 gold=%b dut=%b", gold._48728_.Q, dut.data_register_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48729_.Q !== dut.data_register_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26250 gold=%b dut=%b", gold._48729_.Q, dut.data_register_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48730_.Q !== dut.data_register_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26251 gold=%b dut=%b", gold._48730_.Q, dut.data_register_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48731_.Q !== dut.data_register_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26252 gold=%b dut=%b", gold._48731_.Q, dut.data_register_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48732_.Q !== dut.data_register_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26253 gold=%b dut=%b", gold._48732_.Q, dut.data_register_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48733_.Q !== dut.data_register_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26254 gold=%b dut=%b", gold._48733_.Q, dut.data_register_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48734_.Q !== dut.data_register_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26255 gold=%b dut=%b", gold._48734_.Q, dut.data_register_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48735_.Q !== dut.data_register_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26256 gold=%b dut=%b", gold._48735_.Q, dut.data_register_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48736_.Q !== dut.data_register_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26257 gold=%b dut=%b", gold._48736_.Q, dut.data_register_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48737_.Q !== dut.data_register_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26258 gold=%b dut=%b", gold._48737_.Q, dut.data_register_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48738_.Q !== dut.data_register_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26259 gold=%b dut=%b", gold._48738_.Q, dut.data_register_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48739_.Q !== dut.data_register_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26260 gold=%b dut=%b", gold._48739_.Q, dut.data_register_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48740_.Q !== dut.data_register_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26261 gold=%b dut=%b", gold._48740_.Q, dut.data_register_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48741_.Q !== dut.data_register_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26262 gold=%b dut=%b", gold._48741_.Q, dut.data_register_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48742_.Q !== dut.status_flag_4) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26263 gold=%b dut=%b", gold._48742_.Q, dut.status_flag_4);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48679_.Q !== dut.data_reg_0_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26264 gold=%b dut=%b", gold._48679_.Q, dut.data_reg_0_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48680_.Q !== dut.data_reg_0_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26265 gold=%b dut=%b", gold._48680_.Q, dut.data_reg_0_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48681_.Q !== dut.data_reg_0_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26266 gold=%b dut=%b", gold._48681_.Q, dut.data_reg_0_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48682_.Q !== dut.data_reg_0_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26267 gold=%b dut=%b", gold._48682_.Q, dut.data_reg_0_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48683_.Q !== dut.data_reg_0_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26268 gold=%b dut=%b", gold._48683_.Q, dut.data_reg_0_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48684_.Q !== dut.data_reg_0_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26269 gold=%b dut=%b", gold._48684_.Q, dut.data_reg_0_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48685_.Q !== dut.data_reg_0_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26270 gold=%b dut=%b", gold._48685_.Q, dut.data_reg_0_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48686_.Q !== dut.data_reg_0_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26271 gold=%b dut=%b", gold._48686_.Q, dut.data_reg_0_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48687_.Q !== dut.data_reg_0_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26272 gold=%b dut=%b", gold._48687_.Q, dut.data_reg_0_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48688_.Q !== dut.data_reg_0_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26273 gold=%b dut=%b", gold._48688_.Q, dut.data_reg_0_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48689_.Q !== dut.data_reg_0_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26274 gold=%b dut=%b", gold._48689_.Q, dut.data_reg_0_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48690_.Q !== dut.data_reg_0_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26275 gold=%b dut=%b", gold._48690_.Q, dut.data_reg_0_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48691_.Q !== dut.data_reg_0_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26276 gold=%b dut=%b", gold._48691_.Q, dut.data_reg_0_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48692_.Q !== dut.data_reg_0_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26277 gold=%b dut=%b", gold._48692_.Q, dut.data_reg_0_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48693_.Q !== dut.data_reg_0_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26278 gold=%b dut=%b", gold._48693_.Q, dut.data_reg_0_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48694_.Q !== dut.data_reg_0_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26279 gold=%b dut=%b", gold._48694_.Q, dut.data_reg_0_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48695_.Q !== dut.data_reg_0_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26280 gold=%b dut=%b", gold._48695_.Q, dut.data_reg_0_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48696_.Q !== dut.data_reg_0_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26281 gold=%b dut=%b", gold._48696_.Q, dut.data_reg_0_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48697_.Q !== dut.data_reg_0_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26282 gold=%b dut=%b", gold._48697_.Q, dut.data_reg_0_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48698_.Q !== dut.data_reg_0_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26283 gold=%b dut=%b", gold._48698_.Q, dut.data_reg_0_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48699_.Q !== dut.data_reg_0_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26284 gold=%b dut=%b", gold._48699_.Q, dut.data_reg_0_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48700_.Q !== dut.data_reg_0_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26285 gold=%b dut=%b", gold._48700_.Q, dut.data_reg_0_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48701_.Q !== dut.data_reg_0_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26286 gold=%b dut=%b", gold._48701_.Q, dut.data_reg_0_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48702_.Q !== dut.cycle_counter_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26287 gold=%b dut=%b", gold._48702_.Q, dut.cycle_counter_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48703_.Q !== dut.cycle_counter_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26288 gold=%b dut=%b", gold._48703_.Q, dut.cycle_counter_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48704_.Q !== dut.cycle_counter_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26289 gold=%b dut=%b", gold._48704_.Q, dut.cycle_counter_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48705_.Q !== dut.cycle_counter_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26290 gold=%b dut=%b", gold._48705_.Q, dut.cycle_counter_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48706_.Q !== dut.cycle_counter_high[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26291 gold=%b dut=%b", gold._48706_.Q, dut.cycle_counter_high[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48707_.Q !== dut.cycle_counter_high[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26292 gold=%b dut=%b", gold._48707_.Q, dut.cycle_counter_high[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48708_.Q !== dut.cycle_counter_high[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26293 gold=%b dut=%b", gold._48708_.Q, dut.cycle_counter_high[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48709_.Q !== dut.cycle_counter_high[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26294 gold=%b dut=%b", gold._48709_.Q, dut.cycle_counter_high[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48710_.Q !== dut.control_flag_2) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26295 gold=%b dut=%b", gold._48710_.Q, dut.control_flag_2);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49576_.Q !== dut.control_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26296 gold=%b dut=%b", gold._49576_.Q, dut.control_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49577_.Q !== dut.control_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26297 gold=%b dut=%b", gold._49577_.Q, dut.control_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49578_.Q !== dut.control_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26298 gold=%b dut=%b", gold._49578_.Q, dut.control_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49579_.Q !== dut.control_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26299 gold=%b dut=%b", gold._49579_.Q, dut.control_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49580_.Q !== dut.control_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26300 gold=%b dut=%b", gold._49580_.Q, dut.control_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49581_.Q !== dut.control_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26301 gold=%b dut=%b", gold._49581_.Q, dut.control_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49582_.Q !== dut.control_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26302 gold=%b dut=%b", gold._49582_.Q, dut.control_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49583_.Q !== dut.control_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26303 gold=%b dut=%b", gold._49583_.Q, dut.control_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49584_.Q !== dut.control_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26304 gold=%b dut=%b", gold._49584_.Q, dut.control_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49585_.Q !== dut.control_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26305 gold=%b dut=%b", gold._49585_.Q, dut.control_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49586_.Q !== dut.control_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26306 gold=%b dut=%b", gold._49586_.Q, dut.control_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49587_.Q !== dut.control_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26307 gold=%b dut=%b", gold._49587_.Q, dut.control_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49588_.Q !== dut.control_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26308 gold=%b dut=%b", gold._49588_.Q, dut.control_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49589_.Q !== dut.control_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26309 gold=%b dut=%b", gold._49589_.Q, dut.control_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49590_.Q !== dut.control_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26310 gold=%b dut=%b", gold._49590_.Q, dut.control_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49591_.Q !== dut.control_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26311 gold=%b dut=%b", gold._49591_.Q, dut.control_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49592_.Q !== dut.control_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26312 gold=%b dut=%b", gold._49592_.Q, dut.control_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49593_.Q !== dut.control_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26313 gold=%b dut=%b", gold._49593_.Q, dut.control_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49594_.Q !== dut.control_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26314 gold=%b dut=%b", gold._49594_.Q, dut.control_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49595_.Q !== dut.control_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26315 gold=%b dut=%b", gold._49595_.Q, dut.control_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49596_.Q !== dut.control_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26316 gold=%b dut=%b", gold._49596_.Q, dut.control_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49597_.Q !== dut.control_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26317 gold=%b dut=%b", gold._49597_.Q, dut.control_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49598_.Q !== dut.control_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26318 gold=%b dut=%b", gold._49598_.Q, dut.control_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49599_.Q !== dut.control_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26319 gold=%b dut=%b", gold._49599_.Q, dut.control_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49600_.Q !== dut.control_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26320 gold=%b dut=%b", gold._49600_.Q, dut.control_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49601_.Q !== dut.control_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26321 gold=%b dut=%b", gold._49601_.Q, dut.control_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49602_.Q !== dut.control_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26322 gold=%b dut=%b", gold._49602_.Q, dut.control_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49603_.Q !== dut.control_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26323 gold=%b dut=%b", gold._49603_.Q, dut.control_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49604_.Q !== dut.control_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26324 gold=%b dut=%b", gold._49604_.Q, dut.control_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49605_.Q !== dut.control_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26325 gold=%b dut=%b", gold._49605_.Q, dut.control_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49606_.Q !== dut.control_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26326 gold=%b dut=%b", gold._49606_.Q, dut.control_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49607_.Q !== dut.control_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26327 gold=%b dut=%b", gold._49607_.Q, dut.control_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48647_.Q !== dut.counter_a[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26328 gold=%b dut=%b", gold._48647_.Q, dut.counter_a[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48648_.Q !== dut.counter_a[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26329 gold=%b dut=%b", gold._48648_.Q, dut.counter_a[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48649_.Q !== dut.counter_a[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26330 gold=%b dut=%b", gold._48649_.Q, dut.counter_a[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48650_.Q !== dut.counter_a[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26331 gold=%b dut=%b", gold._48650_.Q, dut.counter_a[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48651_.Q !== dut.counter_a[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26332 gold=%b dut=%b", gold._48651_.Q, dut.counter_a[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48652_.Q !== dut.counter_a[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26333 gold=%b dut=%b", gold._48652_.Q, dut.counter_a[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48653_.Q !== dut.counter_a[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26334 gold=%b dut=%b", gold._48653_.Q, dut.counter_a[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48654_.Q !== dut.counter_a[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26335 gold=%b dut=%b", gold._48654_.Q, dut.counter_a[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48655_.Q !== dut.counter_a[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26336 gold=%b dut=%b", gold._48655_.Q, dut.counter_a[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48656_.Q !== dut.counter_a[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26337 gold=%b dut=%b", gold._48656_.Q, dut.counter_a[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48657_.Q !== dut.counter_a[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26338 gold=%b dut=%b", gold._48657_.Q, dut.counter_a[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48658_.Q !== dut.counter_a[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26339 gold=%b dut=%b", gold._48658_.Q, dut.counter_a[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48659_.Q !== dut.counter_a[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26340 gold=%b dut=%b", gold._48659_.Q, dut.counter_a[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48660_.Q !== dut.counter_a[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26341 gold=%b dut=%b", gold._48660_.Q, dut.counter_a[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48661_.Q !== dut.counter_a[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26342 gold=%b dut=%b", gold._48661_.Q, dut.counter_a[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48662_.Q !== dut.data_reg_1_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26343 gold=%b dut=%b", gold._48662_.Q, dut.data_reg_1_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48663_.Q !== dut.data_reg_1_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26344 gold=%b dut=%b", gold._48663_.Q, dut.data_reg_1_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48664_.Q !== dut.data_reg_1_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26345 gold=%b dut=%b", gold._48664_.Q, dut.data_reg_1_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48665_.Q !== dut.data_reg_1_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26346 gold=%b dut=%b", gold._48665_.Q, dut.data_reg_1_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48666_.Q !== dut.data_reg_1_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26347 gold=%b dut=%b", gold._48666_.Q, dut.data_reg_1_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48667_.Q !== dut.data_reg_1_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26348 gold=%b dut=%b", gold._48667_.Q, dut.data_reg_1_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48668_.Q !== dut.data_reg_1_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26349 gold=%b dut=%b", gold._48668_.Q, dut.data_reg_1_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48669_.Q !== dut.data_reg_1_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26350 gold=%b dut=%b", gold._48669_.Q, dut.data_reg_1_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48670_.Q !== dut.data_reg_1_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26351 gold=%b dut=%b", gold._48670_.Q, dut.data_reg_1_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48671_.Q !== dut.data_reg_1_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26352 gold=%b dut=%b", gold._48671_.Q, dut.data_reg_1_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48672_.Q !== dut.data_reg_1_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26353 gold=%b dut=%b", gold._48672_.Q, dut.data_reg_1_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48673_.Q !== dut.data_reg_1_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26354 gold=%b dut=%b", gold._48673_.Q, dut.data_reg_1_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48674_.Q !== dut.data_reg_1_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26355 gold=%b dut=%b", gold._48674_.Q, dut.data_reg_1_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48675_.Q !== dut.data_reg_1_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26356 gold=%b dut=%b", gold._48675_.Q, dut.data_reg_1_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48676_.Q !== dut.data_reg_1_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26357 gold=%b dut=%b", gold._48676_.Q, dut.data_reg_1_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48677_.Q !== dut.data_reg_1_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26358 gold=%b dut=%b", gold._48677_.Q, dut.data_reg_1_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48678_.Q !== dut.data_reg_1_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26359 gold=%b dut=%b", gold._48678_.Q, dut.data_reg_1_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48615_.Q !== dut.address_counter_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26360 gold=%b dut=%b", gold._48615_.Q, dut.address_counter_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48616_.Q !== dut.address_counter_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26361 gold=%b dut=%b", gold._48616_.Q, dut.address_counter_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48617_.Q !== dut.address_counter_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26362 gold=%b dut=%b", gold._48617_.Q, dut.address_counter_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48618_.Q !== dut.address_counter_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26363 gold=%b dut=%b", gold._48618_.Q, dut.address_counter_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48619_.Q !== dut.address_counter_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26364 gold=%b dut=%b", gold._48619_.Q, dut.address_counter_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48620_.Q !== dut.address_counter_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26365 gold=%b dut=%b", gold._48620_.Q, dut.address_counter_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48621_.Q !== dut.address_counter_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26366 gold=%b dut=%b", gold._48621_.Q, dut.address_counter_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48622_.Q !== dut.address_counter_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26367 gold=%b dut=%b", gold._48622_.Q, dut.address_counter_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48623_.Q !== dut.address_counter_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26368 gold=%b dut=%b", gold._48623_.Q, dut.address_counter_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48624_.Q !== dut.address_counter_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26369 gold=%b dut=%b", gold._48624_.Q, dut.address_counter_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48625_.Q !== dut.address_counter_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26370 gold=%b dut=%b", gold._48625_.Q, dut.address_counter_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48626_.Q !== dut.address_counter_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26371 gold=%b dut=%b", gold._48626_.Q, dut.address_counter_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48627_.Q !== dut.address_counter_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26372 gold=%b dut=%b", gold._48627_.Q, dut.address_counter_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48628_.Q !== dut.address_counter_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26373 gold=%b dut=%b", gold._48628_.Q, dut.address_counter_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48629_.Q !== dut.address_counter_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26374 gold=%b dut=%b", gold._48629_.Q, dut.address_counter_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48630_.Q !== dut.address_counter_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26375 gold=%b dut=%b", gold._48630_.Q, dut.address_counter_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48631_.Q !== dut.address_counter_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26376 gold=%b dut=%b", gold._48631_.Q, dut.address_counter_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48632_.Q !== dut.address_counter_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26377 gold=%b dut=%b", gold._48632_.Q, dut.address_counter_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48633_.Q !== dut.address_counter_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26378 gold=%b dut=%b", gold._48633_.Q, dut.address_counter_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48634_.Q !== dut.address_counter_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26379 gold=%b dut=%b", gold._48634_.Q, dut.address_counter_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48635_.Q !== dut.address_counter_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26380 gold=%b dut=%b", gold._48635_.Q, dut.address_counter_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48636_.Q !== dut.address_counter_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26381 gold=%b dut=%b", gold._48636_.Q, dut.address_counter_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48637_.Q !== dut.address_counter_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26382 gold=%b dut=%b", gold._48637_.Q, dut.address_counter_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48638_.Q !== dut.address_counter_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26383 gold=%b dut=%b", gold._48638_.Q, dut.address_counter_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48639_.Q !== dut.address_counter_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26384 gold=%b dut=%b", gold._48639_.Q, dut.address_counter_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48640_.Q !== dut.address_counter_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26385 gold=%b dut=%b", gold._48640_.Q, dut.address_counter_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48641_.Q !== dut.address_counter_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26386 gold=%b dut=%b", gold._48641_.Q, dut.address_counter_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48642_.Q !== dut.address_counter_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26387 gold=%b dut=%b", gold._48642_.Q, dut.address_counter_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48643_.Q !== dut.address_counter_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26388 gold=%b dut=%b", gold._48643_.Q, dut.address_counter_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48644_.Q !== dut.address_counter_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26389 gold=%b dut=%b", gold._48644_.Q, dut.address_counter_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48645_.Q !== dut.address_counter_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26390 gold=%b dut=%b", gold._48645_.Q, dut.address_counter_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48646_.Q !== dut.counter_control_state) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26391 gold=%b dut=%b", gold._48646_.Q, dut.counter_control_state);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48583_.Q !== dut.word_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26392 gold=%b dut=%b", gold._48583_.Q, dut.word_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48584_.Q !== dut.word_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26393 gold=%b dut=%b", gold._48584_.Q, dut.word_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48585_.Q !== dut.word_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26394 gold=%b dut=%b", gold._48585_.Q, dut.word_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48586_.Q !== dut.word_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26395 gold=%b dut=%b", gold._48586_.Q, dut.word_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48587_.Q !== dut.word_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26396 gold=%b dut=%b", gold._48587_.Q, dut.word_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48588_.Q !== dut.word_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26397 gold=%b dut=%b", gold._48588_.Q, dut.word_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48589_.Q !== dut.word_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26398 gold=%b dut=%b", gold._48589_.Q, dut.word_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48590_.Q !== dut.word_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26399 gold=%b dut=%b", gold._48590_.Q, dut.word_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48591_.Q !== dut.word_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26400 gold=%b dut=%b", gold._48591_.Q, dut.word_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48592_.Q !== dut.word_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26401 gold=%b dut=%b", gold._48592_.Q, dut.word_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48593_.Q !== dut.word_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26402 gold=%b dut=%b", gold._48593_.Q, dut.word_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48594_.Q !== dut.word_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26403 gold=%b dut=%b", gold._48594_.Q, dut.word_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48595_.Q !== dut.word_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26404 gold=%b dut=%b", gold._48595_.Q, dut.word_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48596_.Q !== dut.word_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26405 gold=%b dut=%b", gold._48596_.Q, dut.word_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48597_.Q !== dut.word_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26406 gold=%b dut=%b", gold._48597_.Q, dut.word_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48598_.Q !== dut.word_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26407 gold=%b dut=%b", gold._48598_.Q, dut.word_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48599_.Q !== dut.word_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26408 gold=%b dut=%b", gold._48599_.Q, dut.word_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48600_.Q !== dut.word_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26409 gold=%b dut=%b", gold._48600_.Q, dut.word_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48601_.Q !== dut.word_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26410 gold=%b dut=%b", gold._48601_.Q, dut.word_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48602_.Q !== dut.word_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26411 gold=%b dut=%b", gold._48602_.Q, dut.word_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48603_.Q !== dut.word_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26412 gold=%b dut=%b", gold._48603_.Q, dut.word_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48604_.Q !== dut.word_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26413 gold=%b dut=%b", gold._48604_.Q, dut.word_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48605_.Q !== dut.word_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26414 gold=%b dut=%b", gold._48605_.Q, dut.word_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48606_.Q !== dut.word_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26415 gold=%b dut=%b", gold._48606_.Q, dut.word_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48607_.Q !== dut.word_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26416 gold=%b dut=%b", gold._48607_.Q, dut.word_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48608_.Q !== dut.word_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26417 gold=%b dut=%b", gold._48608_.Q, dut.word_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48609_.Q !== dut.word_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26418 gold=%b dut=%b", gold._48609_.Q, dut.word_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48610_.Q !== dut.word_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26419 gold=%b dut=%b", gold._48610_.Q, dut.word_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48611_.Q !== dut.word_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26420 gold=%b dut=%b", gold._48611_.Q, dut.word_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48612_.Q !== dut.word_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26421 gold=%b dut=%b", gold._48612_.Q, dut.word_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48613_.Q !== dut.word_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26422 gold=%b dut=%b", gold._48613_.Q, dut.word_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48614_.Q !== dut.word_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26423 gold=%b dut=%b", gold._48614_.Q, dut.word_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48551_.Q !== dut.indexed_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26424 gold=%b dut=%b", gold._48551_.Q, dut.indexed_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48552_.Q !== dut.indexed_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26425 gold=%b dut=%b", gold._48552_.Q, dut.indexed_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48553_.Q !== dut.indexed_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26426 gold=%b dut=%b", gold._48553_.Q, dut.indexed_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48554_.Q !== dut.indexed_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26427 gold=%b dut=%b", gold._48554_.Q, dut.indexed_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48555_.Q !== dut.indexed_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26428 gold=%b dut=%b", gold._48555_.Q, dut.indexed_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48556_.Q !== dut.indexed_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26429 gold=%b dut=%b", gold._48556_.Q, dut.indexed_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48557_.Q !== dut.indexed_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26430 gold=%b dut=%b", gold._48557_.Q, dut.indexed_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48558_.Q !== dut.indexed_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26431 gold=%b dut=%b", gold._48558_.Q, dut.indexed_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48559_.Q !== dut.indexed_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26432 gold=%b dut=%b", gold._48559_.Q, dut.indexed_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48560_.Q !== dut.indexed_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26433 gold=%b dut=%b", gold._48560_.Q, dut.indexed_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48561_.Q !== dut.indexed_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26434 gold=%b dut=%b", gold._48561_.Q, dut.indexed_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48562_.Q !== dut.indexed_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26435 gold=%b dut=%b", gold._48562_.Q, dut.indexed_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48563_.Q !== dut.indexed_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26436 gold=%b dut=%b", gold._48563_.Q, dut.indexed_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48564_.Q !== dut.indexed_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26437 gold=%b dut=%b", gold._48564_.Q, dut.indexed_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48565_.Q !== dut.indexed_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26438 gold=%b dut=%b", gold._48565_.Q, dut.indexed_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48566_.Q !== dut.indexed_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26439 gold=%b dut=%b", gold._48566_.Q, dut.indexed_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48567_.Q !== dut.indexed_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26440 gold=%b dut=%b", gold._48567_.Q, dut.indexed_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48568_.Q !== dut.indexed_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26441 gold=%b dut=%b", gold._48568_.Q, dut.indexed_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48569_.Q !== dut.indexed_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26442 gold=%b dut=%b", gold._48569_.Q, dut.indexed_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48570_.Q !== dut.indexed_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26443 gold=%b dut=%b", gold._48570_.Q, dut.indexed_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48571_.Q !== dut.indexed_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26444 gold=%b dut=%b", gold._48571_.Q, dut.indexed_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48572_.Q !== dut.indexed_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26445 gold=%b dut=%b", gold._48572_.Q, dut.indexed_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48573_.Q !== dut.indexed_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26446 gold=%b dut=%b", gold._48573_.Q, dut.indexed_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48574_.Q !== dut.indexed_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26447 gold=%b dut=%b", gold._48574_.Q, dut.indexed_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48575_.Q !== dut.indexed_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26448 gold=%b dut=%b", gold._48575_.Q, dut.indexed_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48576_.Q !== dut.indexed_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26449 gold=%b dut=%b", gold._48576_.Q, dut.indexed_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48577_.Q !== dut.indexed_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26450 gold=%b dut=%b", gold._48577_.Q, dut.indexed_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48578_.Q !== dut.indexed_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26451 gold=%b dut=%b", gold._48578_.Q, dut.indexed_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48579_.Q !== dut.indexed_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26452 gold=%b dut=%b", gold._48579_.Q, dut.indexed_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48580_.Q !== dut.indexed_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26453 gold=%b dut=%b", gold._48580_.Q, dut.indexed_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48581_.Q !== dut.indexed_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26454 gold=%b dut=%b", gold._48581_.Q, dut.indexed_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48582_.Q !== dut.word_valid_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26455 gold=%b dut=%b", gold._48582_.Q, dut.word_valid_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48519_.Q !== dut.write_data_register_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26456 gold=%b dut=%b", gold._48519_.Q, dut.write_data_register_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48520_.Q !== dut.write_data_register_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26457 gold=%b dut=%b", gold._48520_.Q, dut.write_data_register_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48521_.Q !== dut.write_data_register_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26458 gold=%b dut=%b", gold._48521_.Q, dut.write_data_register_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48522_.Q !== dut.write_data_register_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26459 gold=%b dut=%b", gold._48522_.Q, dut.write_data_register_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48523_.Q !== dut.write_data_register_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26460 gold=%b dut=%b", gold._48523_.Q, dut.write_data_register_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48524_.Q !== dut.write_data_register_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26461 gold=%b dut=%b", gold._48524_.Q, dut.write_data_register_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48525_.Q !== dut.write_data_register_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26462 gold=%b dut=%b", gold._48525_.Q, dut.write_data_register_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48526_.Q !== dut.write_data_register_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26463 gold=%b dut=%b", gold._48526_.Q, dut.write_data_register_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48527_.Q !== dut.write_data_register_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26464 gold=%b dut=%b", gold._48527_.Q, dut.write_data_register_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48528_.Q !== dut.write_data_register_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26465 gold=%b dut=%b", gold._48528_.Q, dut.write_data_register_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48529_.Q !== dut.write_data_register_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26466 gold=%b dut=%b", gold._48529_.Q, dut.write_data_register_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48530_.Q !== dut.write_data_register_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26467 gold=%b dut=%b", gold._48530_.Q, dut.write_data_register_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48531_.Q !== dut.write_data_register_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26468 gold=%b dut=%b", gold._48531_.Q, dut.write_data_register_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48532_.Q !== dut.write_data_register_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26469 gold=%b dut=%b", gold._48532_.Q, dut.write_data_register_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48533_.Q !== dut.write_data_register_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26470 gold=%b dut=%b", gold._48533_.Q, dut.write_data_register_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48534_.Q !== dut.write_data_register_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26471 gold=%b dut=%b", gold._48534_.Q, dut.write_data_register_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48535_.Q !== dut.write_data_register_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26472 gold=%b dut=%b", gold._48535_.Q, dut.write_data_register_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48536_.Q !== dut.write_data_register_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26473 gold=%b dut=%b", gold._48536_.Q, dut.write_data_register_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48537_.Q !== dut.write_data_register_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26474 gold=%b dut=%b", gold._48537_.Q, dut.write_data_register_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48538_.Q !== dut.write_data_register_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26475 gold=%b dut=%b", gold._48538_.Q, dut.write_data_register_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48539_.Q !== dut.write_data_register_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26476 gold=%b dut=%b", gold._48539_.Q, dut.write_data_register_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48540_.Q !== dut.write_data_register_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26477 gold=%b dut=%b", gold._48540_.Q, dut.write_data_register_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48541_.Q !== dut.write_data_register_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26478 gold=%b dut=%b", gold._48541_.Q, dut.write_data_register_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48542_.Q !== dut.write_data_register_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26479 gold=%b dut=%b", gold._48542_.Q, dut.write_data_register_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48543_.Q !== dut.write_data_register_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26480 gold=%b dut=%b", gold._48543_.Q, dut.write_data_register_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48544_.Q !== dut.write_data_register_2[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26481 gold=%b dut=%b", gold._48544_.Q, dut.write_data_register_2[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48545_.Q !== dut.write_data_register_2[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26482 gold=%b dut=%b", gold._48545_.Q, dut.write_data_register_2[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48546_.Q !== dut.write_data_register_2[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26483 gold=%b dut=%b", gold._48546_.Q, dut.write_data_register_2[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48547_.Q !== dut.write_data_register_2[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26484 gold=%b dut=%b", gold._48547_.Q, dut.write_data_register_2[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48548_.Q !== dut.write_data_register_2[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26485 gold=%b dut=%b", gold._48548_.Q, dut.write_data_register_2[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48549_.Q !== dut.write_data_register_2[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26486 gold=%b dut=%b", gold._48549_.Q, dut.write_data_register_2[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48550_.Q !== dut.write_data_register_2[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26487 gold=%b dut=%b", gold._48550_.Q, dut.write_data_register_2[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48487_.Q !== dut.data_register_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26488 gold=%b dut=%b", gold._48487_.Q, dut.data_register_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48488_.Q !== dut.data_register_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26489 gold=%b dut=%b", gold._48488_.Q, dut.data_register_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48489_.Q !== dut.data_register_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26490 gold=%b dut=%b", gold._48489_.Q, dut.data_register_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48490_.Q !== dut.data_register_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26491 gold=%b dut=%b", gold._48490_.Q, dut.data_register_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48491_.Q !== dut.data_register_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26492 gold=%b dut=%b", gold._48491_.Q, dut.data_register_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48492_.Q !== dut.data_register_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26493 gold=%b dut=%b", gold._48492_.Q, dut.data_register_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48493_.Q !== dut.data_register_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26494 gold=%b dut=%b", gold._48493_.Q, dut.data_register_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48494_.Q !== dut.data_register_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26495 gold=%b dut=%b", gold._48494_.Q, dut.data_register_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48495_.Q !== dut.data_register_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26496 gold=%b dut=%b", gold._48495_.Q, dut.data_register_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48496_.Q !== dut.data_register_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26497 gold=%b dut=%b", gold._48496_.Q, dut.data_register_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48497_.Q !== dut.data_register_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26498 gold=%b dut=%b", gold._48497_.Q, dut.data_register_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48498_.Q !== dut.data_register_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26499 gold=%b dut=%b", gold._48498_.Q, dut.data_register_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48499_.Q !== dut.data_register_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26500 gold=%b dut=%b", gold._48499_.Q, dut.data_register_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48500_.Q !== dut.data_register_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26501 gold=%b dut=%b", gold._48500_.Q, dut.data_register_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48501_.Q !== dut.data_register_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26502 gold=%b dut=%b", gold._48501_.Q, dut.data_register_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48502_.Q !== dut.wide_counter_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26503 gold=%b dut=%b", gold._48502_.Q, dut.wide_counter_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48503_.Q !== dut.wide_counter_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26504 gold=%b dut=%b", gold._48503_.Q, dut.wide_counter_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48504_.Q !== dut.wide_counter_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26505 gold=%b dut=%b", gold._48504_.Q, dut.wide_counter_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48505_.Q !== dut.wide_counter_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26506 gold=%b dut=%b", gold._48505_.Q, dut.wide_counter_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48506_.Q !== dut.wide_counter_high[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26507 gold=%b dut=%b", gold._48506_.Q, dut.wide_counter_high[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48507_.Q !== dut.wide_counter_high[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26508 gold=%b dut=%b", gold._48507_.Q, dut.wide_counter_high[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48508_.Q !== dut.wide_counter_high[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26509 gold=%b dut=%b", gold._48508_.Q, dut.wide_counter_high[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48509_.Q !== dut.wide_counter_high[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26510 gold=%b dut=%b", gold._48509_.Q, dut.wide_counter_high[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48510_.Q !== dut.wide_counter_high[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26511 gold=%b dut=%b", gold._48510_.Q, dut.wide_counter_high[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48511_.Q !== dut.wide_counter_high[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26512 gold=%b dut=%b", gold._48511_.Q, dut.wide_counter_high[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48512_.Q !== dut.wide_counter_high[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26513 gold=%b dut=%b", gold._48512_.Q, dut.wide_counter_high[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48513_.Q !== dut.wide_counter_high[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26514 gold=%b dut=%b", gold._48513_.Q, dut.wide_counter_high[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48514_.Q !== dut.wide_counter_high[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26515 gold=%b dut=%b", gold._48514_.Q, dut.wide_counter_high[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48515_.Q !== dut.wide_counter_high[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26516 gold=%b dut=%b", gold._48515_.Q, dut.wide_counter_high[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48516_.Q !== dut.wide_counter_high[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26517 gold=%b dut=%b", gold._48516_.Q, dut.wide_counter_high[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48517_.Q !== dut.wide_counter_high[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26518 gold=%b dut=%b", gold._48517_.Q, dut.wide_counter_high[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48518_.Q !== dut.control_flag_3) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26519 gold=%b dut=%b", gold._48518_.Q, dut.control_flag_3);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49544_.Q !== dut.data_word_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26520 gold=%b dut=%b", gold._49544_.Q, dut.data_word_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49545_.Q !== dut.data_word_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26521 gold=%b dut=%b", gold._49545_.Q, dut.data_word_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49546_.Q !== dut.data_word_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26522 gold=%b dut=%b", gold._49546_.Q, dut.data_word_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49547_.Q !== dut.data_word_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26523 gold=%b dut=%b", gold._49547_.Q, dut.data_word_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49548_.Q !== dut.data_word_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26524 gold=%b dut=%b", gold._49548_.Q, dut.data_word_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49549_.Q !== dut.data_word_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26525 gold=%b dut=%b", gold._49549_.Q, dut.data_word_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49550_.Q !== dut.data_word_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26526 gold=%b dut=%b", gold._49550_.Q, dut.data_word_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49551_.Q !== dut.data_word_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26527 gold=%b dut=%b", gold._49551_.Q, dut.data_word_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49552_.Q !== dut.data_word_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26528 gold=%b dut=%b", gold._49552_.Q, dut.data_word_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49553_.Q !== dut.data_word_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26529 gold=%b dut=%b", gold._49553_.Q, dut.data_word_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49554_.Q !== dut.data_word_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26530 gold=%b dut=%b", gold._49554_.Q, dut.data_word_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49555_.Q !== dut.data_word_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26531 gold=%b dut=%b", gold._49555_.Q, dut.data_word_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49556_.Q !== dut.data_word_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26532 gold=%b dut=%b", gold._49556_.Q, dut.data_word_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49557_.Q !== dut.data_word_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26533 gold=%b dut=%b", gold._49557_.Q, dut.data_word_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49558_.Q !== dut.data_word_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26534 gold=%b dut=%b", gold._49558_.Q, dut.data_word_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49559_.Q !== dut.data_word_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26535 gold=%b dut=%b", gold._49559_.Q, dut.data_word_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49560_.Q !== dut.data_word_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26536 gold=%b dut=%b", gold._49560_.Q, dut.data_word_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49561_.Q !== dut.data_word_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26537 gold=%b dut=%b", gold._49561_.Q, dut.data_word_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49562_.Q !== dut.data_word_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26538 gold=%b dut=%b", gold._49562_.Q, dut.data_word_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49563_.Q !== dut.data_word_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26539 gold=%b dut=%b", gold._49563_.Q, dut.data_word_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49564_.Q !== dut.data_word_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26540 gold=%b dut=%b", gold._49564_.Q, dut.data_word_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49565_.Q !== dut.data_word_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26541 gold=%b dut=%b", gold._49565_.Q, dut.data_word_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49566_.Q !== dut.data_word_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26542 gold=%b dut=%b", gold._49566_.Q, dut.data_word_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49567_.Q !== dut.data_word_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26543 gold=%b dut=%b", gold._49567_.Q, dut.data_word_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49568_.Q !== dut.data_word_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26544 gold=%b dut=%b", gold._49568_.Q, dut.data_word_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49569_.Q !== dut.data_word_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26545 gold=%b dut=%b", gold._49569_.Q, dut.data_word_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49570_.Q !== dut.data_word_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26546 gold=%b dut=%b", gold._49570_.Q, dut.data_word_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49571_.Q !== dut.data_word_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26547 gold=%b dut=%b", gold._49571_.Q, dut.data_word_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49572_.Q !== dut.data_word_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26548 gold=%b dut=%b", gold._49572_.Q, dut.data_word_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49573_.Q !== dut.data_word_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26549 gold=%b dut=%b", gold._49573_.Q, dut.data_word_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49574_.Q !== dut.data_word_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26550 gold=%b dut=%b", gold._49574_.Q, dut.data_word_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49575_.Q !== dut.data_word_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26551 gold=%b dut=%b", gold._49575_.Q, dut.data_word_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49512_.Q !== dut.data_register_3[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26552 gold=%b dut=%b", gold._49512_.Q, dut.data_register_3[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49513_.Q !== dut.data_register_3[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26553 gold=%b dut=%b", gold._49513_.Q, dut.data_register_3[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49514_.Q !== dut.data_register_3[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26554 gold=%b dut=%b", gold._49514_.Q, dut.data_register_3[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49515_.Q !== dut.data_register_3[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26555 gold=%b dut=%b", gold._49515_.Q, dut.data_register_3[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49516_.Q !== dut.data_register_3[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26556 gold=%b dut=%b", gold._49516_.Q, dut.data_register_3[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49517_.Q !== dut.data_register_3[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26557 gold=%b dut=%b", gold._49517_.Q, dut.data_register_3[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49518_.Q !== dut.data_register_3[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26558 gold=%b dut=%b", gold._49518_.Q, dut.data_register_3[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49519_.Q !== dut.data_register_3[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26559 gold=%b dut=%b", gold._49519_.Q, dut.data_register_3[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49520_.Q !== dut.data_register_3[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26560 gold=%b dut=%b", gold._49520_.Q, dut.data_register_3[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49521_.Q !== dut.data_register_3[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26561 gold=%b dut=%b", gold._49521_.Q, dut.data_register_3[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49522_.Q !== dut.data_register_3[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26562 gold=%b dut=%b", gold._49522_.Q, dut.data_register_3[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49523_.Q !== dut.data_register_3[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26563 gold=%b dut=%b", gold._49523_.Q, dut.data_register_3[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49524_.Q !== dut.data_register_3[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26564 gold=%b dut=%b", gold._49524_.Q, dut.data_register_3[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49525_.Q !== dut.data_register_3[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26565 gold=%b dut=%b", gold._49525_.Q, dut.data_register_3[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49526_.Q !== dut.data_register_3[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26566 gold=%b dut=%b", gold._49526_.Q, dut.data_register_3[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49527_.Q !== dut.data_register_3[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26567 gold=%b dut=%b", gold._49527_.Q, dut.data_register_3[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49528_.Q !== dut.data_register_3[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26568 gold=%b dut=%b", gold._49528_.Q, dut.data_register_3[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49529_.Q !== dut.data_register_3[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26569 gold=%b dut=%b", gold._49529_.Q, dut.data_register_3[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49530_.Q !== dut.data_register_3[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26570 gold=%b dut=%b", gold._49530_.Q, dut.data_register_3[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49531_.Q !== dut.data_register_3[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26571 gold=%b dut=%b", gold._49531_.Q, dut.data_register_3[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49532_.Q !== dut.data_register_3[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26572 gold=%b dut=%b", gold._49532_.Q, dut.data_register_3[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49533_.Q !== dut.data_register_3[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26573 gold=%b dut=%b", gold._49533_.Q, dut.data_register_3[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49534_.Q !== dut.data_register_3[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26574 gold=%b dut=%b", gold._49534_.Q, dut.data_register_3[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49535_.Q !== dut.data_register_3[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26575 gold=%b dut=%b", gold._49535_.Q, dut.data_register_3[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49536_.Q !== dut.data_register_3[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26576 gold=%b dut=%b", gold._49536_.Q, dut.data_register_3[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49537_.Q !== dut.data_register_3[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26577 gold=%b dut=%b", gold._49537_.Q, dut.data_register_3[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49538_.Q !== dut.data_register_3[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26578 gold=%b dut=%b", gold._49538_.Q, dut.data_register_3[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49539_.Q !== dut.data_register_3[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26579 gold=%b dut=%b", gold._49539_.Q, dut.data_register_3[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49540_.Q !== dut.data_register_3[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26580 gold=%b dut=%b", gold._49540_.Q, dut.data_register_3[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49541_.Q !== dut.data_register_3[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26581 gold=%b dut=%b", gold._49541_.Q, dut.data_register_3[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49542_.Q !== dut.fsm_state_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26582 gold=%b dut=%b", gold._49542_.Q, dut.fsm_state_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49543_.Q !== dut.fsm_state_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26583 gold=%b dut=%b", gold._49543_.Q, dut.fsm_state_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49480_.Q !== dut.data_reg_22bit[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26584 gold=%b dut=%b", gold._49480_.Q, dut.data_reg_22bit[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49481_.Q !== dut.data_reg_22bit[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26585 gold=%b dut=%b", gold._49481_.Q, dut.data_reg_22bit[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49482_.Q !== dut.data_reg_22bit[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26586 gold=%b dut=%b", gold._49482_.Q, dut.data_reg_22bit[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49483_.Q !== dut.data_reg_22bit[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26587 gold=%b dut=%b", gold._49483_.Q, dut.data_reg_22bit[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49484_.Q !== dut.data_reg_22bit[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26588 gold=%b dut=%b", gold._49484_.Q, dut.data_reg_22bit[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49485_.Q !== dut.data_reg_22bit[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26589 gold=%b dut=%b", gold._49485_.Q, dut.data_reg_22bit[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49486_.Q !== dut.data_reg_22bit[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26590 gold=%b dut=%b", gold._49486_.Q, dut.data_reg_22bit[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49487_.Q !== dut.data_reg_22bit[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26591 gold=%b dut=%b", gold._49487_.Q, dut.data_reg_22bit[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49488_.Q !== dut.data_reg_22bit[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26592 gold=%b dut=%b", gold._49488_.Q, dut.data_reg_22bit[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49489_.Q !== dut.data_reg_22bit[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26593 gold=%b dut=%b", gold._49489_.Q, dut.data_reg_22bit[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49490_.Q !== dut.data_reg_22bit[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26594 gold=%b dut=%b", gold._49490_.Q, dut.data_reg_22bit[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49491_.Q !== dut.data_reg_22bit[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26595 gold=%b dut=%b", gold._49491_.Q, dut.data_reg_22bit[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49492_.Q !== dut.data_reg_22bit[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26596 gold=%b dut=%b", gold._49492_.Q, dut.data_reg_22bit[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49493_.Q !== dut.data_reg_22bit[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26597 gold=%b dut=%b", gold._49493_.Q, dut.data_reg_22bit[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49494_.Q !== dut.data_reg_22bit[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26598 gold=%b dut=%b", gold._49494_.Q, dut.data_reg_22bit[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49495_.Q !== dut.data_reg_22bit[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26599 gold=%b dut=%b", gold._49495_.Q, dut.data_reg_22bit[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49496_.Q !== dut.data_reg_22bit[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26600 gold=%b dut=%b", gold._49496_.Q, dut.data_reg_22bit[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49497_.Q !== dut.data_reg_22bit[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26601 gold=%b dut=%b", gold._49497_.Q, dut.data_reg_22bit[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49498_.Q !== dut.data_reg_22bit[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26602 gold=%b dut=%b", gold._49498_.Q, dut.data_reg_22bit[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49499_.Q !== dut.data_reg_22bit[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26603 gold=%b dut=%b", gold._49499_.Q, dut.data_reg_22bit[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49500_.Q !== dut.data_reg_22bit[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26604 gold=%b dut=%b", gold._49500_.Q, dut.data_reg_22bit[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49501_.Q !== dut.data_reg_22bit[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26605 gold=%b dut=%b", gold._49501_.Q, dut.data_reg_22bit[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49502_.Q !== dut.wide_counter_high_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26606 gold=%b dut=%b", gold._49502_.Q, dut.wide_counter_high_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49503_.Q !== dut.wide_counter_high_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26607 gold=%b dut=%b", gold._49503_.Q, dut.wide_counter_high_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49504_.Q !== dut.wide_counter_high_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26608 gold=%b dut=%b", gold._49504_.Q, dut.wide_counter_high_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49505_.Q !== dut.wide_counter_high_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26609 gold=%b dut=%b", gold._49505_.Q, dut.wide_counter_high_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49506_.Q !== dut.wide_counter_high_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26610 gold=%b dut=%b", gold._49506_.Q, dut.wide_counter_high_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49507_.Q !== dut.wide_counter_high_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26611 gold=%b dut=%b", gold._49507_.Q, dut.wide_counter_high_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49508_.Q !== dut.wide_counter_high_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26612 gold=%b dut=%b", gold._49508_.Q, dut.wide_counter_high_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49509_.Q !== dut.wide_counter_high_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26613 gold=%b dut=%b", gold._49509_.Q, dut.wide_counter_high_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49510_.Q !== dut.wide_counter_high_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26614 gold=%b dut=%b", gold._49510_.Q, dut.wide_counter_high_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49511_.Q !== dut.control_flag_4) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26615 gold=%b dut=%b", gold._49511_.Q, dut.control_flag_4);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49448_.Q !== dut.control_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26616 gold=%b dut=%b", gold._49448_.Q, dut.control_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49449_.Q !== dut.control_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26617 gold=%b dut=%b", gold._49449_.Q, dut.control_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49450_.Q !== dut.control_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26618 gold=%b dut=%b", gold._49450_.Q, dut.control_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49451_.Q !== dut.control_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26619 gold=%b dut=%b", gold._49451_.Q, dut.control_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49452_.Q !== dut.control_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26620 gold=%b dut=%b", gold._49452_.Q, dut.control_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49453_.Q !== dut.control_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26621 gold=%b dut=%b", gold._49453_.Q, dut.control_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49454_.Q !== dut.control_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26622 gold=%b dut=%b", gold._49454_.Q, dut.control_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49455_.Q !== dut.control_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26623 gold=%b dut=%b", gold._49455_.Q, dut.control_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49456_.Q !== dut.control_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26624 gold=%b dut=%b", gold._49456_.Q, dut.control_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49457_.Q !== dut.control_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26625 gold=%b dut=%b", gold._49457_.Q, dut.control_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49458_.Q !== dut.control_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26626 gold=%b dut=%b", gold._49458_.Q, dut.control_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49459_.Q !== dut.control_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26627 gold=%b dut=%b", gold._49459_.Q, dut.control_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49460_.Q !== dut.control_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26628 gold=%b dut=%b", gold._49460_.Q, dut.control_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49461_.Q !== dut.control_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26629 gold=%b dut=%b", gold._49461_.Q, dut.control_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49462_.Q !== dut.control_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26630 gold=%b dut=%b", gold._49462_.Q, dut.control_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49463_.Q !== dut.control_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26631 gold=%b dut=%b", gold._49463_.Q, dut.control_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49464_.Q !== dut.control_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26632 gold=%b dut=%b", gold._49464_.Q, dut.control_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49465_.Q !== dut.control_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26633 gold=%b dut=%b", gold._49465_.Q, dut.control_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49466_.Q !== dut.control_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26634 gold=%b dut=%b", gold._49466_.Q, dut.control_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49467_.Q !== dut.control_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26635 gold=%b dut=%b", gold._49467_.Q, dut.control_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49468_.Q !== dut.control_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26636 gold=%b dut=%b", gold._49468_.Q, dut.control_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49469_.Q !== dut.control_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26637 gold=%b dut=%b", gold._49469_.Q, dut.control_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49470_.Q !== dut.control_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26638 gold=%b dut=%b", gold._49470_.Q, dut.control_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49471_.Q !== dut.control_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26639 gold=%b dut=%b", gold._49471_.Q, dut.control_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49472_.Q !== dut.control_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26640 gold=%b dut=%b", gold._49472_.Q, dut.control_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49473_.Q !== dut.control_reg_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26641 gold=%b dut=%b", gold._49473_.Q, dut.control_reg_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49474_.Q !== dut.control_reg_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26642 gold=%b dut=%b", gold._49474_.Q, dut.control_reg_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49475_.Q !== dut.control_reg_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26643 gold=%b dut=%b", gold._49475_.Q, dut.control_reg_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49476_.Q !== dut.control_reg_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26644 gold=%b dut=%b", gold._49476_.Q, dut.control_reg_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49477_.Q !== dut.control_reg_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26645 gold=%b dut=%b", gold._49477_.Q, dut.control_reg_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49478_.Q !== dut.control_reg_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26646 gold=%b dut=%b", gold._49478_.Q, dut.control_reg_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49479_.Q !== dut.control_reg_1[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26647 gold=%b dut=%b", gold._49479_.Q, dut.control_reg_1[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49416_.Q !== dut.fsm_state_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26648 gold=%b dut=%b", gold._49416_.Q, dut.fsm_state_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49417_.Q !== dut.fsm_state_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26649 gold=%b dut=%b", gold._49417_.Q, dut.fsm_state_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49418_.Q !== dut.fsm_state_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26650 gold=%b dut=%b", gold._49418_.Q, dut.fsm_state_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49419_.Q !== dut.fsm_state_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26651 gold=%b dut=%b", gold._49419_.Q, dut.fsm_state_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49420_.Q !== dut.fsm_state_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26652 gold=%b dut=%b", gold._49420_.Q, dut.fsm_state_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49421_.Q !== dut.fsm_state_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26653 gold=%b dut=%b", gold._49421_.Q, dut.fsm_state_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49422_.Q !== dut.payload_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26654 gold=%b dut=%b", gold._49422_.Q, dut.payload_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49423_.Q !== dut.payload_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26655 gold=%b dut=%b", gold._49423_.Q, dut.payload_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49424_.Q !== dut.payload_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26656 gold=%b dut=%b", gold._49424_.Q, dut.payload_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49425_.Q !== dut.payload_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26657 gold=%b dut=%b", gold._49425_.Q, dut.payload_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49426_.Q !== dut.payload_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26658 gold=%b dut=%b", gold._49426_.Q, dut.payload_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49427_.Q !== dut.payload_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26659 gold=%b dut=%b", gold._49427_.Q, dut.payload_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49428_.Q !== dut.payload_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26660 gold=%b dut=%b", gold._49428_.Q, dut.payload_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49429_.Q !== dut.payload_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26661 gold=%b dut=%b", gold._49429_.Q, dut.payload_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49430_.Q !== dut.payload_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26662 gold=%b dut=%b", gold._49430_.Q, dut.payload_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49431_.Q !== dut.payload_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26663 gold=%b dut=%b", gold._49431_.Q, dut.payload_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49432_.Q !== dut.payload_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26664 gold=%b dut=%b", gold._49432_.Q, dut.payload_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49433_.Q !== dut.payload_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26665 gold=%b dut=%b", gold._49433_.Q, dut.payload_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49434_.Q !== dut.payload_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26666 gold=%b dut=%b", gold._49434_.Q, dut.payload_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49435_.Q !== dut.payload_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26667 gold=%b dut=%b", gold._49435_.Q, dut.payload_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49436_.Q !== dut.payload_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26668 gold=%b dut=%b", gold._49436_.Q, dut.payload_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49437_.Q !== dut.payload_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26669 gold=%b dut=%b", gold._49437_.Q, dut.payload_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49438_.Q !== dut.payload_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26670 gold=%b dut=%b", gold._49438_.Q, dut.payload_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49439_.Q !== dut.payload_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26671 gold=%b dut=%b", gold._49439_.Q, dut.payload_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49440_.Q !== dut.payload_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26672 gold=%b dut=%b", gold._49440_.Q, dut.payload_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49441_.Q !== dut.payload_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26673 gold=%b dut=%b", gold._49441_.Q, dut.payload_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49442_.Q !== dut.payload_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26674 gold=%b dut=%b", gold._49442_.Q, dut.payload_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49443_.Q !== dut.payload_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26675 gold=%b dut=%b", gold._49443_.Q, dut.payload_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49444_.Q !== dut.payload_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26676 gold=%b dut=%b", gold._49444_.Q, dut.payload_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49445_.Q !== dut.payload_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26677 gold=%b dut=%b", gold._49445_.Q, dut.payload_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49446_.Q !== dut.payload_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26678 gold=%b dut=%b", gold._49446_.Q, dut.payload_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49447_.Q !== dut.unnamed_26679) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26679 gold=%b dut=%b", gold._49447_.Q, dut.unnamed_26679);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49384_.Q !== dut.data_word_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26680 gold=%b dut=%b", gold._49384_.Q, dut.data_word_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49385_.Q !== dut.data_word_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26681 gold=%b dut=%b", gold._49385_.Q, dut.data_word_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49386_.Q !== dut.data_word_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26682 gold=%b dut=%b", gold._49386_.Q, dut.data_word_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49387_.Q !== dut.data_word_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26683 gold=%b dut=%b", gold._49387_.Q, dut.data_word_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49388_.Q !== dut.data_word_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26684 gold=%b dut=%b", gold._49388_.Q, dut.data_word_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49389_.Q !== dut.data_word_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26685 gold=%b dut=%b", gold._49389_.Q, dut.data_word_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49390_.Q !== dut.data_word_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26686 gold=%b dut=%b", gold._49390_.Q, dut.data_word_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49391_.Q !== dut.data_word_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26687 gold=%b dut=%b", gold._49391_.Q, dut.data_word_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49392_.Q !== dut.data_word_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26688 gold=%b dut=%b", gold._49392_.Q, dut.data_word_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49393_.Q !== dut.data_word_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26689 gold=%b dut=%b", gold._49393_.Q, dut.data_word_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49394_.Q !== dut.data_word_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26690 gold=%b dut=%b", gold._49394_.Q, dut.data_word_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49395_.Q !== dut.data_word_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26691 gold=%b dut=%b", gold._49395_.Q, dut.data_word_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49396_.Q !== dut.data_word_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26692 gold=%b dut=%b", gold._49396_.Q, dut.data_word_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49397_.Q !== dut.data_word_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26693 gold=%b dut=%b", gold._49397_.Q, dut.data_word_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49398_.Q !== dut.data_word_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26694 gold=%b dut=%b", gold._49398_.Q, dut.data_word_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49399_.Q !== dut.data_word_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26695 gold=%b dut=%b", gold._49399_.Q, dut.data_word_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49400_.Q !== dut.data_word_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26696 gold=%b dut=%b", gold._49400_.Q, dut.data_word_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49401_.Q !== dut.data_word_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26697 gold=%b dut=%b", gold._49401_.Q, dut.data_word_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49402_.Q !== dut.data_word_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26698 gold=%b dut=%b", gold._49402_.Q, dut.data_word_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49403_.Q !== dut.data_word_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26699 gold=%b dut=%b", gold._49403_.Q, dut.data_word_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49404_.Q !== dut.data_word_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26700 gold=%b dut=%b", gold._49404_.Q, dut.data_word_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49405_.Q !== dut.data_word_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26701 gold=%b dut=%b", gold._49405_.Q, dut.data_word_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49406_.Q !== dut.data_word_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26702 gold=%b dut=%b", gold._49406_.Q, dut.data_word_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49407_.Q !== dut.data_word_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26703 gold=%b dut=%b", gold._49407_.Q, dut.data_word_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49408_.Q !== dut.data_word_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26704 gold=%b dut=%b", gold._49408_.Q, dut.data_word_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49409_.Q !== dut.data_word_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26705 gold=%b dut=%b", gold._49409_.Q, dut.data_word_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49410_.Q !== dut.data_word_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26706 gold=%b dut=%b", gold._49410_.Q, dut.data_word_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49411_.Q !== dut.data_word_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26707 gold=%b dut=%b", gold._49411_.Q, dut.data_word_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49412_.Q !== dut.data_word_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26708 gold=%b dut=%b", gold._49412_.Q, dut.data_word_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49413_.Q !== dut.data_word_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26709 gold=%b dut=%b", gold._49413_.Q, dut.data_word_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49414_.Q !== dut.data_word_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26710 gold=%b dut=%b", gold._49414_.Q, dut.data_word_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49415_.Q !== dut.data_word_1[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26711 gold=%b dut=%b", gold._49415_.Q, dut.data_word_1[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49352_.Q !== dut.wide_data_reg_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26712 gold=%b dut=%b", gold._49352_.Q, dut.wide_data_reg_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49353_.Q !== dut.wide_data_reg_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26713 gold=%b dut=%b", gold._49353_.Q, dut.wide_data_reg_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49354_.Q !== dut.wide_data_reg_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26714 gold=%b dut=%b", gold._49354_.Q, dut.wide_data_reg_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49355_.Q !== dut.wide_data_reg_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26715 gold=%b dut=%b", gold._49355_.Q, dut.wide_data_reg_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49356_.Q !== dut.wide_data_reg_4[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26716 gold=%b dut=%b", gold._49356_.Q, dut.wide_data_reg_4[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49357_.Q !== dut.wide_data_reg_4[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26717 gold=%b dut=%b", gold._49357_.Q, dut.wide_data_reg_4[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49358_.Q !== dut.wide_data_reg_4[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26718 gold=%b dut=%b", gold._49358_.Q, dut.wide_data_reg_4[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49359_.Q !== dut.wide_data_reg_4[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26719 gold=%b dut=%b", gold._49359_.Q, dut.wide_data_reg_4[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49360_.Q !== dut.wide_data_reg_4[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26720 gold=%b dut=%b", gold._49360_.Q, dut.wide_data_reg_4[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49361_.Q !== dut.wide_data_reg_4[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26721 gold=%b dut=%b", gold._49361_.Q, dut.wide_data_reg_4[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49362_.Q !== dut.wide_data_reg_4[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26722 gold=%b dut=%b", gold._49362_.Q, dut.wide_data_reg_4[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49363_.Q !== dut.wide_data_reg_4[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26723 gold=%b dut=%b", gold._49363_.Q, dut.wide_data_reg_4[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49364_.Q !== dut.wide_data_reg_4[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26724 gold=%b dut=%b", gold._49364_.Q, dut.wide_data_reg_4[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49365_.Q !== dut.wide_data_reg_4[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26725 gold=%b dut=%b", gold._49365_.Q, dut.wide_data_reg_4[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49366_.Q !== dut.wide_data_reg_4[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26726 gold=%b dut=%b", gold._49366_.Q, dut.wide_data_reg_4[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49367_.Q !== dut.wide_data_reg_4[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26727 gold=%b dut=%b", gold._49367_.Q, dut.wide_data_reg_4[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49368_.Q !== dut.wide_data_reg_4[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26728 gold=%b dut=%b", gold._49368_.Q, dut.wide_data_reg_4[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49369_.Q !== dut.wide_data_reg_4[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26729 gold=%b dut=%b", gold._49369_.Q, dut.wide_data_reg_4[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49370_.Q !== dut.wide_data_reg_4[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26730 gold=%b dut=%b", gold._49370_.Q, dut.wide_data_reg_4[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49371_.Q !== dut.wide_data_reg_4[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26731 gold=%b dut=%b", gold._49371_.Q, dut.wide_data_reg_4[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49372_.Q !== dut.wide_data_reg_4[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26732 gold=%b dut=%b", gold._49372_.Q, dut.wide_data_reg_4[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49373_.Q !== dut.wide_data_reg_4[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26733 gold=%b dut=%b", gold._49373_.Q, dut.wide_data_reg_4[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49374_.Q !== dut.wide_data_reg_4[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26734 gold=%b dut=%b", gold._49374_.Q, dut.wide_data_reg_4[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49375_.Q !== dut.wide_data_reg_4[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26735 gold=%b dut=%b", gold._49375_.Q, dut.wide_data_reg_4[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49376_.Q !== dut.wide_data_reg_4[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26736 gold=%b dut=%b", gold._49376_.Q, dut.wide_data_reg_4[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49377_.Q !== dut.wide_data_reg_4[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26737 gold=%b dut=%b", gold._49377_.Q, dut.wide_data_reg_4[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49378_.Q !== dut.wide_data_reg_4[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26738 gold=%b dut=%b", gold._49378_.Q, dut.wide_data_reg_4[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49379_.Q !== dut.wide_data_reg_4[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26739 gold=%b dut=%b", gold._49379_.Q, dut.wide_data_reg_4[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49380_.Q !== dut.wide_data_reg_4[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26740 gold=%b dut=%b", gold._49380_.Q, dut.wide_data_reg_4[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49381_.Q !== dut.wide_data_reg_4[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26741 gold=%b dut=%b", gold._49381_.Q, dut.wide_data_reg_4[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49382_.Q !== dut.status_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26742 gold=%b dut=%b", gold._49382_.Q, dut.status_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49383_.Q !== dut.status_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26743 gold=%b dut=%b", gold._49383_.Q, dut.status_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49841_.Q !== dut.data_reg_21[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26778 gold=%b dut=%b", gold._49841_.Q, dut.data_reg_21[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49842_.Q !== dut.data_reg_21[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26779 gold=%b dut=%b", gold._49842_.Q, dut.data_reg_21[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49843_.Q !== dut.data_reg_21[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26780 gold=%b dut=%b", gold._49843_.Q, dut.data_reg_21[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49844_.Q !== dut.data_reg_21[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26781 gold=%b dut=%b", gold._49844_.Q, dut.data_reg_21[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49845_.Q !== dut.data_reg_21[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26782 gold=%b dut=%b", gold._49845_.Q, dut.data_reg_21[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49846_.Q !== dut.data_reg_21[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26783 gold=%b dut=%b", gold._49846_.Q, dut.data_reg_21[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49847_.Q !== dut.data_reg_21[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26784 gold=%b dut=%b", gold._49847_.Q, dut.data_reg_21[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49848_.Q !== dut.data_reg_21[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26785 gold=%b dut=%b", gold._49848_.Q, dut.data_reg_21[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49849_.Q !== dut.data_reg_21[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26786 gold=%b dut=%b", gold._49849_.Q, dut.data_reg_21[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49850_.Q !== dut.data_reg_21[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26787 gold=%b dut=%b", gold._49850_.Q, dut.data_reg_21[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49851_.Q !== dut.data_reg_21[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26788 gold=%b dut=%b", gold._49851_.Q, dut.data_reg_21[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49852_.Q !== dut.data_reg_21[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26789 gold=%b dut=%b", gold._49852_.Q, dut.data_reg_21[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49853_.Q !== dut.data_reg_21[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26790 gold=%b dut=%b", gold._49853_.Q, dut.data_reg_21[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49854_.Q !== dut.data_reg_21[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26791 gold=%b dut=%b", gold._49854_.Q, dut.data_reg_21[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49855_.Q !== dut.data_reg_21[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26792 gold=%b dut=%b", gold._49855_.Q, dut.data_reg_21[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49856_.Q !== dut.data_reg_21[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26793 gold=%b dut=%b", gold._49856_.Q, dut.data_reg_21[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49857_.Q !== dut.data_reg_21[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26794 gold=%b dut=%b", gold._49857_.Q, dut.data_reg_21[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49858_.Q !== dut.data_reg_21[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26795 gold=%b dut=%b", gold._49858_.Q, dut.data_reg_21[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49859_.Q !== dut.data_reg_21[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26796 gold=%b dut=%b", gold._49859_.Q, dut.data_reg_21[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49860_.Q !== dut.data_reg_21[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26797 gold=%b dut=%b", gold._49860_.Q, dut.data_reg_21[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49861_.Q !== dut.data_reg_21[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26798 gold=%b dut=%b", gold._49861_.Q, dut.data_reg_21[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49862_.Q !== dut.unnamed_26799[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26799 gold=%b dut=%b", gold._49862_.Q, dut.unnamed_26799[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49863_.Q !== dut.unnamed_26799[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26800 gold=%b dut=%b", gold._49863_.Q, dut.unnamed_26799[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49864_.Q !== dut.unnamed_26799[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26801 gold=%b dut=%b", gold._49864_.Q, dut.unnamed_26799[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49865_.Q !== dut.unnamed_26799[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26802 gold=%b dut=%b", gold._49865_.Q, dut.unnamed_26799[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49866_.Q !== dut.unnamed_26799[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26803 gold=%b dut=%b", gold._49866_.Q, dut.unnamed_26799[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49867_.Q !== dut.unnamed_26799[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26804 gold=%b dut=%b", gold._49867_.Q, dut.unnamed_26799[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49868_.Q !== dut.unnamed_26799[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26805 gold=%b dut=%b", gold._49868_.Q, dut.unnamed_26799[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49869_.Q !== dut.unnamed_26799[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26806 gold=%b dut=%b", gold._49869_.Q, dut.unnamed_26799[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49870_.Q !== dut.unnamed_26799[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26807 gold=%b dut=%b", gold._49870_.Q, dut.unnamed_26799[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49840_.Q !== dut.status_flag_5) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26808 gold=%b dut=%b", gold._49840_.Q, dut.status_flag_5);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49839_.Q !== dut.mode_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26842 gold=%b dut=%b", gold._49839_.Q, dut.mode_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49871_.Q !== dut.unnamed_26843[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26843 gold=%b dut=%b", gold._49871_.Q, dut.unnamed_26843[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49872_.Q !== dut.unnamed_26843[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26844 gold=%b dut=%b", gold._49872_.Q, dut.unnamed_26843[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49873_.Q !== dut.unnamed_26843[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26845 gold=%b dut=%b", gold._49873_.Q, dut.unnamed_26843[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49874_.Q !== dut.unnamed_26843[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26846 gold=%b dut=%b", gold._49874_.Q, dut.unnamed_26843[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49875_.Q !== dut.unnamed_26843[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26847 gold=%b dut=%b", gold._49875_.Q, dut.unnamed_26843[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49876_.Q !== dut.unnamed_26843[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26848 gold=%b dut=%b", gold._49876_.Q, dut.unnamed_26843[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49877_.Q !== dut.unnamed_26843[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26849 gold=%b dut=%b", gold._49877_.Q, dut.unnamed_26843[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49878_.Q !== dut.unnamed_26843[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26850 gold=%b dut=%b", gold._49878_.Q, dut.unnamed_26843[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49879_.Q !== dut.unnamed_26843[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26851 gold=%b dut=%b", gold._49879_.Q, dut.unnamed_26843[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49880_.Q !== dut.unnamed_26843[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26852 gold=%b dut=%b", gold._49880_.Q, dut.unnamed_26843[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49881_.Q !== dut.unnamed_26843[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26853 gold=%b dut=%b", gold._49881_.Q, dut.unnamed_26843[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49882_.Q !== dut.unnamed_26843[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26854 gold=%b dut=%b", gold._49882_.Q, dut.unnamed_26843[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49883_.Q !== dut.unnamed_26843[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26855 gold=%b dut=%b", gold._49883_.Q, dut.unnamed_26843[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49884_.Q !== dut.unnamed_26843[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26856 gold=%b dut=%b", gold._49884_.Q, dut.unnamed_26843[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49885_.Q !== dut.unnamed_26843[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26857 gold=%b dut=%b", gold._49885_.Q, dut.unnamed_26843[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49886_.Q !== dut.unnamed_26843[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26858 gold=%b dut=%b", gold._49886_.Q, dut.unnamed_26843[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49887_.Q !== dut.unnamed_26843[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26859 gold=%b dut=%b", gold._49887_.Q, dut.unnamed_26843[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49888_.Q !== dut.unnamed_26843[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26860 gold=%b dut=%b", gold._49888_.Q, dut.unnamed_26843[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49889_.Q !== dut.unnamed_26843[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26861 gold=%b dut=%b", gold._49889_.Q, dut.unnamed_26843[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49890_.Q !== dut.unnamed_26843[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26862 gold=%b dut=%b", gold._49890_.Q, dut.unnamed_26843[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49891_.Q !== dut.unnamed_26843[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26863 gold=%b dut=%b", gold._49891_.Q, dut.unnamed_26843[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49892_.Q !== dut.unnamed_26843[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26864 gold=%b dut=%b", gold._49892_.Q, dut.unnamed_26843[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49893_.Q !== dut.unnamed_26843[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26865 gold=%b dut=%b", gold._49893_.Q, dut.unnamed_26843[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49894_.Q !== dut.unnamed_26843[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26866 gold=%b dut=%b", gold._49894_.Q, dut.unnamed_26843[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49895_.Q !== dut.unnamed_26843[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26867 gold=%b dut=%b", gold._49895_.Q, dut.unnamed_26843[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49896_.Q !== dut.unnamed_26843[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26868 gold=%b dut=%b", gold._49896_.Q, dut.unnamed_26843[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49897_.Q !== dut.unnamed_26843[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26869 gold=%b dut=%b", gold._49897_.Q, dut.unnamed_26843[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49898_.Q !== dut.unnamed_26843[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26870 gold=%b dut=%b", gold._49898_.Q, dut.unnamed_26843[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49899_.Q !== dut.unnamed_26843[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26871 gold=%b dut=%b", gold._49899_.Q, dut.unnamed_26843[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49900_.Q !== dut.unnamed_26843[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26872 gold=%b dut=%b", gold._49900_.Q, dut.unnamed_26843[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49901_.Q !== dut.unnamed_26843[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26873 gold=%b dut=%b", gold._49901_.Q, dut.unnamed_26843[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49902_.Q !== dut.mux_sample_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26874 gold=%b dut=%b", gold._49902_.Q, dut.mux_sample_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49903_.Q !== dut.mux_sample_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26875 gold=%b dut=%b", gold._49903_.Q, dut.mux_sample_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49904_.Q !== dut.mux_sample_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26876 gold=%b dut=%b", gold._49904_.Q, dut.mux_sample_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49905_.Q !== dut.mux_sample_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26877 gold=%b dut=%b", gold._49905_.Q, dut.mux_sample_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49906_.Q !== dut.mux_sample_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26878 gold=%b dut=%b", gold._49906_.Q, dut.mux_sample_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50487_.Q !== dut.status_flag_6) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26879 gold=%b dut=%b", gold._50487_.Q, dut.status_flag_6);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49300_.Q !== dut.decoded_select_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26880 gold=%b dut=%b", gold._49300_.Q, dut.decoded_select_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49301_.Q !== dut.decoded_select_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26881 gold=%b dut=%b", gold._49301_.Q, dut.decoded_select_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49302_.Q !== dut.decoded_select_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26882 gold=%b dut=%b", gold._49302_.Q, dut.decoded_select_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49303_.Q !== dut.decoded_select_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26883 gold=%b dut=%b", gold._49303_.Q, dut.decoded_select_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49304_.Q !== dut.decoded_select_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26884 gold=%b dut=%b", gold._49304_.Q, dut.decoded_select_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49305_.Q !== dut.decoded_select_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26885 gold=%b dut=%b", gold._49305_.Q, dut.decoded_select_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49307_.Q !== dut.decoded_select_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26886 gold=%b dut=%b", gold._49307_.Q, dut.decoded_select_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49308_.Q !== dut.decoded_select_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26887 gold=%b dut=%b", gold._49308_.Q, dut.decoded_select_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49309_.Q !== dut.decoded_select_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26888 gold=%b dut=%b", gold._49309_.Q, dut.decoded_select_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49310_.Q !== dut.decoded_select_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26889 gold=%b dut=%b", gold._49310_.Q, dut.decoded_select_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49311_.Q !== dut.decoded_select_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26890 gold=%b dut=%b", gold._49311_.Q, dut.decoded_select_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49312_.Q !== dut.decoded_select_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26891 gold=%b dut=%b", gold._49312_.Q, dut.decoded_select_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49313_.Q !== dut.decoded_select_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26892 gold=%b dut=%b", gold._49313_.Q, dut.decoded_select_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49314_.Q !== dut.decoded_select_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26893 gold=%b dut=%b", gold._49314_.Q, dut.decoded_select_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49315_.Q !== dut.decoded_select_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26894 gold=%b dut=%b", gold._49315_.Q, dut.decoded_select_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49316_.Q !== dut.decoded_select_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26895 gold=%b dut=%b", gold._49316_.Q, dut.decoded_select_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49318_.Q !== dut.decoded_select_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26896 gold=%b dut=%b", gold._49318_.Q, dut.decoded_select_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49319_.Q !== dut.decoded_select_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26897 gold=%b dut=%b", gold._49319_.Q, dut.decoded_select_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49320_.Q !== dut.decoded_select_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26898 gold=%b dut=%b", gold._49320_.Q, dut.decoded_select_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49321_.Q !== dut.decoded_select_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26899 gold=%b dut=%b", gold._49321_.Q, dut.decoded_select_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49322_.Q !== dut.decoded_select_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26900 gold=%b dut=%b", gold._49322_.Q, dut.decoded_select_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49323_.Q !== dut.decoded_select_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26901 gold=%b dut=%b", gold._49323_.Q, dut.decoded_select_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49324_.Q !== dut.decoded_select_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26902 gold=%b dut=%b", gold._49324_.Q, dut.decoded_select_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49325_.Q !== dut.decoded_select_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26903 gold=%b dut=%b", gold._49325_.Q, dut.decoded_select_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49326_.Q !== dut.decoded_select_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26904 gold=%b dut=%b", gold._49326_.Q, dut.decoded_select_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49327_.Q !== dut.decoded_select_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26905 gold=%b dut=%b", gold._49327_.Q, dut.decoded_select_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49329_.Q !== dut.decoded_select_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26906 gold=%b dut=%b", gold._49329_.Q, dut.decoded_select_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49330_.Q !== dut.decoded_select_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26907 gold=%b dut=%b", gold._49330_.Q, dut.decoded_select_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49331_.Q !== dut.decoded_select_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26908 gold=%b dut=%b", gold._49331_.Q, dut.decoded_select_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49332_.Q !== dut.decoded_select_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26909 gold=%b dut=%b", gold._49332_.Q, dut.decoded_select_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49295_.Q !== dut.control_flag_5) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26910 gold=%b dut=%b", gold._49295_.Q, dut.control_flag_5);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50481_.Q !== dut.datapath_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26912 gold=%b dut=%b", gold._50481_.Q, dut.datapath_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50482_.Q !== dut.datapath_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26913 gold=%b dut=%b", gold._50482_.Q, dut.datapath_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50483_.Q !== dut.datapath_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26914 gold=%b dut=%b", gold._50483_.Q, dut.datapath_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50476_.Q !== dut.datapath_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26915 gold=%b dut=%b", gold._50476_.Q, dut.datapath_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50480_.Q !== dut.datapath_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26916 gold=%b dut=%b", gold._50480_.Q, dut.datapath_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50484_.Q !== dut.datapath_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26917 gold=%b dut=%b", gold._50484_.Q, dut.datapath_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50485_.Q !== dut.datapath_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26918 gold=%b dut=%b", gold._50485_.Q, dut.datapath_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50478_.Q !== dut.datapath_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26919 gold=%b dut=%b", gold._50478_.Q, dut.datapath_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50479_.Q !== dut.datapath_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26920 gold=%b dut=%b", gold._50479_.Q, dut.datapath_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50486_.Q !== dut.datapath_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26921 gold=%b dut=%b", gold._50486_.Q, dut.datapath_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50475_.Q !== dut.datapath_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26922 gold=%b dut=%b", gold._50475_.Q, dut.datapath_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50467_.Q !== dut.datapath_flags[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26923 gold=%b dut=%b", gold._50467_.Q, dut.datapath_flags[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50468_.Q !== dut.datapath_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26924 gold=%b dut=%b", gold._50468_.Q, dut.datapath_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50469_.Q !== dut.datapath_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26925 gold=%b dut=%b", gold._50469_.Q, dut.datapath_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50470_.Q !== dut.datapath_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26926 gold=%b dut=%b", gold._50470_.Q, dut.datapath_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50471_.Q !== dut.datapath_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26927 gold=%b dut=%b", gold._50471_.Q, dut.datapath_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50472_.Q !== dut.datapath_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26928 gold=%b dut=%b", gold._50472_.Q, dut.datapath_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50473_.Q !== dut.datapath_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26929 gold=%b dut=%b", gold._50473_.Q, dut.datapath_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50474_.Q !== dut.datapath_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26930 gold=%b dut=%b", gold._50474_.Q, dut.datapath_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50477_.Q !== dut.datapath_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26942 gold=%b dut=%b", gold._50477_.Q, dut.datapath_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50499_.Q !== dut.result_condition_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26943 gold=%b dut=%b", gold._50499_.Q, dut.result_condition_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50500_.Q !== dut.result_condition_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26944 gold=%b dut=%b", gold._50500_.Q, dut.result_condition_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50501_.Q !== dut.result_condition_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26945 gold=%b dut=%b", gold._50501_.Q, dut.result_condition_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50502_.Q !== dut.control_state_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26946 gold=%b dut=%b", gold._50502_.Q, dut.control_state_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50503_.Q !== dut.control_state_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26947 gold=%b dut=%b", gold._50503_.Q, dut.control_state_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50493_.Q !== dut.result_condition_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26955 gold=%b dut=%b", gold._50493_.Q, dut.result_condition_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50494_.Q !== dut.result_condition_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26956 gold=%b dut=%b", gold._50494_.Q, dut.result_condition_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50495_.Q !== dut.result_condition_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26957 gold=%b dut=%b", gold._50495_.Q, dut.result_condition_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50496_.Q !== dut.result_condition_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26958 gold=%b dut=%b", gold._50496_.Q, dut.result_condition_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50497_.Q !== dut.result_condition_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26959 gold=%b dut=%b", gold._50497_.Q, dut.result_condition_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50498_.Q !== dut.result_condition_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26960 gold=%b dut=%b", gold._50498_.Q, dut.result_condition_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50488_.Q !== dut.result_condition_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26961 gold=%b dut=%b", gold._50488_.Q, dut.result_condition_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50489_.Q !== dut.result_condition_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26962 gold=%b dut=%b", gold._50489_.Q, dut.result_condition_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50490_.Q !== dut.result_condition_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26963 gold=%b dut=%b", gold._50490_.Q, dut.result_condition_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50491_.Q !== dut.result_condition_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26964 gold=%b dut=%b", gold._50491_.Q, dut.result_condition_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50492_.Q !== dut.result_condition_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26965 gold=%b dut=%b", gold._50492_.Q, dut.result_condition_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49673_.Q !== dut.fsm_state_bit_0) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26966 gold=%b dut=%b", gold._49673_.Q, dut.fsm_state_bit_0);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48310_.Q !== dut.compare_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26967 gold=%b dut=%b", gold._48310_.Q, dut.compare_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50004_.Q !== dut.zero_pattern_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26968 gold=%b dut=%b", gold._50004_.Q, dut.zero_pattern_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49930_.Q !== dut.event_delay_shift[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26969 gold=%b dut=%b", gold._49930_.Q, dut.event_delay_shift[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50543_.Q !== dut.data_reg_7_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26975 gold=%b dut=%b", gold._50543_.Q, dut.data_reg_7_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50544_.Q !== dut.data_reg_7_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26976 gold=%b dut=%b", gold._50544_.Q, dut.data_reg_7_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50545_.Q !== dut.data_reg_7_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26977 gold=%b dut=%b", gold._50545_.Q, dut.data_reg_7_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50546_.Q !== dut.data_reg_7_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26978 gold=%b dut=%b", gold._50546_.Q, dut.data_reg_7_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50547_.Q !== dut.data_reg_7_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26979 gold=%b dut=%b", gold._50547_.Q, dut.data_reg_7_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50548_.Q !== dut.data_reg_7_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26980 gold=%b dut=%b", gold._50548_.Q, dut.data_reg_7_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50549_.Q !== dut.data_reg_7_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26981 gold=%b dut=%b", gold._50549_.Q, dut.data_reg_7_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50550_.Q !== dut.data_reg_5_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26982 gold=%b dut=%b", gold._50550_.Q, dut.data_reg_5_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50551_.Q !== dut.data_reg_5_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26983 gold=%b dut=%b", gold._50551_.Q, dut.data_reg_5_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50552_.Q !== dut.data_reg_5_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26984 gold=%b dut=%b", gold._50552_.Q, dut.data_reg_5_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50553_.Q !== dut.data_reg_5_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26985 gold=%b dut=%b", gold._50553_.Q, dut.data_reg_5_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50554_.Q !== dut.data_reg_5_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26986 gold=%b dut=%b", gold._50554_.Q, dut.data_reg_5_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50555_.Q !== dut.data_reg_3_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26987 gold=%b dut=%b", gold._50555_.Q, dut.data_reg_3_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50556_.Q !== dut.data_reg_3_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26988 gold=%b dut=%b", gold._50556_.Q, dut.data_reg_3_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50557_.Q !== dut.data_reg_3_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26989 gold=%b dut=%b", gold._50557_.Q, dut.data_reg_3_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50558_.Q !== dut.data_reg_10_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26990 gold=%b dut=%b", gold._50558_.Q, dut.data_reg_10_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50559_.Q !== dut.data_reg_10_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26991 gold=%b dut=%b", gold._50559_.Q, dut.data_reg_10_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50560_.Q !== dut.data_reg_10_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26992 gold=%b dut=%b", gold._50560_.Q, dut.data_reg_10_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50561_.Q !== dut.data_reg_10_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26993 gold=%b dut=%b", gold._50561_.Q, dut.data_reg_10_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50562_.Q !== dut.data_reg_10_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26994 gold=%b dut=%b", gold._50562_.Q, dut.data_reg_10_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50563_.Q !== dut.data_reg_10_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26995 gold=%b dut=%b", gold._50563_.Q, dut.data_reg_10_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50564_.Q !== dut.data_reg_10_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26996 gold=%b dut=%b", gold._50564_.Q, dut.data_reg_10_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50565_.Q !== dut.data_reg_10_0[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26997 gold=%b dut=%b", gold._50565_.Q, dut.data_reg_10_0[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50566_.Q !== dut.data_reg_10_0[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26998 gold=%b dut=%b", gold._50566_.Q, dut.data_reg_10_0[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50567_.Q !== dut.data_reg_10_0[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26999 gold=%b dut=%b", gold._50567_.Q, dut.data_reg_10_0[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50568_.Q !== dut.data_reg_7_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27000 gold=%b dut=%b", gold._50568_.Q, dut.data_reg_7_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50569_.Q !== dut.data_reg_7_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27001 gold=%b dut=%b", gold._50569_.Q, dut.data_reg_7_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50570_.Q !== dut.data_reg_7_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27002 gold=%b dut=%b", gold._50570_.Q, dut.data_reg_7_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50571_.Q !== dut.data_reg_7_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27003 gold=%b dut=%b", gold._50571_.Q, dut.data_reg_7_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50572_.Q !== dut.data_reg_7_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27004 gold=%b dut=%b", gold._50572_.Q, dut.data_reg_7_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50573_.Q !== dut.data_reg_7_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27005 gold=%b dut=%b", gold._50573_.Q, dut.data_reg_7_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50574_.Q !== dut.data_reg_7_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27006 gold=%b dut=%b", gold._50574_.Q, dut.data_reg_7_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49674_.Q !== dut.fsm_state_bit_1) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27072 gold=%b dut=%b", gold._49674_.Q, dut.fsm_state_bit_1);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48423_.Q !== dut.unnamed_27075[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27075 gold=%b dut=%b", gold._48423_.Q, dut.unnamed_27075[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48424_.Q !== dut.unnamed_27075[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27076 gold=%b dut=%b", gold._48424_.Q, dut.unnamed_27075[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48425_.Q !== dut.unnamed_27075[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27077 gold=%b dut=%b", gold._48425_.Q, dut.unnamed_27075[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48426_.Q !== dut.unnamed_27075[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27078 gold=%b dut=%b", gold._48426_.Q, dut.unnamed_27075[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48427_.Q !== dut.unnamed_27075[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27079 gold=%b dut=%b", gold._48427_.Q, dut.unnamed_27075[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48428_.Q !== dut.unnamed_27075[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27080 gold=%b dut=%b", gold._48428_.Q, dut.unnamed_27075[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48429_.Q !== dut.unnamed_27075[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27081 gold=%b dut=%b", gold._48429_.Q, dut.unnamed_27075[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48430_.Q !== dut.unnamed_27075[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27082 gold=%b dut=%b", gold._48430_.Q, dut.unnamed_27075[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48431_.Q !== dut.unnamed_27075[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27083 gold=%b dut=%b", gold._48431_.Q, dut.unnamed_27075[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48432_.Q !== dut.unnamed_27075[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27084 gold=%b dut=%b", gold._48432_.Q, dut.unnamed_27075[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48433_.Q !== dut.unnamed_27075[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27085 gold=%b dut=%b", gold._48433_.Q, dut.unnamed_27075[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48434_.Q !== dut.unnamed_27075[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27086 gold=%b dut=%b", gold._48434_.Q, dut.unnamed_27075[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48435_.Q !== dut.unnamed_27075[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27087 gold=%b dut=%b", gold._48435_.Q, dut.unnamed_27075[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48436_.Q !== dut.unnamed_27075[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27088 gold=%b dut=%b", gold._48436_.Q, dut.unnamed_27075[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48437_.Q !== dut.unnamed_27075[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27089 gold=%b dut=%b", gold._48437_.Q, dut.unnamed_27075[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48438_.Q !== dut.unnamed_27075[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27090 gold=%b dut=%b", gold._48438_.Q, dut.unnamed_27075[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48439_.Q !== dut.unnamed_27075[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27091 gold=%b dut=%b", gold._48439_.Q, dut.unnamed_27075[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48440_.Q !== dut.unnamed_27075[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27092 gold=%b dut=%b", gold._48440_.Q, dut.unnamed_27075[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48441_.Q !== dut.unnamed_27075[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27093 gold=%b dut=%b", gold._48441_.Q, dut.unnamed_27075[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48442_.Q !== dut.unnamed_27075[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27094 gold=%b dut=%b", gold._48442_.Q, dut.unnamed_27075[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48443_.Q !== dut.unnamed_27075[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27095 gold=%b dut=%b", gold._48443_.Q, dut.unnamed_27075[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48444_.Q !== dut.unnamed_27075[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27096 gold=%b dut=%b", gold._48444_.Q, dut.unnamed_27075[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48445_.Q !== dut.unnamed_27075[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27097 gold=%b dut=%b", gold._48445_.Q, dut.unnamed_27075[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48446_.Q !== dut.unnamed_27075[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27098 gold=%b dut=%b", gold._48446_.Q, dut.unnamed_27075[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48447_.Q !== dut.unnamed_27075[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27099 gold=%b dut=%b", gold._48447_.Q, dut.unnamed_27075[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48448_.Q !== dut.unnamed_27075[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27100 gold=%b dut=%b", gold._48448_.Q, dut.unnamed_27075[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48449_.Q !== dut.unnamed_27075[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27101 gold=%b dut=%b", gold._48449_.Q, dut.unnamed_27075[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48450_.Q !== dut.unnamed_27075[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27102 gold=%b dut=%b", gold._48450_.Q, dut.unnamed_27075[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48451_.Q !== dut.unnamed_27075[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27103 gold=%b dut=%b", gold._48451_.Q, dut.unnamed_27075[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48452_.Q !== dut.unnamed_27075[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27104 gold=%b dut=%b", gold._48452_.Q, dut.unnamed_27075[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48453_.Q !== dut.unnamed_27075[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27105 gold=%b dut=%b", gold._48453_.Q, dut.unnamed_27075[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48454_.Q !== dut.unnamed_27075[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27106 gold=%b dut=%b", gold._48454_.Q, dut.unnamed_27075[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48455_.Q !== dut.unnamed_27075[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27107 gold=%b dut=%b", gold._48455_.Q, dut.unnamed_27075[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48456_.Q !== dut.unnamed_27075[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27108 gold=%b dut=%b", gold._48456_.Q, dut.unnamed_27075[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48457_.Q !== dut.unnamed_27075[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27109 gold=%b dut=%b", gold._48457_.Q, dut.unnamed_27075[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48458_.Q !== dut.unnamed_27075[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27110 gold=%b dut=%b", gold._48458_.Q, dut.unnamed_27075[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48459_.Q !== dut.unnamed_27075[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27111 gold=%b dut=%b", gold._48459_.Q, dut.unnamed_27075[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48460_.Q !== dut.unnamed_27075[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27112 gold=%b dut=%b", gold._48460_.Q, dut.unnamed_27075[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48461_.Q !== dut.unnamed_27075[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27113 gold=%b dut=%b", gold._48461_.Q, dut.unnamed_27075[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48462_.Q !== dut.control_state_5[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27114 gold=%b dut=%b", gold._48462_.Q, dut.control_state_5[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48463_.Q !== dut.control_state_5[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27115 gold=%b dut=%b", gold._48463_.Q, dut.control_state_5[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48464_.Q !== dut.control_state_5[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27116 gold=%b dut=%b", gold._48464_.Q, dut.control_state_5[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48465_.Q !== dut.control_state_5[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27117 gold=%b dut=%b", gold._48465_.Q, dut.control_state_5[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48466_.Q !== dut.control_state_5[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27118 gold=%b dut=%b", gold._48466_.Q, dut.control_state_5[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48467_.Q !== dut.control_state_5[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27119 gold=%b dut=%b", gold._48467_.Q, dut.control_state_5[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48468_.Q !== dut.control_state_5[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27120 gold=%b dut=%b", gold._48468_.Q, dut.control_state_5[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48469_.Q !== dut.control_state_5[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27121 gold=%b dut=%b", gold._48469_.Q, dut.control_state_5[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48470_.Q !== dut.control_state_5[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27122 gold=%b dut=%b", gold._48470_.Q, dut.control_state_5[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48471_.Q !== dut.control_state_5[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27123 gold=%b dut=%b", gold._48471_.Q, dut.control_state_5[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48472_.Q !== dut.control_state_5[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27124 gold=%b dut=%b", gold._48472_.Q, dut.control_state_5[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48473_.Q !== dut.control_state_5[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27125 gold=%b dut=%b", gold._48473_.Q, dut.control_state_5[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48474_.Q !== dut.control_state_5[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27126 gold=%b dut=%b", gold._48474_.Q, dut.control_state_5[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48475_.Q !== dut.control_state_5[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27127 gold=%b dut=%b", gold._48475_.Q, dut.control_state_5[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48476_.Q !== dut.control_state_5[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27128 gold=%b dut=%b", gold._48476_.Q, dut.control_state_5[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48477_.Q !== dut.control_state_5[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27129 gold=%b dut=%b", gold._48477_.Q, dut.control_state_5[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48478_.Q !== dut.control_state_5[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27130 gold=%b dut=%b", gold._48478_.Q, dut.control_state_5[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48479_.Q !== dut.control_state_5[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27131 gold=%b dut=%b", gold._48479_.Q, dut.control_state_5[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48480_.Q !== dut.control_state_5[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27132 gold=%b dut=%b", gold._48480_.Q, dut.control_state_5[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48481_.Q !== dut.control_state_5[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27133 gold=%b dut=%b", gold._48481_.Q, dut.control_state_5[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48482_.Q !== dut.control_state_5[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27134 gold=%b dut=%b", gold._48482_.Q, dut.control_state_5[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48483_.Q !== dut.control_state_5[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27135 gold=%b dut=%b", gold._48483_.Q, dut.control_state_5[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48484_.Q !== dut.control_state_5[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27136 gold=%b dut=%b", gold._48484_.Q, dut.control_state_5[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48485_.Q !== dut.control_state_5[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27137 gold=%b dut=%b", gold._48485_.Q, dut.control_state_5[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48486_.Q !== dut.control_state_5[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27138 gold=%b dut=%b", gold._48486_.Q, dut.control_state_5[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49965_.Q !== dut.data_word_a[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27140 gold=%b dut=%b", gold._49965_.Q, dut.data_word_a[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49966_.Q !== dut.data_word_a[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27141 gold=%b dut=%b", gold._49966_.Q, dut.data_word_a[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49967_.Q !== dut.data_word_a[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27142 gold=%b dut=%b", gold._49967_.Q, dut.data_word_a[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49968_.Q !== dut.data_word_a[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27143 gold=%b dut=%b", gold._49968_.Q, dut.data_word_a[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49969_.Q !== dut.data_word_a[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27144 gold=%b dut=%b", gold._49969_.Q, dut.data_word_a[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49970_.Q !== dut.data_word_a[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27145 gold=%b dut=%b", gold._49970_.Q, dut.data_word_a[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49971_.Q !== dut.data_word_a[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27146 gold=%b dut=%b", gold._49971_.Q, dut.data_word_a[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49972_.Q !== dut.data_word_a[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27147 gold=%b dut=%b", gold._49972_.Q, dut.data_word_a[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49973_.Q !== dut.data_word_a[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27148 gold=%b dut=%b", gold._49973_.Q, dut.data_word_a[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49974_.Q !== dut.data_word_a[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27149 gold=%b dut=%b", gold._49974_.Q, dut.data_word_a[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49975_.Q !== dut.data_word_a[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27150 gold=%b dut=%b", gold._49975_.Q, dut.data_word_a[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49976_.Q !== dut.data_word_a[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27151 gold=%b dut=%b", gold._49976_.Q, dut.data_word_a[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49977_.Q !== dut.data_word_a[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27152 gold=%b dut=%b", gold._49977_.Q, dut.data_word_a[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49978_.Q !== dut.data_word_a[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27153 gold=%b dut=%b", gold._49978_.Q, dut.data_word_a[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49979_.Q !== dut.data_word_a[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27154 gold=%b dut=%b", gold._49979_.Q, dut.data_word_a[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49980_.Q !== dut.data_word_a[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27155 gold=%b dut=%b", gold._49980_.Q, dut.data_word_a[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49981_.Q !== dut.data_word_a[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27156 gold=%b dut=%b", gold._49981_.Q, dut.data_word_a[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49982_.Q !== dut.data_word_a[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27157 gold=%b dut=%b", gold._49982_.Q, dut.data_word_a[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49983_.Q !== dut.data_word_a[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27158 gold=%b dut=%b", gold._49983_.Q, dut.data_word_a[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49984_.Q !== dut.data_word_a[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27159 gold=%b dut=%b", gold._49984_.Q, dut.data_word_a[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49985_.Q !== dut.data_word_a[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27160 gold=%b dut=%b", gold._49985_.Q, dut.data_word_a[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49986_.Q !== dut.data_word_a[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27161 gold=%b dut=%b", gold._49986_.Q, dut.data_word_a[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49987_.Q !== dut.data_word_a[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27162 gold=%b dut=%b", gold._49987_.Q, dut.data_word_a[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49988_.Q !== dut.data_word_a[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27163 gold=%b dut=%b", gold._49988_.Q, dut.data_word_a[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49989_.Q !== dut.data_word_a[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27164 gold=%b dut=%b", gold._49989_.Q, dut.data_word_a[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49990_.Q !== dut.data_word_a[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27165 gold=%b dut=%b", gold._49990_.Q, dut.data_word_a[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49991_.Q !== dut.data_word_a[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27166 gold=%b dut=%b", gold._49991_.Q, dut.data_word_a[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49992_.Q !== dut.data_word_a[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27167 gold=%b dut=%b", gold._49992_.Q, dut.data_word_a[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49993_.Q !== dut.data_word_a[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27168 gold=%b dut=%b", gold._49993_.Q, dut.data_word_a[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49994_.Q !== dut.data_word_a[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27169 gold=%b dut=%b", gold._49994_.Q, dut.data_word_a[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49995_.Q !== dut.data_word_a[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27170 gold=%b dut=%b", gold._49995_.Q, dut.data_word_a[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49996_.Q !== dut.data_word_a[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27171 gold=%b dut=%b", gold._49996_.Q, dut.data_word_a[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49997_.Q !== dut.data_word_a[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27172 gold=%b dut=%b", gold._49997_.Q, dut.data_word_a[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49932_.Q !== dut.input_capture_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27173 gold=%b dut=%b", gold._49932_.Q, dut.input_capture_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49933_.Q !== dut.input_capture_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27174 gold=%b dut=%b", gold._49933_.Q, dut.input_capture_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49934_.Q !== dut.input_capture_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27175 gold=%b dut=%b", gold._49934_.Q, dut.input_capture_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49935_.Q !== dut.input_capture_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27176 gold=%b dut=%b", gold._49935_.Q, dut.input_capture_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49936_.Q !== dut.input_capture_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27177 gold=%b dut=%b", gold._49936_.Q, dut.input_capture_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49937_.Q !== dut.input_capture_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27178 gold=%b dut=%b", gold._49937_.Q, dut.input_capture_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49938_.Q !== dut.input_capture_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27179 gold=%b dut=%b", gold._49938_.Q, dut.input_capture_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49939_.Q !== dut.input_capture_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27180 gold=%b dut=%b", gold._49939_.Q, dut.input_capture_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49940_.Q !== dut.input_capture_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27181 gold=%b dut=%b", gold._49940_.Q, dut.input_capture_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49941_.Q !== dut.input_capture_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27182 gold=%b dut=%b", gold._49941_.Q, dut.input_capture_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49942_.Q !== dut.input_capture_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27183 gold=%b dut=%b", gold._49942_.Q, dut.input_capture_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49943_.Q !== dut.input_capture_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27184 gold=%b dut=%b", gold._49943_.Q, dut.input_capture_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49944_.Q !== dut.input_capture_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27185 gold=%b dut=%b", gold._49944_.Q, dut.input_capture_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49945_.Q !== dut.input_capture_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27186 gold=%b dut=%b", gold._49945_.Q, dut.input_capture_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49946_.Q !== dut.input_capture_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27187 gold=%b dut=%b", gold._49946_.Q, dut.input_capture_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49947_.Q !== dut.input_capture_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27188 gold=%b dut=%b", gold._49947_.Q, dut.input_capture_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49948_.Q !== dut.input_capture_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27189 gold=%b dut=%b", gold._49948_.Q, dut.input_capture_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49949_.Q !== dut.input_capture_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27190 gold=%b dut=%b", gold._49949_.Q, dut.input_capture_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49950_.Q !== dut.input_capture_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27191 gold=%b dut=%b", gold._49950_.Q, dut.input_capture_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49951_.Q !== dut.input_capture_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27192 gold=%b dut=%b", gold._49951_.Q, dut.input_capture_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49952_.Q !== dut.input_capture_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27193 gold=%b dut=%b", gold._49952_.Q, dut.input_capture_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49953_.Q !== dut.input_capture_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27194 gold=%b dut=%b", gold._49953_.Q, dut.input_capture_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49954_.Q !== dut.input_capture_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27195 gold=%b dut=%b", gold._49954_.Q, dut.input_capture_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49955_.Q !== dut.input_capture_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27196 gold=%b dut=%b", gold._49955_.Q, dut.input_capture_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49956_.Q !== dut.input_capture_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27197 gold=%b dut=%b", gold._49956_.Q, dut.input_capture_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49957_.Q !== dut.input_capture_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27198 gold=%b dut=%b", gold._49957_.Q, dut.input_capture_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49958_.Q !== dut.input_capture_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27199 gold=%b dut=%b", gold._49958_.Q, dut.input_capture_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49959_.Q !== dut.input_capture_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27200 gold=%b dut=%b", gold._49959_.Q, dut.input_capture_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49960_.Q !== dut.input_capture_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27201 gold=%b dut=%b", gold._49960_.Q, dut.input_capture_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49961_.Q !== dut.input_capture_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27202 gold=%b dut=%b", gold._49961_.Q, dut.input_capture_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49962_.Q !== dut.input_capture_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27203 gold=%b dut=%b", gold._49962_.Q, dut.input_capture_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49963_.Q !== dut.input_capture_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27204 gold=%b dut=%b", gold._49963_.Q, dut.input_capture_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49964_.Q !== dut.data_word_b_msb_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27205 gold=%b dut=%b", gold._49964_.Q, dut.data_word_b_msb_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48422_.Q !== dut.unnamed_27206) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27206 gold=%b dut=%b", gold._48422_.Q, dut.unnamed_27206);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50023_.Q !== dut.compare_data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27208 gold=%b dut=%b", gold._50023_.Q, dut.compare_data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50024_.Q !== dut.compare_data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27209 gold=%b dut=%b", gold._50024_.Q, dut.compare_data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50025_.Q !== dut.compare_data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27210 gold=%b dut=%b", gold._50025_.Q, dut.compare_data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50026_.Q !== dut.compare_data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27211 gold=%b dut=%b", gold._50026_.Q, dut.compare_data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50027_.Q !== dut.compare_data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27212 gold=%b dut=%b", gold._50027_.Q, dut.compare_data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50028_.Q !== dut.compare_data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27213 gold=%b dut=%b", gold._50028_.Q, dut.compare_data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50029_.Q !== dut.compare_data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27214 gold=%b dut=%b", gold._50029_.Q, dut.compare_data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50030_.Q !== dut.compare_data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27215 gold=%b dut=%b", gold._50030_.Q, dut.compare_data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50031_.Q !== dut.compare_data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27216 gold=%b dut=%b", gold._50031_.Q, dut.compare_data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50032_.Q !== dut.compare_data_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27217 gold=%b dut=%b", gold._50032_.Q, dut.compare_data_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50033_.Q !== dut.compare_data_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27218 gold=%b dut=%b", gold._50033_.Q, dut.compare_data_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50034_.Q !== dut.compare_data_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27219 gold=%b dut=%b", gold._50034_.Q, dut.compare_data_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50035_.Q !== dut.compare_data_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27220 gold=%b dut=%b", gold._50035_.Q, dut.compare_data_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50036_.Q !== dut.compare_data_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27221 gold=%b dut=%b", gold._50036_.Q, dut.compare_data_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50037_.Q !== dut.compare_data_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27222 gold=%b dut=%b", gold._50037_.Q, dut.compare_data_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50038_.Q !== dut.compare_data_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27223 gold=%b dut=%b", gold._50038_.Q, dut.compare_data_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50039_.Q !== dut.compare_data_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27224 gold=%b dut=%b", gold._50039_.Q, dut.compare_data_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50040_.Q !== dut.compare_data_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27225 gold=%b dut=%b", gold._50040_.Q, dut.compare_data_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50041_.Q !== dut.compare_data_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27226 gold=%b dut=%b", gold._50041_.Q, dut.compare_data_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50042_.Q !== dut.compare_data_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27227 gold=%b dut=%b", gold._50042_.Q, dut.compare_data_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50043_.Q !== dut.compare_data_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27228 gold=%b dut=%b", gold._50043_.Q, dut.compare_data_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50044_.Q !== dut.compare_data_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27229 gold=%b dut=%b", gold._50044_.Q, dut.compare_data_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50045_.Q !== dut.compare_data_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27230 gold=%b dut=%b", gold._50045_.Q, dut.compare_data_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50046_.Q !== dut.compare_data_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27231 gold=%b dut=%b", gold._50046_.Q, dut.compare_data_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50047_.Q !== dut.compare_data_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27232 gold=%b dut=%b", gold._50047_.Q, dut.compare_data_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50048_.Q !== dut.compare_data_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27233 gold=%b dut=%b", gold._50048_.Q, dut.compare_data_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50049_.Q !== dut.compare_data_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27234 gold=%b dut=%b", gold._50049_.Q, dut.compare_data_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50050_.Q !== dut.compare_data_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27235 gold=%b dut=%b", gold._50050_.Q, dut.compare_data_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50051_.Q !== dut.compare_data_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27236 gold=%b dut=%b", gold._50051_.Q, dut.compare_data_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50052_.Q !== dut.compare_data_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27237 gold=%b dut=%b", gold._50052_.Q, dut.compare_data_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50053_.Q !== dut.compare_data_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27238 gold=%b dut=%b", gold._50053_.Q, dut.compare_data_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50054_.Q !== dut.compare_data_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27239 gold=%b dut=%b", gold._50054_.Q, dut.compare_data_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49707_.Q !== dut.unnamed_27240[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27240 gold=%b dut=%b", gold._49707_.Q, dut.unnamed_27240[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49708_.Q !== dut.unnamed_27240[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27241 gold=%b dut=%b", gold._49708_.Q, dut.unnamed_27240[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49709_.Q !== dut.unnamed_27240[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27242 gold=%b dut=%b", gold._49709_.Q, dut.unnamed_27240[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49710_.Q !== dut.unnamed_27240[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27243 gold=%b dut=%b", gold._49710_.Q, dut.unnamed_27240[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49711_.Q !== dut.unnamed_27240[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27244 gold=%b dut=%b", gold._49711_.Q, dut.unnamed_27240[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49712_.Q !== dut.unnamed_27240[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27245 gold=%b dut=%b", gold._49712_.Q, dut.unnamed_27240[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49713_.Q !== dut.unnamed_27240[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27246 gold=%b dut=%b", gold._49713_.Q, dut.unnamed_27240[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49714_.Q !== dut.unnamed_27240[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27247 gold=%b dut=%b", gold._49714_.Q, dut.unnamed_27240[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49715_.Q !== dut.unnamed_27240[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27248 gold=%b dut=%b", gold._49715_.Q, dut.unnamed_27240[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49716_.Q !== dut.unnamed_27240[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27249 gold=%b dut=%b", gold._49716_.Q, dut.unnamed_27240[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49717_.Q !== dut.unnamed_27240[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27250 gold=%b dut=%b", gold._49717_.Q, dut.unnamed_27240[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49718_.Q !== dut.unnamed_27240[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27251 gold=%b dut=%b", gold._49718_.Q, dut.unnamed_27240[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49719_.Q !== dut.unnamed_27240[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27252 gold=%b dut=%b", gold._49719_.Q, dut.unnamed_27240[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49720_.Q !== dut.unnamed_27240[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27253 gold=%b dut=%b", gold._49720_.Q, dut.unnamed_27240[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49721_.Q !== dut.unnamed_27240[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27254 gold=%b dut=%b", gold._49721_.Q, dut.unnamed_27240[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49722_.Q !== dut.unnamed_27240[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27255 gold=%b dut=%b", gold._49722_.Q, dut.unnamed_27240[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49723_.Q !== dut.unnamed_27240[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27256 gold=%b dut=%b", gold._49723_.Q, dut.unnamed_27240[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49724_.Q !== dut.unnamed_27240[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27257 gold=%b dut=%b", gold._49724_.Q, dut.unnamed_27240[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49725_.Q !== dut.unnamed_27240[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27258 gold=%b dut=%b", gold._49725_.Q, dut.unnamed_27240[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49726_.Q !== dut.unnamed_27240[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27259 gold=%b dut=%b", gold._49726_.Q, dut.unnamed_27240[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49727_.Q !== dut.unnamed_27240[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27260 gold=%b dut=%b", gold._49727_.Q, dut.unnamed_27240[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49728_.Q !== dut.unnamed_27240[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27261 gold=%b dut=%b", gold._49728_.Q, dut.unnamed_27240[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49729_.Q !== dut.unnamed_27240[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27262 gold=%b dut=%b", gold._49729_.Q, dut.unnamed_27240[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49730_.Q !== dut.unnamed_27240[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27263 gold=%b dut=%b", gold._49730_.Q, dut.unnamed_27240[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49731_.Q !== dut.unnamed_27240[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27264 gold=%b dut=%b", gold._49731_.Q, dut.unnamed_27240[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49732_.Q !== dut.unnamed_27240[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27265 gold=%b dut=%b", gold._49732_.Q, dut.unnamed_27240[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49733_.Q !== dut.unnamed_27240[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27266 gold=%b dut=%b", gold._49733_.Q, dut.unnamed_27240[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49734_.Q !== dut.unnamed_27240[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27267 gold=%b dut=%b", gold._49734_.Q, dut.unnamed_27240[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49735_.Q !== dut.unnamed_27240[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27268 gold=%b dut=%b", gold._49735_.Q, dut.unnamed_27240[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49736_.Q !== dut.unnamed_27240[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27269 gold=%b dut=%b", gold._49736_.Q, dut.unnamed_27240[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49737_.Q !== dut.unnamed_27240[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27270 gold=%b dut=%b", gold._49737_.Q, dut.unnamed_27240[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49675_.Q !== dut.wide_data_reg_5[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27271 gold=%b dut=%b", gold._49675_.Q, dut.wide_data_reg_5[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49676_.Q !== dut.wide_data_reg_5[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27272 gold=%b dut=%b", gold._49676_.Q, dut.wide_data_reg_5[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49677_.Q !== dut.wide_data_reg_5[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27273 gold=%b dut=%b", gold._49677_.Q, dut.wide_data_reg_5[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49678_.Q !== dut.wide_data_reg_5[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27274 gold=%b dut=%b", gold._49678_.Q, dut.wide_data_reg_5[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49679_.Q !== dut.wide_data_reg_5[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27275 gold=%b dut=%b", gold._49679_.Q, dut.wide_data_reg_5[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49680_.Q !== dut.wide_data_reg_5[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27276 gold=%b dut=%b", gold._49680_.Q, dut.wide_data_reg_5[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49681_.Q !== dut.wide_data_reg_5[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27277 gold=%b dut=%b", gold._49681_.Q, dut.wide_data_reg_5[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49682_.Q !== dut.wide_data_reg_5[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27278 gold=%b dut=%b", gold._49682_.Q, dut.wide_data_reg_5[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49683_.Q !== dut.wide_data_reg_5[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27279 gold=%b dut=%b", gold._49683_.Q, dut.wide_data_reg_5[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49684_.Q !== dut.wide_data_reg_5[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27280 gold=%b dut=%b", gold._49684_.Q, dut.wide_data_reg_5[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49685_.Q !== dut.wide_data_reg_5[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27281 gold=%b dut=%b", gold._49685_.Q, dut.wide_data_reg_5[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49686_.Q !== dut.wide_data_reg_5[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27282 gold=%b dut=%b", gold._49686_.Q, dut.wide_data_reg_5[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49687_.Q !== dut.wide_data_reg_5[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27283 gold=%b dut=%b", gold._49687_.Q, dut.wide_data_reg_5[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49688_.Q !== dut.wide_data_reg_5[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27284 gold=%b dut=%b", gold._49688_.Q, dut.wide_data_reg_5[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49689_.Q !== dut.wide_data_reg_5[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27285 gold=%b dut=%b", gold._49689_.Q, dut.wide_data_reg_5[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49690_.Q !== dut.wide_data_reg_5[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27286 gold=%b dut=%b", gold._49690_.Q, dut.wide_data_reg_5[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49691_.Q !== dut.wide_data_reg_5[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27287 gold=%b dut=%b", gold._49691_.Q, dut.wide_data_reg_5[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49692_.Q !== dut.wide_data_reg_5[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27288 gold=%b dut=%b", gold._49692_.Q, dut.wide_data_reg_5[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49693_.Q !== dut.wide_data_reg_5[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27289 gold=%b dut=%b", gold._49693_.Q, dut.wide_data_reg_5[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49694_.Q !== dut.wide_data_reg_5[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27290 gold=%b dut=%b", gold._49694_.Q, dut.wide_data_reg_5[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49695_.Q !== dut.wide_data_reg_5[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27291 gold=%b dut=%b", gold._49695_.Q, dut.wide_data_reg_5[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49696_.Q !== dut.wide_data_reg_5[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27292 gold=%b dut=%b", gold._49696_.Q, dut.wide_data_reg_5[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49697_.Q !== dut.wide_data_reg_5[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27293 gold=%b dut=%b", gold._49697_.Q, dut.wide_data_reg_5[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49698_.Q !== dut.wide_data_reg_5[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27294 gold=%b dut=%b", gold._49698_.Q, dut.wide_data_reg_5[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49699_.Q !== dut.wide_data_reg_5[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27295 gold=%b dut=%b", gold._49699_.Q, dut.wide_data_reg_5[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49700_.Q !== dut.wide_data_reg_5[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27296 gold=%b dut=%b", gold._49700_.Q, dut.wide_data_reg_5[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49701_.Q !== dut.wide_data_reg_5[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27297 gold=%b dut=%b", gold._49701_.Q, dut.wide_data_reg_5[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49702_.Q !== dut.unnamed_27298[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27298 gold=%b dut=%b", gold._49702_.Q, dut.unnamed_27298[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49703_.Q !== dut.unnamed_27298[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27299 gold=%b dut=%b", gold._49703_.Q, dut.unnamed_27298[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49704_.Q !== dut.unnamed_27298[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27300 gold=%b dut=%b", gold._49704_.Q, dut.unnamed_27298[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49705_.Q !== dut.unnamed_27298[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27301 gold=%b dut=%b", gold._49705_.Q, dut.unnamed_27298[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49706_.Q !== dut.unnamed_27298[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27302 gold=%b dut=%b", gold._49706_.Q, dut.unnamed_27298[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50001_.Q !== dut.compare_done_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27303 gold=%b dut=%b", gold._50001_.Q, dut.compare_done_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50161_.Q !== dut.done_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27304 gold=%b dut=%b", gold._50161_.Q, dut.done_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50128_.Q !== dut.event_pulse_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27305 gold=%b dut=%b", gold._50128_.Q, dut.event_pulse_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50022_.Q !== dut.decode_match_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27306 gold=%b dut=%b", gold._50022_.Q, dut.decode_match_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49910_.Q !== dut.parity_or_activity_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27307 gold=%b dut=%b", gold._49910_.Q, dut.parity_or_activity_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48383_.Q !== dut.control_flag_27439) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27439 gold=%b dut=%b", gold._48383_.Q, dut.control_flag_27439);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49738_.Q !== dut.unnamed_27441[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27441 gold=%b dut=%b", gold._49738_.Q, dut.unnamed_27441[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49739_.Q !== dut.unnamed_27441[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27442 gold=%b dut=%b", gold._49739_.Q, dut.unnamed_27441[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49740_.Q !== dut.unnamed_27441[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27443 gold=%b dut=%b", gold._49740_.Q, dut.unnamed_27441[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49741_.Q !== dut.unnamed_27441[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27444 gold=%b dut=%b", gold._49741_.Q, dut.unnamed_27441[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49742_.Q !== dut.compare_match_data[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27445 gold=%b dut=%b", gold._49742_.Q, dut.compare_match_data[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49743_.Q !== dut.compare_match_data[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27446 gold=%b dut=%b", gold._49743_.Q, dut.compare_match_data[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49744_.Q !== dut.compare_match_data[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27447 gold=%b dut=%b", gold._49744_.Q, dut.compare_match_data[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49745_.Q !== dut.compare_match_data[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27448 gold=%b dut=%b", gold._49745_.Q, dut.compare_match_data[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49746_.Q !== dut.compare_match_data[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27449 gold=%b dut=%b", gold._49746_.Q, dut.compare_match_data[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49747_.Q !== dut.compare_match_data[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27450 gold=%b dut=%b", gold._49747_.Q, dut.compare_match_data[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49748_.Q !== dut.compare_match_data[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27451 gold=%b dut=%b", gold._49748_.Q, dut.compare_match_data[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49749_.Q !== dut.compare_match_data[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27452 gold=%b dut=%b", gold._49749_.Q, dut.compare_match_data[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49750_.Q !== dut.compare_match_data[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27453 gold=%b dut=%b", gold._49750_.Q, dut.compare_match_data[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49751_.Q !== dut.compare_match_data[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27454 gold=%b dut=%b", gold._49751_.Q, dut.compare_match_data[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49752_.Q !== dut.compare_match_data[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27455 gold=%b dut=%b", gold._49752_.Q, dut.compare_match_data[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49753_.Q !== dut.compare_match_data[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27456 gold=%b dut=%b", gold._49753_.Q, dut.compare_match_data[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49754_.Q !== dut.compare_match_data[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27457 gold=%b dut=%b", gold._49754_.Q, dut.compare_match_data[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49755_.Q !== dut.compare_match_data[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27458 gold=%b dut=%b", gold._49755_.Q, dut.compare_match_data[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49756_.Q !== dut.compare_match_data[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27459 gold=%b dut=%b", gold._49756_.Q, dut.compare_match_data[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49757_.Q !== dut.compare_match_data[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27460 gold=%b dut=%b", gold._49757_.Q, dut.compare_match_data[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49758_.Q !== dut.compare_match_data[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27461 gold=%b dut=%b", gold._49758_.Q, dut.compare_match_data[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49759_.Q !== dut.compare_match_data[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27462 gold=%b dut=%b", gold._49759_.Q, dut.compare_match_data[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49760_.Q !== dut.compare_match_data[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27463 gold=%b dut=%b", gold._49760_.Q, dut.compare_match_data[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49761_.Q !== dut.compare_match_data[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27464 gold=%b dut=%b", gold._49761_.Q, dut.compare_match_data[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49762_.Q !== dut.compare_match_data[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27465 gold=%b dut=%b", gold._49762_.Q, dut.compare_match_data[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49763_.Q !== dut.compare_match_data[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27466 gold=%b dut=%b", gold._49763_.Q, dut.compare_match_data[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49764_.Q !== dut.compare_match_data[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27467 gold=%b dut=%b", gold._49764_.Q, dut.compare_match_data[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49765_.Q !== dut.compare_match_data[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27468 gold=%b dut=%b", gold._49765_.Q, dut.compare_match_data[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49766_.Q !== dut.compare_match_data[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27469 gold=%b dut=%b", gold._49766_.Q, dut.compare_match_data[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49767_.Q !== dut.compare_match_data[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27470 gold=%b dut=%b", gold._49767_.Q, dut.compare_match_data[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49768_.Q !== dut.compare_match_data[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27471 gold=%b dut=%b", gold._49768_.Q, dut.compare_match_data[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49769_.Q !== dut.compare_match_data[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27472 gold=%b dut=%b", gold._49769_.Q, dut.compare_match_data[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49772_.Q !== dut.pending_vector[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27473 gold=%b dut=%b", gold._49772_.Q, dut.pending_vector[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49773_.Q !== dut.pending_vector[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27474 gold=%b dut=%b", gold._49773_.Q, dut.pending_vector[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49774_.Q !== dut.pending_vector[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27475 gold=%b dut=%b", gold._49774_.Q, dut.pending_vector[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49775_.Q !== dut.pending_vector[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27476 gold=%b dut=%b", gold._49775_.Q, dut.pending_vector[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49776_.Q !== dut.pending_vector[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27477 gold=%b dut=%b", gold._49776_.Q, dut.pending_vector[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49777_.Q !== dut.pending_vector[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27478 gold=%b dut=%b", gold._49777_.Q, dut.pending_vector[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49778_.Q !== dut.pending_vector[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27479 gold=%b dut=%b", gold._49778_.Q, dut.pending_vector[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49779_.Q !== dut.pending_vector[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27480 gold=%b dut=%b", gold._49779_.Q, dut.pending_vector[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49780_.Q !== dut.pending_vector[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27481 gold=%b dut=%b", gold._49780_.Q, dut.pending_vector[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49781_.Q !== dut.pending_vector[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27482 gold=%b dut=%b", gold._49781_.Q, dut.pending_vector[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49782_.Q !== dut.pending_vector[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27483 gold=%b dut=%b", gold._49782_.Q, dut.pending_vector[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49783_.Q !== dut.pending_vector[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27484 gold=%b dut=%b", gold._49783_.Q, dut.pending_vector[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49784_.Q !== dut.pending_vector[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27485 gold=%b dut=%b", gold._49784_.Q, dut.pending_vector[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49785_.Q !== dut.pending_vector[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27486 gold=%b dut=%b", gold._49785_.Q, dut.pending_vector[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49786_.Q !== dut.pending_vector[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27487 gold=%b dut=%b", gold._49786_.Q, dut.pending_vector[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49787_.Q !== dut.pending_vector[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27488 gold=%b dut=%b", gold._49787_.Q, dut.pending_vector[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49788_.Q !== dut.pending_vector[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27489 gold=%b dut=%b", gold._49788_.Q, dut.pending_vector[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49789_.Q !== dut.pending_vector[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27490 gold=%b dut=%b", gold._49789_.Q, dut.pending_vector[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49790_.Q !== dut.pending_vector[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27491 gold=%b dut=%b", gold._49790_.Q, dut.pending_vector[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49791_.Q !== dut.pending_vector[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27492 gold=%b dut=%b", gold._49791_.Q, dut.pending_vector[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49792_.Q !== dut.pending_vector[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27493 gold=%b dut=%b", gold._49792_.Q, dut.pending_vector[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49793_.Q !== dut.pending_vector[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27494 gold=%b dut=%b", gold._49793_.Q, dut.pending_vector[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49794_.Q !== dut.pending_vector[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27495 gold=%b dut=%b", gold._49794_.Q, dut.pending_vector[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49795_.Q !== dut.pending_vector[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27496 gold=%b dut=%b", gold._49795_.Q, dut.pending_vector[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49796_.Q !== dut.pending_vector[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27497 gold=%b dut=%b", gold._49796_.Q, dut.pending_vector[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49797_.Q !== dut.pending_vector[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27498 gold=%b dut=%b", gold._49797_.Q, dut.pending_vector[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49798_.Q !== dut.pending_vector[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27499 gold=%b dut=%b", gold._49798_.Q, dut.pending_vector[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49799_.Q !== dut.pending_vector[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27500 gold=%b dut=%b", gold._49799_.Q, dut.pending_vector[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49800_.Q !== dut.pending_vector[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27501 gold=%b dut=%b", gold._49800_.Q, dut.pending_vector[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49801_.Q !== dut.pending_vector[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27502 gold=%b dut=%b", gold._49801_.Q, dut.pending_vector[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49802_.Q !== dut.pending_vector[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27503 gold=%b dut=%b", gold._49802_.Q, dut.pending_vector[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49803_.Q !== dut.pending_vector[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27504 gold=%b dut=%b", gold._49803_.Q, dut.pending_vector[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49805_.Q !== dut.pending_vector[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27506 gold=%b dut=%b", gold._49805_.Q, dut.pending_vector[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50525_.Q !== dut.regfile_bit25_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27507 gold=%b dut=%b", gold._50525_.Q, dut.regfile_bit25_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50534_.Q !== dut.regfile_bit24_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27508 gold=%b dut=%b", gold._50534_.Q, dut.regfile_bit24_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50516_.Q !== dut.regfile_bit25_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27509 gold=%b dut=%b", gold._50516_.Q, dut.regfile_bit25_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50529_.Q !== dut.regfile_bit24_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27510 gold=%b dut=%b", gold._50529_.Q, dut.regfile_bit24_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50535_.Q !== dut.control_state_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27511 gold=%b dut=%b", gold._50535_.Q, dut.control_state_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49909_.Q !== dut.decoded_status_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27512 gold=%b dut=%b", gold._49909_.Q, dut.decoded_status_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49999_.Q !== dut.mode_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27513 gold=%b dut=%b", gold._49999_.Q, dut.mode_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49998_.Q !== dut.mode_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27514 gold=%b dut=%b", gold._49998_.Q, dut.mode_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49929_.Q !== dut.decoded_status_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27515 gold=%b dut=%b", gold._49929_.Q, dut.decoded_status_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50458_.Q !== dut.latched_condition_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27516 gold=%b dut=%b", gold._50458_.Q, dut.latched_condition_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49771_.Q !== dut.condition_latch) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27517 gold=%b dut=%b", gold._49771_.Q, dut.condition_latch);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50511_.Q !== dut.event_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27518 gold=%b dut=%b", gold._50511_.Q, dut.event_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50510_.Q !== dut.event_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27519 gold=%b dut=%b", gold._50510_.Q, dut.event_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50509_.Q !== dut.decoded_status_low[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27520 gold=%b dut=%b", gold._50509_.Q, dut.decoded_status_low[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49770_.Q !== dut.control_flag_6) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27521 gold=%b dut=%b", gold._49770_.Q, dut.control_flag_6);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49804_.Q !== dut.fsm_state_3) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27522 gold=%b dut=%b", gold._49804_.Q, dut.fsm_state_3);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50463_.Q !== dut.control_state_6[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27523 gold=%b dut=%b", gold._50463_.Q, dut.control_state_6[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50540_.Q !== dut.regfile_bit29_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27524 gold=%b dut=%b", gold._50540_.Q, dut.regfile_bit29_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50542_.Q !== dut.status_flag_7) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27525 gold=%b dut=%b", gold._50542_.Q, dut.status_flag_7);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50539_.Q !== dut.regfile_bit29_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27526 gold=%b dut=%b", gold._50539_.Q, dut.regfile_bit29_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50127_.Q !== dut.control_state_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27527 gold=%b dut=%b", gold._50127_.Q, dut.control_state_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50541_.Q !== dut.regfile_bit29_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27528 gold=%b dut=%b", gold._50541_.Q, dut.regfile_bit29_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50506_.Q !== dut.decoded_status_low[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27529 gold=%b dut=%b", gold._50506_.Q, dut.decoded_status_low[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50517_.Q !== dut.regfile_bit25_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27530 gold=%b dut=%b", gold._50517_.Q, dut.regfile_bit25_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50530_.Q !== dut.regfile_bit24_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27531 gold=%b dut=%b", gold._50530_.Q, dut.regfile_bit24_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50515_.Q !== dut.decoded_status_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27532 gold=%b dut=%b", gold._50515_.Q, dut.decoded_status_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50514_.Q !== dut.decoded_status_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27533 gold=%b dut=%b", gold._50514_.Q, dut.decoded_status_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50513_.Q !== dut.decoded_status_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27534 gold=%b dut=%b", gold._50513_.Q, dut.decoded_status_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50512_.Q !== dut.decoded_status_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27535 gold=%b dut=%b", gold._50512_.Q, dut.decoded_status_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50507_.Q !== dut.control_state_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27536 gold=%b dut=%b", gold._50507_.Q, dut.control_state_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50538_.Q !== dut.regfile_bit33_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27537 gold=%b dut=%b", gold._50538_.Q, dut.regfile_bit33_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50508_.Q !== dut.decoded_status_low[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27538 gold=%b dut=%b", gold._50508_.Q, dut.decoded_status_low[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50537_.Q !== dut.regfile_bit33_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27539 gold=%b dut=%b", gold._50537_.Q, dut.regfile_bit33_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50523_.Q !== dut.regfile_bit25_slice[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27540 gold=%b dut=%b", gold._50523_.Q, dut.regfile_bit25_slice[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50528_.Q !== dut.regfile_bit24_slice[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27541 gold=%b dut=%b", gold._50528_.Q, dut.regfile_bit24_slice[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50522_.Q !== dut.regfile_bit25_slice[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27542 gold=%b dut=%b", gold._50522_.Q, dut.regfile_bit25_slice[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50533_.Q !== dut.regfile_bit24_slice[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27543 gold=%b dut=%b", gold._50533_.Q, dut.regfile_bit24_slice[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50532_.Q !== dut.regfile_bit24_slice[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27544 gold=%b dut=%b", gold._50532_.Q, dut.regfile_bit24_slice[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50521_.Q !== dut.regfile_bit25_slice[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27545 gold=%b dut=%b", gold._50521_.Q, dut.regfile_bit25_slice[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50518_.Q !== dut.regfile_bit25_slice[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27546 gold=%b dut=%b", gold._50518_.Q, dut.regfile_bit25_slice[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50526_.Q !== dut.regfile_bit24_slice[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27547 gold=%b dut=%b", gold._50526_.Q, dut.regfile_bit24_slice[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50519_.Q !== dut.regfile_bit25_slice[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27548 gold=%b dut=%b", gold._50519_.Q, dut.regfile_bit25_slice[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50527_.Q !== dut.regfile_bit24_slice[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27549 gold=%b dut=%b", gold._50527_.Q, dut.regfile_bit24_slice[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50524_.Q !== dut.regfile_bit25_slice[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27550 gold=%b dut=%b", gold._50524_.Q, dut.regfile_bit25_slice[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50536_.Q !== dut.regfile_bit33_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27551 gold=%b dut=%b", gold._50536_.Q, dut.regfile_bit33_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50504_.Q !== dut.decoded_status_low[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27552 gold=%b dut=%b", gold._50504_.Q, dut.decoded_status_low[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50505_.Q !== dut.control_state_4[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27553 gold=%b dut=%b", gold._50505_.Q, dut.control_state_4[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50520_.Q !== dut.regfile_bit25_slice[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27554 gold=%b dut=%b", gold._50520_.Q, dut.regfile_bit25_slice[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50531_.Q !== dut.regfile_bit24_slice[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27555 gold=%b dut=%b", gold._50531_.Q, dut.regfile_bit24_slice[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50125_.Q !== dut.sticky_control_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27556 gold=%b dut=%b", gold._50125_.Q, dut.sticky_control_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50126_.Q !== dut.completion_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27557 gold=%b dut=%b", gold._50126_.Q, dut.completion_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50093_.Q !== dut.low_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27558 gold=%b dut=%b", gold._50093_.Q, dut.low_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50094_.Q !== dut.low_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27559 gold=%b dut=%b", gold._50094_.Q, dut.low_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50095_.Q !== dut.low_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27560 gold=%b dut=%b", gold._50095_.Q, dut.low_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50096_.Q !== dut.low_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27561 gold=%b dut=%b", gold._50096_.Q, dut.low_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50097_.Q !== dut.low_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27562 gold=%b dut=%b", gold._50097_.Q, dut.low_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50098_.Q !== dut.low_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27563 gold=%b dut=%b", gold._50098_.Q, dut.low_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50099_.Q !== dut.low_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27564 gold=%b dut=%b", gold._50099_.Q, dut.low_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50100_.Q !== dut.low_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27565 gold=%b dut=%b", gold._50100_.Q, dut.low_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50101_.Q !== dut.low_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27566 gold=%b dut=%b", gold._50101_.Q, dut.low_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50102_.Q !== dut.low_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27567 gold=%b dut=%b", gold._50102_.Q, dut.low_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50103_.Q !== dut.low_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27568 gold=%b dut=%b", gold._50103_.Q, dut.low_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50104_.Q !== dut.low_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27569 gold=%b dut=%b", gold._50104_.Q, dut.low_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50105_.Q !== dut.low_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27570 gold=%b dut=%b", gold._50105_.Q, dut.low_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50106_.Q !== dut.low_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27571 gold=%b dut=%b", gold._50106_.Q, dut.low_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50107_.Q !== dut.low_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27572 gold=%b dut=%b", gold._50107_.Q, dut.low_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50108_.Q !== dut.low_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27573 gold=%b dut=%b", gold._50108_.Q, dut.low_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50109_.Q !== dut.low_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27574 gold=%b dut=%b", gold._50109_.Q, dut.low_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50110_.Q !== dut.low_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27575 gold=%b dut=%b", gold._50110_.Q, dut.low_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50111_.Q !== dut.low_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27576 gold=%b dut=%b", gold._50111_.Q, dut.low_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50112_.Q !== dut.low_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27577 gold=%b dut=%b", gold._50112_.Q, dut.low_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50113_.Q !== dut.low_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27578 gold=%b dut=%b", gold._50113_.Q, dut.low_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50114_.Q !== dut.low_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27579 gold=%b dut=%b", gold._50114_.Q, dut.low_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50115_.Q !== dut.low_data_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27580 gold=%b dut=%b", gold._50115_.Q, dut.low_data_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50116_.Q !== dut.low_data_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27581 gold=%b dut=%b", gold._50116_.Q, dut.low_data_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50117_.Q !== dut.low_data_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27582 gold=%b dut=%b", gold._50117_.Q, dut.low_data_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50118_.Q !== dut.low_data_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27583 gold=%b dut=%b", gold._50118_.Q, dut.low_data_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50119_.Q !== dut.low_data_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27584 gold=%b dut=%b", gold._50119_.Q, dut.low_data_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50120_.Q !== dut.low_data_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27585 gold=%b dut=%b", gold._50120_.Q, dut.low_data_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50121_.Q !== dut.low_data_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27586 gold=%b dut=%b", gold._50121_.Q, dut.low_data_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50122_.Q !== dut.low_data_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27587 gold=%b dut=%b", gold._50122_.Q, dut.low_data_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50123_.Q !== dut.low_data_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27588 gold=%b dut=%b", gold._50123_.Q, dut.low_data_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50124_.Q !== dut.low_data_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27589 gold=%b dut=%b", gold._50124_.Q, dut.low_data_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48319_.Q !== dut.buffer_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27590 gold=%b dut=%b", gold._48319_.Q, dut.buffer_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48320_.Q !== dut.buffer_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27591 gold=%b dut=%b", gold._48320_.Q, dut.buffer_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48321_.Q !== dut.buffer_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27592 gold=%b dut=%b", gold._48321_.Q, dut.buffer_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48322_.Q !== dut.buffer_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27593 gold=%b dut=%b", gold._48322_.Q, dut.buffer_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48323_.Q !== dut.buffer_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27594 gold=%b dut=%b", gold._48323_.Q, dut.buffer_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48324_.Q !== dut.buffer_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27595 gold=%b dut=%b", gold._48324_.Q, dut.buffer_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48325_.Q !== dut.buffer_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27596 gold=%b dut=%b", gold._48325_.Q, dut.buffer_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48326_.Q !== dut.buffer_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27597 gold=%b dut=%b", gold._48326_.Q, dut.buffer_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48327_.Q !== dut.buffer_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27598 gold=%b dut=%b", gold._48327_.Q, dut.buffer_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48328_.Q !== dut.buffer_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27599 gold=%b dut=%b", gold._48328_.Q, dut.buffer_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48329_.Q !== dut.buffer_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27600 gold=%b dut=%b", gold._48329_.Q, dut.buffer_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48330_.Q !== dut.buffer_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27601 gold=%b dut=%b", gold._48330_.Q, dut.buffer_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48331_.Q !== dut.buffer_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27602 gold=%b dut=%b", gold._48331_.Q, dut.buffer_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48332_.Q !== dut.buffer_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27603 gold=%b dut=%b", gold._48332_.Q, dut.buffer_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48333_.Q !== dut.buffer_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27604 gold=%b dut=%b", gold._48333_.Q, dut.buffer_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48334_.Q !== dut.buffer_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27605 gold=%b dut=%b", gold._48334_.Q, dut.buffer_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48335_.Q !== dut.buffer_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27606 gold=%b dut=%b", gold._48335_.Q, dut.buffer_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48336_.Q !== dut.buffer_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27607 gold=%b dut=%b", gold._48336_.Q, dut.buffer_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48337_.Q !== dut.buffer_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27608 gold=%b dut=%b", gold._48337_.Q, dut.buffer_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48338_.Q !== dut.buffer_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27609 gold=%b dut=%b", gold._48338_.Q, dut.buffer_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48339_.Q !== dut.buffer_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27610 gold=%b dut=%b", gold._48339_.Q, dut.buffer_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48340_.Q !== dut.buffer_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27611 gold=%b dut=%b", gold._48340_.Q, dut.buffer_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48341_.Q !== dut.buffer_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27612 gold=%b dut=%b", gold._48341_.Q, dut.buffer_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48342_.Q !== dut.decode_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27613 gold=%b dut=%b", gold._48342_.Q, dut.decode_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48343_.Q !== dut.decode_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27614 gold=%b dut=%b", gold._48343_.Q, dut.decode_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48344_.Q !== dut.decode_flags[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27615 gold=%b dut=%b", gold._48344_.Q, dut.decode_flags[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48345_.Q !== dut.decode_flags[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27616 gold=%b dut=%b", gold._48345_.Q, dut.decode_flags[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48346_.Q !== dut.decode_flags[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27617 gold=%b dut=%b", gold._48346_.Q, dut.decode_flags[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48347_.Q !== dut.decode_flags[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27618 gold=%b dut=%b", gold._48347_.Q, dut.decode_flags[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48348_.Q !== dut.decode_flags[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27619 gold=%b dut=%b", gold._48348_.Q, dut.decode_flags[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48349_.Q !== dut.decode_flags[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27620 gold=%b dut=%b", gold._48349_.Q, dut.decode_flags[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48350_.Q !== dut.decode_flags[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27621 gold=%b dut=%b", gold._48350_.Q, dut.decode_flags[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50020_.Q !== dut.retry_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27622 gold=%b dut=%b", gold._50020_.Q, dut.retry_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50021_.Q !== dut.retry_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27623 gold=%b dut=%b", gold._50021_.Q, dut.retry_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50459_.Q !== dut.control_state_7[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27624 gold=%b dut=%b", gold._50459_.Q, dut.control_state_7[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50457_.Q !== dut.control_state_7[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27625 gold=%b dut=%b", gold._50457_.Q, dut.control_state_7[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50460_.Q !== dut.control_state_7[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27626 gold=%b dut=%b", gold._50460_.Q, dut.control_state_7[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50456_.Q !== dut.control_valid_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27627 gold=%b dut=%b", gold._50456_.Q, dut.control_valid_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50462_.Q !== dut.control_state_6[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27628 gold=%b dut=%b", gold._50462_.Q, dut.control_state_6[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50465_.Q !== dut.datapath_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27629 gold=%b dut=%b", gold._50465_.Q, dut.datapath_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48271_.Q !== dut.decode_state_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27630 gold=%b dut=%b", gold._48271_.Q, dut.decode_state_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48268_.Q !== dut.decode_state_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27631 gold=%b dut=%b", gold._48268_.Q, dut.decode_state_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50000_.Q !== dut.decoded_activity_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27632 gold=%b dut=%b", gold._50000_.Q, dut.decoded_activity_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50461_.Q !== dut.control_state_7[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27633 gold=%b dut=%b", gold._50461_.Q, dut.control_state_7[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50464_.Q !== dut.control_state_6[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27634 gold=%b dut=%b", gold._50464_.Q, dut.control_state_6[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48269_.Q !== dut.decode_state_flags[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27635 gold=%b dut=%b", gold._48269_.Q, dut.decode_state_flags[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48270_.Q !== dut.decode_state_flags[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27636 gold=%b dut=%b", gold._48270_.Q, dut.decode_state_flags[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50002_.Q !== dut.edge_condition_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27637 gold=%b dut=%b", gold._50002_.Q, dut.edge_condition_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50017_.Q !== dut.match_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27638 gold=%b dut=%b", gold._50017_.Q, dut.match_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50012_.Q !== dut.control_state_8[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27639 gold=%b dut=%b", gold._50012_.Q, dut.control_state_8[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50014_.Q !== dut.control_state_8[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27640 gold=%b dut=%b", gold._50014_.Q, dut.control_state_8[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50013_.Q !== dut.control_state_8[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27641 gold=%b dut=%b", gold._50013_.Q, dut.control_state_8[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50015_.Q !== dut.control_state_8[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27642 gold=%b dut=%b", gold._50015_.Q, dut.control_state_8[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50006_.Q !== dut.address_capture[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27643 gold=%b dut=%b", gold._50006_.Q, dut.address_capture[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50007_.Q !== dut.address_capture[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27644 gold=%b dut=%b", gold._50007_.Q, dut.address_capture[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50008_.Q !== dut.address_capture[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27645 gold=%b dut=%b", gold._50008_.Q, dut.address_capture[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50009_.Q !== dut.address_capture[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27646 gold=%b dut=%b", gold._50009_.Q, dut.address_capture[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50010_.Q !== dut.address_capture[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27647 gold=%b dut=%b", gold._50010_.Q, dut.address_capture[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50011_.Q !== dut.address_capture[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27648 gold=%b dut=%b", gold._50011_.Q, dut.address_capture[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50018_.Q !== dut.hold_valid_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27649 gold=%b dut=%b", gold._50018_.Q, dut.hold_valid_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50019_.Q !== dut.match_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27650 gold=%b dut=%b", gold._50019_.Q, dut.match_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50016_.Q !== dut.pending_request_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27651 gold=%b dut=%b", gold._50016_.Q, dut.pending_request_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49913_.Q !== dut.load_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27652 gold=%b dut=%b", gold._49913_.Q, dut.load_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49914_.Q !== dut.load_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27653 gold=%b dut=%b", gold._49914_.Q, dut.load_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49915_.Q !== dut.load_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27654 gold=%b dut=%b", gold._49915_.Q, dut.load_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49916_.Q !== dut.load_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27655 gold=%b dut=%b", gold._49916_.Q, dut.load_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49917_.Q !== dut.load_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27656 gold=%b dut=%b", gold._49917_.Q, dut.load_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49918_.Q !== dut.load_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27657 gold=%b dut=%b", gold._49918_.Q, dut.load_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49919_.Q !== dut.load_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27658 gold=%b dut=%b", gold._49919_.Q, dut.load_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49920_.Q !== dut.load_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27659 gold=%b dut=%b", gold._49920_.Q, dut.load_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49921_.Q !== dut.load_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27660 gold=%b dut=%b", gold._49921_.Q, dut.load_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49922_.Q !== dut.load_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27661 gold=%b dut=%b", gold._49922_.Q, dut.load_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49923_.Q !== dut.load_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27662 gold=%b dut=%b", gold._49923_.Q, dut.load_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49924_.Q !== dut.load_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27663 gold=%b dut=%b", gold._49924_.Q, dut.load_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49925_.Q !== dut.load_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27664 gold=%b dut=%b", gold._49925_.Q, dut.load_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49926_.Q !== dut.load_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27665 gold=%b dut=%b", gold._49926_.Q, dut.load_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49927_.Q !== dut.load_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27666 gold=%b dut=%b", gold._49927_.Q, dut.load_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49928_.Q !== dut.load_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27667 gold=%b dut=%b", gold._49928_.Q, dut.load_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50058_.Q !== dut.control_state_9[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27668 gold=%b dut=%b", gold._50058_.Q, dut.control_state_9[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50056_.Q !== dut.control_state_9[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27669 gold=%b dut=%b", gold._50056_.Q, dut.control_state_9[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50057_.Q !== dut.control_state_9[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27670 gold=%b dut=%b", gold._50057_.Q, dut.control_state_9[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50055_.Q !== dut.control_state_9[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27671 gold=%b dut=%b", gold._50055_.Q, dut.control_state_9[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50003_.Q !== dut.qualified_status_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27672 gold=%b dut=%b", gold._50003_.Q, dut.qualified_status_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49911_.Q !== dut.control_state_10[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27673 gold=%b dut=%b", gold._49911_.Q, dut.control_state_10[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49832_.Q !== dut.data_reg_7[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27674 gold=%b dut=%b", gold._49832_.Q, dut.data_reg_7[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49833_.Q !== dut.data_reg_7[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27675 gold=%b dut=%b", gold._49833_.Q, dut.data_reg_7[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49834_.Q !== dut.data_reg_7[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27676 gold=%b dut=%b", gold._49834_.Q, dut.data_reg_7[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49835_.Q !== dut.data_reg_7[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27677 gold=%b dut=%b", gold._49835_.Q, dut.data_reg_7[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49836_.Q !== dut.data_reg_7[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27678 gold=%b dut=%b", gold._49836_.Q, dut.data_reg_7[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49837_.Q !== dut.data_reg_7[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27679 gold=%b dut=%b", gold._49837_.Q, dut.data_reg_7[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49838_.Q !== dut.data_reg_7[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27680 gold=%b dut=%b", gold._49838_.Q, dut.data_reg_7[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49807_.Q !== dut.control_reg_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27681 gold=%b dut=%b", gold._49807_.Q, dut.control_reg_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49808_.Q !== dut.control_reg_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27682 gold=%b dut=%b", gold._49808_.Q, dut.control_reg_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49809_.Q !== dut.control_reg_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27683 gold=%b dut=%b", gold._49809_.Q, dut.control_reg_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49810_.Q !== dut.control_reg_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27684 gold=%b dut=%b", gold._49810_.Q, dut.control_reg_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49811_.Q !== dut.control_reg_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27685 gold=%b dut=%b", gold._49811_.Q, dut.control_reg_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49812_.Q !== dut.control_reg_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27686 gold=%b dut=%b", gold._49812_.Q, dut.control_reg_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49813_.Q !== dut.control_reg_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27687 gold=%b dut=%b", gold._49813_.Q, dut.control_reg_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49814_.Q !== dut.control_reg_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27688 gold=%b dut=%b", gold._49814_.Q, dut.control_reg_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49815_.Q !== dut.control_reg_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27689 gold=%b dut=%b", gold._49815_.Q, dut.control_reg_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49816_.Q !== dut.control_reg_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27690 gold=%b dut=%b", gold._49816_.Q, dut.control_reg_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49817_.Q !== dut.control_reg_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27691 gold=%b dut=%b", gold._49817_.Q, dut.control_reg_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49818_.Q !== dut.control_reg_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27692 gold=%b dut=%b", gold._49818_.Q, dut.control_reg_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49819_.Q !== dut.control_reg_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27693 gold=%b dut=%b", gold._49819_.Q, dut.control_reg_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49820_.Q !== dut.control_reg_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27694 gold=%b dut=%b", gold._49820_.Q, dut.control_reg_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49821_.Q !== dut.control_reg_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27695 gold=%b dut=%b", gold._49821_.Q, dut.control_reg_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49822_.Q !== dut.control_reg_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27696 gold=%b dut=%b", gold._49822_.Q, dut.control_reg_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49823_.Q !== dut.control_reg_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27697 gold=%b dut=%b", gold._49823_.Q, dut.control_reg_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49824_.Q !== dut.control_reg_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27698 gold=%b dut=%b", gold._49824_.Q, dut.control_reg_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49825_.Q !== dut.control_reg_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27699 gold=%b dut=%b", gold._49825_.Q, dut.control_reg_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49826_.Q !== dut.control_reg_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27700 gold=%b dut=%b", gold._49826_.Q, dut.control_reg_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49827_.Q !== dut.control_reg_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27701 gold=%b dut=%b", gold._49827_.Q, dut.control_reg_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49828_.Q !== dut.control_reg_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27702 gold=%b dut=%b", gold._49828_.Q, dut.control_reg_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49829_.Q !== dut.control_reg_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27703 gold=%b dut=%b", gold._49829_.Q, dut.control_reg_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49830_.Q !== dut.control_reg_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27704 gold=%b dut=%b", gold._49830_.Q, dut.control_reg_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49831_.Q !== dut.control_reg_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27705 gold=%b dut=%b", gold._49831_.Q, dut.control_reg_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49907_.Q !== dut.control_state_10[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27706 gold=%b dut=%b", gold._49907_.Q, dut.control_state_10[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49908_.Q !== dut.control_state_10[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27707 gold=%b dut=%b", gold._49908_.Q, dut.control_state_10[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50059_.Q !== dut.control_status[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27708 gold=%b dut=%b", gold._50059_.Q, dut.control_status[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50060_.Q !== dut.control_status[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27709 gold=%b dut=%b", gold._50060_.Q, dut.control_status[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48385_.Q !== dut.data_register_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27742 gold=%b dut=%b", gold._48385_.Q, dut.data_register_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48386_.Q !== dut.data_register_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27743 gold=%b dut=%b", gold._48386_.Q, dut.data_register_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48387_.Q !== dut.data_register_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27744 gold=%b dut=%b", gold._48387_.Q, dut.data_register_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48388_.Q !== dut.data_register_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27745 gold=%b dut=%b", gold._48388_.Q, dut.data_register_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48389_.Q !== dut.data_register_4[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27746 gold=%b dut=%b", gold._48389_.Q, dut.data_register_4[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48390_.Q !== dut.data_register_4[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27747 gold=%b dut=%b", gold._48390_.Q, dut.data_register_4[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48391_.Q !== dut.data_register_4[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27748 gold=%b dut=%b", gold._48391_.Q, dut.data_register_4[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48392_.Q !== dut.data_register_4[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27749 gold=%b dut=%b", gold._48392_.Q, dut.data_register_4[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48393_.Q !== dut.data_register_4[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27750 gold=%b dut=%b", gold._48393_.Q, dut.data_register_4[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48394_.Q !== dut.data_register_4[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27751 gold=%b dut=%b", gold._48394_.Q, dut.data_register_4[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48395_.Q !== dut.data_register_4[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27752 gold=%b dut=%b", gold._48395_.Q, dut.data_register_4[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48396_.Q !== dut.data_register_4[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27753 gold=%b dut=%b", gold._48396_.Q, dut.data_register_4[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48397_.Q !== dut.data_register_4[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27754 gold=%b dut=%b", gold._48397_.Q, dut.data_register_4[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48398_.Q !== dut.data_register_4[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27755 gold=%b dut=%b", gold._48398_.Q, dut.data_register_4[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48399_.Q !== dut.data_register_4[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27756 gold=%b dut=%b", gold._48399_.Q, dut.data_register_4[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48400_.Q !== dut.data_register_4[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27757 gold=%b dut=%b", gold._48400_.Q, dut.data_register_4[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48401_.Q !== dut.data_register_4[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27758 gold=%b dut=%b", gold._48401_.Q, dut.data_register_4[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48402_.Q !== dut.data_register_4[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27759 gold=%b dut=%b", gold._48402_.Q, dut.data_register_4[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48403_.Q !== dut.data_register_4[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27760 gold=%b dut=%b", gold._48403_.Q, dut.data_register_4[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48404_.Q !== dut.data_register_4[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27761 gold=%b dut=%b", gold._48404_.Q, dut.data_register_4[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48405_.Q !== dut.data_register_4[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27762 gold=%b dut=%b", gold._48405_.Q, dut.data_register_4[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48406_.Q !== dut.data_register_4[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27763 gold=%b dut=%b", gold._48406_.Q, dut.data_register_4[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48407_.Q !== dut.data_register_4[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27764 gold=%b dut=%b", gold._48407_.Q, dut.data_register_4[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48408_.Q !== dut.data_register_4[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27765 gold=%b dut=%b", gold._48408_.Q, dut.data_register_4[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48409_.Q !== dut.data_register_4[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27766 gold=%b dut=%b", gold._48409_.Q, dut.data_register_4[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48410_.Q !== dut.data_register_4[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27767 gold=%b dut=%b", gold._48410_.Q, dut.data_register_4[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48411_.Q !== dut.data_register_4[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27768 gold=%b dut=%b", gold._48411_.Q, dut.data_register_4[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48412_.Q !== dut.data_register_4[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27769 gold=%b dut=%b", gold._48412_.Q, dut.data_register_4[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48413_.Q !== dut.data_register_4[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27770 gold=%b dut=%b", gold._48413_.Q, dut.data_register_4[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48414_.Q !== dut.data_register_4[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27771 gold=%b dut=%b", gold._48414_.Q, dut.data_register_4[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48415_.Q !== dut.data_register_4[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27772 gold=%b dut=%b", gold._48415_.Q, dut.data_register_4[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48416_.Q !== dut.data_register_4[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27773 gold=%b dut=%b", gold._48416_.Q, dut.data_register_4[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48384_.Q !== dut.control_flag_27775) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27775 gold=%b dut=%b", gold._48384_.Q, dut.control_flag_27775);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49672_.Q !== dut.status_flag_8) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27776 gold=%b dut=%b", gold._49672_.Q, dut.status_flag_8);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49931_.Q !== dut.event_delay_shift[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27781 gold=%b dut=%b", gold._49931_.Q, dut.event_delay_shift[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50005_.Q !== dut.all_clear_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27782 gold=%b dut=%b", gold._50005_.Q, dut.all_clear_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50162_.Q !== dut.fsm_state_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27783 gold=%b dut=%b", gold._50162_.Q, dut.fsm_state_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50163_.Q !== dut.fsm_state_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27784 gold=%b dut=%b", gold._50163_.Q, dut.fsm_state_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50164_.Q !== dut.fsm_state_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27785 gold=%b dut=%b", gold._50164_.Q, dut.fsm_state_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50165_.Q !== dut.fsm_state_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27786 gold=%b dut=%b", gold._50165_.Q, dut.fsm_state_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49912_.Q !== dut.control_state_10[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27787 gold=%b dut=%b", gold._49912_.Q, dut.control_state_10[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._49297_.Q !== dut.busy_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27788 gold=%b dut=%b", gold._49297_.Q, dut.busy_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50198_.Q !== dut.data_reg_24[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27789 gold=%b dut=%b", gold._50198_.Q, dut.data_reg_24[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50199_.Q !== dut.data_reg_24[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27790 gold=%b dut=%b", gold._50199_.Q, dut.data_reg_24[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50200_.Q !== dut.data_reg_24[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27791 gold=%b dut=%b", gold._50200_.Q, dut.data_reg_24[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50201_.Q !== dut.data_reg_24[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27792 gold=%b dut=%b", gold._50201_.Q, dut.data_reg_24[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50202_.Q !== dut.data_reg_24[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27793 gold=%b dut=%b", gold._50202_.Q, dut.data_reg_24[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50203_.Q !== dut.data_reg_24[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27794 gold=%b dut=%b", gold._50203_.Q, dut.data_reg_24[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50204_.Q !== dut.data_reg_24[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27795 gold=%b dut=%b", gold._50204_.Q, dut.data_reg_24[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50205_.Q !== dut.data_reg_24[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27796 gold=%b dut=%b", gold._50205_.Q, dut.data_reg_24[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50206_.Q !== dut.data_reg_24[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27797 gold=%b dut=%b", gold._50206_.Q, dut.data_reg_24[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50207_.Q !== dut.data_reg_24[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27798 gold=%b dut=%b", gold._50207_.Q, dut.data_reg_24[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50208_.Q !== dut.data_reg_24[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27799 gold=%b dut=%b", gold._50208_.Q, dut.data_reg_24[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50209_.Q !== dut.data_reg_24[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27800 gold=%b dut=%b", gold._50209_.Q, dut.data_reg_24[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50210_.Q !== dut.data_reg_24[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27801 gold=%b dut=%b", gold._50210_.Q, dut.data_reg_24[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50211_.Q !== dut.data_reg_24[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27802 gold=%b dut=%b", gold._50211_.Q, dut.data_reg_24[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50212_.Q !== dut.data_reg_24[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27803 gold=%b dut=%b", gold._50212_.Q, dut.data_reg_24[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50213_.Q !== dut.data_reg_24[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27804 gold=%b dut=%b", gold._50213_.Q, dut.data_reg_24[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50214_.Q !== dut.data_reg_24[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27805 gold=%b dut=%b", gold._50214_.Q, dut.data_reg_24[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50215_.Q !== dut.data_reg_24[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27806 gold=%b dut=%b", gold._50215_.Q, dut.data_reg_24[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50216_.Q !== dut.data_reg_24[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27807 gold=%b dut=%b", gold._50216_.Q, dut.data_reg_24[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50217_.Q !== dut.data_reg_24[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27808 gold=%b dut=%b", gold._50217_.Q, dut.data_reg_24[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50218_.Q !== dut.data_reg_24[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27809 gold=%b dut=%b", gold._50218_.Q, dut.data_reg_24[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50219_.Q !== dut.data_reg_24[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27810 gold=%b dut=%b", gold._50219_.Q, dut.data_reg_24[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50220_.Q !== dut.data_reg_24[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27811 gold=%b dut=%b", gold._50220_.Q, dut.data_reg_24[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50221_.Q !== dut.data_reg_24[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27812 gold=%b dut=%b", gold._50221_.Q, dut.data_reg_24[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50222_.Q !== dut.accumulator_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27813 gold=%b dut=%b", gold._50222_.Q, dut.accumulator_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50223_.Q !== dut.accumulator_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27814 gold=%b dut=%b", gold._50223_.Q, dut.accumulator_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50224_.Q !== dut.accumulator_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27815 gold=%b dut=%b", gold._50224_.Q, dut.accumulator_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50225_.Q !== dut.accumulator_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27816 gold=%b dut=%b", gold._50225_.Q, dut.accumulator_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50226_.Q !== dut.accumulator_high[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27817 gold=%b dut=%b", gold._50226_.Q, dut.accumulator_high[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50227_.Q !== dut.accumulator_high[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27818 gold=%b dut=%b", gold._50227_.Q, dut.accumulator_high[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50228_.Q !== dut.accumulator_high[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27819 gold=%b dut=%b", gold._50228_.Q, dut.accumulator_high[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48273_.Q !== dut.low_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27884 gold=%b dut=%b", gold._48273_.Q, dut.low_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48274_.Q !== dut.low_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27885 gold=%b dut=%b", gold._48274_.Q, dut.low_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48275_.Q !== dut.low_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27886 gold=%b dut=%b", gold._48275_.Q, dut.low_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48276_.Q !== dut.low_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27887 gold=%b dut=%b", gold._48276_.Q, dut.low_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48277_.Q !== dut.low_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27888 gold=%b dut=%b", gold._48277_.Q, dut.low_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48278_.Q !== dut.low_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27889 gold=%b dut=%b", gold._48278_.Q, dut.low_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48279_.Q !== dut.low_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27890 gold=%b dut=%b", gold._48279_.Q, dut.low_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48280_.Q !== dut.low_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27891 gold=%b dut=%b", gold._48280_.Q, dut.low_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48281_.Q !== dut.low_data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27892 gold=%b dut=%b", gold._48281_.Q, dut.low_data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48282_.Q !== dut.adder_result_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27893 gold=%b dut=%b", gold._48282_.Q, dut.adder_result_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48283_.Q !== dut.adder_result_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27894 gold=%b dut=%b", gold._48283_.Q, dut.adder_result_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48284_.Q !== dut.adder_result_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27895 gold=%b dut=%b", gold._48284_.Q, dut.adder_result_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48285_.Q !== dut.adder_result_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27896 gold=%b dut=%b", gold._48285_.Q, dut.adder_result_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48286_.Q !== dut.adder_result_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27897 gold=%b dut=%b", gold._48286_.Q, dut.adder_result_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48287_.Q !== dut.adder_result_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27898 gold=%b dut=%b", gold._48287_.Q, dut.adder_result_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48288_.Q !== dut.adder_result_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27899 gold=%b dut=%b", gold._48288_.Q, dut.adder_result_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48289_.Q !== dut.adder_result_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27900 gold=%b dut=%b", gold._48289_.Q, dut.adder_result_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48290_.Q !== dut.adder_result_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27901 gold=%b dut=%b", gold._48290_.Q, dut.adder_result_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48291_.Q !== dut.adder_result_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27902 gold=%b dut=%b", gold._48291_.Q, dut.adder_result_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48292_.Q !== dut.adder_result_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27903 gold=%b dut=%b", gold._48292_.Q, dut.adder_result_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48293_.Q !== dut.adder_result_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27904 gold=%b dut=%b", gold._48293_.Q, dut.adder_result_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48294_.Q !== dut.adder_result_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27905 gold=%b dut=%b", gold._48294_.Q, dut.adder_result_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48295_.Q !== dut.adder_result_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27906 gold=%b dut=%b", gold._48295_.Q, dut.adder_result_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48296_.Q !== dut.adder_result_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27907 gold=%b dut=%b", gold._48296_.Q, dut.adder_result_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48297_.Q !== dut.adder_result_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27908 gold=%b dut=%b", gold._48297_.Q, dut.adder_result_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48298_.Q !== dut.adder_result_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27909 gold=%b dut=%b", gold._48298_.Q, dut.adder_result_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48299_.Q !== dut.adder_result_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27910 gold=%b dut=%b", gold._48299_.Q, dut.adder_result_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48300_.Q !== dut.adder_result_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27911 gold=%b dut=%b", gold._48300_.Q, dut.adder_result_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48301_.Q !== dut.adder_result_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27912 gold=%b dut=%b", gold._48301_.Q, dut.adder_result_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48302_.Q !== dut.adder_result_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27913 gold=%b dut=%b", gold._48302_.Q, dut.adder_result_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48303_.Q !== dut.adder_result_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27914 gold=%b dut=%b", gold._48303_.Q, dut.adder_result_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48304_.Q !== dut.adder_result_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27915 gold=%b dut=%b", gold._48304_.Q, dut.adder_result_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50229_.Q !== dut.pipeline_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27917 gold=%b dut=%b", gold._50229_.Q, dut.pipeline_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50230_.Q !== dut.pipeline_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27918 gold=%b dut=%b", gold._50230_.Q, dut.pipeline_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50231_.Q !== dut.pipeline_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27919 gold=%b dut=%b", gold._50231_.Q, dut.pipeline_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50232_.Q !== dut.pipeline_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27920 gold=%b dut=%b", gold._50232_.Q, dut.pipeline_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50233_.Q !== dut.pipeline_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27921 gold=%b dut=%b", gold._50233_.Q, dut.pipeline_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50234_.Q !== dut.pipeline_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27922 gold=%b dut=%b", gold._50234_.Q, dut.pipeline_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50235_.Q !== dut.pipeline_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27923 gold=%b dut=%b", gold._50235_.Q, dut.pipeline_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50236_.Q !== dut.pipeline_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27924 gold=%b dut=%b", gold._50236_.Q, dut.pipeline_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50237_.Q !== dut.pipeline_data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27925 gold=%b dut=%b", gold._50237_.Q, dut.pipeline_data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50238_.Q !== dut.pipeline_data_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27926 gold=%b dut=%b", gold._50238_.Q, dut.pipeline_data_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50239_.Q !== dut.pipeline_data_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27927 gold=%b dut=%b", gold._50239_.Q, dut.pipeline_data_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50240_.Q !== dut.pipeline_data_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27928 gold=%b dut=%b", gold._50240_.Q, dut.pipeline_data_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50241_.Q !== dut.pipeline_data_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27929 gold=%b dut=%b", gold._50241_.Q, dut.pipeline_data_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50242_.Q !== dut.pipeline_data_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27930 gold=%b dut=%b", gold._50242_.Q, dut.pipeline_data_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50243_.Q !== dut.pipeline_data_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27931 gold=%b dut=%b", gold._50243_.Q, dut.pipeline_data_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50244_.Q !== dut.pipeline_data_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27932 gold=%b dut=%b", gold._50244_.Q, dut.pipeline_data_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50245_.Q !== dut.pipeline_data_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27933 gold=%b dut=%b", gold._50245_.Q, dut.pipeline_data_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50246_.Q !== dut.pipeline_data_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27934 gold=%b dut=%b", gold._50246_.Q, dut.pipeline_data_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50247_.Q !== dut.pipeline_data_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27935 gold=%b dut=%b", gold._50247_.Q, dut.pipeline_data_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50248_.Q !== dut.pipeline_data_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27936 gold=%b dut=%b", gold._50248_.Q, dut.pipeline_data_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50249_.Q !== dut.pipeline_data_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27937 gold=%b dut=%b", gold._50249_.Q, dut.pipeline_data_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50250_.Q !== dut.pipeline_data_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27938 gold=%b dut=%b", gold._50250_.Q, dut.pipeline_data_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50251_.Q !== dut.pipeline_data_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27939 gold=%b dut=%b", gold._50251_.Q, dut.pipeline_data_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50252_.Q !== dut.pipeline_data_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27940 gold=%b dut=%b", gold._50252_.Q, dut.pipeline_data_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50253_.Q !== dut.pipeline_data_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27941 gold=%b dut=%b", gold._50253_.Q, dut.pipeline_data_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50254_.Q !== dut.pipeline_data_reg_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27942 gold=%b dut=%b", gold._50254_.Q, dut.pipeline_data_reg_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50255_.Q !== dut.pipeline_data_reg_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27943 gold=%b dut=%b", gold._50255_.Q, dut.pipeline_data_reg_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50256_.Q !== dut.pipeline_data_reg_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27944 gold=%b dut=%b", gold._50256_.Q, dut.pipeline_data_reg_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50257_.Q !== dut.pipeline_data_reg_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27945 gold=%b dut=%b", gold._50257_.Q, dut.pipeline_data_reg_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50258_.Q !== dut.pipeline_data_reg_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27946 gold=%b dut=%b", gold._50258_.Q, dut.pipeline_data_reg_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50259_.Q !== dut.pipeline_data_reg_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27947 gold=%b dut=%b", gold._50259_.Q, dut.pipeline_data_reg_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48305_.Q !== dut.index_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27948 gold=%b dut=%b", gold._48305_.Q, dut.index_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48306_.Q !== dut.index_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27949 gold=%b dut=%b", gold._48306_.Q, dut.index_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48307_.Q !== dut.index_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27950 gold=%b dut=%b", gold._48307_.Q, dut.index_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48308_.Q !== dut.index_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27951 gold=%b dut=%b", gold._48308_.Q, dut.index_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._48309_.Q !== dut.index_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27952 gold=%b dut=%b", gold._48309_.Q, dut.index_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50061_.Q !== dut.write_decode_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27953 gold=%b dut=%b", gold._50061_.Q, dut.write_decode_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50062_.Q !== dut.wide_data_reg_6[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27954 gold=%b dut=%b", gold._50062_.Q, dut.wide_data_reg_6[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50063_.Q !== dut.wide_data_reg_6[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27955 gold=%b dut=%b", gold._50063_.Q, dut.wide_data_reg_6[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50064_.Q !== dut.wide_data_reg_6[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27956 gold=%b dut=%b", gold._50064_.Q, dut.wide_data_reg_6[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50065_.Q !== dut.wide_data_reg_6[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27957 gold=%b dut=%b", gold._50065_.Q, dut.wide_data_reg_6[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50066_.Q !== dut.wide_data_reg_6[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27958 gold=%b dut=%b", gold._50066_.Q, dut.wide_data_reg_6[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50067_.Q !== dut.wide_data_reg_6[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27959 gold=%b dut=%b", gold._50067_.Q, dut.wide_data_reg_6[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50068_.Q !== dut.wide_data_reg_6[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27960 gold=%b dut=%b", gold._50068_.Q, dut.wide_data_reg_6[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50069_.Q !== dut.wide_data_reg_6[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27961 gold=%b dut=%b", gold._50069_.Q, dut.wide_data_reg_6[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50070_.Q !== dut.wide_data_reg_6[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27962 gold=%b dut=%b", gold._50070_.Q, dut.wide_data_reg_6[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50071_.Q !== dut.wide_data_reg_6[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27963 gold=%b dut=%b", gold._50071_.Q, dut.wide_data_reg_6[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50072_.Q !== dut.wide_data_reg_6[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27964 gold=%b dut=%b", gold._50072_.Q, dut.wide_data_reg_6[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50073_.Q !== dut.wide_data_reg_6[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27965 gold=%b dut=%b", gold._50073_.Q, dut.wide_data_reg_6[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50074_.Q !== dut.wide_data_reg_6[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27966 gold=%b dut=%b", gold._50074_.Q, dut.wide_data_reg_6[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50075_.Q !== dut.wide_data_reg_6[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27967 gold=%b dut=%b", gold._50075_.Q, dut.wide_data_reg_6[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50076_.Q !== dut.wide_data_reg_6[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27968 gold=%b dut=%b", gold._50076_.Q, dut.wide_data_reg_6[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50077_.Q !== dut.wide_data_reg_6[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27969 gold=%b dut=%b", gold._50077_.Q, dut.wide_data_reg_6[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50078_.Q !== dut.wide_data_reg_6[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27970 gold=%b dut=%b", gold._50078_.Q, dut.wide_data_reg_6[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50079_.Q !== dut.wide_data_reg_6[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27971 gold=%b dut=%b", gold._50079_.Q, dut.wide_data_reg_6[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50080_.Q !== dut.wide_data_reg_6[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27972 gold=%b dut=%b", gold._50080_.Q, dut.wide_data_reg_6[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50081_.Q !== dut.wide_data_reg_6[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27973 gold=%b dut=%b", gold._50081_.Q, dut.wide_data_reg_6[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50082_.Q !== dut.wide_data_reg_6[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27974 gold=%b dut=%b", gold._50082_.Q, dut.wide_data_reg_6[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50083_.Q !== dut.wide_data_reg_6[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27975 gold=%b dut=%b", gold._50083_.Q, dut.wide_data_reg_6[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50084_.Q !== dut.wide_data_reg_6[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27976 gold=%b dut=%b", gold._50084_.Q, dut.wide_data_reg_6[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50085_.Q !== dut.wide_data_reg_6[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27977 gold=%b dut=%b", gold._50085_.Q, dut.wide_data_reg_6[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50086_.Q !== dut.wide_data_reg_6[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27978 gold=%b dut=%b", gold._50086_.Q, dut.wide_data_reg_6[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50087_.Q !== dut.wide_data_reg_6[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27979 gold=%b dut=%b", gold._50087_.Q, dut.wide_data_reg_6[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50088_.Q !== dut.wide_data_reg_6[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27980 gold=%b dut=%b", gold._50088_.Q, dut.wide_data_reg_6[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50089_.Q !== dut.wide_data_reg_6[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27981 gold=%b dut=%b", gold._50089_.Q, dut.wide_data_reg_6[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50090_.Q !== dut.wide_data_reg_6[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27982 gold=%b dut=%b", gold._50090_.Q, dut.wide_data_reg_6[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50091_.Q !== dut.wide_data_reg_6[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27983 gold=%b dut=%b", gold._50091_.Q, dut.wide_data_reg_6[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (gold._50092_.Q !== dut.wide_data_nonzero_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27984 gold=%b dut=%b", gold._50092_.Q, dut.wide_data_nonzero_flag);
ff_errors=ff_errors+1;
end
end
end
endmodule