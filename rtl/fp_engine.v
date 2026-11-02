`timescale 1ns/1ps
// Serialized RV32F unit. Arithmetic is Berkeley HardFloat, RISC-V specialization.
// active/consume form a request/completion handshake; operands stay stable.
module fp_engine(input wire clk,rst_n,active,consume,
 input wire [31:0] instr,x,mem_data,
 output reg done, output reg [31:0] result,
 output reg illegal, output reg int_write,
 output wire mem_load,mem_store,mem_write,
 output wire [31:0] address,store_data,
 output wire [7:0] fcsr);
 reg [31:0] rf[0:31]; reg [4:0] fflags; reg [2:0] frm;
 reg busy; integer k;
 reg issue;
 reg [31:0] a,b,c,exec_x,load_data;
 reg [32:0] ar,br,cr;
 wire [32:0] raw_ar,raw_br,raw_cr;
 initial begin for(k=0;k<32;k=k+1) rf[k]=0; end
 wire [6:0] op=instr[6:0], fn=instr[31:25];
 wire [4:0] rd=instr[11:7],rs1=instr[19:15],rs2=instr[24:20];
 wire [2:0] f3=instr[14:12], rm=(f3==7 ? frm : f3);

 wire nan_a=(&a[30:23]) && (|a[22:0]),nan_b=(&b[30:23]) && (|b[22:0]);
 wire snan_a=nan_a && !a[22],snan_b=nan_b && !b[22];
 wire zero_a=(a[30:0]==0),zero_b=(b[30:0]==0);
 wire inf_a=(a[30:0]==31'h7f800000),inf_b=(b[30:0]==31'h7f800000);
 // Resolve special cases before the iterative unit. This also avoids exposing
 // uninitialized don't-care datapath bits from a first special-case operation.
 wire div_special=fn==7'h2c ? (nan_a || inf_a || zero_a || a[31]) :
     (nan_a || nan_b || inf_a || inf_b || zero_a || zero_b);
 assign fcsr={frm,fflags};
 assign mem_load=op==7'h07; assign mem_store=op==7'h27;
 assign address=x+(mem_store ? {{20{instr[31]}},instr[31:25],instr[11:7]} : {{20{instr[31]}},instr[31:20]});
 assign store_data=rf[rs2];
 wire start=active && !done && !busy && !illegal;
 assign mem_write=start && mem_store && rst_n;
 wire [32:0] add_r,mul_r,fma_r,i2f_r,div_r;
 wire [31:0] add_f,mul_f,fma_f,i2f_f,div_f,f2i;
 wire [4:0] add_flags,mul_flags,fma_flags,i2f_flags,div_flags,cmp_flags;
 wire [2:0] f2i_flags;
 wire lt,eq,gt,unordered,div_ready,div_valid;
 fNToRecFN #(8,24) ca(rf[rs1],raw_ar),cb(rf[rs2],raw_br),cc(rf[instr[31:27]],raw_cr);


 wire [1:0] fma_op={op==7'h4b || op==7'h4f,op==7'h47 || op==7'h4f};
 wire arithmetic=(op==7'h43 || op==7'h47 || op==7'h4b || op==7'h4f) ||
     (op==7'h53 && (fn==0 || fn==4 || fn==8));
 wire add_mode=op==7'h53 && (fn==0 || fn==4);
 wire mul_mode=op==7'h53 && fn==8;
 wire [32:0] one_rec,zero_rec;
 fNToRecFN #(8,24) cone(32'h3f800000,one_rec);
 fNToRecFN #(8,24) czero({a[31]^b[31],31'd0},zero_rec);
 wire arith_valid;
 fp_arith_pipe fm(clk,rst_n,issue && arithmetic,
   add_mode ? {1'b0,fn==4} : mul_mode ? 2'b00 : fma_op,
   ar,add_mode ? one_rec : br,add_mode ? br : mul_mode ? zero_rec : cr,
   rm,arith_valid,fma_r,fma_flags);
 assign add_r=fma_r; assign mul_r=fma_r;
 assign add_flags=fma_flags; assign mul_flags=fma_flags;
 wire is_i2f=op==7'h53 && fn==7'h68;
 wire i2f_valid;
 fp_int_pipe cvif(clk,rst_n,issue && is_i2f,!rs2[0],exec_x,rm,i2f_valid,i2f_r,i2f_flags);
 recFNToIN #(8,24,32) cvfi(1'b1,ar,rm,!rs2[0],f2i,f2i_flags);
 compareRecFN #(8,24) cp(ar,br,(fn==7'h50 && f3!=2),lt,eq,gt,unordered,cmp_flags);
 wire is_div=op==7'h53 && (fn==7'h0c || fn==7'h2c);
 fp_div_pipe #(8,24,0) ds(rst_n,clk,1'b1,div_ready,issue && is_div && !div_special,fn==7'h2c,ar,br,rm,div_valid,,div_r,div_flags);
 recFNToFN #(8,24) oa(add_r,add_f),om(mul_r,mul_f),ofm(fma_r,fma_f),oi(i2f_r,i2f_f),od(div_r,div_f);
 reg fp_write,csr_write,needs_round;
 reg [31:0] value,csr_old,csr_new,csr_operand;
 reg [4:0] flags;
 always @(*) begin
  illegal=0; int_write=0; fp_write=0; csr_write=0; needs_round=0;
  value=0; flags=0; csr_old=0; csr_new=0; csr_operand=0;
  case(op)
   7'h07: begin fp_write=1; value=load_data; if(f3!=2) illegal=1; end
   7'h27: if(f3!=2) illegal=1;
   7'h43,7'h47,7'h4b,7'h4f: begin
    fp_write=1; value=fma_f; flags=fma_flags; needs_round=1;
    if(instr[26:25]!=0) illegal=1;
   end
   7'h53: begin
    case(fn)
     7'h00,7'h04: begin fp_write=1; value=add_f; flags=add_flags; needs_round=1; end
     7'h08: begin fp_write=1; value=mul_f; flags=mul_flags; needs_round=1; end
     7'h0c,7'h2c: begin
      fp_write=1; value=div_f; flags=div_flags; needs_round=1;
      if(fn==7'h2c && rs2!=0) illegal=1;
      if(div_special) begin
       flags=0;
       if(fn==7'h2c) begin
        if(nan_a) begin value=32'h7fc00000; flags={snan_a,4'd0}; end
        else if(a[31] && !zero_a) begin value=32'h7fc00000; flags=16; end
        else value=a;
       end else begin
        if(nan_a || nan_b) begin value=32'h7fc00000; flags={snan_a|snan_b,4'd0}; end
        else if((zero_a && zero_b) || (inf_a && inf_b)) begin value=32'h7fc00000; flags=16; end
        else if(inf_a || zero_b) begin value={a[31]^b[31],31'h7f800000}; flags=(!inf_a && zero_b) ? 8 : 0; end
        else value={a[31]^b[31],31'd0};
       end
      end
     end
     7'h10: begin
      fp_write=1;
      case(f3)
       0:value={b[31],a[30:0]}; 1:value={!b[31],a[30:0]}; 2:value={a[31]^b[31],a[30:0]};
       default:illegal=1;
      endcase
     end
     7'h14: begin
      fp_write=1; flags={snan_a|snan_b,4'd0};
      if(f3>1) illegal=1;
      if(nan_a && nan_b) value=32'h7fc00000;
      else if(nan_a) value=b; else if(nan_b) value=a;
      else if(zero_a && zero_b) value={f3[0] ? (a[31]&b[31]) : (a[31]|b[31]),31'd0};
      else value=(f3[0] ? gt : lt) ? a : b;
     end
     7'h50: begin
      int_write=1; flags=cmp_flags;
      case(f3) 0:value={31'd0,lt|eq}; 1:value={31'd0,lt}; 2:value={31'd0,eq}; default:illegal=1; endcase
     end
     7'h60: begin
      int_write=1; value=f2i; flags={|f2i_flags[2:1],3'd0,f2i_flags[0]}; needs_round=1;
      if(rs2>1) illegal=1;
     end
     7'h68: begin fp_write=1; value=i2f_f; flags=i2f_flags; needs_round=1; if(rs2>1) illegal=1; end
     7'h70: begin
      int_write=1; if(rs2!=0 || f3>1) illegal=1;
      if(f3==0) value=a;
      else if(nan_a) value=a[22] ? 32'h200 : 32'h100;
      else if(&a[30:23]) value=a[31] ? 32'h001 : 32'h080;
      else if(zero_a) value=a[31] ? 32'h008 : 32'h010;
      else if(a[30:23]==0) value=a[31] ? 32'h004 : 32'h020;
      else value=a[31] ? 32'h002 : 32'h040;
     end
     7'h78: begin fp_write=1; value=exec_x; if(rs2!=0 || f3!=0) illegal=1; end
     default:illegal=1;
    endcase
   end
   7'h73: begin
    int_write=1;
    case(instr[31:20]) 1:csr_old={27'd0,fflags}; 2:csr_old={29'd0,frm}; 3:csr_old={24'd0,frm,fflags}; default:illegal=1; endcase
    csr_operand=f3[2] ? {27'd0,rs1} : exec_x;
    case(f3[1:0])
     1:begin csr_write=1; csr_new=csr_operand; end
     2:begin csr_write=rs1!=0; csr_new=csr_old|csr_operand; end
     3:begin csr_write=rs1!=0; csr_new=csr_old&~csr_operand; end
     default:illegal=1;
    endcase
    value=csr_old;
   end
   default:illegal=1;
  endcase
  if(needs_round && rm>4) illegal=1;
  if(illegal) begin fp_write=0; int_write=0; csr_write=0; end
 end
 always @(posedge clk) begin
  if(!rst_n) begin issue<=0; busy<=0; done<=0; result<=0; fflags<=0; frm<=0; end
  else begin
   if(consume) done<=0;
   issue<=0;
   if(start) begin
    busy<=1; issue<=1;
    a<=rf[rs1]; b<=rf[rs2]; c<=rf[instr[31:27]];
    ar<=raw_ar; br<=raw_br; cr<=raw_cr;
    exec_x<=x; load_data<=mem_data;
   end
   if(issue) begin
    if(arithmetic || is_i2f || (is_div && !div_special)) busy<=1;
    else begin
     busy<=0; done<=1; result<=value;
     if(fp_write) rf[rd]<=value;
     if(csr_write) begin
      case(instr[31:20]) 1:fflags<=csr_new[4:0]; 2:frm<=csr_new[2:0]; 3:begin frm<=csr_new[7:5]; fflags<=csr_new[4:0]; end endcase
     end else fflags<=fflags|flags;
    end
   end
   if(busy && is_i2f && i2f_valid) begin
    busy<=0;done<=1;result<=i2f_f;rf[rd]<=i2f_f;fflags<=fflags|i2f_flags;
   end
   if(busy && arithmetic && arith_valid) begin
    busy<=0; done<=1; result<=fma_f; rf[rd]<=fma_f; fflags<=fflags|fma_flags;
   end
   if(busy && is_div && !issue && div_valid) begin
    busy<=0; done<=1; result<=div_f; rf[rd]<=div_f; fflags<=fflags|div_flags;
   end
  end
 end
endmodule
