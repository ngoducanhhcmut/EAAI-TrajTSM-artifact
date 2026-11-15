"""Continuous, reset-per-scene full-system replay and physically reachable jobs."""
import sys, json, pickle, time, csv, struct, hashlib, ast
from collections import Counter
from dataclasses import asdict, replace
import numpy as np
from packetizer_v2 import *
sys.path.insert(0,str(HW/'eval_nuscenes'))
import run_w7 as w7
import w7_secondary as secondary

def save(name,value):
    (HERE/name).write_text(json.dumps(value,indent=2,allow_nan=False),encoding='utf8')

def lead(objects,x):
    # Explicit empty-front sentinel, not a fabricated measured lead. The scalar
    # golden front gate has no "absent" bit. Put it at the 9999 m ABI boundary.
    ahead=[o for o in objects if o.x>x]
    if not ahead:return fixed(9999),0
    obj=min(ahead,key=lambda o:o.x-o.length)
    return obj.x-obj.length+4800000,obj.v

def make_ego(t,si,objects):
    x,v,a=map(fixed,si)
    lx,lv=lead(objects,x)
    return g.Ego(t,x,v,a,lx,lv)

def metrics(rows):
    # W7 bootstrap: clustered scene resampling, 2000 draws, same seed; rate units %.
    sc=[r['scene'] for r in rows]
    def rate(num,den):
        n,d=sum(num),sum(den)
        return dict(n=n,denominator=d,rate_pct=100*n/d if d else None,
                    ci95_pct=secondary.boot(sc,num,den) if d else None)
    ac=[int(r['response']['accept']) for r in rows]
    safe=[int(r['oracle']['label']=='SAFE') for r in rows]
    unsafe=[int(r['oracle']['label']=='UNSAFE') for r in rows]
    return dict(acceptance=rate(ac,[1]*len(rows)),
                false_reject=rate([(1-a)*s for a,s in zip(ac,safe)],safe),
                false_accept=rate([a*s for a,s in zip(ac,unsafe)],unsafe),
                oracle_unknown=sum(r['oracle']['label']=='UNKNOWN' for r in rows))

def errstats(rows):
    out={}
    for field in ('position_error_m','velocity_error_mps','acceleration_error_mps2'):
        v=np.array([abs(r[field]) for r in rows])
        out[field]=dict(mean=float(v.mean()),p95=float(np.percentile(v,95)),max=float(v.max()))
    out.update(n=len(rows),position_over_16cm=sum(abs(r['position_error_m'])>.16 for r in rows),
               velocity_over_20cmps=sum(abs(r['velocity_error_mps'])>.2 for r in rows),
               either_over_tolerance=sum(abs(r['position_error_m'])>.16 or abs(r['velocity_error_mps'])>.2 for r in rows),
               b2_reject=sum(not r['b2_pass'] for r in rows))
    return out

def run_scene(cache,scene,label,sink):
    replay=SceneReplay(cache,scene,label,sink);replay.begin()
    rr=sorted([r for r in cache['frames'] if r['scene']==scene],key=lambda r:r['timestamp'])
    for r in rr:
        if not r.get('odd'):continue
        ep=cache['keyposes'][r['token']];angle=w7.yaw(ep['rotation'])
        axis=np.array([np.cos(angle),np.sin(angle)])
        if label=='H':
            origin=np.array(ep['translation'][:2])
            wp=[replay.poses.at(r['timestamp']+dt,origin,axis,0)[0] for dt in (500000,1000000,1500000,2000000)]
        else:
            if r['token'] not in cache['plans']:raise ValueError('missing T token '+r['token'])
            wp=cache['plans'][r['token']][:,0]
        replay.admit(r,wp)
    if replay.last:replay.advance_to(rr[-1]['timestamp']-replay.start+ADMISSION+1)
    return replay

def worker(part,parts):
    cache=pickle.loads((HERE/'inputs.pkl').read_bytes())
    folder=HERE/'shards';folder.mkdir(exist_ok=True)
    for i,scene in enumerate(cache['scenes']):
        if i%parts!=part:continue
        for label in 'HT':
            dest=folder/(scene+'_'+label+'.pkl')
            if dest.exists():continue
            records=[]
            replay=run_scene(cache,scene,label,lambda line,row,d:records.append((line,row)))
            tmp=dest.with_suffix('.tmp')
            with tmp.open('wb') as f:pickle.dump(dict(records=records,rows=replay.rows),f,protocol=4)
            tmp.replace(dest)
            print(label,scene,len(replay.rows),replay.index,flush=True)

