from pathlib import Path
import os,subprocess,json,sys,argparse
from verification_format import listing,f32,flags
verbose=False
trace_cycles=0
case_filter=None
ROOT=Path(__file__).resolve().parent; os.chdir(ROOT)
B=ROOT/'build_fc';B.mkdir(exist_ok=True)
IV=os.environ.get('IVERILOG','iverilog');VVP=os.environ.get('VVP','vvp')
def run(cmd,log,env=None):
 p=subprocess.run([str(x) for x in cmd],capture_output=True,text=True,env=env,timeout=120)
 (B/log).write_text(p.stdout+p.stderr)
 if p.returncode:
  print(p.stdout+p.stderr,flush=True)
  raise RuntimeError((cmd[0],p.returncode,log))
 return p.stdout
def compile(name):
 cfg=B/(name+'.conf');pp=B/(name+'.pp.v');out=B/(name+'.vvp')

 if os.name!='nt':
  sources=[p.name for p in ROOT.glob('*.v') if not p.name.startswith('tb_')]+[p.as_posix() for p in Path('hardfloat').glob('*.v')]
  run([IV,'-g2012','-gstrict-expr-width','-Ihardfloat','-s',name,'-o',out,name+'.v']+sources,name+'_compile.log')
  return out
 env=os.environ.copy();env['IVERILOG_ICONFIG']=str(cfg)
 sources=[p.name for p in ROOT.glob('*.v') if not p.name.startswith('tb_')]+[p.as_posix() for p in Path('hardfloat').glob('*.v')]
 run([IV,'-E','-g2012','-gstrict-expr-width','-Ihardfloat','-s',name,'-o',pp,name+'.v']+sources,name+'_pp.log',env)
 lines=cfg.read_text().splitlines();base=Path(next(l[8:] for l in lines if l.startswith('basedir:')))
 cfg.write_text('\n'.join('out:'+out.as_posix() if l.startswith('out:') else l for l in lines)+'\n')
 run([base/'ivl.exe','-C',cfg,'-C',base/'vvp.conf',pp],name+'_compile.log')
 return out
def I(n,a,f,d,op=0x13):return ((n&4095)<<20)|(a<<15)|(f<<12)|(d<<7)|op
def S(n,b,a,op=0x23):return (((n>>5)&127)<<25)|(b<<20)|(a<<15)|(2<<12)|((n&31)<<7)|op
def FP(fn,d,a,b=0,rm=0):return fn<<25|b<<20|a<<15|rm<<12|d<<7|0x53
def CSR(addr,d,a,f=1):return addr<<20|a<<15|f<<12|d<<7|0x73
def pack(items):
 data=b''.join(n.to_bytes(size,'little') for n,size in items);data+=b'\x01\x00'*((1024-len(data))//2)
 return ''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,1024,4))
def test(name,items,x=None,f=None,m=None,csr=0,trap=None):
 if case_filter and case_filter not in name:return
 if verbose:
  print('\n=== '+name+' ===',flush=True);listing(items)
  print('  Checked state       Expected    Single-core Pipeline    Status')
 (ROOT/'fc.hex').write_text(pack(items));(B/(name+'.hex')).write_text(pack(items))
 out=run([VVP,sim,f'+TRACE_CYCLES={trace_cycles}'],name+'.log');assert 'DONE' in out
 expected={'X':x or {},'F':f or {},'M':m or {}}
 for line in out.splitlines():
  t=line.split()
  if t and t[0]=='TRACE' and verbose:print(line)
  if t and t[0] in expected:
   kind,idx,a,b=t;idx=int(idx);a=int(a,16);b=int(b,16)
   if verbose and idx in expected[kind]:
    e=expected[kind][idx];label=f'{kind}{idx}' if kind!='M' else f'MEM[0x{idx*4:03x}]'
    print(f'  {label:19} {e:08x}    {a:08x}    {b:08x}    '+('PASS' if a==b==e else 'FAIL')+(f'  float: expected={f32(e)} actual={f32(a)}/{f32(b)}' if kind=='F' else ''))
   assert a==b,(name,'core mismatch',kind,idx,hex(a),hex(b))
   if idx in expected[kind]:assert a==expected[kind][idx],(name,kind,idx,hex(a),hex(expected[kind][idx]))
  elif t and t[0]=='CSR':
   ok=int(t[1],16)==csr and int(t[2],16)==csr
   if verbose:print(f'  FCSR                {csr:08x}    {int(t[1],16):08x}    {int(t[2],16):08x}    '+('PASS' if ok else 'FAIL')+f'  flags={flags(csr&31)} frm={csr>>5}')
   assert ok,(name,line,csr)
  elif t and t[0]=='TRAP':
   got=tuple(int(v,16) for v in t[3:]) if int(t[2]) else None
   if verbose:print(f'  Trap {t[1]}: expected={trap}, actual={got}: '+('PASS' if got==trap else 'FAIL'))
   assert got==trap,(name,line,trap)
 if verbose:print('  All 32 integer registers, 32 FP registers and 256 memory words agree between cores.\n  Only rows above have explicit expected values; agreement alone is not an independent oracle.')
 print('PASS',name,flush=True)
