"""Analytic interface checks plus golden regeneration of both physical corpora."""
import json,hashlib
from dataclasses import replace
from packetizer import *
def restore(d):
    d=d.copy();d['ego']=g.Ego(**d['ego'])
    if d.get('pkt'):
        p=d['pkt'];pd=p['plan'];pd['snapshot']=g.Ego(**pd['snapshot'])
        d['pkt']=g.Packet(g.Plan(**pd),p['crc'],tuple(p['snapshot_ids']),p['schema'])
    if d.get('cert'):d['cert']=g.Certificate(**d['cert'])
    d['objects']=tuple(g.Motion(**o) for o in d['objects'])
    return d
def main():
    # Constant acceleration: x(t)=2t-.25t^2, independent analytic states.
    q=quadratic(.9375,1.75)
    assert np.allclose(q,(.1975,1.95,-.5),rtol=0,atol=1e-14)
    snap=g.Ego(0,0,2000000,-500000,50000000,0)
    live=replace(snap,t=80000,x=158400,v=1960000)
    d,_=make_packet(1,0,live,snap,.9375,1.75,0,[])
    assert d['pkt'].plan.apply==100000 and d['pkt'].plan.generated==0
    assert g.b1_ingress(g.Ingress(),80000,live,d['pkt'])[1]=='ok'
    assert g.b2_splice(live,d['pkt'].plan)
    checks={}
    for name in ('cosim_0103','replay_rtl_subset'):
        m=json.loads((HERE/(name+'.json')).read_text())
        lines=(HERE/(name+'.mem')).read_text().splitlines();assert len(lines)==m['jobs']
        state=g.Supervisor();commits=0;accepts=0
        for line,row in zip(lines,m['jobs_meta']):
            if row['reset']:state=g.Supervisor()
            d=restore(row['input']);state,o,expected=job(state,d,row['reset'])
            assert line==expected.strip()
            assert len(line)==12010 and int(line,16).bit_length()<=48037
            assert o==row['response']
            commits+=o['commit']=='committed';accepts+=o['accept']
            if row['kind']=='admission':
                p=d['pkt'].plan
                assert p.generated+100000==p.apply and d['now']==p.generated+80000
                assert p.snapshot.t==p.generated
        checks[name]=dict(jobs=len(lines),accepted=accepts,committed=commits,all_bits_regenerated_exactly=True)
    checks['analytic_quadratic_and_b1_b2']=True
    (HERE/'checks.json').write_text(json.dumps(checks,indent=2))
    print(checks)
if __name__=='__main__':main()
