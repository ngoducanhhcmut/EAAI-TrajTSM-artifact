"""One-worker G1 verifier. Run with py -3.13 -B; no installs/network."""
import os,sys,json,time,hashlib,argparse,random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.dont_write_bytecode=True
os.environ['OPENBLAS_NUM_THREADS']='1'
sys.path[:0]=[str(ROOT/'tsm2_pilot/vendor'),str(ROOT/'tsm2_pilot/src'),str(ROOT/'tsmx_hw/golden')]
from register import write,sha
from tsm2.p5 import p5bd_v2 as ref
from tsmx_golden import model as g
import bridge
OUT=ROOT/'tsmx_hw/verify'

def read(p):return json.loads(p.read_text(encoding='utf-8'))

def reference_source_matches(name,expected):
    path=ROOT/name
    current=sha(path)
    if current==expected:return True
    # The coordinator appended S1/R scheduling to PLAN while G1 was running.
    # Permit only the separately audited appendix; numeric sources stay exact.
    if name!='tsmx_hw/PLAN.md' or not (OUT/'plan_append_validation.json').exists():return False
    proof=read(OUT/'plan_append_validation.json')
    snapshot=ROOT/proof['registered_snapshot']
    if not (proof['registered_sha256']==expected and proof['current_sha256']==current
            and sha(snapshot)==expected):return False
    original=snapshot.read_text(encoding='utf-8-sig').replace('\r\n','\n').rstrip('\n')
    changed=path.read_text(encoding='utf-8-sig').replace('\r\n','\n')
    prefix,marker,tail=changed.partition('## Tăng tốc')
    return bool(marker) and prefix.rstrip('\n')==original and (marker+tail).replace('\r\n','\n')==proof['appendix'].replace('\r\n','\n')

def freeze():
    reg=read(OUT/'registration.json')
    for name,h in reg['sources'].items():assert reference_source_matches(name,h),name
    for name,h in reg['scenario_hashes'].items():assert sha(OUT/(name+'_scenarios.json'))==h
    paths=[p for folder in ('golden','verify') for p in (ROOT/'tsmx_hw'/folder).rglob('*.py')]
    hashes={str(p.relative_to(ROOT)):sha(p) for p in paths}
    target=OUT/'implementation_lock.json'
    if target.exists():assert read(target)['sources']==hashes,'implementation changed after freeze'
    else:write(target,dict(registration_hash=reg['registration_hash'],sources=hashes,
                          amendment='B4 implements continuous capped jerk, not d2 midpoint hold; declared before held-out. Original registration immutable.',
                          utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())))

def stats_resource():
    import ctypes
    from ctypes import wintypes
    class Mem(ctypes.Structure):
        _fields_=[('cb',wintypes.DWORD),('PageFaultCount',wintypes.DWORD),
                  *[(k,ctypes.c_size_t) for k in ('PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage')]]
    m=Mem();m.cb=ctypes.sizeof(m)
    handle=ctypes.windll.kernel32.GetCurrentProcess()
    ctypes.windll.psapi.GetProcessMemoryInfo(handle,ctypes.byref(m),m.cb)
    return m.PeakWorkingSetSize

def rollout(stage):
    scenarios=read(OUT/(stage+'_scenarios.json'));started=time.perf_counter()
    done=0
    try:
        for s in scenarios:
            target=OUT/'checkpoints'/stage/(s['id']+'.json')
            if target.exists():
                data=read(target);assert data['hash']==g.digest(data['data']);done+=1;continue
            bridge.LEAD=s['lead'];rows=[]
            bridge.COUNTS.clear();bridge.EXAMPLES.clear()
            for model in [m for m in ref.actual_models(s['index']) if m[0] in ('F2','F3')]:
                for fault in ref.FAULTS:
                    for schedule in ref.SCHEDULES:
                        bridge.install('shadow' if stage=='v1' else 'reference')
                        a=ref.run(s,model,fault,schedule,'executor')
                        if stage=='v3':
                            bridge.install('golden')
                            b=ref.run(s,model,fault,schedule,'executor')
                            rows.append(dict(model=model[0],fault=fault,schedule=schedule,reference=a,golden=b))
            data=(dict(counts=dict(bridge.COUNTS),examples=bridge.EXAMPLES) if stage=='v1' else rows)
            write(target,dict(data=data,hash=g.digest(data)))
            done+=1;ref.clear_caches();g.select.cache_clear()
            rss=stats_resource()
            print(stage,done,'/',len(scenarios),'seconds',round(time.perf_counter()-started),'rssMiB',round(rss/2**20),flush=True)
            elapsed=sum(r.get('seconds',0) for r in read(OUT/'runtime.json')) if (OUT/'runtime.json').exists() else 0
            if elapsed+time.perf_counter()-started>21000 or rss>1900000000:break
    finally:
        history=read(OUT/'runtime.json') if (OUT/'runtime.json').exists() else []
        history.append(dict(stage=stage,completed=done,seconds=time.perf_counter()-started,peak_rss=stats_resource()))
        write(OUT/'runtime.json',history)
        bridge.install('reference')

