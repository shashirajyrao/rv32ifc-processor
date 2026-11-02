`timescale 1ns/1ps
module tb_fc;
 reg clk=0; always #5 clk=~clk; reg rst_n=0;
 integer k; reg [31:0] a,b;
 integer trace_cycles=0,cycle=0;
 initial begin if(!$value$plusargs("TRACE_CYCLES=%d",trace_cycles)) trace_cycles=0; end
 always @(negedge clk) if(rst_n) begin
  cycle=cycle+1;
  if(cycle<=trace_cycles)
   $display("TRACE cycle=%0d IF_PC=%h IF_raw=%h ID_valid=%b ID_PC=%h EX_valid=%b EX_PC=%h MEM_valid=%b WB_valid=%b FP_drain=%b FP_wait=%b",cycle,pl.PCF,pl.RawInstrF,pl.ValidD,pl.PCD,pl.ValidE,pl.PCE,pl.ValidM,pl.ValidW,pl.ExtDrain,pl.ExtWait);
 end
 riscv_top #(.IMEM_FILE("fc.hex")) sc(.clk(clk),.rst_n(rst_n));
 riscv_pipe_top #(.IMEM_FILE("fc.hex")) pl(.clk(clk),.rst_n(rst_n));
 initial begin
  repeat(4) @(posedge clk); #1 rst_n=1;
  repeat(1600) @(posedge clk); #1;
  for(k=0;k<32;k=k+1) begin
   a=sc.u_rf.rf[k];b=pl.u_rf.rf[k]; $display("X %0d %h %h",k,a,b);
   a=sc.u_fp.rf[k];b=pl.u_fp.rf[k]; $display("F %0d %h %h",k,a,b);
  end
  for(k=0;k<256;k=k+1) begin a=sc.u_dmem.mem[k];b=pl.u_dmem.mem[k]; $display("M %0d %h %h",k,a,b); end
  $display("CSR %h %h",sc.u_fp.fcsr,pl.u_fp.fcsr);
  $display("TRAP S %b %h %h %h",sc.Trap,sc.TrapCause,sc.TrapPC,sc.TrapValue);
  $display("TRAP P %b %h %h %h",pl.Trap,pl.TrapCause,pl.TrapPC,pl.TrapValue);
  $display("DONE");$finish;
 end
endmodule
