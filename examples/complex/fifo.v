// fifo.v —— 同步 FIFO (数据路径 + 双指针控制, 中等复杂度)
module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 4    // 2^4 = 16 深度
)(
    input                  clk,
    input                  rst,
    input                  wr_en,
    input                  rd_en,
    input      [WIDTH-1:0] din,
    output reg [WIDTH-1:0] dout,
    output                 full,
    output                 empty
);
    reg [WIDTH-1:0] mem [0:(1<<DEPTH)-1];
    reg [DEPTH:0]   wr_ptr;   // 多一位用于区分满/空
    reg [DEPTH:0]   rd_ptr;

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[DEPTH] != rd_ptr[DEPTH]) &&
                   (wr_ptr[DEPTH-1:0] == rd_ptr[DEPTH-1:0]);

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            dout   <= 0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[DEPTH-1:0]] <= din;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                dout   <= mem[rd_ptr[DEPTH-1:0]];
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
