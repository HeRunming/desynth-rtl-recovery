// traffic.v —— 交通灯状态机（人类可读的 RTL）
// 意图非常清晰：红->绿->黄->红 循环，每个状态停留若干周期
module traffic (
    input        clk,
    input        rst,
    output [1:0] light    // 00=红 01=绿 10=黄
);
    // 状态编码
    localparam RED    = 2'd0;
    localparam GREEN  = 2'd1;
    localparam YELLOW = 2'd2;

    // 每个状态的持续周期
    localparam RED_TIME    = 8'd20;
    localparam GREEN_TIME  = 8'd15;
    localparam YELLOW_TIME = 8'd5;

    reg [1:0] state;      // 当前状态
    reg [7:0] timer;      // 倒计时

    always @(posedge clk) begin
        if (rst) begin
            state <= RED;
            timer <= RED_TIME;
        end else if (timer == 8'd0) begin
            // 计时结束，切换到下一个状态
            case (state)
                RED:    begin state <= GREEN;  timer <= GREEN_TIME;  end
                GREEN:  begin state <= YELLOW; timer <= YELLOW_TIME; end
                YELLOW: begin state <= RED;    timer <= RED_TIME;    end
                default: state <= RED;
            endcase
        end else begin
            timer <= timer - 1;   // 继续倒计时
        end
    end

    // 输出逻辑：状态直接映射到灯
    assign light = state;
endmodule
