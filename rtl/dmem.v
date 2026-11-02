`timescale 1ns/1ps
// Little-endian memory. Natural alignment required; no address wrapping.
module dmem #(parameter ADDR_BITS=8)(
 input wire clk, we, input wire [31:0] a, wd, input wire [2:0] funct3,
 output reg [31:0] rd, output wire AccessFault, Misaligned
);
 reg [31:0] mem [0:(2**ADDR_BITS)-1]; integer i;
 initial begin for(i=0;i<(2**ADDR_BITS);i=i+1) mem[i]=0; end
 assign AccessFault=(a >> (ADDR_BITS+2)) != 0;
 assign Misaligned=((funct3[1:0]==1) && a[0]) || ((funct3[1:0]==2) && (a[1:0]!=0));
 wire [31:0] lane=mem[a[ADDR_BITS+1:2]] >> (8*a[1:0]);
 always @(*) begin
  rd=0;
  if (!AccessFault && !Misaligned) begin
   case(funct3)
    0: rd={{24{lane[7]}},lane[7:0]};
    1: rd={{16{lane[15]}},lane[15:0]};
    2: rd=lane;
    4: rd={24'd0,lane[7:0]};
    5: rd={16'd0,lane[15:0]};
    default: rd=0;
   endcase
  end
 end
 always @(posedge clk) begin
  if (we && !AccessFault && !Misaligned) begin
   case(funct3)
    0: mem[a[ADDR_BITS+1:2]][8*a[1:0] +: 8] <= wd[7:0];
    1: mem[a[ADDR_BITS+1:2]][8*a[1:0] +: 16] <= wd[15:0];
    2: mem[a[ADDR_BITS+1:2]] <= wd;
   endcase
  end
 end
endmodule
