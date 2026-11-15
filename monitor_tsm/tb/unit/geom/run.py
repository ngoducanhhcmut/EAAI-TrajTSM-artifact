"""Reproducible Icarus baseline, exhaustive disjoint shards and output mutation campaign."""
from pathlib import Path
import subprocess,sys,json,re,time,concurrent.futures
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
RTL=HW/'rtl'

def compile_to(out,main=None,defines=(),swept=None):
    cmd=['iverilog','-g2012','-s','tb_m_tsmx_geom','-I',str(HERE),*defines,'-o',str(out),
         str(RTL/'arith/m_tsmx_arith_div.sv'),str(RTL/'geom/m_tsmx_geom_adv.sv'),
         str(swept or RTL/'geom/m_tsmx_geom_swept.sv'),str(main or RTL/'geom/m_tsmx_geom.sv'),str(HERE/'tb_m_tsmx_geom.sv')]
    r=subprocess.run(cmd,cwd=HERE,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    out.with_suffix('.compile.log').write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\n'+r.stdout+f'\nEXIT {r.returncode}\n')
    assert r.returncode==0,r.stdout[-3000:]

def sim(args,log,exe=None):
    cmd=['vvp',str(exe or HERE/'sim.vvp'),*args]
    with log.open('w') as f:
        f.write('COMMAND '+subprocess.list2cmdline(cmd)+'\n');f.flush()
        r=subprocess.run(cmd,cwd=HERE,text=True,stdout=f,stderr=subprocess.STDOUT,timeout=7200)
        f.write(f'\nEXIT {r.returncode}\n')
    return r.returncode,log.read_text()

def shard(item):
    start,n=item;log=HERE/'shards'/f'S{start:05d}.log'
    old=log.read_text() if log.exists() else ''
    if '--resume' in sys.argv and f'PASS geom: golden={n}/{n}' in old and 'EXIT 0' in old:
        code,txt=0,old
    else:code,txt=sim([f'+START={start}',f'+LIMIT={n}','+NOSTALL=1'],log)
    assert code==0 and f'PASS geom: golden={n}/{n}' in txt,txt[-2500:]
    hits={int(i):int(v) for i,v in re.findall(r'ASSERT (\d+) .* hits=(\d+)',txt)}
    lat=re.search(r'LATENCY min=(\d+) max=(\d+) cycles/job job_II_max=(\d+)',txt)
    actor=re.search(r'ACTOR_II min=(\d+) max=(\d+) hits=(\d+) row_cycles_max=(\d+)',txt)
    result=dict(start=start,count=n,hits=hits,latency=list(map(int,lat.groups())),actor=list(map(int,actor.groups())))
    print('passed shard',start,n,flush=True)
    return result

def mutant(i):
    # Select a known preflight reject for the reject-only assertions; all others use case zero.
    start=128 if i in (21,23) else 0
    code,txt=sim([f'+MUTANT={i}',f'+START={start}','+LIMIT=40'],HERE/'mutants'/f'M{i:02d}.log')
    assert code!=0 and f'ASSERT_FAIL {i} ' in txt,(i,txt[-2000:])
    print('killed mutant',i,flush=True)
    return dict(id=i,killed=True)

def main():
    n=json.loads((HERE/'vectors.json').read_text())['total']
    for name in ('shards','mutants'):(HERE/name).mkdir(exist_ok=True)
    if '--mutants-only' not in sys.argv and '--resume' not in sys.argv:compile_to(HERE/'sim.vvp')
    if '--mutants-only' not in sys.argv and '--resume' not in sys.argv:
        code,txt=sim(['+RESET_MID=1','+LIMIT=3'],HERE/'reset_mid.log')
        assert code==0 and 'RESET_MID PASS' in txt and 'PASS geom: golden=3/3' in txt
        print('passed reset during active arithmetic',flush=True)
    if '--mutants-only' not in sys.argv:
        # The two large scheduling cases start immediately while shorter shards run beside them.
        jobs=[(n-2,1),(n-1,1)]+[(i,min(100,n-2-i)) for i in range(0,n-2,100)]
        if '--resume' in sys.argv:
            # Completed logs are checked again before reuse, avoiding duplicate simulation.
            pass
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(shard,jobs))
        hits={i:sum(r['hits'][i] for r in results) for i in range(26)}
        assert all(hits.values()),hits
        assert sum(r['count'] for r in results)==n
        actor_max=max(r['actor'][1] for r in results)
        assert actor_max<=48
        result=dict(total=n,hits=hits,latency_min=min(r['latency'][0] for r in results),
                    latency_max=max(r['latency'][1] for r in results),actor_ii_max=actor_max,
                    actor_row_max=max(r['actor'][3] for r in results),shards=results)
        (HERE/'results.json').write_text(json.dumps(result,indent=2)+'\n')
        txt=''.join(f'ASSERT {i} hits={v}\n' for i,v in hits.items())
        txt+=f'LATENCY min={result["latency_min"]} max={result["latency_max"]}\n'
        txt+=f'MEASURED actor II max={actor_max}/48; row cycles max={result["actor_row_max"]}/1536\n'
        txt+='assertion failures: 0, assertions never exercised: 0\n'
        txt+=f'PASS geom: golden={n}/{n} assertions=26\n'
        (HERE/'simulation.log').write_text(txt);print(txt,flush=True)
        code,txt=sim(['+START=128','+LIMIT=34'],HERE/'stalled_edges.log')
        assert code==0 and 'PASS geom: golden=34/34' in txt
        print('passed all stalled edges',flush=True)
    if '--baseline-only' in sys.argv:return
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:mutants=list(pool.map(mutant,range(26)))
    (HERE/'mutants.json').write_text(json.dumps(mutants,indent=2)+'\n')
    print('PASS mutants: 26/26',flush=True)
if __name__=='__main__':main()
