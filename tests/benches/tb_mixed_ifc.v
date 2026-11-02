`timescale 1ns/1ps
module tb_mixed_ifc;
reg clk=0;always #5 clk=~clk;reg rst_n=0;
integer cycles=0,retired=0,stop_pc,expected_count,k,errors=0;
reg [31:0] exp_x[0:31],exp_f[0:31],exp_m[0:255],exp_pc[0:255];
real cpi;
riscv_pipe_top dut(.clk(clk),.rst_n(rst_n));
initial begin
 for(k=0;k<32;k=k+1) begin exp_x[k]=0;exp_f[k]=0;end
 for(k=0;k<256;k=k+1) exp_m[k]=0;
 `include "mixed_expected.vh"
 repeat(4) @(posedge clk);#1 rst_n=1;
end
task check;
 input [31:0] got,want;input [127:0] kind;input integer index;
 begin
 if(got!==want) begin errors=errors+1;$display("FAIL %0s[%0d] got=%h expected=%h",kind,index,got,want);end
 else if(want!=0) $display("PASS %0s[%0d] = %h",kind,index,got);
 end
endtask
always @(negedge clk) if(rst_n) begin
 cycles=cycles+1;
 if(dut.Trap) $fatal(1,"TRAP pc=%h cause=%h",dut.TrapPC,dut.TrapCause);
 if(dut.ValidW) begin
  if(retired>=expected_count || dut.PCW!==exp_pc[retired]) $fatal(1,"retirement order mismatch at %0d PC=%h",retired,dut.PCW);
  $display("RETIRE cycle=%0d PC=%h expanded_instruction=%h",cycles,dut.PCW,dut.InstrW);
  retired=retired+1;
  if(dut.PCW==stop_pc) begin
   // This terminal instruction has no writeback. Older writes have completed.
   for(k=0;k<32;k=k+1) begin check(dut.u_rf.rf[k],exp_x[k],"X",k);check(dut.u_fp.rf[k],exp_f[k],"F",k);end
   for(k=0;k<256;k=k+1) check(dut.u_dmem.mem[k],exp_m[k],"MEM",k);
   check({24'd0,dut.u_fp.fcsr},0,"FCSR",0);
   if(retired!=expected_count) $fatal(1,"count mismatch");
   cpi=1.0*cycles/retired;
   $display("MIXED RV32IFC cycles=%0d retired=%0d CPI=%0f",cycles,retired,cpi);
   $display("Checked all 32 integer registers, 32 FP registers, 256 memory words, FCSR and exact retirement order.");
   if(errors) $fatal(1,"RESULT FAIL: %0d errors",errors);
   $display("RESULT PASS");$finish;
  end
 end
 if(cycles>10000) $fatal(1,"TIMEOUT");
end
endmodule
