import os
os.environ.setdefault('IVERILOG',('C:/iverilog/bin/iverilog.exe' if os.name=='nt' else 'iverilog'))
os.environ.setdefault('VVP',('C:/iverilog/bin/vvp.exe' if os.name=='nt' else 'vvp'))
import fc_verify as f
print(f.run([f.VVP,f.compile('tb_mixed_ifc')],'mixed_ifc.log'))
