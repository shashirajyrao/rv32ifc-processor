"""Human-readable instruction/value formatting for verification reports."""
import struct
RM={0:'RNE',1:'RTZ',2:'RDN',3:'RUP',4:'RMM',7:'DYNAMIC'}
def f32(x):return format(struct.unpack('<f',struct.pack('<I',x&0xffffffff))[0],'.9g')
def flags(x):return '|'.join(n for mask,n in [(16,'NV'),(8,'DZ'),(4,'OF'),(2,'UF'),(1,'NX')] if x&mask) or 'none'
def sx(x,n):return x-(1<<n) if x&(1<<(n-1)) else x
def mnemonic(ins,size=4):
 if size==2:
  q=ins&3;f=ins>>13;rd=(ins>>7)&31;rs2=(ins>>2)&31
  if q==0:return {0:'c.addi4spn',2:'c.lw',3:'c.flw',6:'c.sw',7:'c.fsw'}.get(f,'reserved C encoding')
  if q==1:
   if f==3:return 'c.addi16sp' if rd==2 else 'c.lui'
   if f==4:
    sub=(ins>>10)&3
    return ['c.srli','c.srai','c.andi',['c.sub','c.xor','c.or','c.and'][(ins>>5)&3]][sub]
   return {0:'c.nop' if rd==0 else 'c.addi',1:'c.jal',2:'c.li',5:'c.j',6:'c.beqz',7:'c.bnez'}[f]
  if q==2:
   if f==4:
    if ins&0x1000:return 'c.ebreak' if rd==rs2==0 else 'c.jalr' if rs2==0 else 'c.add'
    return 'c.jr' if rs2==0 else 'c.mv'
   return {0:'c.slli',2:'c.lwsp',3:'c.flwsp',6:'c.swsp',7:'c.fswsp'}.get(f,'reserved C encoding')
  return 'not compressed'
 op=ins&127;d=(ins>>7)&31;a=(ins>>15)&31;b=(ins>>20)&31;f=(ins>>12)&7;fn=ins>>25
 if op in (0x43,0x47,0x4b,0x4f):return f"{ {0x43:'fmadd.s',0x47:'fmsub.s',0x4b:'fnmsub.s',0x4f:'fnmadd.s'}[op]} f{d},f{a},f{b},f{ins>>27}"
 if op==0x53:
  name={0:'fadd.s',4:'fsub.s',8:'fmul.s',12:'fdiv.s',44:'fsqrt.s',16:['fsgnj.s','fsgnjn.s','fsgnjx.s'][min(f,2)],20:'fmax.s' if f else 'fmin.s',80:{0:'fle.s',1:'flt.s',2:'feq.s'}.get(f,'reserved compare'),96:'fcvt.wu.s' if b else 'fcvt.w.s',104:'fcvt.s.wu' if b else 'fcvt.s.w',112:'fclass.s' if f else 'fmv.x.w',120:'fmv.w.x'}.get(fn,'reserved FP encoding')
  if fn in (96,112):return f'{name} x{d},f{a}'
  if fn in (104,120):return f'{name} f{d},x{a}'
  if fn==80:return f'{name} x{d},f{a},f{b}'
  return f'{name} f{d},f{a}'+('' if fn==44 else f',f{b}')
 if op in (3,7):return f"{('flw' if op==7 else {0:'lb',1:'lh',2:'lw',4:'lbu',5:'lhu'}.get(f,'load?'))} {'f' if op==7 else 'x'}{d},{sx(ins>>20,12)}(x{a})"
 if op in (0x23,0x27):return f"{'fsw' if op==0x27 else {0:'sb',1:'sh',2:'sw'}.get(f,'store?')} {'f' if op==0x27 else 'x'}{b},{sx(((ins>>25)<<5)|d,12)}(x{a})"
 if op==0x13:
  name=['addi','slli','slti','sltiu','xori','srai' if ins&(1<<30) else 'srli','ori','andi'][f]
  return f'{name} x{d},x{a},{b if f in (1,5) else sx(ins>>20,12)}'
 if op==0x33:return f"{['sub' if fn==32 else 'add','sll','slt','sltu','xor','sra' if fn==32 else 'srl','or','and'][f]} x{d},x{a},x{b}"
 if op in (0x37,0x17):return f"{'lui' if op==0x37 else 'auipc'} x{d},0x{ins>>12:x}"
 if op==0x67:return f'jalr x{d},{sx(ins>>20,12)}(x{a})'
 if op==0x6f:
  off=sx(((ins>>31)<<20)|(((ins>>12)&255)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&1023)<<1),21)
  return f'jal x{d},offset {off}'
 if op==0x63:
  off=sx(((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&63)<<5)|(((ins>>8)&15)<<1),13)
  return f"{ {0:'beq',1:'bne',4:'blt',5:'bge',6:'bltu',7:'bgeu'}.get(f,'branch?')} x{a},x{b},offset {off}"
 if op==0x73:
  if ins in (0x73,0x100073):return 'ecall' if ins==0x73 else 'ebreak'
  return f"{ {1:'csrrw',2:'csrrs',3:'csrrc',5:'csrrwi',6:'csrrsi',7:'csrrci'}.get(f,'system?')} x{d},0x{ins>>20:03x},{a if f>=5 else 'x'+str(a)}"
 return 'unknown/reserved'

def listing(items):
 pc=0;n=0
 while n<len(items):
  ins,size=items[n];end=n+1
  if (ins,size)==(1,2):
   while end<len(items) and items[end]==(1,2):end+=1
  if end-n>6:
   print(f'  {pc:04x}..{pc+2*(end-n)-1:04x}  {end-n} x c.nop padding halfwords');pc+=2*(end-n);n=end;continue
  print(f'  PC=0x{pc:04x}  {size*8:2d}-bit  raw=0x{ins:0{size*2}x}  {mnemonic(ins,size)}')
  pc+=size;n+=1
