"""Run independent RV32I regressions; any compiler/test failure exits nonzero."""
from pathlib import Path
import argparse, os, random, subprocess, sys, json
from rv32_model import execute
ROOT=Path(__file__).resolve().parent
os.chdir(ROOT)
parser=argparse.ArgumentParser()
parser.add_argument('--iverilog',default=os.environ.get('IVERILOG','iverilog'))
parser.add_argument('--vvp',default=os.environ.get('VVP','vvp'))
parser.add_argument('--split-compile',action='store_true',default=(os.name=='nt'),help='Run preprocessor and compiler separately (default on Windows), checking both exits')
parser.add_argument('--normal-compile',action='store_false',dest='split_compile',help='Use the standard Icarus driver pipeline')
args=parser.parse_args()
BUILD=ROOT/'build'; BUILD.mkdir(exist_ok=True)
sources=sorted(p.name for p in ROOT.glob('*.v') if not p.name.startswith('tb_'))+[p.as_posix() for p in Path('hardfloat').glob('*.v')]
def run(cmd,log):
    if str(cmd[0])==args.iverilog and '-Ihardfloat' not in cmd: cmd=[cmd[0],'-Ihardfloat']+cmd[1:]
    if args.split_compile and str(cmd[0])==args.iverilog and '-E' not in cmd:
        # Icarus exposes IVERILOG_ICONFIG for inspecting/reusing compiler settings.
        # This uses the same compiler backend, without the crashing shell pipe.
        config=(BUILD/(log+'.conf')).resolve()
        pp=(BUILD/(log+'.pp.v')).resolve()
        stage=list(cmd); out_index=stage.index('-o')+1; output=stage[out_index]
        stage[out_index]=pp; stage.insert(1,'-E')
        previous=os.environ.get('IVERILOG_ICONFIG')
        os.environ['IVERILOG_ICONFIG']=str(config)
        try: run(stage,log+'.preprocess')
        finally:
            if previous is None: os.environ.pop('IVERILOG_ICONFIG',None)
            else: os.environ['IVERILOG_ICONFIG']=previous
        lines=config.read_text().splitlines()
        basedir=next(line[8:] for line in lines if line.startswith('basedir:'))
        config.write_text('\n'.join('out:'+str(output).replace('\\','/') if line.startswith('out:') else line for line in lines)+'\n')
        backend=Path(basedir)/('ivl.exe' if os.name=='nt' else 'ivl')
        return run([backend,'-C',config,'-C',Path(basedir)/'vvp.conf',pp],log)
    p=subprocess.run([str(x) for x in cmd],capture_output=True,text=True,timeout=90)
    (BUILD/log).write_text(p.stdout+p.stderr)
    if p.returncode: raise RuntimeError(f'{cmd[0]} exited {p.returncode}; see build/{log}')
    if 'FAIL' in p.stdout or 'FATAL' in p.stdout: raise RuntimeError(f'test failed: build/{log}')
    return p.stdout
def compile_tb(name,extra=None):
    target=BUILD/(name+('' if not extra else '_custom')+'.vvp')
    run([args.iverilog,'-g2012','-gstrict-expr-width','-Wall','-s',name,'-o',target]+(extra or [])+[name+'.v']+sources,name+'_compile.log')
    return target
