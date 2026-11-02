"""Run verification with readable output and a saved transcript."""
import argparse,os,subprocess,sys
from pathlib import Path

root=Path(__file__).resolve().parent
os.chdir(root)
parser=argparse.ArgumentParser()
parser.add_argument('--all-vectors',action='store_true',help='Print every FP vector, not just the 12 introductory examples')
parser.add_argument('--trace-cycles',type=int,default=0,help='Print initial pipeline cycles for every integration case')
args=parser.parse_args()
for variable,exe in [('IVERILOG','iverilog.exe'),('VVP','vvp.exe')]:
 candidate=Path('C:/iverilog/bin')/exe
 if variable not in os.environ and candidate.exists():os.environ[variable]=str(candidate)
with (root/'verification_terminal.log').open('w',encoding='utf-8') as log:
 def emit(line):
  print(line,flush=True);log.write(line+'\n');log.flush()
 emit('RV32F/C VERIFICATION: expected values versus simulated hardware')
 emit('Single-core = riscv_top; Pipeline = riscv_pipe_top. Values are hexadecimal unless labelled float.')
 emit('FP flags: NV invalid, DZ divide by zero, OF overflow, UF underflow, NX inexact.')
 emit('Engine cycles are FP-unit latency, not processor CPI.')
 commands=[['fc_verify.py','--verbose','--trace-cycles',str(args.trace_cycles)],['verify_fp_vectors.py']+(['--all-vectors'] if args.all_vectors else ['--show','12'])]
 for command in commands:
  emit('\nRunning: '+sys.executable+' '+' '.join(command))
  with subprocess.Popen([sys.executable,'-u']+command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True) as proc:
   for line in proc.stdout:emit(line.rstrip('\n'))
   code=proc.wait()
  if code:
   emit(f'FAIL: process exited {code}; see diagnostic above.');sys.exit(code)
 emit('\nPASS: all F/C integration cases, all independent FP vectors, and FP reset cancellation.')
 emit('Full log: '+str(root/'verification_terminal.log'))
 emit('Readable vector table: '+str(root/'fp_vectors.csv'))
