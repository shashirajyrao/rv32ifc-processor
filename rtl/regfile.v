`timescale 1ns/1ps
// regfile.v -- 32 x 32 register file (plain Verilog-2001)
// Two asynchronous read ports, one synchronous write port. x0 is hardwired to 0.
//
// BYPASS = 0 : plain read (single-cycle core; a bypass there would create a
//              combinational loop through the ALU)
// BYPASS = 1 : write-first. A read of the register being written in the same
//              cycle returns the incoming write data (needed by the pipeline,
//              where WB writes while ID reads).

module regfile #(
    parameter BYPASS = 0
)(
    input  wire        clk,
    input  wire        we3,
    input  wire [4:0]  a1,
    input  wire [4:0]  a2,
    input  wire [4:0]  a3,
    input  wire [31:0] wd3,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);

    reg [31:0] rf [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            rf[i] = 32'd0;
    end

    always @(posedge clk) begin
        if (we3 && (a3 != 5'd0))
            rf[a3] <= wd3;
    end

    wire byp1 = (BYPASS != 0) && we3 && (a3 != 5'd0) && (a3 == a1);
    wire byp2 = (BYPASS != 0) && we3 && (a3 != 5'd0) && (a3 == a2);

    assign rd1 = (a1 == 5'd0) ? 32'd0 : byp1 ? wd3 : rf[a1];
    assign rd2 = (a2 == 5'd0) ? 32'd0 : byp2 ? wd3 : rf[a2];

endmodule
