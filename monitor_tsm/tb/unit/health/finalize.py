"""Validate complete shard coverage and retained evidence before reporting R11 PASS."""
import json,re,hashlib
from run import HERE,HW
def main():
    r=json.loads((HERE/'results.json').read_text());n=json.loads((HERE/'vectors.json').read_text())['total']
    seen=[];hits=[0]*26
    for shard in r['shards']:
        assert shard['passed'] and shard['returncode']==0
        start,end=shard['start'],shard['end'];seen+=list(range(start,end))
        s=(HERE/shard['log']).read_text()
        jobs=[int(k) for k in re.findall(r'JOB (\d+) cycles=',s) if start<=int(k)<end]
        assert jobs==list(range(start,end)),(start,end,jobs)
        checks=re.findall(r'ASSERT (\d+) (\w+) spec5.3/5.5.11 hits=(\d+)',s)
        assert len(checks)==26
        for k,name,h in checks:assert int(h)>0;hits[int(k)]+=int(h)
    assert seen==list(range(n))
    mutants=json.loads((HERE/'mutants.json').read_text());source=json.loads((HERE/'source_mutants.json').read_text())
    assert len(mutants)==26 and all(m['killed'] for m in mutants)
    assert len(source)==4 and all(m['killed'] for m in source)
    m=json.loads((HERE/'measure.json').read_text())
    assert m['capacity1']['returncode']==m['budget']['returncode']==0
    assert all(t['returncode']!=0 for t in m['illegal'])
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (HW/'rtl/health').glob('*.sv')}
    line=f'PASS health: golden={n}/{n} assertions=26 mutants=26/26 source=4/4'
    with (HERE/'simulation.log').open('a') as f:f.write('\n'+line+'\n')
    (HERE/'final.json').write_text(json.dumps(dict(total=n,assertion_hits=hits,mutants=26,source_mutants=4,rtl_sha256=hashes,latency=r['latency'],ii=r['ii']),indent=2)+'\n')
    print(line)
if __name__=='__main__':main()
