`timescale 1ns/1ps
`include "riscv_defs.vh"

module riscv_top #(
    parameter ENABLE_C=1,
    parameter IMEM_FILE    = "program.hex",
    parameter IMEM_ADDR_BITS = 8,               
    parameter DMEM_ADDR_BITS = 8,
    parameter RESET_VECTOR = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,        

    output reg  [31:0] PC,
    output wire [31:0] Instr,
    output wire [31:0] ALUResult,    
    output wire [31:0] WriteData,    
    output reg Trap,
    output reg [31:0] TrapCause, TrapPC, TrapValue,
    output wire        MemWrite
);

    wire [31:0] PCNext, PCPlus4, PCTarget;
    wire [31:0] RD1, SrcA, SrcB, ImmExt, ReadData, Result;
    wire        Zero;           
    wire        BranchTaken;    


    wire Ext, FPDone, FPIllegal, FPIntWrite, FPLoad, FPStore, FPWrite;
    wire [31:0] FPResult, FPAddress, FPData, RawInstr; wire [2:0] Length; wire BadCompressed;
    wire PCSrc, ALUSrc, RegWrite, RawMemWrite, JumpReg;
    wire FetchAccess, FetchMisaligned, DataAccess, DataMisaligned;
    wire Illegal, Ecall, Ebreak, Fault;
    wire [31:0] Cause, Value;
    wire [1:0]  ResultSrc;
    wire [1:0]  ALUSrcA;
    wire [2:0]  ImmSrc;
    wire [3:0]  ALUControl;

  
    always @(posedge clk) begin
        if (!rst_n) PC <= RESET_VECTOR;
        else if (!Trap && !Fault && (!Ext || FPDone)) PC <= PCNext;
    end

    assign PCPlus4 = PC + Length;
    assign PCTarget = JumpReg ? ((RD1 + ImmExt) & 32'hfffffffe) : PC + ImmExt;               
    assign PCNext   = PCSrc ? PCTarget : PCPlus4;


    imem #(.ADDR_BITS(IMEM_ADDR_BITS), .INIT_FILE(IMEM_FILE),.ENABLE_C(ENABLE_C)) u_imem (
        .a  (PC),
        .rd (Instr), .Length(Length), .RawInstr(RawInstr), .IllegalCompressed(BadCompressed), .AccessFault(FetchAccess), .Misaligned(FetchMisaligned)
    );


    control_unit u_ctrl (
        .Instr(Instr), .Ext(Ext), .JumpReg(JumpReg),
        .Illegal(Illegal), .Ecall(Ecall), .Ebreak(Ebreak),
        .BranchTaken(BranchTaken),
        .PCSrc      (PCSrc),
        .ResultSrc  (ResultSrc),
        .MemWrite   (RawMemWrite),
        .ALUControl (ALUControl),
        .ALUSrc     (ALUSrc),
        .ALUSrcA    (ALUSrcA),
        .ImmSrc     (ImmSrc),
        .RegWrite   (RegWrite)
    );


    regfile u_rf (
        .clk (clk),
        .we3 (RegWrite && rst_n && !Trap && !Fault && (!Ext || (FPDone && FPIntWrite))),
        .a1  (Instr[19:15]),
        .a2  (Instr[24:20]),
        .a3  (Instr[11:7]),
        .wd3 (Result),
        .rd1 (RD1),
        .rd2 (WriteData)
    );


    extend u_ext (
        .instr  (Instr[31:7]),
        .ImmSrc (ImmSrc),
        .ImmExt (ImmExt)
    );


    branch_unit u_br (
        .a      (RD1),
        .b      (WriteData),          
        .funct3 (Instr[14:12]),
        .take   (BranchTaken)
    );


    assign SrcA = (ALUSrcA == `ASRC_PC)   ? PC :
                  (ALUSrcA == `ASRC_ZERO) ? 32'd0 :
                                            RD1;

    assign SrcB = ALUSrc ? ImmExt : WriteData;

    alu u_alu (
        .a        (SrcA),
        .b        (SrcB),
        .alu_ctrl (ALUControl),
        .result   (ALUResult),
        .zero     (Zero)
    );


    dmem #(.ADDR_BITS(DMEM_ADDR_BITS)) u_dmem (
        .clk (clk),
        .we  (MemWrite),
        .a   (Ext ? FPAddress : ALUResult),
        .wd  (Ext ? FPData : WriteData),
        .rd  (ReadData), .funct3(Ext ? 3'd2 : Instr[14:12]),
        .AccessFault(DataAccess), .Misaligned(DataMisaligned)
    );

    assign Result = Ext ? FPResult : (ResultSrc == `RES_MEM) ? ReadData :
                    (ResultSrc == `RES_PC4) ? PCPlus4  :
                                              ALUResult;


    assign MemWrite=(Ext ? FPWrite : RawMemWrite) && rst_n && !Trap && !Fault;
    exception_unit #(.ENABLE_C(ENABLE_C)) u_exc (
      .FetchAccess(FetchAccess), .FetchMisaligned(FetchMisaligned),
      .Illegal(Illegal || BadCompressed || (Ext && FPIllegal)), .Ecall(Ecall), .Ebreak(Ebreak), .Taken(PCSrc),
      .Load(Ext ? FPLoad : ResultSrc==`RES_MEM), .Store(Ext ? FPStore : RawMemWrite),
      .DataAccess(DataAccess), .DataMisaligned(DataMisaligned),
      .PC(PC), .Instr(RawInstr), .Target(PCTarget), .Address(Ext ? FPAddress : ALUResult),
      .Fault(Fault), .Cause(Cause), .Value(Value)
    );
    always @(posedge clk) begin
      if (!rst_n) begin Trap<=0; TrapCause<=0; TrapPC<=0; TrapValue<=0; end
      else if (!Trap && Fault) begin
        Trap<=1; TrapCause<=Cause; TrapPC<=PC; TrapValue<=Value;
      end
    end
    fp_engine u_fp(.clk(clk),.rst_n(rst_n),.active(Ext && !Trap && !Fault),
      .consume(Ext && FPDone && !Trap && !Fault),.instr(Instr),.x(RD1),.mem_data(ReadData),
      .done(FPDone),.result(FPResult),.illegal(FPIllegal),.int_write(FPIntWrite),
      .mem_load(FPLoad),.mem_store(FPStore),.mem_write(FPWrite),.address(FPAddress),.store_data(FPData));
endmodule