def i(imm,a,f,d,op=0x13): return ((imm&4095)<<20)|(a<<15)|(f<<12)|(d<<7)|op
def r(f7,b,a,f,d): return (f7<<25)|(b<<20)|(a<<15)|(f<<12)|(d<<7)|0x33
def s(imm,b,a,f=2): return (((imm>>5)&127)<<25)|(b<<20)|(a<<15)|(f<<12)|((imm&31)<<7)|0x23
def j(off,d=0): return (((off>>20)&1)<<31)|(((off>>1)&1023)<<21)|(((off>>11)&1)<<20)|(((off>>12)&255)<<12)|(d<<7)|0x6f
def b(off,rs2,rs1,f=0): return (((off>>12)&1)<<31)|(((off>>5)&63)<<25)|(rs2<<20)|(rs1<<15)|(f<<12)|(((off>>1)&15)<<8)|(((off>>11)&1)<<7)|0x63
results=[]
run([sys.executable,'gen_program.py'],'generator.log')
(ROOT/'control.hex').write_text(''.join(f'{w:08x}\n' for w in [0x13,0x00700093,0x00102023,0x63]+[0x13]*252))
# The historical testbench filename differs from its module name.
demo=BUILD/'demo.vvp'
run([args.iverilog,'-g2012','-gstrict-expr-width','-Wall','-s','tb_riscv_pipe','-o',demo,'tb_riscv_top.v']+sources,'demo_compile.log')
run([args.vvp,demo],'demo.log'); print('PASS demo',flush=True)
branch=compile_tb('tb_branch_unit'); run([args.vvp,branch],'branch.log'); print('PASS 22648 branch checks',flush=True)
sim=compile_tb('tb_regression')
def test(name,words,stop=None,trap=None,stalls=None,reset_pc=0,simulator=None,known=None):
    if stop is None and trap is None: stop=4*(len(words)-1)
    expected=execute(words,stop_pc=stop,reset_pc=reset_pc)
    assert expected['trap']==trap,(name,expected['trap'],trap)
    if known:
        for reg,val in known.items(): assert expected['regs'][reg]==val,(name,reg)
    assert len(words)<=256
    image=''.join(f'{w:08x}\n' for w in words+[0x13]*(256-len(words)))
    (ROOT/'regression.hex').write_text(image); (BUILD/(name+'.hex')).write_text(image)
    out=run([args.vvp,simulator or sim],name+'.log')
    assert 'DONE' in out,name+' incomplete simulation'
    seen={'REG':0,'MEM':0}; retired=[]; traps=0
    for line in out.splitlines():
        if line.startswith(('REG ','MEM ')):
            kind,idx,p,q=line.split(); idx=int(idx); seen[kind]+=1
            exp=expected['regs' if kind=='REG' else 'mem'][idx]
            assert int(p,16)==exp and int(q,16)==exp,(name,kind,idx,p,q,hex(exp))
        elif line.startswith('TRAP '):
            _,core,flag,cause,pc,value=line.split(); traps+=1
            got=(int(cause,16),int(pc,16),int(value,16)) if int(flag) else None
            assert got==trap,(name,core,got,trap)
        elif line.startswith('RET '): retired.append(int(line.split()[1],16))
        elif line.startswith('STALLS ') and stalls is not None:
            assert int(line.split()[1])==stalls,(name,line,stalls)
    assert seen=={'REG':32,'MEM':256} and traps==2,name
    assert retired[:len(expected['trace'])]==expected['trace'],(name,'retirement order')
    if trap: assert retired==expected['trace'],(name,'faulting/younger instruction retired')
    results.append(name); print('PASS '+name,flush=True)

test('btb_alias',[j(256)]+[0x13]*63+[i(1,0,0,1),i(42,0,0,2),0x63],known={1:1,2:42})
test('jalr_alu_forward',[i(17,0,0,1),i(0,1,0,5,0x67),i(99,0,0,2),0x63,i(42,0,0,3),0x63],known={2:0,3:42,5:8})
test('jalr_load_forward',[i(24,0,0,1),s(0,1,0),i(0,0,2,2,3),i(0,2,0,5,0x67),i(99,0,0,3),0x63,i(42,5,0,3),0x63],known={3:58,5:16})
test('jalr_rd_rs1',[i(16,0,0,1),i(0,1,0,1,0x67),i(99,0,0,2),0x63,i(0,1,0,2),0x63],known={1:8,2:8})
test('jalr_target_change',[i(16,0,0,1),i(0,1,0,5,0x67),0x63,0x13,i(32,0,0,1),j(-16),0x13,0x13,i(42,0,0,2),0x63],known={2:42,5:8})
test('load_extensions',[0x800080b7,i(-128,1,0,1),s(0,1,0)]+[i(off,0,f,d,3) for d,(f,off) in enumerate([(0,0),(4,0),(0,3),(4,3),(1,2),(5,2)],2)]+[0x63])
test('subword_stores',[i(-1,0,0,1),s(0,1,0),i(18,0,0,2),s(1,2,0,0),s(2,2,0,1),i(0,0,2,3,3),0x63],known={3:0x001212ff})
test('reset_side_effect',[i(1,1,0,1),0x63],known={1:1})
test('no_false_stall',[i(0,0,2,5,3),i(5,0,0,6),0x63],stalls=0)
test('real_load_store_stall',[i(42,0,0,1),s(0,1,0),i(0,0,2,2,3),s(4,2,0),i(4,0,2,3,3),0x63],stalls=1,known={3:42})
test('fence',[i(42,0,0,1),s(0,1,0),0x0ff0000f,i(0,0,2,2,3),0x63],known={2:42})
test('ecall_precise',[i(7,0,0,1),s(0,1,0),0x73,i(99,0,0,2),s(0,2,0)],trap=(11,8,0))
test('ebreak_precise',[i(7,0,0,1),0x100073,i(99,0,0,1),s(0,1,0)],trap=(3,4,4))
for name,ins in [('unknown',0xffffffff),('mul',r(1,2,1,0,3)),('bad_shift',i(0x41,0,1,1)),('bad_branch',b(8,0,0,2)),('bad_load',i(0,0,3,1,3)),('bad_store',s(0,1,0,3)),('bad_jalr',i(0,0,1,1,0x67)),('csr',0x300110f3)]:
    test('illegal_'+name,[i(7,0,0,1),ins,i(99,0,0,1),s(0,1,0)],trap=(2,4,ins))
