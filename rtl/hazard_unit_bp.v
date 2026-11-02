`timescale 1ns/1ps
// hazard_unit_bp.v -- stall and flush control with branch prediction support
//                     (plain Verilog-2001)
//
// Changes from basic hazard unit:
//   * Flushes trigger on MISPREDICTIONS rather than all taken branches.
//   * On correct prediction: 0-cycle penalty (no flush).
//   * On misprediction: 2-cycle penalty to redirect to corrected PC.

module hazard_unit_bp (
    input wire UsesRs1D, UsesRs2D,
    input  wire [4:0] Rs1D,
    input  wire [4:0] Rs2D,
    input  wire [4:0] RdE,
    input  wire       LoadE,          // instruction in EX is a load
    input  wire       BranchE,        // instruction in EX is a branch
    input  wire       JumpE,          // instruction in EX is a jump
    input  wire       BranchTakenE,   // branch condition result from branch_unit
    input  wire       PredictTakenE,  // what was predicted in IF for this instruction
    input  wire [31:0] PredictedPCE,  // predicted target address
    input  wire [31:0] PCTargetE,     // actual computed target (PC + imm)
    input  wire [31:0] PCPlus4E,      // PC+4 of the branch instruction

    output wire       StallF,
    output wire       StallD,
    output wire       FlushD,
    output wire       FlushE,

    // Corrected PC on misprediction (fed back to PC mux)
    output wire       MispredictE,
    output wire [31:0] CorrectedPCE
);

    // ----------------------------------------------------------------
    // Load-use stall (unchanged)
    // ----------------------------------------------------------------
    wire lwStall = LoadE && (RdE != 5'd0) && ((UsesRs1D && RdE == Rs1D) || (UsesRs2D && RdE == Rs2D));

    // ----------------------------------------------------------------
    // Misprediction detection
    // ----------------------------------------------------------------
    wire ActualTakenE = (BranchE & BranchTakenE) | JumpE;

    // Misprediction cases:
    //   1. Predicted taken, but actually not-taken
    //   2. Predicted not-taken, but actually taken
    //   3. Predicted taken to wrong target
    wire wrong_direction = (PredictTakenE != ActualTakenE);
    wire wrong_target    = PredictTakenE & ActualTakenE & (PredictedPCE != PCTargetE);

    assign MispredictE = wrong_direction | wrong_target;

    // Corrected PC:
    //   If actually taken -> go to PCTargetE
    //   If actually not-taken -> go to PCPlus4E (fall-through)
    assign CorrectedPCE = ActualTakenE ? PCTargetE : PCPlus4E;

    // ----------------------------------------------------------------
    // Stall and flush outputs
    // ----------------------------------------------------------------
    assign StallF = lwStall && !MispredictE;
    assign StallD = lwStall && !MispredictE;
    assign FlushD = MispredictE;                     // squash IF instruction on mispredict
    assign FlushE = lwStall | MispredictE;           // bubble into ID/EX

endmodule
