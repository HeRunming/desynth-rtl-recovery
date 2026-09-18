// counter.v —— 人类可读的 RTL（我们最终想从网表恢复出的东西）
module counter (
    input        clk,      // 时钟
    input        rst,      // 复位
    input        enable,   // 使能
    output reg [7:0] count // 8位计数值
);
    always @(posedge clk) begin
        if (rst)
            count <= 8'b0;         // 复位清零
        else if (enable)
            count <= count + 1;    // 每个时钟+1
    end
endmodule
