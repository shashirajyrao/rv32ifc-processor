import random,argparse,csv
from verification_format import mnemonic,f32,flags as flag_names,RM
from pathlib import Path
from fc_verify import compile,run,FP,VVP
from fp_reference import arithmetic,rounding,finite,cls,Q
parser=argparse.ArgumentParser(description='Independent exact-rational FP reference checks')
parser.add_argument('--show',type=int,default=0,help='Print first N vectors; all vectors still execute')
parser.add_argument('--all-vectors',action='store_true')
args=parser.parse_args()
v=[]
# Easy-to-check examples run before the randomized and edge-case regression.
examples=[('add',0,0x3fc00000,0x40100000,0,0),('sub',4,0x40100000,0x3fc00000,0,0),('mul',8,0x3fc00000,0x40100000,0,0),('div',12,0x40100000,0x3fc00000,0,0),('sqrt',44,0x40100000,0,0,0),('div',12,0x3f800000,0x40400000,0,0),('div',12,0x3f800000,0,0,0),('sqrt',44,0xbf800000,0,0,0),('add',0,0x3f800000,0x33800000,0,0),('add',0,0x3f800000,0x33800000,0,3),('mul',8,0x7f7fffff,0x40000000,0,0),('mul',8,1,0x3f000000,0,0)]
for op,fn,a,b,c,rm in examples:
 expected,flags=arithmetic(op,a,b,c,rm)
 v.append([FP(fn,4,1,0 if op=='sqrt' else 2,rm),a,b,c,0,0,expected,flags])
corners=[0,0x80000000,1,0x007fffff,0x00800000,0x3f800000,0xbf800000,0x3fc00000,0x3f800001,0x33800000,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7fc00000,0x7f800001]
rng=random.Random(20261030)
for op,fn in [('add',0),('sub',4),('mul',8),('div',12),('sqrt',44),('fma00',0x43),('fma01',0x47),('fma10',0x4b),('fma11',0x4f)]:
 for mode in range(5):
  pairs=[(a,corners[(n*7+mode)%len(corners)],corners[(n*3+1)%len(corners)]) for n,a in enumerate(corners)]
  pairs += [(rng.getrandbits(32),rng.getrandbits(32),rng.getrandbits(32)) for _ in range(12)]
  for a,b,c in pairs:
   expected,flags=arithmetic(op,a,b,c,mode)
   ins=FP(fn,4,1,0 if op=='sqrt' else 2,mode) if not op.startswith('fma') else (3<<27)|(2<<20)|(1<<15)|(mode<<12)|(4<<7)|fn
   v.append([ins,a,b,c,0,0,expected,flags])
 # Dynamic rounding uses the same operation with frm selected.
 for mode in range(5):
  a,b,c=0x3f800001,0x3f800001,0xbf800000;expected,flags=arithmetic(op,a,b,c,mode)
  ins=FP(fn,4,1,0 if op=='sqrt' else 2,7) if not op.startswith('fma') else (3<<27)|(2<<20)|(1<<15)|(7<<12)|(4<<7)|fn
  v.append([ins,a,b,c,0,mode,expected,flags])
for unsigned in (0,1):
 for rm in range(5):
  for x in [0,1,0xffffffff,0x80000000,0x7fffffff,16777217,0xff000001]:
   n=x if unsigned or x<0x80000000 else x-0x100000000
   out,flags=rounding(Q(n),rm)
   v.append([FP(0x68,4,1,unsigned,rm),0,0,0,x,0,out,flags])
  for a in corners+[0x4f000000,0x4f800000,0xcf000000,0x3fc00000,0xbfc00000]:
   lo=0 if unsigned else -2147483648; hi=4294967295 if unsigned else 2147483647
   if cls(a) in ('nan','inf'):
    out=hi if cls(a)=='nan' or not(a>>31) else lo;flags=16
   else:
    n=finite(a);q,r=divmod(abs(n).numerator,abs(n).denominator);d=abs(n).denominator;sign=n<0
    inc=bool(r) and ((rm==0 and (2*r>d or (2*r==d and q&1))) or (rm==4 and 2*r>=d) or (rm==2 and sign) or (rm==3 and not sign))
    out=(q+int(inc))*(-1 if sign else 1)
    if out<lo or out>hi:out=max(lo,min(hi,out));flags=16
    else:flags=int(bool(r))
   v.append([FP(0x60,4,1,unsigned,rm),a,0,0,0,0,out&0xffffffff,flags])
