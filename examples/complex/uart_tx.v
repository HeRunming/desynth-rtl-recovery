// uart_tx.v —— UART 发送器 (真实、有代表性的设计)
// 特点: 状态机(控制) + 移位寄存器(数据路径) + 波特率计数器 + 位计数器
// 这是真实硬件里非常典型的"控制+数据路径混合"模块
module uart_tx #(
    parameter CLKS_PER_BIT = 87   // 波特率分频 (如 10MHz / 115200)
)(
    input        clk,
    input        rst,
    input        tx_start,     // 开始发送
    input  [7:0] tx_data,      // 待发送字节
    output reg   tx_serial,    // 串行输出
    output reg   tx_busy,      // 忙标志
    output reg   tx_done       // 完成脉冲
);
    // 状态定义
    localparam IDLE      = 3'b000;
    localparam START_BIT = 3'b001;
    localparam DATA_BITS = 3'b010;
    localparam STOP_BIT  = 3'b011;
    localparam CLEANUP   = 3'b100;

    reg [2:0] state;
    reg [7:0] clk_count;   // 波特率计数
    reg [2:0] bit_index;   // 当前发送第几位
    reg [7:0] tx_shift;    // 数据移位寄存器

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            tx_serial <= 1'b1;      // 空闲时为高
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            clk_count <= 0;
            bit_index <= 0;
        end else begin
            tx_done <= 1'b0;        // 默认拉低
            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (tx_start) begin
                        tx_busy  <= 1'b1;
                        tx_shift <= tx_data;   // 锁存数据
                        state    <= START_BIT;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                START_BIT: begin
                    tx_serial <= 1'b0;         // 起始位为低
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state     <= DATA_BITS;
                    end
                end

                DATA_BITS: begin
                    tx_serial <= tx_shift[bit_index];   // 逐位发送
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state     <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    tx_serial <= 1'b1;         // 停止位为高
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        tx_done   <= 1'b1;
                        tx_busy   <= 1'b0;
                        state     <= CLEANUP;
                    end
                end

                CLEANUP: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
