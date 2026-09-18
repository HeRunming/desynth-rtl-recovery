// crc8.v —— CRC-8 计算器 (难例: 特定多项式的异或反馈网络)
// 难点: 多项式 0x07 的反馈结构综合后完全打散, 常数/抽头位置极难反推
module crc8 (
    input        clk,
    input        rst,
    input        data_valid,
    input  [7:0] data_in,
    output reg [7:0] crc_out
);
    // CRC-8, 多项式 x^8 + x^2 + x + 1 (0x07)
    wire [7:0] next_crc;
    wire [7:0] d = data_in;
    wire [7:0] c = crc_out;

    // 展开的 CRC 反馈逻辑 (每一位都是若干输入位和当前CRC位的异或)
    assign next_crc[0] = c[0]^c[6]^c[7]^d[0]^d[6]^d[7];
    assign next_crc[1] = c[0]^c[1]^c[6]^d[0]^d[1]^d[6];
    assign next_crc[2] = c[0]^c[1]^c[2]^c[6]^d[0]^d[1]^d[2]^d[6];
    assign next_crc[3] = c[1]^c[2]^c[3]^c[7]^d[1]^d[2]^d[3]^d[7];
    assign next_crc[4] = c[2]^c[3]^c[4]^d[2]^d[3]^d[4];
    assign next_crc[5] = c[3]^c[4]^c[5]^d[3]^d[4]^d[5];
    assign next_crc[6] = c[4]^c[5]^c[6]^d[4]^d[5]^d[6];
    assign next_crc[7] = c[5]^c[6]^c[7]^d[5]^d[6]^d[7];

    always @(posedge clk) begin
        if (rst)
            crc_out <= 8'h00;
        else if (data_valid)
            crc_out <= next_crc;
    end
endmodule
