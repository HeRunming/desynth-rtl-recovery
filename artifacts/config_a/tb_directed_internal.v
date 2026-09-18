`timescale 1ns/1ps
module tb_directed_internal;
integer ff_errors=0, ff_checks=0;
  reg clk=0, resetn=0;
  reg mem_ready=1;
  reg [31:0] irq=0;
  reg g_pcpi_wr=0, g_pcpi_wait=0, g_pcpi_ready=0;
  reg d_pcpi_wr=0, d_pcpi_wait=0, d_pcpi_ready=0;
  reg [31:0] g_pcpi_rd=0, d_pcpi_rd=0;
  wire g_mem_valid, g_mem_instr, d_mem_valid, d_mem_instr;
  wire [31:0] g_mem_addr, d_mem_addr, g_mem_wdata, d_mem_wdata;
  wire [3:0] g_mem_wstrb, d_mem_wstrb;
  wire [31:0] mem_rdata;

  wire g_trap, g_mem_la_read, g_mem_la_write, g_pcpi_valid, g_trace_valid;
  wire [31:0] g_mem_la_addr, g_mem_la_wdata, g_pcpi_insn, g_pcpi_rs1, g_pcpi_rs2, g_eoi;
  wire [3:0] g_mem_la_wstrb;
  wire [35:0] g_trace_data;
  wire d_trap, d_mem_la_read, d_mem_la_write, d_pcpi_valid, d_trace_valid;
  wire [31:0] d_mem_la_addr, d_mem_la_wdata, d_pcpi_insn, d_pcpi_rs1, d_pcpi_rs2, d_eoi;
  wire [3:0] d_mem_la_wstrb;
  wire [35:0] d_trace_data;

  picorv32 g ( .clk(clk), .resetn(resetn), .trap(g_trap), .mem_valid(g_mem_valid), .mem_instr(g_mem_instr), .mem_ready(mem_ready), .mem_addr(g_mem_addr), .mem_wdata(g_mem_wdata), .mem_wstrb(g_mem_wstrb), .mem_rdata(mem_rdata), .mem_la_read(g_mem_la_read), .mem_la_write(g_mem_la_write), .mem_la_addr(g_mem_la_addr), .mem_la_wdata(g_mem_la_wdata), .mem_la_wstrb(g_mem_la_wstrb), .pcpi_valid(g_pcpi_valid), .pcpi_insn(g_pcpi_insn), .pcpi_rs1(g_pcpi_rs1), .pcpi_rs2(g_pcpi_rs2), .pcpi_wr(g_pcpi_wr), .pcpi_rd(g_pcpi_rd), .pcpi_wait(g_pcpi_wait), .pcpi_ready(g_pcpi_ready), .irq(irq), .eoi(g_eoi), .trace_valid(g_trace_valid), .trace_data(g_trace_data) );
  picorv32_lift d ( .clk(clk), .resetn(resetn), .trap(d_trap), .mem_valid(d_mem_valid), .mem_instr(d_mem_instr), .mem_ready(mem_ready), .mem_addr(d_mem_addr), .mem_wdata(d_mem_wdata), .mem_wstrb(d_mem_wstrb), .mem_rdata(mem_rdata), .mem_la_read(d_mem_la_read), .mem_la_write(d_mem_la_write), .mem_la_addr(d_mem_la_addr), .mem_la_wdata(d_mem_la_wdata), .mem_la_wstrb(d_mem_la_wstrb), .pcpi_valid(d_pcpi_valid), .pcpi_insn(d_pcpi_insn), .pcpi_rs1(d_pcpi_rs1), .pcpi_rs2(d_pcpi_rs2), .pcpi_wr(d_pcpi_wr), .pcpi_rd(d_pcpi_rd), .pcpi_wait(d_pcpi_wait), .pcpi_ready(d_pcpi_ready), .irq(irq), .eoi(d_eoi), .trace_valid(d_trace_valid), .trace_data(d_trace_data) );

  always #5 clk = ~clk;

  function [31:0] rom(input [31:0] addr);
    begin
      case (addr[31:2])
        30'd0: rom = 32'hfff00093;
        30'd1: rom = 32'h00200113;
        30'd2: rom = 32'h022081b3;
        30'd3: rom = 32'h10302023;
        30'd4: rom = 32'hfff00093;
        30'd5: rom = 32'h00200113;
        30'd6: rom = 32'h022091b3;
        30'd7: rom = 32'h10302223;
        30'd8: rom = 32'hfff00093;
        30'd9: rom = 32'h00200113;
        30'd10: rom = 32'h0220a1b3;
        30'd11: rom = 32'h10302423;
        30'd12: rom = 32'hfff00093;
        30'd13: rom = 32'h00200113;
        30'd14: rom = 32'h0220b1b3;
        30'd15: rom = 32'h10302623;
        30'd16: rom = 32'h80000093;
        30'd17: rom = 32'hfff00113;
        30'd18: rom = 32'h022091b3;
        30'd19: rom = 32'h10302823;
        30'd20: rom = 32'h80000093;
        30'd21: rom = 32'hfff00113;
        30'd22: rom = 32'h0220a1b3;
        30'd23: rom = 32'h10302a23;
        30'd24: rom = 32'h7ff00093;
        30'd25: rom = 32'h00200113;
        30'd26: rom = 32'h0220b1b3;
        30'd27: rom = 32'h10302c23;
        30'd28: rom = 32'h00000093;
        30'd29: rom = 32'hfff00113;
        30'd30: rom = 32'h022081b3;
        30'd31: rom = 32'h10302e23;
        30'd32: rom = 32'h0000006f;
        default: rom = 32'h00000013;
      endcase
    end
  endfunction
  assign mem_rdata = rom(g_mem_addr);

  integer cyc=0, errors=0, stores=0, dstores=0;
  integer op_seen [0:3], dop_seen [0:3];
  integer oi;
  always @(posedge clk) begin
    #1;
    if (resetn) begin
      cyc = cyc + 1;
      if (g_mem_valid !== d_mem_valid || g_mem_instr !== d_mem_instr || g_mem_addr !== d_mem_addr || g_mem_wdata !== d_mem_wdata || g_mem_wstrb !== d_mem_wstrb) begin
        errors = errors + 1;
        if (errors <= 8) $display("IFACE_MISMATCH cyc=%0d g=(%b,%b,%h,%h,%h) d=(%b,%b,%h,%h,%h)", cyc, g_mem_valid,g_mem_instr,g_mem_addr,g_mem_wdata,g_mem_wstrb,d_mem_valid,d_mem_instr,d_mem_addr,d_mem_wdata,d_mem_wstrb);
      end
      if (g_pcpi_valid && g_pcpi_insn[6:0] === 7'b0110011 && g_pcpi_insn[31:25] === 7'b0000001) op_seen[g_pcpi_insn[14:12]] = op_seen[g_pcpi_insn[14:12]] + 1;
      if (d_pcpi_valid && d_pcpi_insn[6:0] === 7'b0110011 && d_pcpi_insn[31:25] === 7'b0000001) dop_seen[d_pcpi_insn[14:12]] = dop_seen[d_pcpi_insn[14:12]] + 1;
      if (g_mem_valid && !g_mem_instr && g_mem_wstrb != 0) begin
        stores = stores + 1;
        $display("MUL_STORE cyc=%0d addr=%h gold=%h dut=%h wstrb=%h", cyc, g_mem_addr, g_mem_wdata, d_mem_wdata, g_mem_wstrb);
        if (g_mem_addr !== d_mem_addr || g_mem_wdata !== d_mem_wdata || g_mem_wstrb !== d_mem_wstrb) errors = errors + 1;
      end
      if (d_mem_valid && !d_mem_instr && d_mem_wstrb != 0) dstores = dstores + 1;
    end
  end
  initial begin
    for (oi=0; oi<4; oi=oi+1) begin op_seen[oi]=0; dop_seen[oi]=0; end
    repeat (5) @(posedge clk);
    @(negedge clk); resetn = 1;
    repeat (1500) @(posedge clk);
    $display("MUL_DIRECTED seed=%0d errors=%0d stores_gold=%0d stores_dut=%0d cycles=%0d", 0, errors, stores, dstores, cyc);
    for (oi=0; oi<4; oi=oi+1) $display("MUL_OPCODE funct3=%0d gold_handshakes=%0d dut_handshakes=%0d", oi, op_seen[oi], dop_seen[oi]);
    #2;
    $display("DIRECTED_INTERNAL bits=2313 errors=%0d checks=%0d",ff_errors,ff_checks);
    if(ff_errors || errors || stores!=8 || dstores!=8 || ff_checks<2313*1499) $fatal(1,"directed/internal failure");
    for(oi=0;oi<4;oi=oi+1) if(op_seen[oi]==0 || dop_seen[oi]==0) $fatal(1,"missing opcode");
    $finish;
  end
always @(posedge clk) begin
#1;
if (resetn) begin
ff_checks=ff_checks+1;
if (g._49806_.Q !== d.status_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=414 gold=%b dut=%b", g._49806_.Q, d.status_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50167_.Q !== d.control_word_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=621 gold=%b dut=%b", g._50167_.Q, d.control_word_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50168_.Q !== d.control_word_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=622 gold=%b dut=%b", g._50168_.Q, d.control_word_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50169_.Q !== d.control_word_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=623 gold=%b dut=%b", g._50169_.Q, d.control_word_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50170_.Q !== d.control_word_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=624 gold=%b dut=%b", g._50170_.Q, d.control_word_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50171_.Q !== d.control_word_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=625 gold=%b dut=%b", g._50171_.Q, d.control_word_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50172_.Q !== d.control_word_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=626 gold=%b dut=%b", g._50172_.Q, d.control_word_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50173_.Q !== d.control_word_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=627 gold=%b dut=%b", g._50173_.Q, d.control_word_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50174_.Q !== d.control_word_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=628 gold=%b dut=%b", g._50174_.Q, d.control_word_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50175_.Q !== d.control_word_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=629 gold=%b dut=%b", g._50175_.Q, d.control_word_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50176_.Q !== d.control_word_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=630 gold=%b dut=%b", g._50176_.Q, d.control_word_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50177_.Q !== d.control_word_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=631 gold=%b dut=%b", g._50177_.Q, d.control_word_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50178_.Q !== d.control_word_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=632 gold=%b dut=%b", g._50178_.Q, d.control_word_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50179_.Q !== d.control_word_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=633 gold=%b dut=%b", g._50179_.Q, d.control_word_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50180_.Q !== d.control_word_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=634 gold=%b dut=%b", g._50180_.Q, d.control_word_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50181_.Q !== d.control_word_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=635 gold=%b dut=%b", g._50181_.Q, d.control_word_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50182_.Q !== d.control_word_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=636 gold=%b dut=%b", g._50182_.Q, d.control_word_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50183_.Q !== d.control_word_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=637 gold=%b dut=%b", g._50183_.Q, d.control_word_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50184_.Q !== d.control_word_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=638 gold=%b dut=%b", g._50184_.Q, d.control_word_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50185_.Q !== d.control_word_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=639 gold=%b dut=%b", g._50185_.Q, d.control_word_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50186_.Q !== d.control_word_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=640 gold=%b dut=%b", g._50186_.Q, d.control_word_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50187_.Q !== d.control_word_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=641 gold=%b dut=%b", g._50187_.Q, d.control_word_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50188_.Q !== d.control_word_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=642 gold=%b dut=%b", g._50188_.Q, d.control_word_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50189_.Q !== d.control_word_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=643 gold=%b dut=%b", g._50189_.Q, d.control_word_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50190_.Q !== d.control_word_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=644 gold=%b dut=%b", g._50190_.Q, d.control_word_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50191_.Q !== d.control_word_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=645 gold=%b dut=%b", g._50191_.Q, d.control_word_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50192_.Q !== d.control_word_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=646 gold=%b dut=%b", g._50192_.Q, d.control_word_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50193_.Q !== d.control_word_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=647 gold=%b dut=%b", g._50193_.Q, d.control_word_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50194_.Q !== d.control_word_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=648 gold=%b dut=%b", g._50194_.Q, d.control_word_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50195_.Q !== d.control_word_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=649 gold=%b dut=%b", g._50195_.Q, d.control_word_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50196_.Q !== d.control_word_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=650 gold=%b dut=%b", g._50196_.Q, d.control_word_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50197_.Q !== d.control_word_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=651 gold=%b dut=%b", g._50197_.Q, d.control_word_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50166_.Q !== d.status_flag_1) begin
if(ff_errors<8) $display("FF_MISMATCH qid=652 gold=%b dut=%b", g._50166_.Q, d.status_flag_1);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50129_.Q !== d.small_selected_data_word[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=653 gold=%b dut=%b", g._50129_.Q, d.small_selected_data_word[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50130_.Q !== d.small_selected_data_word[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=654 gold=%b dut=%b", g._50130_.Q, d.small_selected_data_word[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50131_.Q !== d.small_selected_data_word[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=655 gold=%b dut=%b", g._50131_.Q, d.small_selected_data_word[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50132_.Q !== d.small_selected_data_word[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=656 gold=%b dut=%b", g._50132_.Q, d.small_selected_data_word[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50133_.Q !== d.small_selected_data_word[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=657 gold=%b dut=%b", g._50133_.Q, d.small_selected_data_word[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50134_.Q !== d.small_selected_data_word[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=658 gold=%b dut=%b", g._50134_.Q, d.small_selected_data_word[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50135_.Q !== d.small_selected_data_word[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=659 gold=%b dut=%b", g._50135_.Q, d.small_selected_data_word[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50136_.Q !== d.small_selected_data_word[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=660 gold=%b dut=%b", g._50136_.Q, d.small_selected_data_word[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50137_.Q !== d.small_selected_data_word[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=661 gold=%b dut=%b", g._50137_.Q, d.small_selected_data_word[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50138_.Q !== d.small_selected_data_word[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=662 gold=%b dut=%b", g._50138_.Q, d.small_selected_data_word[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50139_.Q !== d.small_selected_data_word[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=663 gold=%b dut=%b", g._50139_.Q, d.small_selected_data_word[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50140_.Q !== d.small_selected_data_word[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=664 gold=%b dut=%b", g._50140_.Q, d.small_selected_data_word[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50141_.Q !== d.small_selected_data_word[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=665 gold=%b dut=%b", g._50141_.Q, d.small_selected_data_word[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50142_.Q !== d.small_selected_data_word[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=666 gold=%b dut=%b", g._50142_.Q, d.small_selected_data_word[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50143_.Q !== d.small_selected_data_word[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=667 gold=%b dut=%b", g._50143_.Q, d.small_selected_data_word[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50144_.Q !== d.small_selected_data_word[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=668 gold=%b dut=%b", g._50144_.Q, d.small_selected_data_word[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50145_.Q !== d.small_selected_data_word[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=669 gold=%b dut=%b", g._50145_.Q, d.small_selected_data_word[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50146_.Q !== d.small_selected_data_word[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=670 gold=%b dut=%b", g._50146_.Q, d.small_selected_data_word[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50147_.Q !== d.small_selected_data_word[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=671 gold=%b dut=%b", g._50147_.Q, d.small_selected_data_word[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50148_.Q !== d.small_selected_data_word[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=672 gold=%b dut=%b", g._50148_.Q, d.small_selected_data_word[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50149_.Q !== d.small_selected_data_word[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=673 gold=%b dut=%b", g._50149_.Q, d.small_selected_data_word[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50150_.Q !== d.small_selected_data_word[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=674 gold=%b dut=%b", g._50150_.Q, d.small_selected_data_word[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50151_.Q !== d.small_selected_data_word[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=675 gold=%b dut=%b", g._50151_.Q, d.small_selected_data_word[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50152_.Q !== d.small_selected_data_word[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=676 gold=%b dut=%b", g._50152_.Q, d.small_selected_data_word[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50153_.Q !== d.small_selected_data_word[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=677 gold=%b dut=%b", g._50153_.Q, d.small_selected_data_word[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50154_.Q !== d.small_selected_data_word[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=678 gold=%b dut=%b", g._50154_.Q, d.small_selected_data_word[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50155_.Q !== d.small_selected_data_word[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=679 gold=%b dut=%b", g._50155_.Q, d.small_selected_data_word[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50156_.Q !== d.small_selected_data_word[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=680 gold=%b dut=%b", g._50156_.Q, d.small_selected_data_word[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50157_.Q !== d.small_selected_data_word[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=681 gold=%b dut=%b", g._50157_.Q, d.small_selected_data_word[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50158_.Q !== d.small_selected_data_word[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=682 gold=%b dut=%b", g._50158_.Q, d.small_selected_data_word[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50159_.Q !== d.small_selected_data_word[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=683 gold=%b dut=%b", g._50159_.Q, d.small_selected_data_word[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50160_.Q !== d.small_selected_data_word[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=684 gold=%b dut=%b", g._50160_.Q, d.small_selected_data_word[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50424_.Q !== d.data_word[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=752 gold=%b dut=%b", g._50424_.Q, d.data_word[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50425_.Q !== d.data_word[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=753 gold=%b dut=%b", g._50425_.Q, d.data_word[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50426_.Q !== d.data_word[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=754 gold=%b dut=%b", g._50426_.Q, d.data_word[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50427_.Q !== d.data_word[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=755 gold=%b dut=%b", g._50427_.Q, d.data_word[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50428_.Q !== d.data_word[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=756 gold=%b dut=%b", g._50428_.Q, d.data_word[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50429_.Q !== d.data_word[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=757 gold=%b dut=%b", g._50429_.Q, d.data_word[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50430_.Q !== d.data_word[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=758 gold=%b dut=%b", g._50430_.Q, d.data_word[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50431_.Q !== d.data_word[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=759 gold=%b dut=%b", g._50431_.Q, d.data_word[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50432_.Q !== d.data_word[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=760 gold=%b dut=%b", g._50432_.Q, d.data_word[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50433_.Q !== d.data_word[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=761 gold=%b dut=%b", g._50433_.Q, d.data_word[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50434_.Q !== d.data_word[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=762 gold=%b dut=%b", g._50434_.Q, d.data_word[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50435_.Q !== d.data_word[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=763 gold=%b dut=%b", g._50435_.Q, d.data_word[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50436_.Q !== d.data_word[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=764 gold=%b dut=%b", g._50436_.Q, d.data_word[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50437_.Q !== d.data_word[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=765 gold=%b dut=%b", g._50437_.Q, d.data_word[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50438_.Q !== d.data_word[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=766 gold=%b dut=%b", g._50438_.Q, d.data_word[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50439_.Q !== d.data_word[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=767 gold=%b dut=%b", g._50439_.Q, d.data_word[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50440_.Q !== d.data_word[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=768 gold=%b dut=%b", g._50440_.Q, d.data_word[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50441_.Q !== d.data_word[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=769 gold=%b dut=%b", g._50441_.Q, d.data_word[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50442_.Q !== d.data_word[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=770 gold=%b dut=%b", g._50442_.Q, d.data_word[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50443_.Q !== d.data_word[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=771 gold=%b dut=%b", g._50443_.Q, d.data_word[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50444_.Q !== d.data_word[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=772 gold=%b dut=%b", g._50444_.Q, d.data_word[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50445_.Q !== d.data_word[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=773 gold=%b dut=%b", g._50445_.Q, d.data_word[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50446_.Q !== d.data_word[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=774 gold=%b dut=%b", g._50446_.Q, d.data_word[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50447_.Q !== d.data_word[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=775 gold=%b dut=%b", g._50447_.Q, d.data_word[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50448_.Q !== d.data_word[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=776 gold=%b dut=%b", g._50448_.Q, d.data_word[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50449_.Q !== d.data_word[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=777 gold=%b dut=%b", g._50449_.Q, d.data_word[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50450_.Q !== d.data_word[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=778 gold=%b dut=%b", g._50450_.Q, d.data_word[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50451_.Q !== d.data_word[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=779 gold=%b dut=%b", g._50451_.Q, d.data_word[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50452_.Q !== d.data_word[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=780 gold=%b dut=%b", g._50452_.Q, d.data_word[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50453_.Q !== d.data_word[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=781 gold=%b dut=%b", g._50453_.Q, d.data_word[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50454_.Q !== d.data_word[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=782 gold=%b dut=%b", g._50454_.Q, d.data_word[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50455_.Q !== d.data_word[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=783 gold=%b dut=%b", g._50455_.Q, d.data_word[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49296_.Q !== d.status_flag_2) begin
if(ff_errors<8) $display("FF_MISMATCH qid=784 gold=%b dut=%b", g._49296_.Q, d.status_flag_2);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50388_.Q !== d.write_data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=785 gold=%b dut=%b", g._50388_.Q, d.write_data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50389_.Q !== d.write_data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=786 gold=%b dut=%b", g._50389_.Q, d.write_data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50390_.Q !== d.write_data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=787 gold=%b dut=%b", g._50390_.Q, d.write_data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50391_.Q !== d.write_data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=788 gold=%b dut=%b", g._50391_.Q, d.write_data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50392_.Q !== d.write_data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=789 gold=%b dut=%b", g._50392_.Q, d.write_data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50393_.Q !== d.write_data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=790 gold=%b dut=%b", g._50393_.Q, d.write_data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50394_.Q !== d.write_data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=791 gold=%b dut=%b", g._50394_.Q, d.write_data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50395_.Q !== d.write_data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=792 gold=%b dut=%b", g._50395_.Q, d.write_data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50396_.Q !== d.write_data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=793 gold=%b dut=%b", g._50396_.Q, d.write_data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50397_.Q !== d.write_data_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=794 gold=%b dut=%b", g._50397_.Q, d.write_data_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50398_.Q !== d.write_data_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=795 gold=%b dut=%b", g._50398_.Q, d.write_data_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50399_.Q !== d.write_data_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=796 gold=%b dut=%b", g._50399_.Q, d.write_data_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50400_.Q !== d.write_data_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=797 gold=%b dut=%b", g._50400_.Q, d.write_data_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50401_.Q !== d.write_data_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=798 gold=%b dut=%b", g._50401_.Q, d.write_data_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50402_.Q !== d.write_data_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=799 gold=%b dut=%b", g._50402_.Q, d.write_data_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50403_.Q !== d.write_data_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=800 gold=%b dut=%b", g._50403_.Q, d.write_data_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50404_.Q !== d.write_data_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=801 gold=%b dut=%b", g._50404_.Q, d.write_data_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50405_.Q !== d.write_data_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=802 gold=%b dut=%b", g._50405_.Q, d.write_data_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50406_.Q !== d.write_data_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=803 gold=%b dut=%b", g._50406_.Q, d.write_data_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50407_.Q !== d.write_data_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=804 gold=%b dut=%b", g._50407_.Q, d.write_data_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50408_.Q !== d.write_data_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=805 gold=%b dut=%b", g._50408_.Q, d.write_data_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50409_.Q !== d.write_data_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=806 gold=%b dut=%b", g._50409_.Q, d.write_data_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50410_.Q !== d.write_data_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=807 gold=%b dut=%b", g._50410_.Q, d.write_data_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50411_.Q !== d.write_data_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=808 gold=%b dut=%b", g._50411_.Q, d.write_data_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50412_.Q !== d.write_data_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=809 gold=%b dut=%b", g._50412_.Q, d.write_data_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50413_.Q !== d.write_data_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=810 gold=%b dut=%b", g._50413_.Q, d.write_data_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50414_.Q !== d.write_data_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=811 gold=%b dut=%b", g._50414_.Q, d.write_data_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50415_.Q !== d.write_data_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=812 gold=%b dut=%b", g._50415_.Q, d.write_data_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50416_.Q !== d.write_data_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=813 gold=%b dut=%b", g._50416_.Q, d.write_data_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50417_.Q !== d.write_data_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=814 gold=%b dut=%b", g._50417_.Q, d.write_data_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50418_.Q !== d.write_data_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=815 gold=%b dut=%b", g._50418_.Q, d.write_data_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50419_.Q !== d.write_data_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=816 gold=%b dut=%b", g._50419_.Q, d.write_data_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50420_.Q !== d.write_data_register[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=817 gold=%b dut=%b", g._50420_.Q, d.write_data_register[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50421_.Q !== d.write_data_register[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=818 gold=%b dut=%b", g._50421_.Q, d.write_data_register[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50422_.Q !== d.transfer_status[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=819 gold=%b dut=%b", g._50422_.Q, d.transfer_status[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50423_.Q !== d.transfer_status[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=820 gold=%b dut=%b", g._50423_.Q, d.transfer_status[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48417_.Q !== d.control_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=935 gold=%b dut=%b", g._48417_.Q, d.control_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48418_.Q !== d.control_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=936 gold=%b dut=%b", g._48418_.Q, d.control_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48419_.Q !== d.control_state[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=937 gold=%b dut=%b", g._48419_.Q, d.control_state[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48420_.Q !== d.control_state[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=938 gold=%b dut=%b", g._48420_.Q, d.control_state[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48421_.Q !== d.control_state[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=939 gold=%b dut=%b", g._48421_.Q, d.control_state[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48262_.Q !== d.control_state[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=940 gold=%b dut=%b", g._48262_.Q, d.control_state[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48263_.Q !== d.control_state[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=941 gold=%b dut=%b", g._48263_.Q, d.control_state[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48264_.Q !== d.control_state[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=942 gold=%b dut=%b", g._48264_.Q, d.control_state[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48265_.Q !== d.control_state[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=943 gold=%b dut=%b", g._48265_.Q, d.control_state[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48266_.Q !== d.control_state[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=944 gold=%b dut=%b", g._48266_.Q, d.control_state[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48267_.Q !== d.control_state[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=945 gold=%b dut=%b", g._48267_.Q, d.control_state[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48351_.Q !== d.alu_result_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25421 gold=%b dut=%b", g._48351_.Q, d.alu_result_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48352_.Q !== d.alu_result_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25422 gold=%b dut=%b", g._48352_.Q, d.alu_result_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48353_.Q !== d.alu_result_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25423 gold=%b dut=%b", g._48353_.Q, d.alu_result_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48354_.Q !== d.alu_result_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25424 gold=%b dut=%b", g._48354_.Q, d.alu_result_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48355_.Q !== d.alu_result_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25425 gold=%b dut=%b", g._48355_.Q, d.alu_result_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48356_.Q !== d.alu_result_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25426 gold=%b dut=%b", g._48356_.Q, d.alu_result_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48357_.Q !== d.alu_result_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25427 gold=%b dut=%b", g._48357_.Q, d.alu_result_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48358_.Q !== d.alu_result_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25428 gold=%b dut=%b", g._48358_.Q, d.alu_result_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48359_.Q !== d.alu_result_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25429 gold=%b dut=%b", g._48359_.Q, d.alu_result_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48360_.Q !== d.alu_result_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25430 gold=%b dut=%b", g._48360_.Q, d.alu_result_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48361_.Q !== d.alu_result_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25431 gold=%b dut=%b", g._48361_.Q, d.alu_result_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48362_.Q !== d.alu_result_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25432 gold=%b dut=%b", g._48362_.Q, d.alu_result_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48363_.Q !== d.alu_result_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25433 gold=%b dut=%b", g._48363_.Q, d.alu_result_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48364_.Q !== d.alu_result_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25434 gold=%b dut=%b", g._48364_.Q, d.alu_result_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48365_.Q !== d.alu_result_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25435 gold=%b dut=%b", g._48365_.Q, d.alu_result_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48366_.Q !== d.alu_result_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25436 gold=%b dut=%b", g._48366_.Q, d.alu_result_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48367_.Q !== d.alu_result_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25437 gold=%b dut=%b", g._48367_.Q, d.alu_result_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48368_.Q !== d.alu_result_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25438 gold=%b dut=%b", g._48368_.Q, d.alu_result_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48369_.Q !== d.alu_result_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25439 gold=%b dut=%b", g._48369_.Q, d.alu_result_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48370_.Q !== d.alu_result_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25440 gold=%b dut=%b", g._48370_.Q, d.alu_result_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48371_.Q !== d.alu_result_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25441 gold=%b dut=%b", g._48371_.Q, d.alu_result_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48372_.Q !== d.alu_result_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25442 gold=%b dut=%b", g._48372_.Q, d.alu_result_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48373_.Q !== d.alu_result_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25443 gold=%b dut=%b", g._48373_.Q, d.alu_result_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48374_.Q !== d.alu_result_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25444 gold=%b dut=%b", g._48374_.Q, d.alu_result_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48375_.Q !== d.alu_result_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25445 gold=%b dut=%b", g._48375_.Q, d.alu_result_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48376_.Q !== d.alu_result_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25446 gold=%b dut=%b", g._48376_.Q, d.alu_result_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48377_.Q !== d.alu_result_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25447 gold=%b dut=%b", g._48377_.Q, d.alu_result_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48378_.Q !== d.alu_result_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25448 gold=%b dut=%b", g._48378_.Q, d.alu_result_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48379_.Q !== d.alu_result_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25449 gold=%b dut=%b", g._48379_.Q, d.alu_result_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48380_.Q !== d.alu_result_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25450 gold=%b dut=%b", g._48380_.Q, d.alu_result_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48381_.Q !== d.alu_result_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25451 gold=%b dut=%b", g._48381_.Q, d.alu_result_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48382_.Q !== d.control_flag_25452) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25452 gold=%b dut=%b", g._48382_.Q, d.control_flag_25452);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48272_.Q !== d.sticky_hold_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25454 gold=%b dut=%b", g._48272_.Q, d.sticky_hold_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50466_.Q !== d.datapath_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25455 gold=%b dut=%b", g._50466_.Q, d.datapath_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50324_.Q !== d.enabled_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25456 gold=%b dut=%b", g._50324_.Q, d.enabled_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50325_.Q !== d.enabled_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25457 gold=%b dut=%b", g._50325_.Q, d.enabled_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50326_.Q !== d.enabled_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25458 gold=%b dut=%b", g._50326_.Q, d.enabled_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50327_.Q !== d.enabled_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25459 gold=%b dut=%b", g._50327_.Q, d.enabled_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50328_.Q !== d.enabled_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25460 gold=%b dut=%b", g._50328_.Q, d.enabled_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50329_.Q !== d.enabled_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25461 gold=%b dut=%b", g._50329_.Q, d.enabled_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50330_.Q !== d.enabled_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25462 gold=%b dut=%b", g._50330_.Q, d.enabled_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50331_.Q !== d.enabled_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25463 gold=%b dut=%b", g._50331_.Q, d.enabled_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50332_.Q !== d.enabled_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25464 gold=%b dut=%b", g._50332_.Q, d.enabled_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50333_.Q !== d.enabled_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25465 gold=%b dut=%b", g._50333_.Q, d.enabled_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50334_.Q !== d.enabled_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25466 gold=%b dut=%b", g._50334_.Q, d.enabled_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50335_.Q !== d.enabled_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25467 gold=%b dut=%b", g._50335_.Q, d.enabled_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50336_.Q !== d.enabled_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25468 gold=%b dut=%b", g._50336_.Q, d.enabled_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50337_.Q !== d.enabled_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25469 gold=%b dut=%b", g._50337_.Q, d.enabled_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50338_.Q !== d.enabled_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25470 gold=%b dut=%b", g._50338_.Q, d.enabled_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50339_.Q !== d.enabled_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25471 gold=%b dut=%b", g._50339_.Q, d.enabled_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50340_.Q !== d.enabled_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25472 gold=%b dut=%b", g._50340_.Q, d.enabled_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50341_.Q !== d.enabled_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25473 gold=%b dut=%b", g._50341_.Q, d.enabled_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50342_.Q !== d.enabled_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25474 gold=%b dut=%b", g._50342_.Q, d.enabled_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50343_.Q !== d.enabled_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25475 gold=%b dut=%b", g._50343_.Q, d.enabled_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50344_.Q !== d.enabled_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25476 gold=%b dut=%b", g._50344_.Q, d.enabled_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50345_.Q !== d.enabled_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25477 gold=%b dut=%b", g._50345_.Q, d.enabled_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50346_.Q !== d.enabled_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25478 gold=%b dut=%b", g._50346_.Q, d.enabled_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50347_.Q !== d.enabled_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25479 gold=%b dut=%b", g._50347_.Q, d.enabled_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50348_.Q !== d.enabled_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25480 gold=%b dut=%b", g._50348_.Q, d.enabled_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50349_.Q !== d.enabled_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25481 gold=%b dut=%b", g._50349_.Q, d.enabled_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50350_.Q !== d.enabled_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25482 gold=%b dut=%b", g._50350_.Q, d.enabled_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50351_.Q !== d.enabled_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25483 gold=%b dut=%b", g._50351_.Q, d.enabled_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50352_.Q !== d.enabled_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25484 gold=%b dut=%b", g._50352_.Q, d.enabled_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50353_.Q !== d.enabled_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25485 gold=%b dut=%b", g._50353_.Q, d.enabled_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50354_.Q !== d.enabled_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25486 gold=%b dut=%b", g._50354_.Q, d.enabled_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50355_.Q !== d.enabled_counter[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25487 gold=%b dut=%b", g._50355_.Q, d.enabled_counter[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50356_.Q !== d.enabled_counter[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25488 gold=%b dut=%b", g._50356_.Q, d.enabled_counter[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50357_.Q !== d.enabled_counter[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25489 gold=%b dut=%b", g._50357_.Q, d.enabled_counter[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50358_.Q !== d.enabled_counter[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25490 gold=%b dut=%b", g._50358_.Q, d.enabled_counter[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50359_.Q !== d.enabled_counter[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25491 gold=%b dut=%b", g._50359_.Q, d.enabled_counter[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50360_.Q !== d.enabled_counter[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25492 gold=%b dut=%b", g._50360_.Q, d.enabled_counter[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50361_.Q !== d.enabled_counter[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25493 gold=%b dut=%b", g._50361_.Q, d.enabled_counter[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50362_.Q !== d.enabled_counter[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25494 gold=%b dut=%b", g._50362_.Q, d.enabled_counter[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50363_.Q !== d.enabled_counter[39]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25495 gold=%b dut=%b", g._50363_.Q, d.enabled_counter[39]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50364_.Q !== d.enabled_counter[40]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25496 gold=%b dut=%b", g._50364_.Q, d.enabled_counter[40]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50365_.Q !== d.enabled_counter[41]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25497 gold=%b dut=%b", g._50365_.Q, d.enabled_counter[41]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50366_.Q !== d.enabled_counter[42]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25498 gold=%b dut=%b", g._50366_.Q, d.enabled_counter[42]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50367_.Q !== d.enabled_counter[43]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25499 gold=%b dut=%b", g._50367_.Q, d.enabled_counter[43]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50368_.Q !== d.enabled_counter[44]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25500 gold=%b dut=%b", g._50368_.Q, d.enabled_counter[44]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50369_.Q !== d.enabled_counter[45]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25501 gold=%b dut=%b", g._50369_.Q, d.enabled_counter[45]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50370_.Q !== d.enabled_counter[46]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25502 gold=%b dut=%b", g._50370_.Q, d.enabled_counter[46]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50371_.Q !== d.enabled_counter[47]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25503 gold=%b dut=%b", g._50371_.Q, d.enabled_counter[47]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50372_.Q !== d.enabled_counter[48]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25504 gold=%b dut=%b", g._50372_.Q, d.enabled_counter[48]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50373_.Q !== d.enabled_counter[49]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25505 gold=%b dut=%b", g._50373_.Q, d.enabled_counter[49]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50374_.Q !== d.enabled_counter[50]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25506 gold=%b dut=%b", g._50374_.Q, d.enabled_counter[50]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50375_.Q !== d.enabled_counter[51]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25507 gold=%b dut=%b", g._50375_.Q, d.enabled_counter[51]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50376_.Q !== d.enabled_counter[52]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25508 gold=%b dut=%b", g._50376_.Q, d.enabled_counter[52]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50377_.Q !== d.enabled_counter[53]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25509 gold=%b dut=%b", g._50377_.Q, d.enabled_counter[53]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50378_.Q !== d.enabled_counter[54]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25510 gold=%b dut=%b", g._50378_.Q, d.enabled_counter[54]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50379_.Q !== d.enabled_counter[55]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25511 gold=%b dut=%b", g._50379_.Q, d.enabled_counter[55]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50380_.Q !== d.enabled_counter[56]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25512 gold=%b dut=%b", g._50380_.Q, d.enabled_counter[56]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50381_.Q !== d.enabled_counter[57]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25513 gold=%b dut=%b", g._50381_.Q, d.enabled_counter[57]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50382_.Q !== d.enabled_counter[58]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25514 gold=%b dut=%b", g._50382_.Q, d.enabled_counter[58]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50383_.Q !== d.enabled_counter[59]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25515 gold=%b dut=%b", g._50383_.Q, d.enabled_counter[59]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50384_.Q !== d.enabled_counter[60]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25516 gold=%b dut=%b", g._50384_.Q, d.enabled_counter[60]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50385_.Q !== d.enabled_counter[61]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25517 gold=%b dut=%b", g._50385_.Q, d.enabled_counter[61]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50386_.Q !== d.enabled_counter[62]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25518 gold=%b dut=%b", g._50386_.Q, d.enabled_counter[62]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50387_.Q !== d.enabled_counter[63]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25519 gold=%b dut=%b", g._50387_.Q, d.enabled_counter[63]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50260_.Q !== d.small_event_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25520 gold=%b dut=%b", g._50260_.Q, d.small_event_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50261_.Q !== d.small_event_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25521 gold=%b dut=%b", g._50261_.Q, d.small_event_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50262_.Q !== d.small_event_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25522 gold=%b dut=%b", g._50262_.Q, d.small_event_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50263_.Q !== d.small_event_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25523 gold=%b dut=%b", g._50263_.Q, d.small_event_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50264_.Q !== d.small_event_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25524 gold=%b dut=%b", g._50264_.Q, d.small_event_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50265_.Q !== d.small_event_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25525 gold=%b dut=%b", g._50265_.Q, d.small_event_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50266_.Q !== d.small_event_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25526 gold=%b dut=%b", g._50266_.Q, d.small_event_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50267_.Q !== d.small_event_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25527 gold=%b dut=%b", g._50267_.Q, d.small_event_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50268_.Q !== d.small_event_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25528 gold=%b dut=%b", g._50268_.Q, d.small_event_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50269_.Q !== d.small_event_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25529 gold=%b dut=%b", g._50269_.Q, d.small_event_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50270_.Q !== d.small_event_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25530 gold=%b dut=%b", g._50270_.Q, d.small_event_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50271_.Q !== d.small_event_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25531 gold=%b dut=%b", g._50271_.Q, d.small_event_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50272_.Q !== d.small_event_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25532 gold=%b dut=%b", g._50272_.Q, d.small_event_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50273_.Q !== d.small_event_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25533 gold=%b dut=%b", g._50273_.Q, d.small_event_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50274_.Q !== d.small_event_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25534 gold=%b dut=%b", g._50274_.Q, d.small_event_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50275_.Q !== d.small_event_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25535 gold=%b dut=%b", g._50275_.Q, d.small_event_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50276_.Q !== d.small_event_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25536 gold=%b dut=%b", g._50276_.Q, d.small_event_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50277_.Q !== d.small_event_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25537 gold=%b dut=%b", g._50277_.Q, d.small_event_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50278_.Q !== d.small_event_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25538 gold=%b dut=%b", g._50278_.Q, d.small_event_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50279_.Q !== d.small_event_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25539 gold=%b dut=%b", g._50279_.Q, d.small_event_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50280_.Q !== d.small_event_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25540 gold=%b dut=%b", g._50280_.Q, d.small_event_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50281_.Q !== d.small_event_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25541 gold=%b dut=%b", g._50281_.Q, d.small_event_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50282_.Q !== d.small_event_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25542 gold=%b dut=%b", g._50282_.Q, d.small_event_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50283_.Q !== d.small_event_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25543 gold=%b dut=%b", g._50283_.Q, d.small_event_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50284_.Q !== d.small_event_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25544 gold=%b dut=%b", g._50284_.Q, d.small_event_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50285_.Q !== d.small_event_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25545 gold=%b dut=%b", g._50285_.Q, d.small_event_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50286_.Q !== d.small_event_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25546 gold=%b dut=%b", g._50286_.Q, d.small_event_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50287_.Q !== d.small_event_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25547 gold=%b dut=%b", g._50287_.Q, d.small_event_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50288_.Q !== d.small_event_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25548 gold=%b dut=%b", g._50288_.Q, d.small_event_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50289_.Q !== d.small_event_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25549 gold=%b dut=%b", g._50289_.Q, d.small_event_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50290_.Q !== d.small_event_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25550 gold=%b dut=%b", g._50290_.Q, d.small_event_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50291_.Q !== d.small_event_counter[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25551 gold=%b dut=%b", g._50291_.Q, d.small_event_counter[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50292_.Q !== d.small_event_counter[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25552 gold=%b dut=%b", g._50292_.Q, d.small_event_counter[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50293_.Q !== d.small_event_counter[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25553 gold=%b dut=%b", g._50293_.Q, d.small_event_counter[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50294_.Q !== d.small_event_counter[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25554 gold=%b dut=%b", g._50294_.Q, d.small_event_counter[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50295_.Q !== d.small_event_counter[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25555 gold=%b dut=%b", g._50295_.Q, d.small_event_counter[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50296_.Q !== d.small_event_counter[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25556 gold=%b dut=%b", g._50296_.Q, d.small_event_counter[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50297_.Q !== d.small_event_counter[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25557 gold=%b dut=%b", g._50297_.Q, d.small_event_counter[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50298_.Q !== d.small_event_counter[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25558 gold=%b dut=%b", g._50298_.Q, d.small_event_counter[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50299_.Q !== d.small_event_counter[39]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25559 gold=%b dut=%b", g._50299_.Q, d.small_event_counter[39]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50300_.Q !== d.small_event_counter[40]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25560 gold=%b dut=%b", g._50300_.Q, d.small_event_counter[40]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50301_.Q !== d.small_event_counter[41]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25561 gold=%b dut=%b", g._50301_.Q, d.small_event_counter[41]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50302_.Q !== d.control_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25562 gold=%b dut=%b", g._50302_.Q, d.control_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50303_.Q !== d.control_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25563 gold=%b dut=%b", g._50303_.Q, d.control_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50304_.Q !== d.control_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25564 gold=%b dut=%b", g._50304_.Q, d.control_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50305_.Q !== d.control_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25565 gold=%b dut=%b", g._50305_.Q, d.control_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50306_.Q !== d.control_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25566 gold=%b dut=%b", g._50306_.Q, d.control_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50307_.Q !== d.control_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25567 gold=%b dut=%b", g._50307_.Q, d.control_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50308_.Q !== d.control_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25568 gold=%b dut=%b", g._50308_.Q, d.control_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50309_.Q !== d.control_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25569 gold=%b dut=%b", g._50309_.Q, d.control_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50310_.Q !== d.control_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25570 gold=%b dut=%b", g._50310_.Q, d.control_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50311_.Q !== d.control_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25571 gold=%b dut=%b", g._50311_.Q, d.control_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50312_.Q !== d.control_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25572 gold=%b dut=%b", g._50312_.Q, d.control_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50313_.Q !== d.control_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25573 gold=%b dut=%b", g._50313_.Q, d.control_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50314_.Q !== d.control_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25574 gold=%b dut=%b", g._50314_.Q, d.control_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50315_.Q !== d.control_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25575 gold=%b dut=%b", g._50315_.Q, d.control_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50316_.Q !== d.control_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25576 gold=%b dut=%b", g._50316_.Q, d.control_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50317_.Q !== d.control_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25577 gold=%b dut=%b", g._50317_.Q, d.control_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50318_.Q !== d.control_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25578 gold=%b dut=%b", g._50318_.Q, d.control_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50319_.Q !== d.control_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25579 gold=%b dut=%b", g._50319_.Q, d.control_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50320_.Q !== d.control_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25580 gold=%b dut=%b", g._50320_.Q, d.control_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50321_.Q !== d.control_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25581 gold=%b dut=%b", g._50321_.Q, d.control_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50322_.Q !== d.control_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25582 gold=%b dut=%b", g._50322_.Q, d.control_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50323_.Q !== d.control_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25583 gold=%b dut=%b", g._50323_.Q, d.control_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48311_.Q !== d.control_state_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25584 gold=%b dut=%b", g._48311_.Q, d.control_state_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48312_.Q !== d.control_state_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25585 gold=%b dut=%b", g._48312_.Q, d.control_state_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48313_.Q !== d.control_state_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25586 gold=%b dut=%b", g._48313_.Q, d.control_state_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48314_.Q !== d.control_state_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25587 gold=%b dut=%b", g._48314_.Q, d.control_state_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48315_.Q !== d.control_state_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25588 gold=%b dut=%b", g._48315_.Q, d.control_state_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48316_.Q !== d.control_state_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25589 gold=%b dut=%b", g._48316_.Q, d.control_state_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48317_.Q !== d.control_state_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25590 gold=%b dut=%b", g._48317_.Q, d.control_state_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48318_.Q !== d.control_state_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25591 gold=%b dut=%b", g._48318_.Q, d.control_state_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49640_.Q !== d.hold_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25592 gold=%b dut=%b", g._49640_.Q, d.hold_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49641_.Q !== d.hold_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25593 gold=%b dut=%b", g._49641_.Q, d.hold_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49642_.Q !== d.hold_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25594 gold=%b dut=%b", g._49642_.Q, d.hold_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49643_.Q !== d.hold_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25595 gold=%b dut=%b", g._49643_.Q, d.hold_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49644_.Q !== d.hold_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25596 gold=%b dut=%b", g._49644_.Q, d.hold_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49645_.Q !== d.hold_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25597 gold=%b dut=%b", g._49645_.Q, d.hold_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49646_.Q !== d.hold_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25598 gold=%b dut=%b", g._49646_.Q, d.hold_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49647_.Q !== d.hold_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25599 gold=%b dut=%b", g._49647_.Q, d.hold_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49648_.Q !== d.hold_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25600 gold=%b dut=%b", g._49648_.Q, d.hold_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49649_.Q !== d.hold_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25601 gold=%b dut=%b", g._49649_.Q, d.hold_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49650_.Q !== d.hold_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25602 gold=%b dut=%b", g._49650_.Q, d.hold_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49651_.Q !== d.hold_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25603 gold=%b dut=%b", g._49651_.Q, d.hold_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49652_.Q !== d.hold_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25604 gold=%b dut=%b", g._49652_.Q, d.hold_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49653_.Q !== d.hold_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25605 gold=%b dut=%b", g._49653_.Q, d.hold_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49654_.Q !== d.hold_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25606 gold=%b dut=%b", g._49654_.Q, d.hold_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49655_.Q !== d.hold_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25607 gold=%b dut=%b", g._49655_.Q, d.hold_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49656_.Q !== d.hold_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25608 gold=%b dut=%b", g._49656_.Q, d.hold_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49657_.Q !== d.hold_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25609 gold=%b dut=%b", g._49657_.Q, d.hold_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49658_.Q !== d.hold_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25610 gold=%b dut=%b", g._49658_.Q, d.hold_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49659_.Q !== d.hold_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25611 gold=%b dut=%b", g._49659_.Q, d.hold_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49660_.Q !== d.hold_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25612 gold=%b dut=%b", g._49660_.Q, d.hold_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49661_.Q !== d.hold_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25613 gold=%b dut=%b", g._49661_.Q, d.hold_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49662_.Q !== d.hold_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25614 gold=%b dut=%b", g._49662_.Q, d.hold_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49663_.Q !== d.hold_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25615 gold=%b dut=%b", g._49663_.Q, d.hold_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49664_.Q !== d.hold_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25616 gold=%b dut=%b", g._49664_.Q, d.hold_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49665_.Q !== d.hold_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25617 gold=%b dut=%b", g._49665_.Q, d.hold_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49666_.Q !== d.hold_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25618 gold=%b dut=%b", g._49666_.Q, d.hold_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49667_.Q !== d.hold_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25619 gold=%b dut=%b", g._49667_.Q, d.hold_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49668_.Q !== d.hold_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25620 gold=%b dut=%b", g._49668_.Q, d.hold_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49669_.Q !== d.hold_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25621 gold=%b dut=%b", g._49669_.Q, d.hold_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49670_.Q !== d.hold_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25622 gold=%b dut=%b", g._49670_.Q, d.hold_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49671_.Q !== d.hold_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25623 gold=%b dut=%b", g._49671_.Q, d.hold_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49287_.Q !== d.write_data_register_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25624 gold=%b dut=%b", g._49287_.Q, d.write_data_register_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49288_.Q !== d.write_data_register_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25625 gold=%b dut=%b", g._49288_.Q, d.write_data_register_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49289_.Q !== d.write_data_register_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25626 gold=%b dut=%b", g._49289_.Q, d.write_data_register_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49290_.Q !== d.write_data_register_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25627 gold=%b dut=%b", g._49290_.Q, d.write_data_register_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49291_.Q !== d.write_data_register_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25628 gold=%b dut=%b", g._49291_.Q, d.write_data_register_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49292_.Q !== d.write_data_register_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25629 gold=%b dut=%b", g._49292_.Q, d.write_data_register_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49293_.Q !== d.write_data_register_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25630 gold=%b dut=%b", g._49293_.Q, d.write_data_register_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49294_.Q !== d.write_data_register_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25631 gold=%b dut=%b", g._49294_.Q, d.write_data_register_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49298_.Q !== d.write_data_register_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25632 gold=%b dut=%b", g._49298_.Q, d.write_data_register_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49299_.Q !== d.write_data_register_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25633 gold=%b dut=%b", g._49299_.Q, d.write_data_register_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49306_.Q !== d.data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25634 gold=%b dut=%b", g._49306_.Q, d.data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49317_.Q !== d.data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25635 gold=%b dut=%b", g._49317_.Q, d.data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49328_.Q !== d.data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25636 gold=%b dut=%b", g._49328_.Q, d.data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49333_.Q !== d.data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25637 gold=%b dut=%b", g._49333_.Q, d.data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49334_.Q !== d.data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25638 gold=%b dut=%b", g._49334_.Q, d.data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49335_.Q !== d.data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25639 gold=%b dut=%b", g._49335_.Q, d.data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49336_.Q !== d.data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25640 gold=%b dut=%b", g._49336_.Q, d.data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49337_.Q !== d.data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25641 gold=%b dut=%b", g._49337_.Q, d.data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49338_.Q !== d.data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25642 gold=%b dut=%b", g._49338_.Q, d.data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49339_.Q !== d.data_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25643 gold=%b dut=%b", g._49339_.Q, d.data_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49340_.Q !== d.data_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25644 gold=%b dut=%b", g._49340_.Q, d.data_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49341_.Q !== d.data_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25645 gold=%b dut=%b", g._49341_.Q, d.data_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49342_.Q !== d.data_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25646 gold=%b dut=%b", g._49342_.Q, d.data_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49343_.Q !== d.data_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25647 gold=%b dut=%b", g._49343_.Q, d.data_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49344_.Q !== d.data_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25648 gold=%b dut=%b", g._49344_.Q, d.data_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49345_.Q !== d.data_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25649 gold=%b dut=%b", g._49345_.Q, d.data_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49346_.Q !== d.data_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25650 gold=%b dut=%b", g._49346_.Q, d.data_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49347_.Q !== d.data_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25651 gold=%b dut=%b", g._49347_.Q, d.data_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49348_.Q !== d.data_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25652 gold=%b dut=%b", g._49348_.Q, d.data_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49349_.Q !== d.data_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25653 gold=%b dut=%b", g._49349_.Q, d.data_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49350_.Q !== d.data_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25654 gold=%b dut=%b", g._49350_.Q, d.data_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49351_.Q !== d.data_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25655 gold=%b dut=%b", g._49351_.Q, d.data_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49255_.Q !== d.narrow_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25656 gold=%b dut=%b", g._49255_.Q, d.narrow_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49256_.Q !== d.narrow_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25657 gold=%b dut=%b", g._49256_.Q, d.narrow_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49257_.Q !== d.narrow_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25658 gold=%b dut=%b", g._49257_.Q, d.narrow_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49258_.Q !== d.narrow_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25659 gold=%b dut=%b", g._49258_.Q, d.narrow_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49259_.Q !== d.narrow_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25660 gold=%b dut=%b", g._49259_.Q, d.narrow_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49260_.Q !== d.narrow_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25661 gold=%b dut=%b", g._49260_.Q, d.narrow_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49261_.Q !== d.narrow_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25662 gold=%b dut=%b", g._49261_.Q, d.narrow_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49262_.Q !== d.cycle_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25663 gold=%b dut=%b", g._49262_.Q, d.cycle_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49263_.Q !== d.cycle_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25664 gold=%b dut=%b", g._49263_.Q, d.cycle_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49264_.Q !== d.cycle_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25665 gold=%b dut=%b", g._49264_.Q, d.cycle_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49265_.Q !== d.cycle_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25666 gold=%b dut=%b", g._49265_.Q, d.cycle_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49266_.Q !== d.cycle_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25667 gold=%b dut=%b", g._49266_.Q, d.cycle_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49267_.Q !== d.cycle_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25668 gold=%b dut=%b", g._49267_.Q, d.cycle_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49268_.Q !== d.cycle_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25669 gold=%b dut=%b", g._49268_.Q, d.cycle_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49269_.Q !== d.cycle_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25670 gold=%b dut=%b", g._49269_.Q, d.cycle_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49270_.Q !== d.cycle_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25671 gold=%b dut=%b", g._49270_.Q, d.cycle_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49271_.Q !== d.cycle_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25672 gold=%b dut=%b", g._49271_.Q, d.cycle_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49272_.Q !== d.cycle_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25673 gold=%b dut=%b", g._49272_.Q, d.cycle_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49273_.Q !== d.cycle_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25674 gold=%b dut=%b", g._49273_.Q, d.cycle_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49274_.Q !== d.cycle_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25675 gold=%b dut=%b", g._49274_.Q, d.cycle_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49275_.Q !== d.cycle_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25676 gold=%b dut=%b", g._49275_.Q, d.cycle_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49276_.Q !== d.cycle_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25677 gold=%b dut=%b", g._49276_.Q, d.cycle_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49277_.Q !== d.cycle_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25678 gold=%b dut=%b", g._49277_.Q, d.cycle_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49278_.Q !== d.cycle_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25679 gold=%b dut=%b", g._49278_.Q, d.cycle_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49279_.Q !== d.cycle_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25680 gold=%b dut=%b", g._49279_.Q, d.cycle_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49280_.Q !== d.cycle_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25681 gold=%b dut=%b", g._49280_.Q, d.cycle_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49281_.Q !== d.cycle_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25682 gold=%b dut=%b", g._49281_.Q, d.cycle_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49282_.Q !== d.cycle_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25683 gold=%b dut=%b", g._49282_.Q, d.cycle_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49283_.Q !== d.cycle_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25684 gold=%b dut=%b", g._49283_.Q, d.cycle_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49284_.Q !== d.cycle_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25685 gold=%b dut=%b", g._49284_.Q, d.cycle_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49285_.Q !== d.cycle_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25686 gold=%b dut=%b", g._49285_.Q, d.cycle_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49286_.Q !== d.cycle_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25687 gold=%b dut=%b", g._49286_.Q, d.cycle_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49223_.Q !== d.wide_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25688 gold=%b dut=%b", g._49223_.Q, d.wide_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49224_.Q !== d.wide_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25689 gold=%b dut=%b", g._49224_.Q, d.wide_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49225_.Q !== d.wide_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25690 gold=%b dut=%b", g._49225_.Q, d.wide_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49226_.Q !== d.wide_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25691 gold=%b dut=%b", g._49226_.Q, d.wide_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49227_.Q !== d.wide_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25692 gold=%b dut=%b", g._49227_.Q, d.wide_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49228_.Q !== d.wide_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25693 gold=%b dut=%b", g._49228_.Q, d.wide_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49229_.Q !== d.wide_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25694 gold=%b dut=%b", g._49229_.Q, d.wide_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49230_.Q !== d.wide_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25695 gold=%b dut=%b", g._49230_.Q, d.wide_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49231_.Q !== d.wide_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25696 gold=%b dut=%b", g._49231_.Q, d.wide_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49232_.Q !== d.wide_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25697 gold=%b dut=%b", g._49232_.Q, d.wide_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49233_.Q !== d.wide_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25698 gold=%b dut=%b", g._49233_.Q, d.wide_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49234_.Q !== d.wide_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25699 gold=%b dut=%b", g._49234_.Q, d.wide_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49235_.Q !== d.wide_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25700 gold=%b dut=%b", g._49235_.Q, d.wide_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49236_.Q !== d.wide_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25701 gold=%b dut=%b", g._49236_.Q, d.wide_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49237_.Q !== d.wide_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25702 gold=%b dut=%b", g._49237_.Q, d.wide_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49238_.Q !== d.wide_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25703 gold=%b dut=%b", g._49238_.Q, d.wide_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49239_.Q !== d.wide_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25704 gold=%b dut=%b", g._49239_.Q, d.wide_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49240_.Q !== d.wide_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25705 gold=%b dut=%b", g._49240_.Q, d.wide_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49241_.Q !== d.wide_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25706 gold=%b dut=%b", g._49241_.Q, d.wide_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49242_.Q !== d.wide_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25707 gold=%b dut=%b", g._49242_.Q, d.wide_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49243_.Q !== d.wide_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25708 gold=%b dut=%b", g._49243_.Q, d.wide_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49244_.Q !== d.wide_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25709 gold=%b dut=%b", g._49244_.Q, d.wide_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49245_.Q !== d.wide_data_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25710 gold=%b dut=%b", g._49245_.Q, d.wide_data_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49246_.Q !== d.wide_data_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25711 gold=%b dut=%b", g._49246_.Q, d.wide_data_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49247_.Q !== d.wide_data_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25712 gold=%b dut=%b", g._49247_.Q, d.wide_data_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49248_.Q !== d.wide_data_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25713 gold=%b dut=%b", g._49248_.Q, d.wide_data_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49249_.Q !== d.wide_data_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25714 gold=%b dut=%b", g._49249_.Q, d.wide_data_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49250_.Q !== d.wide_data_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25715 gold=%b dut=%b", g._49250_.Q, d.wide_data_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49251_.Q !== d.wide_data_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25716 gold=%b dut=%b", g._49251_.Q, d.wide_data_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49252_.Q !== d.wide_data_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25717 gold=%b dut=%b", g._49252_.Q, d.wide_data_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49253_.Q !== d.wide_data_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25718 gold=%b dut=%b", g._49253_.Q, d.wide_data_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49254_.Q !== d.wide_data_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25719 gold=%b dut=%b", g._49254_.Q, d.wide_data_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49191_.Q !== d.wide_data_reg[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25720 gold=%b dut=%b", g._49191_.Q, d.wide_data_reg[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49192_.Q !== d.wide_data_reg[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25721 gold=%b dut=%b", g._49192_.Q, d.wide_data_reg[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49193_.Q !== d.wide_data_reg[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25722 gold=%b dut=%b", g._49193_.Q, d.wide_data_reg[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49194_.Q !== d.wide_data_reg[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25723 gold=%b dut=%b", g._49194_.Q, d.wide_data_reg[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49195_.Q !== d.wide_data_reg[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25724 gold=%b dut=%b", g._49195_.Q, d.wide_data_reg[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49196_.Q !== d.wide_data_reg[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25725 gold=%b dut=%b", g._49196_.Q, d.wide_data_reg[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49197_.Q !== d.wide_data_reg[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25726 gold=%b dut=%b", g._49197_.Q, d.wide_data_reg[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49198_.Q !== d.wide_data_reg[39]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25727 gold=%b dut=%b", g._49198_.Q, d.wide_data_reg[39]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49199_.Q !== d.wide_data_reg[40]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25728 gold=%b dut=%b", g._49199_.Q, d.wide_data_reg[40]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49200_.Q !== d.wide_data_reg[41]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25729 gold=%b dut=%b", g._49200_.Q, d.wide_data_reg[41]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49201_.Q !== d.wide_data_reg[42]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25730 gold=%b dut=%b", g._49201_.Q, d.wide_data_reg[42]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49202_.Q !== d.wide_data_reg[43]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25731 gold=%b dut=%b", g._49202_.Q, d.wide_data_reg[43]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49203_.Q !== d.wide_data_reg[44]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25732 gold=%b dut=%b", g._49203_.Q, d.wide_data_reg[44]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49204_.Q !== d.wide_data_reg[45]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25733 gold=%b dut=%b", g._49204_.Q, d.wide_data_reg[45]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49205_.Q !== d.wide_data_reg[46]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25734 gold=%b dut=%b", g._49205_.Q, d.wide_data_reg[46]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49206_.Q !== d.wide_data_reg[47]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25735 gold=%b dut=%b", g._49206_.Q, d.wide_data_reg[47]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49207_.Q !== d.wide_data_reg[48]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25736 gold=%b dut=%b", g._49207_.Q, d.wide_data_reg[48]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49208_.Q !== d.wide_data_reg[49]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25737 gold=%b dut=%b", g._49208_.Q, d.wide_data_reg[49]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49209_.Q !== d.wide_data_reg[50]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25738 gold=%b dut=%b", g._49209_.Q, d.wide_data_reg[50]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49210_.Q !== d.wide_data_reg[51]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25739 gold=%b dut=%b", g._49210_.Q, d.wide_data_reg[51]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49211_.Q !== d.wide_data_reg[52]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25740 gold=%b dut=%b", g._49211_.Q, d.wide_data_reg[52]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49212_.Q !== d.wide_data_reg[53]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25741 gold=%b dut=%b", g._49212_.Q, d.wide_data_reg[53]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49213_.Q !== d.wide_data_reg[54]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25742 gold=%b dut=%b", g._49213_.Q, d.wide_data_reg[54]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49214_.Q !== d.wide_data_reg[55]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25743 gold=%b dut=%b", g._49214_.Q, d.wide_data_reg[55]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49215_.Q !== d.wide_data_reg[56]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25744 gold=%b dut=%b", g._49215_.Q, d.wide_data_reg[56]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49216_.Q !== d.wide_data_reg[57]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25745 gold=%b dut=%b", g._49216_.Q, d.wide_data_reg[57]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49217_.Q !== d.wide_data_reg[58]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25746 gold=%b dut=%b", g._49217_.Q, d.wide_data_reg[58]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49218_.Q !== d.wide_data_reg[59]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25747 gold=%b dut=%b", g._49218_.Q, d.wide_data_reg[59]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49219_.Q !== d.wide_data_reg[60]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25748 gold=%b dut=%b", g._49219_.Q, d.wide_data_reg[60]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49220_.Q !== d.wide_data_reg[61]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25749 gold=%b dut=%b", g._49220_.Q, d.wide_data_reg[61]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49221_.Q !== d.wide_data_reg[62]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25750 gold=%b dut=%b", g._49221_.Q, d.wide_data_reg[62]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49222_.Q !== d.control_state_2) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25751 gold=%b dut=%b", g._49222_.Q, d.control_state_2);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49159_.Q !== d.data_word_lo[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25752 gold=%b dut=%b", g._49159_.Q, d.data_word_lo[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49160_.Q !== d.data_word_lo[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25753 gold=%b dut=%b", g._49160_.Q, d.data_word_lo[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49161_.Q !== d.data_word_lo[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25754 gold=%b dut=%b", g._49161_.Q, d.data_word_lo[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49162_.Q !== d.data_word_lo[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25755 gold=%b dut=%b", g._49162_.Q, d.data_word_lo[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49163_.Q !== d.data_word_lo[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25756 gold=%b dut=%b", g._49163_.Q, d.data_word_lo[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49164_.Q !== d.data_word_lo[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25757 gold=%b dut=%b", g._49164_.Q, d.data_word_lo[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49165_.Q !== d.data_word_lo[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25758 gold=%b dut=%b", g._49165_.Q, d.data_word_lo[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49166_.Q !== d.data_word_lo[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25759 gold=%b dut=%b", g._49166_.Q, d.data_word_lo[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49167_.Q !== d.data_word_lo[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25760 gold=%b dut=%b", g._49167_.Q, d.data_word_lo[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49168_.Q !== d.data_word_lo[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25761 gold=%b dut=%b", g._49168_.Q, d.data_word_lo[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49169_.Q !== d.data_word_lo[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25762 gold=%b dut=%b", g._49169_.Q, d.data_word_lo[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49170_.Q !== d.data_word_lo[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25763 gold=%b dut=%b", g._49170_.Q, d.data_word_lo[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49171_.Q !== d.data_word_lo[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25764 gold=%b dut=%b", g._49171_.Q, d.data_word_lo[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49172_.Q !== d.data_word_lo[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25765 gold=%b dut=%b", g._49172_.Q, d.data_word_lo[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49173_.Q !== d.data_word_lo[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25766 gold=%b dut=%b", g._49173_.Q, d.data_word_lo[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49174_.Q !== d.data_word_lo[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25767 gold=%b dut=%b", g._49174_.Q, d.data_word_lo[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49175_.Q !== d.data_word_lo[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25768 gold=%b dut=%b", g._49175_.Q, d.data_word_lo[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49176_.Q !== d.data_word_lo[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25769 gold=%b dut=%b", g._49176_.Q, d.data_word_lo[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49177_.Q !== d.data_word_lo[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25770 gold=%b dut=%b", g._49177_.Q, d.data_word_lo[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49178_.Q !== d.data_word_lo[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25771 gold=%b dut=%b", g._49178_.Q, d.data_word_lo[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49179_.Q !== d.data_word_lo[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25772 gold=%b dut=%b", g._49179_.Q, d.data_word_lo[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49180_.Q !== d.data_word_lo[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25773 gold=%b dut=%b", g._49180_.Q, d.data_word_lo[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49181_.Q !== d.data_word_lo[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25774 gold=%b dut=%b", g._49181_.Q, d.data_word_lo[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49182_.Q !== d.wide_data_reg[63]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25775 gold=%b dut=%b", g._49182_.Q, d.wide_data_reg[63]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49183_.Q !== d.wide_data_reg[64]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25776 gold=%b dut=%b", g._49183_.Q, d.wide_data_reg[64]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49184_.Q !== d.wide_data_reg[65]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25777 gold=%b dut=%b", g._49184_.Q, d.wide_data_reg[65]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49185_.Q !== d.wide_data_reg[66]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25778 gold=%b dut=%b", g._49185_.Q, d.wide_data_reg[66]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49186_.Q !== d.wide_data_reg[67]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25779 gold=%b dut=%b", g._49186_.Q, d.wide_data_reg[67]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49187_.Q !== d.wide_data_reg[68]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25780 gold=%b dut=%b", g._49187_.Q, d.wide_data_reg[68]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49188_.Q !== d.wide_data_reg[69]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25781 gold=%b dut=%b", g._49188_.Q, d.wide_data_reg[69]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49189_.Q !== d.wide_data_reg[70]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25782 gold=%b dut=%b", g._49189_.Q, d.wide_data_reg[70]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49190_.Q !== d.wide_data_reg[71]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25783 gold=%b dut=%b", g._49190_.Q, d.wide_data_reg[71]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49127_.Q !== d.datapath_reg_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25784 gold=%b dut=%b", g._49127_.Q, d.datapath_reg_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49128_.Q !== d.datapath_reg_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25785 gold=%b dut=%b", g._49128_.Q, d.datapath_reg_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49129_.Q !== d.datapath_reg_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25786 gold=%b dut=%b", g._49129_.Q, d.datapath_reg_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49130_.Q !== d.datapath_reg_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25787 gold=%b dut=%b", g._49130_.Q, d.datapath_reg_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49131_.Q !== d.datapath_reg_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25788 gold=%b dut=%b", g._49131_.Q, d.datapath_reg_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49132_.Q !== d.datapath_reg_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25789 gold=%b dut=%b", g._49132_.Q, d.datapath_reg_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49133_.Q !== d.datapath_reg_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25790 gold=%b dut=%b", g._49133_.Q, d.datapath_reg_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49134_.Q !== d.datapath_reg_0[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25791 gold=%b dut=%b", g._49134_.Q, d.datapath_reg_0[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49135_.Q !== d.datapath_reg_0[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25792 gold=%b dut=%b", g._49135_.Q, d.datapath_reg_0[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49136_.Q !== d.datapath_reg_0[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25793 gold=%b dut=%b", g._49136_.Q, d.datapath_reg_0[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49137_.Q !== d.datapath_reg_0[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25794 gold=%b dut=%b", g._49137_.Q, d.datapath_reg_0[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49138_.Q !== d.datapath_reg_0[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25795 gold=%b dut=%b", g._49138_.Q, d.datapath_reg_0[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49139_.Q !== d.datapath_reg_0[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25796 gold=%b dut=%b", g._49139_.Q, d.datapath_reg_0[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49140_.Q !== d.datapath_reg_0[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25797 gold=%b dut=%b", g._49140_.Q, d.datapath_reg_0[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49141_.Q !== d.datapath_reg_0[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25798 gold=%b dut=%b", g._49141_.Q, d.datapath_reg_0[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49142_.Q !== d.datapath_reg_0[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25799 gold=%b dut=%b", g._49142_.Q, d.datapath_reg_0[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49143_.Q !== d.datapath_reg_0[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25800 gold=%b dut=%b", g._49143_.Q, d.datapath_reg_0[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49144_.Q !== d.datapath_reg_0[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25801 gold=%b dut=%b", g._49144_.Q, d.datapath_reg_0[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49145_.Q !== d.datapath_reg_0[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25802 gold=%b dut=%b", g._49145_.Q, d.datapath_reg_0[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49146_.Q !== d.datapath_reg_0[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25803 gold=%b dut=%b", g._49146_.Q, d.datapath_reg_0[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49147_.Q !== d.datapath_reg_0[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25804 gold=%b dut=%b", g._49147_.Q, d.datapath_reg_0[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49148_.Q !== d.datapath_reg_0[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25805 gold=%b dut=%b", g._49148_.Q, d.datapath_reg_0[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49149_.Q !== d.datapath_reg_0[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25806 gold=%b dut=%b", g._49149_.Q, d.datapath_reg_0[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49150_.Q !== d.datapath_reg_0[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25807 gold=%b dut=%b", g._49150_.Q, d.datapath_reg_0[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49151_.Q !== d.datapath_reg_0[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25808 gold=%b dut=%b", g._49151_.Q, d.datapath_reg_0[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49152_.Q !== d.datapath_reg_0[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25809 gold=%b dut=%b", g._49152_.Q, d.datapath_reg_0[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49153_.Q !== d.datapath_reg_0[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25810 gold=%b dut=%b", g._49153_.Q, d.datapath_reg_0[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49154_.Q !== d.datapath_reg_0[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25811 gold=%b dut=%b", g._49154_.Q, d.datapath_reg_0[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49155_.Q !== d.datapath_reg_0[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25812 gold=%b dut=%b", g._49155_.Q, d.datapath_reg_0[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49156_.Q !== d.datapath_reg_0[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25813 gold=%b dut=%b", g._49156_.Q, d.datapath_reg_0[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49157_.Q !== d.datapath_reg_0[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25814 gold=%b dut=%b", g._49157_.Q, d.datapath_reg_0[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49158_.Q !== d.datapath_reg_0[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25815 gold=%b dut=%b", g._49158_.Q, d.datapath_reg_0[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49095_.Q !== d.narrow_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25816 gold=%b dut=%b", g._49095_.Q, d.narrow_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49096_.Q !== d.narrow_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25817 gold=%b dut=%b", g._49096_.Q, d.narrow_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49097_.Q !== d.narrow_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25818 gold=%b dut=%b", g._49097_.Q, d.narrow_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49098_.Q !== d.narrow_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25819 gold=%b dut=%b", g._49098_.Q, d.narrow_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49099_.Q !== d.narrow_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25820 gold=%b dut=%b", g._49099_.Q, d.narrow_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49100_.Q !== d.narrow_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25821 gold=%b dut=%b", g._49100_.Q, d.narrow_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49101_.Q !== d.narrow_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25822 gold=%b dut=%b", g._49101_.Q, d.narrow_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49102_.Q !== d.datapath_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25823 gold=%b dut=%b", g._49102_.Q, d.datapath_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49103_.Q !== d.datapath_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25824 gold=%b dut=%b", g._49103_.Q, d.datapath_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49104_.Q !== d.datapath_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25825 gold=%b dut=%b", g._49104_.Q, d.datapath_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49105_.Q !== d.datapath_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25826 gold=%b dut=%b", g._49105_.Q, d.datapath_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49106_.Q !== d.datapath_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25827 gold=%b dut=%b", g._49106_.Q, d.datapath_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49107_.Q !== d.datapath_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25828 gold=%b dut=%b", g._49107_.Q, d.datapath_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49108_.Q !== d.datapath_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25829 gold=%b dut=%b", g._49108_.Q, d.datapath_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49109_.Q !== d.datapath_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25830 gold=%b dut=%b", g._49109_.Q, d.datapath_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49110_.Q !== d.datapath_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25831 gold=%b dut=%b", g._49110_.Q, d.datapath_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49111_.Q !== d.datapath_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25832 gold=%b dut=%b", g._49111_.Q, d.datapath_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49112_.Q !== d.datapath_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25833 gold=%b dut=%b", g._49112_.Q, d.datapath_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49113_.Q !== d.datapath_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25834 gold=%b dut=%b", g._49113_.Q, d.datapath_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49114_.Q !== d.datapath_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25835 gold=%b dut=%b", g._49114_.Q, d.datapath_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49115_.Q !== d.datapath_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25836 gold=%b dut=%b", g._49115_.Q, d.datapath_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49116_.Q !== d.datapath_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25837 gold=%b dut=%b", g._49116_.Q, d.datapath_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49117_.Q !== d.datapath_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25838 gold=%b dut=%b", g._49117_.Q, d.datapath_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49118_.Q !== d.datapath_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25839 gold=%b dut=%b", g._49118_.Q, d.datapath_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49119_.Q !== d.datapath_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25840 gold=%b dut=%b", g._49119_.Q, d.datapath_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49120_.Q !== d.datapath_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25841 gold=%b dut=%b", g._49120_.Q, d.datapath_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49121_.Q !== d.datapath_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25842 gold=%b dut=%b", g._49121_.Q, d.datapath_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49122_.Q !== d.datapath_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25843 gold=%b dut=%b", g._49122_.Q, d.datapath_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49123_.Q !== d.datapath_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25844 gold=%b dut=%b", g._49123_.Q, d.datapath_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49124_.Q !== d.datapath_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25845 gold=%b dut=%b", g._49124_.Q, d.datapath_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49125_.Q !== d.datapath_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25846 gold=%b dut=%b", g._49125_.Q, d.datapath_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49126_.Q !== d.datapath_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25847 gold=%b dut=%b", g._49126_.Q, d.datapath_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49063_.Q !== d.wide_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25848 gold=%b dut=%b", g._49063_.Q, d.wide_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49064_.Q !== d.wide_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25849 gold=%b dut=%b", g._49064_.Q, d.wide_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49065_.Q !== d.wide_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25850 gold=%b dut=%b", g._49065_.Q, d.wide_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49066_.Q !== d.wide_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25851 gold=%b dut=%b", g._49066_.Q, d.wide_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49067_.Q !== d.wide_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25852 gold=%b dut=%b", g._49067_.Q, d.wide_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49068_.Q !== d.wide_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25853 gold=%b dut=%b", g._49068_.Q, d.wide_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49069_.Q !== d.wide_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25854 gold=%b dut=%b", g._49069_.Q, d.wide_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49070_.Q !== d.wide_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25855 gold=%b dut=%b", g._49070_.Q, d.wide_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49071_.Q !== d.wide_data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25856 gold=%b dut=%b", g._49071_.Q, d.wide_data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49072_.Q !== d.wide_data_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25857 gold=%b dut=%b", g._49072_.Q, d.wide_data_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49073_.Q !== d.wide_data_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25858 gold=%b dut=%b", g._49073_.Q, d.wide_data_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49074_.Q !== d.wide_data_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25859 gold=%b dut=%b", g._49074_.Q, d.wide_data_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49075_.Q !== d.wide_data_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25860 gold=%b dut=%b", g._49075_.Q, d.wide_data_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49076_.Q !== d.wide_data_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25861 gold=%b dut=%b", g._49076_.Q, d.wide_data_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49077_.Q !== d.wide_data_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25862 gold=%b dut=%b", g._49077_.Q, d.wide_data_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49078_.Q !== d.wide_data_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25863 gold=%b dut=%b", g._49078_.Q, d.wide_data_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49079_.Q !== d.wide_data_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25864 gold=%b dut=%b", g._49079_.Q, d.wide_data_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49080_.Q !== d.wide_data_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25865 gold=%b dut=%b", g._49080_.Q, d.wide_data_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49081_.Q !== d.wide_data_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25866 gold=%b dut=%b", g._49081_.Q, d.wide_data_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49082_.Q !== d.wide_data_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25867 gold=%b dut=%b", g._49082_.Q, d.wide_data_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49083_.Q !== d.wide_data_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25868 gold=%b dut=%b", g._49083_.Q, d.wide_data_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49084_.Q !== d.wide_data_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25869 gold=%b dut=%b", g._49084_.Q, d.wide_data_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49085_.Q !== d.wide_data_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25870 gold=%b dut=%b", g._49085_.Q, d.wide_data_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49086_.Q !== d.wide_data_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25871 gold=%b dut=%b", g._49086_.Q, d.wide_data_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49087_.Q !== d.wide_data_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25872 gold=%b dut=%b", g._49087_.Q, d.wide_data_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49088_.Q !== d.wide_data_reg_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25873 gold=%b dut=%b", g._49088_.Q, d.wide_data_reg_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49089_.Q !== d.wide_data_reg_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25874 gold=%b dut=%b", g._49089_.Q, d.wide_data_reg_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49090_.Q !== d.wide_data_reg_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25875 gold=%b dut=%b", g._49090_.Q, d.wide_data_reg_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49091_.Q !== d.wide_data_reg_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25876 gold=%b dut=%b", g._49091_.Q, d.wide_data_reg_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49092_.Q !== d.wide_data_reg_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25877 gold=%b dut=%b", g._49092_.Q, d.wide_data_reg_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49093_.Q !== d.wide_data_reg_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25878 gold=%b dut=%b", g._49093_.Q, d.wide_data_reg_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49094_.Q !== d.narrow_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25879 gold=%b dut=%b", g._49094_.Q, d.narrow_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49031_.Q !== d.data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25880 gold=%b dut=%b", g._49031_.Q, d.data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49032_.Q !== d.data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25881 gold=%b dut=%b", g._49032_.Q, d.data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49033_.Q !== d.data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25882 gold=%b dut=%b", g._49033_.Q, d.data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49034_.Q !== d.data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25883 gold=%b dut=%b", g._49034_.Q, d.data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49035_.Q !== d.data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25884 gold=%b dut=%b", g._49035_.Q, d.data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49036_.Q !== d.data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25885 gold=%b dut=%b", g._49036_.Q, d.data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49037_.Q !== d.data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25886 gold=%b dut=%b", g._49037_.Q, d.data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49038_.Q !== d.data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25887 gold=%b dut=%b", g._49038_.Q, d.data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49039_.Q !== d.data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25888 gold=%b dut=%b", g._49039_.Q, d.data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49040_.Q !== d.data_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25889 gold=%b dut=%b", g._49040_.Q, d.data_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49041_.Q !== d.data_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25890 gold=%b dut=%b", g._49041_.Q, d.data_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49042_.Q !== d.data_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25891 gold=%b dut=%b", g._49042_.Q, d.data_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49043_.Q !== d.data_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25892 gold=%b dut=%b", g._49043_.Q, d.data_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49044_.Q !== d.data_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25893 gold=%b dut=%b", g._49044_.Q, d.data_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49045_.Q !== d.data_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25894 gold=%b dut=%b", g._49045_.Q, d.data_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49046_.Q !== d.data_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25895 gold=%b dut=%b", g._49046_.Q, d.data_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49047_.Q !== d.data_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25896 gold=%b dut=%b", g._49047_.Q, d.data_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49048_.Q !== d.data_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25897 gold=%b dut=%b", g._49048_.Q, d.data_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49049_.Q !== d.data_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25898 gold=%b dut=%b", g._49049_.Q, d.data_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49050_.Q !== d.data_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25899 gold=%b dut=%b", g._49050_.Q, d.data_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49051_.Q !== d.data_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25900 gold=%b dut=%b", g._49051_.Q, d.data_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49052_.Q !== d.data_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25901 gold=%b dut=%b", g._49052_.Q, d.data_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49053_.Q !== d.data_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25902 gold=%b dut=%b", g._49053_.Q, d.data_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49054_.Q !== d.data_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25903 gold=%b dut=%b", g._49054_.Q, d.data_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49055_.Q !== d.data_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25904 gold=%b dut=%b", g._49055_.Q, d.data_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49056_.Q !== d.data_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25905 gold=%b dut=%b", g._49056_.Q, d.data_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49057_.Q !== d.data_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25906 gold=%b dut=%b", g._49057_.Q, d.data_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49058_.Q !== d.data_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25907 gold=%b dut=%b", g._49058_.Q, d.data_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49059_.Q !== d.data_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25908 gold=%b dut=%b", g._49059_.Q, d.data_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49060_.Q !== d.data_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25909 gold=%b dut=%b", g._49060_.Q, d.data_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49061_.Q !== d.data_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25910 gold=%b dut=%b", g._49061_.Q, d.data_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49062_.Q !== d.wide_data_reg_1[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25911 gold=%b dut=%b", g._49062_.Q, d.wide_data_reg_1[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48999_.Q !== d.address_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25912 gold=%b dut=%b", g._48999_.Q, d.address_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49000_.Q !== d.address_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25913 gold=%b dut=%b", g._49000_.Q, d.address_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49001_.Q !== d.address_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25914 gold=%b dut=%b", g._49001_.Q, d.address_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49002_.Q !== d.address_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25915 gold=%b dut=%b", g._49002_.Q, d.address_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49003_.Q !== d.address_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25916 gold=%b dut=%b", g._49003_.Q, d.address_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49004_.Q !== d.address_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25917 gold=%b dut=%b", g._49004_.Q, d.address_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49005_.Q !== d.address_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25918 gold=%b dut=%b", g._49005_.Q, d.address_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49006_.Q !== d.address_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25919 gold=%b dut=%b", g._49006_.Q, d.address_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49007_.Q !== d.address_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25920 gold=%b dut=%b", g._49007_.Q, d.address_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49008_.Q !== d.address_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25921 gold=%b dut=%b", g._49008_.Q, d.address_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49009_.Q !== d.address_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25922 gold=%b dut=%b", g._49009_.Q, d.address_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49010_.Q !== d.address_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25923 gold=%b dut=%b", g._49010_.Q, d.address_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49011_.Q !== d.address_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25924 gold=%b dut=%b", g._49011_.Q, d.address_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49012_.Q !== d.address_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25925 gold=%b dut=%b", g._49012_.Q, d.address_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49013_.Q !== d.address_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25926 gold=%b dut=%b", g._49013_.Q, d.address_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49014_.Q !== d.address_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25927 gold=%b dut=%b", g._49014_.Q, d.address_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49015_.Q !== d.address_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25928 gold=%b dut=%b", g._49015_.Q, d.address_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49016_.Q !== d.address_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25929 gold=%b dut=%b", g._49016_.Q, d.address_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49017_.Q !== d.address_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25930 gold=%b dut=%b", g._49017_.Q, d.address_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49018_.Q !== d.address_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25931 gold=%b dut=%b", g._49018_.Q, d.address_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49019_.Q !== d.address_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25932 gold=%b dut=%b", g._49019_.Q, d.address_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49020_.Q !== d.address_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25933 gold=%b dut=%b", g._49020_.Q, d.address_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49021_.Q !== d.address_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25934 gold=%b dut=%b", g._49021_.Q, d.address_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49022_.Q !== d.address_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25935 gold=%b dut=%b", g._49022_.Q, d.address_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49023_.Q !== d.address_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25936 gold=%b dut=%b", g._49023_.Q, d.address_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49024_.Q !== d.address_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25937 gold=%b dut=%b", g._49024_.Q, d.address_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49025_.Q !== d.address_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25938 gold=%b dut=%b", g._49025_.Q, d.address_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49026_.Q !== d.address_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25939 gold=%b dut=%b", g._49026_.Q, d.address_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49027_.Q !== d.address_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25940 gold=%b dut=%b", g._49027_.Q, d.address_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49028_.Q !== d.address_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25941 gold=%b dut=%b", g._49028_.Q, d.address_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49029_.Q !== d.address_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25942 gold=%b dut=%b", g._49029_.Q, d.address_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49030_.Q !== d.control_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25943 gold=%b dut=%b", g._49030_.Q, d.control_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49608_.Q !== d.data_register_b[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25944 gold=%b dut=%b", g._49608_.Q, d.data_register_b[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49609_.Q !== d.data_register_b[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25945 gold=%b dut=%b", g._49609_.Q, d.data_register_b[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49610_.Q !== d.data_register_b[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25946 gold=%b dut=%b", g._49610_.Q, d.data_register_b[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49611_.Q !== d.data_register_b[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25947 gold=%b dut=%b", g._49611_.Q, d.data_register_b[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49612_.Q !== d.data_register_b[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25948 gold=%b dut=%b", g._49612_.Q, d.data_register_b[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49613_.Q !== d.data_register_b[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25949 gold=%b dut=%b", g._49613_.Q, d.data_register_b[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49614_.Q !== d.data_register_b[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25950 gold=%b dut=%b", g._49614_.Q, d.data_register_b[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49615_.Q !== d.data_register_b[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25951 gold=%b dut=%b", g._49615_.Q, d.data_register_b[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49616_.Q !== d.data_register_b[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25952 gold=%b dut=%b", g._49616_.Q, d.data_register_b[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49617_.Q !== d.data_register_b[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25953 gold=%b dut=%b", g._49617_.Q, d.data_register_b[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49618_.Q !== d.data_register_b[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25954 gold=%b dut=%b", g._49618_.Q, d.data_register_b[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49619_.Q !== d.data_register_b[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25955 gold=%b dut=%b", g._49619_.Q, d.data_register_b[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49620_.Q !== d.data_register_b[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25956 gold=%b dut=%b", g._49620_.Q, d.data_register_b[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49621_.Q !== d.data_register_b[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25957 gold=%b dut=%b", g._49621_.Q, d.data_register_b[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49622_.Q !== d.data_register_b[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25958 gold=%b dut=%b", g._49622_.Q, d.data_register_b[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49623_.Q !== d.data_register_b[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25959 gold=%b dut=%b", g._49623_.Q, d.data_register_b[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49624_.Q !== d.data_register_b[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25960 gold=%b dut=%b", g._49624_.Q, d.data_register_b[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49625_.Q !== d.data_register_b[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25961 gold=%b dut=%b", g._49625_.Q, d.data_register_b[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49626_.Q !== d.data_register_b[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25962 gold=%b dut=%b", g._49626_.Q, d.data_register_b[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49627_.Q !== d.data_register_b[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25963 gold=%b dut=%b", g._49627_.Q, d.data_register_b[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49628_.Q !== d.data_register_b[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25964 gold=%b dut=%b", g._49628_.Q, d.data_register_b[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49629_.Q !== d.data_register_b[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25965 gold=%b dut=%b", g._49629_.Q, d.data_register_b[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49630_.Q !== d.data_register_b[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25966 gold=%b dut=%b", g._49630_.Q, d.data_register_b[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49631_.Q !== d.data_register_b[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25967 gold=%b dut=%b", g._49631_.Q, d.data_register_b[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49632_.Q !== d.data_register_b[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25968 gold=%b dut=%b", g._49632_.Q, d.data_register_b[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49633_.Q !== d.data_register_b[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25969 gold=%b dut=%b", g._49633_.Q, d.data_register_b[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49634_.Q !== d.data_register_b[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25970 gold=%b dut=%b", g._49634_.Q, d.data_register_b[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49635_.Q !== d.data_register_b[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25971 gold=%b dut=%b", g._49635_.Q, d.data_register_b[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49636_.Q !== d.data_register_b[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25972 gold=%b dut=%b", g._49636_.Q, d.data_register_b[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49637_.Q !== d.data_register_b[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25973 gold=%b dut=%b", g._49637_.Q, d.data_register_b[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49638_.Q !== d.data_register_b[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25974 gold=%b dut=%b", g._49638_.Q, d.data_register_b[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49639_.Q !== d.data_register_b[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25975 gold=%b dut=%b", g._49639_.Q, d.data_register_b[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48967_.Q !== d.data_reg_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25976 gold=%b dut=%b", g._48967_.Q, d.data_reg_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48968_.Q !== d.data_reg_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25977 gold=%b dut=%b", g._48968_.Q, d.data_reg_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48969_.Q !== d.data_reg_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25978 gold=%b dut=%b", g._48969_.Q, d.data_reg_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48970_.Q !== d.data_reg_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25979 gold=%b dut=%b", g._48970_.Q, d.data_reg_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48971_.Q !== d.data_reg_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25980 gold=%b dut=%b", g._48971_.Q, d.data_reg_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48972_.Q !== d.data_reg_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25981 gold=%b dut=%b", g._48972_.Q, d.data_reg_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48973_.Q !== d.data_reg_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25982 gold=%b dut=%b", g._48973_.Q, d.data_reg_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48974_.Q !== d.data_reg_0[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25983 gold=%b dut=%b", g._48974_.Q, d.data_reg_0[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48975_.Q !== d.data_reg_0[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25984 gold=%b dut=%b", g._48975_.Q, d.data_reg_0[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48976_.Q !== d.data_reg_0[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25985 gold=%b dut=%b", g._48976_.Q, d.data_reg_0[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48977_.Q !== d.data_reg_0[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25986 gold=%b dut=%b", g._48977_.Q, d.data_reg_0[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48978_.Q !== d.data_reg_0[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25987 gold=%b dut=%b", g._48978_.Q, d.data_reg_0[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48979_.Q !== d.data_reg_0[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25988 gold=%b dut=%b", g._48979_.Q, d.data_reg_0[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48980_.Q !== d.data_reg_0[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25989 gold=%b dut=%b", g._48980_.Q, d.data_reg_0[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48981_.Q !== d.data_reg_0[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25990 gold=%b dut=%b", g._48981_.Q, d.data_reg_0[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48982_.Q !== d.data_reg_0[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25991 gold=%b dut=%b", g._48982_.Q, d.data_reg_0[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48983_.Q !== d.data_reg_0[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25992 gold=%b dut=%b", g._48983_.Q, d.data_reg_0[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48984_.Q !== d.data_reg_0[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25993 gold=%b dut=%b", g._48984_.Q, d.data_reg_0[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48985_.Q !== d.data_reg_0[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25994 gold=%b dut=%b", g._48985_.Q, d.data_reg_0[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48986_.Q !== d.data_reg_0[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25995 gold=%b dut=%b", g._48986_.Q, d.data_reg_0[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48987_.Q !== d.data_reg_0[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25996 gold=%b dut=%b", g._48987_.Q, d.data_reg_0[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48988_.Q !== d.data_reg_0[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25997 gold=%b dut=%b", g._48988_.Q, d.data_reg_0[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48989_.Q !== d.data_reg_0[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25998 gold=%b dut=%b", g._48989_.Q, d.data_reg_0[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48990_.Q !== d.data_reg_0[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=25999 gold=%b dut=%b", g._48990_.Q, d.data_reg_0[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48991_.Q !== d.data_reg_0[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26000 gold=%b dut=%b", g._48991_.Q, d.data_reg_0[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48992_.Q !== d.data_reg_0[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26001 gold=%b dut=%b", g._48992_.Q, d.data_reg_0[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48993_.Q !== d.data_reg_0[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26002 gold=%b dut=%b", g._48993_.Q, d.data_reg_0[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48994_.Q !== d.data_reg_0[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26003 gold=%b dut=%b", g._48994_.Q, d.data_reg_0[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48995_.Q !== d.data_reg_0[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26004 gold=%b dut=%b", g._48995_.Q, d.data_reg_0[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48996_.Q !== d.data_reg_0[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26005 gold=%b dut=%b", g._48996_.Q, d.data_reg_0[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48997_.Q !== d.data_reg_0[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26006 gold=%b dut=%b", g._48997_.Q, d.data_reg_0[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48998_.Q !== d.data_reg_0[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26007 gold=%b dut=%b", g._48998_.Q, d.data_reg_0[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48935_.Q !== d.narrow_data_reg_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26008 gold=%b dut=%b", g._48935_.Q, d.narrow_data_reg_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48936_.Q !== d.narrow_data_reg_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26009 gold=%b dut=%b", g._48936_.Q, d.narrow_data_reg_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48937_.Q !== d.narrow_data_reg_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26010 gold=%b dut=%b", g._48937_.Q, d.narrow_data_reg_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48938_.Q !== d.narrow_data_reg_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26011 gold=%b dut=%b", g._48938_.Q, d.narrow_data_reg_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48939_.Q !== d.narrow_data_reg_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26012 gold=%b dut=%b", g._48939_.Q, d.narrow_data_reg_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48940_.Q !== d.narrow_data_reg_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26013 gold=%b dut=%b", g._48940_.Q, d.narrow_data_reg_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48941_.Q !== d.narrow_data_reg_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26014 gold=%b dut=%b", g._48941_.Q, d.narrow_data_reg_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48942_.Q !== d.narrow_data_reg_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26015 gold=%b dut=%b", g._48942_.Q, d.narrow_data_reg_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48943_.Q !== d.narrow_data_reg_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26016 gold=%b dut=%b", g._48943_.Q, d.narrow_data_reg_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48944_.Q !== d.narrow_data_reg_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26017 gold=%b dut=%b", g._48944_.Q, d.narrow_data_reg_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48945_.Q !== d.narrow_data_reg_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26018 gold=%b dut=%b", g._48945_.Q, d.narrow_data_reg_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48946_.Q !== d.narrow_data_reg_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26019 gold=%b dut=%b", g._48946_.Q, d.narrow_data_reg_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48947_.Q !== d.narrow_data_reg_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26020 gold=%b dut=%b", g._48947_.Q, d.narrow_data_reg_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48948_.Q !== d.narrow_data_reg_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26021 gold=%b dut=%b", g._48948_.Q, d.narrow_data_reg_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48949_.Q !== d.narrow_data_reg_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26022 gold=%b dut=%b", g._48949_.Q, d.narrow_data_reg_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48950_.Q !== d.narrow_data_reg_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26023 gold=%b dut=%b", g._48950_.Q, d.narrow_data_reg_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48951_.Q !== d.narrow_data_reg_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26024 gold=%b dut=%b", g._48951_.Q, d.narrow_data_reg_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48952_.Q !== d.narrow_data_reg_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26025 gold=%b dut=%b", g._48952_.Q, d.narrow_data_reg_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48953_.Q !== d.narrow_data_reg_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26026 gold=%b dut=%b", g._48953_.Q, d.narrow_data_reg_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48954_.Q !== d.narrow_data_reg_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26027 gold=%b dut=%b", g._48954_.Q, d.narrow_data_reg_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48955_.Q !== d.narrow_data_reg_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26028 gold=%b dut=%b", g._48955_.Q, d.narrow_data_reg_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48956_.Q !== d.narrow_data_reg_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26029 gold=%b dut=%b", g._48956_.Q, d.narrow_data_reg_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48957_.Q !== d.narrow_data_reg_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26030 gold=%b dut=%b", g._48957_.Q, d.narrow_data_reg_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48958_.Q !== d.narrow_data_reg_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26031 gold=%b dut=%b", g._48958_.Q, d.narrow_data_reg_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48959_.Q !== d.narrow_data_reg_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26032 gold=%b dut=%b", g._48959_.Q, d.narrow_data_reg_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48960_.Q !== d.narrow_data_reg_2[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26033 gold=%b dut=%b", g._48960_.Q, d.narrow_data_reg_2[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48961_.Q !== d.narrow_data_reg_2[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26034 gold=%b dut=%b", g._48961_.Q, d.narrow_data_reg_2[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48962_.Q !== d.narrow_data_reg_2[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26035 gold=%b dut=%b", g._48962_.Q, d.narrow_data_reg_2[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48963_.Q !== d.narrow_data_reg_2[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26036 gold=%b dut=%b", g._48963_.Q, d.narrow_data_reg_2[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48964_.Q !== d.narrow_data_reg_2[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26037 gold=%b dut=%b", g._48964_.Q, d.narrow_data_reg_2[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48965_.Q !== d.narrow_data_reg_2[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26038 gold=%b dut=%b", g._48965_.Q, d.narrow_data_reg_2[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48966_.Q !== d.narrow_data_reg_2[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26039 gold=%b dut=%b", g._48966_.Q, d.narrow_data_reg_2[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48903_.Q !== d.wide_data_reg_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26040 gold=%b dut=%b", g._48903_.Q, d.wide_data_reg_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48904_.Q !== d.wide_data_reg_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26041 gold=%b dut=%b", g._48904_.Q, d.wide_data_reg_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48905_.Q !== d.wide_data_reg_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26042 gold=%b dut=%b", g._48905_.Q, d.wide_data_reg_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48906_.Q !== d.wide_data_reg_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26043 gold=%b dut=%b", g._48906_.Q, d.wide_data_reg_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48907_.Q !== d.wide_data_reg_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26044 gold=%b dut=%b", g._48907_.Q, d.wide_data_reg_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48908_.Q !== d.wide_data_reg_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26045 gold=%b dut=%b", g._48908_.Q, d.wide_data_reg_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48909_.Q !== d.wide_data_reg_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26046 gold=%b dut=%b", g._48909_.Q, d.wide_data_reg_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48910_.Q !== d.wide_data_reg_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26047 gold=%b dut=%b", g._48910_.Q, d.wide_data_reg_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48911_.Q !== d.wide_data_reg_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26048 gold=%b dut=%b", g._48911_.Q, d.wide_data_reg_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48912_.Q !== d.wide_data_reg_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26049 gold=%b dut=%b", g._48912_.Q, d.wide_data_reg_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48913_.Q !== d.wide_data_reg_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26050 gold=%b dut=%b", g._48913_.Q, d.wide_data_reg_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48914_.Q !== d.wide_data_reg_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26051 gold=%b dut=%b", g._48914_.Q, d.wide_data_reg_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48915_.Q !== d.wide_data_reg_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26052 gold=%b dut=%b", g._48915_.Q, d.wide_data_reg_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48916_.Q !== d.wide_data_reg_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26053 gold=%b dut=%b", g._48916_.Q, d.wide_data_reg_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48917_.Q !== d.wide_data_reg_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26054 gold=%b dut=%b", g._48917_.Q, d.wide_data_reg_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48918_.Q !== d.wide_data_reg_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26055 gold=%b dut=%b", g._48918_.Q, d.wide_data_reg_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48919_.Q !== d.wide_data_reg_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26056 gold=%b dut=%b", g._48919_.Q, d.wide_data_reg_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48920_.Q !== d.wide_data_reg_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26057 gold=%b dut=%b", g._48920_.Q, d.wide_data_reg_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48921_.Q !== d.wide_data_reg_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26058 gold=%b dut=%b", g._48921_.Q, d.wide_data_reg_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48922_.Q !== d.wide_data_reg_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26059 gold=%b dut=%b", g._48922_.Q, d.wide_data_reg_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48923_.Q !== d.wide_data_reg_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26060 gold=%b dut=%b", g._48923_.Q, d.wide_data_reg_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48924_.Q !== d.wide_data_reg_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26061 gold=%b dut=%b", g._48924_.Q, d.wide_data_reg_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48925_.Q !== d.wide_data_reg_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26062 gold=%b dut=%b", g._48925_.Q, d.wide_data_reg_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48926_.Q !== d.wide_data_reg_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26063 gold=%b dut=%b", g._48926_.Q, d.wide_data_reg_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48927_.Q !== d.wide_data_reg_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26064 gold=%b dut=%b", g._48927_.Q, d.wide_data_reg_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48928_.Q !== d.wide_data_reg_2[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26065 gold=%b dut=%b", g._48928_.Q, d.wide_data_reg_2[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48929_.Q !== d.wide_data_reg_2[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26066 gold=%b dut=%b", g._48929_.Q, d.wide_data_reg_2[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48930_.Q !== d.wide_data_reg_2[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26067 gold=%b dut=%b", g._48930_.Q, d.wide_data_reg_2[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48931_.Q !== d.wide_data_reg_2[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26068 gold=%b dut=%b", g._48931_.Q, d.wide_data_reg_2[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48932_.Q !== d.wide_data_reg_2[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26069 gold=%b dut=%b", g._48932_.Q, d.wide_data_reg_2[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48933_.Q !== d.wide_data_reg_2[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26070 gold=%b dut=%b", g._48933_.Q, d.wide_data_reg_2[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48934_.Q !== d.wide_data_reg_2[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26071 gold=%b dut=%b", g._48934_.Q, d.wide_data_reg_2[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48871_.Q !== d.arithmetic_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26072 gold=%b dut=%b", g._48871_.Q, d.arithmetic_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48872_.Q !== d.arithmetic_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26073 gold=%b dut=%b", g._48872_.Q, d.arithmetic_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48873_.Q !== d.arithmetic_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26074 gold=%b dut=%b", g._48873_.Q, d.arithmetic_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48874_.Q !== d.arithmetic_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26075 gold=%b dut=%b", g._48874_.Q, d.arithmetic_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48875_.Q !== d.arithmetic_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26076 gold=%b dut=%b", g._48875_.Q, d.arithmetic_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48876_.Q !== d.arithmetic_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26077 gold=%b dut=%b", g._48876_.Q, d.arithmetic_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48877_.Q !== d.arithmetic_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26078 gold=%b dut=%b", g._48877_.Q, d.arithmetic_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48878_.Q !== d.arithmetic_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26079 gold=%b dut=%b", g._48878_.Q, d.arithmetic_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48879_.Q !== d.arithmetic_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26080 gold=%b dut=%b", g._48879_.Q, d.arithmetic_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48880_.Q !== d.arithmetic_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26081 gold=%b dut=%b", g._48880_.Q, d.arithmetic_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48881_.Q !== d.arithmetic_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26082 gold=%b dut=%b", g._48881_.Q, d.arithmetic_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48882_.Q !== d.arithmetic_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26083 gold=%b dut=%b", g._48882_.Q, d.arithmetic_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48883_.Q !== d.arithmetic_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26084 gold=%b dut=%b", g._48883_.Q, d.arithmetic_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48884_.Q !== d.arithmetic_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26085 gold=%b dut=%b", g._48884_.Q, d.arithmetic_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48885_.Q !== d.arithmetic_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26086 gold=%b dut=%b", g._48885_.Q, d.arithmetic_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48886_.Q !== d.arithmetic_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26087 gold=%b dut=%b", g._48886_.Q, d.arithmetic_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48887_.Q !== d.arithmetic_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26088 gold=%b dut=%b", g._48887_.Q, d.arithmetic_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48888_.Q !== d.arithmetic_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26089 gold=%b dut=%b", g._48888_.Q, d.arithmetic_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48889_.Q !== d.arithmetic_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26090 gold=%b dut=%b", g._48889_.Q, d.arithmetic_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48890_.Q !== d.arithmetic_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26091 gold=%b dut=%b", g._48890_.Q, d.arithmetic_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48891_.Q !== d.arithmetic_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26092 gold=%b dut=%b", g._48891_.Q, d.arithmetic_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48892_.Q !== d.arithmetic_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26093 gold=%b dut=%b", g._48892_.Q, d.arithmetic_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48893_.Q !== d.arithmetic_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26094 gold=%b dut=%b", g._48893_.Q, d.arithmetic_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48894_.Q !== d.arithmetic_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26095 gold=%b dut=%b", g._48894_.Q, d.arithmetic_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48895_.Q !== d.arithmetic_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26096 gold=%b dut=%b", g._48895_.Q, d.arithmetic_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48896_.Q !== d.arithmetic_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26097 gold=%b dut=%b", g._48896_.Q, d.arithmetic_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48897_.Q !== d.arithmetic_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26098 gold=%b dut=%b", g._48897_.Q, d.arithmetic_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48898_.Q !== d.arithmetic_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26099 gold=%b dut=%b", g._48898_.Q, d.arithmetic_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48899_.Q !== d.arithmetic_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26100 gold=%b dut=%b", g._48899_.Q, d.arithmetic_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48900_.Q !== d.arithmetic_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26101 gold=%b dut=%b", g._48900_.Q, d.arithmetic_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48901_.Q !== d.arithmetic_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26102 gold=%b dut=%b", g._48901_.Q, d.arithmetic_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48902_.Q !== d.status_flag_3) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26103 gold=%b dut=%b", g._48902_.Q, d.status_flag_3);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48839_.Q !== d.cycle_counter_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26104 gold=%b dut=%b", g._48839_.Q, d.cycle_counter_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48840_.Q !== d.cycle_counter_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26105 gold=%b dut=%b", g._48840_.Q, d.cycle_counter_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48841_.Q !== d.cycle_counter_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26106 gold=%b dut=%b", g._48841_.Q, d.cycle_counter_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48842_.Q !== d.cycle_counter_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26107 gold=%b dut=%b", g._48842_.Q, d.cycle_counter_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48843_.Q !== d.cycle_counter_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26108 gold=%b dut=%b", g._48843_.Q, d.cycle_counter_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48844_.Q !== d.cycle_counter_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26109 gold=%b dut=%b", g._48844_.Q, d.cycle_counter_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48845_.Q !== d.cycle_counter_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26110 gold=%b dut=%b", g._48845_.Q, d.cycle_counter_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48846_.Q !== d.cycle_counter_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26111 gold=%b dut=%b", g._48846_.Q, d.cycle_counter_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48847_.Q !== d.cycle_counter_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26112 gold=%b dut=%b", g._48847_.Q, d.cycle_counter_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48848_.Q !== d.cycle_counter_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26113 gold=%b dut=%b", g._48848_.Q, d.cycle_counter_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48849_.Q !== d.cycle_counter_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26114 gold=%b dut=%b", g._48849_.Q, d.cycle_counter_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48850_.Q !== d.cycle_counter_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26115 gold=%b dut=%b", g._48850_.Q, d.cycle_counter_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48851_.Q !== d.cycle_counter_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26116 gold=%b dut=%b", g._48851_.Q, d.cycle_counter_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48852_.Q !== d.cycle_counter_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26117 gold=%b dut=%b", g._48852_.Q, d.cycle_counter_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48853_.Q !== d.mode_data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26118 gold=%b dut=%b", g._48853_.Q, d.mode_data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48854_.Q !== d.mode_data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26119 gold=%b dut=%b", g._48854_.Q, d.mode_data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48855_.Q !== d.mode_data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26120 gold=%b dut=%b", g._48855_.Q, d.mode_data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48856_.Q !== d.mode_data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26121 gold=%b dut=%b", g._48856_.Q, d.mode_data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48857_.Q !== d.mode_data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26122 gold=%b dut=%b", g._48857_.Q, d.mode_data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48858_.Q !== d.mode_data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26123 gold=%b dut=%b", g._48858_.Q, d.mode_data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48859_.Q !== d.mode_data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26124 gold=%b dut=%b", g._48859_.Q, d.mode_data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48860_.Q !== d.mode_data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26125 gold=%b dut=%b", g._48860_.Q, d.mode_data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48861_.Q !== d.mode_data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26126 gold=%b dut=%b", g._48861_.Q, d.mode_data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48862_.Q !== d.control_state_3[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26127 gold=%b dut=%b", g._48862_.Q, d.control_state_3[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48863_.Q !== d.control_state_3[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26128 gold=%b dut=%b", g._48863_.Q, d.control_state_3[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48864_.Q !== d.control_state_3[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26129 gold=%b dut=%b", g._48864_.Q, d.control_state_3[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48865_.Q !== d.control_state_3[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26130 gold=%b dut=%b", g._48865_.Q, d.control_state_3[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48866_.Q !== d.control_state_3[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26131 gold=%b dut=%b", g._48866_.Q, d.control_state_3[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48867_.Q !== d.control_state_3[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26132 gold=%b dut=%b", g._48867_.Q, d.control_state_3[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48868_.Q !== d.control_state_3[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26133 gold=%b dut=%b", g._48868_.Q, d.control_state_3[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48869_.Q !== d.control_state_3[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26134 gold=%b dut=%b", g._48869_.Q, d.control_state_3[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48870_.Q !== d.control_state_3[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26135 gold=%b dut=%b", g._48870_.Q, d.control_state_3[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48807_.Q !== d.adder_result_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26136 gold=%b dut=%b", g._48807_.Q, d.adder_result_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48808_.Q !== d.adder_result_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26137 gold=%b dut=%b", g._48808_.Q, d.adder_result_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48809_.Q !== d.adder_result_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26138 gold=%b dut=%b", g._48809_.Q, d.adder_result_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48810_.Q !== d.adder_result_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26139 gold=%b dut=%b", g._48810_.Q, d.adder_result_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48811_.Q !== d.adder_result_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26140 gold=%b dut=%b", g._48811_.Q, d.adder_result_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48812_.Q !== d.adder_result_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26141 gold=%b dut=%b", g._48812_.Q, d.adder_result_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48813_.Q !== d.adder_result_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26142 gold=%b dut=%b", g._48813_.Q, d.adder_result_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48814_.Q !== d.adder_result_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26143 gold=%b dut=%b", g._48814_.Q, d.adder_result_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48815_.Q !== d.adder_result_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26144 gold=%b dut=%b", g._48815_.Q, d.adder_result_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48816_.Q !== d.adder_result_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26145 gold=%b dut=%b", g._48816_.Q, d.adder_result_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48817_.Q !== d.adder_result_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26146 gold=%b dut=%b", g._48817_.Q, d.adder_result_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48818_.Q !== d.adder_result_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26147 gold=%b dut=%b", g._48818_.Q, d.adder_result_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48819_.Q !== d.adder_result_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26148 gold=%b dut=%b", g._48819_.Q, d.adder_result_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48820_.Q !== d.adder_result_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26149 gold=%b dut=%b", g._48820_.Q, d.adder_result_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48821_.Q !== d.adder_result_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26150 gold=%b dut=%b", g._48821_.Q, d.adder_result_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48822_.Q !== d.cycle_counter_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26151 gold=%b dut=%b", g._48822_.Q, d.cycle_counter_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48823_.Q !== d.cycle_counter_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26152 gold=%b dut=%b", g._48823_.Q, d.cycle_counter_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48824_.Q !== d.cycle_counter_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26153 gold=%b dut=%b", g._48824_.Q, d.cycle_counter_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48825_.Q !== d.cycle_counter_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26154 gold=%b dut=%b", g._48825_.Q, d.cycle_counter_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48826_.Q !== d.cycle_counter_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26155 gold=%b dut=%b", g._48826_.Q, d.cycle_counter_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48827_.Q !== d.cycle_counter_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26156 gold=%b dut=%b", g._48827_.Q, d.cycle_counter_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48828_.Q !== d.cycle_counter_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26157 gold=%b dut=%b", g._48828_.Q, d.cycle_counter_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48829_.Q !== d.cycle_counter_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26158 gold=%b dut=%b", g._48829_.Q, d.cycle_counter_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48830_.Q !== d.cycle_counter_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26159 gold=%b dut=%b", g._48830_.Q, d.cycle_counter_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48831_.Q !== d.cycle_counter_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26160 gold=%b dut=%b", g._48831_.Q, d.cycle_counter_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48832_.Q !== d.cycle_counter_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26161 gold=%b dut=%b", g._48832_.Q, d.cycle_counter_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48833_.Q !== d.cycle_counter_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26162 gold=%b dut=%b", g._48833_.Q, d.cycle_counter_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48834_.Q !== d.cycle_counter_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26163 gold=%b dut=%b", g._48834_.Q, d.cycle_counter_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48835_.Q !== d.cycle_counter_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26164 gold=%b dut=%b", g._48835_.Q, d.cycle_counter_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48836_.Q !== d.cycle_counter_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26165 gold=%b dut=%b", g._48836_.Q, d.cycle_counter_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48837_.Q !== d.cycle_counter_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26166 gold=%b dut=%b", g._48837_.Q, d.cycle_counter_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48838_.Q !== d.control_flag_1) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26167 gold=%b dut=%b", g._48838_.Q, d.control_flag_1);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48775_.Q !== d.fsm_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26168 gold=%b dut=%b", g._48775_.Q, d.fsm_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48776_.Q !== d.fsm_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26169 gold=%b dut=%b", g._48776_.Q, d.fsm_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48777_.Q !== d.fsm_state[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26170 gold=%b dut=%b", g._48777_.Q, d.fsm_state[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48778_.Q !== d.fsm_state[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26171 gold=%b dut=%b", g._48778_.Q, d.fsm_state[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48779_.Q !== d.fsm_state[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26172 gold=%b dut=%b", g._48779_.Q, d.fsm_state[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48780_.Q !== d.fsm_state[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26173 gold=%b dut=%b", g._48780_.Q, d.fsm_state[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48781_.Q !== d.fsm_state[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26174 gold=%b dut=%b", g._48781_.Q, d.fsm_state[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48782_.Q !== d.pipeline_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26175 gold=%b dut=%b", g._48782_.Q, d.pipeline_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48783_.Q !== d.pipeline_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26176 gold=%b dut=%b", g._48783_.Q, d.pipeline_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48784_.Q !== d.pipeline_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26177 gold=%b dut=%b", g._48784_.Q, d.pipeline_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48785_.Q !== d.pipeline_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26178 gold=%b dut=%b", g._48785_.Q, d.pipeline_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48786_.Q !== d.pipeline_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26179 gold=%b dut=%b", g._48786_.Q, d.pipeline_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48787_.Q !== d.pipeline_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26180 gold=%b dut=%b", g._48787_.Q, d.pipeline_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48788_.Q !== d.pipeline_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26181 gold=%b dut=%b", g._48788_.Q, d.pipeline_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48789_.Q !== d.pipeline_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26182 gold=%b dut=%b", g._48789_.Q, d.pipeline_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48790_.Q !== d.pipeline_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26183 gold=%b dut=%b", g._48790_.Q, d.pipeline_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48791_.Q !== d.pipeline_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26184 gold=%b dut=%b", g._48791_.Q, d.pipeline_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48792_.Q !== d.pipeline_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26185 gold=%b dut=%b", g._48792_.Q, d.pipeline_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48793_.Q !== d.pipeline_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26186 gold=%b dut=%b", g._48793_.Q, d.pipeline_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48794_.Q !== d.pipeline_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26187 gold=%b dut=%b", g._48794_.Q, d.pipeline_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48795_.Q !== d.pipeline_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26188 gold=%b dut=%b", g._48795_.Q, d.pipeline_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48796_.Q !== d.pipeline_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26189 gold=%b dut=%b", g._48796_.Q, d.pipeline_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48797_.Q !== d.pipeline_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26190 gold=%b dut=%b", g._48797_.Q, d.pipeline_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48798_.Q !== d.pipeline_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26191 gold=%b dut=%b", g._48798_.Q, d.pipeline_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48799_.Q !== d.pipeline_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26192 gold=%b dut=%b", g._48799_.Q, d.pipeline_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48800_.Q !== d.pipeline_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26193 gold=%b dut=%b", g._48800_.Q, d.pipeline_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48801_.Q !== d.pipeline_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26194 gold=%b dut=%b", g._48801_.Q, d.pipeline_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48802_.Q !== d.pipeline_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26195 gold=%b dut=%b", g._48802_.Q, d.pipeline_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48803_.Q !== d.pipeline_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26196 gold=%b dut=%b", g._48803_.Q, d.pipeline_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48804_.Q !== d.pipeline_data_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26197 gold=%b dut=%b", g._48804_.Q, d.pipeline_data_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48805_.Q !== d.pipeline_data_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26198 gold=%b dut=%b", g._48805_.Q, d.pipeline_data_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48806_.Q !== d.pipeline_data_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26199 gold=%b dut=%b", g._48806_.Q, d.pipeline_data_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48743_.Q !== d.wide_data_reg_3[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26200 gold=%b dut=%b", g._48743_.Q, d.wide_data_reg_3[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48744_.Q !== d.wide_data_reg_3[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26201 gold=%b dut=%b", g._48744_.Q, d.wide_data_reg_3[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48745_.Q !== d.wide_data_reg_3[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26202 gold=%b dut=%b", g._48745_.Q, d.wide_data_reg_3[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48746_.Q !== d.wide_data_reg_3[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26203 gold=%b dut=%b", g._48746_.Q, d.wide_data_reg_3[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48747_.Q !== d.wide_data_reg_3[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26204 gold=%b dut=%b", g._48747_.Q, d.wide_data_reg_3[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48748_.Q !== d.wide_data_reg_3[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26205 gold=%b dut=%b", g._48748_.Q, d.wide_data_reg_3[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48749_.Q !== d.wide_data_reg_3[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26206 gold=%b dut=%b", g._48749_.Q, d.wide_data_reg_3[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48750_.Q !== d.wide_data_reg_3[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26207 gold=%b dut=%b", g._48750_.Q, d.wide_data_reg_3[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48751_.Q !== d.wide_data_reg_3[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26208 gold=%b dut=%b", g._48751_.Q, d.wide_data_reg_3[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48752_.Q !== d.wide_data_reg_3[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26209 gold=%b dut=%b", g._48752_.Q, d.wide_data_reg_3[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48753_.Q !== d.wide_data_reg_3[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26210 gold=%b dut=%b", g._48753_.Q, d.wide_data_reg_3[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48754_.Q !== d.wide_data_reg_3[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26211 gold=%b dut=%b", g._48754_.Q, d.wide_data_reg_3[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48755_.Q !== d.wide_data_reg_3[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26212 gold=%b dut=%b", g._48755_.Q, d.wide_data_reg_3[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48756_.Q !== d.wide_data_reg_3[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26213 gold=%b dut=%b", g._48756_.Q, d.wide_data_reg_3[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48757_.Q !== d.wide_data_reg_3[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26214 gold=%b dut=%b", g._48757_.Q, d.wide_data_reg_3[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48758_.Q !== d.wide_data_reg_3[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26215 gold=%b dut=%b", g._48758_.Q, d.wide_data_reg_3[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48759_.Q !== d.wide_data_reg_3[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26216 gold=%b dut=%b", g._48759_.Q, d.wide_data_reg_3[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48760_.Q !== d.wide_data_reg_3[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26217 gold=%b dut=%b", g._48760_.Q, d.wide_data_reg_3[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48761_.Q !== d.wide_data_reg_3[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26218 gold=%b dut=%b", g._48761_.Q, d.wide_data_reg_3[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48762_.Q !== d.wide_data_reg_3[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26219 gold=%b dut=%b", g._48762_.Q, d.wide_data_reg_3[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48763_.Q !== d.wide_data_reg_3[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26220 gold=%b dut=%b", g._48763_.Q, d.wide_data_reg_3[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48764_.Q !== d.wide_data_reg_3[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26221 gold=%b dut=%b", g._48764_.Q, d.wide_data_reg_3[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48765_.Q !== d.wide_data_reg_3[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26222 gold=%b dut=%b", g._48765_.Q, d.wide_data_reg_3[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48766_.Q !== d.wide_data_reg_3[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26223 gold=%b dut=%b", g._48766_.Q, d.wide_data_reg_3[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48767_.Q !== d.wide_data_reg_3[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26224 gold=%b dut=%b", g._48767_.Q, d.wide_data_reg_3[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48768_.Q !== d.wide_data_reg_3[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26225 gold=%b dut=%b", g._48768_.Q, d.wide_data_reg_3[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48769_.Q !== d.wide_data_reg_3[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26226 gold=%b dut=%b", g._48769_.Q, d.wide_data_reg_3[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48770_.Q !== d.wide_data_reg_3[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26227 gold=%b dut=%b", g._48770_.Q, d.wide_data_reg_3[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48771_.Q !== d.wide_data_reg_3[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26228 gold=%b dut=%b", g._48771_.Q, d.wide_data_reg_3[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48772_.Q !== d.wide_data_reg_3[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26229 gold=%b dut=%b", g._48772_.Q, d.wide_data_reg_3[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48773_.Q !== d.wide_data_reg_3[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26230 gold=%b dut=%b", g._48773_.Q, d.wide_data_reg_3[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48774_.Q !== d.wide_data_reg_3[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26231 gold=%b dut=%b", g._48774_.Q, d.wide_data_reg_3[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48711_.Q !== d.data_register_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26232 gold=%b dut=%b", g._48711_.Q, d.data_register_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48712_.Q !== d.data_register_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26233 gold=%b dut=%b", g._48712_.Q, d.data_register_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48713_.Q !== d.data_register_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26234 gold=%b dut=%b", g._48713_.Q, d.data_register_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48714_.Q !== d.data_register_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26235 gold=%b dut=%b", g._48714_.Q, d.data_register_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48715_.Q !== d.data_register_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26236 gold=%b dut=%b", g._48715_.Q, d.data_register_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48716_.Q !== d.data_register_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26237 gold=%b dut=%b", g._48716_.Q, d.data_register_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48717_.Q !== d.data_register_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26238 gold=%b dut=%b", g._48717_.Q, d.data_register_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48718_.Q !== d.data_register_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26239 gold=%b dut=%b", g._48718_.Q, d.data_register_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48719_.Q !== d.data_register_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26240 gold=%b dut=%b", g._48719_.Q, d.data_register_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48720_.Q !== d.data_register_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26241 gold=%b dut=%b", g._48720_.Q, d.data_register_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48721_.Q !== d.data_register_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26242 gold=%b dut=%b", g._48721_.Q, d.data_register_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48722_.Q !== d.data_register_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26243 gold=%b dut=%b", g._48722_.Q, d.data_register_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48723_.Q !== d.data_register_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26244 gold=%b dut=%b", g._48723_.Q, d.data_register_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48724_.Q !== d.data_register_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26245 gold=%b dut=%b", g._48724_.Q, d.data_register_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48725_.Q !== d.data_register_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26246 gold=%b dut=%b", g._48725_.Q, d.data_register_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48726_.Q !== d.data_register_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26247 gold=%b dut=%b", g._48726_.Q, d.data_register_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48727_.Q !== d.data_register_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26248 gold=%b dut=%b", g._48727_.Q, d.data_register_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48728_.Q !== d.data_register_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26249 gold=%b dut=%b", g._48728_.Q, d.data_register_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48729_.Q !== d.data_register_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26250 gold=%b dut=%b", g._48729_.Q, d.data_register_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48730_.Q !== d.data_register_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26251 gold=%b dut=%b", g._48730_.Q, d.data_register_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48731_.Q !== d.data_register_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26252 gold=%b dut=%b", g._48731_.Q, d.data_register_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48732_.Q !== d.data_register_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26253 gold=%b dut=%b", g._48732_.Q, d.data_register_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48733_.Q !== d.data_register_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26254 gold=%b dut=%b", g._48733_.Q, d.data_register_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48734_.Q !== d.data_register_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26255 gold=%b dut=%b", g._48734_.Q, d.data_register_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48735_.Q !== d.data_register_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26256 gold=%b dut=%b", g._48735_.Q, d.data_register_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48736_.Q !== d.data_register_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26257 gold=%b dut=%b", g._48736_.Q, d.data_register_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48737_.Q !== d.data_register_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26258 gold=%b dut=%b", g._48737_.Q, d.data_register_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48738_.Q !== d.data_register_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26259 gold=%b dut=%b", g._48738_.Q, d.data_register_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48739_.Q !== d.data_register_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26260 gold=%b dut=%b", g._48739_.Q, d.data_register_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48740_.Q !== d.data_register_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26261 gold=%b dut=%b", g._48740_.Q, d.data_register_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48741_.Q !== d.data_register_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26262 gold=%b dut=%b", g._48741_.Q, d.data_register_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48742_.Q !== d.status_flag_4) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26263 gold=%b dut=%b", g._48742_.Q, d.status_flag_4);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48679_.Q !== d.data_reg_0_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26264 gold=%b dut=%b", g._48679_.Q, d.data_reg_0_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48680_.Q !== d.data_reg_0_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26265 gold=%b dut=%b", g._48680_.Q, d.data_reg_0_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48681_.Q !== d.data_reg_0_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26266 gold=%b dut=%b", g._48681_.Q, d.data_reg_0_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48682_.Q !== d.data_reg_0_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26267 gold=%b dut=%b", g._48682_.Q, d.data_reg_0_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48683_.Q !== d.data_reg_0_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26268 gold=%b dut=%b", g._48683_.Q, d.data_reg_0_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48684_.Q !== d.data_reg_0_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26269 gold=%b dut=%b", g._48684_.Q, d.data_reg_0_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48685_.Q !== d.data_reg_0_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26270 gold=%b dut=%b", g._48685_.Q, d.data_reg_0_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48686_.Q !== d.data_reg_0_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26271 gold=%b dut=%b", g._48686_.Q, d.data_reg_0_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48687_.Q !== d.data_reg_0_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26272 gold=%b dut=%b", g._48687_.Q, d.data_reg_0_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48688_.Q !== d.data_reg_0_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26273 gold=%b dut=%b", g._48688_.Q, d.data_reg_0_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48689_.Q !== d.data_reg_0_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26274 gold=%b dut=%b", g._48689_.Q, d.data_reg_0_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48690_.Q !== d.data_reg_0_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26275 gold=%b dut=%b", g._48690_.Q, d.data_reg_0_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48691_.Q !== d.data_reg_0_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26276 gold=%b dut=%b", g._48691_.Q, d.data_reg_0_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48692_.Q !== d.data_reg_0_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26277 gold=%b dut=%b", g._48692_.Q, d.data_reg_0_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48693_.Q !== d.data_reg_0_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26278 gold=%b dut=%b", g._48693_.Q, d.data_reg_0_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48694_.Q !== d.data_reg_0_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26279 gold=%b dut=%b", g._48694_.Q, d.data_reg_0_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48695_.Q !== d.data_reg_0_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26280 gold=%b dut=%b", g._48695_.Q, d.data_reg_0_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48696_.Q !== d.data_reg_0_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26281 gold=%b dut=%b", g._48696_.Q, d.data_reg_0_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48697_.Q !== d.data_reg_0_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26282 gold=%b dut=%b", g._48697_.Q, d.data_reg_0_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48698_.Q !== d.data_reg_0_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26283 gold=%b dut=%b", g._48698_.Q, d.data_reg_0_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48699_.Q !== d.data_reg_0_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26284 gold=%b dut=%b", g._48699_.Q, d.data_reg_0_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48700_.Q !== d.data_reg_0_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26285 gold=%b dut=%b", g._48700_.Q, d.data_reg_0_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48701_.Q !== d.data_reg_0_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26286 gold=%b dut=%b", g._48701_.Q, d.data_reg_0_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48702_.Q !== d.cycle_counter_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26287 gold=%b dut=%b", g._48702_.Q, d.cycle_counter_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48703_.Q !== d.cycle_counter_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26288 gold=%b dut=%b", g._48703_.Q, d.cycle_counter_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48704_.Q !== d.cycle_counter_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26289 gold=%b dut=%b", g._48704_.Q, d.cycle_counter_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48705_.Q !== d.cycle_counter_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26290 gold=%b dut=%b", g._48705_.Q, d.cycle_counter_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48706_.Q !== d.cycle_counter_high[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26291 gold=%b dut=%b", g._48706_.Q, d.cycle_counter_high[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48707_.Q !== d.cycle_counter_high[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26292 gold=%b dut=%b", g._48707_.Q, d.cycle_counter_high[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48708_.Q !== d.cycle_counter_high[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26293 gold=%b dut=%b", g._48708_.Q, d.cycle_counter_high[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48709_.Q !== d.cycle_counter_high[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26294 gold=%b dut=%b", g._48709_.Q, d.cycle_counter_high[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48710_.Q !== d.control_flag_2) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26295 gold=%b dut=%b", g._48710_.Q, d.control_flag_2);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49576_.Q !== d.control_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26296 gold=%b dut=%b", g._49576_.Q, d.control_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49577_.Q !== d.control_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26297 gold=%b dut=%b", g._49577_.Q, d.control_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49578_.Q !== d.control_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26298 gold=%b dut=%b", g._49578_.Q, d.control_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49579_.Q !== d.control_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26299 gold=%b dut=%b", g._49579_.Q, d.control_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49580_.Q !== d.control_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26300 gold=%b dut=%b", g._49580_.Q, d.control_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49581_.Q !== d.control_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26301 gold=%b dut=%b", g._49581_.Q, d.control_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49582_.Q !== d.control_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26302 gold=%b dut=%b", g._49582_.Q, d.control_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49583_.Q !== d.control_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26303 gold=%b dut=%b", g._49583_.Q, d.control_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49584_.Q !== d.control_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26304 gold=%b dut=%b", g._49584_.Q, d.control_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49585_.Q !== d.control_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26305 gold=%b dut=%b", g._49585_.Q, d.control_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49586_.Q !== d.control_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26306 gold=%b dut=%b", g._49586_.Q, d.control_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49587_.Q !== d.control_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26307 gold=%b dut=%b", g._49587_.Q, d.control_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49588_.Q !== d.control_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26308 gold=%b dut=%b", g._49588_.Q, d.control_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49589_.Q !== d.control_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26309 gold=%b dut=%b", g._49589_.Q, d.control_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49590_.Q !== d.control_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26310 gold=%b dut=%b", g._49590_.Q, d.control_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49591_.Q !== d.control_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26311 gold=%b dut=%b", g._49591_.Q, d.control_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49592_.Q !== d.control_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26312 gold=%b dut=%b", g._49592_.Q, d.control_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49593_.Q !== d.control_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26313 gold=%b dut=%b", g._49593_.Q, d.control_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49594_.Q !== d.control_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26314 gold=%b dut=%b", g._49594_.Q, d.control_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49595_.Q !== d.control_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26315 gold=%b dut=%b", g._49595_.Q, d.control_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49596_.Q !== d.control_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26316 gold=%b dut=%b", g._49596_.Q, d.control_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49597_.Q !== d.control_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26317 gold=%b dut=%b", g._49597_.Q, d.control_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49598_.Q !== d.control_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26318 gold=%b dut=%b", g._49598_.Q, d.control_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49599_.Q !== d.control_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26319 gold=%b dut=%b", g._49599_.Q, d.control_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49600_.Q !== d.control_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26320 gold=%b dut=%b", g._49600_.Q, d.control_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49601_.Q !== d.control_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26321 gold=%b dut=%b", g._49601_.Q, d.control_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49602_.Q !== d.control_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26322 gold=%b dut=%b", g._49602_.Q, d.control_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49603_.Q !== d.control_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26323 gold=%b dut=%b", g._49603_.Q, d.control_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49604_.Q !== d.control_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26324 gold=%b dut=%b", g._49604_.Q, d.control_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49605_.Q !== d.control_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26325 gold=%b dut=%b", g._49605_.Q, d.control_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49606_.Q !== d.control_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26326 gold=%b dut=%b", g._49606_.Q, d.control_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49607_.Q !== d.control_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26327 gold=%b dut=%b", g._49607_.Q, d.control_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48647_.Q !== d.counter_a[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26328 gold=%b dut=%b", g._48647_.Q, d.counter_a[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48648_.Q !== d.counter_a[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26329 gold=%b dut=%b", g._48648_.Q, d.counter_a[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48649_.Q !== d.counter_a[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26330 gold=%b dut=%b", g._48649_.Q, d.counter_a[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48650_.Q !== d.counter_a[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26331 gold=%b dut=%b", g._48650_.Q, d.counter_a[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48651_.Q !== d.counter_a[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26332 gold=%b dut=%b", g._48651_.Q, d.counter_a[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48652_.Q !== d.counter_a[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26333 gold=%b dut=%b", g._48652_.Q, d.counter_a[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48653_.Q !== d.counter_a[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26334 gold=%b dut=%b", g._48653_.Q, d.counter_a[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48654_.Q !== d.counter_a[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26335 gold=%b dut=%b", g._48654_.Q, d.counter_a[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48655_.Q !== d.counter_a[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26336 gold=%b dut=%b", g._48655_.Q, d.counter_a[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48656_.Q !== d.counter_a[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26337 gold=%b dut=%b", g._48656_.Q, d.counter_a[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48657_.Q !== d.counter_a[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26338 gold=%b dut=%b", g._48657_.Q, d.counter_a[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48658_.Q !== d.counter_a[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26339 gold=%b dut=%b", g._48658_.Q, d.counter_a[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48659_.Q !== d.counter_a[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26340 gold=%b dut=%b", g._48659_.Q, d.counter_a[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48660_.Q !== d.counter_a[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26341 gold=%b dut=%b", g._48660_.Q, d.counter_a[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48661_.Q !== d.counter_a[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26342 gold=%b dut=%b", g._48661_.Q, d.counter_a[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48662_.Q !== d.data_reg_1_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26343 gold=%b dut=%b", g._48662_.Q, d.data_reg_1_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48663_.Q !== d.data_reg_1_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26344 gold=%b dut=%b", g._48663_.Q, d.data_reg_1_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48664_.Q !== d.data_reg_1_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26345 gold=%b dut=%b", g._48664_.Q, d.data_reg_1_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48665_.Q !== d.data_reg_1_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26346 gold=%b dut=%b", g._48665_.Q, d.data_reg_1_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48666_.Q !== d.data_reg_1_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26347 gold=%b dut=%b", g._48666_.Q, d.data_reg_1_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48667_.Q !== d.data_reg_1_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26348 gold=%b dut=%b", g._48667_.Q, d.data_reg_1_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48668_.Q !== d.data_reg_1_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26349 gold=%b dut=%b", g._48668_.Q, d.data_reg_1_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48669_.Q !== d.data_reg_1_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26350 gold=%b dut=%b", g._48669_.Q, d.data_reg_1_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48670_.Q !== d.data_reg_1_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26351 gold=%b dut=%b", g._48670_.Q, d.data_reg_1_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48671_.Q !== d.data_reg_1_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26352 gold=%b dut=%b", g._48671_.Q, d.data_reg_1_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48672_.Q !== d.data_reg_1_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26353 gold=%b dut=%b", g._48672_.Q, d.data_reg_1_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48673_.Q !== d.data_reg_1_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26354 gold=%b dut=%b", g._48673_.Q, d.data_reg_1_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48674_.Q !== d.data_reg_1_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26355 gold=%b dut=%b", g._48674_.Q, d.data_reg_1_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48675_.Q !== d.data_reg_1_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26356 gold=%b dut=%b", g._48675_.Q, d.data_reg_1_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48676_.Q !== d.data_reg_1_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26357 gold=%b dut=%b", g._48676_.Q, d.data_reg_1_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48677_.Q !== d.data_reg_1_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26358 gold=%b dut=%b", g._48677_.Q, d.data_reg_1_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48678_.Q !== d.data_reg_1_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26359 gold=%b dut=%b", g._48678_.Q, d.data_reg_1_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48615_.Q !== d.address_counter_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26360 gold=%b dut=%b", g._48615_.Q, d.address_counter_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48616_.Q !== d.address_counter_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26361 gold=%b dut=%b", g._48616_.Q, d.address_counter_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48617_.Q !== d.address_counter_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26362 gold=%b dut=%b", g._48617_.Q, d.address_counter_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48618_.Q !== d.address_counter_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26363 gold=%b dut=%b", g._48618_.Q, d.address_counter_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48619_.Q !== d.address_counter_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26364 gold=%b dut=%b", g._48619_.Q, d.address_counter_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48620_.Q !== d.address_counter_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26365 gold=%b dut=%b", g._48620_.Q, d.address_counter_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48621_.Q !== d.address_counter_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26366 gold=%b dut=%b", g._48621_.Q, d.address_counter_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48622_.Q !== d.address_counter_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26367 gold=%b dut=%b", g._48622_.Q, d.address_counter_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48623_.Q !== d.address_counter_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26368 gold=%b dut=%b", g._48623_.Q, d.address_counter_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48624_.Q !== d.address_counter_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26369 gold=%b dut=%b", g._48624_.Q, d.address_counter_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48625_.Q !== d.address_counter_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26370 gold=%b dut=%b", g._48625_.Q, d.address_counter_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48626_.Q !== d.address_counter_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26371 gold=%b dut=%b", g._48626_.Q, d.address_counter_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48627_.Q !== d.address_counter_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26372 gold=%b dut=%b", g._48627_.Q, d.address_counter_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48628_.Q !== d.address_counter_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26373 gold=%b dut=%b", g._48628_.Q, d.address_counter_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48629_.Q !== d.address_counter_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26374 gold=%b dut=%b", g._48629_.Q, d.address_counter_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48630_.Q !== d.address_counter_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26375 gold=%b dut=%b", g._48630_.Q, d.address_counter_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48631_.Q !== d.address_counter_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26376 gold=%b dut=%b", g._48631_.Q, d.address_counter_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48632_.Q !== d.address_counter_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26377 gold=%b dut=%b", g._48632_.Q, d.address_counter_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48633_.Q !== d.address_counter_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26378 gold=%b dut=%b", g._48633_.Q, d.address_counter_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48634_.Q !== d.address_counter_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26379 gold=%b dut=%b", g._48634_.Q, d.address_counter_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48635_.Q !== d.address_counter_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26380 gold=%b dut=%b", g._48635_.Q, d.address_counter_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48636_.Q !== d.address_counter_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26381 gold=%b dut=%b", g._48636_.Q, d.address_counter_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48637_.Q !== d.address_counter_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26382 gold=%b dut=%b", g._48637_.Q, d.address_counter_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48638_.Q !== d.address_counter_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26383 gold=%b dut=%b", g._48638_.Q, d.address_counter_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48639_.Q !== d.address_counter_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26384 gold=%b dut=%b", g._48639_.Q, d.address_counter_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48640_.Q !== d.address_counter_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26385 gold=%b dut=%b", g._48640_.Q, d.address_counter_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48641_.Q !== d.address_counter_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26386 gold=%b dut=%b", g._48641_.Q, d.address_counter_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48642_.Q !== d.address_counter_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26387 gold=%b dut=%b", g._48642_.Q, d.address_counter_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48643_.Q !== d.address_counter_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26388 gold=%b dut=%b", g._48643_.Q, d.address_counter_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48644_.Q !== d.address_counter_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26389 gold=%b dut=%b", g._48644_.Q, d.address_counter_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48645_.Q !== d.address_counter_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26390 gold=%b dut=%b", g._48645_.Q, d.address_counter_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48646_.Q !== d.counter_control_state) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26391 gold=%b dut=%b", g._48646_.Q, d.counter_control_state);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48583_.Q !== d.word_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26392 gold=%b dut=%b", g._48583_.Q, d.word_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48584_.Q !== d.word_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26393 gold=%b dut=%b", g._48584_.Q, d.word_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48585_.Q !== d.word_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26394 gold=%b dut=%b", g._48585_.Q, d.word_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48586_.Q !== d.word_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26395 gold=%b dut=%b", g._48586_.Q, d.word_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48587_.Q !== d.word_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26396 gold=%b dut=%b", g._48587_.Q, d.word_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48588_.Q !== d.word_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26397 gold=%b dut=%b", g._48588_.Q, d.word_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48589_.Q !== d.word_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26398 gold=%b dut=%b", g._48589_.Q, d.word_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48590_.Q !== d.word_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26399 gold=%b dut=%b", g._48590_.Q, d.word_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48591_.Q !== d.word_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26400 gold=%b dut=%b", g._48591_.Q, d.word_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48592_.Q !== d.word_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26401 gold=%b dut=%b", g._48592_.Q, d.word_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48593_.Q !== d.word_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26402 gold=%b dut=%b", g._48593_.Q, d.word_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48594_.Q !== d.word_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26403 gold=%b dut=%b", g._48594_.Q, d.word_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48595_.Q !== d.word_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26404 gold=%b dut=%b", g._48595_.Q, d.word_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48596_.Q !== d.word_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26405 gold=%b dut=%b", g._48596_.Q, d.word_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48597_.Q !== d.word_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26406 gold=%b dut=%b", g._48597_.Q, d.word_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48598_.Q !== d.word_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26407 gold=%b dut=%b", g._48598_.Q, d.word_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48599_.Q !== d.word_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26408 gold=%b dut=%b", g._48599_.Q, d.word_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48600_.Q !== d.word_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26409 gold=%b dut=%b", g._48600_.Q, d.word_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48601_.Q !== d.word_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26410 gold=%b dut=%b", g._48601_.Q, d.word_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48602_.Q !== d.word_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26411 gold=%b dut=%b", g._48602_.Q, d.word_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48603_.Q !== d.word_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26412 gold=%b dut=%b", g._48603_.Q, d.word_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48604_.Q !== d.word_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26413 gold=%b dut=%b", g._48604_.Q, d.word_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48605_.Q !== d.word_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26414 gold=%b dut=%b", g._48605_.Q, d.word_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48606_.Q !== d.word_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26415 gold=%b dut=%b", g._48606_.Q, d.word_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48607_.Q !== d.word_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26416 gold=%b dut=%b", g._48607_.Q, d.word_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48608_.Q !== d.word_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26417 gold=%b dut=%b", g._48608_.Q, d.word_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48609_.Q !== d.word_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26418 gold=%b dut=%b", g._48609_.Q, d.word_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48610_.Q !== d.word_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26419 gold=%b dut=%b", g._48610_.Q, d.word_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48611_.Q !== d.word_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26420 gold=%b dut=%b", g._48611_.Q, d.word_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48612_.Q !== d.word_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26421 gold=%b dut=%b", g._48612_.Q, d.word_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48613_.Q !== d.word_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26422 gold=%b dut=%b", g._48613_.Q, d.word_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48614_.Q !== d.word_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26423 gold=%b dut=%b", g._48614_.Q, d.word_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48551_.Q !== d.indexed_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26424 gold=%b dut=%b", g._48551_.Q, d.indexed_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48552_.Q !== d.indexed_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26425 gold=%b dut=%b", g._48552_.Q, d.indexed_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48553_.Q !== d.indexed_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26426 gold=%b dut=%b", g._48553_.Q, d.indexed_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48554_.Q !== d.indexed_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26427 gold=%b dut=%b", g._48554_.Q, d.indexed_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48555_.Q !== d.indexed_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26428 gold=%b dut=%b", g._48555_.Q, d.indexed_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48556_.Q !== d.indexed_counter[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26429 gold=%b dut=%b", g._48556_.Q, d.indexed_counter[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48557_.Q !== d.indexed_counter[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26430 gold=%b dut=%b", g._48557_.Q, d.indexed_counter[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48558_.Q !== d.indexed_counter[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26431 gold=%b dut=%b", g._48558_.Q, d.indexed_counter[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48559_.Q !== d.indexed_counter[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26432 gold=%b dut=%b", g._48559_.Q, d.indexed_counter[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48560_.Q !== d.indexed_counter[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26433 gold=%b dut=%b", g._48560_.Q, d.indexed_counter[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48561_.Q !== d.indexed_counter[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26434 gold=%b dut=%b", g._48561_.Q, d.indexed_counter[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48562_.Q !== d.indexed_counter[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26435 gold=%b dut=%b", g._48562_.Q, d.indexed_counter[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48563_.Q !== d.indexed_counter[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26436 gold=%b dut=%b", g._48563_.Q, d.indexed_counter[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48564_.Q !== d.indexed_counter[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26437 gold=%b dut=%b", g._48564_.Q, d.indexed_counter[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48565_.Q !== d.indexed_counter[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26438 gold=%b dut=%b", g._48565_.Q, d.indexed_counter[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48566_.Q !== d.indexed_counter[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26439 gold=%b dut=%b", g._48566_.Q, d.indexed_counter[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48567_.Q !== d.indexed_counter[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26440 gold=%b dut=%b", g._48567_.Q, d.indexed_counter[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48568_.Q !== d.indexed_counter[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26441 gold=%b dut=%b", g._48568_.Q, d.indexed_counter[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48569_.Q !== d.indexed_counter[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26442 gold=%b dut=%b", g._48569_.Q, d.indexed_counter[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48570_.Q !== d.indexed_counter[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26443 gold=%b dut=%b", g._48570_.Q, d.indexed_counter[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48571_.Q !== d.indexed_counter[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26444 gold=%b dut=%b", g._48571_.Q, d.indexed_counter[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48572_.Q !== d.indexed_counter[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26445 gold=%b dut=%b", g._48572_.Q, d.indexed_counter[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48573_.Q !== d.indexed_counter[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26446 gold=%b dut=%b", g._48573_.Q, d.indexed_counter[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48574_.Q !== d.indexed_counter[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26447 gold=%b dut=%b", g._48574_.Q, d.indexed_counter[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48575_.Q !== d.indexed_counter[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26448 gold=%b dut=%b", g._48575_.Q, d.indexed_counter[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48576_.Q !== d.indexed_counter[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26449 gold=%b dut=%b", g._48576_.Q, d.indexed_counter[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48577_.Q !== d.indexed_counter[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26450 gold=%b dut=%b", g._48577_.Q, d.indexed_counter[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48578_.Q !== d.indexed_counter[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26451 gold=%b dut=%b", g._48578_.Q, d.indexed_counter[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48579_.Q !== d.indexed_counter[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26452 gold=%b dut=%b", g._48579_.Q, d.indexed_counter[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48580_.Q !== d.indexed_counter[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26453 gold=%b dut=%b", g._48580_.Q, d.indexed_counter[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48581_.Q !== d.indexed_counter[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26454 gold=%b dut=%b", g._48581_.Q, d.indexed_counter[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48582_.Q !== d.word_valid_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26455 gold=%b dut=%b", g._48582_.Q, d.word_valid_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48519_.Q !== d.write_data_register_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26456 gold=%b dut=%b", g._48519_.Q, d.write_data_register_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48520_.Q !== d.write_data_register_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26457 gold=%b dut=%b", g._48520_.Q, d.write_data_register_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48521_.Q !== d.write_data_register_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26458 gold=%b dut=%b", g._48521_.Q, d.write_data_register_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48522_.Q !== d.write_data_register_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26459 gold=%b dut=%b", g._48522_.Q, d.write_data_register_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48523_.Q !== d.write_data_register_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26460 gold=%b dut=%b", g._48523_.Q, d.write_data_register_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48524_.Q !== d.write_data_register_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26461 gold=%b dut=%b", g._48524_.Q, d.write_data_register_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48525_.Q !== d.write_data_register_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26462 gold=%b dut=%b", g._48525_.Q, d.write_data_register_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48526_.Q !== d.write_data_register_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26463 gold=%b dut=%b", g._48526_.Q, d.write_data_register_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48527_.Q !== d.write_data_register_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26464 gold=%b dut=%b", g._48527_.Q, d.write_data_register_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48528_.Q !== d.write_data_register_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26465 gold=%b dut=%b", g._48528_.Q, d.write_data_register_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48529_.Q !== d.write_data_register_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26466 gold=%b dut=%b", g._48529_.Q, d.write_data_register_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48530_.Q !== d.write_data_register_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26467 gold=%b dut=%b", g._48530_.Q, d.write_data_register_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48531_.Q !== d.write_data_register_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26468 gold=%b dut=%b", g._48531_.Q, d.write_data_register_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48532_.Q !== d.write_data_register_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26469 gold=%b dut=%b", g._48532_.Q, d.write_data_register_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48533_.Q !== d.write_data_register_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26470 gold=%b dut=%b", g._48533_.Q, d.write_data_register_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48534_.Q !== d.write_data_register_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26471 gold=%b dut=%b", g._48534_.Q, d.write_data_register_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48535_.Q !== d.write_data_register_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26472 gold=%b dut=%b", g._48535_.Q, d.write_data_register_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48536_.Q !== d.write_data_register_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26473 gold=%b dut=%b", g._48536_.Q, d.write_data_register_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48537_.Q !== d.write_data_register_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26474 gold=%b dut=%b", g._48537_.Q, d.write_data_register_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48538_.Q !== d.write_data_register_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26475 gold=%b dut=%b", g._48538_.Q, d.write_data_register_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48539_.Q !== d.write_data_register_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26476 gold=%b dut=%b", g._48539_.Q, d.write_data_register_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48540_.Q !== d.write_data_register_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26477 gold=%b dut=%b", g._48540_.Q, d.write_data_register_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48541_.Q !== d.write_data_register_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26478 gold=%b dut=%b", g._48541_.Q, d.write_data_register_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48542_.Q !== d.write_data_register_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26479 gold=%b dut=%b", g._48542_.Q, d.write_data_register_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48543_.Q !== d.write_data_register_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26480 gold=%b dut=%b", g._48543_.Q, d.write_data_register_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48544_.Q !== d.write_data_register_2[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26481 gold=%b dut=%b", g._48544_.Q, d.write_data_register_2[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48545_.Q !== d.write_data_register_2[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26482 gold=%b dut=%b", g._48545_.Q, d.write_data_register_2[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48546_.Q !== d.write_data_register_2[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26483 gold=%b dut=%b", g._48546_.Q, d.write_data_register_2[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48547_.Q !== d.write_data_register_2[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26484 gold=%b dut=%b", g._48547_.Q, d.write_data_register_2[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48548_.Q !== d.write_data_register_2[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26485 gold=%b dut=%b", g._48548_.Q, d.write_data_register_2[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48549_.Q !== d.write_data_register_2[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26486 gold=%b dut=%b", g._48549_.Q, d.write_data_register_2[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48550_.Q !== d.write_data_register_2[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26487 gold=%b dut=%b", g._48550_.Q, d.write_data_register_2[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48487_.Q !== d.data_register_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26488 gold=%b dut=%b", g._48487_.Q, d.data_register_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48488_.Q !== d.data_register_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26489 gold=%b dut=%b", g._48488_.Q, d.data_register_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48489_.Q !== d.data_register_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26490 gold=%b dut=%b", g._48489_.Q, d.data_register_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48490_.Q !== d.data_register_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26491 gold=%b dut=%b", g._48490_.Q, d.data_register_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48491_.Q !== d.data_register_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26492 gold=%b dut=%b", g._48491_.Q, d.data_register_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48492_.Q !== d.data_register_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26493 gold=%b dut=%b", g._48492_.Q, d.data_register_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48493_.Q !== d.data_register_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26494 gold=%b dut=%b", g._48493_.Q, d.data_register_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48494_.Q !== d.data_register_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26495 gold=%b dut=%b", g._48494_.Q, d.data_register_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48495_.Q !== d.data_register_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26496 gold=%b dut=%b", g._48495_.Q, d.data_register_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48496_.Q !== d.data_register_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26497 gold=%b dut=%b", g._48496_.Q, d.data_register_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48497_.Q !== d.data_register_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26498 gold=%b dut=%b", g._48497_.Q, d.data_register_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48498_.Q !== d.data_register_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26499 gold=%b dut=%b", g._48498_.Q, d.data_register_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48499_.Q !== d.data_register_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26500 gold=%b dut=%b", g._48499_.Q, d.data_register_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48500_.Q !== d.data_register_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26501 gold=%b dut=%b", g._48500_.Q, d.data_register_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48501_.Q !== d.data_register_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26502 gold=%b dut=%b", g._48501_.Q, d.data_register_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48502_.Q !== d.wide_counter_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26503 gold=%b dut=%b", g._48502_.Q, d.wide_counter_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48503_.Q !== d.wide_counter_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26504 gold=%b dut=%b", g._48503_.Q, d.wide_counter_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48504_.Q !== d.wide_counter_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26505 gold=%b dut=%b", g._48504_.Q, d.wide_counter_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48505_.Q !== d.wide_counter_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26506 gold=%b dut=%b", g._48505_.Q, d.wide_counter_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48506_.Q !== d.wide_counter_high[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26507 gold=%b dut=%b", g._48506_.Q, d.wide_counter_high[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48507_.Q !== d.wide_counter_high[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26508 gold=%b dut=%b", g._48507_.Q, d.wide_counter_high[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48508_.Q !== d.wide_counter_high[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26509 gold=%b dut=%b", g._48508_.Q, d.wide_counter_high[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48509_.Q !== d.wide_counter_high[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26510 gold=%b dut=%b", g._48509_.Q, d.wide_counter_high[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48510_.Q !== d.wide_counter_high[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26511 gold=%b dut=%b", g._48510_.Q, d.wide_counter_high[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48511_.Q !== d.wide_counter_high[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26512 gold=%b dut=%b", g._48511_.Q, d.wide_counter_high[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48512_.Q !== d.wide_counter_high[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26513 gold=%b dut=%b", g._48512_.Q, d.wide_counter_high[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48513_.Q !== d.wide_counter_high[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26514 gold=%b dut=%b", g._48513_.Q, d.wide_counter_high[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48514_.Q !== d.wide_counter_high[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26515 gold=%b dut=%b", g._48514_.Q, d.wide_counter_high[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48515_.Q !== d.wide_counter_high[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26516 gold=%b dut=%b", g._48515_.Q, d.wide_counter_high[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48516_.Q !== d.wide_counter_high[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26517 gold=%b dut=%b", g._48516_.Q, d.wide_counter_high[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48517_.Q !== d.wide_counter_high[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26518 gold=%b dut=%b", g._48517_.Q, d.wide_counter_high[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48518_.Q !== d.control_flag_3) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26519 gold=%b dut=%b", g._48518_.Q, d.control_flag_3);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49544_.Q !== d.data_word_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26520 gold=%b dut=%b", g._49544_.Q, d.data_word_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49545_.Q !== d.data_word_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26521 gold=%b dut=%b", g._49545_.Q, d.data_word_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49546_.Q !== d.data_word_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26522 gold=%b dut=%b", g._49546_.Q, d.data_word_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49547_.Q !== d.data_word_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26523 gold=%b dut=%b", g._49547_.Q, d.data_word_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49548_.Q !== d.data_word_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26524 gold=%b dut=%b", g._49548_.Q, d.data_word_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49549_.Q !== d.data_word_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26525 gold=%b dut=%b", g._49549_.Q, d.data_word_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49550_.Q !== d.data_word_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26526 gold=%b dut=%b", g._49550_.Q, d.data_word_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49551_.Q !== d.data_word_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26527 gold=%b dut=%b", g._49551_.Q, d.data_word_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49552_.Q !== d.data_word_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26528 gold=%b dut=%b", g._49552_.Q, d.data_word_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49553_.Q !== d.data_word_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26529 gold=%b dut=%b", g._49553_.Q, d.data_word_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49554_.Q !== d.data_word_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26530 gold=%b dut=%b", g._49554_.Q, d.data_word_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49555_.Q !== d.data_word_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26531 gold=%b dut=%b", g._49555_.Q, d.data_word_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49556_.Q !== d.data_word_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26532 gold=%b dut=%b", g._49556_.Q, d.data_word_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49557_.Q !== d.data_word_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26533 gold=%b dut=%b", g._49557_.Q, d.data_word_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49558_.Q !== d.data_word_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26534 gold=%b dut=%b", g._49558_.Q, d.data_word_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49559_.Q !== d.data_word_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26535 gold=%b dut=%b", g._49559_.Q, d.data_word_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49560_.Q !== d.data_word_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26536 gold=%b dut=%b", g._49560_.Q, d.data_word_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49561_.Q !== d.data_word_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26537 gold=%b dut=%b", g._49561_.Q, d.data_word_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49562_.Q !== d.data_word_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26538 gold=%b dut=%b", g._49562_.Q, d.data_word_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49563_.Q !== d.data_word_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26539 gold=%b dut=%b", g._49563_.Q, d.data_word_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49564_.Q !== d.data_word_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26540 gold=%b dut=%b", g._49564_.Q, d.data_word_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49565_.Q !== d.data_word_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26541 gold=%b dut=%b", g._49565_.Q, d.data_word_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49566_.Q !== d.data_word_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26542 gold=%b dut=%b", g._49566_.Q, d.data_word_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49567_.Q !== d.data_word_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26543 gold=%b dut=%b", g._49567_.Q, d.data_word_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49568_.Q !== d.data_word_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26544 gold=%b dut=%b", g._49568_.Q, d.data_word_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49569_.Q !== d.data_word_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26545 gold=%b dut=%b", g._49569_.Q, d.data_word_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49570_.Q !== d.data_word_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26546 gold=%b dut=%b", g._49570_.Q, d.data_word_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49571_.Q !== d.data_word_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26547 gold=%b dut=%b", g._49571_.Q, d.data_word_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49572_.Q !== d.data_word_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26548 gold=%b dut=%b", g._49572_.Q, d.data_word_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49573_.Q !== d.data_word_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26549 gold=%b dut=%b", g._49573_.Q, d.data_word_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49574_.Q !== d.data_word_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26550 gold=%b dut=%b", g._49574_.Q, d.data_word_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49575_.Q !== d.data_word_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26551 gold=%b dut=%b", g._49575_.Q, d.data_word_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49512_.Q !== d.data_register_3[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26552 gold=%b dut=%b", g._49512_.Q, d.data_register_3[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49513_.Q !== d.data_register_3[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26553 gold=%b dut=%b", g._49513_.Q, d.data_register_3[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49514_.Q !== d.data_register_3[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26554 gold=%b dut=%b", g._49514_.Q, d.data_register_3[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49515_.Q !== d.data_register_3[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26555 gold=%b dut=%b", g._49515_.Q, d.data_register_3[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49516_.Q !== d.data_register_3[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26556 gold=%b dut=%b", g._49516_.Q, d.data_register_3[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49517_.Q !== d.data_register_3[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26557 gold=%b dut=%b", g._49517_.Q, d.data_register_3[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49518_.Q !== d.data_register_3[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26558 gold=%b dut=%b", g._49518_.Q, d.data_register_3[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49519_.Q !== d.data_register_3[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26559 gold=%b dut=%b", g._49519_.Q, d.data_register_3[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49520_.Q !== d.data_register_3[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26560 gold=%b dut=%b", g._49520_.Q, d.data_register_3[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49521_.Q !== d.data_register_3[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26561 gold=%b dut=%b", g._49521_.Q, d.data_register_3[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49522_.Q !== d.data_register_3[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26562 gold=%b dut=%b", g._49522_.Q, d.data_register_3[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49523_.Q !== d.data_register_3[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26563 gold=%b dut=%b", g._49523_.Q, d.data_register_3[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49524_.Q !== d.data_register_3[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26564 gold=%b dut=%b", g._49524_.Q, d.data_register_3[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49525_.Q !== d.data_register_3[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26565 gold=%b dut=%b", g._49525_.Q, d.data_register_3[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49526_.Q !== d.data_register_3[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26566 gold=%b dut=%b", g._49526_.Q, d.data_register_3[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49527_.Q !== d.data_register_3[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26567 gold=%b dut=%b", g._49527_.Q, d.data_register_3[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49528_.Q !== d.data_register_3[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26568 gold=%b dut=%b", g._49528_.Q, d.data_register_3[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49529_.Q !== d.data_register_3[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26569 gold=%b dut=%b", g._49529_.Q, d.data_register_3[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49530_.Q !== d.data_register_3[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26570 gold=%b dut=%b", g._49530_.Q, d.data_register_3[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49531_.Q !== d.data_register_3[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26571 gold=%b dut=%b", g._49531_.Q, d.data_register_3[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49532_.Q !== d.data_register_3[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26572 gold=%b dut=%b", g._49532_.Q, d.data_register_3[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49533_.Q !== d.data_register_3[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26573 gold=%b dut=%b", g._49533_.Q, d.data_register_3[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49534_.Q !== d.data_register_3[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26574 gold=%b dut=%b", g._49534_.Q, d.data_register_3[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49535_.Q !== d.data_register_3[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26575 gold=%b dut=%b", g._49535_.Q, d.data_register_3[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49536_.Q !== d.data_register_3[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26576 gold=%b dut=%b", g._49536_.Q, d.data_register_3[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49537_.Q !== d.data_register_3[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26577 gold=%b dut=%b", g._49537_.Q, d.data_register_3[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49538_.Q !== d.data_register_3[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26578 gold=%b dut=%b", g._49538_.Q, d.data_register_3[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49539_.Q !== d.data_register_3[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26579 gold=%b dut=%b", g._49539_.Q, d.data_register_3[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49540_.Q !== d.data_register_3[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26580 gold=%b dut=%b", g._49540_.Q, d.data_register_3[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49541_.Q !== d.data_register_3[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26581 gold=%b dut=%b", g._49541_.Q, d.data_register_3[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49542_.Q !== d.fsm_state_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26582 gold=%b dut=%b", g._49542_.Q, d.fsm_state_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49543_.Q !== d.fsm_state_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26583 gold=%b dut=%b", g._49543_.Q, d.fsm_state_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49480_.Q !== d.data_reg_22bit[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26584 gold=%b dut=%b", g._49480_.Q, d.data_reg_22bit[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49481_.Q !== d.data_reg_22bit[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26585 gold=%b dut=%b", g._49481_.Q, d.data_reg_22bit[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49482_.Q !== d.data_reg_22bit[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26586 gold=%b dut=%b", g._49482_.Q, d.data_reg_22bit[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49483_.Q !== d.data_reg_22bit[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26587 gold=%b dut=%b", g._49483_.Q, d.data_reg_22bit[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49484_.Q !== d.data_reg_22bit[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26588 gold=%b dut=%b", g._49484_.Q, d.data_reg_22bit[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49485_.Q !== d.data_reg_22bit[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26589 gold=%b dut=%b", g._49485_.Q, d.data_reg_22bit[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49486_.Q !== d.data_reg_22bit[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26590 gold=%b dut=%b", g._49486_.Q, d.data_reg_22bit[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49487_.Q !== d.data_reg_22bit[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26591 gold=%b dut=%b", g._49487_.Q, d.data_reg_22bit[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49488_.Q !== d.data_reg_22bit[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26592 gold=%b dut=%b", g._49488_.Q, d.data_reg_22bit[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49489_.Q !== d.data_reg_22bit[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26593 gold=%b dut=%b", g._49489_.Q, d.data_reg_22bit[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49490_.Q !== d.data_reg_22bit[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26594 gold=%b dut=%b", g._49490_.Q, d.data_reg_22bit[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49491_.Q !== d.data_reg_22bit[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26595 gold=%b dut=%b", g._49491_.Q, d.data_reg_22bit[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49492_.Q !== d.data_reg_22bit[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26596 gold=%b dut=%b", g._49492_.Q, d.data_reg_22bit[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49493_.Q !== d.data_reg_22bit[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26597 gold=%b dut=%b", g._49493_.Q, d.data_reg_22bit[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49494_.Q !== d.data_reg_22bit[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26598 gold=%b dut=%b", g._49494_.Q, d.data_reg_22bit[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49495_.Q !== d.data_reg_22bit[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26599 gold=%b dut=%b", g._49495_.Q, d.data_reg_22bit[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49496_.Q !== d.data_reg_22bit[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26600 gold=%b dut=%b", g._49496_.Q, d.data_reg_22bit[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49497_.Q !== d.data_reg_22bit[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26601 gold=%b dut=%b", g._49497_.Q, d.data_reg_22bit[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49498_.Q !== d.data_reg_22bit[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26602 gold=%b dut=%b", g._49498_.Q, d.data_reg_22bit[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49499_.Q !== d.data_reg_22bit[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26603 gold=%b dut=%b", g._49499_.Q, d.data_reg_22bit[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49500_.Q !== d.data_reg_22bit[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26604 gold=%b dut=%b", g._49500_.Q, d.data_reg_22bit[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49501_.Q !== d.data_reg_22bit[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26605 gold=%b dut=%b", g._49501_.Q, d.data_reg_22bit[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49502_.Q !== d.wide_counter_high_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26606 gold=%b dut=%b", g._49502_.Q, d.wide_counter_high_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49503_.Q !== d.wide_counter_high_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26607 gold=%b dut=%b", g._49503_.Q, d.wide_counter_high_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49504_.Q !== d.wide_counter_high_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26608 gold=%b dut=%b", g._49504_.Q, d.wide_counter_high_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49505_.Q !== d.wide_counter_high_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26609 gold=%b dut=%b", g._49505_.Q, d.wide_counter_high_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49506_.Q !== d.wide_counter_high_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26610 gold=%b dut=%b", g._49506_.Q, d.wide_counter_high_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49507_.Q !== d.wide_counter_high_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26611 gold=%b dut=%b", g._49507_.Q, d.wide_counter_high_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49508_.Q !== d.wide_counter_high_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26612 gold=%b dut=%b", g._49508_.Q, d.wide_counter_high_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49509_.Q !== d.wide_counter_high_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26613 gold=%b dut=%b", g._49509_.Q, d.wide_counter_high_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49510_.Q !== d.wide_counter_high_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26614 gold=%b dut=%b", g._49510_.Q, d.wide_counter_high_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49511_.Q !== d.control_flag_4) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26615 gold=%b dut=%b", g._49511_.Q, d.control_flag_4);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49448_.Q !== d.control_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26616 gold=%b dut=%b", g._49448_.Q, d.control_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49449_.Q !== d.control_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26617 gold=%b dut=%b", g._49449_.Q, d.control_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49450_.Q !== d.control_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26618 gold=%b dut=%b", g._49450_.Q, d.control_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49451_.Q !== d.control_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26619 gold=%b dut=%b", g._49451_.Q, d.control_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49452_.Q !== d.control_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26620 gold=%b dut=%b", g._49452_.Q, d.control_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49453_.Q !== d.control_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26621 gold=%b dut=%b", g._49453_.Q, d.control_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49454_.Q !== d.control_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26622 gold=%b dut=%b", g._49454_.Q, d.control_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49455_.Q !== d.control_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26623 gold=%b dut=%b", g._49455_.Q, d.control_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49456_.Q !== d.control_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26624 gold=%b dut=%b", g._49456_.Q, d.control_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49457_.Q !== d.control_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26625 gold=%b dut=%b", g._49457_.Q, d.control_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49458_.Q !== d.control_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26626 gold=%b dut=%b", g._49458_.Q, d.control_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49459_.Q !== d.control_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26627 gold=%b dut=%b", g._49459_.Q, d.control_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49460_.Q !== d.control_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26628 gold=%b dut=%b", g._49460_.Q, d.control_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49461_.Q !== d.control_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26629 gold=%b dut=%b", g._49461_.Q, d.control_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49462_.Q !== d.control_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26630 gold=%b dut=%b", g._49462_.Q, d.control_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49463_.Q !== d.control_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26631 gold=%b dut=%b", g._49463_.Q, d.control_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49464_.Q !== d.control_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26632 gold=%b dut=%b", g._49464_.Q, d.control_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49465_.Q !== d.control_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26633 gold=%b dut=%b", g._49465_.Q, d.control_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49466_.Q !== d.control_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26634 gold=%b dut=%b", g._49466_.Q, d.control_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49467_.Q !== d.control_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26635 gold=%b dut=%b", g._49467_.Q, d.control_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49468_.Q !== d.control_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26636 gold=%b dut=%b", g._49468_.Q, d.control_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49469_.Q !== d.control_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26637 gold=%b dut=%b", g._49469_.Q, d.control_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49470_.Q !== d.control_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26638 gold=%b dut=%b", g._49470_.Q, d.control_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49471_.Q !== d.control_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26639 gold=%b dut=%b", g._49471_.Q, d.control_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49472_.Q !== d.control_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26640 gold=%b dut=%b", g._49472_.Q, d.control_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49473_.Q !== d.control_reg_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26641 gold=%b dut=%b", g._49473_.Q, d.control_reg_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49474_.Q !== d.control_reg_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26642 gold=%b dut=%b", g._49474_.Q, d.control_reg_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49475_.Q !== d.control_reg_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26643 gold=%b dut=%b", g._49475_.Q, d.control_reg_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49476_.Q !== d.control_reg_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26644 gold=%b dut=%b", g._49476_.Q, d.control_reg_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49477_.Q !== d.control_reg_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26645 gold=%b dut=%b", g._49477_.Q, d.control_reg_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49478_.Q !== d.control_reg_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26646 gold=%b dut=%b", g._49478_.Q, d.control_reg_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49479_.Q !== d.control_reg_1[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26647 gold=%b dut=%b", g._49479_.Q, d.control_reg_1[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49416_.Q !== d.fsm_state_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26648 gold=%b dut=%b", g._49416_.Q, d.fsm_state_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49417_.Q !== d.fsm_state_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26649 gold=%b dut=%b", g._49417_.Q, d.fsm_state_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49418_.Q !== d.fsm_state_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26650 gold=%b dut=%b", g._49418_.Q, d.fsm_state_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49419_.Q !== d.fsm_state_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26651 gold=%b dut=%b", g._49419_.Q, d.fsm_state_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49420_.Q !== d.fsm_state_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26652 gold=%b dut=%b", g._49420_.Q, d.fsm_state_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49421_.Q !== d.fsm_state_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26653 gold=%b dut=%b", g._49421_.Q, d.fsm_state_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49422_.Q !== d.payload_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26654 gold=%b dut=%b", g._49422_.Q, d.payload_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49423_.Q !== d.payload_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26655 gold=%b dut=%b", g._49423_.Q, d.payload_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49424_.Q !== d.payload_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26656 gold=%b dut=%b", g._49424_.Q, d.payload_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49425_.Q !== d.payload_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26657 gold=%b dut=%b", g._49425_.Q, d.payload_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49426_.Q !== d.payload_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26658 gold=%b dut=%b", g._49426_.Q, d.payload_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49427_.Q !== d.payload_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26659 gold=%b dut=%b", g._49427_.Q, d.payload_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49428_.Q !== d.payload_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26660 gold=%b dut=%b", g._49428_.Q, d.payload_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49429_.Q !== d.payload_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26661 gold=%b dut=%b", g._49429_.Q, d.payload_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49430_.Q !== d.payload_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26662 gold=%b dut=%b", g._49430_.Q, d.payload_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49431_.Q !== d.payload_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26663 gold=%b dut=%b", g._49431_.Q, d.payload_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49432_.Q !== d.payload_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26664 gold=%b dut=%b", g._49432_.Q, d.payload_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49433_.Q !== d.payload_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26665 gold=%b dut=%b", g._49433_.Q, d.payload_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49434_.Q !== d.payload_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26666 gold=%b dut=%b", g._49434_.Q, d.payload_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49435_.Q !== d.payload_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26667 gold=%b dut=%b", g._49435_.Q, d.payload_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49436_.Q !== d.payload_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26668 gold=%b dut=%b", g._49436_.Q, d.payload_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49437_.Q !== d.payload_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26669 gold=%b dut=%b", g._49437_.Q, d.payload_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49438_.Q !== d.payload_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26670 gold=%b dut=%b", g._49438_.Q, d.payload_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49439_.Q !== d.payload_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26671 gold=%b dut=%b", g._49439_.Q, d.payload_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49440_.Q !== d.payload_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26672 gold=%b dut=%b", g._49440_.Q, d.payload_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49441_.Q !== d.payload_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26673 gold=%b dut=%b", g._49441_.Q, d.payload_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49442_.Q !== d.payload_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26674 gold=%b dut=%b", g._49442_.Q, d.payload_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49443_.Q !== d.payload_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26675 gold=%b dut=%b", g._49443_.Q, d.payload_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49444_.Q !== d.payload_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26676 gold=%b dut=%b", g._49444_.Q, d.payload_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49445_.Q !== d.payload_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26677 gold=%b dut=%b", g._49445_.Q, d.payload_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49446_.Q !== d.payload_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26678 gold=%b dut=%b", g._49446_.Q, d.payload_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49447_.Q !== d.unnamed_26679) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26679 gold=%b dut=%b", g._49447_.Q, d.unnamed_26679);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49384_.Q !== d.data_word_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26680 gold=%b dut=%b", g._49384_.Q, d.data_word_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49385_.Q !== d.data_word_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26681 gold=%b dut=%b", g._49385_.Q, d.data_word_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49386_.Q !== d.data_word_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26682 gold=%b dut=%b", g._49386_.Q, d.data_word_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49387_.Q !== d.data_word_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26683 gold=%b dut=%b", g._49387_.Q, d.data_word_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49388_.Q !== d.data_word_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26684 gold=%b dut=%b", g._49388_.Q, d.data_word_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49389_.Q !== d.data_word_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26685 gold=%b dut=%b", g._49389_.Q, d.data_word_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49390_.Q !== d.data_word_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26686 gold=%b dut=%b", g._49390_.Q, d.data_word_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49391_.Q !== d.data_word_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26687 gold=%b dut=%b", g._49391_.Q, d.data_word_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49392_.Q !== d.data_word_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26688 gold=%b dut=%b", g._49392_.Q, d.data_word_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49393_.Q !== d.data_word_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26689 gold=%b dut=%b", g._49393_.Q, d.data_word_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49394_.Q !== d.data_word_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26690 gold=%b dut=%b", g._49394_.Q, d.data_word_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49395_.Q !== d.data_word_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26691 gold=%b dut=%b", g._49395_.Q, d.data_word_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49396_.Q !== d.data_word_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26692 gold=%b dut=%b", g._49396_.Q, d.data_word_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49397_.Q !== d.data_word_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26693 gold=%b dut=%b", g._49397_.Q, d.data_word_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49398_.Q !== d.data_word_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26694 gold=%b dut=%b", g._49398_.Q, d.data_word_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49399_.Q !== d.data_word_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26695 gold=%b dut=%b", g._49399_.Q, d.data_word_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49400_.Q !== d.data_word_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26696 gold=%b dut=%b", g._49400_.Q, d.data_word_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49401_.Q !== d.data_word_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26697 gold=%b dut=%b", g._49401_.Q, d.data_word_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49402_.Q !== d.data_word_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26698 gold=%b dut=%b", g._49402_.Q, d.data_word_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49403_.Q !== d.data_word_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26699 gold=%b dut=%b", g._49403_.Q, d.data_word_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49404_.Q !== d.data_word_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26700 gold=%b dut=%b", g._49404_.Q, d.data_word_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49405_.Q !== d.data_word_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26701 gold=%b dut=%b", g._49405_.Q, d.data_word_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49406_.Q !== d.data_word_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26702 gold=%b dut=%b", g._49406_.Q, d.data_word_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49407_.Q !== d.data_word_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26703 gold=%b dut=%b", g._49407_.Q, d.data_word_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49408_.Q !== d.data_word_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26704 gold=%b dut=%b", g._49408_.Q, d.data_word_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49409_.Q !== d.data_word_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26705 gold=%b dut=%b", g._49409_.Q, d.data_word_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49410_.Q !== d.data_word_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26706 gold=%b dut=%b", g._49410_.Q, d.data_word_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49411_.Q !== d.data_word_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26707 gold=%b dut=%b", g._49411_.Q, d.data_word_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49412_.Q !== d.data_word_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26708 gold=%b dut=%b", g._49412_.Q, d.data_word_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49413_.Q !== d.data_word_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26709 gold=%b dut=%b", g._49413_.Q, d.data_word_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49414_.Q !== d.data_word_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26710 gold=%b dut=%b", g._49414_.Q, d.data_word_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49415_.Q !== d.data_word_1[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26711 gold=%b dut=%b", g._49415_.Q, d.data_word_1[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49352_.Q !== d.wide_data_reg_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26712 gold=%b dut=%b", g._49352_.Q, d.wide_data_reg_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49353_.Q !== d.wide_data_reg_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26713 gold=%b dut=%b", g._49353_.Q, d.wide_data_reg_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49354_.Q !== d.wide_data_reg_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26714 gold=%b dut=%b", g._49354_.Q, d.wide_data_reg_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49355_.Q !== d.wide_data_reg_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26715 gold=%b dut=%b", g._49355_.Q, d.wide_data_reg_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49356_.Q !== d.wide_data_reg_4[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26716 gold=%b dut=%b", g._49356_.Q, d.wide_data_reg_4[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49357_.Q !== d.wide_data_reg_4[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26717 gold=%b dut=%b", g._49357_.Q, d.wide_data_reg_4[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49358_.Q !== d.wide_data_reg_4[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26718 gold=%b dut=%b", g._49358_.Q, d.wide_data_reg_4[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49359_.Q !== d.wide_data_reg_4[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26719 gold=%b dut=%b", g._49359_.Q, d.wide_data_reg_4[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49360_.Q !== d.wide_data_reg_4[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26720 gold=%b dut=%b", g._49360_.Q, d.wide_data_reg_4[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49361_.Q !== d.wide_data_reg_4[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26721 gold=%b dut=%b", g._49361_.Q, d.wide_data_reg_4[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49362_.Q !== d.wide_data_reg_4[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26722 gold=%b dut=%b", g._49362_.Q, d.wide_data_reg_4[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49363_.Q !== d.wide_data_reg_4[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26723 gold=%b dut=%b", g._49363_.Q, d.wide_data_reg_4[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49364_.Q !== d.wide_data_reg_4[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26724 gold=%b dut=%b", g._49364_.Q, d.wide_data_reg_4[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49365_.Q !== d.wide_data_reg_4[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26725 gold=%b dut=%b", g._49365_.Q, d.wide_data_reg_4[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49366_.Q !== d.wide_data_reg_4[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26726 gold=%b dut=%b", g._49366_.Q, d.wide_data_reg_4[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49367_.Q !== d.wide_data_reg_4[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26727 gold=%b dut=%b", g._49367_.Q, d.wide_data_reg_4[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49368_.Q !== d.wide_data_reg_4[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26728 gold=%b dut=%b", g._49368_.Q, d.wide_data_reg_4[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49369_.Q !== d.wide_data_reg_4[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26729 gold=%b dut=%b", g._49369_.Q, d.wide_data_reg_4[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49370_.Q !== d.wide_data_reg_4[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26730 gold=%b dut=%b", g._49370_.Q, d.wide_data_reg_4[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49371_.Q !== d.wide_data_reg_4[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26731 gold=%b dut=%b", g._49371_.Q, d.wide_data_reg_4[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49372_.Q !== d.wide_data_reg_4[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26732 gold=%b dut=%b", g._49372_.Q, d.wide_data_reg_4[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49373_.Q !== d.wide_data_reg_4[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26733 gold=%b dut=%b", g._49373_.Q, d.wide_data_reg_4[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49374_.Q !== d.wide_data_reg_4[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26734 gold=%b dut=%b", g._49374_.Q, d.wide_data_reg_4[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49375_.Q !== d.wide_data_reg_4[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26735 gold=%b dut=%b", g._49375_.Q, d.wide_data_reg_4[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49376_.Q !== d.wide_data_reg_4[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26736 gold=%b dut=%b", g._49376_.Q, d.wide_data_reg_4[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49377_.Q !== d.wide_data_reg_4[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26737 gold=%b dut=%b", g._49377_.Q, d.wide_data_reg_4[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49378_.Q !== d.wide_data_reg_4[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26738 gold=%b dut=%b", g._49378_.Q, d.wide_data_reg_4[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49379_.Q !== d.wide_data_reg_4[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26739 gold=%b dut=%b", g._49379_.Q, d.wide_data_reg_4[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49380_.Q !== d.wide_data_reg_4[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26740 gold=%b dut=%b", g._49380_.Q, d.wide_data_reg_4[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49381_.Q !== d.wide_data_reg_4[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26741 gold=%b dut=%b", g._49381_.Q, d.wide_data_reg_4[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49382_.Q !== d.status_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26742 gold=%b dut=%b", g._49382_.Q, d.status_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49383_.Q !== d.status_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26743 gold=%b dut=%b", g._49383_.Q, d.status_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49841_.Q !== d.data_reg_21[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26778 gold=%b dut=%b", g._49841_.Q, d.data_reg_21[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49842_.Q !== d.data_reg_21[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26779 gold=%b dut=%b", g._49842_.Q, d.data_reg_21[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49843_.Q !== d.data_reg_21[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26780 gold=%b dut=%b", g._49843_.Q, d.data_reg_21[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49844_.Q !== d.data_reg_21[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26781 gold=%b dut=%b", g._49844_.Q, d.data_reg_21[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49845_.Q !== d.data_reg_21[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26782 gold=%b dut=%b", g._49845_.Q, d.data_reg_21[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49846_.Q !== d.data_reg_21[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26783 gold=%b dut=%b", g._49846_.Q, d.data_reg_21[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49847_.Q !== d.data_reg_21[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26784 gold=%b dut=%b", g._49847_.Q, d.data_reg_21[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49848_.Q !== d.data_reg_21[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26785 gold=%b dut=%b", g._49848_.Q, d.data_reg_21[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49849_.Q !== d.data_reg_21[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26786 gold=%b dut=%b", g._49849_.Q, d.data_reg_21[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49850_.Q !== d.data_reg_21[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26787 gold=%b dut=%b", g._49850_.Q, d.data_reg_21[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49851_.Q !== d.data_reg_21[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26788 gold=%b dut=%b", g._49851_.Q, d.data_reg_21[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49852_.Q !== d.data_reg_21[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26789 gold=%b dut=%b", g._49852_.Q, d.data_reg_21[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49853_.Q !== d.data_reg_21[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26790 gold=%b dut=%b", g._49853_.Q, d.data_reg_21[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49854_.Q !== d.data_reg_21[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26791 gold=%b dut=%b", g._49854_.Q, d.data_reg_21[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49855_.Q !== d.data_reg_21[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26792 gold=%b dut=%b", g._49855_.Q, d.data_reg_21[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49856_.Q !== d.data_reg_21[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26793 gold=%b dut=%b", g._49856_.Q, d.data_reg_21[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49857_.Q !== d.data_reg_21[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26794 gold=%b dut=%b", g._49857_.Q, d.data_reg_21[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49858_.Q !== d.data_reg_21[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26795 gold=%b dut=%b", g._49858_.Q, d.data_reg_21[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49859_.Q !== d.data_reg_21[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26796 gold=%b dut=%b", g._49859_.Q, d.data_reg_21[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49860_.Q !== d.data_reg_21[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26797 gold=%b dut=%b", g._49860_.Q, d.data_reg_21[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49861_.Q !== d.data_reg_21[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26798 gold=%b dut=%b", g._49861_.Q, d.data_reg_21[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49862_.Q !== d.unnamed_26799[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26799 gold=%b dut=%b", g._49862_.Q, d.unnamed_26799[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49863_.Q !== d.unnamed_26799[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26800 gold=%b dut=%b", g._49863_.Q, d.unnamed_26799[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49864_.Q !== d.unnamed_26799[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26801 gold=%b dut=%b", g._49864_.Q, d.unnamed_26799[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49865_.Q !== d.unnamed_26799[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26802 gold=%b dut=%b", g._49865_.Q, d.unnamed_26799[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49866_.Q !== d.unnamed_26799[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26803 gold=%b dut=%b", g._49866_.Q, d.unnamed_26799[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49867_.Q !== d.unnamed_26799[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26804 gold=%b dut=%b", g._49867_.Q, d.unnamed_26799[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49868_.Q !== d.unnamed_26799[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26805 gold=%b dut=%b", g._49868_.Q, d.unnamed_26799[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49869_.Q !== d.unnamed_26799[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26806 gold=%b dut=%b", g._49869_.Q, d.unnamed_26799[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49870_.Q !== d.unnamed_26799[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26807 gold=%b dut=%b", g._49870_.Q, d.unnamed_26799[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49840_.Q !== d.status_flag_5) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26808 gold=%b dut=%b", g._49840_.Q, d.status_flag_5);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49839_.Q !== d.mode_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26842 gold=%b dut=%b", g._49839_.Q, d.mode_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49871_.Q !== d.unnamed_26843[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26843 gold=%b dut=%b", g._49871_.Q, d.unnamed_26843[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49872_.Q !== d.unnamed_26843[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26844 gold=%b dut=%b", g._49872_.Q, d.unnamed_26843[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49873_.Q !== d.unnamed_26843[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26845 gold=%b dut=%b", g._49873_.Q, d.unnamed_26843[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49874_.Q !== d.unnamed_26843[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26846 gold=%b dut=%b", g._49874_.Q, d.unnamed_26843[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49875_.Q !== d.unnamed_26843[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26847 gold=%b dut=%b", g._49875_.Q, d.unnamed_26843[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49876_.Q !== d.unnamed_26843[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26848 gold=%b dut=%b", g._49876_.Q, d.unnamed_26843[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49877_.Q !== d.unnamed_26843[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26849 gold=%b dut=%b", g._49877_.Q, d.unnamed_26843[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49878_.Q !== d.unnamed_26843[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26850 gold=%b dut=%b", g._49878_.Q, d.unnamed_26843[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49879_.Q !== d.unnamed_26843[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26851 gold=%b dut=%b", g._49879_.Q, d.unnamed_26843[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49880_.Q !== d.unnamed_26843[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26852 gold=%b dut=%b", g._49880_.Q, d.unnamed_26843[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49881_.Q !== d.unnamed_26843[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26853 gold=%b dut=%b", g._49881_.Q, d.unnamed_26843[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49882_.Q !== d.unnamed_26843[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26854 gold=%b dut=%b", g._49882_.Q, d.unnamed_26843[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49883_.Q !== d.unnamed_26843[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26855 gold=%b dut=%b", g._49883_.Q, d.unnamed_26843[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49884_.Q !== d.unnamed_26843[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26856 gold=%b dut=%b", g._49884_.Q, d.unnamed_26843[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49885_.Q !== d.unnamed_26843[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26857 gold=%b dut=%b", g._49885_.Q, d.unnamed_26843[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49886_.Q !== d.unnamed_26843[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26858 gold=%b dut=%b", g._49886_.Q, d.unnamed_26843[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49887_.Q !== d.unnamed_26843[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26859 gold=%b dut=%b", g._49887_.Q, d.unnamed_26843[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49888_.Q !== d.unnamed_26843[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26860 gold=%b dut=%b", g._49888_.Q, d.unnamed_26843[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49889_.Q !== d.unnamed_26843[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26861 gold=%b dut=%b", g._49889_.Q, d.unnamed_26843[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49890_.Q !== d.unnamed_26843[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26862 gold=%b dut=%b", g._49890_.Q, d.unnamed_26843[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49891_.Q !== d.unnamed_26843[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26863 gold=%b dut=%b", g._49891_.Q, d.unnamed_26843[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49892_.Q !== d.unnamed_26843[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26864 gold=%b dut=%b", g._49892_.Q, d.unnamed_26843[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49893_.Q !== d.unnamed_26843[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26865 gold=%b dut=%b", g._49893_.Q, d.unnamed_26843[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49894_.Q !== d.unnamed_26843[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26866 gold=%b dut=%b", g._49894_.Q, d.unnamed_26843[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49895_.Q !== d.unnamed_26843[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26867 gold=%b dut=%b", g._49895_.Q, d.unnamed_26843[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49896_.Q !== d.unnamed_26843[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26868 gold=%b dut=%b", g._49896_.Q, d.unnamed_26843[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49897_.Q !== d.unnamed_26843[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26869 gold=%b dut=%b", g._49897_.Q, d.unnamed_26843[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49898_.Q !== d.unnamed_26843[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26870 gold=%b dut=%b", g._49898_.Q, d.unnamed_26843[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49899_.Q !== d.unnamed_26843[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26871 gold=%b dut=%b", g._49899_.Q, d.unnamed_26843[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49900_.Q !== d.unnamed_26843[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26872 gold=%b dut=%b", g._49900_.Q, d.unnamed_26843[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49901_.Q !== d.unnamed_26843[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26873 gold=%b dut=%b", g._49901_.Q, d.unnamed_26843[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49902_.Q !== d.mux_sample_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26874 gold=%b dut=%b", g._49902_.Q, d.mux_sample_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49903_.Q !== d.mux_sample_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26875 gold=%b dut=%b", g._49903_.Q, d.mux_sample_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49904_.Q !== d.mux_sample_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26876 gold=%b dut=%b", g._49904_.Q, d.mux_sample_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49905_.Q !== d.mux_sample_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26877 gold=%b dut=%b", g._49905_.Q, d.mux_sample_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49906_.Q !== d.mux_sample_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26878 gold=%b dut=%b", g._49906_.Q, d.mux_sample_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50487_.Q !== d.status_flag_6) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26879 gold=%b dut=%b", g._50487_.Q, d.status_flag_6);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49300_.Q !== d.decoded_select_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26880 gold=%b dut=%b", g._49300_.Q, d.decoded_select_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49301_.Q !== d.decoded_select_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26881 gold=%b dut=%b", g._49301_.Q, d.decoded_select_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49302_.Q !== d.decoded_select_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26882 gold=%b dut=%b", g._49302_.Q, d.decoded_select_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49303_.Q !== d.decoded_select_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26883 gold=%b dut=%b", g._49303_.Q, d.decoded_select_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49304_.Q !== d.decoded_select_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26884 gold=%b dut=%b", g._49304_.Q, d.decoded_select_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49305_.Q !== d.decoded_select_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26885 gold=%b dut=%b", g._49305_.Q, d.decoded_select_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49307_.Q !== d.decoded_select_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26886 gold=%b dut=%b", g._49307_.Q, d.decoded_select_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49308_.Q !== d.decoded_select_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26887 gold=%b dut=%b", g._49308_.Q, d.decoded_select_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49309_.Q !== d.decoded_select_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26888 gold=%b dut=%b", g._49309_.Q, d.decoded_select_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49310_.Q !== d.decoded_select_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26889 gold=%b dut=%b", g._49310_.Q, d.decoded_select_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49311_.Q !== d.decoded_select_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26890 gold=%b dut=%b", g._49311_.Q, d.decoded_select_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49312_.Q !== d.decoded_select_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26891 gold=%b dut=%b", g._49312_.Q, d.decoded_select_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49313_.Q !== d.decoded_select_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26892 gold=%b dut=%b", g._49313_.Q, d.decoded_select_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49314_.Q !== d.decoded_select_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26893 gold=%b dut=%b", g._49314_.Q, d.decoded_select_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49315_.Q !== d.decoded_select_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26894 gold=%b dut=%b", g._49315_.Q, d.decoded_select_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49316_.Q !== d.decoded_select_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26895 gold=%b dut=%b", g._49316_.Q, d.decoded_select_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49318_.Q !== d.decoded_select_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26896 gold=%b dut=%b", g._49318_.Q, d.decoded_select_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49319_.Q !== d.decoded_select_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26897 gold=%b dut=%b", g._49319_.Q, d.decoded_select_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49320_.Q !== d.decoded_select_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26898 gold=%b dut=%b", g._49320_.Q, d.decoded_select_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49321_.Q !== d.decoded_select_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26899 gold=%b dut=%b", g._49321_.Q, d.decoded_select_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49322_.Q !== d.decoded_select_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26900 gold=%b dut=%b", g._49322_.Q, d.decoded_select_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49323_.Q !== d.decoded_select_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26901 gold=%b dut=%b", g._49323_.Q, d.decoded_select_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49324_.Q !== d.decoded_select_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26902 gold=%b dut=%b", g._49324_.Q, d.decoded_select_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49325_.Q !== d.decoded_select_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26903 gold=%b dut=%b", g._49325_.Q, d.decoded_select_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49326_.Q !== d.decoded_select_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26904 gold=%b dut=%b", g._49326_.Q, d.decoded_select_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49327_.Q !== d.decoded_select_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26905 gold=%b dut=%b", g._49327_.Q, d.decoded_select_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49329_.Q !== d.decoded_select_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26906 gold=%b dut=%b", g._49329_.Q, d.decoded_select_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49330_.Q !== d.decoded_select_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26907 gold=%b dut=%b", g._49330_.Q, d.decoded_select_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49331_.Q !== d.decoded_select_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26908 gold=%b dut=%b", g._49331_.Q, d.decoded_select_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49332_.Q !== d.decoded_select_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26909 gold=%b dut=%b", g._49332_.Q, d.decoded_select_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49295_.Q !== d.control_flag_5) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26910 gold=%b dut=%b", g._49295_.Q, d.control_flag_5);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50481_.Q !== d.datapath_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26912 gold=%b dut=%b", g._50481_.Q, d.datapath_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50482_.Q !== d.datapath_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26913 gold=%b dut=%b", g._50482_.Q, d.datapath_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50483_.Q !== d.datapath_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26914 gold=%b dut=%b", g._50483_.Q, d.datapath_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50476_.Q !== d.datapath_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26915 gold=%b dut=%b", g._50476_.Q, d.datapath_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50480_.Q !== d.datapath_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26916 gold=%b dut=%b", g._50480_.Q, d.datapath_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50484_.Q !== d.datapath_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26917 gold=%b dut=%b", g._50484_.Q, d.datapath_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50485_.Q !== d.datapath_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26918 gold=%b dut=%b", g._50485_.Q, d.datapath_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50478_.Q !== d.datapath_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26919 gold=%b dut=%b", g._50478_.Q, d.datapath_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50479_.Q !== d.datapath_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26920 gold=%b dut=%b", g._50479_.Q, d.datapath_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50486_.Q !== d.datapath_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26921 gold=%b dut=%b", g._50486_.Q, d.datapath_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50475_.Q !== d.datapath_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26922 gold=%b dut=%b", g._50475_.Q, d.datapath_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50467_.Q !== d.datapath_flags[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26923 gold=%b dut=%b", g._50467_.Q, d.datapath_flags[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50468_.Q !== d.datapath_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26924 gold=%b dut=%b", g._50468_.Q, d.datapath_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50469_.Q !== d.datapath_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26925 gold=%b dut=%b", g._50469_.Q, d.datapath_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50470_.Q !== d.datapath_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26926 gold=%b dut=%b", g._50470_.Q, d.datapath_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50471_.Q !== d.datapath_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26927 gold=%b dut=%b", g._50471_.Q, d.datapath_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50472_.Q !== d.datapath_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26928 gold=%b dut=%b", g._50472_.Q, d.datapath_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50473_.Q !== d.datapath_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26929 gold=%b dut=%b", g._50473_.Q, d.datapath_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50474_.Q !== d.datapath_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26930 gold=%b dut=%b", g._50474_.Q, d.datapath_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50477_.Q !== d.datapath_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26942 gold=%b dut=%b", g._50477_.Q, d.datapath_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50499_.Q !== d.result_condition_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26943 gold=%b dut=%b", g._50499_.Q, d.result_condition_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50500_.Q !== d.result_condition_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26944 gold=%b dut=%b", g._50500_.Q, d.result_condition_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50501_.Q !== d.result_condition_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26945 gold=%b dut=%b", g._50501_.Q, d.result_condition_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50502_.Q !== d.control_state_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26946 gold=%b dut=%b", g._50502_.Q, d.control_state_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50503_.Q !== d.control_state_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26947 gold=%b dut=%b", g._50503_.Q, d.control_state_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50493_.Q !== d.result_condition_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26955 gold=%b dut=%b", g._50493_.Q, d.result_condition_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50494_.Q !== d.result_condition_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26956 gold=%b dut=%b", g._50494_.Q, d.result_condition_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50495_.Q !== d.result_condition_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26957 gold=%b dut=%b", g._50495_.Q, d.result_condition_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50496_.Q !== d.result_condition_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26958 gold=%b dut=%b", g._50496_.Q, d.result_condition_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50497_.Q !== d.result_condition_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26959 gold=%b dut=%b", g._50497_.Q, d.result_condition_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50498_.Q !== d.result_condition_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26960 gold=%b dut=%b", g._50498_.Q, d.result_condition_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50488_.Q !== d.result_condition_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26961 gold=%b dut=%b", g._50488_.Q, d.result_condition_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50489_.Q !== d.result_condition_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26962 gold=%b dut=%b", g._50489_.Q, d.result_condition_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50490_.Q !== d.result_condition_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26963 gold=%b dut=%b", g._50490_.Q, d.result_condition_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50491_.Q !== d.result_condition_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26964 gold=%b dut=%b", g._50491_.Q, d.result_condition_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50492_.Q !== d.result_condition_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26965 gold=%b dut=%b", g._50492_.Q, d.result_condition_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49673_.Q !== d.fsm_state_bit_0) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26966 gold=%b dut=%b", g._49673_.Q, d.fsm_state_bit_0);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48310_.Q !== d.compare_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26967 gold=%b dut=%b", g._48310_.Q, d.compare_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50004_.Q !== d.zero_pattern_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26968 gold=%b dut=%b", g._50004_.Q, d.zero_pattern_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49930_.Q !== d.event_delay_shift[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26969 gold=%b dut=%b", g._49930_.Q, d.event_delay_shift[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50543_.Q !== d.data_reg_7_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26975 gold=%b dut=%b", g._50543_.Q, d.data_reg_7_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50544_.Q !== d.data_reg_7_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26976 gold=%b dut=%b", g._50544_.Q, d.data_reg_7_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50545_.Q !== d.data_reg_7_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26977 gold=%b dut=%b", g._50545_.Q, d.data_reg_7_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50546_.Q !== d.data_reg_7_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26978 gold=%b dut=%b", g._50546_.Q, d.data_reg_7_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50547_.Q !== d.data_reg_7_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26979 gold=%b dut=%b", g._50547_.Q, d.data_reg_7_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50548_.Q !== d.data_reg_7_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26980 gold=%b dut=%b", g._50548_.Q, d.data_reg_7_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50549_.Q !== d.data_reg_7_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26981 gold=%b dut=%b", g._50549_.Q, d.data_reg_7_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50550_.Q !== d.data_reg_5_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26982 gold=%b dut=%b", g._50550_.Q, d.data_reg_5_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50551_.Q !== d.data_reg_5_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26983 gold=%b dut=%b", g._50551_.Q, d.data_reg_5_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50552_.Q !== d.data_reg_5_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26984 gold=%b dut=%b", g._50552_.Q, d.data_reg_5_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50553_.Q !== d.data_reg_5_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26985 gold=%b dut=%b", g._50553_.Q, d.data_reg_5_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50554_.Q !== d.data_reg_5_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26986 gold=%b dut=%b", g._50554_.Q, d.data_reg_5_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50555_.Q !== d.data_reg_3_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26987 gold=%b dut=%b", g._50555_.Q, d.data_reg_3_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50556_.Q !== d.data_reg_3_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26988 gold=%b dut=%b", g._50556_.Q, d.data_reg_3_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50557_.Q !== d.data_reg_3_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26989 gold=%b dut=%b", g._50557_.Q, d.data_reg_3_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50558_.Q !== d.data_reg_10_0[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26990 gold=%b dut=%b", g._50558_.Q, d.data_reg_10_0[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50559_.Q !== d.data_reg_10_0[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26991 gold=%b dut=%b", g._50559_.Q, d.data_reg_10_0[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50560_.Q !== d.data_reg_10_0[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26992 gold=%b dut=%b", g._50560_.Q, d.data_reg_10_0[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50561_.Q !== d.data_reg_10_0[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26993 gold=%b dut=%b", g._50561_.Q, d.data_reg_10_0[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50562_.Q !== d.data_reg_10_0[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26994 gold=%b dut=%b", g._50562_.Q, d.data_reg_10_0[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50563_.Q !== d.data_reg_10_0[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26995 gold=%b dut=%b", g._50563_.Q, d.data_reg_10_0[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50564_.Q !== d.data_reg_10_0[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26996 gold=%b dut=%b", g._50564_.Q, d.data_reg_10_0[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50565_.Q !== d.data_reg_10_0[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26997 gold=%b dut=%b", g._50565_.Q, d.data_reg_10_0[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50566_.Q !== d.data_reg_10_0[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26998 gold=%b dut=%b", g._50566_.Q, d.data_reg_10_0[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50567_.Q !== d.data_reg_10_0[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=26999 gold=%b dut=%b", g._50567_.Q, d.data_reg_10_0[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50568_.Q !== d.data_reg_7_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27000 gold=%b dut=%b", g._50568_.Q, d.data_reg_7_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50569_.Q !== d.data_reg_7_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27001 gold=%b dut=%b", g._50569_.Q, d.data_reg_7_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50570_.Q !== d.data_reg_7_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27002 gold=%b dut=%b", g._50570_.Q, d.data_reg_7_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50571_.Q !== d.data_reg_7_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27003 gold=%b dut=%b", g._50571_.Q, d.data_reg_7_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50572_.Q !== d.data_reg_7_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27004 gold=%b dut=%b", g._50572_.Q, d.data_reg_7_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50573_.Q !== d.data_reg_7_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27005 gold=%b dut=%b", g._50573_.Q, d.data_reg_7_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50574_.Q !== d.data_reg_7_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27006 gold=%b dut=%b", g._50574_.Q, d.data_reg_7_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49674_.Q !== d.fsm_state_bit_1) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27072 gold=%b dut=%b", g._49674_.Q, d.fsm_state_bit_1);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48423_.Q !== d.unnamed_27075[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27075 gold=%b dut=%b", g._48423_.Q, d.unnamed_27075[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48424_.Q !== d.unnamed_27075[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27076 gold=%b dut=%b", g._48424_.Q, d.unnamed_27075[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48425_.Q !== d.unnamed_27075[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27077 gold=%b dut=%b", g._48425_.Q, d.unnamed_27075[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48426_.Q !== d.unnamed_27075[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27078 gold=%b dut=%b", g._48426_.Q, d.unnamed_27075[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48427_.Q !== d.unnamed_27075[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27079 gold=%b dut=%b", g._48427_.Q, d.unnamed_27075[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48428_.Q !== d.unnamed_27075[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27080 gold=%b dut=%b", g._48428_.Q, d.unnamed_27075[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48429_.Q !== d.unnamed_27075[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27081 gold=%b dut=%b", g._48429_.Q, d.unnamed_27075[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48430_.Q !== d.unnamed_27075[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27082 gold=%b dut=%b", g._48430_.Q, d.unnamed_27075[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48431_.Q !== d.unnamed_27075[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27083 gold=%b dut=%b", g._48431_.Q, d.unnamed_27075[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48432_.Q !== d.unnamed_27075[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27084 gold=%b dut=%b", g._48432_.Q, d.unnamed_27075[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48433_.Q !== d.unnamed_27075[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27085 gold=%b dut=%b", g._48433_.Q, d.unnamed_27075[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48434_.Q !== d.unnamed_27075[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27086 gold=%b dut=%b", g._48434_.Q, d.unnamed_27075[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48435_.Q !== d.unnamed_27075[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27087 gold=%b dut=%b", g._48435_.Q, d.unnamed_27075[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48436_.Q !== d.unnamed_27075[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27088 gold=%b dut=%b", g._48436_.Q, d.unnamed_27075[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48437_.Q !== d.unnamed_27075[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27089 gold=%b dut=%b", g._48437_.Q, d.unnamed_27075[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48438_.Q !== d.unnamed_27075[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27090 gold=%b dut=%b", g._48438_.Q, d.unnamed_27075[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48439_.Q !== d.unnamed_27075[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27091 gold=%b dut=%b", g._48439_.Q, d.unnamed_27075[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48440_.Q !== d.unnamed_27075[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27092 gold=%b dut=%b", g._48440_.Q, d.unnamed_27075[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48441_.Q !== d.unnamed_27075[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27093 gold=%b dut=%b", g._48441_.Q, d.unnamed_27075[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48442_.Q !== d.unnamed_27075[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27094 gold=%b dut=%b", g._48442_.Q, d.unnamed_27075[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48443_.Q !== d.unnamed_27075[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27095 gold=%b dut=%b", g._48443_.Q, d.unnamed_27075[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48444_.Q !== d.unnamed_27075[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27096 gold=%b dut=%b", g._48444_.Q, d.unnamed_27075[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48445_.Q !== d.unnamed_27075[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27097 gold=%b dut=%b", g._48445_.Q, d.unnamed_27075[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48446_.Q !== d.unnamed_27075[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27098 gold=%b dut=%b", g._48446_.Q, d.unnamed_27075[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48447_.Q !== d.unnamed_27075[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27099 gold=%b dut=%b", g._48447_.Q, d.unnamed_27075[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48448_.Q !== d.unnamed_27075[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27100 gold=%b dut=%b", g._48448_.Q, d.unnamed_27075[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48449_.Q !== d.unnamed_27075[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27101 gold=%b dut=%b", g._48449_.Q, d.unnamed_27075[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48450_.Q !== d.unnamed_27075[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27102 gold=%b dut=%b", g._48450_.Q, d.unnamed_27075[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48451_.Q !== d.unnamed_27075[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27103 gold=%b dut=%b", g._48451_.Q, d.unnamed_27075[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48452_.Q !== d.unnamed_27075[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27104 gold=%b dut=%b", g._48452_.Q, d.unnamed_27075[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48453_.Q !== d.unnamed_27075[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27105 gold=%b dut=%b", g._48453_.Q, d.unnamed_27075[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48454_.Q !== d.unnamed_27075[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27106 gold=%b dut=%b", g._48454_.Q, d.unnamed_27075[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48455_.Q !== d.unnamed_27075[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27107 gold=%b dut=%b", g._48455_.Q, d.unnamed_27075[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48456_.Q !== d.unnamed_27075[33]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27108 gold=%b dut=%b", g._48456_.Q, d.unnamed_27075[33]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48457_.Q !== d.unnamed_27075[34]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27109 gold=%b dut=%b", g._48457_.Q, d.unnamed_27075[34]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48458_.Q !== d.unnamed_27075[35]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27110 gold=%b dut=%b", g._48458_.Q, d.unnamed_27075[35]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48459_.Q !== d.unnamed_27075[36]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27111 gold=%b dut=%b", g._48459_.Q, d.unnamed_27075[36]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48460_.Q !== d.unnamed_27075[37]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27112 gold=%b dut=%b", g._48460_.Q, d.unnamed_27075[37]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48461_.Q !== d.unnamed_27075[38]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27113 gold=%b dut=%b", g._48461_.Q, d.unnamed_27075[38]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48462_.Q !== d.control_state_5[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27114 gold=%b dut=%b", g._48462_.Q, d.control_state_5[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48463_.Q !== d.control_state_5[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27115 gold=%b dut=%b", g._48463_.Q, d.control_state_5[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48464_.Q !== d.control_state_5[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27116 gold=%b dut=%b", g._48464_.Q, d.control_state_5[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48465_.Q !== d.control_state_5[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27117 gold=%b dut=%b", g._48465_.Q, d.control_state_5[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48466_.Q !== d.control_state_5[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27118 gold=%b dut=%b", g._48466_.Q, d.control_state_5[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48467_.Q !== d.control_state_5[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27119 gold=%b dut=%b", g._48467_.Q, d.control_state_5[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48468_.Q !== d.control_state_5[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27120 gold=%b dut=%b", g._48468_.Q, d.control_state_5[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48469_.Q !== d.control_state_5[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27121 gold=%b dut=%b", g._48469_.Q, d.control_state_5[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48470_.Q !== d.control_state_5[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27122 gold=%b dut=%b", g._48470_.Q, d.control_state_5[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48471_.Q !== d.control_state_5[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27123 gold=%b dut=%b", g._48471_.Q, d.control_state_5[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48472_.Q !== d.control_state_5[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27124 gold=%b dut=%b", g._48472_.Q, d.control_state_5[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48473_.Q !== d.control_state_5[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27125 gold=%b dut=%b", g._48473_.Q, d.control_state_5[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48474_.Q !== d.control_state_5[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27126 gold=%b dut=%b", g._48474_.Q, d.control_state_5[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48475_.Q !== d.control_state_5[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27127 gold=%b dut=%b", g._48475_.Q, d.control_state_5[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48476_.Q !== d.control_state_5[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27128 gold=%b dut=%b", g._48476_.Q, d.control_state_5[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48477_.Q !== d.control_state_5[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27129 gold=%b dut=%b", g._48477_.Q, d.control_state_5[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48478_.Q !== d.control_state_5[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27130 gold=%b dut=%b", g._48478_.Q, d.control_state_5[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48479_.Q !== d.control_state_5[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27131 gold=%b dut=%b", g._48479_.Q, d.control_state_5[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48480_.Q !== d.control_state_5[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27132 gold=%b dut=%b", g._48480_.Q, d.control_state_5[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48481_.Q !== d.control_state_5[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27133 gold=%b dut=%b", g._48481_.Q, d.control_state_5[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48482_.Q !== d.control_state_5[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27134 gold=%b dut=%b", g._48482_.Q, d.control_state_5[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48483_.Q !== d.control_state_5[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27135 gold=%b dut=%b", g._48483_.Q, d.control_state_5[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48484_.Q !== d.control_state_5[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27136 gold=%b dut=%b", g._48484_.Q, d.control_state_5[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48485_.Q !== d.control_state_5[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27137 gold=%b dut=%b", g._48485_.Q, d.control_state_5[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48486_.Q !== d.control_state_5[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27138 gold=%b dut=%b", g._48486_.Q, d.control_state_5[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49965_.Q !== d.data_word_a[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27140 gold=%b dut=%b", g._49965_.Q, d.data_word_a[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49966_.Q !== d.data_word_a[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27141 gold=%b dut=%b", g._49966_.Q, d.data_word_a[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49967_.Q !== d.data_word_a[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27142 gold=%b dut=%b", g._49967_.Q, d.data_word_a[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49968_.Q !== d.data_word_a[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27143 gold=%b dut=%b", g._49968_.Q, d.data_word_a[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49969_.Q !== d.data_word_a[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27144 gold=%b dut=%b", g._49969_.Q, d.data_word_a[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49970_.Q !== d.data_word_a[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27145 gold=%b dut=%b", g._49970_.Q, d.data_word_a[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49971_.Q !== d.data_word_a[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27146 gold=%b dut=%b", g._49971_.Q, d.data_word_a[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49972_.Q !== d.data_word_a[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27147 gold=%b dut=%b", g._49972_.Q, d.data_word_a[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49973_.Q !== d.data_word_a[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27148 gold=%b dut=%b", g._49973_.Q, d.data_word_a[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49974_.Q !== d.data_word_a[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27149 gold=%b dut=%b", g._49974_.Q, d.data_word_a[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49975_.Q !== d.data_word_a[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27150 gold=%b dut=%b", g._49975_.Q, d.data_word_a[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49976_.Q !== d.data_word_a[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27151 gold=%b dut=%b", g._49976_.Q, d.data_word_a[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49977_.Q !== d.data_word_a[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27152 gold=%b dut=%b", g._49977_.Q, d.data_word_a[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49978_.Q !== d.data_word_a[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27153 gold=%b dut=%b", g._49978_.Q, d.data_word_a[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49979_.Q !== d.data_word_a[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27154 gold=%b dut=%b", g._49979_.Q, d.data_word_a[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49980_.Q !== d.data_word_a[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27155 gold=%b dut=%b", g._49980_.Q, d.data_word_a[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49981_.Q !== d.data_word_a[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27156 gold=%b dut=%b", g._49981_.Q, d.data_word_a[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49982_.Q !== d.data_word_a[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27157 gold=%b dut=%b", g._49982_.Q, d.data_word_a[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49983_.Q !== d.data_word_a[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27158 gold=%b dut=%b", g._49983_.Q, d.data_word_a[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49984_.Q !== d.data_word_a[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27159 gold=%b dut=%b", g._49984_.Q, d.data_word_a[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49985_.Q !== d.data_word_a[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27160 gold=%b dut=%b", g._49985_.Q, d.data_word_a[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49986_.Q !== d.data_word_a[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27161 gold=%b dut=%b", g._49986_.Q, d.data_word_a[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49987_.Q !== d.data_word_a[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27162 gold=%b dut=%b", g._49987_.Q, d.data_word_a[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49988_.Q !== d.data_word_a[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27163 gold=%b dut=%b", g._49988_.Q, d.data_word_a[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49989_.Q !== d.data_word_a[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27164 gold=%b dut=%b", g._49989_.Q, d.data_word_a[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49990_.Q !== d.data_word_a[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27165 gold=%b dut=%b", g._49990_.Q, d.data_word_a[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49991_.Q !== d.data_word_a[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27166 gold=%b dut=%b", g._49991_.Q, d.data_word_a[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49992_.Q !== d.data_word_a[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27167 gold=%b dut=%b", g._49992_.Q, d.data_word_a[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49993_.Q !== d.data_word_a[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27168 gold=%b dut=%b", g._49993_.Q, d.data_word_a[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49994_.Q !== d.data_word_a[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27169 gold=%b dut=%b", g._49994_.Q, d.data_word_a[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49995_.Q !== d.data_word_a[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27170 gold=%b dut=%b", g._49995_.Q, d.data_word_a[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49996_.Q !== d.data_word_a[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27171 gold=%b dut=%b", g._49996_.Q, d.data_word_a[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49997_.Q !== d.data_word_a[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27172 gold=%b dut=%b", g._49997_.Q, d.data_word_a[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49932_.Q !== d.input_capture_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27173 gold=%b dut=%b", g._49932_.Q, d.input_capture_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49933_.Q !== d.input_capture_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27174 gold=%b dut=%b", g._49933_.Q, d.input_capture_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49934_.Q !== d.input_capture_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27175 gold=%b dut=%b", g._49934_.Q, d.input_capture_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49935_.Q !== d.input_capture_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27176 gold=%b dut=%b", g._49935_.Q, d.input_capture_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49936_.Q !== d.input_capture_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27177 gold=%b dut=%b", g._49936_.Q, d.input_capture_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49937_.Q !== d.input_capture_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27178 gold=%b dut=%b", g._49937_.Q, d.input_capture_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49938_.Q !== d.input_capture_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27179 gold=%b dut=%b", g._49938_.Q, d.input_capture_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49939_.Q !== d.input_capture_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27180 gold=%b dut=%b", g._49939_.Q, d.input_capture_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49940_.Q !== d.input_capture_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27181 gold=%b dut=%b", g._49940_.Q, d.input_capture_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49941_.Q !== d.input_capture_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27182 gold=%b dut=%b", g._49941_.Q, d.input_capture_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49942_.Q !== d.input_capture_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27183 gold=%b dut=%b", g._49942_.Q, d.input_capture_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49943_.Q !== d.input_capture_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27184 gold=%b dut=%b", g._49943_.Q, d.input_capture_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49944_.Q !== d.input_capture_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27185 gold=%b dut=%b", g._49944_.Q, d.input_capture_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49945_.Q !== d.input_capture_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27186 gold=%b dut=%b", g._49945_.Q, d.input_capture_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49946_.Q !== d.input_capture_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27187 gold=%b dut=%b", g._49946_.Q, d.input_capture_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49947_.Q !== d.input_capture_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27188 gold=%b dut=%b", g._49947_.Q, d.input_capture_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49948_.Q !== d.input_capture_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27189 gold=%b dut=%b", g._49948_.Q, d.input_capture_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49949_.Q !== d.input_capture_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27190 gold=%b dut=%b", g._49949_.Q, d.input_capture_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49950_.Q !== d.input_capture_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27191 gold=%b dut=%b", g._49950_.Q, d.input_capture_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49951_.Q !== d.input_capture_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27192 gold=%b dut=%b", g._49951_.Q, d.input_capture_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49952_.Q !== d.input_capture_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27193 gold=%b dut=%b", g._49952_.Q, d.input_capture_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49953_.Q !== d.input_capture_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27194 gold=%b dut=%b", g._49953_.Q, d.input_capture_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49954_.Q !== d.input_capture_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27195 gold=%b dut=%b", g._49954_.Q, d.input_capture_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49955_.Q !== d.input_capture_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27196 gold=%b dut=%b", g._49955_.Q, d.input_capture_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49956_.Q !== d.input_capture_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27197 gold=%b dut=%b", g._49956_.Q, d.input_capture_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49957_.Q !== d.input_capture_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27198 gold=%b dut=%b", g._49957_.Q, d.input_capture_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49958_.Q !== d.input_capture_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27199 gold=%b dut=%b", g._49958_.Q, d.input_capture_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49959_.Q !== d.input_capture_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27200 gold=%b dut=%b", g._49959_.Q, d.input_capture_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49960_.Q !== d.input_capture_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27201 gold=%b dut=%b", g._49960_.Q, d.input_capture_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49961_.Q !== d.input_capture_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27202 gold=%b dut=%b", g._49961_.Q, d.input_capture_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49962_.Q !== d.input_capture_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27203 gold=%b dut=%b", g._49962_.Q, d.input_capture_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49963_.Q !== d.input_capture_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27204 gold=%b dut=%b", g._49963_.Q, d.input_capture_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49964_.Q !== d.data_word_b_msb_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27205 gold=%b dut=%b", g._49964_.Q, d.data_word_b_msb_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48422_.Q !== d.unnamed_27206) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27206 gold=%b dut=%b", g._48422_.Q, d.unnamed_27206);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50023_.Q !== d.compare_data_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27208 gold=%b dut=%b", g._50023_.Q, d.compare_data_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50024_.Q !== d.compare_data_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27209 gold=%b dut=%b", g._50024_.Q, d.compare_data_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50025_.Q !== d.compare_data_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27210 gold=%b dut=%b", g._50025_.Q, d.compare_data_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50026_.Q !== d.compare_data_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27211 gold=%b dut=%b", g._50026_.Q, d.compare_data_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50027_.Q !== d.compare_data_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27212 gold=%b dut=%b", g._50027_.Q, d.compare_data_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50028_.Q !== d.compare_data_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27213 gold=%b dut=%b", g._50028_.Q, d.compare_data_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50029_.Q !== d.compare_data_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27214 gold=%b dut=%b", g._50029_.Q, d.compare_data_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50030_.Q !== d.compare_data_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27215 gold=%b dut=%b", g._50030_.Q, d.compare_data_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50031_.Q !== d.compare_data_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27216 gold=%b dut=%b", g._50031_.Q, d.compare_data_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50032_.Q !== d.compare_data_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27217 gold=%b dut=%b", g._50032_.Q, d.compare_data_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50033_.Q !== d.compare_data_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27218 gold=%b dut=%b", g._50033_.Q, d.compare_data_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50034_.Q !== d.compare_data_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27219 gold=%b dut=%b", g._50034_.Q, d.compare_data_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50035_.Q !== d.compare_data_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27220 gold=%b dut=%b", g._50035_.Q, d.compare_data_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50036_.Q !== d.compare_data_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27221 gold=%b dut=%b", g._50036_.Q, d.compare_data_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50037_.Q !== d.compare_data_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27222 gold=%b dut=%b", g._50037_.Q, d.compare_data_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50038_.Q !== d.compare_data_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27223 gold=%b dut=%b", g._50038_.Q, d.compare_data_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50039_.Q !== d.compare_data_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27224 gold=%b dut=%b", g._50039_.Q, d.compare_data_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50040_.Q !== d.compare_data_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27225 gold=%b dut=%b", g._50040_.Q, d.compare_data_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50041_.Q !== d.compare_data_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27226 gold=%b dut=%b", g._50041_.Q, d.compare_data_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50042_.Q !== d.compare_data_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27227 gold=%b dut=%b", g._50042_.Q, d.compare_data_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50043_.Q !== d.compare_data_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27228 gold=%b dut=%b", g._50043_.Q, d.compare_data_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50044_.Q !== d.compare_data_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27229 gold=%b dut=%b", g._50044_.Q, d.compare_data_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50045_.Q !== d.compare_data_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27230 gold=%b dut=%b", g._50045_.Q, d.compare_data_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50046_.Q !== d.compare_data_register[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27231 gold=%b dut=%b", g._50046_.Q, d.compare_data_register[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50047_.Q !== d.compare_data_register[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27232 gold=%b dut=%b", g._50047_.Q, d.compare_data_register[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50048_.Q !== d.compare_data_register[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27233 gold=%b dut=%b", g._50048_.Q, d.compare_data_register[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50049_.Q !== d.compare_data_register[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27234 gold=%b dut=%b", g._50049_.Q, d.compare_data_register[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50050_.Q !== d.compare_data_register[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27235 gold=%b dut=%b", g._50050_.Q, d.compare_data_register[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50051_.Q !== d.compare_data_register[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27236 gold=%b dut=%b", g._50051_.Q, d.compare_data_register[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50052_.Q !== d.compare_data_register[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27237 gold=%b dut=%b", g._50052_.Q, d.compare_data_register[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50053_.Q !== d.compare_data_register[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27238 gold=%b dut=%b", g._50053_.Q, d.compare_data_register[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50054_.Q !== d.compare_data_register[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27239 gold=%b dut=%b", g._50054_.Q, d.compare_data_register[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49707_.Q !== d.unnamed_27240[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27240 gold=%b dut=%b", g._49707_.Q, d.unnamed_27240[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49708_.Q !== d.unnamed_27240[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27241 gold=%b dut=%b", g._49708_.Q, d.unnamed_27240[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49709_.Q !== d.unnamed_27240[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27242 gold=%b dut=%b", g._49709_.Q, d.unnamed_27240[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49710_.Q !== d.unnamed_27240[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27243 gold=%b dut=%b", g._49710_.Q, d.unnamed_27240[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49711_.Q !== d.unnamed_27240[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27244 gold=%b dut=%b", g._49711_.Q, d.unnamed_27240[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49712_.Q !== d.unnamed_27240[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27245 gold=%b dut=%b", g._49712_.Q, d.unnamed_27240[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49713_.Q !== d.unnamed_27240[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27246 gold=%b dut=%b", g._49713_.Q, d.unnamed_27240[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49714_.Q !== d.unnamed_27240[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27247 gold=%b dut=%b", g._49714_.Q, d.unnamed_27240[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49715_.Q !== d.unnamed_27240[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27248 gold=%b dut=%b", g._49715_.Q, d.unnamed_27240[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49716_.Q !== d.unnamed_27240[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27249 gold=%b dut=%b", g._49716_.Q, d.unnamed_27240[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49717_.Q !== d.unnamed_27240[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27250 gold=%b dut=%b", g._49717_.Q, d.unnamed_27240[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49718_.Q !== d.unnamed_27240[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27251 gold=%b dut=%b", g._49718_.Q, d.unnamed_27240[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49719_.Q !== d.unnamed_27240[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27252 gold=%b dut=%b", g._49719_.Q, d.unnamed_27240[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49720_.Q !== d.unnamed_27240[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27253 gold=%b dut=%b", g._49720_.Q, d.unnamed_27240[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49721_.Q !== d.unnamed_27240[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27254 gold=%b dut=%b", g._49721_.Q, d.unnamed_27240[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49722_.Q !== d.unnamed_27240[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27255 gold=%b dut=%b", g._49722_.Q, d.unnamed_27240[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49723_.Q !== d.unnamed_27240[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27256 gold=%b dut=%b", g._49723_.Q, d.unnamed_27240[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49724_.Q !== d.unnamed_27240[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27257 gold=%b dut=%b", g._49724_.Q, d.unnamed_27240[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49725_.Q !== d.unnamed_27240[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27258 gold=%b dut=%b", g._49725_.Q, d.unnamed_27240[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49726_.Q !== d.unnamed_27240[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27259 gold=%b dut=%b", g._49726_.Q, d.unnamed_27240[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49727_.Q !== d.unnamed_27240[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27260 gold=%b dut=%b", g._49727_.Q, d.unnamed_27240[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49728_.Q !== d.unnamed_27240[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27261 gold=%b dut=%b", g._49728_.Q, d.unnamed_27240[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49729_.Q !== d.unnamed_27240[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27262 gold=%b dut=%b", g._49729_.Q, d.unnamed_27240[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49730_.Q !== d.unnamed_27240[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27263 gold=%b dut=%b", g._49730_.Q, d.unnamed_27240[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49731_.Q !== d.unnamed_27240[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27264 gold=%b dut=%b", g._49731_.Q, d.unnamed_27240[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49732_.Q !== d.unnamed_27240[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27265 gold=%b dut=%b", g._49732_.Q, d.unnamed_27240[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49733_.Q !== d.unnamed_27240[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27266 gold=%b dut=%b", g._49733_.Q, d.unnamed_27240[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49734_.Q !== d.unnamed_27240[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27267 gold=%b dut=%b", g._49734_.Q, d.unnamed_27240[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49735_.Q !== d.unnamed_27240[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27268 gold=%b dut=%b", g._49735_.Q, d.unnamed_27240[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49736_.Q !== d.unnamed_27240[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27269 gold=%b dut=%b", g._49736_.Q, d.unnamed_27240[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49737_.Q !== d.unnamed_27240[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27270 gold=%b dut=%b", g._49737_.Q, d.unnamed_27240[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49675_.Q !== d.wide_data_reg_5[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27271 gold=%b dut=%b", g._49675_.Q, d.wide_data_reg_5[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49676_.Q !== d.wide_data_reg_5[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27272 gold=%b dut=%b", g._49676_.Q, d.wide_data_reg_5[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49677_.Q !== d.wide_data_reg_5[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27273 gold=%b dut=%b", g._49677_.Q, d.wide_data_reg_5[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49678_.Q !== d.wide_data_reg_5[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27274 gold=%b dut=%b", g._49678_.Q, d.wide_data_reg_5[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49679_.Q !== d.wide_data_reg_5[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27275 gold=%b dut=%b", g._49679_.Q, d.wide_data_reg_5[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49680_.Q !== d.wide_data_reg_5[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27276 gold=%b dut=%b", g._49680_.Q, d.wide_data_reg_5[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49681_.Q !== d.wide_data_reg_5[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27277 gold=%b dut=%b", g._49681_.Q, d.wide_data_reg_5[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49682_.Q !== d.wide_data_reg_5[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27278 gold=%b dut=%b", g._49682_.Q, d.wide_data_reg_5[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49683_.Q !== d.wide_data_reg_5[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27279 gold=%b dut=%b", g._49683_.Q, d.wide_data_reg_5[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49684_.Q !== d.wide_data_reg_5[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27280 gold=%b dut=%b", g._49684_.Q, d.wide_data_reg_5[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49685_.Q !== d.wide_data_reg_5[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27281 gold=%b dut=%b", g._49685_.Q, d.wide_data_reg_5[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49686_.Q !== d.wide_data_reg_5[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27282 gold=%b dut=%b", g._49686_.Q, d.wide_data_reg_5[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49687_.Q !== d.wide_data_reg_5[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27283 gold=%b dut=%b", g._49687_.Q, d.wide_data_reg_5[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49688_.Q !== d.wide_data_reg_5[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27284 gold=%b dut=%b", g._49688_.Q, d.wide_data_reg_5[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49689_.Q !== d.wide_data_reg_5[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27285 gold=%b dut=%b", g._49689_.Q, d.wide_data_reg_5[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49690_.Q !== d.wide_data_reg_5[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27286 gold=%b dut=%b", g._49690_.Q, d.wide_data_reg_5[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49691_.Q !== d.wide_data_reg_5[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27287 gold=%b dut=%b", g._49691_.Q, d.wide_data_reg_5[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49692_.Q !== d.wide_data_reg_5[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27288 gold=%b dut=%b", g._49692_.Q, d.wide_data_reg_5[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49693_.Q !== d.wide_data_reg_5[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27289 gold=%b dut=%b", g._49693_.Q, d.wide_data_reg_5[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49694_.Q !== d.wide_data_reg_5[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27290 gold=%b dut=%b", g._49694_.Q, d.wide_data_reg_5[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49695_.Q !== d.wide_data_reg_5[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27291 gold=%b dut=%b", g._49695_.Q, d.wide_data_reg_5[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49696_.Q !== d.wide_data_reg_5[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27292 gold=%b dut=%b", g._49696_.Q, d.wide_data_reg_5[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49697_.Q !== d.wide_data_reg_5[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27293 gold=%b dut=%b", g._49697_.Q, d.wide_data_reg_5[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49698_.Q !== d.wide_data_reg_5[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27294 gold=%b dut=%b", g._49698_.Q, d.wide_data_reg_5[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49699_.Q !== d.wide_data_reg_5[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27295 gold=%b dut=%b", g._49699_.Q, d.wide_data_reg_5[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49700_.Q !== d.wide_data_reg_5[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27296 gold=%b dut=%b", g._49700_.Q, d.wide_data_reg_5[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49701_.Q !== d.wide_data_reg_5[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27297 gold=%b dut=%b", g._49701_.Q, d.wide_data_reg_5[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49702_.Q !== d.unnamed_27298[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27298 gold=%b dut=%b", g._49702_.Q, d.unnamed_27298[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49703_.Q !== d.unnamed_27298[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27299 gold=%b dut=%b", g._49703_.Q, d.unnamed_27298[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49704_.Q !== d.unnamed_27298[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27300 gold=%b dut=%b", g._49704_.Q, d.unnamed_27298[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49705_.Q !== d.unnamed_27298[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27301 gold=%b dut=%b", g._49705_.Q, d.unnamed_27298[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49706_.Q !== d.unnamed_27298[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27302 gold=%b dut=%b", g._49706_.Q, d.unnamed_27298[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50001_.Q !== d.compare_done_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27303 gold=%b dut=%b", g._50001_.Q, d.compare_done_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50161_.Q !== d.done_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27304 gold=%b dut=%b", g._50161_.Q, d.done_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50128_.Q !== d.event_pulse_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27305 gold=%b dut=%b", g._50128_.Q, d.event_pulse_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50022_.Q !== d.decode_match_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27306 gold=%b dut=%b", g._50022_.Q, d.decode_match_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49910_.Q !== d.parity_or_activity_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27307 gold=%b dut=%b", g._49910_.Q, d.parity_or_activity_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48383_.Q !== d.control_flag_27439) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27439 gold=%b dut=%b", g._48383_.Q, d.control_flag_27439);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49738_.Q !== d.unnamed_27441[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27441 gold=%b dut=%b", g._49738_.Q, d.unnamed_27441[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49739_.Q !== d.unnamed_27441[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27442 gold=%b dut=%b", g._49739_.Q, d.unnamed_27441[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49740_.Q !== d.unnamed_27441[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27443 gold=%b dut=%b", g._49740_.Q, d.unnamed_27441[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49741_.Q !== d.unnamed_27441[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27444 gold=%b dut=%b", g._49741_.Q, d.unnamed_27441[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49742_.Q !== d.compare_match_data[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27445 gold=%b dut=%b", g._49742_.Q, d.compare_match_data[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49743_.Q !== d.compare_match_data[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27446 gold=%b dut=%b", g._49743_.Q, d.compare_match_data[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49744_.Q !== d.compare_match_data[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27447 gold=%b dut=%b", g._49744_.Q, d.compare_match_data[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49745_.Q !== d.compare_match_data[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27448 gold=%b dut=%b", g._49745_.Q, d.compare_match_data[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49746_.Q !== d.compare_match_data[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27449 gold=%b dut=%b", g._49746_.Q, d.compare_match_data[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49747_.Q !== d.compare_match_data[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27450 gold=%b dut=%b", g._49747_.Q, d.compare_match_data[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49748_.Q !== d.compare_match_data[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27451 gold=%b dut=%b", g._49748_.Q, d.compare_match_data[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49749_.Q !== d.compare_match_data[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27452 gold=%b dut=%b", g._49749_.Q, d.compare_match_data[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49750_.Q !== d.compare_match_data[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27453 gold=%b dut=%b", g._49750_.Q, d.compare_match_data[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49751_.Q !== d.compare_match_data[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27454 gold=%b dut=%b", g._49751_.Q, d.compare_match_data[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49752_.Q !== d.compare_match_data[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27455 gold=%b dut=%b", g._49752_.Q, d.compare_match_data[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49753_.Q !== d.compare_match_data[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27456 gold=%b dut=%b", g._49753_.Q, d.compare_match_data[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49754_.Q !== d.compare_match_data[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27457 gold=%b dut=%b", g._49754_.Q, d.compare_match_data[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49755_.Q !== d.compare_match_data[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27458 gold=%b dut=%b", g._49755_.Q, d.compare_match_data[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49756_.Q !== d.compare_match_data[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27459 gold=%b dut=%b", g._49756_.Q, d.compare_match_data[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49757_.Q !== d.compare_match_data[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27460 gold=%b dut=%b", g._49757_.Q, d.compare_match_data[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49758_.Q !== d.compare_match_data[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27461 gold=%b dut=%b", g._49758_.Q, d.compare_match_data[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49759_.Q !== d.compare_match_data[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27462 gold=%b dut=%b", g._49759_.Q, d.compare_match_data[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49760_.Q !== d.compare_match_data[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27463 gold=%b dut=%b", g._49760_.Q, d.compare_match_data[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49761_.Q !== d.compare_match_data[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27464 gold=%b dut=%b", g._49761_.Q, d.compare_match_data[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49762_.Q !== d.compare_match_data[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27465 gold=%b dut=%b", g._49762_.Q, d.compare_match_data[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49763_.Q !== d.compare_match_data[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27466 gold=%b dut=%b", g._49763_.Q, d.compare_match_data[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49764_.Q !== d.compare_match_data[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27467 gold=%b dut=%b", g._49764_.Q, d.compare_match_data[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49765_.Q !== d.compare_match_data[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27468 gold=%b dut=%b", g._49765_.Q, d.compare_match_data[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49766_.Q !== d.compare_match_data[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27469 gold=%b dut=%b", g._49766_.Q, d.compare_match_data[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49767_.Q !== d.compare_match_data[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27470 gold=%b dut=%b", g._49767_.Q, d.compare_match_data[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49768_.Q !== d.compare_match_data[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27471 gold=%b dut=%b", g._49768_.Q, d.compare_match_data[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49769_.Q !== d.compare_match_data[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27472 gold=%b dut=%b", g._49769_.Q, d.compare_match_data[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49772_.Q !== d.pending_vector[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27473 gold=%b dut=%b", g._49772_.Q, d.pending_vector[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49773_.Q !== d.pending_vector[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27474 gold=%b dut=%b", g._49773_.Q, d.pending_vector[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49774_.Q !== d.pending_vector[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27475 gold=%b dut=%b", g._49774_.Q, d.pending_vector[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49775_.Q !== d.pending_vector[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27476 gold=%b dut=%b", g._49775_.Q, d.pending_vector[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49776_.Q !== d.pending_vector[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27477 gold=%b dut=%b", g._49776_.Q, d.pending_vector[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49777_.Q !== d.pending_vector[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27478 gold=%b dut=%b", g._49777_.Q, d.pending_vector[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49778_.Q !== d.pending_vector[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27479 gold=%b dut=%b", g._49778_.Q, d.pending_vector[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49779_.Q !== d.pending_vector[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27480 gold=%b dut=%b", g._49779_.Q, d.pending_vector[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49780_.Q !== d.pending_vector[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27481 gold=%b dut=%b", g._49780_.Q, d.pending_vector[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49781_.Q !== d.pending_vector[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27482 gold=%b dut=%b", g._49781_.Q, d.pending_vector[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49782_.Q !== d.pending_vector[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27483 gold=%b dut=%b", g._49782_.Q, d.pending_vector[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49783_.Q !== d.pending_vector[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27484 gold=%b dut=%b", g._49783_.Q, d.pending_vector[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49784_.Q !== d.pending_vector[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27485 gold=%b dut=%b", g._49784_.Q, d.pending_vector[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49785_.Q !== d.pending_vector[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27486 gold=%b dut=%b", g._49785_.Q, d.pending_vector[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49786_.Q !== d.pending_vector[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27487 gold=%b dut=%b", g._49786_.Q, d.pending_vector[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49787_.Q !== d.pending_vector[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27488 gold=%b dut=%b", g._49787_.Q, d.pending_vector[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49788_.Q !== d.pending_vector[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27489 gold=%b dut=%b", g._49788_.Q, d.pending_vector[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49789_.Q !== d.pending_vector[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27490 gold=%b dut=%b", g._49789_.Q, d.pending_vector[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49790_.Q !== d.pending_vector[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27491 gold=%b dut=%b", g._49790_.Q, d.pending_vector[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49791_.Q !== d.pending_vector[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27492 gold=%b dut=%b", g._49791_.Q, d.pending_vector[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49792_.Q !== d.pending_vector[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27493 gold=%b dut=%b", g._49792_.Q, d.pending_vector[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49793_.Q !== d.pending_vector[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27494 gold=%b dut=%b", g._49793_.Q, d.pending_vector[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49794_.Q !== d.pending_vector[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27495 gold=%b dut=%b", g._49794_.Q, d.pending_vector[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49795_.Q !== d.pending_vector[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27496 gold=%b dut=%b", g._49795_.Q, d.pending_vector[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49796_.Q !== d.pending_vector[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27497 gold=%b dut=%b", g._49796_.Q, d.pending_vector[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49797_.Q !== d.pending_vector[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27498 gold=%b dut=%b", g._49797_.Q, d.pending_vector[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49798_.Q !== d.pending_vector[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27499 gold=%b dut=%b", g._49798_.Q, d.pending_vector[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49799_.Q !== d.pending_vector[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27500 gold=%b dut=%b", g._49799_.Q, d.pending_vector[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49800_.Q !== d.pending_vector[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27501 gold=%b dut=%b", g._49800_.Q, d.pending_vector[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49801_.Q !== d.pending_vector[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27502 gold=%b dut=%b", g._49801_.Q, d.pending_vector[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49802_.Q !== d.pending_vector[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27503 gold=%b dut=%b", g._49802_.Q, d.pending_vector[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49803_.Q !== d.pending_vector[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27504 gold=%b dut=%b", g._49803_.Q, d.pending_vector[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49805_.Q !== d.pending_vector[32]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27506 gold=%b dut=%b", g._49805_.Q, d.pending_vector[32]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50525_.Q !== d.regfile_bit25_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27507 gold=%b dut=%b", g._50525_.Q, d.regfile_bit25_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50534_.Q !== d.regfile_bit24_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27508 gold=%b dut=%b", g._50534_.Q, d.regfile_bit24_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50516_.Q !== d.regfile_bit25_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27509 gold=%b dut=%b", g._50516_.Q, d.regfile_bit25_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50529_.Q !== d.regfile_bit24_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27510 gold=%b dut=%b", g._50529_.Q, d.regfile_bit24_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50535_.Q !== d.control_state_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27511 gold=%b dut=%b", g._50535_.Q, d.control_state_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49909_.Q !== d.decoded_status_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27512 gold=%b dut=%b", g._49909_.Q, d.decoded_status_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49999_.Q !== d.mode_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27513 gold=%b dut=%b", g._49999_.Q, d.mode_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49998_.Q !== d.mode_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27514 gold=%b dut=%b", g._49998_.Q, d.mode_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49929_.Q !== d.decoded_status_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27515 gold=%b dut=%b", g._49929_.Q, d.decoded_status_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50458_.Q !== d.latched_condition_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27516 gold=%b dut=%b", g._50458_.Q, d.latched_condition_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49771_.Q !== d.condition_latch) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27517 gold=%b dut=%b", g._49771_.Q, d.condition_latch);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50511_.Q !== d.event_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27518 gold=%b dut=%b", g._50511_.Q, d.event_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50510_.Q !== d.event_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27519 gold=%b dut=%b", g._50510_.Q, d.event_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50509_.Q !== d.decoded_status_low[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27520 gold=%b dut=%b", g._50509_.Q, d.decoded_status_low[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49770_.Q !== d.control_flag_6) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27521 gold=%b dut=%b", g._49770_.Q, d.control_flag_6);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49804_.Q !== d.fsm_state_3) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27522 gold=%b dut=%b", g._49804_.Q, d.fsm_state_3);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50463_.Q !== d.control_state_6[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27523 gold=%b dut=%b", g._50463_.Q, d.control_state_6[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50540_.Q !== d.regfile_bit29_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27524 gold=%b dut=%b", g._50540_.Q, d.regfile_bit29_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50542_.Q !== d.status_flag_7) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27525 gold=%b dut=%b", g._50542_.Q, d.status_flag_7);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50539_.Q !== d.regfile_bit29_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27526 gold=%b dut=%b", g._50539_.Q, d.regfile_bit29_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50127_.Q !== d.control_state_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27527 gold=%b dut=%b", g._50127_.Q, d.control_state_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50541_.Q !== d.regfile_bit29_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27528 gold=%b dut=%b", g._50541_.Q, d.regfile_bit29_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50506_.Q !== d.decoded_status_low[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27529 gold=%b dut=%b", g._50506_.Q, d.decoded_status_low[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50517_.Q !== d.regfile_bit25_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27530 gold=%b dut=%b", g._50517_.Q, d.regfile_bit25_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50530_.Q !== d.regfile_bit24_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27531 gold=%b dut=%b", g._50530_.Q, d.regfile_bit24_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50515_.Q !== d.decoded_status_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27532 gold=%b dut=%b", g._50515_.Q, d.decoded_status_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50514_.Q !== d.decoded_status_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27533 gold=%b dut=%b", g._50514_.Q, d.decoded_status_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50513_.Q !== d.decoded_status_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27534 gold=%b dut=%b", g._50513_.Q, d.decoded_status_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50512_.Q !== d.decoded_status_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27535 gold=%b dut=%b", g._50512_.Q, d.decoded_status_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50507_.Q !== d.control_state_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27536 gold=%b dut=%b", g._50507_.Q, d.control_state_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50538_.Q !== d.regfile_bit33_slice[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27537 gold=%b dut=%b", g._50538_.Q, d.regfile_bit33_slice[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50508_.Q !== d.decoded_status_low[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27538 gold=%b dut=%b", g._50508_.Q, d.decoded_status_low[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50537_.Q !== d.regfile_bit33_slice[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27539 gold=%b dut=%b", g._50537_.Q, d.regfile_bit33_slice[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50523_.Q !== d.regfile_bit25_slice[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27540 gold=%b dut=%b", g._50523_.Q, d.regfile_bit25_slice[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50528_.Q !== d.regfile_bit24_slice[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27541 gold=%b dut=%b", g._50528_.Q, d.regfile_bit24_slice[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50522_.Q !== d.regfile_bit25_slice[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27542 gold=%b dut=%b", g._50522_.Q, d.regfile_bit25_slice[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50533_.Q !== d.regfile_bit24_slice[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27543 gold=%b dut=%b", g._50533_.Q, d.regfile_bit24_slice[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50532_.Q !== d.regfile_bit24_slice[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27544 gold=%b dut=%b", g._50532_.Q, d.regfile_bit24_slice[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50521_.Q !== d.regfile_bit25_slice[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27545 gold=%b dut=%b", g._50521_.Q, d.regfile_bit25_slice[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50518_.Q !== d.regfile_bit25_slice[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27546 gold=%b dut=%b", g._50518_.Q, d.regfile_bit25_slice[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50526_.Q !== d.regfile_bit24_slice[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27547 gold=%b dut=%b", g._50526_.Q, d.regfile_bit24_slice[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50519_.Q !== d.regfile_bit25_slice[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27548 gold=%b dut=%b", g._50519_.Q, d.regfile_bit25_slice[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50527_.Q !== d.regfile_bit24_slice[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27549 gold=%b dut=%b", g._50527_.Q, d.regfile_bit24_slice[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50524_.Q !== d.regfile_bit25_slice[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27550 gold=%b dut=%b", g._50524_.Q, d.regfile_bit25_slice[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50536_.Q !== d.regfile_bit33_slice[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27551 gold=%b dut=%b", g._50536_.Q, d.regfile_bit33_slice[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50504_.Q !== d.decoded_status_low[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27552 gold=%b dut=%b", g._50504_.Q, d.decoded_status_low[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50505_.Q !== d.control_state_4[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27553 gold=%b dut=%b", g._50505_.Q, d.control_state_4[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50520_.Q !== d.regfile_bit25_slice[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27554 gold=%b dut=%b", g._50520_.Q, d.regfile_bit25_slice[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50531_.Q !== d.regfile_bit24_slice[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27555 gold=%b dut=%b", g._50531_.Q, d.regfile_bit24_slice[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50125_.Q !== d.sticky_control_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27556 gold=%b dut=%b", g._50125_.Q, d.sticky_control_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50126_.Q !== d.completion_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27557 gold=%b dut=%b", g._50126_.Q, d.completion_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50093_.Q !== d.low_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27558 gold=%b dut=%b", g._50093_.Q, d.low_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50094_.Q !== d.low_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27559 gold=%b dut=%b", g._50094_.Q, d.low_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50095_.Q !== d.low_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27560 gold=%b dut=%b", g._50095_.Q, d.low_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50096_.Q !== d.low_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27561 gold=%b dut=%b", g._50096_.Q, d.low_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50097_.Q !== d.low_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27562 gold=%b dut=%b", g._50097_.Q, d.low_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50098_.Q !== d.low_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27563 gold=%b dut=%b", g._50098_.Q, d.low_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50099_.Q !== d.low_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27564 gold=%b dut=%b", g._50099_.Q, d.low_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50100_.Q !== d.low_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27565 gold=%b dut=%b", g._50100_.Q, d.low_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50101_.Q !== d.low_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27566 gold=%b dut=%b", g._50101_.Q, d.low_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50102_.Q !== d.low_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27567 gold=%b dut=%b", g._50102_.Q, d.low_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50103_.Q !== d.low_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27568 gold=%b dut=%b", g._50103_.Q, d.low_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50104_.Q !== d.low_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27569 gold=%b dut=%b", g._50104_.Q, d.low_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50105_.Q !== d.low_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27570 gold=%b dut=%b", g._50105_.Q, d.low_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50106_.Q !== d.low_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27571 gold=%b dut=%b", g._50106_.Q, d.low_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50107_.Q !== d.low_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27572 gold=%b dut=%b", g._50107_.Q, d.low_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50108_.Q !== d.low_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27573 gold=%b dut=%b", g._50108_.Q, d.low_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50109_.Q !== d.low_data_reg[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27574 gold=%b dut=%b", g._50109_.Q, d.low_data_reg[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50110_.Q !== d.low_data_reg[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27575 gold=%b dut=%b", g._50110_.Q, d.low_data_reg[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50111_.Q !== d.low_data_reg[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27576 gold=%b dut=%b", g._50111_.Q, d.low_data_reg[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50112_.Q !== d.low_data_reg[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27577 gold=%b dut=%b", g._50112_.Q, d.low_data_reg[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50113_.Q !== d.low_data_reg[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27578 gold=%b dut=%b", g._50113_.Q, d.low_data_reg[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50114_.Q !== d.low_data_reg[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27579 gold=%b dut=%b", g._50114_.Q, d.low_data_reg[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50115_.Q !== d.low_data_reg[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27580 gold=%b dut=%b", g._50115_.Q, d.low_data_reg[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50116_.Q !== d.low_data_reg[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27581 gold=%b dut=%b", g._50116_.Q, d.low_data_reg[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50117_.Q !== d.low_data_reg[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27582 gold=%b dut=%b", g._50117_.Q, d.low_data_reg[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50118_.Q !== d.low_data_reg[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27583 gold=%b dut=%b", g._50118_.Q, d.low_data_reg[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50119_.Q !== d.low_data_reg[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27584 gold=%b dut=%b", g._50119_.Q, d.low_data_reg[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50120_.Q !== d.low_data_reg[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27585 gold=%b dut=%b", g._50120_.Q, d.low_data_reg[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50121_.Q !== d.low_data_reg[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27586 gold=%b dut=%b", g._50121_.Q, d.low_data_reg[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50122_.Q !== d.low_data_reg[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27587 gold=%b dut=%b", g._50122_.Q, d.low_data_reg[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50123_.Q !== d.low_data_reg[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27588 gold=%b dut=%b", g._50123_.Q, d.low_data_reg[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50124_.Q !== d.low_data_reg[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27589 gold=%b dut=%b", g._50124_.Q, d.low_data_reg[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48319_.Q !== d.buffer_register[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27590 gold=%b dut=%b", g._48319_.Q, d.buffer_register[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48320_.Q !== d.buffer_register[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27591 gold=%b dut=%b", g._48320_.Q, d.buffer_register[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48321_.Q !== d.buffer_register[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27592 gold=%b dut=%b", g._48321_.Q, d.buffer_register[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48322_.Q !== d.buffer_register[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27593 gold=%b dut=%b", g._48322_.Q, d.buffer_register[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48323_.Q !== d.buffer_register[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27594 gold=%b dut=%b", g._48323_.Q, d.buffer_register[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48324_.Q !== d.buffer_register[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27595 gold=%b dut=%b", g._48324_.Q, d.buffer_register[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48325_.Q !== d.buffer_register[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27596 gold=%b dut=%b", g._48325_.Q, d.buffer_register[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48326_.Q !== d.buffer_register[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27597 gold=%b dut=%b", g._48326_.Q, d.buffer_register[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48327_.Q !== d.buffer_register[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27598 gold=%b dut=%b", g._48327_.Q, d.buffer_register[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48328_.Q !== d.buffer_register[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27599 gold=%b dut=%b", g._48328_.Q, d.buffer_register[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48329_.Q !== d.buffer_register[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27600 gold=%b dut=%b", g._48329_.Q, d.buffer_register[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48330_.Q !== d.buffer_register[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27601 gold=%b dut=%b", g._48330_.Q, d.buffer_register[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48331_.Q !== d.buffer_register[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27602 gold=%b dut=%b", g._48331_.Q, d.buffer_register[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48332_.Q !== d.buffer_register[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27603 gold=%b dut=%b", g._48332_.Q, d.buffer_register[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48333_.Q !== d.buffer_register[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27604 gold=%b dut=%b", g._48333_.Q, d.buffer_register[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48334_.Q !== d.buffer_register[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27605 gold=%b dut=%b", g._48334_.Q, d.buffer_register[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48335_.Q !== d.buffer_register[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27606 gold=%b dut=%b", g._48335_.Q, d.buffer_register[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48336_.Q !== d.buffer_register[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27607 gold=%b dut=%b", g._48336_.Q, d.buffer_register[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48337_.Q !== d.buffer_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27608 gold=%b dut=%b", g._48337_.Q, d.buffer_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48338_.Q !== d.buffer_register[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27609 gold=%b dut=%b", g._48338_.Q, d.buffer_register[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48339_.Q !== d.buffer_register[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27610 gold=%b dut=%b", g._48339_.Q, d.buffer_register[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48340_.Q !== d.buffer_register[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27611 gold=%b dut=%b", g._48340_.Q, d.buffer_register[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48341_.Q !== d.buffer_register[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27612 gold=%b dut=%b", g._48341_.Q, d.buffer_register[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48342_.Q !== d.decode_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27613 gold=%b dut=%b", g._48342_.Q, d.decode_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48343_.Q !== d.decode_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27614 gold=%b dut=%b", g._48343_.Q, d.decode_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48344_.Q !== d.decode_flags[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27615 gold=%b dut=%b", g._48344_.Q, d.decode_flags[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48345_.Q !== d.decode_flags[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27616 gold=%b dut=%b", g._48345_.Q, d.decode_flags[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48346_.Q !== d.decode_flags[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27617 gold=%b dut=%b", g._48346_.Q, d.decode_flags[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48347_.Q !== d.decode_flags[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27618 gold=%b dut=%b", g._48347_.Q, d.decode_flags[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48348_.Q !== d.decode_flags[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27619 gold=%b dut=%b", g._48348_.Q, d.decode_flags[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48349_.Q !== d.decode_flags[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27620 gold=%b dut=%b", g._48349_.Q, d.decode_flags[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48350_.Q !== d.decode_flags[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27621 gold=%b dut=%b", g._48350_.Q, d.decode_flags[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50020_.Q !== d.retry_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27622 gold=%b dut=%b", g._50020_.Q, d.retry_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50021_.Q !== d.retry_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27623 gold=%b dut=%b", g._50021_.Q, d.retry_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50459_.Q !== d.control_state_7[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27624 gold=%b dut=%b", g._50459_.Q, d.control_state_7[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50457_.Q !== d.control_state_7[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27625 gold=%b dut=%b", g._50457_.Q, d.control_state_7[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50460_.Q !== d.control_state_7[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27626 gold=%b dut=%b", g._50460_.Q, d.control_state_7[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50456_.Q !== d.control_valid_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27627 gold=%b dut=%b", g._50456_.Q, d.control_valid_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50462_.Q !== d.control_state_6[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27628 gold=%b dut=%b", g._50462_.Q, d.control_state_6[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50465_.Q !== d.datapath_register[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27629 gold=%b dut=%b", g._50465_.Q, d.datapath_register[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48271_.Q !== d.decode_state_flags[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27630 gold=%b dut=%b", g._48271_.Q, d.decode_state_flags[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48268_.Q !== d.decode_state_flags[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27631 gold=%b dut=%b", g._48268_.Q, d.decode_state_flags[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50000_.Q !== d.decoded_activity_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27632 gold=%b dut=%b", g._50000_.Q, d.decoded_activity_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50461_.Q !== d.control_state_7[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27633 gold=%b dut=%b", g._50461_.Q, d.control_state_7[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50464_.Q !== d.control_state_6[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27634 gold=%b dut=%b", g._50464_.Q, d.control_state_6[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48269_.Q !== d.decode_state_flags[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27635 gold=%b dut=%b", g._48269_.Q, d.decode_state_flags[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48270_.Q !== d.decode_state_flags[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27636 gold=%b dut=%b", g._48270_.Q, d.decode_state_flags[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50002_.Q !== d.edge_condition_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27637 gold=%b dut=%b", g._50002_.Q, d.edge_condition_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50017_.Q !== d.match_state[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27638 gold=%b dut=%b", g._50017_.Q, d.match_state[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50012_.Q !== d.control_state_8[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27639 gold=%b dut=%b", g._50012_.Q, d.control_state_8[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50014_.Q !== d.control_state_8[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27640 gold=%b dut=%b", g._50014_.Q, d.control_state_8[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50013_.Q !== d.control_state_8[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27641 gold=%b dut=%b", g._50013_.Q, d.control_state_8[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50015_.Q !== d.control_state_8[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27642 gold=%b dut=%b", g._50015_.Q, d.control_state_8[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50006_.Q !== d.address_capture[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27643 gold=%b dut=%b", g._50006_.Q, d.address_capture[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50007_.Q !== d.address_capture[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27644 gold=%b dut=%b", g._50007_.Q, d.address_capture[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50008_.Q !== d.address_capture[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27645 gold=%b dut=%b", g._50008_.Q, d.address_capture[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50009_.Q !== d.address_capture[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27646 gold=%b dut=%b", g._50009_.Q, d.address_capture[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50010_.Q !== d.address_capture[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27647 gold=%b dut=%b", g._50010_.Q, d.address_capture[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50011_.Q !== d.address_capture[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27648 gold=%b dut=%b", g._50011_.Q, d.address_capture[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50018_.Q !== d.hold_valid_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27649 gold=%b dut=%b", g._50018_.Q, d.hold_valid_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50019_.Q !== d.match_state[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27650 gold=%b dut=%b", g._50019_.Q, d.match_state[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50016_.Q !== d.pending_request_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27651 gold=%b dut=%b", g._50016_.Q, d.pending_request_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49913_.Q !== d.load_data_reg[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27652 gold=%b dut=%b", g._49913_.Q, d.load_data_reg[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49914_.Q !== d.load_data_reg[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27653 gold=%b dut=%b", g._49914_.Q, d.load_data_reg[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49915_.Q !== d.load_data_reg[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27654 gold=%b dut=%b", g._49915_.Q, d.load_data_reg[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49916_.Q !== d.load_data_reg[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27655 gold=%b dut=%b", g._49916_.Q, d.load_data_reg[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49917_.Q !== d.load_data_reg[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27656 gold=%b dut=%b", g._49917_.Q, d.load_data_reg[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49918_.Q !== d.load_data_reg[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27657 gold=%b dut=%b", g._49918_.Q, d.load_data_reg[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49919_.Q !== d.load_data_reg[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27658 gold=%b dut=%b", g._49919_.Q, d.load_data_reg[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49920_.Q !== d.load_data_reg[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27659 gold=%b dut=%b", g._49920_.Q, d.load_data_reg[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49921_.Q !== d.load_data_reg[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27660 gold=%b dut=%b", g._49921_.Q, d.load_data_reg[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49922_.Q !== d.load_data_reg[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27661 gold=%b dut=%b", g._49922_.Q, d.load_data_reg[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49923_.Q !== d.load_data_reg[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27662 gold=%b dut=%b", g._49923_.Q, d.load_data_reg[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49924_.Q !== d.load_data_reg[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27663 gold=%b dut=%b", g._49924_.Q, d.load_data_reg[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49925_.Q !== d.load_data_reg[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27664 gold=%b dut=%b", g._49925_.Q, d.load_data_reg[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49926_.Q !== d.load_data_reg[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27665 gold=%b dut=%b", g._49926_.Q, d.load_data_reg[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49927_.Q !== d.load_data_reg[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27666 gold=%b dut=%b", g._49927_.Q, d.load_data_reg[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49928_.Q !== d.load_data_reg[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27667 gold=%b dut=%b", g._49928_.Q, d.load_data_reg[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50058_.Q !== d.control_state_9[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27668 gold=%b dut=%b", g._50058_.Q, d.control_state_9[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50056_.Q !== d.control_state_9[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27669 gold=%b dut=%b", g._50056_.Q, d.control_state_9[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50057_.Q !== d.control_state_9[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27670 gold=%b dut=%b", g._50057_.Q, d.control_state_9[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50055_.Q !== d.control_state_9[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27671 gold=%b dut=%b", g._50055_.Q, d.control_state_9[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50003_.Q !== d.qualified_status_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27672 gold=%b dut=%b", g._50003_.Q, d.qualified_status_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49911_.Q !== d.control_state_10[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27673 gold=%b dut=%b", g._49911_.Q, d.control_state_10[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49832_.Q !== d.data_reg_7[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27674 gold=%b dut=%b", g._49832_.Q, d.data_reg_7[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49833_.Q !== d.data_reg_7[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27675 gold=%b dut=%b", g._49833_.Q, d.data_reg_7[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49834_.Q !== d.data_reg_7[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27676 gold=%b dut=%b", g._49834_.Q, d.data_reg_7[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49835_.Q !== d.data_reg_7[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27677 gold=%b dut=%b", g._49835_.Q, d.data_reg_7[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49836_.Q !== d.data_reg_7[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27678 gold=%b dut=%b", g._49836_.Q, d.data_reg_7[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49837_.Q !== d.data_reg_7[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27679 gold=%b dut=%b", g._49837_.Q, d.data_reg_7[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49838_.Q !== d.data_reg_7[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27680 gold=%b dut=%b", g._49838_.Q, d.data_reg_7[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49807_.Q !== d.control_reg_2[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27681 gold=%b dut=%b", g._49807_.Q, d.control_reg_2[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49808_.Q !== d.control_reg_2[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27682 gold=%b dut=%b", g._49808_.Q, d.control_reg_2[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49809_.Q !== d.control_reg_2[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27683 gold=%b dut=%b", g._49809_.Q, d.control_reg_2[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49810_.Q !== d.control_reg_2[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27684 gold=%b dut=%b", g._49810_.Q, d.control_reg_2[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49811_.Q !== d.control_reg_2[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27685 gold=%b dut=%b", g._49811_.Q, d.control_reg_2[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49812_.Q !== d.control_reg_2[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27686 gold=%b dut=%b", g._49812_.Q, d.control_reg_2[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49813_.Q !== d.control_reg_2[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27687 gold=%b dut=%b", g._49813_.Q, d.control_reg_2[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49814_.Q !== d.control_reg_2[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27688 gold=%b dut=%b", g._49814_.Q, d.control_reg_2[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49815_.Q !== d.control_reg_2[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27689 gold=%b dut=%b", g._49815_.Q, d.control_reg_2[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49816_.Q !== d.control_reg_2[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27690 gold=%b dut=%b", g._49816_.Q, d.control_reg_2[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49817_.Q !== d.control_reg_2[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27691 gold=%b dut=%b", g._49817_.Q, d.control_reg_2[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49818_.Q !== d.control_reg_2[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27692 gold=%b dut=%b", g._49818_.Q, d.control_reg_2[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49819_.Q !== d.control_reg_2[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27693 gold=%b dut=%b", g._49819_.Q, d.control_reg_2[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49820_.Q !== d.control_reg_2[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27694 gold=%b dut=%b", g._49820_.Q, d.control_reg_2[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49821_.Q !== d.control_reg_2[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27695 gold=%b dut=%b", g._49821_.Q, d.control_reg_2[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49822_.Q !== d.control_reg_2[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27696 gold=%b dut=%b", g._49822_.Q, d.control_reg_2[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49823_.Q !== d.control_reg_2[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27697 gold=%b dut=%b", g._49823_.Q, d.control_reg_2[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49824_.Q !== d.control_reg_2[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27698 gold=%b dut=%b", g._49824_.Q, d.control_reg_2[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49825_.Q !== d.control_reg_2[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27699 gold=%b dut=%b", g._49825_.Q, d.control_reg_2[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49826_.Q !== d.control_reg_2[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27700 gold=%b dut=%b", g._49826_.Q, d.control_reg_2[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49827_.Q !== d.control_reg_2[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27701 gold=%b dut=%b", g._49827_.Q, d.control_reg_2[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49828_.Q !== d.control_reg_2[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27702 gold=%b dut=%b", g._49828_.Q, d.control_reg_2[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49829_.Q !== d.control_reg_2[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27703 gold=%b dut=%b", g._49829_.Q, d.control_reg_2[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49830_.Q !== d.control_reg_2[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27704 gold=%b dut=%b", g._49830_.Q, d.control_reg_2[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49831_.Q !== d.control_reg_2[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27705 gold=%b dut=%b", g._49831_.Q, d.control_reg_2[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49907_.Q !== d.control_state_10[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27706 gold=%b dut=%b", g._49907_.Q, d.control_state_10[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49908_.Q !== d.control_state_10[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27707 gold=%b dut=%b", g._49908_.Q, d.control_state_10[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50059_.Q !== d.control_status[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27708 gold=%b dut=%b", g._50059_.Q, d.control_status[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50060_.Q !== d.control_status[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27709 gold=%b dut=%b", g._50060_.Q, d.control_status[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48385_.Q !== d.data_register_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27742 gold=%b dut=%b", g._48385_.Q, d.data_register_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48386_.Q !== d.data_register_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27743 gold=%b dut=%b", g._48386_.Q, d.data_register_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48387_.Q !== d.data_register_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27744 gold=%b dut=%b", g._48387_.Q, d.data_register_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48388_.Q !== d.data_register_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27745 gold=%b dut=%b", g._48388_.Q, d.data_register_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48389_.Q !== d.data_register_4[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27746 gold=%b dut=%b", g._48389_.Q, d.data_register_4[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48390_.Q !== d.data_register_4[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27747 gold=%b dut=%b", g._48390_.Q, d.data_register_4[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48391_.Q !== d.data_register_4[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27748 gold=%b dut=%b", g._48391_.Q, d.data_register_4[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48392_.Q !== d.data_register_4[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27749 gold=%b dut=%b", g._48392_.Q, d.data_register_4[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48393_.Q !== d.data_register_4[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27750 gold=%b dut=%b", g._48393_.Q, d.data_register_4[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48394_.Q !== d.data_register_4[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27751 gold=%b dut=%b", g._48394_.Q, d.data_register_4[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48395_.Q !== d.data_register_4[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27752 gold=%b dut=%b", g._48395_.Q, d.data_register_4[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48396_.Q !== d.data_register_4[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27753 gold=%b dut=%b", g._48396_.Q, d.data_register_4[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48397_.Q !== d.data_register_4[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27754 gold=%b dut=%b", g._48397_.Q, d.data_register_4[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48398_.Q !== d.data_register_4[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27755 gold=%b dut=%b", g._48398_.Q, d.data_register_4[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48399_.Q !== d.data_register_4[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27756 gold=%b dut=%b", g._48399_.Q, d.data_register_4[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48400_.Q !== d.data_register_4[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27757 gold=%b dut=%b", g._48400_.Q, d.data_register_4[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48401_.Q !== d.data_register_4[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27758 gold=%b dut=%b", g._48401_.Q, d.data_register_4[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48402_.Q !== d.data_register_4[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27759 gold=%b dut=%b", g._48402_.Q, d.data_register_4[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48403_.Q !== d.data_register_4[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27760 gold=%b dut=%b", g._48403_.Q, d.data_register_4[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48404_.Q !== d.data_register_4[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27761 gold=%b dut=%b", g._48404_.Q, d.data_register_4[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48405_.Q !== d.data_register_4[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27762 gold=%b dut=%b", g._48405_.Q, d.data_register_4[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48406_.Q !== d.data_register_4[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27763 gold=%b dut=%b", g._48406_.Q, d.data_register_4[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48407_.Q !== d.data_register_4[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27764 gold=%b dut=%b", g._48407_.Q, d.data_register_4[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48408_.Q !== d.data_register_4[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27765 gold=%b dut=%b", g._48408_.Q, d.data_register_4[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48409_.Q !== d.data_register_4[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27766 gold=%b dut=%b", g._48409_.Q, d.data_register_4[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48410_.Q !== d.data_register_4[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27767 gold=%b dut=%b", g._48410_.Q, d.data_register_4[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48411_.Q !== d.data_register_4[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27768 gold=%b dut=%b", g._48411_.Q, d.data_register_4[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48412_.Q !== d.data_register_4[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27769 gold=%b dut=%b", g._48412_.Q, d.data_register_4[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48413_.Q !== d.data_register_4[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27770 gold=%b dut=%b", g._48413_.Q, d.data_register_4[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48414_.Q !== d.data_register_4[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27771 gold=%b dut=%b", g._48414_.Q, d.data_register_4[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48415_.Q !== d.data_register_4[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27772 gold=%b dut=%b", g._48415_.Q, d.data_register_4[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48416_.Q !== d.data_register_4[31]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27773 gold=%b dut=%b", g._48416_.Q, d.data_register_4[31]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48384_.Q !== d.control_flag_27775) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27775 gold=%b dut=%b", g._48384_.Q, d.control_flag_27775);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49672_.Q !== d.status_flag_8) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27776 gold=%b dut=%b", g._49672_.Q, d.status_flag_8);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49931_.Q !== d.event_delay_shift[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27781 gold=%b dut=%b", g._49931_.Q, d.event_delay_shift[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50005_.Q !== d.all_clear_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27782 gold=%b dut=%b", g._50005_.Q, d.all_clear_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50162_.Q !== d.fsm_state_4[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27783 gold=%b dut=%b", g._50162_.Q, d.fsm_state_4[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50163_.Q !== d.fsm_state_4[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27784 gold=%b dut=%b", g._50163_.Q, d.fsm_state_4[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50164_.Q !== d.fsm_state_4[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27785 gold=%b dut=%b", g._50164_.Q, d.fsm_state_4[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50165_.Q !== d.fsm_state_4[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27786 gold=%b dut=%b", g._50165_.Q, d.fsm_state_4[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49912_.Q !== d.control_state_10[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27787 gold=%b dut=%b", g._49912_.Q, d.control_state_10[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._49297_.Q !== d.busy_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27788 gold=%b dut=%b", g._49297_.Q, d.busy_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50198_.Q !== d.data_reg_24[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27789 gold=%b dut=%b", g._50198_.Q, d.data_reg_24[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50199_.Q !== d.data_reg_24[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27790 gold=%b dut=%b", g._50199_.Q, d.data_reg_24[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50200_.Q !== d.data_reg_24[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27791 gold=%b dut=%b", g._50200_.Q, d.data_reg_24[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50201_.Q !== d.data_reg_24[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27792 gold=%b dut=%b", g._50201_.Q, d.data_reg_24[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50202_.Q !== d.data_reg_24[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27793 gold=%b dut=%b", g._50202_.Q, d.data_reg_24[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50203_.Q !== d.data_reg_24[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27794 gold=%b dut=%b", g._50203_.Q, d.data_reg_24[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50204_.Q !== d.data_reg_24[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27795 gold=%b dut=%b", g._50204_.Q, d.data_reg_24[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50205_.Q !== d.data_reg_24[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27796 gold=%b dut=%b", g._50205_.Q, d.data_reg_24[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50206_.Q !== d.data_reg_24[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27797 gold=%b dut=%b", g._50206_.Q, d.data_reg_24[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50207_.Q !== d.data_reg_24[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27798 gold=%b dut=%b", g._50207_.Q, d.data_reg_24[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50208_.Q !== d.data_reg_24[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27799 gold=%b dut=%b", g._50208_.Q, d.data_reg_24[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50209_.Q !== d.data_reg_24[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27800 gold=%b dut=%b", g._50209_.Q, d.data_reg_24[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50210_.Q !== d.data_reg_24[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27801 gold=%b dut=%b", g._50210_.Q, d.data_reg_24[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50211_.Q !== d.data_reg_24[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27802 gold=%b dut=%b", g._50211_.Q, d.data_reg_24[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50212_.Q !== d.data_reg_24[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27803 gold=%b dut=%b", g._50212_.Q, d.data_reg_24[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50213_.Q !== d.data_reg_24[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27804 gold=%b dut=%b", g._50213_.Q, d.data_reg_24[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50214_.Q !== d.data_reg_24[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27805 gold=%b dut=%b", g._50214_.Q, d.data_reg_24[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50215_.Q !== d.data_reg_24[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27806 gold=%b dut=%b", g._50215_.Q, d.data_reg_24[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50216_.Q !== d.data_reg_24[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27807 gold=%b dut=%b", g._50216_.Q, d.data_reg_24[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50217_.Q !== d.data_reg_24[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27808 gold=%b dut=%b", g._50217_.Q, d.data_reg_24[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50218_.Q !== d.data_reg_24[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27809 gold=%b dut=%b", g._50218_.Q, d.data_reg_24[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50219_.Q !== d.data_reg_24[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27810 gold=%b dut=%b", g._50219_.Q, d.data_reg_24[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50220_.Q !== d.data_reg_24[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27811 gold=%b dut=%b", g._50220_.Q, d.data_reg_24[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50221_.Q !== d.data_reg_24[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27812 gold=%b dut=%b", g._50221_.Q, d.data_reg_24[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50222_.Q !== d.accumulator_high[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27813 gold=%b dut=%b", g._50222_.Q, d.accumulator_high[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50223_.Q !== d.accumulator_high[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27814 gold=%b dut=%b", g._50223_.Q, d.accumulator_high[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50224_.Q !== d.accumulator_high[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27815 gold=%b dut=%b", g._50224_.Q, d.accumulator_high[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50225_.Q !== d.accumulator_high[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27816 gold=%b dut=%b", g._50225_.Q, d.accumulator_high[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50226_.Q !== d.accumulator_high[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27817 gold=%b dut=%b", g._50226_.Q, d.accumulator_high[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50227_.Q !== d.accumulator_high[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27818 gold=%b dut=%b", g._50227_.Q, d.accumulator_high[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50228_.Q !== d.accumulator_high[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27819 gold=%b dut=%b", g._50228_.Q, d.accumulator_high[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48273_.Q !== d.low_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27884 gold=%b dut=%b", g._48273_.Q, d.low_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48274_.Q !== d.low_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27885 gold=%b dut=%b", g._48274_.Q, d.low_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48275_.Q !== d.low_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27886 gold=%b dut=%b", g._48275_.Q, d.low_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48276_.Q !== d.low_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27887 gold=%b dut=%b", g._48276_.Q, d.low_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48277_.Q !== d.low_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27888 gold=%b dut=%b", g._48277_.Q, d.low_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48278_.Q !== d.low_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27889 gold=%b dut=%b", g._48278_.Q, d.low_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48279_.Q !== d.low_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27890 gold=%b dut=%b", g._48279_.Q, d.low_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48280_.Q !== d.low_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27891 gold=%b dut=%b", g._48280_.Q, d.low_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48281_.Q !== d.low_data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27892 gold=%b dut=%b", g._48281_.Q, d.low_data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48282_.Q !== d.adder_result_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27893 gold=%b dut=%b", g._48282_.Q, d.adder_result_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48283_.Q !== d.adder_result_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27894 gold=%b dut=%b", g._48283_.Q, d.adder_result_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48284_.Q !== d.adder_result_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27895 gold=%b dut=%b", g._48284_.Q, d.adder_result_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48285_.Q !== d.adder_result_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27896 gold=%b dut=%b", g._48285_.Q, d.adder_result_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48286_.Q !== d.adder_result_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27897 gold=%b dut=%b", g._48286_.Q, d.adder_result_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48287_.Q !== d.adder_result_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27898 gold=%b dut=%b", g._48287_.Q, d.adder_result_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48288_.Q !== d.adder_result_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27899 gold=%b dut=%b", g._48288_.Q, d.adder_result_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48289_.Q !== d.adder_result_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27900 gold=%b dut=%b", g._48289_.Q, d.adder_result_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48290_.Q !== d.adder_result_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27901 gold=%b dut=%b", g._48290_.Q, d.adder_result_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48291_.Q !== d.adder_result_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27902 gold=%b dut=%b", g._48291_.Q, d.adder_result_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48292_.Q !== d.adder_result_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27903 gold=%b dut=%b", g._48292_.Q, d.adder_result_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48293_.Q !== d.adder_result_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27904 gold=%b dut=%b", g._48293_.Q, d.adder_result_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48294_.Q !== d.adder_result_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27905 gold=%b dut=%b", g._48294_.Q, d.adder_result_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48295_.Q !== d.adder_result_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27906 gold=%b dut=%b", g._48295_.Q, d.adder_result_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48296_.Q !== d.adder_result_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27907 gold=%b dut=%b", g._48296_.Q, d.adder_result_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48297_.Q !== d.adder_result_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27908 gold=%b dut=%b", g._48297_.Q, d.adder_result_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48298_.Q !== d.adder_result_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27909 gold=%b dut=%b", g._48298_.Q, d.adder_result_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48299_.Q !== d.adder_result_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27910 gold=%b dut=%b", g._48299_.Q, d.adder_result_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48300_.Q !== d.adder_result_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27911 gold=%b dut=%b", g._48300_.Q, d.adder_result_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48301_.Q !== d.adder_result_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27912 gold=%b dut=%b", g._48301_.Q, d.adder_result_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48302_.Q !== d.adder_result_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27913 gold=%b dut=%b", g._48302_.Q, d.adder_result_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48303_.Q !== d.adder_result_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27914 gold=%b dut=%b", g._48303_.Q, d.adder_result_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48304_.Q !== d.adder_result_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27915 gold=%b dut=%b", g._48304_.Q, d.adder_result_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50229_.Q !== d.pipeline_data_reg_1[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27917 gold=%b dut=%b", g._50229_.Q, d.pipeline_data_reg_1[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50230_.Q !== d.pipeline_data_reg_1[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27918 gold=%b dut=%b", g._50230_.Q, d.pipeline_data_reg_1[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50231_.Q !== d.pipeline_data_reg_1[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27919 gold=%b dut=%b", g._50231_.Q, d.pipeline_data_reg_1[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50232_.Q !== d.pipeline_data_reg_1[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27920 gold=%b dut=%b", g._50232_.Q, d.pipeline_data_reg_1[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50233_.Q !== d.pipeline_data_reg_1[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27921 gold=%b dut=%b", g._50233_.Q, d.pipeline_data_reg_1[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50234_.Q !== d.pipeline_data_reg_1[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27922 gold=%b dut=%b", g._50234_.Q, d.pipeline_data_reg_1[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50235_.Q !== d.pipeline_data_reg_1[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27923 gold=%b dut=%b", g._50235_.Q, d.pipeline_data_reg_1[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50236_.Q !== d.pipeline_data_reg_1[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27924 gold=%b dut=%b", g._50236_.Q, d.pipeline_data_reg_1[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50237_.Q !== d.pipeline_data_reg_1[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27925 gold=%b dut=%b", g._50237_.Q, d.pipeline_data_reg_1[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50238_.Q !== d.pipeline_data_reg_1[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27926 gold=%b dut=%b", g._50238_.Q, d.pipeline_data_reg_1[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50239_.Q !== d.pipeline_data_reg_1[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27927 gold=%b dut=%b", g._50239_.Q, d.pipeline_data_reg_1[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50240_.Q !== d.pipeline_data_reg_1[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27928 gold=%b dut=%b", g._50240_.Q, d.pipeline_data_reg_1[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50241_.Q !== d.pipeline_data_reg_1[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27929 gold=%b dut=%b", g._50241_.Q, d.pipeline_data_reg_1[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50242_.Q !== d.pipeline_data_reg_1[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27930 gold=%b dut=%b", g._50242_.Q, d.pipeline_data_reg_1[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50243_.Q !== d.pipeline_data_reg_1[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27931 gold=%b dut=%b", g._50243_.Q, d.pipeline_data_reg_1[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50244_.Q !== d.pipeline_data_reg_1[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27932 gold=%b dut=%b", g._50244_.Q, d.pipeline_data_reg_1[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50245_.Q !== d.pipeline_data_reg_1[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27933 gold=%b dut=%b", g._50245_.Q, d.pipeline_data_reg_1[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50246_.Q !== d.pipeline_data_reg_1[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27934 gold=%b dut=%b", g._50246_.Q, d.pipeline_data_reg_1[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50247_.Q !== d.pipeline_data_reg_1[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27935 gold=%b dut=%b", g._50247_.Q, d.pipeline_data_reg_1[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50248_.Q !== d.pipeline_data_reg_1[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27936 gold=%b dut=%b", g._50248_.Q, d.pipeline_data_reg_1[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50249_.Q !== d.pipeline_data_reg_1[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27937 gold=%b dut=%b", g._50249_.Q, d.pipeline_data_reg_1[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50250_.Q !== d.pipeline_data_reg_1[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27938 gold=%b dut=%b", g._50250_.Q, d.pipeline_data_reg_1[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50251_.Q !== d.pipeline_data_reg_1[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27939 gold=%b dut=%b", g._50251_.Q, d.pipeline_data_reg_1[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50252_.Q !== d.pipeline_data_reg_1[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27940 gold=%b dut=%b", g._50252_.Q, d.pipeline_data_reg_1[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50253_.Q !== d.pipeline_data_reg_1[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27941 gold=%b dut=%b", g._50253_.Q, d.pipeline_data_reg_1[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50254_.Q !== d.pipeline_data_reg_1[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27942 gold=%b dut=%b", g._50254_.Q, d.pipeline_data_reg_1[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50255_.Q !== d.pipeline_data_reg_1[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27943 gold=%b dut=%b", g._50255_.Q, d.pipeline_data_reg_1[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50256_.Q !== d.pipeline_data_reg_1[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27944 gold=%b dut=%b", g._50256_.Q, d.pipeline_data_reg_1[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50257_.Q !== d.pipeline_data_reg_1[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27945 gold=%b dut=%b", g._50257_.Q, d.pipeline_data_reg_1[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50258_.Q !== d.pipeline_data_reg_1[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27946 gold=%b dut=%b", g._50258_.Q, d.pipeline_data_reg_1[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50259_.Q !== d.pipeline_data_reg_1[30]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27947 gold=%b dut=%b", g._50259_.Q, d.pipeline_data_reg_1[30]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48305_.Q !== d.index_counter[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27948 gold=%b dut=%b", g._48305_.Q, d.index_counter[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48306_.Q !== d.index_counter[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27949 gold=%b dut=%b", g._48306_.Q, d.index_counter[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48307_.Q !== d.index_counter[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27950 gold=%b dut=%b", g._48307_.Q, d.index_counter[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48308_.Q !== d.index_counter[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27951 gold=%b dut=%b", g._48308_.Q, d.index_counter[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._48309_.Q !== d.index_counter[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27952 gold=%b dut=%b", g._48309_.Q, d.index_counter[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50061_.Q !== d.write_decode_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27953 gold=%b dut=%b", g._50061_.Q, d.write_decode_flag);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50062_.Q !== d.wide_data_reg_6[0]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27954 gold=%b dut=%b", g._50062_.Q, d.wide_data_reg_6[0]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50063_.Q !== d.wide_data_reg_6[1]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27955 gold=%b dut=%b", g._50063_.Q, d.wide_data_reg_6[1]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50064_.Q !== d.wide_data_reg_6[2]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27956 gold=%b dut=%b", g._50064_.Q, d.wide_data_reg_6[2]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50065_.Q !== d.wide_data_reg_6[3]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27957 gold=%b dut=%b", g._50065_.Q, d.wide_data_reg_6[3]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50066_.Q !== d.wide_data_reg_6[4]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27958 gold=%b dut=%b", g._50066_.Q, d.wide_data_reg_6[4]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50067_.Q !== d.wide_data_reg_6[5]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27959 gold=%b dut=%b", g._50067_.Q, d.wide_data_reg_6[5]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50068_.Q !== d.wide_data_reg_6[6]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27960 gold=%b dut=%b", g._50068_.Q, d.wide_data_reg_6[6]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50069_.Q !== d.wide_data_reg_6[7]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27961 gold=%b dut=%b", g._50069_.Q, d.wide_data_reg_6[7]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50070_.Q !== d.wide_data_reg_6[8]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27962 gold=%b dut=%b", g._50070_.Q, d.wide_data_reg_6[8]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50071_.Q !== d.wide_data_reg_6[9]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27963 gold=%b dut=%b", g._50071_.Q, d.wide_data_reg_6[9]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50072_.Q !== d.wide_data_reg_6[10]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27964 gold=%b dut=%b", g._50072_.Q, d.wide_data_reg_6[10]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50073_.Q !== d.wide_data_reg_6[11]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27965 gold=%b dut=%b", g._50073_.Q, d.wide_data_reg_6[11]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50074_.Q !== d.wide_data_reg_6[12]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27966 gold=%b dut=%b", g._50074_.Q, d.wide_data_reg_6[12]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50075_.Q !== d.wide_data_reg_6[13]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27967 gold=%b dut=%b", g._50075_.Q, d.wide_data_reg_6[13]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50076_.Q !== d.wide_data_reg_6[14]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27968 gold=%b dut=%b", g._50076_.Q, d.wide_data_reg_6[14]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50077_.Q !== d.wide_data_reg_6[15]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27969 gold=%b dut=%b", g._50077_.Q, d.wide_data_reg_6[15]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50078_.Q !== d.wide_data_reg_6[16]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27970 gold=%b dut=%b", g._50078_.Q, d.wide_data_reg_6[16]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50079_.Q !== d.wide_data_reg_6[17]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27971 gold=%b dut=%b", g._50079_.Q, d.wide_data_reg_6[17]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50080_.Q !== d.wide_data_reg_6[18]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27972 gold=%b dut=%b", g._50080_.Q, d.wide_data_reg_6[18]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50081_.Q !== d.wide_data_reg_6[19]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27973 gold=%b dut=%b", g._50081_.Q, d.wide_data_reg_6[19]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50082_.Q !== d.wide_data_reg_6[20]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27974 gold=%b dut=%b", g._50082_.Q, d.wide_data_reg_6[20]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50083_.Q !== d.wide_data_reg_6[21]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27975 gold=%b dut=%b", g._50083_.Q, d.wide_data_reg_6[21]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50084_.Q !== d.wide_data_reg_6[22]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27976 gold=%b dut=%b", g._50084_.Q, d.wide_data_reg_6[22]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50085_.Q !== d.wide_data_reg_6[23]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27977 gold=%b dut=%b", g._50085_.Q, d.wide_data_reg_6[23]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50086_.Q !== d.wide_data_reg_6[24]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27978 gold=%b dut=%b", g._50086_.Q, d.wide_data_reg_6[24]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50087_.Q !== d.wide_data_reg_6[25]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27979 gold=%b dut=%b", g._50087_.Q, d.wide_data_reg_6[25]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50088_.Q !== d.wide_data_reg_6[26]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27980 gold=%b dut=%b", g._50088_.Q, d.wide_data_reg_6[26]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50089_.Q !== d.wide_data_reg_6[27]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27981 gold=%b dut=%b", g._50089_.Q, d.wide_data_reg_6[27]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50090_.Q !== d.wide_data_reg_6[28]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27982 gold=%b dut=%b", g._50090_.Q, d.wide_data_reg_6[28]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50091_.Q !== d.wide_data_reg_6[29]) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27983 gold=%b dut=%b", g._50091_.Q, d.wide_data_reg_6[29]);
ff_errors=ff_errors+1;
end
ff_checks=ff_checks+1;
if (g._50092_.Q !== d.wide_data_nonzero_flag) begin
if(ff_errors<8) $display("FF_MISMATCH qid=27984 gold=%b dut=%b", g._50092_.Q, d.wide_data_nonzero_flag);
ff_errors=ff_errors+1;
end
end
end
endmodule
