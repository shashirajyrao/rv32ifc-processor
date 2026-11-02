"""Exact rational binary32 rounding oracle (no host float arithmetic)."""
from fractions import Fraction as Q
from math import isqrt
def power(n):return Q(1<<n) if n>=0 else Q(1,1<<-n)
def finite(x):
 e=(x>>23)&255;f=x&0x7fffff
 return (-1 if x>>31 else 1)*Q(f+(0x800000 if e else 0))*power(e-150 if e else -149)
def log2(v):
 n=v.numerator.bit_length()-v.denominator.bit_length()
 return n-1 if v<power(n) else n
def finish(q,shift,sign,rem,cmp,rm):
 inc=rem and ((rm==0 and (cmp>0 or (cmp==0 and q&1))) or (rm==4 and cmp>=0) or (rm==2 and sign) or (rm==3 and not sign))
 q+=int(bool(inc))
 if q>=1<<24:q>>=1;shift+=1
 e=shift+23
 if e>127:
  inf=rm in (0,4) or (rm==2 and sign) or (rm==3 and not sign)
  return (sign<<31)|(0x7f800000 if inf else 0x7f7fffff),5
 if q<1<<23: bits=q
 else:bits=((e+127)<<23)|(q&0x7fffff)
 flags=(1 | (2 if bits<0x800000 else 0)) if rem else 0
 return (sign<<31)|bits,flags
def rounding(v,rm,zero_sign=0):
 if not v:return zero_sign<<31,0
 sign=int(v<0);v=abs(v);shift=max(log2(v)-23,-149);scaled=v/power(shift)
 q,r=divmod(scaled.numerator,scaled.denominator);cmp=2*r-scaled.denominator
 return finish(q,shift,sign,r!=0,cmp,rm)
def square_root(v,rm):
 if not v:return 0,0
 shift=max(log2(v)//2-23,-149);s=v/power(2*shift)
 q=isqrt(s.numerator//s.denominator)
 rem=q*q*s.denominator!=s.numerator
 cmp=4*s.numerator-(2*q+1)**2*s.denominator
 return finish(q,shift,0,rem,cmp,rm)
def cls(x):
 return 'nan' if x&0x7fffffff>0x7f800000 else 'inf' if x&0x7fffffff==0x7f800000 else 'zero' if x&0x7fffffff==0 else 'finite'
def arithmetic(op,a,b,c,rm):
 ca,cb,cc=cls(a),cls(b),cls(c);sa=a>>31;sb=b>>31;sc=c>>31
 args=[a] if op=='sqrt' else [a,b,c] if op.startswith('fma') else [a,b]
 sn=any(cls(v)=='nan' and not(v&0x400000) for v in args)
 if any(cls(v)=='nan' for v in args):
  invalid=sn or (op.startswith('fma') and ((ca=='inf' and cb=='zero') or (ca=='zero' and cb=='inf')))
  return 0x7fc00000,16 if invalid else 0
 if op=='sqrt':
  if sa and ca!='zero':return 0x7fc00000,16
  if ca in ('inf','zero'):return a,0
  return square_root(finite(a),rm)
 if op in ('add','sub'):
  sb^=op=='sub';b=(b&0x7fffffff)|(sb<<31)
  if ca=='inf' and cb=='inf' and sa!=sb:return 0x7fc00000,16
  if ca=='inf':return a,0
  if cb=='inf':return b,0
  return rounding(finite(a)+finite(b),rm,sa if ca==cb=='zero' and sa==sb else int(rm==2))
 sign=sa^sb
 if op=='div':
  if ca==cb=='zero' or ca==cb=='inf':return 0x7fc00000,16
  if ca=='inf':return (sign<<31)|0x7f800000,0
  if cb=='zero':return (sign<<31)|0x7f800000,8
  if ca=='zero' or cb=='inf':return sign<<31,0
  return rounding(finite(a)/finite(b),rm)
 if (ca=='inf' and cb=='zero') or (ca=='zero' and cb=='inf'):return 0x7fc00000,16
 if op=='mul':
  if 'inf' in (ca,cb):return (sign<<31)|0x7f800000,0
  return rounding(finite(a)*finite(b),rm,sign)
 # FMA operation bits negate product and addend independently.
 negp=int(op[-2]);negc=int(op[-1]);sign^=negp;sc^=negc
 if 'inf' in (ca,cb):
  if cc=='inf' and sign!=sc:return 0x7fc00000,16
  return (sign<<31)|0x7f800000,0
 if cc=='inf':return (sc<<31)|0x7f800000,0
 product=finite(a)*finite(b)*(-1 if negp else 1);addend=finite(c)*(-1 if negc else 1)
 zs=sign if product==addend==0 and sign==sc else int(rm==2)
 return rounding(product+addend,rm,zs)
