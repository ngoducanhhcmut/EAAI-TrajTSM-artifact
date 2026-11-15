"""Existing verify/unit.py freshness and freeze witnesses, golden only."""
import json
from dataclasses import replace, asdict
import packetizer_v2 as pk
g=pk.g

def run():
    e=g.Ego(1000000,0,6*g.S,0,40*g.S,0);out={}
    for encoding in ('E0','E1','E2'):
        pk.ENCODING=encoding
        q=pk.encode_state([3,6,9,12],e,0)
        p=g.Plan(1,e,e.t,e.t+pk.APPLY,*map(pk.fixed,q),compute=5000)
        packet=g.packet(p)
        encoder=pk.TransactionEncoder(encoding)
        first=encoder.encode(1,e.t,e,[3,6,9,12],0)
        retry=encoder.encode(1,e.t,replace(e,t=e.t+100000,x=e.x+g.S),[3,6,9,12],1)
        assert first is retry and g.packet(first)==g.packet(retry)
        cases={
            'fresh':(g.Ingress(),e.t,e,packet,'ok'),
            'stale_150001us':(g.Ingress(),e.t,e,g.packet(replace(p,snapshot=replace(e,t=e.t-150001))),'freshness'),
            'motion_freeze':(g.Ingress(signature=(p.x,p.v,p.a,p.tail),freeze_x=-g.S),e.t,e,packet,'freeze'),
            'no_sample_freeze':(g.Ingress(last_sample=0),400000,e,None,'freeze_no_sample'),
            'retry_same_transaction':(g.Ingress(seq=p.seq),e.t,e,packet,'sequence')}
        result={}
        for name,(state,now,ego,pkt,expected) in cases.items():
            actual=g.b1_ingress(state,now,ego,pkt)[1]
            assert actual==expected,(encoding,name,actual)
            result[name]=dict(expected=expected,actual=actual,pass_=True,state=asdict(state),now=now,ego=asdict(ego),packet=asdict(pkt) if pkt else None)
        out[encoding]=result
    # Known exact quadratic: equal LS weights recover all coefficients.
    t=pk._times; q=pk.smooth(4*t-.75*t*t)
    assert max(abs(x-y) for x,y in zip(q,(.3925,3.85,-1.5)))<1e-12
    e=replace(e,v=0,a=-g.S);pk.ENCODING='E2'
    q=pk.encode_state([100,200,300,400],e,0)
    assert q[0]==0 and q[1]==0 and -8<=q[2]<=2
    return dict(encodings=out,exact_LS_quadratic=True,E2_stop_clipped=True,transaction_retry_packet_unchanged=True,
                limitation='Freshly reanchoring frozen waypoints changes the signature; firmware must preserve planner transaction ownership. These witnesses do not prove semantic planner liveness.')

if __name__=='__main__':
    (pk.HERE/'witnesses.json').write_text(json.dumps(run(),indent=2))
    print('PASS existing stale/frozen witnesses for E0/E1/E2 and encoding analytic checks')
