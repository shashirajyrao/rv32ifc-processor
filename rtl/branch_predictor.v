`timescale 1ns/1ps
// branch_predictor.v -- 2-bit saturating counter BHT with BTB (plain Verilog-2001)
//
// Branch History Table (BHT):
//   - Indexed by lower bits of PC: PC[BHT_ADDR_BITS:1]
//   - Each entry: 2-bit saturating counter
//       2'b00 = Strongly Not-Taken (SNT)
//       2'b01 = Weakly Not-Taken   (WNT)
//       2'b10 = Weakly Taken       (WT)
//       2'b11 = Strongly Taken     (ST)
//   - Prediction: counter[1] => 1 = predict taken, 0 = predict not-taken
//
// Branch Target Buffer (BTB):
//   - Same index as BHT
//   - Stores the branch/jump target address
//   - Valid bit indicates entry is populated
//
// Interface:
//   PREDICT (IF stage): given PCF, output predicted next PC and prediction flag
//   UPDATE  (EX stage): after branch resolves, update BHT counter and BTB entry

`include "riscv_defs.vh"

module branch_predictor #(
    parameter BHT_ADDR_BITS = 6                     // 2^6 = 64 entries
)(
    input  wire        clk,
    input  wire        rst_n,

    // ------ Prediction port (IF stage) ------
    input  wire [31:0] PCF,                          // current fetch PC
    output wire        PredictTakenF,                // 1 = predict taken
    output wire [31:0] PredictedPCF,                 // predicted target PC
    output wire        BTBHitF,                      // BTB has a valid entry for this PC

    // ------ Update port (EX stage) ------
    input  wire        UpdateEn,                     // a branch/jump was in EX this cycle
    input  wire [31:0] UpdatePC,                     // PC of the branch (PCE)
    input  wire        ActualTaken,                  // was the branch actually taken?
    input  wire [31:0] ActualTarget                  // actual computed target (PCTargetE)
);

    localparam NUM_ENTRIES = 2 ** BHT_ADDR_BITS;

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------
    (* ram_style = "distributed" *) reg [1:0]  bht [0:NUM_ENTRIES-1];                // 2-bit saturating counters
    (* ram_style = "distributed" *) reg [31-BHT_ADDR_BITS:0] btb_tag [0:NUM_ENTRIES-1];
    (* ram_style = "distributed" *) reg [31:0] btb [0:NUM_ENTRIES-1];                // target addresses
    reg        btb_valid [0:NUM_ENTRIES-1];          // valid bits

    // ----------------------------------------------------------------
    // Index extraction (halfword-aligned)
    // ----------------------------------------------------------------
    wire [BHT_ADDR_BITS-1:0] pred_idx   = PCF[BHT_ADDR_BITS:1];
    wire [BHT_ADDR_BITS-1:0] update_idx = UpdatePC[BHT_ADDR_BITS:1];

    // ----------------------------------------------------------------
    // Prediction logic (combinational, evaluated in IF)
    // ----------------------------------------------------------------
    wire [1:0] pred_counter = bht[pred_idx];

    assign BTBHitF       = btb_valid[pred_idx] && (btb_tag[pred_idx] == {PCF[31:BHT_ADDR_BITS+1], PCF[0]});
    assign PredictTakenF = BTBHitF & pred_counter[1];   // predict taken if MSB=1 and target known
    assign PredictedPCF  = btb_valid[pred_idx] ? btb[pred_idx] : 32'd0;                // target from BTB

    // ----------------------------------------------------------------
    // Update logic (synchronous, from EX stage resolution)
    // ----------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                btb_valid[i] <= 1'b0;
            end
        end else if (UpdateEn) begin
            btb_valid[update_idx] <= 1'b1;
        end
    end

    // Only validity resets; payload RAM is initialized on allocation.
    always @(posedge clk) begin
        if (rst_n && UpdateEn) begin
            // Update 2-bit saturating counter
            if (!btb_valid[update_idx] || btb_tag[update_idx] != {UpdatePC[31:BHT_ADDR_BITS+1], UpdatePC[0]})
                bht[update_idx] <= ActualTaken ? 2'b10 : 2'b01;
            else if (ActualTaken) begin
                if (bht[update_idx] != 2'b11)
                    bht[update_idx] <= bht[update_idx] + 2'b01;
            end else begin
                if (bht[update_idx] != 2'b00)
                    bht[update_idx] <= bht[update_idx] - 2'b01;
            end

            // Update BTB entry with actual target
            btb[update_idx]       <= ActualTarget;
            btb_tag[update_idx]   <= {UpdatePC[31:BHT_ADDR_BITS+1], UpdatePC[0]};

        end
    end

endmodule

