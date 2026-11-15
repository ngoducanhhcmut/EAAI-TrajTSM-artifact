"""Supplemental preregistered directed port vectors. Run after rollout worker exits.

No model changes or fitting: expected decisions below are fixed before execution.
"""
import sys,json,hashlib,time
from pathlib import Path
from dataclasses import asdict,replace
HERE=Path(__file__).resolve().parent
VERIFY=HERE.parent/'verify'
sys.dont_write_bytecode=True
sys.path[:0]=[str(HERE.parent/'golden'),str(VERIFY)]
from tsmx_golden import model as g
from fractions import Fraction as F
import oracle

CASES={
    'rear':[(20,0,True),(20,1,True),(20,10,False),(6,0,True),(5,0,False),(5,1,False),
            (10,2,True),(10,3,False),(25,10,False),(40,10,True)],
    'selector_masks':[0,65535,1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,24,20,6,4608],
    'wrap_offsets':[0,1,19999,20000,39999,40000,99999,100000,499999,500000,500001],
    'interior_gaps':[498000,499000,500000,500001,501000,502000,502500,502501,503000,510000],
    'lane_offsets':[-800001,-800000,-799999,0,799999,800000,800001],
    'system_modes':['RECOVERY','RECOVERY','L0','L1','L1','L1','L2','L3','HOLD','L3'],
    'past_apply_delays':[-1,-2,-1000,-100000,-150000,-1000000],
    'ego_clock_offsets':[-150001,-150000,-1,0,1,150000],
    'lease_lengths':[20000,100001,120001,499999,500000,500001,1000000,10000000],
    'invalid_live_offsets':[-1,1,-100000],
    'corrupt_row_positions':[(1<<63)-1,(1<<63)-2,-(1<<63),-(1<<63)+1],
    'fractional_accel_actor_x':[-100000000,100000000],
}

def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')

def register():
    target=VERIFY/'edge_registration.json'
    reg=dict(utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),cases=CASES,
             source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
             reason='Static coverage review: rear, interior minimum, multi-candidate rank and serial expiry. No model/policy changes.',
             execution='after single rollout worker exits; supplemental to frozen V1/V2/V3, not a new statistical test')
    if target.exists():
        old=json.loads(target.read_text());assert old['cases']==json.loads(json.dumps(CASES)) and old['source_sha256']==reg['source_sha256']
    else:write(target,reg)

