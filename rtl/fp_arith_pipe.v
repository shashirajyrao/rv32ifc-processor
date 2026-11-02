`timescale 1ns/1ps
// Registered RV32F arithmetic using unmodified Berkeley HardFloat primitives.
module fp_arith_pipe(input clk,rst_n,start,input [1:0] op,
 input [32:0] a,b,c,input [2:0] rm,
 output valid,output [32:0] result,output [4:0] flags);
 wire [23:0] ma,mb; wire [47:0] mc;
 wire [5:0] st; wire signed [9:0] ex; wire [4:0] align_dist; wire [25:0] hi;
 mulAddRecFNToRaw_preMul #(8,24) pre(1'b1,op,a,b,c,rm,ma,mb,mc,st,ex,align_dist,hi);
 reg [23:0] a1,b1; reg [47:0] c1;
 reg [5:0] s1,s2,s3; reg signed [9:0] e1,e2,e3;
 reg [4:0] d1,d2,d3; reg [25:0] h1,h2,h3;
 reg [2:0] r1,r2,r3,r4;
 reg [47:0] product2,c2; reg [48:0] sum3;
 wire inv,nan,inf,zero,sign; wire signed [9:0] exp; wire [26:0] sig;
 mulAddRecFNToRaw_postMul #(8,24) post(s3,e3,d3,h3,sum3,r3,inv,nan,inf,zero,sign,exp,sig);
 reg iv4,n4,i4,z4,s4; reg signed [9:0] e4; reg [26:0] sig4;
 reg [4:0] v;
 assign valid=v[4];
 fp_round_pipe #(8,26,8,24,0) rnd(clk,1'b1,iv4,1'b0,n4,i4,z4,s4,e4,sig4,r4,result,flags);
 always @(posedge clk) begin
  if(!rst_n) v<=0; else v<={v[3:0],start};
  a1<=ma; b1<=mb; c1<=mc; s1<=st; e1<=ex; d1<=align_dist; h1<=hi; r1<=rm;
  product2<=a1*b1; c2<=c1; s2<=s1; e2<=e1; d2<=d1; h2<=h1; r2<=r1;
  sum3<={1'b0,product2}+{1'b0,c2}; s3<=s2; e3<=e2; d3<=d2; h3<=h2; r3<=r2;
  iv4<=inv; n4<=nan; i4<=inf; z4<=zero; s4<=sign; e4<=exp; sig4<=sig; r4<=r3;
 end
endmodule

