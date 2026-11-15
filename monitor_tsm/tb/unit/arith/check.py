"""Scoped VLSIT checks and lint attempt. All logs remain in this block's directory."""
from pathlib import Path
import subprocess,sys
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
SKILL=HW.parent/'.agents/skills/vlsit-rtl-generator/scripts'
def run(script,args,log,allowed=(0,)):
    cmd=[sys.executable,str(SKILL/script),*map(str,args)]
    r=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (HERE/log).write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\n'+r.stdout+f'\nEXIT {r.returncode}\n')
    print(r.stdout)
    assert r.returncode in allowed,(script,r.returncode)
run('vlsit_spec_gaps.py',['gaps',HW/'spec/TSMX_Design_Specification.md'],'gap_scan.log',(0,1,2))
run('vlsit_rtl_check.py',['check',HW/'rtl/arith','--report',HW/'rtl/R2_RULES.md'],'rule_check.log')
run('vlsit_rtl_check.py',['coverage'],'rule_coverage.log')
run('vlsit_lint_rtl.py',['filelist',HW/'rtl/arith','--out',HW/'rtl/filelist_R2.f','--top','m_tsmx_arith','--force'],'filelist.log')
run('vlsit_lint_rtl.py',['lint',HW/'rtl/filelist_R2.f','--top','m_tsmx_arith'],'lint.log',(0,3))