class SceneReplay:
    def __init__(self,cache,scene,label,sink=None):
        self.cache,self.scene,self.label,self.sink=cache,scene,label,sink
        self.poses=SweepPoses(cache['sweeps'][scene])
        self.state=g.Supervisor();self.index=0;self.last=None;self.executor=None
        self.outputs=[];self.rows=[];self.pending_service=[]
    def emit(self,d,kind,token=None,extra=None):
        before=self.state
        b1_reason=g.b1_ingress(before.ingress,d['now'],d['ego'],d.get('pkt'))[1]
        self.state,o,line=job(before,d,self.index==0)
        row=dict(scene=self.scene,source=self.label,token=token,kind=kind,now=d['now'],
                 reset=self.index==0,response=o,mode=self.state.mode,b1_reason=b1_reason,
                 pending=bool(self.state.pending),backup=bool(self.state.backup),
                 executor_b9=(g.b9_cert(before.pending[1],before.pending[2],d['now'],True,
                                      before.pending[0],d.get('ack',False),before.pending[1].seq)
                              if before.pending else None))
        if extra:row.update(extra)
        row['input']={k:(asdict(v) if hasattr(v,'__dataclass_fields__') else
                         [asdict(z) for z in v] if k=='objects' else v) for k,v in d.items()}
        if self.sink:self.sink(line,row,d)
        self.index+=1;self.outputs.append(row)
        # Ideal command tracking between recorded measurements only.
        if self.state.pending:self.executor=self.state.pending[1]
        elif self.state.mode=='L1' and self.state.backup:self.executor=self.state.backup[0]
        else:
            cid=o['candidate'] if self.state.mode=='L2' else 15
            e=d['ego'];self.executor=g.Plan(0,e,d['now'],d['now'],e.x,e.v,e.a,tail=cid)
        self.last=d
        return row
    def service(self,when):
        old=self.last;delta=when-old['now']
        objects=old['objects']
        if all(0<=o.v<=20*g.S for o in objects):
            objects=g.propagated_objects(objects,delta,old['ego'].x)
        p=self.executor
        if p and 0<=p.v<=10*g.S and -8*g.S<=p.a<=2*g.S:
            x,v=g.phase_state(p,when)
            a=p.a if when-p.apply<g.DT else g.profile_a(p.tail,when-p.apply-g.DT,p.a)
            si=(x/g.S,v/g.S,a/g.S)
        else:
            e=old['ego'];si=(e.x/g.S,e.v/g.S,e.a/g.S)
        e=make_ego(when,si,objects)
        self.emit(dict(now=when,ego=e,objects=objects,lane=LANE,ack=True),'service')
    def advance_to(self,t):
        while self.last and self.last['now']+100000<t:self.service(self.last['now']+100000)
    def admit(self,r,wp,oracle_records=None):
        s=self.cache['samples'][r['token']];ep=self.cache['keyposes'][r['token']]
        origin=np.array(ep['translation'][:2]);yaw=w7.yaw(ep['rotation'])
        axis=np.array([np.cos(yaw),np.sin(yaw)])
        tr=int(s['timestamp']-self.start);tc=tr+ADMISSION
        self.advance_to(tc)
        offset=self.poses.offset(s['timestamp'])
        live=self.poses.at(s['timestamp']+ADMISSION,origin,axis,offset)
        snap=self.poses.at(s['timestamp'],origin,axis,offset)
        apply=self.poses.at(s['timestamp']+APPLY,origin,axis,offset)
        records=oracle_records if oracle_records is not None else r['objects']
        packet_records=[]
        for record in records:
            vector,age=self.cache['causal_velocities'][record['token']]
            packet_records.append(dict(record,v=float(vector@axis) if vector is not None else None))
        # First build with a correct conservative explicit-world lead, then seal.
        dummy=make_ego(tc,live,())
        snapshot=make_ego(tr,snap,())
        d,detail=make_packet(len(self.rows)+1,tr,dummy,snapshot,wp,None,offset,packet_records)
        e=make_ego(tc,live,d['objects'])
        obj0=va_world(packet_records,0,detail['cover_horizon_us']+ADMISSION,offset)
        snapshot=make_ego(tr,snap,obj0)
        p=replace(d['pkt'].plan,snapshot=snapshot)
        d.update(ego=e,pkt=g.packet(p,(p.seq,)*3),cert=g.certify(p,tr+500000,d['objects'],LANE))
        # An unknown/out-of-domain velocity cannot authorize a context-bound
        # certificate. Keep the packet/raw world, withhold that certificate.
        # Otherwise the unmodified top can reach advance() on invalid objects.
        host_guard=any(not (0<=o.v<=20*g.S and 0<o.length<=20*g.S and abs(o.x)<=10000*g.S) for o in d['objects']) or len(d['objects'])>32
        if host_guard:d['cert']=None
        q=detail['q']
        # Registered W7 oracle is retained verbatim (including .5 s object offset).
        # This is a deliberately reported epoch mismatch, not an aligned oracle.
        oracle=w7.oracle(tuple(q),records)
        row=self.emit(d,'admission',r['token'],dict(plan=asdict(p),packet=asdict(d['pkt']),
                      ego=asdict(e),objects=[asdict(o) for o in d['objects']],
                      oracle=oracle,host_object_guard=host_guard,b2_pass=g.b2_splice(e,p),
                      position_error_m=offset+q[0]-apply[0],velocity_error_mps=q[1]-apply[1],
                      acceleration_error_mps2=q[2]-apply[2],**detail))
        self.rows.append(row)
        # Apply/ACK at tr+100 ms: 20 ms after admission, before the 40 ms timeout.
        self.service(tr+APPLY)
        return row
    def begin(self):
        self.start=min(s['timestamp'] for s in self.cache['samples'].values()
                       if self.cache['scene_names'][s['scene_token']]==self.scene)

