`timescale 1ns/1ps
// riscv_pipe_top.v -- 5-stage pipelined RV32I core WITH Branch Prediction
//                     (plain Verilog-2001)
//
// Features:
//   * Dynamic Branch Prediction in IF stage: 2-bit Saturating Counter BHT + BTB
//   * Piped prediction metadata (PredictTaken, PredictedPC) through IF/ID and ID/EX
//   * Hazard Unit with Misprediction Detection:
//       - Correct prediction: 0-cycle flush penalty (continuous 1 CPI execution!)
//       - Misprediction: 2-cycle flush penalty to redirect to corrected PC
//   * Operand Forwarding (MEM->EX, WB->EX) & Write-first Register File
//   * Load-Use 1-cycle stall interlock

`include "riscv_defs.vh"

module riscv_pipe_top #(
    parameter ENABLE_C=1,
    parameter IMEM_FILE      = "program.hex",
    parameter IMEM_ADDR_BITS = 8,
    parameter DMEM_ADDR_BITS = 8,
    parameter RESET_VECTOR   = 32'h0000_0000,
    parameter BHT_ADDR_BITS  = 6               // 64-entry branch predictor
)(
    input  wire        clk,
    input  wire        rst_n,        // active-low, synchronous
    output reg Trap,
    output reg [31:0] TrapCause, TrapPC, TrapValue,
    output reg  [31:0] PCF           // fetch address (observation)
);

    localparam [31:0] NOP = 32'h0000_0013;      // addi x0, x0, 0

    // ============================================================
    // Hazard / forwarding control wires
    // ============================================================
    wire StallF,StallD,FlushD,FlushE;
    wire HazStallF,HazStallD,HazFlushE,ExtDrain,ExtWait;
    wire FPDone,FPIllegal,FPIntWrite,FPLoad,FPStore,FPWrite;
    wire [31:0] FPResult,FPAddress,FPData;
    assign ExtDrain=ValidD && ExtD && (ValidE || ValidM || ValidW);
    assign ExtWait=ValidE && ExtE && !FPDone && !FaultE;
    assign StallF=(HazStallF || ExtDrain || ExtWait) && !MispredictE;
    assign StallD=(HazStallD || ExtDrain || ExtWait) && !MispredictE;
    assign FlushE=HazFlushE || (ExtDrain && !ExtWait);

    wire [1:0]  ForwardAE, ForwardBE;
    wire MispredictE, TrapEventM; wire FaultE; wire [31:0] CauseE, ValueE;
    wire [31:0] CorrectedPCE;
    wire        PCSrcE = MispredictE;           // Pipeline redirect on misprediction

    // EX/MEM destination info (used by forwarding unit in EX)
    reg         RegWriteM;
    reg  [4:0]  RdM;

    // ============================================================
    // IF stage
    // ============================================================
    wire [31:0] InstrF, PCPlus4F, PCNextF, RawInstrF; wire [2:0] LengthF; wire BadCompressedF;

    // Branch prediction wires
    wire PredictTakenF, RawPredictTakenF, BTBHitF;
    wire FetchAccessF, FetchMisalignedF;
    assign PredictTakenF=RawPredictTakenF && !FetchAccessF && !FetchMisalignedF &&
        (InstrF[6:0]==`OP_BRANCH || InstrF[6:0]==`OP_JAL || InstrF[6:0]==`OP_JALR);
    wire [31:0] PredictedPCF;

    // Predictor update wires from EX stage
    wire        BP_UpdateEn;
    wire [31:0] BP_UpdatePC;
    wire        BP_ActualTaken;
    wire [31:0] BP_ActualTarget;

    always @(posedge clk) begin
        if (!rst_n)       PCF <= RESET_VECTOR;
        else if (!Trap && !TrapEventM && !StallF) PCF <= PCNextF;
    end

    assign PCPlus4F = PCF + LengthF;

    // PC Selection:
    //   1. Misprediction Correction: override wrong path with Corrected PC
    //   2. Speculative Fetch: branch predictor predicted TAKEN with known BTB target
    //   3. Default: sequential PC + 4
    assign PCNextF = MispredictE    ? CorrectedPCE :
                     PredictTakenF  ? PredictedPCF :
                                      PCPlus4F;

    imem #(.ADDR_BITS(IMEM_ADDR_BITS), .INIT_FILE(IMEM_FILE),.ENABLE_C(ENABLE_C)) u_imem (
        .a  (PCF),
        .rd (InstrF), .Length(LengthF), .RawInstr(RawInstrF), .IllegalCompressed(BadCompressedF), .AccessFault(FetchAccessF), .Misaligned(FetchMisalignedF)
    );

    branch_predictor #(.BHT_ADDR_BITS(BHT_ADDR_BITS)) u_bp (
        .clk           (clk),
        .rst_n         (rst_n),
        .PCF           (PCF),
        .PredictTakenF (RawPredictTakenF),
        .PredictedPCF  (PredictedPCF),
        .BTBHitF       (BTBHitF),
        .UpdateEn      (BP_UpdateEn),
        .UpdatePC      (BP_UpdatePC),
        .ActualTaken   (BP_ActualTaken),
        .ActualTarget  (BP_ActualTarget)
    );

    // ============================================================
    // IF/ID pipeline register
    // ============================================================
    reg [31:0] InstrD, PCD, PCPlus4D, RawInstrD; reg BadCompressedD;
    reg        PredictTakenD;
    reg [31:0] PredictedPCD;
    reg FetchAccessD, FetchMisalignedD;
    reg        ValidD;                              // trace only

    always @(posedge clk) begin
        if (!rst_n || FlushD || Trap || TrapEventM) begin
            InstrD        <= NOP;
            RawInstrD<=0; BadCompressedD<=0; FetchAccessD<=0; FetchMisalignedD<=0;
            PCD           <= 32'd0;
            PCPlus4D      <= 32'd0;
            PredictTakenD <= 1'b0;
            PredictedPCD  <= 32'd0;
            ValidD        <= 1'b0;
        end else if (!StallD) begin
            InstrD        <= InstrF;
            RawInstrD<=RawInstrF; BadCompressedD<=BadCompressedF; FetchAccessD<=FetchAccessF; FetchMisalignedD<=FetchMisalignedF;
            PCD           <= PCF;
            PCPlus4D      <= PCPlus4F;
            PredictTakenD <= PredictTakenF;
            PredictedPCD  <= PredictedPCF;
            ValidD        <= 1'b1;
        end
    end

    // ============================================================
    // ID stage
    // ============================================================
    wire [4:0]  Rs1D = InstrD[19:15];
    wire [4:0]  Rs2D = InstrD[24:20];
    wire [4:0]  RdD  = InstrD[11:7];

    wire ExtD;
    wire JumpRegD, UsesRs1D, UsesRs2D, IllegalD, EcallD, EbreakD;
    wire        RegWriteD, MemWriteD, BranchD, JumpD, ALUSrcD;
    wire [1:0]  ResultSrcD, ALUSrcAD;
    wire [2:0]  ImmSrcD;
    wire [3:0]  ALUControlD;
    wire [31:0] RD1D, RD2D, ImmExtD;

    // write-back wires (from WB stage)
    wire        RegWriteW;
    wire [4:0]  RdW;
    wire [31:0] ResultW;

    control_unit u_ctrl (
        .Instr(InstrD), .Ext(ExtD), .JumpReg(JumpRegD),
        .UsesRs1(UsesRs1D), .UsesRs2(UsesRs2D),
        .Illegal(IllegalD), .Ecall(EcallD), .Ebreak(EbreakD),
        .BranchTaken (1'b0),                        // branch decided in EX
        .PCSrc       (),
        .ResultSrc   (ResultSrcD),
        .MemWrite    (MemWriteD),
        .ALUControl  (ALUControlD),
        .ALUSrc      (ALUSrcD),
        .ALUSrcA     (ALUSrcAD),
        .ImmSrc      (ImmSrcD),
        .RegWrite    (RegWriteD),
        .Branch      (BranchD),
        .Jump        (JumpD)
    );

    regfile #(.BYPASS(1)) u_rf (
        .clk (clk),
        .we3 (RegWriteW && rst_n && !Trap),
        .a1  (Rs1D),
        .a2  (Rs2D),
        .a3  (RdW),
        .wd3 (ResultW),
        .rd1 (RD1D),
        .rd2 (RD2D)
    );

    extend u_ext (
        .instr  (InstrD[31:7]),
        .ImmSrc (ImmSrcD),
        .ImmExt (ImmExtD)
    );

    // ============================================================
    // ID/EX pipeline register
    // ============================================================
    reg ExtE; reg [31:0] RawInstrE; reg BadCompressedE;
    reg JumpRegE, FetchAccessE, FetchMisalignedE, IllegalE, EcallE, EbreakE;
    reg         RegWriteE, MemWriteE, BranchE, JumpE, ALUSrcE;
    reg  [1:0]  ResultSrcE, ALUSrcAE;
    reg  [3:0]  ALUControlE;
    reg  [2:0]  Funct3E;
    reg  [31:0] RD1E, RD2E, PCE, PCPlus4E, ImmExtE;
    reg  [4:0]  Rs1E, Rs2E, RdE;
    reg         PredictTakenE;
    reg  [31:0] PredictedPCE;
    reg  [31:0] InstrE;                             // trace only
    reg         ValidE;                             // trace only

    always @(posedge clk) begin
        if (!rst_n || FlushE || Trap || TrapEventM) begin
            RegWriteE     <= 1'b0;
            ExtE<=0; RawInstrE<=0; BadCompressedE<=0; JumpRegE<=0; FetchAccessE<=0; FetchMisalignedE<=0; IllegalE<=0; EcallE<=0; EbreakE<=0;
            MemWriteE     <= 1'b0;
            BranchE       <= 1'b0;
            JumpE         <= 1'b0;
            ALUSrcE       <= 1'b0;
            ResultSrcE    <= `RES_ALU;
            ALUSrcAE      <= `ASRC_RS1;
            ALUControlE   <= `ALU_ADD;
            Funct3E       <= 3'd0;
            RD1E          <= 32'd0;
            RD2E          <= 32'd0;
            PCE           <= 32'd0;
            PCPlus4E      <= 32'd0;
            ImmExtE       <= 32'd0;
            Rs1E          <= 5'd0;
            Rs2E          <= 5'd0;
            RdE           <= 5'd0;
            PredictTakenE <= 1'b0;
            PredictedPCE  <= 32'd0;
            InstrE        <= NOP;
            ValidE        <= 1'b0;
        end else if (!ExtWait) begin
            RegWriteE     <= RegWriteD;
            ExtE<=ExtD; RawInstrE<=RawInstrD; BadCompressedE<=BadCompressedD; JumpRegE<=JumpRegD; FetchAccessE<=FetchAccessD; FetchMisalignedE<=FetchMisalignedD;
            IllegalE<=IllegalD; EcallE<=EcallD; EbreakE<=EbreakD;
            MemWriteE     <= MemWriteD;
            BranchE       <= BranchD;
            JumpE         <= JumpD;
            ALUSrcE       <= ALUSrcD;
            ResultSrcE    <= ResultSrcD;
            ALUSrcAE      <= ALUSrcAD;
            ALUControlE   <= ALUControlD;
            Funct3E       <= InstrD[14:12];
            RD1E          <= RD1D;
            RD2E          <= RD2D;
            PCE           <= PCD;
            PCPlus4E      <= PCPlus4D;
            ImmExtE       <= ImmExtD;
            Rs1E          <= Rs1D;
            Rs2E          <= Rs2D;
            RdE           <= RdD;
            PredictTakenE <= PredictTakenD;
            PredictedPCE  <= PredictedPCD;
            InstrE        <= InstrD;
            ValidE        <= ValidD;
        end
    end

    // ============================================================
    // EX stage
    // ============================================================
    wire [31:0] ExecResultM;                        // from EX/MEM

    wire [31:0] SrcAFwdE, WriteDataE, SrcAE, SrcBE, ALUResultE, ExecResultE;
    wire        BranchTakenE;
    wire [31:0] PCTargetE;

    forwarding_unit u_fwd (
        .Rs1E      (Rs1E),
        .Rs2E      (Rs2E),
        .RdM       (RdM),
        .RdW       (RdW),
        .RegWriteM (RegWriteM),
        .RegWriteW (RegWriteW),
        .ForwardAE (ForwardAE),
        .ForwardBE (ForwardBE)
    );

    // Forwarding muxes
    assign SrcAFwdE   = (ForwardAE == `FWD_MEM) ? ExecResultM :
                        (ForwardAE == `FWD_WB ) ? ResultW     : RD1E;
    assign WriteDataE = (ForwardBE == `FWD_MEM) ? ExecResultM :
                        (ForwardBE == `FWD_WB ) ? ResultW     : RD2E;

    // ALU operand muxes
    assign SrcAE = (ALUSrcAE == `ASRC_PC)   ? PCE :
                   (ALUSrcAE == `ASRC_ZERO) ? 32'd0 : SrcAFwdE;
    assign SrcBE = ALUSrcE ? ImmExtE : WriteDataE;

    alu u_alu (
        .a        (SrcAE),
        .b        (SrcBE),
        .alu_ctrl (ALUControlE),
        .result   (ALUResultE),
        .zero     ()
    );

    branch_unit u_br (
        .a      (SrcAFwdE),
        .b      (WriteDataE),
        .funct3 (Funct3E),
        .take   (BranchTakenE)
    );

    assign PCTargetE = JumpRegE ? ((SrcAFwdE + ImmExtE) & 32'hfffffffe) : PCE + ImmExtE;
    assign ExecResultE = ExtE ? FPResult : (ResultSrcE == `RES_PC4) ? PCPlus4E : ALUResultE;

    // Branch predictor update signals from EX
    assign BP_UpdateEn = ValidE && !Trap && !TrapEventM && !FaultE && (BranchE | JumpE);
    assign BP_UpdatePC     = PCE;
    assign BP_ActualTaken  = (BranchE & BranchTakenE) | JumpE;
    assign BP_ActualTarget = PCTargetE;

    // Hazard unit with branch prediction support
    hazard_unit_bp u_haz (
        .UsesRs1D(UsesRs1D), .UsesRs2D(UsesRs2D),
        .Rs1D          (Rs1D),
        .Rs2D          (Rs2D),
        .RdE           (RdE),
        .LoadE         (ResultSrcE == `RES_MEM),
        .BranchE       (BranchE),
        .JumpE         (JumpE),
        .BranchTakenE  (BranchTakenE),
        .PredictTakenE (PredictTakenE),
        .PredictedPCE  (PredictedPCE),
        .PCTargetE     (PCTargetE),
        .PCPlus4E      (PCPlus4E),
        .StallF        (HazStallF),
        .StallD        (HazStallD),
        .FlushD        (FlushD),
        .FlushE        (HazFlushE),
        .MispredictE   (MispredictE),
        .CorrectedPCE  (CorrectedPCE)
    );

    // ============================================================
    // EX/MEM pipeline register
    // ============================================================
    reg MemToRegM, MemWriteM;
    reg [2:0] Funct3M;
    reg FaultM; reg [31:0] CauseM, ValueM;

    reg  [31:0] ExecResultM_r, WriteDataM;
    reg  [31:0] InstrM, PCM;                        // trace only
    reg         ValidM;                             // trace only

    assign ExecResultM = ExecResultM_r;

    always @(posedge clk) begin
        if (!rst_n || Trap || TrapEventM || ExtWait) begin
            RegWriteM     <= 1'b0;
            Funct3M<=0; FaultM<=0; CauseM<=0; ValueM<=0;
            MemToRegM     <= 1'b0;
            MemWriteM     <= 1'b0;
            ExecResultM_r <= 32'd0;
            WriteDataM    <= 32'd0;
            RdM           <= 5'd0;
            InstrM        <= NOP;
            PCM           <= 32'd0;
            ValidM        <= 1'b0;
        end else begin
            RegWriteM     <= RegWriteE && (!ExtE || FPIntWrite);
            Funct3M<=Funct3E; FaultM<=FaultE && ValidE; CauseM<=CauseE; ValueM<=ValueE;
            MemToRegM     <= (ResultSrcE == `RES_MEM);
            MemWriteM     <= MemWriteE;
            ExecResultM_r <= ExecResultE;
            WriteDataM    <= WriteDataE;
            RdM           <= RdE;
            InstrM        <= InstrE;
            PCM           <= PCE;
            ValidM        <= ValidE;
        end
    end

    // ============================================================
    // MEM stage
    // ============================================================
    wire [31:0] ReadDataM;
    wire DataAccessM, DataMisalignedM;
    wire DataFaultM=ValidM && (MemToRegM || MemWriteM) && (DataAccessM || DataMisalignedM);
    assign TrapEventM=ValidM && (FaultM || DataFaultM);

    dmem #(.ADDR_BITS(DMEM_ADDR_BITS)) u_dmem (
        .clk (clk),
        .we  ((ExtE ? FPWrite : MemWriteM) && rst_n && !Trap && !TrapEventM),
        .a   (ExtE ? FPAddress : ExecResultM),
        .wd  (ExtE ? FPData : WriteDataM),
        .rd  (ReadDataM), .funct3(ExtE ? 3'd2 : Funct3M),
        .AccessFault(DataAccessM), .Misaligned(DataMisalignedM)
    );

    // ============================================================
    // MEM/WB pipeline register
    // ============================================================
    reg         RegWriteW_r, MemToRegW;
    reg  [31:0] ExecResultW, ReadDataW;
    reg  [4:0]  RdW_r;
    reg  [31:0] InstrW, PCW;                        // trace only
    reg         ValidW;                             // trace only

    assign RegWriteW = RegWriteW_r;
    assign RdW       = RdW_r;

    always @(posedge clk) begin
        if (!rst_n || Trap || TrapEventM) begin
            RegWriteW_r <= 1'b0;
            MemToRegW   <= 1'b0;
            ExecResultW <= 32'd0;
            ReadDataW   <= 32'd0;
            RdW_r       <= 5'd0;
            InstrW      <= NOP;
            PCW         <= 32'd0;
            ValidW      <= 1'b0;
        end else begin
            RegWriteW_r <= RegWriteM;
            MemToRegW   <= MemToRegM;
            ExecResultW <= ExecResultM;
            ReadDataW   <= ReadDataM;
            RdW_r       <= RdM;
            InstrW      <= InstrM;
            PCW         <= PCM;
            ValidW      <= ValidM;
        end
    end

    // ============================================================
    // WB stage
    // ============================================================
    assign ResultW = MemToRegW ? ReadDataW : ExecResultW;


    // Resolve exceptions in program order at MEM. Older WB commits on the
    // trap edge; the faulting instruction and all younger work are discarded.
    exception_unit #(.ENABLE_C(ENABLE_C)) u_exc (
      .FetchAccess(FetchAccessE), .FetchMisaligned(FetchMisalignedE),
      .Illegal(IllegalE || BadCompressedE || (ExtE && FPIllegal)), .Ecall(EcallE), .Ebreak(EbreakE),
      .Taken(BP_ActualTaken), .Load(ExtE && FPLoad), .Store(ExtE && FPStore),
      .DataAccess(DataAccessM), .DataMisaligned(DataMisalignedM),
      .PC(PCE), .Instr(RawInstrE), .Target(PCTargetE), .Address(ExtE ? FPAddress : ALUResultE),
      .Fault(FaultE), .Cause(CauseE), .Value(ValueE)
    );
    always @(posedge clk) begin
      if (!rst_n) begin Trap<=0; TrapCause<=0; TrapPC<=0; TrapValue<=0; end
      else if (!Trap && TrapEventM) begin
        Trap<=1; TrapPC<=PCM;
        TrapCause<=FaultM ? CauseM : (DataMisalignedM ? (MemWriteM ? 6 : 4) : (MemWriteM ? 7 : 5));
        TrapValue<=FaultM ? ValueM : ExecResultM;
      end
    end
    fp_engine u_fp(.clk(clk),.rst_n(rst_n),.active(ValidE && ExtE && !Trap && !TrapEventM && !FaultE),
      .consume(ExtE && FPDone && !Trap && !TrapEventM),.instr(InstrE),.x(RD1E),.mem_data(ReadDataM),
      .done(FPDone),.result(FPResult),.illegal(FPIllegal),.int_write(FPIntWrite),
      .mem_load(FPLoad),.mem_store(FPStore),.mem_write(FPWrite),.address(FPAddress),.store_data(FPData));
endmodule


