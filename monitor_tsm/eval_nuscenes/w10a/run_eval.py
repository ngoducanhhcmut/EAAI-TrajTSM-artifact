"""Detached four-worker training selection, then sealed-choice validation."""
import sys, os, json, pickle, time, shutil, subprocess, hashlib
from pathlib import Path
sys.dont_write_bytecode=True
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'):os.environ[key]='1'
import packetizer_v2 as pk
import replay_core as rc
os.environ['TEMP']=os.environ['TMP']=str(pk.HERE)
from collections import Counter
import numpy as np
HERE=pk.HERE
ENCODINGS=('E0','E1','E2')

def save(path,value):
    dest=HERE/path; tmp=dest.with_suffix(dest.suffix+'.tmp')
    tmp.write_text(json.dumps(value,indent=2,allow_nan=False,default=lambda x:x.item()));tmp.replace(dest)

def load_cache(split):
    path=HERE/'train_inputs.pkl' if split=='train' else HERE.parent/'w9b/inputs.pkl'
    return pickle.loads(path.read_bytes())

def worker(split,part):
    cache=load_cache(split)
    chosen=json.loads((HERE/'selection.json').read_text())['chosen'] if split=='val' else None
    folder=HERE/split;folder.mkdir(exist_ok=True)
    for i,scene in enumerate(cache['scenes']):
        if i%4!=part:continue
        for encoding in ENCODINGS:
            pk.ENCODING=encoding;pk.EMIT_MEM=encoding==chosen
            for source in 'HT':
                stem=folder/f'{scene}_{encoding}_{source}'
                if stem.with_suffix('.pkl').exists():continue
                counts={k:Counter() for k in ('admission_reasons','all_job_reasons','occupancy','commits','outcomes','b1_reasons')}
                meta=[];mem=audit=None
                if pk.EMIT_MEM:
                    mem=stem.with_suffix('.mem').open('w',encoding='ascii')
                    audit=stem.with_suffix('.jsonl').open('w',encoding='utf8')
                def sink(line,row,d):
                    o=row['response'];counts['all_job_reasons'][o['reason']]+=1
                    counts['occupancy'][row['mode']]+=1;counts['commits'][o['commit']]+=1
                    if mem:
                        mem.write(line);audit.write(json.dumps(row)+'\n')
                        meta.append(dict(kind=row['kind'],now=row['now'],reset=row['reset'],response=o,mode=row['mode']))
                replay=rc.run_scene(cache,scene,source,sink)
                if mem:mem.close();audit.close()
                for r in replay.rows:
                    o=r['response'];counts['admission_reasons'][o['reason']]+=1
                    counts['b1_reasons'][r['b1_reason']]+=1
                    category='accepted' if o['accept'] else 'backup' if r['mode']=='L1' else 'fallback' if r['mode']=='L2' else 'hold' if r['mode']=='HOLD' else 'mitigation'
                    counts['outcomes'][category]+=1
                result=dict(rows=replay.rows,counts=counts,jobs=replay.index,meta=meta)
                tmp=stem.with_suffix('.tmp')
                with tmp.open('wb') as f:pickle.dump(result,f,protocol=4)
                tmp.replace(stem.with_suffix('.pkl'))
        print(split,i,scene,flush=True)

def metrics(rows,scenes):
    index={s:i for i,s in enumerate(scenes)}
    draws=np.random.default_rng(20261104).integers(0,len(scenes),(2000,len(scenes)))
    def rate(num,den):
        nn=np.zeros(len(scenes));dd=nn.copy()
        for r,n,d in zip(rows,num,den):nn[index[r['scene']]]+=n;dd[index[r['scene']]]+=d
        n,d=int(nn.sum()),int(dd.sum());bn=nn[draws].sum(1);bd=dd[draws].sum(1)
        ci=np.percentile(100*bn[bd>0]/bd[bd>0],[2.5,97.5]).tolist() if np.any(bd>0) else None
        return dict(n=n,denominator=d,rate_pct=100*n/d if d else None,ci95_pct=ci)
    ac=[int(r['response']['accept']) for r in rows];safe=[r['oracle']['label']=='SAFE' for r in rows];unsafe=[r['oracle']['label']=='UNSAFE' for r in rows]
    return dict(acceptance=rate(ac,[1]*len(rows)),false_accept=rate([a*s for a,s in zip(ac,unsafe)],unsafe),false_reject=rate([(1-a)*s for a,s in zip(ac,safe)],safe),oracle_unknown=sum(r['oracle']['label']=='UNKNOWN' for r in rows))

def aggregate(split):
    cache=load_cache(split);out={}
    for encoding in ENCODINGS:
        out[encoding]={}
        for source in 'HT':
            rows=[];counts={};jobs=0
            for scene in cache['scenes']:
                r=pickle.loads((HERE/split/f'{scene}_{encoding}_{source}.pkl').read_bytes())
                rows.extend(r['rows']);jobs+=r['jobs']
                for key,c in r['counts'].items():counts.setdefault(key,Counter()).update(c)
            result=dict(metrics=metrics(rows,cache['scenes']),derivative_errors=rc.errstats(rows),jobs=jobs,**{k:dict(c) for k,c in counts.items()})
            result['outcomes'].update(attempts=len(rows),admitted=counts['b1_reasons']['ok'])
            result['occupancy']={m:counts['occupancy'][m] for m in pk.g.MODES}
            result['scenes_with_admissions']=len(set(r['scene'] for r in rows))
            out[encoding][source]=result
    save(split+'_results.json',out)
    return out

