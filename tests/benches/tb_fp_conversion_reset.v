`timescale 1ns/1ps
module tb_fp_conversion_reset;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,active=0; wire done; wire [7:0] csr; integer delay;
fp_engine dut(.clk(clk),.rst_n(rst_n),.active(active),.consume(1'b0),
 .instr(32'hd0008253),.x(32'd4),.mem_data(32'd0),.done(done),.fcsr(csr));
initial begin
 for(delay=1;delay<=3;delay=delay+1) begin
  @(negedge clk);rst_n=0;active=0;
  repeat(2) @(posedge clk);
  @(negedge clk);dut.rf[1]=32'h3f800000;dut.rf[2]=32'h40400000;dut.rf[4]=32'hdeadbeef;rst_n=1;active=1;
  repeat(delay) @(posedge clk);
  @(negedge clk);rst_n=0;active=0;
  @(posedge clk); @(negedge clk);rst_n=1;
  repeat(12) @(posedge clk);#1;
  if(done || dut.busy || csr!==0 || dut.rf[4]!==32'hdeadbeef) $fatal(1,"pipeline reset failure at delay %0d",delay);
  @(negedge clk);active=1;
  repeat(12) @(posedge clk);#1;
  if(!done || dut.rf[4]!==32'h40800000 || csr!==0) $fatal(1,"restart failure");
 end
 $display("PASS arithmetic reset at all three conversion pipeline boundaries and restart");$finish;
end
endmodule


