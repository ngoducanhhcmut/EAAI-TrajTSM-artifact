"""Resume an audited scene prefix using native Python worker processes.

The worker body and aggregator are extracted verbatim from run_w7c.main;
only scene partitioning and output paths change. No inference or oracle changes.
"""
import sys
sys.dont_write_bytecode=True
import run_w7c as a
import inspect
import json
import re
import subprocess
import time
from pathlib import Path


def functions():
    source=inspect.getsource(a.main)
    marker='    result = dict(post_hoc=True'
    assert source.count(marker)==1
    worker,tail=source.split(marker)
    worker=worker.replace('def main():','def worker(shard, shards, cutoff):',1)
    needle="            name = scene['name']\n"
    assert worker.count(needle)==1
    worker=worker.replace(needle,needle+"            if name <= cutoff or int(name.split('-')[1]) % shards != shard:\n                continue\n")
    worker=worker.replace("path = OUT/'accepted.jsonl'", "path = OUT/f'accepted_part_{shard}.jsonl'")
    worker+="    dump(OUT/f'part_{shard}.json', dict(violations=violations,mismatches=mismatches,root=str(root),elapsed_s=time.monotonic()-start))\n"
    aggregator='def aggregate(rows, violations, mismatches, start, root):\n'+marker+tail
    namespace=dict(a.__dict__)
    exec(compile(worker+'\n'+aggregator,str(Path(__file__).resolve()),'exec'),namespace)
    return namespace['worker'],namespace['aggregate']


def main():
    worker,aggregate=functions()
    if len(sys.argv)>1:
        worker(int(sys.argv[1]),int(sys.argv[2]),sys.argv[3])
        return
    start=time.monotonic()
    rawlog=(a.OUT/'run.log').read_bytes()
    log=rawlog.decode('utf-16' if rawlog.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8',errors='replace')
    completed=re.findall(r'(scene-\d+): accepted variant/plans=(\d+), CV violations=(\d+), elapsed=([\d.]+)s',log)
    cutoff,count,violations,prefix_time=completed[-1]
    assert int(violations)==0
    prefix=[]
    with (a.OUT/'accepted.jsonl').open(encoding='utf-8') as f:
        for line in f:
            try:
                r=json.loads(line)
            except json.JSONDecodeError:
                continue
            if r['scene']<=cutoff:
                prefix.append(r)
    assert len(prefix)==int(count),(len(prefix),count)
    a.dump(a.OUT/'parallel_runtime.json',dict(cutoff=cutoff,prefix_rows=len(prefix),prefix_elapsed_seconds=float(prefix_time),
        runtime_scope='Completed prefix elapsed from last scene log plus native parallel suffix wall time; discarded in-flight scene and restart gap excluded.'))
    shards=3
    children=[]
    logs=[]
    for shard in range(shards):
        f=(a.OUT/f'parallel_{shard}.log').open('w',encoding='utf-8')
        logs.append(f)
        children.append(subprocess.Popen([sys.executable,'-B',str(Path(__file__).resolve()),str(shard),str(shards),cutoff],
                                        stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW))
    codes=[p.wait() for p in children]
    for f in logs:
        f.close()
    assert codes==[0]*shards,codes
    rows=prefix
    violations=[]
    mismatches=[]
    for shard in range(shards):
        with (a.OUT/f'accepted_part_{shard}.jsonl').open(encoding='utf-8') as f:
            rows.extend(json.loads(line) for line in f)
        meta=json.loads((a.OUT/f'part_{shard}.json').read_text())
        violations.extend(meta['violations'])
        mismatches.extend(meta['mismatches'])
    rows.sort(key=lambda r:(r['scene'],r['token'],r['plan'],r['variant']))
    with (a.OUT/'accepted.jsonl').open('w',encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r,allow_nan=False)+'\n')
    aggregate(rows,violations,mismatches,start-float(prefix_time),Path(meta['root']))
    result=json.loads((a.OUT/'results.json').read_text(encoding='utf-8'))
    result['runtime_scope']=json.loads((a.OUT/'parallel_runtime.json').read_text())
    result['runtime_scope']['parallel_suffix_wall_seconds']=time.monotonic()-start
    result['sha256']['parallel_replay.py']=a.w.sha(__file__)
    a.dump(a.OUT/'results.json',result)


if __name__=='__main__':
    main()
