// shift_reg: 8位移位寄存器（时序/数据路径类）
module shift_reg (
    input            clk,
    input            rst,
    input            serial_in,
    output reg [7:0] parallel_out
);
    always @(posedge clk) begin
        if (rst) parallel_out <= 8'b0;
        else     parallel_out <= {parallel_out[6:0], serial_in};
    end
endmodule
