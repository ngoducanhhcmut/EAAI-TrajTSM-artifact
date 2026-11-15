"""TSM-X / TSMX project / 0.1. Spec 10.1/15 oracle, unmodified golden.

Seed 0x1A20261029. Every expected bit comes from tsmx_cycle or the documented
spec5.5.13 command projection. No RTL is consulted by this generator.
"""
import argparse
import hashlib
import json
import random
import sys
from dataclasses import asdict, replace
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path[:0]=[str(ROOT/'golden'),str(ROOT.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g
import vectors as fixture_driver

def record(b,w): return g._nested(b,w)[0]
def cat(fields):
    v=0
    for x,w in fields:v=(v<<w)|(int(x)&((1<<w)-1))
    return v
def plan(d):return g.Plan(**{**d,'snapshot':g.Ego(**d['snapshot'])})
def state(d):
    d=d.copy();d['ingress']=g.Ingress(**{**d['ingress'],'signature':tuple(d['ingress']['signature'])})
    d['events']=tuple(tuple(e) for e in d['events'])
    d['pending']=(d['pending'][0],plan(d['pending'][1]),g.Certificate(**d['pending'][2])) if d['pending'] else ()
    d['backup']=(plan(d['backup'][0]),g.Certificate(**d['backup'][1])) if d['backup'] else ()
    return g.Supervisor(**d)
def inputs(d):
    d=d.copy();d['ego']=g.Ego(**d['ego'])
    if d.get('cert'): d['cert']=g.Certificate(**d['cert'])
    if d.get('pkt'):
        p=d['pkt'];d['pkt']=g.Packet(plan(p['plan']),p['crc'],tuple(p['snapshot_ids']),p['schema'])
    if 'objects'in d:d['objects']=tuple(g.Motion(**x) for x in d['objects'])
    if 'lane'in d:d['lane']=tuple(d['lane'])
    return d
def health(d):
    words=d.get('words',());par=d.get('parities',())
    return cat([(1,1),(len(words),11),(len(par),11)]+
               [(w,32) for w in words]+[(0,32)]*(1024-len(words))+
               [(p,1) for p in par]+[(0,1)]*(1024-len(par))+
               [(d.get('lane_pair',(True,True))[0],1),(d.get('lane_pair',(True,True))[1],1),
                (d.get('fsm_onehot',1),6),(d.get('bist',True),1)])
def request(d):
    return cat([(d['now'],32),(record(g.pack_ego(d['ego']),256),256),
        (record(g.pack_packet(d.get('pkt')),721),721),
        (record(g.pack_certificate(d.get('cert')),1217),1217),
        (record(g.pack_world(d.get('objects',())),8200),8200),
        (record(g.pack_lane(d.get('lane',(-1800000,1800000))),384),384)]+
        [(x,1) for x in ('objects'in d,'lane'in d,d.get('lead')=='braking',d.get('capability',True),
                         d.get('health',True),d.get('reset',False),d.get('ack',False))]+
        [(d.get('rear_ftti',1<<30),32),(health(d.get('health_inputs',{})),33824)])
def command(s,o,d):
    p=c=None;mode=s.mode;cid=o['candidate'];label=1 if o['label']=='CERT-FRONT/REAR-COND' else 2
    if mode in ('L0','RECOVERY') and s.pending:
        src=0;p,c=s.pending[1:]
    elif mode=='L1' and s.backup:src=1;p,c=s.backup
    elif mode=='L2' and cid in range(16) and g.LIBRARY[cid][1] and label==1:src=2
    elif mode=='HOLD':src=4
    else:src=3
    if src==3:mode='L3'
    cid=p.tail if p else cid if src==2 else 15
    label=1 if src in (0,1,2) else 2
    if p is None:p=g.Plan(0,d['ego'],d['now'],d['now'],d['ego'].x,d['ego'].v,d['ego'].a,tail=cid,compute=0,count=0)
    return record(g.pack_command(dict(source=src,mode=mode,label=label,candidate=cid,seq=p.seq,
        apply=p.apply,expiry=c.t_e if c else (d['now']+g.DT)&g.MASK,plan=p,certificate=c,
        parking=src==4,override=src==3)),1897)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--sequences',type=int,default=500);args=ap.parse_args()
    rng=random.Random(0x1A20261029);jobs=[];meta=[];adapter=[]
    def add(s,d,group,name,reset=False,fixture=None):
        ns,o=g.tsmx_cycle(s,d)
        if fixture is not None:
            assert json.loads(json.dumps(dict(state=asdict(ns),outputs=o)))==fixture,(name,'golden fixture mismatch')
        req=request(d)
        bits=cat([(reset,1),(req,44673),(record(g.pack_top_rsp(o),38),38),
             (command(ns,o,d),1897),(record(g.pack_ingress(ns.ingress),332),332),
             (g.MODES.index(ns.mode),3),(ns.good,2),(ns.fault_latched,1),
             (bool(ns.pending),1),(bool(ns.backup),1),(ns.events_lost,32),
             (record(g.pack_event(ns.events[-1]),1056),1056)])
        jobs.append(bits);meta.append(dict(group=group,name=name,response=o,now=d['now'],reset=reset))
        return ns
    # Check both legacy checksum and the complete semantic transitions in all 128 cases.
    md=json.loads((ROOT/'vectors/system.json').read_text())
    raw=(ROOT/'vectors/system.hex').read_bytes();assert hashlib.sha256(raw).hexdigest()==md['sha256']
    legacy_state=None
    for line in raw.decode().splitlines():
        encoded=int(line,16);values={}
        for f in md['fields']:
            value=(encoded>>f['lsb'])&((1<<f['bits'])-1)
            if f['signed'] and value>>(f['bits']-1):value-=1<<f['bits']
            values[f['name']]=value
        initial=[values[n] for n in ('x','v','a','object_x','object_v','now','candidate','fault','seq')]
        expected,legacy_state=fixture_driver.evaluate('system',initial,legacy_state)
        assert expected==[values[n] for n in ('accept','selected','mode','reason_crc32','margin','output_digest')]
    rows=[json.loads(x) for x in (ROOT/'vectors/system.ports.jsonl').read_text().splitlines()]
    for i,row in enumerate(rows):
        if i:assert row['input']['state']==rows[i-1]['output']['state']
        add(state(row['input']['state']),inputs(row['input']['inputs']),'system',str(i),i==0,row['output'])
    # The arbitration edge sequence starts at reset; imported live snapshots need a preload.
    # Preserve those separately, never disguise them as physical reset-to-reset top tests.
    for row in [json.loads(x) for x in (ROOT/'vectors/edges.ports.jsonl').read_text().splitlines()]:
        if row['block']!='system':continue
        if row['name'].startswith('arbitration_'):
            add(state(row['input']['state']),inputs(row['input']['inputs']),'edge',row['name'],row['name']=='arbitration_0',row['output'])
        elif row['name'].startswith('live_epoch_'):
            # The live-fault return erases mode/good and authorization differences.
            # Prove whole-state equivalence before using a physical reset snapshot.
            add(g.Supervisor(),inputs(row['input']['inputs']),'edge',row['name'],True,row['output'])
            adapter.append(dict(name=row['name'],status='physical reset is golden whole-state equivalent'))
        else:
            ss,oo=g.tsmx_cycle(state(row['input']['state']),inputs(row['input']['inputs']))
            assert json.loads(json.dumps(dict(state=asdict(ss),outputs=oo)))==row['output']
            d=inputs(row['input']['inputs'])
            prefix=dict(now=(d['now']+1)&g.MASK,ego=replace(d['ego'],t=(d['now']+2)&g.MASK))
            before=add(g.Supervisor(),prefix,'edge',row['name']+':physical_history_prefix',True)
            ns,no=g.tsmx_cycle(before,d)
            assert no==oo and ns.ingress==ss.ingress and ns.events[-1]==ss.events[-1]
            add(before,d,'edge',row['name'])
            adapter.append(dict(name=row['name'],status='physical invalid-live prefix establishes rollback history; original response/event identical'))
    edge_start=128
    edge_end=len(jobs)
    (HERE/'edges.mem').write_text(''.join(f'{j:012010x}\n' for j in jobs[edge_start:edge_end]))
    (HERE/'live_edges.mem').write_text(''.join(f'{j:012010x}\n' for j in jobs[edge_start+10:edge_end]))
    # Reachable transition chain: three admissions, reuse, fallback, capability loss,
    # standstill HOLD and a new valid recovery admission. No hidden state preload.
    mode_start=len(jobs);s=g.Supervisor();modes=[]
    for step in range(8):
        now=step*20000;x=now+(200000 if step>=4 else 0)
        e=g.Ego(now,x,0 if step==6 else 1000000,0,x+50000000,0)
        d=dict(now=now,ego=e,ack=True)
        if step in (0,1,2,7):
            px,pv=g.advance(e.x,e.v,e.a,20000)
            p=g.Plan(200+step,e,now,now+20000,px,pv,0)
            d.update(pkt=g.packet(p),cert=g.certify(p,now+500000))
        if step==5:d['capability']=False
        s=add(s,d,'mode',f'mode_transition_{step}',step==0);modes.append(s.mode)
    assert modes==['RECOVERY','RECOVERY','L0','L1','L2','L3','HOLD','RECOVERY'],modes
    (HERE/'modes.mem').write_text(''.join(f'{j:012010x}\n' for j in jobs[mode_start:]))
    # Stateful fault bursts: every sequence has fresh random ICs, multiple retained commits.
    kinds=['clear','stale','crc','replay','splice','ack_lost','expiry','lane','bist','health','cap','reset','rear']
    for seq in range(args.sequences):
        s=g.Supervisor();x=rng.randrange(-1000000,1000000);v=rng.randrange(0,1000001)
        seqnum=rng.randrange(100,1<<20)
        for step in range(6):
            now=step*20000
            e=g.Ego(now,x+v*now//g.T,v,0,x+50000000+v*now//g.T,rng.randrange(0,1000001))
            px,pv=g.advance(e.x,e.v,e.a,20000)
            p=g.Plan(seqnum+step,e,now,now+20000,px,pv,0)
            objects=(g.Motion(e.x+50000000,0),)
            d=dict(now=now,ego=e,pkt=g.packet(p),cert=g.certify(p,now+500000,objects),ack=step>0,
                   objects=objects,lane=(-1800000,1800000))
            kind=kinds[(seq+step)%len(kinds)] if step in (2,3,4) else 'clear'
            if kind=='stale':
                pe=replace(e,t=(now-150001)&g.MASK);p=replace(p,snapshot=pe);d.update(pkt=g.packet(p),cert=g.certify(p,now+500000))
            elif kind=='crc':d['pkt']=replace(d['pkt'],crc=d['pkt'].crc^1)
            elif kind=='replay' and s.ingress.seq>=0:
                p=replace(p,seq=s.ingress.seq);d.update(pkt=g.packet(p),cert=g.certify(p,now+500000))
            elif kind=='splice':
                p=replace(p,x=p.x+1000000);d.update(pkt=g.packet(p),cert=g.certify(p,now+500000))
            elif kind=='ack_lost':d['ack']=False;d['pkt']=None
            elif kind=='expiry':d['cert']=replace(d['cert'],t_e=now+20000);d['cert']=replace(d['cert'],seal=g.cert_seal(d['cert']))
            elif kind=='lane':d['lane']=(-900000,900000);d['cert']=g.certify(p,now+500000,d['objects'],d['lane'])
            elif kind=='bist':d['health_inputs']=dict(words=(1,),parities=(0,),bist=True)
            elif kind=='health':d['health']=False
            elif kind=='cap':d['capability']=False
            elif kind=='reset':d['reset']=True
            elif kind=='rear':d['rear_ftti']=285000
            if kind not in ('lane',):
                # Explicit objects are part of certificate context even on otherwise valid jobs.
                if d.get('cert') and kind not in ('expiry',):
                    d['cert']=g.certify(d['pkt'].plan if d.get('pkt') else p,now+500000,d['objects'],d['lane'])
            s=add(s,d,'sequence',f'{seq}:{step}:{kind}',step==0)
    width=1+44673+38+1897+332+8+32+1056
    def save_aux(name,fn):
        start=len(jobs);fn()
        (HERE/(name+'.mem')).write_text(''.join(f'{j:0{(width+3)//4}x}\n' for j in jobs[start:]))
        (HERE/(name+'.json')).write_text(json.dumps(meta[start:],indent=2))
        del jobs[start:];del meta[start:]
    def smoke():
        s=g.Supervisor()
        for i,(now,et) in enumerate(((1000,1001),(999,999))):
            d=dict(now=now,ego=g.Ego(et,0,1000000,0,50000000,0))
            s=add(s,d,'smoke',f'live_or_clock_{i}',i==0)
    save_aux('smoke',smoke)
    def worst():
        e=g.Ego(0,0,10000000,0,100000000,0)
        px,pv=g.advance(e.x,e.v,e.a,100000)
        p=g.Plan(1,e,0,100000,px,pv,0)
        objects=tuple(g.Motion(100000000+i*100000,10000000,0,4800000,50000,-4000000) for i in range(32))
        d=dict(now=0,ego=e,pkt=g.packet(p),cert=g.certify(p,500000,objects),objects=objects)
        add(g.Supervisor(),d,'worst','two_full_sweeps_32_objects',True)
    save_aux('worst',worst)
    # A8 (02/11): accelerating ego/plan (0,+2] m/s^2 with a random lead; own RNG so vectors.mem is unchanged.
    def apos():
        r2=random.Random(0x41382026)
        for seq in range(60):
            s=g.Supervisor();x=r2.randrange(-1000000,1000000);v=r2.randrange(0,9000001);a=r2.randrange(1,2000001)
            seqnum=r2.randrange(100,1<<20);gap=r2.randrange(8000000,60000001);ov=r2.randrange(0,10000001)
            for step in range(6):
                now=step*20000
                e=g.Ego(now,x+v*now//g.T,v,a,x+gap,ov)
                px,pv=g.advance(e.x,e.v,e.a,20000)
                p=g.Plan(seqnum+step,e,now,now+20000,px,pv,a)
                objects=(g.Motion(x+gap+ov*now//g.T,ov),)
                d=dict(now=now,ego=e,pkt=g.packet(p),cert=g.certify(p,now+500000,objects),ack=step>0,
                       objects=objects,lane=(-1800000,1800000))
                kind=('clear','crc','stale','splice')[(seq+step)%4] if step in (2,3) else 'clear'
                if kind=='crc':d['pkt']=replace(d['pkt'],crc=d['pkt'].crc^1)
                elif kind=='stale':
                    p=replace(p,snapshot=replace(e,t=(now-150001)&g.MASK));d.update(pkt=g.packet(p),cert=g.certify(p,now+500000,objects))
                elif kind=='splice':
                    p=replace(p,x=p.x+1000000);d.update(pkt=g.packet(p),cert=g.certify(p,now+500000,objects))
                s=add(s,d,'apos',f'{seq}:{step}:{kind}',step==0)
    save_aux('apos',apos)
    def worst_apos():
        e=g.Ego(0,0,9800000,2000000,100000000,0)  # plan reaches the 10 m/s ODD ceiling at apply
        px,pv=g.advance(e.x,e.v,e.a,100000)
        p=g.Plan(1,e,0,100000,px,pv,2000000)
        objects=tuple(g.Motion(100000000+i*100000,10000000,0,4800000,50000,-4000000) for i in range(32))
        d=dict(now=0,ego=e,pkt=g.packet(p),cert=g.certify(p,500000,objects),objects=objects)
        add(g.Supervisor(),d,'worst','two_full_sweeps_32_objects_apos',True)
    save_aux('worst_apos',worst_apos)
    (HERE/'vectors.mem').write_text(''.join(f'{j:0{(width+3)//4}x}\n' for j in jobs))
    manifest=dict(width=width,jobs=len(jobs),sequences=args.sequences,seed=0x1A20261029,
        counts={k:sum(x['group']==k for x in meta) for k in ('system','edge','mode','sequence')},
        fixture_sha256=md['sha256'],adapter_only=adapter,jobs_meta=meta)
    (HERE/'vectors.json').write_text(json.dumps(manifest,indent=2))
    (HERE/'vector_count.svh').write_text(f'localparam integer JOBS={len(jobs)};\nlocalparam integer VW={width};\n')
    print('Golden generated:',manifest['counts'],'new sequences:',args.sequences,flush=True)
if __name__=='__main__':main()
