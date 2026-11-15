"""Optional parallel execution of the same frozen pilot used by run_campaign.

Requires completed baselines; writes its records in the identical resume format.
No fault/cycle/workload selection differs from run_campaign.py.
"""
import argparse,concurrent.futures,json,os,random,shutil,threading
from classify import classify,parse
from gen_faults import HERE
from run_campaign import execute

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--ready-only',action='store_true',help='run only jobs whose own baseline already passed');a=ap.parse_args()
    tool='iverilog';identity=json.loads((HERE/(tool+'_build.json')).read_text())['identity']
    bases={i:json.loads((HERE/f'{tool}_baseline_{i}.json').read_text()) for i in range(4) if (HERE/f'{tool}_baseline_{i}.json').exists()}
    if a.ready_only:bases={i:b for i,b in bases.items() if b['class']=='MASKED'}
    if not a.ready_only:assert len(bases)==4
    assert all(b['identity']==identity and b['class']=='MASKED' for b in bases.values())
    jobs=json.loads((HERE/'workload.json').read_text())
    path=HERE/'results.jsonl';done=set();lock=threading.Lock()
    if path.exists():
        for line in path.read_text().splitlines():
            r=json.loads(line);assert r['identity']==identity and r['tool']==tool;done.add(r['id'])
    sim=[shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe','-i',HERE/'fault.vvp']
    def one(fault):
        baseline=bases[fault['job']]['observation']
        cycle=random.Random(fault['cycle_seed']).randrange(1,baseline['cycles'])
        log=HERE/f"{tool}_fault_{fault['id']:04d}.log"
        r=execute(sim+[f"+FAULT_ID={fault['id']}",f'+FAULT_CYCLE={cycle}','+FILE='+jobs[fault['job']]['file']],log,1800)
        obs=parse(log.read_text());outcome=classify(obs,baseline) if r['returncode']==0 else 'UNRESOLVED'
        record=dict(fault,cycle=cycle,identity=identity,tool=tool,**r,observation=obs,**{'class':outcome})
        with lock:
            with path.open('a') as f:f.write(json.dumps(record)+'\n');f.flush();os.fsync(f.fileno())
            print(f"{fault['id']} {fault['unit']} bit={fault['bit']} cycle={cycle} {outcome} {r['wall_seconds']:.3f}s",flush=True)
    faults=[f for f in json.loads((HERE/'faults.json').read_text())[:24] if f['id'] not in done and f['job'] in bases]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for f in concurrent.futures.as_completed([pool.submit(one,f) for f in faults]):f.result()

if __name__=='__main__':main()
