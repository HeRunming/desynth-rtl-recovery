// fsm_traffic: 交通灯状态机（控制逻辑类 —— 反综合难点）
module fsm_traffic (
    input        clk,
    input        rst,
    output [1:0] light
);
    localparam RED = 2'd0, GREEN = 2'd1, YELLOW = 2'd2;
    reg [1:0] state;
    reg [7:0] timer;
    always @(posedge clk) begin
        if (rst) begin
            state <= RED; timer <= 8'd20;
        end else if (timer == 8'd0) begin
            case (state)
                RED:    begin state <= GREEN;  timer <= 8'd15; end
                GREEN:  begin state <= YELLOW; timer <= 8'd5;  end
                YELLOW: begin state <= RED;    timer <= 8'd20; end
                default: state <= RED;
            endcase
        end else timer <= timer - 1;
    end
    assign light = state;
endmodule