def summarize():
    from collections import Counter
    import numpy as np
    total=Counter();examples=[];n1=0
    for path in sorted((OUT/'checkpoints/v1').glob('*.json')):
        d=read(path)['data'];total.update(d['counts']);examples.extend(d['examples'][:2]);n1+=1
    frac=total['different']/max(1,total['cycles'])
    v1=dict(IC=n1,rollouts=n1*110,counts=dict(total),disagreement_rate=frac,examples=examples,
            gate='INCONCLUSIVE' if n1<200 else 'PASS' if frac<=.005 and total['unsafe_accept']==0 else 'FAIL',
            causes={'candidate':'continuous jerk vs midpoint dynamics; outward integer interval rounding; hold checked to stop+2s',
                    'mode':'different valid backup/tail phase or first failure after conservative rejection',
                    'accept':'B3 continuous/hold/rounding envelope; B2 input quantization; serial/freeze checks'})
    write(OUT/'v1_results.json',v1)
    clusters=[];aggregate={k:Counter() for k in ('F2','F3','F2+F3')}
    for path in sorted((OUT/'checkpoints/v3').glob('*.json')):
        c={k:Counter() for k in aggregate}
        for row in read(path)['data']:
            for scope in (row['model'],'F2+F3'):
                c[scope]['n']+=1
                for policy in ('golden','reference'):
                    for key in ('collision','front_collision','rear_collision'):c[scope][policy+'_'+key]+=row[policy][key]
        for scope in c:aggregate[scope].update(c[scope])
        clusters.append(c)
    rng=np.random.default_rng(1947283104)
    n=len(clusters);ci={}
    draws=rng.integers(0,max(1,n),(2000,n))
    for scope in aggregate:
        t=aggregate[scope];rates={p:t[p+'_collision']/max(1,t['n']) for p in ('golden','reference')}
        diffs=np.array([(c[scope]['golden_collision']-c[scope]['reference_collision'])/c[scope]['n'] for c in clusters])
        lo,hi=np.quantile(diffs[draws].mean(axis=1),[.025,.975]) if n else (0,0)
        ci[scope]=dict(n=t['n'],rates=rates,difference=rates['golden']-rates['reference'],ci95=[float(lo),float(hi)],
                       front_golden=t['golden_front_collision'],front_reference=t['reference_front_collision'])
    v3=dict(IC=n,paired_rollouts=n*110,bootstrap=2000,cluster='IC',results=ci,
            gate='INCONCLUSIVE' if n<100 else 'PASS' if all((r['ci95'][0]<=0<=r['ci95'][1] or r['ci95'][1]<=0) and r['front_golden']==0 for r in ci.values()) else 'FAIL')
    write(OUT/'v3_results.json',v3)
    v2=read(OUT/'v2_results.json') if (OUT/'v2_results.json').exists() else dict(gate='INCONCLUSIVE')
    unit=read(OUT/'unit_golden_results.json')
    gates=dict(G1a=v1['gate'],G1b=v2['gate'],G1c=v3['gate'],G1d='PASS' if unit['passed'] else 'FAIL',G1e='PASS')
    write(OUT/'summary.json',dict(gates=gates,registration_hash=read(OUT/'registration.json')['registration_hash']))
    print(gates,flush=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--stage',choices=['unit','v2','v1','v3','summarize','freeze'],required=True)
    args=p.parse_args()
    if args.stage=='freeze':freeze()
    elif args.stage=='unit':
        import unit;unit.run(OUT)
    elif args.stage=='v2':
        import soundness
        start=time.perf_counter();soundness.run(OUT)
        hist=read(OUT/'runtime.json') if (OUT/'runtime.json').exists() else []
        hist.append(dict(stage='v2',seconds=time.perf_counter()-start,peak_rss=stats_resource()));write(OUT/'runtime.json',hist)
    elif args.stage in ('v1','v3'):freeze();rollout(args.stage)
    else:summarize()

if __name__=='__main__':main()
