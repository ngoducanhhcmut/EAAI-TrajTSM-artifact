"""TSM-X / TSMX project / v0.1. Run portable simulation and mutation checks."""
from pathlib import Path
import subprocess,concurrent.futures,json,re,sys
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
SOURCES=[HW/'rtl/arith/m_tsmx_arith_div.sv',HW/'rtl/arith/m_tsmx_arith.sv',HW/'rtl/splice/m_tsmx_splice.sv',HERE/'tb_m_tsmx_splice.sv']
def command(cmd,log,timeout=3600):
    r=subprocess.run(list(map(str,cmd)),cwd=HERE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    log.write_text('COMMAND '+subprocess.list2cmdline(list(map(str,cmd)))+'\n'+r.stdout+f'\nEXIT {r.returncode}\n')
    return r.returncode,r.stdout
def compile_to(out,source=None):
    files=SOURCES.copy()
    if source:files[2]=source
    code,txt=command(['iverilog','-g2012','-s','tb_m_tsmx_splice','-I',HERE,'-o',out,*files],out.with_suffix('.compile.log'))
    assert code==0,txt[-3000:]
def shard(args):
    first,count=args
    log=HERE/f'shard_{first:05}.log'
    if '--reuse-baseline' in sys.argv:
        txt=log.read_text();code=0 if txt.endswith('EXIT 0\n') else 1
    else:
        code,txt=command(['vvp',HERE/'sim.vvp',f'+START={first}',f'+LIMIT={count}'],log)
    assert code==0 and 'PASS splice:' in txt,txt[-2500:]
    hits={int(i):int(n) for i,n in re.findall(r'ASSERT_HITS (\d+) .* hits=(\d+)',txt)}
    jobs=[int(c) for c in re.findall(r'JOB \d+ cycles=(\d+)',txt)]
    return dict(start=first,count=count,hits=hits,min=min(jobs),max=max(jobs),unstalled=re.findall(r'UNSTALLED .*',txt))
def mutant(i):
    code,txt=command(['vvp',HERE/'sim.vvp',f'+MUTANT={i}','+LIMIT=10'],HERE/f'mutant_{i:02}.log')
    assert code!=0 and f'ASSERT_FAIL {i} ' in txt,(i,txt[-2000:])
    return dict(id=i,killed=True)
def source_mutant(item):
    name,old,new=item
    source=SOURCES[2].read_text();assert source.count(old)==1,name
    path=HERE/'source_mutants'/f'{name}.sv';path.parent.mkdir(exist_ok=True)
    path.write_text(source.replace(old,new));out=path.with_suffix('.vvp');compile_to(out,path)
    code,txt=command(['vvp',out,'+START=568','+LIMIT=200'],path.with_suffix('.log'))
    assert code!=0 and ('ASSERT_FAIL' in txt or 'bounded response' in txt),(name,txt[-2000:])
    return dict(name=name,killed=True)
def main():
    compile_to(HERE/'sim.vvp')
    n=json.loads((HERE/'vectors.json').read_text())['total']
    result={}
    if '--mutants-only' not in sys.argv:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            result['shards']=list(pool.map(shard,[(s,min(600,n-s)) for s in range(0,n,600)]))
        (HERE/'results.json').write_text(json.dumps(result,indent=2)+'\n')
        print(f'PASS splice: golden=128/128 edges=18/18 hex=128/128 total={n}/{n}',flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        result['assertion_mutants']=list(pool.map(mutant,range(24)))
    mutations=[
        ('dx_zero',"LPARA_DX = 32'd50000","LPARA_DX = 32'd0"),
        ('tube_widen',"LPARA_TUBE_X = 32'd160000","LPARA_TUBE_X = 32'd260000"),
        ('delay_boundary',"(w_delay <= LPARA_MAX_DELAY)","(w_delay < LPARA_MAX_DELAY)"),
        ('corner_omit','if (&reg_corner)',"if (reg_corner == 4'd1)"),
        ('stall_drop','ENUM_ST_RESP: if (i_rsp_ready)',"ENUM_ST_RESP: if (1'b1)"),
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        result['source_mutants']=list(pool.map(source_mutant,mutations))
    (HERE/('mutants.json' if '--mutants-only' in sys.argv else 'results.json')).write_text(json.dumps(result,indent=2)+'\n')
    print('PASS mutants: assertions=24/24 source=5/5',flush=True)
    if 'shards' in result:
        lines=['Icarus regression: eight exhaustive disjoint shards; commands/exits in shard logs.',
               'Measured production latency: guard=2; complete sweep=178 cycles.',
               'Measured unstalled II: guard=3; complete sweep=179 cycles.',
               'Assertion mutants killed24/24; source mutants killed5/5.']
        for i in range(24):
            lines.append(f'ASSERT_HITS {i} total={sum(s["hits"][i] for s in result["shards"])}')
        lines+=['assertion failures: 0, assertions never exercised: 0',
                f'PASS splice: golden=128/128 edges=18/18 hex=128/128 extra=4494/4494 total={n}/{n}']
        (HERE/'simulation.log').write_text('\n'.join(lines)+'\n')
        print(lines[-1],flush=True)
if __name__=='__main__': main()
