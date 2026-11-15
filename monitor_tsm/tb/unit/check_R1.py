"""Reproduce R1 gap scan, rule check, generated aggregate filelist, and lint attempts."""
from pathlib import Path
import subprocess
import sys

BASE=Path(__file__).resolve().parent
ROOT=BASE.parents[1]
RTL=ROOT/'rtl'
SKILL=ROOT.parent/'.agents/skills/vlsit-rtl-generator/scripts'

def run(script,args,log,allowed=(0,)):
    cmd=[sys.executable,str(SKILL/script),*map(str,args)]
    r=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    log.write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\n'+r.stdout+f'\nEXIT {r.returncode}\n',encoding='utf-8')
    print(r.stdout)
    if r.returncode not in allowed: raise RuntimeError(str(log))

def main():
    # Scoped extract avoids reading other blocks or concurrently changing codec sections.
    run('vlsit_spec_gaps.py',['gaps',RTL/'R1_SPEC_EXTRACT.md'],RTL/'R1_gap_scan.log',(0,1,2))
    paths=[]
    for blk in ['sel','supervisor','rec']:
        run('vlsit_rtl_check.py',['check',RTL/blk],RTL/f'R1_rules_{blk}.log')
        flist=RTL/blk/'filelist.f'
        run('vlsit_lint_rtl.py',['filelist',RTL/blk,'--out',flist,'--top',f'm_tsmx_{blk}','--force'],RTL/f'R1_filelist_{blk}.log')
        for line in flist.read_text().splitlines():
            if line.strip() and not line.startswith('//'):
                paths.append((flist.parent/line).resolve().relative_to(RTL).as_posix())
    # Three independent leaf tops have no common structural top in this wave.
    # Aggregate the three script-generated lists rather than dropping unreachable leaves.
    (RTL/'filelist_R1.f').write_text('// R1 independent leaf tops; aggregate of VLSIT-generated per-block filelists.\n'+''.join(x+'\n' for x in paths),encoding='ascii')
    run('vlsit_rtl_check.py',['check',RTL,'--report',RTL/'R1_rule_check.md'],RTL/'R1_rule_check.log')
    run('vlsit_rtl_check.py',['coverage'],RTL/'R1_rule_coverage.log')
    for blk in ['sel','supervisor','rec']:
        run('vlsit_lint_rtl.py',['lint',RTL/'filelist_R1.f','--top',f'm_tsmx_{blk}'],RTL/f'R1_lint_{blk}.log',(0,3))

if __name__=='__main__': main()
