"""Firmware abstraction of manuscript_v5 eq. plannerpacket (SI -> golden ABI).

Assumed, not measured: planner 40 ms, firmware 5 ms, transfer 35 ms, admission
at 80 ms, delivery at 99 ms, apply/ACK at 100 ms (20 ms after issuance).
All states use a persistent longitudinal station offset; local axes are fixed
at each planner reference epoch. This is a 1-D open-loop abstraction.
"""
import ast
import sys
from pathlib import Path
from dataclasses import replace
import numpy as np

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
HW = HERE.parents[1]
sys.path[:0] = [str(HW / 'golden'), str(HW / 'tb/integ')]
from tsmx_golden import model as g
import gen_sequences as enc

LANE = (-1800000, 1800000)
ADMISSION = 80000
APPLY = 100000
ACK = 20000

def fixed(x):
    return int(round(float(x) * g.S))

def quadratic(w0, w1, tau=.1):
    alpha = (float(w1) - 2*float(w0)) / .5
    beta = 4*float(w0) - float(w1)
    return alpha*tau*tau + beta*tau, 2*alpha*tau + beta, 2*alpha

class SweepPoses:
    """Central differences on irregular ~20 Hz poses, then linear interpolation.

    Acceleration uses the irregular three-point second derivative. Endpoints
    use one-sided velocity and nearest interior acceleration. Offline estimates
    use future poses; these are not causal CAN/IMU measurements.
    """
    def __init__(self, rows):
        rows = sorted({r['timestamp']: r for r in rows}.values(), key=lambda r:r['timestamp'])
        self.t = np.array([r['timestamp'] for r in rows], np.int64)
        self.p = np.array([r['translation'][:2] for r in rows], float)
        dt = np.diff(self.t)*1e-6
        self.v = np.empty_like(self.p)
        self.v[1:-1] = (self.p[2:]-self.p[:-2]) / (dt[1:]+dt[:-1])[:,None]
        self.v[0] = (self.p[1]-self.p[0])/dt[0]
        self.v[-1] = (self.p[-1]-self.p[-2])/dt[-1]
        self.a = np.empty_like(self.p)
        self.a[1:-1] = 2*((self.p[2:]-self.p[1:-1])/dt[1:,None] -
                             (self.p[1:-1]-self.p[:-2])/dt[:-1,None])/(dt[1:]+dt[:-1])[:,None]
        self.a[0], self.a[-1] = self.a[1], self.a[-2]
        self.station = np.r_[0., np.cumsum(np.linalg.norm(np.diff(self.p,axis=0),axis=1))]
    def at(self, t, origin, axis, offset):
        def interp(a):
            return np.array([np.interp(t-self.t[0], self.t-self.t[0], a[:,k]) for k in range(2)])
        return (offset + float((interp(self.p)-origin)@axis),
                float(interp(self.v)@axis), float(interp(self.a)@axis))
    def offset(self, t):
        return float(np.interp(t-self.t[0],self.t-self.t[0],self.station))

def va_world(records, latency, horizon, offset):
    """Verbatim W7 VA with LAT parameterized to object epoch -> checked state.

    Cover horizon includes bridge and maximum legal live/plan stopping tail.
    Unknown and out-of-domain objects fail closed, never disappear or clip.
    """
    tree = ast.parse((HW/'eval_nuscenes/w7_secondary.py').read_text())
    fn = next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='reduce_neg')
    env = dict(Motion=g.Motion, LAT=latency, S=g.S, fixed=fixed)
    exec(compile(ast.Module(body=[fn],type_ignores=[]),'w7_secondary.py','exec'),env)
    raw = env['reduce_neg'](records,horizon,False)
    if raw is None:
        raw = tuple(g.Motion(fixed(r['x']),-1 if r['v'] is None else fixed(r['v']),
                             length=fixed(r['length'])) for r in records)
    if all(0<=o.v<=20*g.S for o in raw):
        raw = g.propagated_objects(raw,latency,0)
    return tuple(replace(o,x=o.x+fixed(offset)) for o in raw)

