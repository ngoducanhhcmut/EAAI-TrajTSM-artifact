"""TSM-X / TSMX project / v0.1. Record rule, gap and lint evidence in R10 paths."""
import sys
sys.dont_write_bytecode=True
from pathlib import Path
import subprocess
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parent
SKILL=REPO/'.agents/skills/vlsit-rtl-generator/scripts'


def record(args,path):
    cmd=[sys.executable,'-B',*map(str,args)]
    r=subprocess.run(cmd,cwd=REPO,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    path.write_text('```text\nCOMMAND '+subprocess.list2cmdline(cmd)+'\n'+r.stdout+
                    f'\nEXIT {r.returncode}\n```\n',encoding='utf8')
    print(path.name, 'exit',r.returncode)
    return r.returncode


def main():
    record([SKILL/'vlsit_spec_gaps.py','gaps',ROOT/'spec/TSMX_Design_Specification.md'],ROOT/'rtl/R10_GAPS.md')
    rc=record([SKILL/'vlsit_rtl_check.py','check',ROOT/'rtl/arb'],ROOT/'rtl/R10_RULES.md')
    record([SKILL/'vlsit_rtl_check.py','coverage'],ROOT/'rtl/R10_COVERAGE.md')
    record([SKILL/'vlsit_lint_rtl.py','filelist',ROOT/'rtl/arb','--out',ROOT/'rtl/filelist_R10.f',
            '--top','m_tsmx_arb','--force'],ROOT/'rtl/arb/filelist.log')
    lint=record([SKILL/'vlsit_lint_rtl.py','lint',ROOT/'rtl/filelist_R10.f',
                 '--top','m_tsmx_arb','--log',ROOT/'rtl/arb/lint_tool.log'],ROOT/'rtl/R10_LINT.md')
    record([HERE/'run.py','--verilator'],HERE/'verilator_attempt.log')
    if rc or lint not in (0,3): return 1
    return 0


if __name__=='__main__': sys.exit(main())
