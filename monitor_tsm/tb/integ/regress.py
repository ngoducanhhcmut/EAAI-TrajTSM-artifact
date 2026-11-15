"""Complete I1 acceptance matrix. A nonzero or unrun category cannot become PASS.
Run from any directory; Linux uses python3 instead of py -3.13.
"""
import argparse,json,subprocess,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['iverilog','verilator'],default='iverilog')
    a=ap.parse_args();rows=[]
    categories=[('checks','check.py',[]),
       ('functional_2','run.py',['--lanes','2','--tag','full']),
       ('system_8','run.py',['--lanes','8','--limit','128','--allow-inactive','--tag','system']),
       ('worst_8','run.py',['--lanes','8','--skip-compile','--file','worst.mem','--limit','1',
                           '--allow-inactive','--worst','--tag','worst']),
       ('physical_timers_deadline_8','run_control.py',['--lanes','8']),
       ('smoke_2','run.py',['--lanes','2','--skip-compile','--file','smoke.mem','--limit','2','--tag','smoke']),
       ('bist_fault_2','run.py',['--lanes','2','--bist-fault','--allow-inactive','--tag','bist'])]
    for name,script,args in categories:
        if script in ('run.py','run_control.py'):args=['--tool',a.tool]+args
        cmd=[sys.executable,'-B',str(HERE/script)]+args
        start=time.monotonic()
        with (HERE/('regress_'+name+'.log')).open('w') as f:
            f.write('COMMAND: '+subprocess.list2cmdline(cmd)+'\n');f.flush()
            p=subprocess.run(cmd,cwd=HERE,stdout=f,stderr=f)
        # R-015 lack of a lint tool is separately disclosed by check.py.
        rows.append(dict(category=name,exit=p.returncode,seconds=round(time.monotonic()-start,2)))
        (HERE/'regression_results.json').write_text(json.dumps(dict(tool=a.tool,categories=rows,
            complete=len(rows)==len(categories),passed=all(x['exit']==0 for x in rows)),indent=2))
        print(name,p.returncode,flush=True)
        if p.returncode:return p.returncode
    return 0

if __name__=='__main__':sys.exit(main())