for f,addr,cause in [(1,1,4),(2,2,4),(2,1024,5)]:
    test(f'load_fault_{f}_{addr}',[i(7,0,0,1),i(addr,0,f,2,3),s(0,1,0)],trap=(cause,4,addr))
for f,addr,cause in [(1,1,6),(2,2,6),(2,1024,7)]:
    test(f'store_fault_{f}_{addr}',[i(7,0,0,1),s(addr,1,0,f),i(99,0,0,1)],trap=(cause,4,addr))
test('load_x0_fault',[i(1024,0,2,0,3),i(99,0,0,1)],trap=(5,0,1024))
test('jal_alignment',[j(2,1),i(99,0,0,1)],trap=(0,0,2))
test('jalr_alignment',[i(3,0,0,1),i(0,1,0,2,0x67),i(99,0,0,1)],trap=(0,4,2))
test('taken_branch_alignment',[b(2,0,0),i(99,0,0,1)],trap=(0,0,2))
test('untaken_branch_alignment',[i(1,0,0,1),b(2,1,0),i(42,0,0,2),0x63],known={2:42})
test('fetch_access',[j(1024,1)],trap=(1,1024,1024),known={1:4})
test('wrong_path_trap',[j(12),0x73,0xffffffff,i(42,0,0,1),0x63],known={1:42})
test('memory_last_byte',[i(-1,0,0,1),s(1023,1,0,0),i(1023,0,4,2,3),0x63],known={2:255})
# Exercise all six branch conditions on signed/unsigned corner values.
for f in (0,1,4,5,6,7):
    for x,y in [(0,0),(1,2),(-1,1),(1,-1),(-1,-1)]:
        test(f'branch_{f}_{x}_{y}',[i(x,0,0,1),i(y,0,0,2),b(8,2,1,f),i(99,0,0,3),i(42,0,0,4),0x63])
# Real backward loops train counters, change direction and exercise dependencies.
test('loop_prediction',[i(20,0,0,1),i(0,0,0,2),i(1,2,0,2),i(-1,1,0,1),b(-8,0,1,1),0x63],known={1:0,2:20})
for seed in range(20):
    rng=random.Random(seed); words=[0x13]
    for n in range(160):
        d=rng.randrange(32); a=rng.randrange(32); rs2=rng.randrange(32); f=rng.randrange(8); kind=rng.randrange(7)
        if kind==0:
            imm=rng.randrange(-2048,2048)
            if f in (1,5): imm=rng.randrange(32)|(0x400 if f==5 and rng.randrange(2) else 0)
            words.append(i(imm,a,f,d))
        elif kind==1: words.append(r(32 if f in (0,5) and rng.randrange(2) else 0,rs2,a,f,d))
        elif kind==2:
            size=rng.randrange(3); addr=rng.randrange(128)//(1<<size)*(1<<size); words.append(s(addr,rs2,0,size))
        elif kind==3:
            f=rng.choice([0,1,2,4,5]); size=1<<(f&3); addr=rng.randrange(128)//size*size; words.append(i(addr,0,f,d,3))
        elif kind in (4,5): words.append((rng.randrange(1<<20)<<12)|(d<<7)|(0x37 if kind==4 else 0x17))
        else: words.append(b(4,a,rs2,rng.choice([0,1,4,5,6,7])))
    words.append(0x63); test(f'random_{seed}',words)
for vec,cause in [(2,0),(1024,1)]:
    custom=compile_tb('tb_regression',[f'-Ptb_regression.RESET_VECTOR={vec}'])
    test(f'reset_vector_{vec}',[0x13],trap=(cause,vec,vec),reset_pc=vec,simulator=custom)
unit=compile_tb('tb_control_regressions'); run([args.vvp,unit],'control.log'); print('PASS control/reset regressions',flush=True)
(BUILD/'results.json').write_text(json.dumps({'passed':results,'failures':0},indent=2))
print(f'PASS: {len(results)} architectural programs, demo, branch and control/reset suites',flush=True)
print(run([sys.executable,'fc_verify.py'],'fc_integration.log'),end='')
print(run([sys.executable,'verify_fp_vectors.py'],'fp_vectors.log'),end='')
print('PASS: complete RV32IFC regression suite',flush=True)


