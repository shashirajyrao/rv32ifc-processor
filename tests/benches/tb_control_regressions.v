`timescale 1ns/1ps
module tb_control_regressions;
    reg clk=0; always #5 clk=~clk;
    reg rp=0,rs=0,rb=0;
    wire [31:0] ppc,spc;
    riscv_pipe_top #(.ENABLE_C(0),.IMEM_FILE("control.hex")) pipe(.clk(clk),.rst_n(rp),.PCF(ppc));
    riscv_top #(.ENABLE_C(0),.IMEM_FILE("control.hex")) single(.clk(clk),.rst_n(rs),.PC(spc));
    reg [31:0] pc=0,upc=0,target=0;
    reg update=0,taken=0;
    wire predict,hit; wire [31:0] predicted;
    branch_predictor bp(.clk(clk),.rst_n(rb),.PCF(pc),.PredictTakenF(predict),
        .PredictedPCF(predicted),.BTBHitF(hit),.UpdateEn(update),.UpdatePC(upc),
        .ActualTaken(taken),.ActualTarget(target));
    reg use1=0,use2=0,load=0,branch=0,jump=0,bt=0,pred=0;
    reg [4:0] rs1=0,rs2=0,rd=0;
    reg [31:0] predpc=0,actualpc=0,pc4=4;
    wire sf,sd,fd,fe,miss; wire [31:0] corrected;
    wire oldsf,oldsd,oldfd,oldfe;
    hazard_unit_bp hz(.UsesRs1D(use1),.UsesRs2D(use2),.Rs1D(rs1),.Rs2D(rs2),.RdE(rd),
        .LoadE(load),.BranchE(branch),.JumpE(jump),.BranchTakenE(bt),
        .PredictTakenE(pred),.PredictedPCE(predpc),.PCTargetE(actualpc),.PCPlus4E(pc4),
        .StallF(sf),.StallD(sd),.FlushD(fd),.FlushE(fe),.MispredictE(miss),.CorrectedPCE(corrected));
    hazard_unit oldhz(.UsesRs1D(use1),.UsesRs2D(use2),.Rs1D(rs1),.Rs2D(rs2),.RdE(rd),
        .LoadE(load),.PCSrcE(miss),.StallF(oldsf),.StallD(oldsd),.FlushD(oldfd),.FlushE(oldfe));
    integer count;
    task train;
        input [31:0] address,destination;
        input outcome;
        begin
            @(negedge clk); update=1; upc=address; target=destination; taken=outcome;
            @(posedge clk); #1; update=0;
        end
    endtask
    initial begin
        repeat(3) @(posedge clk); #1;
        // Raw immediate bits must not cause a false load-use stall.
        load=1; rd=5; rs2=5; #1;
        if (sf || sd || oldsf || oldsd) $fatal(1,"false load-use stall");
        use2=1; #1;
        if (!sf || !sd || !fe || !oldsf) $fatal(1,"missing real dependency stall");
        // An ordinary instruction with a false prediction must recover,
        // even when it is a load with a dependent instruction in decode.
        pred=1; #1;
        if (!miss || !fd || !fe || sf || sd || corrected!=4 || oldsf) $fatal(1,"redirect priority");
        pred=0; load=0;
        @(negedge clk); rb=1;
        train(0,128,1); pc=0; #1;
        if (!hit || !predict || predicted!=128) $fatal(1,"predictor training");
        pc=256; #1;
        if (hit || predict) $fatal(1,"BTB tag alias");
        train(256,512,1); pc=0; #1;
        if (hit || predict) $fatal(1,"BTB replacement tag");
        pc=256;
        repeat(5) train(256,512,1);
        if (bp.bht[0]!==2'b11) $fatal(1,"counter upper saturation");
        repeat(5) train(256,512,0);
        if (bp.bht[0]!==2'b00 || predict) $fatal(1,"counter lower saturation");

        // Reset before the edge on which WB and MEM would both write.
        @(negedge clk); rp=1; count=0;
        while (!(pipe.ValidM && pipe.PCM==8 && pipe.ValidW && pipe.PCW==4) && count<30) begin
            @(negedge clk); count=count+1;
        end
        if (count==30) $fatal(1,"warm reset setup timed out");
        rp=0; @(posedge clk); #1;
        if (pipe.u_rf.rf[1]!==0 || pipe.u_dmem.mem[0]!==0) $fatal(1,"pipeline writes on reset edge");
        repeat(3) @(posedge clk);
        @(negedge clk); rp=1;
        repeat(20) @(posedge clk); #1;
        if (pipe.u_rf.rf[1]!==7 || pipe.u_dmem.mem[0]!==7 || pipe.Trap) $fatal(1,"pipeline restart");
        @(negedge clk); rs=1; count=0;
        while (spc!=8 && count<20) begin @(negedge clk); count=count+1; end
        if (count==20) $fatal(1,"single reset setup timed out");
        rs=0; @(posedge clk); #1;
        if (single.u_dmem.mem[0]!==0) $fatal(1,"single-cycle store during reset");
        repeat(3) @(posedge clk);
        @(negedge clk); rs=1;
        repeat(10) @(posedge clk); #1;
        if (single.u_dmem.mem[0]!==7 || single.Trap) $fatal(1,"single-cycle restart");
        $display("PASS predictor, hazard priority, warm reset and restart"); $finish;
    end
    initial begin #10000; $fatal(1,"control regression watchdog"); end
endmodule
