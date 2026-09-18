`timescale 1ns/1ps
module tb_mul_directed;
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
    $finish;
  end
endmodule
