"""Compile portable SV, run real-resource regression, then sampled-output mutants."""
import sys,subprocess,json,time,shutil,re,concurrent.futures
from pathlib import Path
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
def call(cmd,log,timeout=300):
    t=time.time()
    with (HERE/log).open('w') as f:
        f.write('COMMAND '+repr(cmd)+'\n');f.flush()
        p=subprocess.run(cmd,cwd=HERE,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
    return dict(returncode=p.returncode,seconds=round(time.time()-t,3),log=log)
def main():
    files=[str(HW/'rtl'/x) for x in (HW/'rtl/filelist_R11.f').read_text().splitlines() if x and not x.startswith('//')]
    cmd=['iverilog','-g2012','-s','tb_m_tsmx_health','-I',str(HERE),'-o',str(HERE/'sim.vvp')]+files+[str(HERE/'tb_m_tsmx_health.sv')]
    result=call(cmd,'compile.log');print(result,flush=True)
    assert result['returncode']==0
    if '--compile-only' in sys.argv:return
    if '--mutants-only' not in sys.argv:
        n=json.loads((HERE/'vectors.json').read_text())['total']
        def shard(start):
            end=min(n,start+64)
            r=call(['vvp',str(HERE/'sim.vvp'),f'+START={start}',f'+END={end}'],f'shard_{start:04}.log',1800)
            s=(HERE/r['log']).read_text();r.update(start=start,end=end,passed=r['returncode']==0 and f'golden={end-start}/{end-start}' in s)
            assert r['passed'],s[-3000:]
            print('shard',start,end,'PASS',flush=True)
            return r
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            result=list(pool.map(shard,range(0,n,64)))
        text='\n'.join((HERE/r['log']).read_text() for r in result)
        measure=[tuple(map(int,m)) for m in re.findall(r'MEASURE latency=(\d+)\.\.(\d+) II=(\d+)\.\.(\d+)',text)]
        summary=dict(total=n,passed=n,shards=result,latency=[min(m[0] for m in measure),max(m[1] for m in measure)],ii=[min(m[2] for m in measure),max(m[3] for m in measure)])
        (HERE/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
        (HERE/'simulation.log').write_text(text+f'\nPASS health: golden={n}/{n} assertions=26\n')
        print(summary,flush=True)
    mutants=[]
    for i in range(26):
        r=call(['vvp',str(HERE/'sim.vvp'),f'+MUTANT={i}','+END=1'],f'mutant_{i:02}.log')
        s=(HERE/r['log']).read_text();r.update(id=i,killed=r['returncode']!=0 and f'ASSERT_FAIL {i} ' in s)
        mutants.append(r);print('mutant',i,r['killed'],flush=True)
        assert r['killed'],s[-1500:]
    (HERE/'mutants.json').write_text(json.dumps(mutants,indent=2)+'\n')
    n=json.loads((HERE/'vectors.json').read_text())['total']
    line=f'PASS health: golden={n}/{n} assertions=26 mutants=26/26'
    if '--mutants-only' not in sys.argv:
        with (HERE/'simulation.log').open('a') as f:f.write(line+'\n')
        print(line,flush=True)
if __name__=='__main__':main()
