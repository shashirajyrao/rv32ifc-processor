`timescale 1ns/1ps
module tb_cpi;
reg clk=0;always #5 clk=~clk;reg rst_n=0;
integer cycles=0,retired=0,stop_pc,expected,waits=0,drains=0;
real cpi;
riscv_pipe_top #(.IMEM_FILE("cpi.hex")) dut(.clk(clk),.rst_n(rst_n));
initial begin
 if(!$value$plusargs("STOP=%d",stop_pc)) $fatal(1,"missing STOP");
 if(!$value$plusargs("COUNT=%d",expected)) $fatal(1,"missing COUNT");
 repeat(4) @(posedge clk);#1 rst_n=1;
end
// WB is sampled after pipeline registers settle. Include the terminal marker
// as one retired instruction; exclude later iterations of its self-loop.
always @(negedge clk) if(rst_n) begin
 cycles=cycles+1;
 if(dut.ExtWait) waits=waits+1;
 if(dut.ExtDrain) drains=drains+1;
 if(dut.Trap) $fatal(1,"unexpected trap PC=%h cause=%h",dut.TrapPC,dut.TrapCause);
 if(dut.ValidW) begin
  retired=retired+1;
  if(dut.PCW==stop_pc) begin
   if(retired!=expected) $fatal(1,"retirement count %0d expected %0d",retired,expected);
   cpi=1.0*cycles/retired;
   $display("CPI_RESULT %0d %0d %0f %0d %0d",cycles,retired,cpi,waits,drains);
   $finish;
  end
 end
 if(cycles>20000) $fatal(1,"benchmark timeout");
end
endmodule
