"""Reproduce filelist, mechanical rule check, coverage and lint discovery (R-015)."""
import json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1];REPO=ROOT.parent
SKILL=REPO/'.agents/skills/vlsit-rtl-generator/scripts'
def run(args,out):
    p=subprocess.run([sys.executable,'-B']+list(map(str,args)),cwd=REPO,capture_output=True,text=True)
    out.write_text('COMMAND: '+subprocess.list2cmdline([sys.executable,'-B']+list(map(str,args)))+'\n'+p.stdout+p.stderr)
    print(p.stdout[-160:]);return p.returncode
dirs=['top','sel','supervisor','rec','csr','arith','codec','splice','mrmgen','geom','ingress','cert','arb','health']
f=run([SKILL/'vlsit_lint_rtl.py','filelist']+[ROOT/'rtl'/d for d in dirs]+['--out',ROOT/'rtl/filelist_top.f','--top','m_tsmx_top','--force'],ROOT/'rtl/I1_FILELIST.md')
r=run([SKILL/'vlsit_rtl_check.py','check',ROOT/'rtl/top','--report',ROOT/'rtl/I1_RULES.md'],ROOT/'rtl/I1_RULE_CHECK.md')
c=run([SKILL/'vlsit_rtl_check.py','coverage'],ROOT/'rtl/I1_COVERAGE.md')
l=run([SKILL/'vlsit_lint_rtl.py','lint',ROOT/'rtl/filelist_top.f','--top','m_tsmx_top','--log',ROOT/'rtl/I1_LINT_DETAIL.md'],ROOT/'rtl/I1_LINT.md')
(HERE/'checks.json').write_text(json.dumps(dict(filelist=f,rules=r,coverage=c,lint=l),indent=2))
if f or r or (l not in (0,3)):raise SystemExit(1)
