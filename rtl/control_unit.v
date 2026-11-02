`timescale 1ns/1ps
`include "riscv_defs.vh"
// Full RV32I encoding validation. Unsupported extensions raise Illegal.
module control_unit (
 input wire [31:0] Instr, input wire BranchTaken,
 output wire PCSrc, output reg [1:0] ResultSrc, output reg MemWrite,
 output reg [3:0] ALUControl, output reg ALUSrc,
 output reg [1:0] ALUSrcA, output reg [2:0] ImmSrc,
 output reg RegWrite, Branch, Jump, JumpReg,
 output reg UsesRs1, UsesRs2, Illegal, Ecall, Ebreak, Ext
);
 wire [6:0] op=Instr[6:0]; wire [2:0] f3=Instr[14:12]; wire [6:0] f7=Instr[31:25];
 always @(*) begin
  ResultSrc=`RES_ALU; MemWrite=0; ALUControl=`ALU_ADD;
  ALUSrc=0; ALUSrcA=`ASRC_RS1; ImmSrc=`IMM_I;
  RegWrite=0; Branch=0; Jump=0; JumpReg=0;
  Ext=0; UsesRs1=0; UsesRs2=0; Illegal=0; Ecall=0; Ebreak=0;
  case(op)
   `OP_LOAD: begin
    UsesRs1=1; ALUSrc=1; ResultSrc=`RES_MEM; RegWrite=1;
    if (!(f3==0 || f3==1 || f3==2 || f3==4 || f3==5)) Illegal=1;
   end
   `OP_STORE: begin
    UsesRs1=1; UsesRs2=1; ALUSrc=1; ImmSrc=`IMM_S; MemWrite=1;
    if (!(f3==0 || f3==1 || f3==2)) Illegal=1;
   end
   `OP_RTYPE, `OP_ITYPE: begin
    UsesRs1=1; UsesRs2=(op==`OP_RTYPE); RegWrite=1; ALUSrc=(op==`OP_ITYPE);
    case(f3)
     0: ALUControl=(op==`OP_RTYPE && f7==7'h20) ? `ALU_SUB : `ALU_ADD;
     1: ALUControl=`ALU_SLL;
     2: ALUControl=`ALU_SLT;
     3: ALUControl=`ALU_SLTU;
     4: ALUControl=`ALU_XOR;
     5: ALUControl=Instr[30] ? `ALU_SRA : `ALU_SRL;
     6: ALUControl=`ALU_OR;
     7: ALUControl=`ALU_AND;
    endcase
    if (op==`OP_RTYPE && !(f7==0 || (f7==7'h20 && (f3==0 || f3==5)))) Illegal=1;
    if (op==`OP_ITYPE && f3==1 && f7!=0) Illegal=1;
    if (op==`OP_ITYPE && f3==5 && !(f7==0 || f7==7'h20)) Illegal=1;
   end
   `OP_BRANCH: begin
    UsesRs1=1; UsesRs2=1; Branch=1; ImmSrc=`IMM_B;
    if (f3==2 || f3==3) Illegal=1;
   end
   `OP_JAL: begin Jump=1; RegWrite=1; ImmSrc=`IMM_J; ResultSrc=`RES_PC4; end
   `OP_JALR: begin
    UsesRs1=1; Jump=1; JumpReg=1; RegWrite=1; ResultSrc=`RES_PC4;
    if (f3!=0) Illegal=1;
   end
   `OP_LUI, `OP_AUIPC: begin
    RegWrite=1; ImmSrc=`IMM_U; ALUSrc=1;
    ALUSrcA=(op==`OP_LUI) ? `ASRC_ZERO : `ASRC_PC;
   end
   7'h0f: begin
    // FENCE is a NOP for this in-order memory; reserved fm/rs1/rd ignored.
    if (f3!=0) Illegal=1; // FENCE.I is a separate, unsupported extension.
   end
   7'h07,7'h27,7'h43,7'h47,7'h4b,7'h4f,7'h53: begin
    Ext=1; UsesRs1=1;
    RegWrite=(op==7'h53 && (f7==7'h60 || f7==7'h70 || f7==7'h50));
   end
   7'h73: begin
    if (f3!=0 && Instr[31:20]>=1 && Instr[31:20]<=3) begin Ext=1; RegWrite=1; UsesRs1=!f3[2]; end
    else if (Instr==32'h00000073) Ecall=1;
    else if (Instr==32'h00100073) Ebreak=1;
    else Illegal=1;
   end
   default: Illegal=1;
  endcase
  if (Illegal) begin
   RegWrite=0; MemWrite=0; Branch=0; Jump=0; JumpReg=0; UsesRs1=0; UsesRs2=0;
  end
 end
 assign PCSrc=(Branch & BranchTaken) | Jump;
endmodule
