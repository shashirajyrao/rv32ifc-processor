`timescale 1ns/1ps
module tb_fp_vectors;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,active=0,consume=0;reg [31:0] ins=0,x=0;
 wire done,illegal,iw;wire [31:0] result;wire [7:0] fcsr;
 fp_engine dut(.clk(clk),.rst_n(rst_n),.active(active),.consume(consume),.instr(ins),.x(x),.mem_data(32'd0),
 .done(done),.result(result),.illegal(illegal),.int_write(iw),.fcsr(fcsr));
 reg [31:0] vec[0:65535];integer n,count,cycles,show;
 initial begin
  if(!$value$plusargs("COUNT=%d",count)) $fatal(1,"COUNT required");
  if(!$value$plusargs("SHOW=%d",show)) show=0;
  if(count<1 || count>8192) $fatal(1,"COUNT outside vector memory capacity");
  $readmemh("fp_vectors.hex",vec,0,count*8-1);
  for(n=0;n<count;n=n+1) begin
   @(negedge clk);rst_n=0;active=0;consume=0;
   @(posedge clk);#1;
   @(negedge clk);
   ins=vec[n*8];dut.rf[1]=vec[n*8+1];dut.rf[2]=vec[n*8+2];dut.rf[3]=vec[n*8+3];
   x=vec[n*8+4];dut.frm=vec[n*8+5][2:0];rst_n=1;active=1;cycles=0;
   while(!done && cycles<80) begin @(posedge clk);#1;cycles=cycles+1;end
   if(!done || illegal || result!==vec[n*8+6] || fcsr[4:0]!==vec[n*8+7][4:0])
    $fatal(1,"vector %0d ins=%h a=%h b=%h c=%h result=%h expected=%h flags=%h expected=%h",n,ins,vec[n*8+1],vec[n*8+2],vec[n*8+3],result,vec[n*8+6],fcsr[4:0],vec[n*8+7][4:0]);
   if(n<show) $display("VECTOR %0d %h %h %h %h %h %h %h %h %h %0d %b",n,ins,vec[n*8+1],vec[n*8+2],vec[n*8+3],x,result,vec[n*8+6],fcsr[4:0],vec[n*8+7][4:0],cycles,iw);
  end
  $display("PASS %0d independent floating-point vectors",count);$finish;
 end
endmodule
