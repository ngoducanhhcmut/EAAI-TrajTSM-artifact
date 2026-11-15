"""Measure no-stall service/II on all80 directed cases, independently of stall regression."""
import concurrent.futures,json,re
from run import HERE,compile,sim

def measure(start):
    code,txt=sim(HERE/'measure.vvp',[f'+START={start}','+LIMIT=5','+NOSTALL=1'],HERE/'measure'/f'D{start}.log')
    assert code==0,txt[-2000:]
    lat=list(map(int,re.search(r'LATENCY min=(\d+) max=(\d+) II min=(\d+) max=(\d+) row_gap_max=(\d+)',txt).groups()))
    return dict(start=start,latency_min=lat[0],latency_max=lat[1],ii_min=lat[2],ii_max=lat[3],row_gap_max=lat[4])
def main():
    compile(HERE/'measure.vvp');(HERE/'measure').mkdir(exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:data=list(pool.map(measure,range(256,336,5)))
    result=dict(cases=80,latency_min=min(x['latency_min'] for x in data),latency_max=max(x['latency_max'] for x in data),ii_min=min(x['ii_min'] for x in data),ii_max=max(x['ii_max'] for x in data),row_gap_max=max(x['row_gap_max'] for x in data),groups=data)
    (HERE/'measure.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
