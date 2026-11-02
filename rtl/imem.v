`timescale 1ns/1ps
module imem #(parameter ADDR_BITS=8, parameter INIT_FILE="program.hex", parameter ENABLE_C=1)(
 input wire [31:0] a, output wire [31:0] rd, output wire AccessFault, Misaligned,
 output wire [2:0] Length, output wire [31:0] RawInstr, output wire IllegalCompressed
);
 reg [31:0] mem [0:(2**ADDR_BITS)-1]; integer i;
 initial begin for(i=0;i<(2**ADDR_BITS);i=i+1) mem[i]=32'h13; $readmemh(INIT_FILE,mem); end
 wire base_bad=(a >> (ADDR_BITS+2))!=0;
 wire [ADDR_BITS-1:0] idx=a[ADDR_BITS+1:2];
 wire [31:0] first=base_bad ? 32'h13 : mem[idx];
 wire [31:0] following=(idx==((2**ADDR_BITS)-1)) ? 32'd0 : mem[idx+1'b1];
 wire [31:0] raw=a[1] ? {following[15:0],first[31:16]} : first;
 wire compressed=ENABLE_C && raw[1:0]!=3;
 wire [31:0] expanded; wire bad_c;
 rvc_decode dec(raw[15:0],expanded,bad_c);
 assign Length=compressed ? 3'd2 : 3'd4;
 assign RawInstr=compressed ? {16'd0,raw[15:0]} : raw;
 assign IllegalCompressed=compressed && bad_c;
 assign AccessFault=base_bad || (!compressed && a[1] && idx==((2**ADDR_BITS)-1));
 assign Misaligned=ENABLE_C ? a[0] : |a[1:0];
 assign rd=(AccessFault || Misaligned) ? 32'h13 : (compressed ? expanded : raw);
endmodule
