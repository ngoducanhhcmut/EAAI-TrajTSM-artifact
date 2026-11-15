"""Run R7 scoped design-rule checks, filelist generation and lint discovery."""
from pathlib import Path
import subprocess,sys,shutil
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
SKILL=HW.parent/'.agents/skills/vlsit-rtl-generator/scripts'
def run(script,args,log,allowed=(0,)):
    cmd=[sys.executable,str(SKILL/script),*map(str,args)]
    r=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (HERE/log).write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\n'+r.stdout+f'\nEXIT {r.returncode}\n')
    print(r.stdout);assert r.returncode in allowed
run('vlsit_spec_gaps.py',['gaps',HW/'spec/TSMX_Design_Specification.md'],'gap_scan.log',(0,2))
run('vlsit_rtl_check.py',['check',HW/'rtl/geom','--report',HW/'rtl/R7_RULES.md'],'rule_check.log')
run('vlsit_rtl_check.py',['coverage'],'rule_coverage.log')
run('vlsit_lint_rtl.py',['filelist',HW/'rtl/geom',HW/'rtl/arith/m_tsmx_arith_div.sv','--out',HW/'rtl/filelist_R7.f','--top','m_tsmx_geom','--force'],'filelist.log')
run('vlsit_lint_rtl.py',['lint',HW/'rtl/filelist_R7.f','--top','m_tsmx_geom'],'lint.log',(0,3))
if not shutil.which('verilator') and not shutil.which('verilator_bin'):
    (HERE/'verilator_compile.log').write_text('NOT RUN: Verilator5 unavailable; no tool installed.\nSee README.md for --binary --timing --assert command.\n')
