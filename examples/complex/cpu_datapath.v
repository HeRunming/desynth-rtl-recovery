// cpu_datapath.v —— 极简 4指令 累加器 CPU (难例: 控制+数据路径深度耦合)
// 难点: 指令译码、多路选择、寄存器堆、PC控制 综合后交织在一起
module cpu_datapath (
    input        clk,
    input        rst,
    input  [7:0] instr,       // [7:6]=opcode, [5:0]=operand
    output [7:0] acc,         // 累加器
    output [3:0] pc           // 程序计数器
);
    localparam OP_LOAD = 2'b00;  // acc = operand
    localparam OP_ADD  = 2'b01;  // acc = acc + operand
    localparam OP_SUB  = 2'b10;  // acc = acc - operand
    localparam OP_JMP  = 2'b11;  // pc = operand[3:0] (条件: acc!=0)

    reg [7:0] acc_reg;
    reg [3:0] pc_reg;

    wire [1:0] opcode = instr[7:6];
    wire [7:0] operand = {2'b0, instr[5:0]};

    always @(posedge clk) begin
        if (rst) begin
            acc_reg <= 8'b0;
            pc_reg  <= 4'b0;
        end else begin
            case (opcode)
                OP_LOAD: begin acc_reg <= operand;           pc_reg <= pc_reg + 1; end
                OP_ADD:  begin acc_reg <= acc_reg + operand; pc_reg <= pc_reg + 1; end
                OP_SUB:  begin acc_reg <= acc_reg - operand; pc_reg <= pc_reg + 1; end
                OP_JMP:  begin
                    if (acc_reg != 8'b0) pc_reg <= instr[3:0];  // 条件跳转
                    else                 pc_reg <= pc_reg + 1;
                end
            endcase
        end
    end

    assign acc = acc_reg;
    assign pc  = pc_reg;
endmodule
