`timescale 1ns/1ps
module tb_fp_reset;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,active=0; wire done;wire [7:0] csr;
 // fdiv.s f4,f1,f2, RNE
 fp_engine dut(.clk(clk),.rst_n(rst_n),.active(active),.consume(1'b0),
   .instr(32'h18208253),.x(32'd0),.mem_data(32'd0),.done(done),.fcsr(csr));
 initial begin
  repeat(3) @(posedge clk);#1;
  dut.rf[1]=32'h3f800000;dut.rf[2]=32'h40400000;dut.rf[4]=32'hdeadbeef;
  @(negedge clk);rst_n=1;active=1;
  repeat(4) @(posedge clk);#1;
  if(!dut.busy || done) $fatal(1,"division did not start");
  @(negedge clk);rst_n=0;active=0;
  @(posedge clk);#1;
  @(negedge clk);rst_n=1;
  repeat(40) @(posedge clk);#1;
  if(done || dut.busy || csr!==0 || dut.rf[4]!==32'hdeadbeef) $fatal(1,"reset did not cancel division");
  @(negedge clk);active=1;
  repeat(40) @(posedge clk);#1;
  if(!done || dut.rf[4]!==32'h3eaaaaab || csr!==1) $fatal(1,"division restart failed");
  $display("PASS FP reset cancellation and restart");$finish;
 end
endmodule
