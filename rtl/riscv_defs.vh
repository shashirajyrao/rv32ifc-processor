// riscv_defs.vh -- shared constants for the RV32I core (plain Verilog-2001)
// Include with:  `include "riscv_defs.vh"

`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// ---------------------------------------------------------------
// ALU control codes (alu_ctrl, 4 bits)
// ---------------------------------------------------------------
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_SLL   4'd2
`define ALU_SLT   4'd3
`define ALU_SLTU  4'd4
`define ALU_XOR   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_OR    4'd8
`define ALU_AND   4'd9

// ---------------------------------------------------------------
// Opcodes (instr[6:0])
// ---------------------------------------------------------------
`define OP_LOAD    7'b0000011
`define OP_STORE   7'b0100011
`define OP_RTYPE   7'b0110011
`define OP_ITYPE   7'b0010011
`define OP_BRANCH  7'b1100011
`define OP_JALR    7'b1100111
`define OP_JAL     7'b1101111
`define OP_LUI     7'b0110111
`define OP_AUIPC   7'b0010111

// ---------------------------------------------------------------
// Immediate format select (ImmSrc, 3 bits)
// ---------------------------------------------------------------
`define IMM_I  3'b000
`define IMM_S  3'b001
`define IMM_B  3'b010
`define IMM_J  3'b011
`define IMM_U  3'b100

// ---------------------------------------------------------------
// ALU operand A select (ALUSrcA, 2 bits)
// ---------------------------------------------------------------
`define ASRC_RS1   2'b00     // rs1 (RD1)
`define ASRC_PC    2'b01     // PC      (auipc)
`define ASRC_ZERO  2'b10     // 0       (lui)

// ---------------------------------------------------------------
// Result mux select (ResultSrc, 2 bits)
// ---------------------------------------------------------------
`define RES_ALU  2'b00       // ALUResult
`define RES_MEM  2'b01       // ReadData   (lw)
`define RES_PC4  2'b10       // PC + 4     (jal link)

// ---------------------------------------------------------------
// Forwarding mux select (ForwardAE / ForwardBE, 2 bits)
// ---------------------------------------------------------------
`define FWD_NONE 2'b00       // no forwarding (use register file value)
`define FWD_WB   2'b01       // forward from WB stage
`define FWD_MEM  2'b10       // forward from MEM stage

`endif