def words(ws):return [(n,4) for n in ws]
if __name__=='__main__':
 parser=argparse.ArgumentParser(description='RV32F/C architectural checks for both cores')
 parser.add_argument('--verbose',action='store_true')
 parser.add_argument('--trace-cycles',type=int,default=0)
 parser.add_argument('--case',help='Run cases containing this text')
 args=parser.parse_args();verbose=args.verbose;trace_cycles=max(0,args.trace_cycles);case_filter=args.case
 sim=compile('tb_fc')
 base=[0x3fc000b7,FP(0x78,1,1),0x40100137,FP(0x78,2,2)] # 1.5 and 2.25
 test('float_basic',words(base+[FP(0,3,1,2),FP(4,4,2,1),FP(8,5,1,2),FP(0xc,6,2,1),FP(0x2c,7,2),FP(0x70,3,3),S(0,3,0,0x27),I(0,0,2,8,7),0x63]),x={3:0x40700000},f={3:0x40700000,4:0x3f400000,5:0x40580000,6:0x3fc00000,7:0x3fc00000,8:0x40700000},m={0:0x40700000})
 test('float_fma',words(base+[0x43|(3<<7)|(1<<15)|(2<<20)|(1<<27),0x47|(4<<7)|(1<<15)|(2<<20)|(1<<27),0x4b|(5<<7)|(1<<15)|(2<<20)|(1<<27),0x4f|(6<<7)|(1<<15)|(2<<20)|(1<<27),0x63]),f={3:0x409c0000,4:0x3ff00000,5:0xbff00000,6:0xc09c0000})
 test('float_compare_convert',words(base+[FP(0x50,3,1,2,1),FP(0x50,4,1,1,2),FP(0x60,5,1,0,1),I(-7,0,0,6),FP(0x68,3,6),FP(0x70,7,3,0,1),CSR(1,8,0,2),0x63]),x={3:1,4:1,5:1,7:2,8:1},f={3:0xc0e00000},csr=1)
 test('compressed_mixed',[(0x4085,2),(I(9,1,0,2),4),(0x0085,2),(0x8106,2),(0x9106,2),(0x63,4)],x={1:2,2:4})
 test('compressed_fp_stack',words([I(128,0,0,2),0x3fc000b7,FP(0x78,1,1)])+[(0xe006|(1<<2),2),(0x6002|(3<<7),2),(0x63,4)],f={1:0x3fc00000,3:0x3fc00000},m={32:0x3fc00000})
 test('compressed_illegal',[(0,2)],trap=(2,0,0))
 test('squash_fp',[ (0x0080006f,4),(FP(0,3,1,2),4),(I(42,0,0,1),4),(0x63,4)],x={1:42},f={3:0})
 test('fp_load_fault',words([I(1024,0,2,1,7),FP(0,2,1,1)]),trap=(5,0,1024),f={1:0,2:0})
 test('fp_store_fault',words(base+[S(2,1,0,0x27)]),trap=(6,16,2))
 test('reserved_rounding',words(base+[FP(0,3,1,2,5)]),trap=(2,16,FP(0,3,1,2,5)),f={3:0})
 test('reserved_dynamic_rounding',words(base+[CSR(2,0,5,5),FP(0,3,1,2,7)]),csr=0xa0,trap=(2,20,FP(0,3,1,2,7)))
 test('flag_accumulation',words(base+[FP(0xc,3,1,0),FP(0x2c,4,3),0xbf8000b7,FP(0x78,5,1),FP(0x2c,6,5),CSR(1,5,0,2),CSR(1,6,0,1),CSR(1,7,0,2),0x63]),f={3:0x7f800000,4:0x7f800000,6:0x7fc00000},x={5:24,6:24,7:0},csr=0)
 # RNE 1+half-ulp stays 1; dynamic RUP gives next representable value.
 test('dynamic_rounding',words([0x3f8000b7,FP(0x78,1,1),0x338000b7,FP(0x78,2,1),FP(0,3,1,2,0),CSR(2,0,3,5),FP(0,4,1,2,7),CSR(3,5,0,2),0x63]),f={3:0x3f800000,4:0x3f800001},x={5:97},csr=97)
 test('nan_min_compare_class',words([0x7f8000b7,I(1,1,0,1),FP(0x78,1,1),0x3f800137,FP(0x78,2,2),FP(0x14,3,1,2),FP(0x50,3,1,2,2),FP(0x70,4,1,0,1),0x63]),f={3:0x3f800000},x={3:0,4:256},csr=16)
 test('fzero_writable',words([0x3f8000b7,FP(0x78,0,1),FP(0,1,0,0),FP(0x70,2,1),0x63]),f={0:0x3f800000,1:0x40000000},x={2:0x40000000})
 # c.jal +4 at PC2 links PC4, 32-bit ADDI at PC6 crosses a word boundary.
 test('compressed_jal',[(0x0001,2),(0x2011,2),(0x4105,2),(I(0,1,0,3),4),(0x63,4)],x={1:4,2:0,3:4})
 test('compressed_jalr',words([I(10,0,0,5)])+[(0x9282,2),(0x4105,2),(0x0001,2),(I(0,1,0,3),4),(0x63,4)],x={1:6,2:0,3:6})
 test('compressed_jr',words([I(8,0,0,5)])+[(0x8282,2),(0x4105,2),(I(42,0,0,3),4),(0x63,4)],x={1:0,2:0,3:42})
 test('compressed_ebreak',[(0x0001,2),(0x9002,2)],trap=(3,2,2))
 # c.addi4spn x8,sp,16; c.addi16sp sp,-16; c.sw/c.lw; c.swsp/c.lwsp.
 test('compressed_memory',words([I(128,0,0,2),I(42,0,0,9)])+[(0x0800,2),(0x717d,2),(0xc004,2),(0x4008,2),(0xc226,2),(0x4592,2),(0x63,4)],x={2:112,8:144,10:42,11:42},m={36:42,29:42})
 test('compressed_fp_prime',words([I(128,0,0,8),0x3fc000b7,FP(0x78,9,1)])+[(0xe004,2),(0x6008,2),(0x63,4)],f={9:0x3fc00000,10:0x3fc00000},m={32:0x3fc00000})
 # C.SRLI/C.SRAI/C.ANDI, C.SUB/XOR/OR/AND and C.SLLI.
 test('compressed_alu',words([I(-16,0,0,8),I(3,0,0,9)])+[(0x8409,2),(0x880d,2),(0x8c05,2),(0x8c25,2),(0x8c45,2),(0x8c65,2),(0x0406,2),(0x8005,2),(0x63,4)],x={8:3})
 test('compressed_lui_li',[(0x6185,2),(0x52fd,2),(0x63,4)],x={3:0x1000,5:0xffffffff})
 test('compressed_zero_branch',[(0x4401,2),(0xc011,2),(0x4105,2),(0x4405,2),(0xe011,2),(0x4109,2),(0x63,4)],x={8:1,2:0})
 test('compressed_back_jump',words([I(2,0,0,8)])+[(0x147d,2),(0xc011,2),(0xbff5,2),(0x63,4)],x={8:0})
 test('last_halfword',words([0x3fe0006f])+[(0x0001,2)]*509+[(0x9002,2)],trap=(3,1022,1022))
 test('cross_end_fault',words([0x3fe0006f])+[(0x0001,2)]*509+[(0x0013,2)],trap=(1,1022,1022))
 test('halfword_float',[(0x0001,2)]+words(base+[FP(0,3,1,2),FP(0x70,3,3),0x63]),x={3:0x40700000},f={3:0x40700000})
 test('nan_payload_memory',words([0x7fa120b7,I(0x345,1,0,1),FP(0x78,1,1),S(0,1,0,0x27),I(0,0,2,2,7),FP(0x70,2,2),0x63]),f={1:0x7fa12345,2:0x7fa12345},x={2:0x7fa12345},m={0:0x7fa12345})
 test('compressed_flwsp_f0',words([I(128,0,0,2),0x3f8000b7,FP(0x78,1,1)])+[(0xe006,2),(0x6002,2),(0x63,4)],f={0:0x3f800000,1:0x3f800000})
 for code in (0x2000,0xa000,0x2002,0xa002,0x4002,0x1002,0x6001,0x6101,0x8002,0x9c01):
  test(f'compressed_reserved_{code:04x}',[(code,2)],trap=(2,0,code))
 test('compressed_hints',[(0x0005,2),(0x4005,2),(0x6005,2),(0x0006,2),(0x8006,2),(0x9006,2),(0x63,4)],x={0:0})
