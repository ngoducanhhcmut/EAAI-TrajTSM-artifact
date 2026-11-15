"""Compile once, baseline, then resume a frozen prefix of the registered plan."""
import argparse, hashlib, json, os, random, shutil, subprocess, sys, time
from pathlib import Path
from gen_faults import HERE,ROOT,sha,dump
from classify import parse,classify

def execute(cmd,log,timeout):
    start=time.monotonic(); timed=False
    with log.open('w') as f:
        f.write('COMMAND '+json.dumps([str(s) for s in cmd])+'\n');f.flush()
        try: rc=subprocess.run([str(s) for s in cmd],cwd=HERE,stdout=f,stderr=subprocess.STDOUT,timeout=timeout).returncode
        except subprocess.TimeoutExpired: rc=None;timed=True
    return dict(returncode=rc,wall_seconds=time.monotonic()-start,wall_timeout=timed)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--tool',choices=['iverilog','verilator'],default='iverilog')
    ap.add_argument('--n',type=int,default=24);ap.add_argument('--timeout',type=float,default=1800)
    ap.add_argument('--compile-only',action='store_true');ap.add_argument('--skip-compile',action='store_true')
    ap.add_argument('--results',default='results.jsonl');ap.add_argument('--baseline-only',action='store_true')
    a=ap.parse_args();assert 0<=a.n<=1440
    result_path=HERE/a.results
    if result_path.parent.resolve()!=HERE:ap.error('results must be inside fault/')
    sources=[ROOT/s for s in json.loads((HERE/'sources.json').read_text())]
    if a.tool=='iverilog':
        compiler=shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'
        vvp=shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe'
        binary=HERE/'fault.vvp'
        cmd=[compiler,'-g2012','-s','tb_fault','-o',binary]+sources+[HERE/'tb_fault.sv']
        sim=[vvp,'-i',binary]
    else:
        binary=HERE/'obj_fault/Vtb_fault'
        cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','-Wno-BLKANDNBLK','-j','4','--top-module','tb_fault','-Mdir',HERE/'obj_fault']+sources+[HERE/'tb_fault.sv']
        sim=[binary]
    identity=hashlib.sha256((''.join(sha(s) for s in sources+[HERE/'tb_fault.sv',HERE/'faults.json',HERE/'workload.json',HERE/'classify.py',HERE/'run_campaign.py'])).encode()).hexdigest()
    stamp=HERE/(a.tool+'_build.json')
    if not a.skip_compile:
        r=execute(cmd,HERE/(a.tool+'_compile.log'),1800)
        dump(a.tool+'_compile.json',r)
        if r['returncode']!=0: print('Compile failed; see',a.tool+'_compile.log');return 1
        dump(stamp.name,dict(identity=identity,command=[str(s) for s in cmd]))
    if not stamp.exists() or json.loads(stamp.read_text())['identity']!=identity:raise RuntimeError('stale build; recompile')
    if a.compile_only:return 0
    jobs=json.loads((HERE/'workload.json').read_text());baselines={}
    for job in jobs:
        name=f"{a.tool}_baseline_{job['id']}"; path=HERE/(name+'.json')
        if path.exists() and json.loads(path.read_text()).get('identity')==identity:
            r=json.loads(path.read_text())
        else:
            log=HERE/(name+'.log');r=execute(sim+['+FILE='+job['file']],log,a.timeout)
            r.update(identity=identity,observation=parse(log.read_text()))
            r['class']=classify(r['observation'],reference=True) if r['returncode']==0 else 'UNRESOLVED'
            dump(path.name,r)
        if r['class']!='MASKED':print('Baseline unresolved:',name,r);return 2
        baselines[job['id']]=r['observation']
        print('BASELINE',job['id'],'cycles',r['observation']['cycles'],'seconds',round(r['wall_seconds'],3),flush=True)
    if a.baseline_only:return 0
    done={}
    if result_path.exists():
        for line in result_path.read_text().splitlines():
            r=json.loads(line)
            if r['identity']!=identity or r['tool']!=a.tool:raise RuntimeError('results identity/tool mismatch')
            done[r['id']]=r
    for fault in json.loads((HERE/'faults.json').read_text())[:a.n]:
        if fault['id'] in done:continue
        baseline=baselines[fault['job']]
        cycle=random.Random(fault['cycle_seed']).randrange(1,baseline['cycles'])
        log=HERE/f"{a.tool}_fault_{fault['id']:04d}.log"
        r=execute(sim+[f"+FAULT_ID={fault['id']}",f'+FAULT_CYCLE={cycle}','+FILE='+jobs[fault['job']]['file']],log,a.timeout)
        obs=parse(log.read_text());outcome=classify(obs,baseline) if r['returncode']==0 else 'UNRESOLVED'
        record=dict(fault,cycle=cycle,identity=identity,tool=a.tool,**r,observation=obs,**{'class':outcome})
        with result_path.open('a') as f:f.write(json.dumps(record)+'\n');f.flush();os.fsync(f.fileno())
        print(f"{fault['id']} {fault['unit']} bit={fault['bit']} cycle={cycle} {outcome} {r['wall_seconds']:.3f}s",flush=True)
    return 0

if __name__=='__main__':sys.exit(main())
