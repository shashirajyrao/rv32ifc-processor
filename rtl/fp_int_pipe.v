`timescale 1ns/1ps
// RV32 integer-to-single conversion: magnitude, normalization, rounding.
module fp_int_pipe(input clk,rst_n,start,signed_in,input [31:0] x,
 input [2:0] rm,output valid,output [32:0] result,output [4:0] flags);
 reg [31:0] magnitude;
 reg sign1,sign2,zero2; reg [2:0] rm1,rm2;
 wire [4:0] distance;
 countLeadingZeros #(32,5) clz(magnitude,distance);
 reg [32:0] sig2; reg signed [7:0] exp2;
 reg [1:0] v;
 assign valid=v[1];
 always @(posedge clk) begin
  if(!rst_n) v<=0; else v<={v[0],start};
  magnitude<=(signed_in && x[31]) ? -x : x;
  sign1<=signed_in && x[31];rm1<=rm;
  sig2<={1'b0,(magnitude<<distance)};
  exp2<={1'b0,2'b10,~distance};
  zero2<=magnitude==0;sign2<=sign1;rm2<=rm1;
 end
 // options=5: MSB always zero and no underflow (HardFloat constants).
 roundAnyRawFNToRecFN #(6,32,8,24,5) rounder(
  1'b1,1'b0,1'b0,1'b0,1'b0,zero2,sign2,exp2,sig2,rm2,result,flags);
endmodule

