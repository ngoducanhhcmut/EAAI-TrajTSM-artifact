"""Exercise classification precedence, unknowns and exact interval endpoints."""
import copy,json
from classify import cp,classify,parse
from gen_faults import HERE,ROOT,dump,sha

def main():
    checks=[]
    workload=json.loads((HERE/'workload.json').read_text())
    for job in workload:
        source=ROOT/job['source']
        assert sha(source)==job['source_sha256']
        assert (HERE/job['file']).read_text().strip()==source.read_text().splitlines()[job['row']]
    inventory=json.loads((HERE/'inventory.json').read_text())
    registers={r['path']:r for r in inventory['registers']}
    samples=json.loads((HERE/'faults.json').read_text())
    for i,f in enumerate(samples):
        r=registers[f['path']]
        assert f['id']==i and f['unit']==r['unit'] and 0<=f['bit']<r['width']
    assert all(sum(f['unit']==u for f in samples)==120 for u in inventory['population'])
    for n in [1,2,24,1440]:
        a,b=cp(0,n),cp(n,n)
        assert abs(a[1]-(1-.025**(1/n)))<1e-12
        assert abs(b[0]-.025**(1/n))<1e-12
        checks.append(dict(n=n,zero=a,all=b))
    base=dict(injected=1,probe=1,hang=0,deadline=0,frames=1,event=1,framing=0,fallback=0,
              pairs={k:[0,0] for k in ['RSP','CMD','EVENT','ING','SUP','LOST','REASON','STATUS']})
    # Authority modes >=2 represent a nonauthoritative command.
    base['pairs']['CMD']=[2<<1894,2<<1894]
    assert classify(base,base)=='MASKED'
    unsafe=copy.deepcopy(base);unsafe['pairs']['RSP'][0]=1<<37;unsafe['pairs']['SUP'][0]=4
    assert classify(unsafe,base)=='SDC-UNSAFE' # fault flag must not hide false ACCEPT
    accepted=copy.deepcopy(base);accepted['pairs']['RSP']=[1<<37,1<<37]
    accepted['pairs']['CMD']=[1<<1218,1<<1218]
    altered=copy.deepcopy(accepted);altered['pairs']['CMD'][0]^=1<<500
    assert classify(altered,accepted)=='SDC-UNSAFE'
    reject=copy.deepcopy(accepted);reject['pairs']['RSP'][0]=0;reject['pairs']['CMD'][0]=2<<1894
    assert classify(reject,accepted)=='DETECTED'
    safe=copy.deepcopy(base);safe['pairs']['EVENT'][0]=1
    assert classify(safe,base)=='SDC-SAFE'
    hang=copy.deepcopy(base);hang['hang']=1
    assert classify(hang,base)=='HANG'
    hang['deadline']=1
    assert classify(hang,base)=='DETECTED'
    missing=copy.deepcopy(base);missing['probe']=0
    assert classify(missing,base)=='UNRESOLVED'
    assert classify(parse('RESULT hang=0\nRSP xx 00'))=='UNRESOLVED'
    dump('tool_checks.json',dict(status='PASS',workload_copies_verified=len(workload),fault_addresses_verified=len(samples),interval_endpoints=checks,
         cases=['masked','unsafe despite detection','different accepted certificate','safe reject','safe difference','uncontained hang','contained timeout','missing probe','unknown observation']))
    print('PASS classification and exact interval checks')

if __name__=='__main__':main()
