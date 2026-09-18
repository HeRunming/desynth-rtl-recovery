// alu8.v —— 8位ALU, 8种运算 (纯组合数据路径, 中等复杂度)
module alu8 (
    input      [7:0] a,
    input      [7:0] b,
    input      [2:0] op,
    output reg [7:0] result,
    output reg       zero,
    output reg       carry
);
    always @(*) begin
        carry = 1'b0;
        case (op)
            3'b000: {carry, result} = a + b;        // 加
            3'b001: {carry, result} = a - b;        // 减
            3'b010: result = a & b;                 // 与
            3'b011: result = a | b;                 // 或
            3'b100: result = a ^ b;                 // 异或
            3'b101: result = ~a;                    // 非
            3'b110: result = a << 1;                // 左移
            3'b111: result = a >> 1;                // 右移
            default: result = 8'b0;
        endcase
        zero = (result == 8'b0);
    end
endmodule
