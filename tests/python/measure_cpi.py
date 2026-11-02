"""Synthetic RV32IFC CPI benchmarks; run from any directory. No fixed-delay CPI."""
import os
from pathlib import Path
os.environ.setdefault('IVERILOG',('C:/iverilog/bin/iverilog.exe' if os.name=='nt' else 'iverilog'))
os.environ.setdefault('VVP',('C:/iverilog/bin/vvp.exe' if os.name=='nt' else 'vvp'))
import fc_verify as f
import json
sim=f.compile('tb_cpi')
def w(x):return (x,4)
I=f.I;FP=f.FP
setup=[w(0x3f8000b7),w(FP(0x78,1,1)),w(0x40000137),w(FP(0x78,2,2))]
integer=[w(I(1,0,0,1))]+[w(I(1,1,0,1)) for _ in range(96)]
compressed=[(0x4085,2)]+[(0x0085,2)]*96
fpbody=[w(FP(0,3,1,2)),w(FP(4,3,2,1)),w(FP(8,3,1,2)),w((2<<27)|(2<<20)|(1<<15)|(3<<7)|0x43),w(FP(0xc,3,1,2)),w(FP(0x2c,3,2)),w(FP(0x60,4,2)),w(FP(0x68,4,4)),w(FP(0x50,5,1,2,1)),w(FP(0x14,5,1,2)),w(FP(0x10,5,1,2)),w(FP(0x70,5,1,0,1))]
cases={'integer':integer,'compressed':compressed,'floating_point':setup+fpbody*8,'mixed_IFC':setup+sum(([(0x0085,2),w(I(1,6,0,6))]+fpbody for _ in range(6)),[])}
results=[];path=Path('cpi.hex');previous=path.read_bytes() if path.exists() else None
try:
 for name,items in cases.items():
  stop=sum(n for _,n in items);items=items+[w(0x0000006f)]
  path.write_text(f.pack(items))
  out=f.run([f.VVP,sim,f'+STOP={stop}',f'+COUNT={len(items)}'],f'cpi_{name}.log')
  line=next(l for l in out.splitlines() if l.startswith('CPI_RESULT ')).split()
  cyc,ret=int(line[1]),int(line[2]);row=dict(workload=name,cycles=cyc,retired=ret,cpi=cyc/ret,fp_wait=int(line[4]),fp_drain=int(line[5]))
  results.append(row)
  print(f'{name:18} cycles={cyc:5} retired={ret:4} CPI={cyc/ret:.4f} FP-wait={line[4]} FP-drain={line[5]}',flush=True)
 total=sum(r['cycles'] for r in results);count=sum(r['retired'] for r in results)
 print(f'Suite aggregate: {total}/{count} = {total/count:.4f} CPI (this workload mix only)')
 Path('cpi_results.json').write_text(json.dumps(results,indent=2))
finally:
 if previous is not None:path.write_bytes(previous)
 else:path.unlink(missing_ok=True)
