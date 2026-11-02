`timescale 1ns/1ps
// branch_unit.v -- branch condition comparator (plain Verilog-2001)
//
//   funct3  instr   condition taken
//   000     beq     a == b
//   001     bne     a != b
//   100     blt     signed   a <  b
//   101     bge     signed   a >= b
//   110     bltu    unsigned a <  b
//   111     bgeu    unsigned a >= b
//   010/011 (invalid for branches) -> never taken
//
// a = rs1, b = rs2. The output is only used when the instruction is a branch.

module branch_unit (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  funct3,
    output reg         take
);

    wire signed [31:0] a_s = a;
    wire signed [31:0] b_s = b;

    always @(*) begin
        case (funct3)
            3'b000:  take = (a   == b  );   // beq
            3'b001:  take = (a   != b  );   // bne
            3'b100:  take = (a_s <  b_s);   // blt
            3'b101:  take = (a_s >= b_s);   // bge
            3'b110:  take = (a   <  b  );   // bltu
            3'b111:  take = (a   >= b  );   // bgeu
            default: take = 1'b0;
        endcase
    end

endmodule
