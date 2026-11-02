`timescale 1ns/1ps
`include "riscv_defs.vh"

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] result,
    output wire        zero
);

 
    wire signed [31:0] a_s = a;
    wire signed [31:0] b_s = b;

    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (alu_ctrl)
            `ALU_ADD : result = a + b;
            `ALU_SUB : result = a - b;
            `ALU_SLL : result = a << shamt;
            `ALU_SLT : result = (a_s < b_s) ? 32'd1 : 32'd0;
            `ALU_SLTU: result = (a   < b  ) ? 32'd1 : 32'd0;
            `ALU_XOR : result = a ^ b;
            `ALU_SRL : result = a >> shamt;
            `ALU_SRA : result = a_s >>> shamt;
            `ALU_OR  : result = a | b;
            `ALU_AND : result = a & b;
            default  : result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
