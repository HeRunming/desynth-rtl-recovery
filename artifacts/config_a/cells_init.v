module FF(C, D, Q); input C, D; output reg Q; initial Q = 1'b0; always @(posedge C) Q <= D; endmodule
module INV(I, O); input I; output O; assign O = ~I; endmodule
module BUF(I, O); input I; output O; assign O = I; endmodule
module AND2(I0,I1,O); input I0,I1; output O; assign O=I0&I1; endmodule
module OR2(I0,I1,O); input I0,I1; output O; assign O=I0|I1; endmodule
module XOR(I0,I1,O); input I0,I1; output O; assign O=I0^I1; endmodule
module MUX(I0,I1,S,O); input I0,I1,S; output O; assign O=S?I1:I0; endmodule
