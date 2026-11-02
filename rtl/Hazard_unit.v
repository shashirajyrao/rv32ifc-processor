`timescale 1ns/1ps
// hazard_unit.v -- stall and flush control for the 5-stage pipeline (plain Verilog-2001)
//
// Load-use hazard: a load in EX whose destination is a source of the instruction
//   in ID. The load data only exists after MEM, so the pipeline stalls one cycle:
//   PC and IF/ID are held, and a bubble is inserted into ID/EX.
//
// Control hazard: a taken branch or jump is resolved in EX (PCSrcE). The two
//   younger instructions (one in IF, one in ID) are on the wrong path and are
//   squashed: IF/ID and ID/EX are turned into bubbles. Penalty = 2 cycles.

module hazard_unit (
    input wire UsesRs1D, UsesRs2D,
    input  wire [4:0] Rs1D,
    input  wire [4:0] Rs2D,
    input  wire [4:0] RdE,
    input  wire       LoadE,      // instruction in EX is a load
    input  wire       PCSrcE,     // taken branch / jump in EX

    output wire       StallF,
    output wire       StallD,
    output wire       FlushD,
    output wire       FlushE
);

    wire lwStall = LoadE && (RdE != 5'd0) && ((UsesRs1D && RdE == Rs1D) || (UsesRs2D && RdE == Rs2D));

    assign StallF = lwStall && !PCSrcE;
    assign StallD = lwStall && !PCSrcE;
    assign FlushD = PCSrcE;
    assign FlushE = lwStall | PCSrcE;

endmodule
