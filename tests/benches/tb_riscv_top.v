// tb_riscv_pipe.v -- testbench for the 5-stage pipeline (plain Verilog-2001)
//
//  * Runs the pipelined core and the single-cycle core (riscv_top) side by side
//    on the same integer_demo.hex.
//  * Prints, every cycle, which instruction is in IF / ID / EX / MEM / WB, plus
//    stalls, flushes, forwarding, memory accesses and register write-backs.
//  * At the end compares the pipeline's registers and data memory against the
//    single-cycle core and against hand-computed expected values.

`timescale 1ns/1ps

`include "program_expected.vh"
module tb_riscv_pipe;

    parameter END_PC = `PROGRAM_END_PC;   // address of the final "beq x0,x0,end" loop

    reg         clk;
    reg         rst_n;
    wire [31:0] PCF;

    integer errors;
    integer cyc;
    integer r, w;

    riscv_pipe_top #(.IMEM_FILE("integer_demo.hex")) dut (.clk(clk), .rst_n(rst_n), .PCF(PCF));

    // single-cycle reference core, same clock / reset / program
    wire [31:0] ref_PC, ref_Instr, ref_ALUResult, ref_WriteData;
    wire        ref_MemWrite;
    riscv_top #(.IMEM_FILE("integer_demo.hex")) ref_core (
        .clk(clk), .rst_n(rst_n),
        .PC(ref_PC), .Instr(ref_Instr), .ALUResult(ref_ALUResult),
        .WriteData(ref_WriteData), .MemWrite(ref_MemWrite)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Helpers for the trace
    // ------------------------------------------------------------
    function [47:0] mnem;
        input [31:0] ins;
        reg [6:0] op;
        reg [2:0] f3;
        reg       f7;
        begin
            op = ins[6:0]; f3 = ins[14:12]; f7 = ins[30];
            mnem = "??????";
            case (op)
                7'b0000011: mnem = "lw    ";
                7'b0100011: mnem = "sw    ";
                7'b1100011:
                    case (f3)
                        3'b000: mnem = "beq   ";
                        3'b001: mnem = "bne   ";
                        3'b100: mnem = "blt   ";
                        3'b101: mnem = "bge   ";
                        3'b110: mnem = "bltu  ";
                        3'b111: mnem = "bgeu  ";
                        default: mnem = "b??   ";
                    endcase
                7'b1101111: mnem = "jal   ";
                7'b0110111: mnem = "lui   ";
                7'b0010111: mnem = "auipc ";
                7'b0110011:
                    case (f3)
                        3'b000: mnem = f7 ? "sub   " : "add   ";
                        3'b001: mnem = "sll   ";
                        3'b010: mnem = "slt   ";
                        3'b011: mnem = "sltu  ";
                        3'b100: mnem = "xor   ";
                        3'b101: mnem = f7 ? "sra   " : "srl   ";
                        3'b110: mnem = "or    ";
                        3'b111: mnem = "and   ";
                    endcase
                7'b0010011:
                    case (f3)
                        3'b000: mnem = "addi  ";
                        3'b001: mnem = "slli  ";
                        3'b010: mnem = "slti  ";
                        3'b011: mnem = "sltiu ";
                        3'b100: mnem = "xori  ";
                        3'b101: mnem = f7 ? "srai  " : "srli  ";
                        3'b110: mnem = "ori   ";
                        3'b111: mnem = "andi  ";
                    endcase
            endcase
        end
    endfunction

    function [31:0] imm_of;
        input [31:0] ins;
        begin
            case (ins[6:0])
                7'b0100011: imm_of = {{20{ins[31]}}, ins[31:25], ins[11:7]};
                7'b1100011: imm_of = {{20{ins[31]}}, ins[7], ins[30:25], ins[11:8], 1'b0};
                7'b1101111: imm_of = {{12{ins[31]}}, ins[19:12], ins[20], ins[30:21], 1'b0};
                7'b0110111,
                7'b0010111: imm_of = {ins[31:12], 12'b0};
                default:    imm_of = {{20{ins[31]}}, ins[31:20]};
            endcase
        end
    endfunction

    function uses_rs1;      // instruction reads rs1
        input [31:0] ins;
        uses_rs1 = !(ins[6:0] == 7'b0110111 || ins[6:0] == 7'b0010111 || ins[6:0] == 7'b1101111);
    endfunction

    function uses_rs2;      // instruction reads rs2
        input [31:0] ins;
        uses_rs2 = (ins[6:0] == 7'b0110011 || ins[6:0] == 7'b0100011 || ins[6:0] == 7'b1100011);
    endfunction

    task show_stage;
        input [23:0] label;
        input        valid;
        input [31:0] pc;
        input [31:0] ins;
        begin
            if (!valid)
                $display("    %0s : ------  bubble", label);
            else begin
                case (ins[6:0])
                    7'b0110011:
                        $display("    %0s : 0x%h  %0s x%0d, x%0d, x%0d",
                                 label, pc, mnem(ins), ins[11:7], ins[19:15], ins[24:20]);
                    7'b0010011:
                        $display("    %0s : 0x%h  %0s x%0d, x%0d, %0d",
                                 label, pc, mnem(ins), ins[11:7], ins[19:15], ((ins[14:12]==1 || ins[14:12]==5) ? $signed({27'd0,ins[24:20]}) : $signed(imm_of(ins))));
                    7'b0000011:
                        $display("    %0s : 0x%h  %0s x%0d, %0d(x%0d)",
                                 label, pc, mnem(ins), ins[11:7], $signed(imm_of(ins)), ins[19:15]);
                    7'b0100011:
                        $display("    %0s : 0x%h  %0s x%0d, %0d(x%0d)",
                                 label, pc, mnem(ins), ins[24:20], $signed(imm_of(ins)), ins[19:15]);
                    7'b1100011:
                        $display("    %0s : 0x%h  %0s x%0d, x%0d, offset %0d",
                                 label, pc, mnem(ins), ins[19:15], ins[24:20], $signed(imm_of(ins)));
                    7'b1101111:
                        $display("    %0s : 0x%h  %0s x%0d, offset %0d",
                                 label, pc, mnem(ins), ins[11:7], $signed(imm_of(ins)));
                    7'b0110111, 7'b0010111:
                        $display("    %0s : 0x%h  %0s x%0d, 0x%h",
                                 label, pc, mnem(ins), ins[11:7], ins[31:12]);
                    default:
                        $display("    %0s : 0x%h  0x%h", label, pc, ins);
                endcase
            end
        end
    endtask

    // ------------------------------------------------------------
    // Per-cycle trace and statistics, sampled at the falling edge
    // ------------------------------------------------------------
    reg     trace_on;
    reg     ended;            // first end-loop instruction has reached WB
    integer retired;          // instructions that completed WB before the end loop
    integer stalls;           // load-use stall cycles
    integer redirects;        // mispredictions (each costs 2 bubbles)
    integer end_cycle;

    always @(negedge clk) begin
        if (trace_on) begin
            $display("");
            $display("cycle %0d", cyc);
            // IF shows the instruction being fetched (it is fetched again after a stall)
            show_stage("IF ", 1'b1,       PCF,      dut.InstrF);
            show_stage("ID ", dut.ValidD, dut.PCD,  dut.InstrD);
            show_stage("EX ", dut.ValidE, dut.PCE,  dut.InstrE);
            show_stage("MEM", dut.ValidM, dut.PCM,  dut.InstrM);
            show_stage("WB ", dut.ValidW, dut.PCW,  dut.InstrW);

            // ---- events ----
            if (dut.HazStallF)
                $display("    >> STALL  load-use: lw x%0d in EX is needed by the instruction in ID; PC and IF/ID held, bubble into EX",
                         dut.RdE);

            if (dut.ExtDrain) $display("    >> WAIT   drain older instructions before FP/CSR execution");
            if (dut.ExtWait) $display("    >> WAIT   FP execution in progress");

            if (dut.ValidE && uses_rs1(dut.InstrE) && dut.ForwardAE == 2'b10)
                $display("    >> FWD    rs1 (x%0d) <- MEM-stage result = %0d", dut.Rs1E, $signed(dut.ExecResultM));
            if (dut.ValidE && uses_rs1(dut.InstrE) && dut.ForwardAE == 2'b01)
                $display("    >> FWD    rs1 (x%0d) <- WB-stage result  = %0d", dut.Rs1E, $signed(dut.ResultW));
            if (dut.ValidE && uses_rs2(dut.InstrE) && dut.ForwardBE == 2'b10)
                $display("    >> FWD    rs2 (x%0d) <- MEM-stage result = %0d", dut.Rs2E, $signed(dut.ExecResultM));
            if (dut.ValidE && uses_rs2(dut.InstrE) && dut.ForwardBE == 2'b01)
                $display("    >> FWD    rs2 (x%0d) <- WB-stage result  = %0d", dut.Rs2E, $signed(dut.ResultW));

            if (dut.PredictTakenF)
                $display("    >> PREDICT speculatively fetching target 0x%h from BTB", dut.PredictedPCF);

            if (dut.ValidE && dut.InstrE[6:0] == 7'b1100011) begin
                if (!dut.MispredictE)
                    $display("    >> BRANCH rs1=%0d rs2=%0d -> condition %0s [PREDICTION CORRECT - 0 cycle penalty!]",
                             $signed(dut.SrcAFwdE), $signed(dut.WriteDataE),
                             dut.BranchTakenE ? "TRUE" : "false");
                else
                    $display("    >> BRANCH rs1=%0d rs2=%0d -> condition %0s [MISPREDICTED]",
                             $signed(dut.SrcAFwdE), $signed(dut.WriteDataE),
                             dut.BranchTakenE ? "TRUE" : "false");
            end

            if (dut.ValidE && dut.MispredictE)
                $display("    >> FLUSH  %0s at 0x%h mispredicted! Redirects fetch to 0x%h; squashed 2 bubbles",
                         mnem(dut.InstrE), dut.PCE, dut.CorrectedPCE);

            if (dut.ValidM && dut.MemWriteM)
                $display("    >> MEM    store: byte addr %0d <= %0d", dut.ExecResultM, $signed(dut.WriteDataM));
            if (dut.ValidM && dut.MemToRegM)
                $display("    >> MEM    load : byte addr %0d -> %0d", dut.ExecResultM, $signed(dut.ReadDataM));

            if (dut.ValidW && dut.RegWriteW && dut.RdW != 5'd0)
                $display("    >> WB     x%0d <= %0d (0x%h)", dut.RdW, $signed(dut.ResultW), dut.ResultW);

            // ---- statistics (stop counting once the end loop reaches WB) ----
            if (!ended) begin
                if (dut.ValidW && dut.PCW == END_PC) begin
                    ended     = 1'b1;
                    end_cycle = cyc;
                end else if (dut.ValidW)
                    retired = retired + 1;
                if (dut.HazStallF)
                    stalls = stalls + 1;
                if (dut.ValidE && dut.PCSrcE && dut.PCE != END_PC)
                    redirects = redirects + 1;
            end

            cyc = cyc + 1;
        end
    end

    // ------------------------------------------------------------
    // Expected final register values (hand computed)
    // ------------------------------------------------------------
    reg [31:0] exp_val [0:31];
    reg        exp_has [0:31];

    task set_exp;
        input [4:0]  reg_n;
        input [31:0] value;
        begin
            exp_val[reg_n] = value;
            exp_has[reg_n] = 1'b1;
        end
    endtask

    task check_mem;
        input [31:0] byte_addr;
        input [31:0] expected;
        reg   [31:0] got;
        begin
            got = dut.u_dmem.mem[byte_addr[9:2]];
            if (got !== expected) begin
                errors = errors + 1;
                $display("  byte addr %0d = %0d (0x%h)   expected %0d   <-- FAIL",
                         byte_addr, $signed(got), got, $signed(expected));
            end else
                $display("  byte addr %0d = %0d (0x%h)   expected %0d   ok",
                         byte_addr, $signed(got), got, $signed(expected));
        end
    endtask

    reg [31:0] expected_mem [0:255];
    integer mem_mismatch;
    real    cpi;

    initial begin
        errors    = 0;
        cyc       = 0;
        ended     = 1'b0;
        retired   = 0;
        stalls    = 0;
        redirects = 0;
        end_cycle = 0;
        trace_on  = 1'b0;
        for (r = 0; r < 32; r = r + 1) begin exp_val[r] = 32'd0; exp_has[r] = 1'b0; end

        $readmemh("program_regs.hex", exp_val);
        $readmemh("program_mem.hex", expected_mem);
        for (r=0; r<32; r=r+1) exp_has[r]=1;

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        trace_on = 1'b1;

        // run until the first end-loop instruction reaches WB (everything before it has retired)
        while (!ended && cyc < 2000)
            @(posedge clk);
        repeat (2) @(posedge clk);
        #1 trace_on = 1'b0;

        $display("");
        $display("==================== FINAL STATE ====================");
        if (!ended) begin
            errors = errors + 1;
            $display("FAIL timeout: end loop never reached WB after %0d cycles", cyc);
        end

        $display("");
        $display("Register file   pipeline value | single-cycle value | expected");
        for (r = 0; r < 32; r = r + 1) begin
            if (dut.u_rf.rf[r] !== ref_core.u_rf.rf[r]) begin
                errors = errors + 1;
                $display("  x%-2d = 0x%h (%0d)   single-cycle = 0x%h   <-- MISMATCH vs single-cycle",
                         r, dut.u_rf.rf[r], $signed(dut.u_rf.rf[r]), ref_core.u_rf.rf[r]);
            end else if (exp_has[r] && dut.u_rf.rf[r] !== exp_val[r]) begin
                errors = errors + 1;
                $display("  x%-2d = 0x%h (%0d)   expected %0d   <-- FAIL",
                         r, dut.u_rf.rf[r], $signed(dut.u_rf.rf[r]), $signed(exp_val[r]));
            end else if (exp_has[r])
                $display("  x%-2d = 0x%h  %11d   same as single-cycle   expected %0d   ok",
                         r, dut.u_rf.rf[r], $signed(dut.u_rf.rf[r]), $signed(exp_val[r]));
            else
                $display("  x%-2d = 0x%h  %11d   same as single-cycle",
                         r, dut.u_rf.rf[r], $signed(dut.u_rf.rf[r]));
        end

        mem_mismatch = 0;
        for (w = 0; w < 256; w = w + 1)
            if (dut.u_dmem.mem[w] !== ref_core.u_dmem.mem[w]) begin
                mem_mismatch = mem_mismatch + 1;
                errors = errors + 1;
                $display("  mem word %0d: pipeline 0x%h vs single-cycle 0x%h  <-- MISMATCH",
                         w, dut.u_dmem.mem[w], ref_core.u_dmem.mem[w]);
            end

        $display("");
        $display("Data memory (all 256 words compared with single-cycle core: %0d mismatches)", mem_mismatch);
        for(w=0;w<256;w=w+1) check_mem(4*w,expected_mem[w]);
        if (dut.Trap || ref_core.Trap) begin
            errors=errors+1;
            $display("FAIL: unexpected trap");
        end

        $display("");
        $display("Performance (until the end loop reaches WB)");
        $display("  instructions retired        : %0d", retired);
        $display("  clock cycles                : %0d", end_cycle);
        $display("  load-use stall cycles       : %0d", stalls);
        $display("  mispredicted branches/jumps : %0d  (2 flushed bubbles each = %0d cycles)", redirects, 2 * redirects);
        $display("  pipeline fill               : 4 cycles");
        $display("  check: %0d + 4 + %0d + %0d = %0d cycles", retired, stalls, 2 * redirects,
                 retired + 4 + stalls + 2 * redirects);
        if (retired > 0) begin
            cpi = end_cycle;
            cpi = cpi / retired;
            $display("  CPI                         : %0f   (single-cycle core: 1 instruction per cycle)", cpi);
        end

        $display("");
        if (errors == 0) $display("RESULT: PASS (0 errors)");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        if (errors != 0) $fatal(1, "processor test failed");
        $finish;
    end

endmodule

