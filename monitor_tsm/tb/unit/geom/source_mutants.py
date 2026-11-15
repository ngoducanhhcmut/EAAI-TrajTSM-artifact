"""Real source-defect tests on owned temporary copies; delivered RTL remains unchanged."""
from pathlib import Path
import json,concurrent.futures
from run import HERE,RTL,compile_to,sim
OUT=HERE/'source_mutants'
OUT.mkdir(exist_ok=True)
jobs=[int(x,16) for x in (HERE/'jobs.mem').read_text().splitlines()]
rows=[int(x,16) for x in (HERE/'rows.mem').read_text().splitlines()]
endpoint=next(i for i,j in enumerate(jobs) if (j&255)==2 and ((j>>48)&255)==4
              and ((rows[((j>>8)&0xffffffff)+1]>>1)&0xffffffff)==8000001)
TESTS=[
    ('stationary','m_tsmx_geom_swept.sv',"w_point=w_td!=64'd0","w_point=1'b0 && w_td!=64'd0",138,10),
    ('inflate','m_tsmx_geom.sv',"w_inflate_nxt=64'(w_iq_0+w_iq_1);","w_inflate_nxt=64'd0;",0,1),
    ('endpoint_numeric','m_tsmx_geom.sv',"w_r[31:0] <= 32'd8000000","1'b1",endpoint,1),
]
def test(item):
    name,file,old,new,start,n=item
    s=(RTL/'geom'/file).read_text();assert s.count(old)==1
    path=OUT/f'{name}.sv';path.write_text(s.replace(old,new));exe=OUT/f'{name}.vvp'
    compile_to(exe,main=path if file=='m_tsmx_geom.sv' else None,
               swept=path if file=='m_tsmx_geom_swept.sv' else None)
    code,txt=sim([f'+START={start}',f'+LIMIT={n}'],OUT/f'{name}.log',exe)
    assert code!=0 and 'ASSERT_FAIL 15 ' in txt,(name,txt[-1800:])
    print('source mutant killed',name,flush=True)
    return dict(name=name,killed=True,start=start,count=n)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(test,TESTS))
(HERE/'source_mutants.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS source mutants: 3/3')
