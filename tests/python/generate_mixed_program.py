from pathlib import Path
import fc_verify as f
items=[];names=[];trace=[];pc=0

def emit(code,name,size=4,retire=True):
 global pc
 here=pc;items.append((code,size));names.append((pc,code,size,name));pc+=size
 if retire:trace.append(here)
 return here
I=f.I;FP=f.FP
emit(I(128,0,0,2),'addi sp,x0,128')
emit(0x4495,'c.li x9,5',2)
emit(0x0485,'c.addi x9,1',2)
emit(I(7,9,0,10),'addi x10,x9,7')
emit(f.S(0,10,2),'sw x10,0(sp)')
emit(I(0,2,2,11,3),'lw x11,0(sp)')
emit(I(1,11,0,12),'addi x12,x11,1 (load-use)')
emit(0x0001,'c.nop',2)
emit(0x3fc000b7,'lui x1,0x3fc00 (1.5 bits)')
emit(FP(0x78,1,1),'fmv.w.x f1,x1')
emit(0x40000337,'lui x6,0x40000 (2.0 bits)')
emit(FP(0x78,2,6),'fmv.w.x f2,x6')
for fn,d,a,b,name in [(0,3,1,2,'fadd.s f3,f1,f2'),(4,4,2,1,'fsub.s f4,f2,f1'),(8,5,1,2,'fmul.s f5,f1,f2'),(0xc,6,5,2,'fdiv.s f6,f5,f2')]:emit(FP(fn,d,a,b),name)
emit((1<<27)|(2<<20)|(1<<15)|(7<<7)|0x43,'fmadd.s f7,f1,f2,f1')
emit(0x408003b7,'lui x7,0x40800 (4.0 bits)')
emit(FP(0x78,8,7),'fmv.w.x f8,x7')
emit(FP(0x2c,9,8),'fsqrt.s f9,f8')
emit(FP(0x60,13,3,0,1),'fcvt.w.s x13,f3,rtz')
emit(FP(0x68,10,13),'fcvt.s.w f10,x13')
emit(FP(0x50,14,9,2,2),'feq.s x14,f9,f2')
emit(FP(0x14,11,1,2),'fmin.s f11,f1,f2')
emit(FP(0x10,12,1,2,1),'fsgnjn.s f12,f1,f2')
emit(FP(0x70,15,12,0,1),'fclass.s x15,f12')
emit(FP(0x70,16,7),'fmv.x.w x16,f7')
emit(f.S(4,7,2,0x27),'fsw f7,4(sp)')
emit(I(4,2,2,13,7),'flw f13,4(sp)')
emit(0xe006|(1<<2)|(2<<9),'c.fswsp f1,8(sp)',2)
emit(0x6002|(14<<7)|(2<<4),'c.flwsp f14,8(sp)',2)
emit(f.CSR(1,17,0,2),'csrrs x17,fflags,x0')
emit(f.CSR(1,0,0,1),'csrrw x0,fflags,x0')
emit(0x468d,'c.li x13,3',2)
loop=emit(0x16fd,'c.addi x13,-1',2)
# BNE x13,x0,loop
from runpy import run_path
n=loop-pc
branch=((n>>12&1)<<31)|((n>>5&63)<<25)|(13<<15)|(1<<12)|((n>>1&15)<<8)|((n>>11&1)<<7)|0x63
bp=emit(branch,'bne x13,x0,loop')
trace.extend([loop,bp,loop,bp])
# Taken branch skips a deliberately incorrect result.
emit((14<<15)|(14<<20)|(4<<8)|0x63,'beq x14,x14,+8')
emit(I(99,0,0,18),'addi x18,x0,99 (must be squashed)',retire=False)
emit(I(42,0,0,18),'addi x18,x0,42')
stop=emit(0x6f,'jal x0,0 (terminal marker)')
Path('program.hex').write_text(f.pack(items))
Path('program_mixed.lst').write_text('\n'.join(f'{p:04x}: {c:0{sz*2}x}  {name}' for p,c,sz,name in names)+'\n')
x={1:0x3fc00000,2:128,6:0x40000000,7:0x40800000,9:6,10:13,11:13,12:14,13:0,14:1,15:2,16:0x40900000,17:1,18:42}
fp={1:0x3fc00000,2:0x40000000,3:0x40600000,4:0x3f000000,5:0x40400000,6:0x3fc00000,7:0x40900000,8:0x40800000,9:0x40000000,10:0x40400000,11:0x3fc00000,12:0xbfc00000,13:0x40900000,14:0x3fc00000}
mem={32:13,33:0x40900000,34:0x3fc00000}
v=[f'stop_pc={stop};expected_count={len(trace)};']
for kind,d in [('exp_x',x),('exp_f',fp),('exp_m',mem)]:
 for k,val in d.items():v.append(f'{kind}[{k}]=32\'h{val:08x};')
for i,p in enumerate(trace):v.append(f'exp_pc[{i}]={p};')
Path('mixed_expected.vh').write_text('\n'.join(v)+'\n')
print(f'Generated {pc} bytes, {len(trace)} expected retirements, terminal PC {stop}')
