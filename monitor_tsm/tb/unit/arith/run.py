"""Reproduce Icarus simulation and assertion/source mutation evidence.

Run py -3.13 -B run.py [--mutants-only]. Verilator command is recorded in README.md.
"""
from pathlib import Path
import concurrent.futures,subprocess,sys,json,time,re
HERE=Path(__file__).resolve().parent
RTL=HERE.parents[2]/'rtl/arith'
IV='iverilog';VVP='vvp'

def compile_to(out,main=None,div=None):
    cmd=[IV,'-g2012','-s','tb_m_tsmx_arith','-I',str(HERE),'-o',str(out),
         str(div or RTL/'m_tsmx_arith_div.sv'),str(main or RTL/'m_tsmx_arith.sv'),str(HERE/'tb_m_tsmx_arith.sv')]
    r=subprocess.run(cmd,cwd=HERE,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    out.with_suffix('.compile.log').write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\n'+r.stdout+f'\nEXIT {r.returncode}\n')
    if r.returncode:raise RuntimeError(str(out))

def simulate(out,args,log):
    cmd=[VVP,str(out),*args]
    with log.open('w') as f:
        f.write('COMMAND '+subprocess.list2cmdline(cmd)+'\n');f.flush()
        r=subprocess.run(cmd,cwd=HERE,text=True,stdout=f,stderr=subprocess.STDOUT,timeout=3600)
        f.write(f'\nEXIT {r.returncode}\n')
    return r.returncode,log.read_text()

def mutant(i):
    log=HERE/'mutants'/f'M{i:02}.log'
    code,txt=simulate(HERE/'sim.vvp',[f'+MUTANT={i}','+LIMIT=1500'],log)
    assert code!=0 and f'ASSERT_FAIL {i} ' in txt,(i,txt[-1500:])
    return dict(id=i,killed=True,log=str(log.relative_to(HERE)))

SOURCE_MUTANTS=(
 ('rounding','div','reg_neg[LPARA_STAGES] != reg_up[LPARA_STAGES]','reg_neg[LPARA_STAGES] == reg_up[LPARA_STAGES]'),
 ('stop_clip','main','if (w_a[159] && (96\'(w_h)','if (1\'b0 && (96\'(w_h)'),
 ('stationary','main',"w_pt_valid[idx]=(w_td!='0)","w_pt_valid[idx]=1'b0 && (w_td!='0)"),
 ('jerk_integral','main','+w_j*(w_hd*w_hd*w_hd-w_tail*w_tail*w_tail)','-w_j*(w_hd*w_hd*w_hd-w_tail*w_tail*w_tail)'),
 ('numeric_sentinel','main','f_abs(w_a) < w_limit','f_abs(w_a) <= w_limit'),
 ('stall','main','ENUM_ST_RESP: if (i_rsp_ready)','ENUM_ST_RESP: if (1\'b1)'),
)
def source_mutant(item):
    name,target,old,new=item;path=HERE/'source_mutants'/f'{name}.sv'
    original=(RTL/('m_tsmx_arith_div.sv' if target=='div' else 'm_tsmx_arith.sv')).read_text()
    assert original.count(old)==1,(name,original.count(old))
    path.write_text(original.replace(old,new))
    out=path.with_suffix('.vvp');compile_to(out,main=path if target=='main' else None,div=path if target=='div' else None)
    code,txt=simulate(out,['+LIMIT=4000'],path.with_suffix('.log'))
    assert code!=0 and ('ASSERT_FAIL' in txt or 'bounded progress' in txt),(name,txt[-1500:])
    return dict(name=name,killed=True,log=str(path.with_suffix('.log').relative_to(HERE)))

def baseline_shard(item):
    start,count=item
    code,txt=simulate(HERE/'sim.vvp',[f'+START={start}',f'+LIMIT={count}'],HERE/'shards'/f'S{start:06}.log')
    assert code==0 and f'PASS arith: golden={count}/{count}' in txt,txt[-3000:]
    hits={int(i):int(n) for i,n in re.findall(r'ASSERT (\d+) .* hits=(\d+)',txt)}
    latency={int(op):(int(lo),int(hi)) for op,lo,hi in re.findall(r'LATENCY op=(\d+) min=(\d+) max=(\d+)',txt)}
    return dict(start=start,count=count,hits=hits,latency=latency)

def baseline():
    compile_to(HERE/'sim.vvp')
    n=json.loads((HERE/'vectors.json').read_text())['total']
    (HERE/'shards').mkdir(exist_ok=True)
    items=[(start,min(4096,n-start)) for start in range(0,n,4096)]
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for result in pool.map(baseline_shard,items):
            results.append(result)
            print('golden shard passed',result['start'],result['count'],flush=True)
    hits={i:sum(r['hits'][i] for r in results) for i in range(26)}
    assert all(hits.values()),hits
    latency={i:(min(r['latency'][i][0] for r in results),max(r['latency'][i][1] for r in results)) for i in range(9)}
    assert sum(r['count'] for r in results)==n
    log='COMMAND py -3.13 -B run.py (8 independent Icarus shards, exhaustive disjoint ranges)\n'
    log+=''.join(f'ASSERT {i} hits={v}\n' for i,v in hits.items())
    log+=''.join(f'LATENCY op={i} min={lo} max={hi}\n' for i,(lo,hi) in latency.items())
    log+='assertion failures: 0, assertions never exercised: 0\n'
    log+=f'PASS arith: golden={n}/{n} assertions=26 shards={len(results)}\nEXIT 0\n'
    (HERE/'simulation.log').write_text(log)
    (HERE/'results.json').write_text(json.dumps(dict(total=n,hits=hits,latency=latency,shards=results),indent=2)+'\n')
    print(log,flush=True)

def main():
    t=time.monotonic()
    if '--mutants-only' not in sys.argv:
        baseline()
    if '--baseline-only' in sys.argv:return
    for name in ('mutants','source_mutants'):(HERE/name).mkdir(exist_ok=True)
    assertions=[];source=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(mutant,range(26)):
            assertions.append(result);print('assertion mutant killed',result['id'],flush=True)
        for result in pool.map(source_mutant,SOURCE_MUTANTS):
            source.append(result);print('source mutant killed',result['name'],flush=True)
    (HERE/'mutants.json').write_text(json.dumps(dict(assertions=assertions,source=source,elapsed_seconds=time.monotonic()-t),indent=2)+'\n')
    print(f'MUTANTS PASS: assertions={len(assertions)}/26 source={len(source)}/{len(SOURCE_MUTANTS)}',flush=True)

if __name__=='__main__':main()
