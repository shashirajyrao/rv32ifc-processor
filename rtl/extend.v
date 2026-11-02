`timescale 1ns/1ps
// extend.v -- immediate generator (plain Verilog-2001)
// Input is Instr[31:7]; bit indices below are the original instruction bit numbers.

`include "riscv_defs.vh"

module extend (
    input  wire [31:7] instr,
    input  wire [2:0]  ImmSrc,
    output reg  [31:0] ImmExt
);

    always @(*) begin
        case (ImmSrc)
            `IMM_I:  ImmExt = {{20{instr[31]}}, instr[31:20]};
            `IMM_S:  ImmExt = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `IMM_B:  ImmExt = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            `IMM_J:  ImmExt = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            `IMM_U:  ImmExt = {instr[31:12], 12'b0};
            default: ImmExt = 32'd0;
        endcase
    end

endmodule
