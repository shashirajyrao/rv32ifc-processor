`timescale 1ns/1ps
module tb_regression;
    parameter RESET_VECTOR=0;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    integer k,cycles,reset_cycles,stalls;
    reg [31:0] pv,sv;
    wire [31:0] pc1,pc2,ins,aluout,wd;
    wire mw;
    riscv_pipe_top #(.ENABLE_C(0),.IMEM_FILE("regression.hex"),.RESET_VECTOR(RESET_VECTOR)) dut(
        .clk(clk),.rst_n(rst_n),.PCF(pc1));
    riscv_top #(.ENABLE_C(0),.IMEM_FILE("regression.hex"),.RESET_VECTOR(RESET_VECTOR)) refcore(
        .clk(clk),.rst_n(rst_n),.PC(pc2),.Instr(ins),.ALUResult(aluout),.WriteData(wd),.MemWrite(mw));
    always @(posedge clk) if (rst_n) begin
        if (dut.ValidW && !dut.Trap) $display("RET %h",dut.PCW);
        if (dut.StallF && !dut.Trap) stalls=stalls+1;
    end
    initial begin
        stalls=0;
        if (!$value$plusargs("CYCLES=%d",cycles)) cycles=1200;
        if (!$value$plusargs("RESET=%d",reset_cycles)) reset_cycles=5;
        repeat(reset_cycles) @(posedge clk); #1 rst_n=1;
        repeat(cycles) @(posedge clk); #1;
        for(k=0;k<32;k=k+1) begin
            pv=dut.u_rf.rf[k]; sv=refcore.u_rf.rf[k]; $display("REG %0d %h %h",k,pv,sv);
        end
        for(k=0;k<256;k=k+1) begin
            pv=dut.u_dmem.mem[k]; sv=refcore.u_dmem.mem[k]; $display("MEM %0d %h %h",k,pv,sv);
        end
        $display("TRAP P %b %h %h %h",dut.Trap,dut.TrapCause,dut.TrapPC,dut.TrapValue);
        $display("TRAP S %b %h %h %h",refcore.Trap,refcore.TrapCause,refcore.TrapPC,refcore.TrapValue);
        $display("STALLS %0d",stalls);
        $display("DONE"); $finish;
    end
endmodule
