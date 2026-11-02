`timescale 1ns/1ps
// forwarding_unit.v -- operand forwarding into EX (plain Verilog-2001)
//
// For each source operand of the instruction in EX, pick the newest value:
//   MEM stage result (instruction one ahead)   -> 2'b10
//   WB  stage result (instruction two ahead)   -> 2'b01
//   register file value read in ID             -> 2'b00
// MEM has priority over WB. x0 is never forwarded.
// (A load in MEM is never forwarded from MEM: the load-use stall guarantees the
//  dependent instruction reaches EX only when the load is already in WB.)

`include "riscv_defs.vh"

module forwarding_unit (
    input  wire [4:0] Rs1E,
    input  wire [4:0] Rs2E,
    input  wire [4:0] RdM,
    input  wire [4:0] RdW,
    input  wire       RegWriteM,
    input  wire       RegWriteW,

    output reg  [1:0] ForwardAE,
    output reg  [1:0] ForwardBE
);

    always @(*) begin
        if      (RegWriteM && (RdM != 5'd0) && (RdM == Rs1E)) ForwardAE = `FWD_MEM;
        else if (RegWriteW && (RdW != 5'd0) && (RdW == Rs1E)) ForwardAE = `FWD_WB;
        else                                                  ForwardAE = `FWD_NONE;

        if      (RegWriteM && (RdM != 5'd0) && (RdM == Rs2E)) ForwardBE = `FWD_MEM;
        else if (RegWriteW && (RdW != 5'd0) && (RdW == Rs2E)) ForwardBE = `FWD_WB;
        else                                                  ForwardBE = `FWD_NONE;
    end

endmodule
