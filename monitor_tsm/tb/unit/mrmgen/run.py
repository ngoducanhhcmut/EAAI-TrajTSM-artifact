"""Compile and run disjoint Icarus shards; reproduce sampled-output and source mutants."""
from pathlib import Path
import subprocess,sys,json,concurrent.futures,re,time
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
RTL=HW/'rtl/mrmgen/m_tsmx_mrmgen.sv'
def compile(out,rtl=RTL):
    cmd=['iverilog','-g2012','-s','tb_m_tsmx_mrmgen','-I',str(HERE),'-o',str(out),str(HW/'rtl/arith/m_tsmx_arith_div.sv'),str(HW/'rtl/arith/m_tsmx_arith.sv'),str(rtl),str(HERE/'tb_m_tsmx_mrmgen.sv')]
    p=subprocess.run(cmd,cwd=HERE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    out.with_suffix('.compile.log').write_text('COMMAND '+subprocess.list2cmdline(cmd)+'\n'+p.stdout+'\nEXIT '+str(p.returncode)+'\n')
    assert p.returncode==0

def sim(out,args,log):
    cmd=['vvp',str(out),*args]
    with log.open('w') as f:
        f.write('COMMAND '+subprocess.list2cmdline(cmd)+'\n');f.flush()
        p=subprocess.run(cmd,cwd=HERE,stdout=f,stderr=subprocess.STDOUT,timeout=3600)
        f.write('\nEXIT '+str(p.returncode)+'\n')
    return p.returncode,log.read_text()

def shard(item):
    start,count=item
    code,txt=sim(HERE/'sim.vvp',[f'+START={start}',f'+LIMIT={count}'],HERE/'shards'/f'S{start:04}.log')
    assert code==0 and f'golden={count}/{count}' in txt,txt[-2500:]
    hits={int(i):int(n) for i,n in re.findall(r'ASSERT (\d+) .* hits=(\d+)',txt)}
    lat=list(map(int,re.search(r'LATENCY min=(\d+) max=(\d+) II min=(\d+) max=(\d+) row_gap_max=(\d+)',txt).groups()))
    rows=int(re.search(r'PASS mrmgen: .* rows=(\d+)',txt).group(1))
    return dict(start=start,count=count,hits=hits,latency=lat,rows=rows)

def output_mutant(i):
    code,txt=sim(HERE/'sim.vvp',[f'+MUTANT={i}','+LIMIT=2'],HERE/'mutants'/f'M{i:02}.log')
    assert code!=0 and f'ASSERT_FAIL {i} ' in txt,(i,txt[-1500:])
    return dict(id=i,killed=True)

SOURCE=[('jerk_sign',"w_jerk_nxt=w_signed;","w_jerk_nxt='0;"),('instant',"if(w_j==32'd0) w_start_nxt=w_ar_resp[511:480];","if(w_j==32'd0) w_start_nxt=reg_a;"),('stall','ENUM_ST_ROW: if(i_row_ready)','ENUM_ST_ROW: if(1\'b1)'),('range',"&& reg_req[111:80]<=32'd10000000","&& reg_req[111:80]<=32'd10000001")]
def source_mutant(item):
    name,old,new=item;src=RTL.read_text();assert src.count(old)==1
    path=HERE/'source_mutants'/f'{name}.sv';path.write_text(src.replace(old,new));out=path.with_suffix('.vvp');compile(out,path)
    start={'instant':271,'range':336}.get(name,0)
    code,txt=sim(out,[f'+START={start}','+LIMIT=45'],path.with_suffix('.log'))
    assert code!=0 and ('ASSERT_FAIL' in txt or '$fatal' in txt or 'FATAL' in txt),(name,txt[-2000:])
    return dict(name=name,killed=True)

def main():
    t=time.monotonic();compile(HERE/'sim.vvp')
    for folder in ('shards','mutants','source_mutants'):(HERE/folder).mkdir(exist_ok=True)
    if '--mutants-only' in sys.argv:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            mutants=list(pool.map(output_mutant,range(32)))
            source=list(pool.map(source_mutant,SOURCE))
        data=dict(assertions=mutants,source=source)
        (HERE/'mutants.json').write_text(json.dumps(data,indent=2)+'\n');print('MUTANTS PASS 32/32 source 4/4',flush=True);return
    n=json.loads((HERE/'vectors.json').read_text())['total'];results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for result in pool.map(shard,[(s,min(80,n-s)) for s in range(0,n,80)]):
            results.append(result);print('PASS shard',result['start'],result['count'],flush=True)
    hits={i:sum(r['hits'][i] for r in results) for i in range(32)}
    data=dict(total=n,rows=sum(r['rows'] for r in results),hits=hits,latency_min=min(r['latency'][0] for r in results),latency_max=max(r['latency'][1] for r in results),ii_min=min(r['latency'][2] for r in results),ii_max=max(r['latency'][3] for r in results),row_gap_max=max(r['latency'][4] for r in results),shards=results,seconds=time.monotonic()-t)
    assert all(hits.values())
    (HERE/'results.json').write_text(json.dumps(data,indent=2)+'\n')
    log=''.join(f'ASSERT {i} hits={v}\n' for i,v in hits.items())
    log+=f'Latency {data["latency_min"]}..{data["latency_max"]}; II {data["ii_min"]}..{data["ii_max"]}; max row gap {data["row_gap_max"]}\n'
    log+='assertion failures: 0, assertions never exercised: 0\n'
    log+=f'PASS mrmgen: golden={n}/{n} rows={data["rows"]} assertions=32\n'
    (HERE/'simulation.log').write_text(log);print(log,flush=True)
if __name__=='__main__':main()
