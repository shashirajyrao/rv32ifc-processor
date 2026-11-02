"""Stage isolated simulation inputs and run checks. Requires Python 3 and Icarus."""
from pathlib import Path
import argparse,os,shutil,subprocess,sys
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('suite',choices=['mixed','cpi','all'],default='mixed',nargs='?');a=p.parse_args()
stage=root/'.build'/a.suite;stage.mkdir(parents=True,exist_ok=True)
for folder in ['rtl','tests/benches','tests/python','programs']:
 for src in (root/folder).iterdir():
  if src.is_file():shutil.copy2(src,stage/src.name)
shutil.copytree(root/'third_party/hardfloat',stage/'hardfloat',dirs_exist_ok=True)
env=os.environ.copy()
if os.name=='nt':
 for key,name in [('IVERILOG','iverilog.exe'),('VVP','vvp.exe')]:
  if Path('C:/iverilog/bin',name).exists():env.setdefault(key,str(Path('C:/iverilog/bin',name)))
def run(name):subprocess.run([sys.executable,name],cwd=stage,env=env,check=True)
if a.suite=='all':
 run('run_tests.py')
 for bench in ['tb_fp_pipeline_reset','tb_fp_conversion_reset']:
  code=f"import fc_verify as f; print(f.run([f.VVP,f.compile('{bench}')],'{bench}_extra.log'))"
  subprocess.run([sys.executable,'-c',code],cwd=stage,env=env,check=True)
 # The legacy integer generator writes program.hex in the isolated staging area.
 shutil.copy2(root/'programs/program.hex',stage/'program.hex')
 run('run_mixed_ifc.py');run('measure_cpi.py')
else:run('run_mixed_ifc.py' if a.suite=='mixed' else 'measure_cpi.py')
print('PASS: '+a.suite+'; logs in '+str(stage))