def stage(split):
    processes=[];logs=[]
    for part in range(4):
        out=(HERE/f'{split}_worker_{part}.log').open('w');err=(HERE/f'{split}_worker_{part}.err').open('w');logs.extend([out,err])
        processes.append(subprocess.Popen([sys.executable,'-B','-u',str(Path(__file__).resolve()),'--worker',split,str(part)],stdout=out,stderr=err,cwd=str(HERE),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)))
    codes=[p.wait() for p in processes]
    for f in logs:f.close()
    if any(codes):raise RuntimeError((split,codes))
    return aggregate(split)

def select(train):
    feasible=[];checks={}
    for e in ENCODINGS:
        checks[e]={}
        for p in 'HT':
            a=train[e][p]['metrics']['false_accept'];b=train['E0'][p]['metrics']['false_accept']
            checks[e][p]=bool(a['denominator'] and b['denominator'] and a['n']*b['denominator']<=b['n']*a['denominator'])
        if all(checks[e].values()):feasible.append(e)
    chosen=max(feasible,key=lambda e:(train[e]['T']['metrics']['acceptance']['n'],-ENCODINGS.index(e))) if feasible else 'E0'
    result=dict(chosen=chosen,feasible=feasible,constraint_checks=checks,training=train,rule='maximize T ACCEPT subject to FA(T), FA(H) <= E0 by exact fractions; E0/E1/E2 tie order; E0 fallback',sealed_before_validation=True,utc=__import__('datetime').datetime.utcnow().isoformat())
    save('selection.json',result);print('SELECTED',chosen,flush=True)
    return chosen

def shards(chosen):
    cache=load_cache('val');scenes=cache['scenes'];sizes={}
    for s in scenes:sizes[s]=sum(pickle.loads((HERE/'val'/f'{s}_{chosen}_{p}.pkl').read_bytes())['jobs'] for p in 'HT')
    groups=[[] for _ in range(8)];loads=[0]*8
    for s in sorted(scenes,key=lambda s:(-sizes[s],s)):
        k=min(range(8),key=lambda k:(loads[k],k));groups[k].append(s);loads[k]+=sizes[s]
    manifest=dict(width_bits=48037,hex_digits=12010,chosen=chosen,scenes=len(scenes),total_jobs=sum(loads),shards=[])
    with (HERE/'replay.jsonl').open('w',encoding='utf8') as audit:
        for k,group in enumerate(groups):
            entry=dict(shard=k,file=f'rtl_shard_{k}.mem',job_count=loads[k],scenes=sorted(group),sequences=[],expected_decisions={p:Counter() for p in 'HT'})
            n=0;dest=HERE/entry['file']
            with dest.open('wb') as mem:
                for s in sorted(group):
                    for p in 'HT':
                        stem=HERE/'val'/f'{s}_{chosen}_{p}';r=pickle.loads(stem.with_suffix('.pkl').read_bytes())
                        entry['sequences'].append(dict(scene=s,source=p,start_job=n,job_count=r['jobs'],jobs=r['meta']))
                        for row in r['rows']:entry['expected_decisions'][p][row['response']['reason']]+=1
                        with stem.with_suffix('.mem').open('rb') as f:shutil.copyfileobj(f,mem)
                        with stem.with_suffix('.jsonl').open(encoding='utf8') as f:shutil.copyfileobj(f,audit)
                        n+=r['jobs']
            assert n==loads[k]
            entry['sha256']=hashlib.sha256(dest.read_bytes()).hexdigest();entry['bytes']=dest.stat().st_size
            manifest['shards'].append(entry)
    save('rtl_manifest.json',manifest)
    # Final files now retain every row; remove only duplicated temporary streams.
    for path in (HERE/'val').glob('*.mem'):path.unlink()
    for path in (HERE/'val').glob('*.jsonl'):path.unlink()
    return manifest

def main():
    start=time.time();free=shutil.disk_usage('C:/').free;assert free>=10*2**30
    train=stage('train');chosen=select(train)
    val=stage('val');manifest=shards(chosen)
    summary=dict(status='golden complete; RTL pending supervisor',chosen=chosen,selection=json.loads((HERE/'selection.json').read_text()),validation=val,shard_job_counts=[r['job_count'] for r in manifest['shards']],total_jobs=manifest['total_jobs'],runtime_seconds=time.time()-start,free_bytes_start=free,free_bytes_end=shutil.disk_usage('C:/').free,bootstrap=dict(replicates=2000,seed=20261104,unit='all 150 scenes including empty scenes',interval='percentile 95%'))
    assert summary['free_bytes_end']>=10*2**30
    save('summary.json',summary)
    subprocess.run([sys.executable,'-B',str(HERE/'finish.py')],check=True)
    print('COMPLETE',chosen,summary['shard_job_counts'],flush=True)

if __name__=='__main__':
    if '--worker' in sys.argv:worker(sys.argv[-2],int(sys.argv[-1]))
    else:main()
