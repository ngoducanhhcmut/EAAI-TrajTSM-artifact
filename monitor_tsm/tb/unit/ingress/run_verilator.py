"""Portable Verilator5 build/run, preserving commands and exit status under this TB."""
from pathlib import Path
import subprocess,shutil,sys
H=Path(__file__).resolve().parent
R=H.parents[3]/'tsmx_hw/rtl'
cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','--top-module','tb_m_tsmx_ingress',
     '--Mdir',str(H/'obj_dir'),'-I'+str(H),str(R/'arith/m_tsmx_arith_div.sv'),
     str(R/'arith/m_tsmx_arith.sv'),str(R/'ingress/m_tsmx_ingress.sv'),str(H/'tb_m_tsmx_ingress.sv')]
if not shutil.which('verilator'):
    (H/'verilator_compile.log').write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\nNOT RUN: Verilator unavailable in PATH. R-015.\nEXIT 3\n')
    print('Verilator not run: unavailable (R-015)');sys.exit(3)
def run(command,name):
    p=subprocess.run(command,cwd=H,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (H/name).write_text('COMMAND '+subprocess.list2cmdline(command)+'\n'+p.stdout+f'\nEXIT {p.returncode}\n')
    return p
p=run(cmd,'verilator_compile.log')
if p.returncode:sys.exit(p.returncode)
binary=H/'obj_dir'/('Vtb_m_tsmx_ingress.exe' if sys.platform=='win32' else 'Vtb_m_tsmx_ingress')
p=run([str(binary)],'verilator_simulation.log')
print(p.stdout[-2400:]);sys.exit(p.returncode)
