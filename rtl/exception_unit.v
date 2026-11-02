`timescale 1ns/1ps
// Execution-environment report, not a privileged CSR/handler implementation.
module exception_unit #(parameter ENABLE_C=1) (
 input wire FetchAccess, FetchMisaligned, Illegal, Ecall, Ebreak,
 input wire Taken, Load, Store, DataAccess, DataMisaligned,
 input wire [31:0] PC, Instr, Target, Address,
 output reg Fault, output reg [31:0] Cause, Value
);
 always @(*) begin
  Fault=1; Cause=0; Value=0;
  if (FetchMisaligned) begin Cause=0; Value=PC; end
  else if (FetchAccess) begin Cause=1; Value=PC; end
  else if (Illegal) begin Cause=2; Value=Instr; end
  else if (Ebreak) begin Cause=3; Value=PC; end
  else if (Ecall) begin Cause=11; Value=0; end
  else if (Taken && (ENABLE_C ? Target[0] : Target[1:0]!=0)) begin Cause=0; Value=Target; end
  else if ((Load || Store) && DataMisaligned) begin Cause=Store ? 6 : 4; Value=Address; end
  else if ((Load || Store) && DataAccess) begin Cause=Store ? 7 : 5; Value=Address; end
  else Fault=0;
 end
endmodule
