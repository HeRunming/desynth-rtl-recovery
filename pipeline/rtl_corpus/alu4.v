// alu4: 4位ALU（数据路径类，多种运算）
module alu4 (
    input      [3:0] a,
    input      [3:0] b,
    input      [1:0] op,     // 00=加 01=减 10=与 11=或
    output reg [3:0] result,
    output           carry
);
    reg [4:0] tmp;
    always @(*) begin
        case (op)
            2'b00: tmp = a + b;
            2'b01: tmp = a - b;
            2'b10: tmp = {1'b0, a & b};
            2'b11: tmp = {1'b0, a | b};
            default: tmp = 5'b0;
        endcase
        result = tmp[3:0];
    end
    assign carry = tmp[4];
endmodule