for a in corners:
 ca=cls(a);sn_a=ca=='nan' and not(a&0x400000)
 klass=(512 if a&0x400000 else 256) if ca=='nan' else (1 if a>>31 else 128) if ca=='inf' else (8 if a>>31 else 16) if ca=='zero' else (4 if a>>31 else 32) if not(a&0x7f800000) else (2 if a>>31 else 64)
 v.append([FP(0x70,4,1,0,1),a,0,0,0,0,klass,0])
 v.append([FP(0x70,4,1),a,0,0,0,0,a,0])
 v.append([FP(0x78,4,1),0,0,0,a,0,a,0])
 for b in corners:
  cb=cls(b);sn_b=cb=='nan' and not(b&0x400000);unord=ca=='nan' or cb=='nan'
  # Monotonic signed-magnitude key, with signed zeros equal.
  ka=~a if a>>31 else a|0x80000000;kb=~b if b>>31 else b|0x80000000
  eq=(a==b or ca==cb=='zero') and not unord;lt=ka<kb and not eq and not unord
  for f in (0,1,2):
   out=int((lt or eq) if f==0 else lt if f==1 else eq)
   flags=16 if ((sn_a or sn_b) if f==2 else unord) else 0
   v.append([FP(0x50,4,1,2,f),a,b,0,0,0,out,flags])
   sign=(b>>31) if f==0 else 1-(b>>31) if f==1 else (a^b)>>31
   v.append([FP(0x10,4,1,2,f),a,b,0,0,0,(a&0x7fffffff)|(sign<<31),0])
  for maximum in (0,1):
   if ca==cb=='nan':out=0x7fc00000
   elif ca=='nan':out=b
   elif cb=='nan':out=a
   elif ca==cb=='zero':out=((a&b) if maximum else (a|b))&0x80000000
   else:out=a if ((ka>kb) if maximum else (ka<kb)) else b
   v.append([FP(0x14,4,1,2,maximum),a,b,0,0,0,out,16 if sn_a or sn_b else 0])
Path('fp_vectors.hex').write_text(''.join(f'{n:08x}\n' for vector in v for n in vector))
with Path('fp_vectors.csv').open('w',newline='') as file:
 writer=csv.writer(file)
 writer.writerow(['index','instruction','mnemonic','rm_bits','frm','a_bits','a_float','b_bits','b_float','c_bits','c_float','x_bits','expected_bits','expected_flags'])
 for i,(ins,a,b,c,x,frm,out,fl) in enumerate(v):writer.writerow([i,f'{ins:08x}',mnemonic(ins),(ins>>12)&7,frm,f'{a:08x}',f32(a),f'{b:08x}',f32(b),f'{c:08x}',f32(c),f'{x:08x}',f'{out:08x}',flag_names(fl)])
sim=compile('tb_fp_vectors')
show=len(v) if args.all_vectors else max(0,args.show)
output=run([VVP,sim,f'+COUNT={len(v)}',f'+SHOW={show}'],'fp_vectors.log')
for line in output.splitlines():
 if not line.startswith('VECTOR '):print(line);continue
 t=line.split();i=int(t[1]);ins,a,b,c,x,actual,expected,af,ef=[int(z,16) for z in t[2:11]];cycles=int(t[11]);integer=int(t[12])
 print(f'\nVector {i}: {mnemonic(ins)}  instruction=0x{ins:08x} rm_bits={(ins>>12)&7} frm={v[i][5]}')
 print(f'  Inputs: a=0x{a:08x} ({f32(a)}), b=0x{b:08x} ({f32(b)}), c=0x{c:08x} ({f32(c)}), x=0x{x:08x}')
 fmt=(lambda z:str(z if z<0x80000000 else z-0x100000000)) if integer else f32
 print(f'  Expected: 0x{expected:08x} ({fmt(expected)}) flags={flag_names(ef)}')
 print(f'  Actual:   0x{actual:08x} ({fmt(actual)}) flags={flag_names(af)}  PASS  engine cycles={cycles}')
reset_sim=compile('tb_fp_reset')
print(run([VVP,reset_sim],'fp_reset.log'))
