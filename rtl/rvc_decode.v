`timescale 1ns/1ps
// Ratified RV32C (including RV32FC loads/stores). D/RV64 encodings are illegal.
module rvc_decode(input wire [15:0] c, output reg [31:0] instr, output reg illegal);
 wire [4:0] rd=c[11:7], rs2=c[6:2], rp={2'b01,c[9:7]}, dp={2'b01,c[4:2]};
 reg [31:0] imm; reg [6:0] op;
 function [31:0] ii;
  input [31:0] n; input [4:0] a,d; input [2:0] f; input [6:0] opcode;
  ii={n[11:0],a,f,d,opcode};
 endfunction
 function [31:0] ss;
  input [31:0] n; input [4:0] a,b; input [6:0] opcode;
  ss={n[11:5],b,a,3'b010,n[4:0],opcode};
 endfunction
 function [31:0] jj;
  input [31:0] n; input [4:0] d;
  jj={n[20],n[10:1],n[11],n[19:12],d,7'h6f};
 endfunction
 always @(*) begin
  instr=32'h13; illegal=0; imm=0; op=0;
  case(c[1:0])
   0: case(c[15:13])
    0: begin
     imm={22'd0,c[10:7],c[12:11],c[5],c[6],2'b00};
     instr=ii(imm,2,dp,0,7'h13); if(imm==0) illegal=1;
    end
    2,3: begin
     imm={25'd0,c[5],c[12:10],c[6],2'b00};
     instr=ii(imm,rp,dp,2,c[13] ? 7'h07 : 7'h03);
    end
    6,7: begin
     imm={25'd0,c[5],c[12:10],c[6],2'b00};
     instr=ss(imm,rp,dp,c[13] ? 7'h27 : 7'h23);
    end
    default: illegal=1;
   endcase
   1: case(c[15:13])
    0: instr=ii({{26{c[12]}},c[12],c[6:2]},rd,rd,0,7'h13);
    1,5: begin
     imm={{20{c[12]}},c[12],c[8],c[10:9],c[6],c[7],c[2],c[11],c[5:3],1'b0};
     instr=jj(imm,c[15:13]==1 ? 5'd1 : 5'd0);
    end
    2: instr=ii({{26{c[12]}},c[12],c[6:2]},0,rd,0,7'h13);
    3: begin
     if(rd==2) begin
      imm={{22{c[12]}},c[12],c[4:3],c[5],c[2],c[6],4'd0}; instr=ii(imm,2,2,0,7'h13);
     end else begin
      imm={{14{c[12]}},c[12],c[6:2],12'd0}; instr={imm[31:12],rd,7'h37};
     end
     if(imm==0) illegal=1;
    end
    4: case(c[11:10])
     0,1: begin
      instr=ii({21'd0,c[10],5'd0,c[6:2]},rp,rp,5,7'h13);
      if(c[12]) illegal=1;
     end
     2: instr=ii({{26{c[12]}},c[12],c[6:2]},rp,rp,7,7'h13);
     3: begin
      if(c[12]) illegal=1;
      case(c[6:5])
       0: instr={7'h20,dp,rp,3'b000,rp,7'h33};
       1: instr={7'd0,dp,rp,3'b100,rp,7'h33};
       2: instr={7'd0,dp,rp,3'b110,rp,7'h33};
       3: instr={7'd0,dp,rp,3'b111,rp,7'h33};
      endcase
     end
    endcase
    6,7: begin
     imm={{23{c[12]}},c[12],c[6:5],c[2],c[11:10],c[4:3],1'b0};
     instr={imm[12],imm[10:5],5'd0,rp,2'b00,c[13],imm[4:1],imm[11],7'h63};
    end
   endcase
   2: case(c[15:13])
    0: begin instr=ii({27'd0,c[6:2]},rd,rd,1,7'h13); if(c[12]) illegal=1; end
    2,3: begin
     imm={24'd0,c[3:2],c[12],c[6:4],2'b00};
     instr=ii(imm,2,rd,2,c[13] ? 7'h07 : 7'h03);
     if(!c[13] && rd==0) illegal=1;
    end
    4: begin
     if(rs2==0) begin
      if(rd==0) begin if(c[12]) instr=32'h00100073; else illegal=1; end
      else instr=ii(0,rd,c[12] ? 5'd1 : 5'd0,0,7'h67);
     end else instr={7'd0,rs2,(c[12] ? rd : 5'd0),3'b000,rd,7'h33};
    end
    6,7: begin
     imm={24'd0,c[8:7],c[12:9],2'b00}; instr=ss(imm,2,rs2,c[13] ? 7'h27 : 7'h23);
    end
    default: illegal=1;
   endcase
   default: illegal=1;
  endcase
  if(illegal) instr=0;
 end
endmodule
