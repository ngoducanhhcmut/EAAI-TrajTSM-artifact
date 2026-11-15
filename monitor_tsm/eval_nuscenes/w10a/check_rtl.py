"""Strict checker for eight shard logs; never treats missing RTL as PASS.

JOB PASS means the existing TB checked response/command/ingress/supervisor/
event bits, deadline assertions, and CSR cycles == observed TB latency.
Golden vectors do not predict absolute cycles; that is not claimed here.
"""
import argparse, json, re, hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent

def check(logdir):
    manifest=json.loads((HERE/'rtl_manifest.json').read_text())
    batches=json.loads((HERE/'rtl_batches.json').read_text())['batches']
    result=dict(passed=False,shards=[],total_jobs=0,decision_tallies={},admission_outcomes={},cycle_meaning='TB CSR cycle count equals observed response latency; no golden absolute cycle prediction')
    for shard in manifest['shards']:
        k=shard['shard'];errors=[];path=logdir/f'w10a_shard_{k}.txt'
        done=Path(str(path)+'.done')
        text=path.read_text(errors='replace') if path.exists() else ''
        if not path.exists():errors.append('missing log')
        if not done.exists() or done.read_text().strip()!='0':errors.append('missing successful .done marker')
        if re.search(r'ASSERT_FAIL|%Error|%Fatal|\bFATAL\b|\bERR\b|mismatch|Assertion failed|RSP job=',text,re.I):errors.append('failure diagnostic in log')
        parts=re.split(r'^W10A_BATCH shard=(\d+) batch=(\d+) start=(\d+) count=(\d+)\s*$',text,flags=re.M)
        expected=[b for b in batches if b['shard']==k]
        actual=[];cycles=[]
        for i in range(1,len(parts),5):
            sk,b,start,count=map(int,parts[i:i+4]);body=parts[i+4]
            actual.append((sk,b,start,count))
            passes=[(int(j),int(c)) for j,c in re.findall(r'^JOB (\d+) PASS cycles=(\d+)(?:\s|$)',body,re.M)]
            if [j for j,c in passes]!=list(range(count)):errors.append(f'batch {b}: missing, duplicate or out-of-order JOB PASS')
            if any(c<=0 or c>1875000 for j,c in passes):errors.append(f'batch {b}: cycle deadline violation')
            if len(re.findall(rf'^PASS top jobs={count} max_cycles=\d+\s*$',body,re.M))!=1:errors.append(f'batch {b}: missing unique completion')
            if not re.search(r'assertion failures: 0, assertions never exercised: \d+',body):errors.append(f'batch {b}: missing assertion summary')
            cycles.extend(c for j,c in passes)
        wanted=[(k,b['batch'],b['start_job'],b['job_count']) for b in expected]
        if actual!=wanted:errors.append('batch headers differ from manifest')
        if len(cycles)!=shard['job_count']:errors.append('total JOB PASS count differs from shard manifest')
        mem=HERE/shard['file']
        if hashlib.sha256(mem.read_bytes()).hexdigest()!=shard['sha256']:errors.append('canonical shard hash mismatch')
        for b in expected:
            if hashlib.sha256((HERE/b['file']).read_bytes()).hexdigest()!=b['sha256']:errors.append(f"batch {b['batch']}: input hash mismatch")
        tallies={}
        if not errors:
            # The TB proved these golden decision bits for every indexed job.
            from collections import Counter
            for seq in shard['sequences']:
                c=tallies.setdefault(seq['source'],Counter())
                for row in seq['jobs']:
                    if row['kind']=='admission':
                        c[row['response']['reason']]+=1
                        target=result['admission_outcomes'].setdefault(seq['source'],{})
                        o=row['response'];mode=row.get('mode')
                        category='accepted' if o.get('accept',o['reason']=='ok') else 'backup' if mode=='L1' else 'fallback' if mode=='L2' else 'hold' if mode=='HOLD' else 'mitigation'
                        target['attempts']=target.get('attempts',0)+1
                        target[category]=target.get(category,0)+1
            for p,c in tallies.items():
                target=result['decision_tallies'].setdefault(p,{})
                for reason,n in c.items():target[reason]=target.get(reason,0)+n
        result['shards'].append(dict(shard=k,passed=not errors,errors=errors,jobs_passed=len(cycles),max_cycles=max(cycles) if cycles else None,admission_decisions=tallies))
        result['total_jobs']+=len(cycles)
    result['passed']=all(s['passed'] for s in result['shards']) and result['total_jobs']==manifest['total_jobs']
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--log-dir',type=Path,default=HERE.parents[1]/'tb/integ/vl_claude_r17_a8_apos');args=ap.parse_args()
    result=check(args.log_dir)
    (HERE/'rtl_checks.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
    raise SystemExit(0 if result['passed'] else 1)