def run():
    register();results=[];ports=[]
    def add(block,name,passed,inp,out):
        results.append(dict(block=block,name=name,passed=bool(passed)))
        ports.append(dict(block=block,name=name,input=inp,output=out))
    tr=g.b4_mrmgen(0,0,0,0)
    for distance,speed,expected in CASES['rear']:
        obj=g.Motion(-distance*g.S,speed*g.S,0,4800000,0,0)
        result=g.b3_geom(tr,(obj,))
        exact=F(distance)-F(24,5)-F(speed)*F(tr.rows[-1][0],g.T)
        add('b3',f'rear_{distance}_{speed}',result.accept==expected and (not result.accept or exact>=F(1,2)),
            dict(traj=asdict(tr),objects=[asdict(obj)]),asdict(result))
    # Endpoints are clear at gap .501, but the interior minimum is .4985.
    v=100000;h=100000;xx,vv=g.advance(0,v,0,h)
    cell=g.Trajectory(True,((0,0,0,v,v,0,0),(h,xx,xx,vv,vv,0,0)),-1,'cell')
    for gap in CASES['interior_gaps']:
        obj=g.Motion(4800000+gap,0,2*g.S,4800000,h,2*g.S)
        result=g.b3_geom(cell,(obj,))
        exact=oracle.minimum(F(gap,g.S),F(0),F(2),F(1,10),F(0),F(1,10))
        # G1c (30/10): B3 is a sound division-free lower bound, not exact. Require
        # soundness (accept => exact >= .5 + 1 LSB) and bounded conservatism
        # (exact >= .5 + 1 LSB + (|aa|+|ab|)h^2/2 + 2 LSB => accept); here aa=2, ab=0.
        need=F(1,2)+F(1,g.S)
        slack=F(2,2)*F(1,10)**2+F(2,g.S)
        ok=(not result.accept or exact>=need) and (result.accept or exact<need+slack)
        add('b3',f'interior_{gap}',ok,dict(traj=asdict(cell),objects=[asdict(obj)]),asdict(result))
    for y in CASES['lane_offsets']:
        result=g.b3_geom(tr,(),y=y)
        add('b3',f'lane_{y}',result.accept==(abs(y)<=800000),dict(traj=asdict(tr),objects=[],y=y),asdict(result))
    for xbad in CASES['corrupt_row_positions']:
        broken=replace(tr,rows=tuple((row[0],xbad,xbad,*row[3:]) for row in tr.rows))
        result=g.b3_geom(broken,())
        add('b3',f'overflow_row_{xbad}',not result.accept,dict(traj=asdict(broken),objects=[]),asdict(result))
    for obj in (g.Motion(20*g.S,0,length=4.8),):
        result=g.b3_geom(tr,(obj,))
        add('b3','noninteger_extent',not result.accept,dict(traj=asdict(tr),objects=[asdict(obj)]),asdict(result))
    for ox in CASES['fractional_accel_actor_x']:
        obj=g.Motion(ox,20*g.S-3,1,4800000,0,1)
        result=g.b3_geom(tr,(obj,))
        horizon=F(tr.rows[-1][0],g.T)
        exact=(oracle.minimum(F(ox-4800000,g.S),F(obj.v,g.S),F(1,g.S),F(0),F(0),horizon)
               if ox>0 else oracle.minimum(F(-ox-4800000,g.S),F(0),F(0),F(obj.v,g.S),F(1,g.S),horizon))
        add('b3',f'fractional_accel_{ox}',result.accept and exact>=F(1,2),
            dict(traj=asdict(tr),objects=[asdict(obj)]),dict(**asdict(result),exact_min_gap=str(exact)))
    for mask in CASES['selector_masks']:
        rs=[g.GeomResult(bool(mask&(1<<i)),0,'fixture',1) for i in range(16)]
        chosen,label=g.b7_select(rs)
        # Independent rank by integer library coordinates: col3 is instant.
        admissible=[i for i in range(16) if mask&(1<<i) and i%4<3]
        expected=min(admissible) if admissible else 15
        add('b7',f'mask_{mask}',chosen==expected and (bool(admissible)==(label!='MITIGATION')),
            dict(results=[asdict(r) for r in rs]),dict(candidate=chosen,label=label))
    e=g.Ego(0xffff0000,0,g.S,0,30*g.S,0)
    p=g.Plan(123,e,e.t,(e.t+100000)&g.MASK,100000,g.S,0)
    c=g.certify(p,(e.t+500000)&g.MASK)
    for offset in CASES['wrap_offsets']:
        now=(e.t+offset)&g.MASK
        reason=g.b9_cert(p,c,now,True,e.t,True,p.seq)
        expected='expiry_at_executor' if offset>=500000 else 'committed' if offset>=100000 else 'pending'
        add('b9',f'wrap_{offset}',reason==expected,dict(plan=asdict(p),cert=asdict(c),now=now,issued=e.t,ack=True,expected_seq=p.seq),dict(reason=reason))
    for value in (g.MASK-1,g.MASK):
        st=g.Recorder(events=((0,'old'),),lost=value,capacity=1)
        out=g.b10_rec(st,(1,'new'))
        add('b10',f'saturate_{value}',out.lost==g.MASK and out.events==((1,'new'),),dict(state=asdict(st),event=[1,'new']),asdict(out))
    known=g.zlib.crc32(b'123456789')
    add('b1','ieee_crc32_known',known==0xcbf43926,dict(bytes_hex=b'123456789'.hex()),dict(crc=known))
    for origin in (0,1000000,0xfffffff0):
        ee=g.Ego(origin,0,g.S,0,30*g.S,0)
        for delay in CASES['past_apply_delays']:
            pp=g.Plan(1,ee,origin,(origin+delay)&g.MASK,0,g.S,0)
            accepted=g.b2_splice(ee,pp)
            add('b2',f'past_apply_{origin}_{delay}',not accepted,dict(ego=asdict(ee),plan=asdict(pp)),dict(accept=accepted))
    base=g.Ego(1000000,0,g.S,0,30*g.S,0)
    pp=g.Plan(1,base,base.t,base.t+100000,100000,g.S,0)
    for offset in CASES['ego_clock_offsets']:
        measured=replace(base,t=base.t+offset)
        _,why=g.b1_ingress(g.Ingress(),base.t,measured,g.packet(pp))
        valid=-150000<=offset<=0
        add('b1',f'ego_time_{offset}',(why=='ok')==valid,dict(now=base.t,ego=asdict(measured),pkt=asdict(g.packet(pp))),dict(reason=why))
    for length in CASES['lease_lengths']:
        cert=g.certify(pp,base.t+length)
        why=g.b9_cert(pp,cert,base.t)
        valid=120000<length<=500000
        add('b9',f'lease_{length}',(why=='ok')==valid,dict(plan=asdict(pp),cert=asdict(cert),now=base.t),dict(reason=why))
    late=replace(pp,apply=base.t-1,x=base.x)
    cert=g.certify(late,base.t+500000)
    why=g.b9_cert(late,cert,base.t)
    add('b9','new_packet_late',why=='late_apply',dict(plan=asdict(late),cert=asdict(cert),now=base.t),dict(reason=why))
    for offset in CASES['invalid_live_offsets']:
        measured=replace(base,t=base.t+offset)
        before=g.Supervisor(mode='L0',good=3)
        after,outputs=g.tsmx_cycle(before,dict(now=base.t,ego=measured,pkt=None))
        add('system',f'live_epoch_{offset}',outputs['mode']=='L3' and outputs['candidate']==15 and not after.backup,
            dict(state=asdict(before),inputs=dict(now=base.t,ego=asdict(measured),pkt=None)),dict(state=asdict(after),outputs=outputs))
    before=g.Supervisor(mode='L0',good=3,ingress=g.Ingress(last_time=base.t+1))
    after,outputs=g.tsmx_cycle(before,dict(now=base.t,ego=base,pkt=None))
    add('system','live_clock_rollback',outputs['reason']=='clock_reset' and outputs['mode']=='L3',
        dict(state=asdict(before),inputs=dict(now=base.t,ego=asdict(base),pkt=None)),dict(state=asdict(after),outputs=outputs))
    state=g.Supervisor()
    for i,expected in enumerate(CASES['system_modes']):
        now=i*g.DT
        ego=g.Ego(now,4200000 if i==8 else i*600000,0 if i==8 else 6*g.S,0,100*g.S,0)
        pp=g.Plan(i,ego,now,now+g.DT,ego.x+600000,ego.v,0)
        cc=g.certify(pp,now+500000)
        inp=dict(now=now,ego=ego,pkt=g.packet(pp) if i<3 else None,cert=cc if i<3 else None,
                 ack=True,reset=i==7,health_inputs=dict(fsm_onehot=3) if i==9 else {})
        before=asdict(state)
        state,outputs=g.tsmx_cycle(state,inp)
        ports_in=dict(state=before,inputs={k:asdict(v) if hasattr(v,'__dataclass_fields__') else v for k,v in inp.items()})
        add('system',f'arbitration_{i}',outputs['mode']==expected,ports_in,dict(state=asdict(state),outputs=outputs))
    result=dict(passed=all(r['passed'] for r in results),n=len(results),cases=results,
                source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    write(VERIFY/'edge_results.json',result)
    (HERE/'edges.ports.jsonl').write_text('\n'.join(json.dumps(p,sort_keys=True,separators=(',',':')) for p in ports)+'\n',encoding='utf-8')
    print('EDGE',result['passed'],len(results),[r for r in results if not r['passed']],flush=True)

if __name__=='__main__':
    if '--register' in sys.argv:register()
    else:run()
