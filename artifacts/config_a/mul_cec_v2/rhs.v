`default_nettype none
module rhs(input [32:0] a,b, output [63:0] result);
assign result = $signed(a) * $signed(b);
endmodule
`default_nettype wire