def make_packet(seq, tr, ego, snapshot, w0, w1, offset, records):
    """Encode a newly completed plan; w0 is the four-waypoint vector.

    The compatibility w1 argument is unused. Replay supplies one completion per
    token. A transport integration must preserve Plan on retry (TransactionEncoder)
    rather than calling this factory with a newly refreshed reference epoch.
    """
    x,v,a = encode_state(w0, snapshot, offset)
    # generated is the preserved plan reference epoch, not transmission time.
    p = g.Plan(seq,snapshot,tr,tr+APPLY,fixed(offset+x),fixed(v),fixed(a),compute=5000)
    horizons=[]
    for ex,ev,ea in ((ego.x,ego.v,ego.a),(p.x,p.v,p.a)):
        for cid in range(16):
            if g.LIBRARY[cid][1]:
                tail=g.b4_mrmgen(ex,ev,ea,cid)
                if tail.accept: horizons.append(tail.rows[-1][0]+APPLY-ADMISSION)
    horizon=max(horizons,default=0)
    objects=va_world(records,ADMISSION,horizon,offset)
    d=dict(now=tr+ADMISSION,ego=ego,pkt=g.packet(p,(seq,seq,seq)),
           cert=g.certify(p,tr+500000,objects,LANE),objects=objects,lane=LANE)
    return d,dict(q=[x,v,a],cover_horizon_us=horizon,object_latency_us=ADMISSION)

def job(state, d, reset=False):
    ns,o=g.tsmx_cycle(state,d)
    bits=enc.cat([(reset,1),(enc.request(d),44673),(enc.record(g.pack_top_rsp(o),38),38),
                  (enc.command(ns,o,d),1897),(enc.record(g.pack_ingress(ns.ingress),332),332),
                  (g.MODES.index(ns.mode),3),(ns.good,2),(ns.fault_latched,1),
                  (bool(ns.pending),1),(bool(ns.backup),1),(ns.events_lost,32),
                  (enc.record(g.pack_event(ns.events[-1]),1056),1056)])
    return ns,o,f'{bits:012010x}\n'

# Fixed candidates; equal-weight quadratic LS with exact origin constraint.
ENCODING = 'E0'
EMIT_MEM = False
_times = np.array([.5, 1., 1.5, 2.])
_fit = np.linalg.pinv(np.column_stack((_times, _times**2)))

def smooth(waypoints, tau=.1):
    beta, alpha = _fit @ np.asarray(waypoints, float)
    return beta*tau+alpha*tau*tau, beta+2*alpha*tau, 2*alpha

def encode_state(waypoints, snapshot, offset, encoding=None):
    encoding = ENCODING if encoding is None else encoding
    if encoding == 'E0': return quadratic(*waypoints[:2])
    q = smooth(waypoints)
    if encoding == 'E1': return q
    if encoding != 'E2': raise ValueError(encoding)
    # Pose-derived snapshots can be outside the ABI even after the W7 keyframe
    # ODD filter. Preserve that invalid snapshot so B1 fails closed. Compute
    # diagnostic kinematics without calling golden's range-checked advance.
    if 0 <= snapshot.v <= 20*g.S and -8*g.S <= snapshot.a <= 2*g.S:
        x, v = g.advance(snapshot.x, snapshot.v, snapshot.a, APPLY)
    else:
        x = snapshot.x + snapshot.v*.1 + .5*snapshot.a*.1**2
        v = snapshot.v + snapshot.a*.1
    return x/g.S-offset, v/g.S, float(np.clip(q[2], -8., 2.))

class TransactionEncoder:
    """Encode each planner completion once; preserve its Plan on retries.

    The producer, not the transport, owns seq and reference_us. A new producer
    sequence AND reference epoch must represent an actual completed plan. This
    ABI cannot infer semantic liveness from repeated waypoint values alone.
    Rebuild the current world/certificate separately around the returned Plan;
    never replace its snapshot, generated/apply epochs or encoded state.
    """
    def __init__(self, encoding):
        self.encoding=encoding
        self.cached=None

    def encode(self, seq, reference_us, snapshot, waypoints, offset):
        if self.cached is not None:
            if seq==self.cached.seq and reference_us==self.cached.generated:
                return self.cached
            if g.elapsed(seq,self.cached.seq)<=0 or g.elapsed(reference_us,self.cached.generated)<=0:
                raise ValueError('planner completion must advance sequence and reference epoch')
        x,v,a=encode_state(waypoints,snapshot,offset,self.encoding)
        self.cached=g.Plan(seq,snapshot,reference_us,reference_us+APPLY,
                           fixed(offset+x),fixed(v),fixed(a),compute=5000)
        return self.cached

_serialized_job = job
def job(state, d, reset=False):
    if EMIT_MEM: return _serialized_job(state, d, reset)
    ns, o = g.tsmx_cycle(state, d)
    return ns, o, ''
