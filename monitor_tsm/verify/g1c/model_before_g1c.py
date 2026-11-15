from dataclasses import dataclass, replace, asdict
from hashlib import sha256
import json
import zlib
from functools import lru_cache

S = T = 1_000_000
DT = 100_000
NAN = -(1 << 63)
MASK = (1 << 32)-1
LIBRARY = tuple((b*S, j*S if j else 0, f'b{b}_j{j or "instant"}')
                for b in (2,4,6,8) for j in (2,4,8,0))
MODES = ('L0','L1','L2','L3','HOLD','RECOVERY')

def checked(x, bits=64):
    if type(x) is not int or not -(1 << (bits-1)) < x < (1 << (bits-1)):
        raise ValueError('numeric_overflow')
    return x

def ceildiv(n,d):
    assert d > 0
    checked(n,256)
    return -((-n)//d)

def digest_json_legacy(x):
    return sha256(json.dumps(x, sort_keys=True,separators=(',',':')).encode()).hexdigest()

def canonical_json_legacy(x):
    return json.dumps(x,sort_keys=True,separators=(',',':')).encode()

# S1b wire ABI: big endian, two's complement, zero LSB byte padding.
# Invalid fixture values may be masked here; admission MUST guard before use.
REASONS = ('ok clock_reset freeze_no_sample timeout numeric range_schema overflow deadline snapshot crc '
           'sequence ego_freshness freshness freeze range phase_alignment horizon trajectory lane_range object_overflow '
           'lane object_range object_speed_bound time separation binding replay context_binding lease_bound expiry_at_executor '
           'ack_timeout committed pending late_apply expiry no_pending splice ftti_budget geometry capability '
           'health reset no_backup ego_live bridge').split()

def _fields(x):
    return asdict(x) if hasattr(x, '__dataclass_fields__') else x

def _record(fields):
    word = bits = 0
    for value, width in fields:
        word = (word << width) | (int(value) & ((1 << width)-1))
        bits += width
    pad = (-bits) % 8
    return (word << pad).to_bytes((bits+pad)//8, 'big')

def _nested(data, bits):
    return int.from_bytes(data, 'big') >> ((-bits) % 8), bits

def pack_ego(x):
    x = _fields(x)
    return _record((x[k], w) for k,w in zip(('t','x','v','a','lx','lv'),(32,64,32,32,64,32)))

def pack_plan(x):
    x = _fields(x)
    return _record([(x['seq'],32), _nested(pack_ego(x['snapshot']),256)] +
                   [(x[k],w) for k,w in zip(('generated','apply','x','v','a','tail','compute','count','schema'),
                                            (32,32,64,32,32,8,32,8,32))])

def pack_packet_body(p, ids=(0,0,0), schema=1):
    return pack_plan(p) + _record([(i,32) for i in ids] + [(schema,32)])

def pack_packet(x):
    if x is None: return _record([(0,721)])
    return _record([(1,1),_nested(pack_plan(x.plan),560),(x.crc,32)] +
                   [(i,32) for i in x.snapshot_ids]+[(x.schema,32)])

def pack_motion(x):
    x = _fields(x)
    return _record((x[k],w) for k,w in zip(('x','v','a','length','event','after_a'),(64,32,32,64,32,32)))

def pack_world(objects):
    if len(objects)>32: raise ValueError('object_overflow')
    return bytes([len(objects)]) + b''.join(pack_motion(o) for o in objects) + bytes((32-len(objects))*32)

def pack_lane(lane=(-1800000,1800000), y=0, half_width=950000, lateral_error=50000, reserve=500000):
    return _record((v,64) for v in (*lane,y,half_width,lateral_error,reserve))

def pack_context(objects=(), lane=(-1800000,1800000)):
    # Context binds only lane lo/hi, exactly as the original semantic contract.
    return pack_world(objects)+_record([(lane[0],64),(lane[1],64),(1,32),(1,32)])

def _hash_field(value):
    if value == '': return 0
    return int(value,16)

def pack_certificate(x, include_seal=True):
    if x is None: return _record([(0,1217)])
    x = _fields(x)
    fields = [(1,1)] if include_seal else []
    fields += [(_hash_field(x[k]),256) for k in ('snapshot','trajectory')]
    fields += [(x[k],32) for k in ('t_a','t_e','capability','config','controller','scope')]
    fields += [(_hash_field(x['context']),256)]
    if include_seal: fields += [(_hash_field(x['seal']),256)]
    return _record(fields)

def pack_row(row):
    return _record(zip(row,(32,64,64,32,32,32,32)))

def pack_trajectory(x):
    x = _fields(x); rows=x['rows']
    if len(rows)>129: raise ValueError('overflow')
    return _record([(x['accept'],1),(REASONS.index(x['reason']),8),(x['stop']>=0,1),
                    (max(0,x['stop']),32),(len(rows),8)] +
                   [_nested(pack_row(r),352) for r in rows]+[(0,352)]*(129-len(rows)))

def pack_geom(x):
    x = _fields(x)
    return _record([(x['accept'],1),(x['margin'],64),(REASONS.index(x['reason']),8),(x['steps'],8)])

def pack_ingress(x):
    x=_fields(x); sig=x['signature']
    return _record([(x['seq']>=0,1),(max(0,x['seq']),32),
                    (x['last_time']>=0,1),(max(0,x['last_time']),32),
                    (x['last_sample']>=0,1),(max(0,x['last_sample']),32),
                    (bool(sig),1)]+list(zip(sig or (0,0,0,0),(64,32,32,8)))+
                   [(x['freeze_since'],32),(x['freeze_x'],64)])

def pack_event(event):
    valid=isinstance(event,(list,tuple)) and len(event)<=4
    fields=[]
    for v in (event if valid else ()):
        if type(v) is int and -(1<<63)<v<(1<<63):
            fields.extend([(0,1),(0,6),(v & ((1<<64)-1),256)])
        elif isinstance(v,str) and v.isascii() and len(v)<=32:
            fields.extend([(1,1),(len(v),6),(int.from_bytes(v.encode().ljust(32,b'\0'),'big'),256)])
        else: valid=False; break
    if not valid: fields=[]
    count=len(event) if valid else 0
    return _record([(valid,1),(count,3)]+fields+[(0,263)]*(4-count))

def pack_top_rsp(x):
    return _record([(x['accept'],1),(REASONS.index(x['reason']),8),
                    (MODES.index(x['mode']),3),(x['candidate'],8),
                    (1 if x['label']=='CERT-FRONT/REAR-COND' else 2,8),
                    (x['independent_brake'],1),(REASONS.index(x['commit']),8),(x['heartbeat'],1)])

def pack_command(x):
    return _record([(x['source'],3),(MODES.index(x['mode']),3),(x['label'],8),
                    (x['candidate'],8),(x['seq'],32),(x['apply'],32),(x['expiry'],32),
                    _nested(pack_plan(x['plan']),560),_nested(pack_certificate(x['certificate']),1217),
                    (x['parking'],1),(x['override'],1)])

def pack_csr_update(x):
    return _record([_nested(pack_top_rsp(x['response']),38)]+
                   [(x[k],1) for k in ('busy','pending','backup','healthy','bist_done')]+
                   [(x[k],w) for k,w in (('cycles',32),('lost',32),('irq_set',8))])

def pack_diagnostic(x):
    """Typed binary diagnostic fixture encoding; never a hardware decision input."""
    x = _fields(x)
    if x is None: return b'N'
    if isinstance(x,bool): return b'B'+bytes([x])
    if isinstance(x,int):
        n=max(1,(x.bit_length()+8)//8)
        return b'I'+n.to_bytes(4,'big')+x.to_bytes(n,'big',signed=True)
    if isinstance(x,str):
        data=x.encode('utf-8'); return b'S'+len(data).to_bytes(4,'big')+data
    if isinstance(x,dict):
        return b'D'+len(x).to_bytes(4,'big')+b''.join(pack_diagnostic(k)+pack_diagnostic(x[k]) for k in sorted(x))
    if isinstance(x,(list,tuple)):
        return b'L'+len(x).to_bytes(4,'big')+b''.join(pack_diagnostic(v) for v in x)
    raise TypeError(type(x))

def digest(x):
    if isinstance(x,bytes): data=x
    else:
        x=_fields(x)
        if isinstance(x,dict) and set(x)=={'t','x','v','a','lx','lv'}: data=pack_ego(x)
        elif isinstance(x,dict) and 'snapshot' in x and 'seq' in x: data=pack_plan(x)
        elif isinstance(x,dict) and 'trajectory' in x and 't_a' in x: data=pack_certificate(x,False)
        elif isinstance(x,dict) and set(x)=={'objects','lane','frame','units'}: data=pack_context(x['objects'],x['lane'])
        else: data=pack_diagnostic(x)
    return sha256(data).hexdigest()

def elapsed(a,b):
    """Signed serial-number difference; caller must stay inside half a wrap."""
    return ((a-b+(1<<31)) & MASK)-(1<<31)

@dataclass(frozen=True)
class Ego:
    t: int
    x: int
    v: int
    a: int
    lx: int
    lv: int

@dataclass(frozen=True)
class Plan:
    seq: int
    snapshot: Ego
    generated: int
    apply: int
    x: int
    v: int
    a: int
    tail: int = 15
    compute: int = 5000
    count: int = 2
    schema: int = 1

@dataclass(frozen=True)
class Packet:
    plan: Plan
    crc: int
    snapshot_ids: tuple = (0,0,0)
    schema: int = 1

def packet(p, ids=(0,0,0)):
    return Packet(p,zlib.crc32(pack_packet_body(p,ids)),ids)

@dataclass(frozen=True)
class Ingress:
    seq: int = -1
    last_time: int = -1
    last_sample: int = -1
    signature: tuple = ()
    freeze_since: int = 0
    freeze_x: int = 0

def b1_ingress(state, now, ego, pkt):
    """Pure admission; clock/sequence use 32-bit serial arithmetic."""
    if state.last_time >= 0 and elapsed(now,state.last_time) < 0:
        return state, 'clock_reset'
    if pkt is None:
        reason = 'freeze_no_sample' if state.last_sample >= 0 and elapsed(now,state.last_sample)>=300000 else 'timeout'
        return state,reason
    p=pkt.plan
    try:
        for st in (ego,p.snapshot):
            for val in asdict(st).values(): checked(val)
            if not (0<=st.t<=MASK and abs(st.x)<=10000*S and abs(st.lx)<=10000*S
                    and 0<=st.v<=10*S and 0<=st.lv<=10*S and -8*S<=st.a<=0):
                return state,'range_schema'
        for val in (now,p.seq,p.generated,p.apply,p.x,p.v,p.a,p.compute,p.count,p.tail,p.schema): checked(val)
    except (ValueError,TypeError): return state,'numeric'
    if not (0<=now<=MASK and 0<=p.seq<=MASK and 0<=p.generated<=MASK and 0<=p.apply<=MASK
            and abs(p.x)<=10000*S and 0<=p.v<=10*S and -8*S<=p.a<=0
            and 0<=p.tail<16 and p.schema==pkt.schema==1): return state,'range_schema'
    if not 2<=p.count<=32: return state,'overflow'
    if not 0<=p.compute<=10000: return state,'deadline'
    if (len(pkt.snapshot_ids)!=3 or len(set(pkt.snapshot_ids))!=1
            or any(type(i) is not int or not 0<=i<=MASK for i in pkt.snapshot_ids)): return state,'snapshot'
    if zlib.crc32(pack_packet_body(p,pkt.snapshot_ids,pkt.schema))!=pkt.crc: return state,'crc'
    if state.seq>=0 and elapsed(p.seq,state.seq)<=0: return state,'sequence'
    if not 0<=elapsed(now,ego.t)<=150000:return state,'ego_freshness'
    if not (0<=elapsed(now,p.snapshot.t)<=150000 and elapsed(now,p.generated)>=0
            and elapsed(p.generated,p.snapshot.t)>=0): return state,'freshness'
    sig=(p.x,p.v,p.a,p.tail)
    if sig==state.signature and elapsed(now,state.freeze_since)>=300000 and abs(ego.x-state.freeze_x)>200000:
        return state,'freeze'
    new=replace(state,seq=p.seq,last_time=now,last_sample=p.snapshot.t)
    if sig!=state.signature: new=replace(new,signature=sig,freeze_since=now,freeze_x=ego.x)
    return new,'ok'

def disp(v,a,n,d=1,up=False):
    """Stop-clipped constant-acceleration displacement at rational n/d ticks."""
    if a<0 and n*(-a)>=v*T*d:
        num,den=v*v,-2*a
    else:
        num,den=2*v*n*T*d+a*n*n,2*T*T*d*d
    checked(num,256); checked(den,256)
    return ceildiv(num,den) if up else num//den

def advance(x,v,a,h,up=False):
    checked(x); checked(v); checked(a)
    if not (0<=v<=20*S and -8*S<=a<=2*S and 0<=h<=12800000): raise ValueError('motion_range')
    dx=disp(v,a,h,up=up)
    nv=max(0,ceildiv(v*T+a*h,T) if up else (v*T+a*h)//T)
    return checked(x+dx),nv

def swept(gap,va,aa,vb,ab,h):
    """Lower bound of exact continuous bumper gap, including both stop events.

    Enumerate endpoints, stops and relative stationary point on every stop phase.
    Candidate times are rational (integer numerator/denominator); displacement is
    rounded down for actor a, up for b. Thus result <= exact min by <2 LSB.
    """
    cuts=[(0,1),(h,1)]
    for v,a in ((va,aa),(vb,ab)):
        if a<0 and 0<v*T<h*(-a): cuts.append((v*T,-a))
    from functools import cmp_to_key
    cuts.sort(key=cmp_to_key(lambda u,w: (u[0]*w[1]>w[0]*u[1])-(u[0]*w[1]<w[0]*u[1])))
    points=list(cuts)
    for l,r in zip(cuts,cuts[1:]):
        # Active accelerations on the open interval. At a stop the next phase is zero.
        ea=aa if not (aa<0 and va*T*l[1]<=l[0]*(-aa)) else 0
        eb=ab if not (ab<0 and vb*T*l[1]<=l[0]*(-ab)) else 0
        ua=va if ea else (0 if aa<0 else va)
        ub=vb if eb else (0 if ab<0 else vb)
        den=ea-eb; num=-(ua-ub)*T
        if den<0: num,den=-num,-den
        if den and l[0]*den < num*l[1] and num*r[1]<r[0]*den: points.append((num,den))
    return min(gap+disp(va,aa,n,d)-disp(vb,ab,n,d,True) for n,d in points)

def b2_splice(ego,plan):
    if not (abs(ego.x)<=10000*S and 0<=ego.v<=10*S and -8*S<=ego.a<=0
            and abs(plan.x)<=10000*S and 0<=plan.v<=10*S):return False
    delay=elapsed(plan.apply,ego.t)
    # A NEW packet cannot splice into its past. Only reusable() may evaluate an
    # already committed backup in its original phase; never restart that epoch.
    if delay<0:return False
    if delay>100000 or not -8*S<=plan.a<=0: return False
    xs=[]; vs=[]
    try:
        for dx in (-50000,50000):
            for dv in (-50000,50000):
                for da in (-100000,100000):
                    v=max(0,ego.v+dv); a=min(0,max(-8*S,ego.a+da))
                    xl,vl=advance(ego.x+dx,v,a,delay)
                    xh,vh=advance(ego.x+dx,v,a,delay,True)
                    xs.extend((xl,xh)); vs.extend((vl,vh))
        return min(xs)>=plan.x-160000 and max(xs)<=plan.x+160000 and min(vs)>=plan.v-200000 and max(vs)<=plan.v+200000
    except ValueError: return False

def profile_a(cid,elapsed_ticks,initial=0):
    b,j,_=LIBRARY[cid]
    if j==0:return -b
    change=j*max(0,elapsed_ticks)//T
    return min(0,max(initial-change,min(initial+change,-b)))

def ramp_integrals(v,a,j,target,h):
    """Exact integer numerator/denominator for continuous capped ramp at h ticks."""
    d=abs(j) if j else 1
    n=min(h*d,abs(target-a)*T) if j else 0
    # Integral a = a*h + j*(tau*h-tau²/2); integral twice a.
    vd=2*T*T*d*d
    vn=v*vd+2*a*h*T*d*d+j*(2*n*h*d-n*n)
    xd=6*T*T*T*d*d*d
    xn=6*v*h*T*T*d*d*d+3*a*h*h*T*d*d*d+j*((h*d)**3-(h*d-n)**3)
    checked(vn,256);checked(xn,256)
    return xn,xd,vn,vd

def continuous_advance(x,v,a,j,target,h,up=False):
    xn,xd,vn,vd=ramp_integrals(v,a,j,target,h)
    if vn<0:
        lo,hi=0,h
        while hi-lo>1:
            mid=(lo+hi)//2
            if ramp_integrals(v,a,j,target,mid)[2]>=0:lo=mid
            else:hi=mid
        xn,xd,_,_=ramp_integrals(v,a,j,target,lo)
        dx=ceildiv(xn,xd)+ceildiv(v,T) if up else xn//xd
        return checked(x+dx),0
    return checked(x+(ceildiv(xn,xd) if up else xn//xd)),max(0,ceildiv(vn,vd) if up else vn//vd)

@dataclass(frozen=True)
class Motion:
    x: int
    v: int
    a: int = 0
    length: int = 4800000
    event: int = 0
    after_a: int = 0

@dataclass(frozen=True)
class GeomResult:
    accept: bool
    margin: int
    reason: str
    steps: int

@dataclass(frozen=True)
class Trajectory:
    accept: bool
    rows: tuple  # phase ticks, xlo/xhi, vlo/vhi, midpoint acceleration, |jerk| bound
    stop: int
    reason: str

def b4_mrmgen(x,v,a,cid,phase=0,limit=128):
    """Continuous jerk-limited ramp, exact capped-ramp integral, stop + 2s hold.

    Rows carry midpoint a AND a Lipschitz jerk bound; B3 inflates the midpoint
    quadratic to cover the continuous curve. Instant explicitly waives jerk.
    Phase is absolute time from original apply; it never restarts the ramp.
    """
    if not (0<=cid<16 and abs(x)<=10000*S and 0<=v<=10*S and -8*S<=a<=0
            and 0<=phase<=12800000 and phase%DT==0 and 1<=limit<=128):return Trajectory(False,(),-1,'range')
    xl=xh=x; vl=vh=v; rows=[]; stop=-1
    for k in range(limit):
        t=phase+k*DT
        b,j,_=LIBRARY[cid]
        start=0 if vh==0 else a if t<DT else profile_a(cid,t-DT,a)
        cmd=0 if vh==0 else a if t<DT else profile_a(cid,t-DT+DT//2,a)
        signed=0 if t<DT or vh==0 or start==-b else -j if start>-b else j
        bound=abs(signed)
        # Non-grid phase may straddle the prefix/ramp transition: reject rather
        # than silently use the wrong epoch. Physical decision phase is 100ms.
        if t<DT<t+DT:return Trajectory(False,tuple(rows),-1,'phase_alignment')
        if not j and t>=DT:start=cmd
        rows.append((t,xl,xh,vl,vh,cmd,bound))
        xl,vl=continuous_advance(xl,vl,start,signed,-b,DT)
        xh,vh=continuous_advance(xh,vh,start,signed,-b,DT,True)
        if vh==0 and stop<0:stop=t+DT
        if stop>=0 and t+DT>=stop+2*T:
            rows.append((t+DT,xl,xh,vl,vh,0,0))
            return Trajectory(True,tuple(rows),stop,'ok')
    return Trajectory(False,tuple(rows),stop,'horizon')

def b3_geom(traj,objects,lane=(-1800000,1800000),y=0,half_width=950000,
            lateral_error=50000,reserve=500000):
    """Sequential lane/longitudinal separation. Objects may be ahead OR behind.

    Object event time is relative to trajectory first row. Its acceleration may
    change once there; intervals are split at that event, with outward bounds.
    Object extent and tracking error are included in length. No relevance truncation.
    """
    if not traj.accept or not 2<=len(traj.rows)<=129:return GeomResult(False,-1,'trajectory',0)
    if (len(lane)!=2 or any(type(v) is not int for v in (*lane,y,half_width,lateral_error,reserve))):
        return GeomResult(False,-1,'lane_range',0)
    # Every generated row is within this proven internal ODD envelope. Check
    # endpoint fields too, before multiplication/advance; corrupted s64 words
    # must produce an explicit reject, never an exception or a wrapped pose.
    for row in traj.rows:
        if not isinstance(row,(tuple,list)) or len(row)!=7 or any(type(v) is not int for v in row):
            return GeomResult(False,-1,'numeric',0)
        t,xl,xh,vl,vh,a,jerk=row
        if not (0<=t<=25600000 and -10070*S<=xl<=xh<=10070*S and 0<=vl<=vh<=20*S
                and -8*S<=a<=0 and 0<=jerk<=8*S):return GeomResult(False,-1,'numeric',0)
    if not (len(lane)==2 and -10000*S<=lane[0]<=lane[1]<=10000*S and abs(y)<=10000*S
            and 0<half_width<=10*S and 0<=lateral_error<=S and 0<=reserve<=10*S):
        return GeomResult(False,-1,'lane_range',0)
    if len(objects)>32:return GeomResult(False,-1,'object_overflow',0)
    if lane[0]>y-half_width-lateral_error or lane[1]<y+half_width+lateral_error:
        return GeomResult(False,-1,'lane',0)
    if any(not (all(type(v) is int for v in (o.x,o.v,o.a,o.length,o.event,o.after_a))
                and abs(o.x)<=10000*S and 0<=o.v<=20*S and -8*S<=o.a<=2*S
                and -8*S<=o.after_a<=2*S and 0<=o.event<=12800000
                and 0<o.length<=20*S) for o in objects):return GeomResult(False,-1,'object_range',0)
    horizon=traj.rows[-1][0]-traj.rows[0][0]
    if not 0<horizon<=12800000:return GeomResult(False,-1,'horizon',0)
    if any(o.v+ceildiv(max(0,o.a,o.after_a)*horizon,T)>20*S for o in objects):
        return GeomResult(False,-1,'object_speed_bound',0)
    states=[(o.x,o.x,o.v,o.v) for o in objects]; minimum=10000*S
    origin=traj.rows[0][0]
    for k,(row,nxt) in enumerate(zip(traj.rows,traj.rows[1:])):
        t,xl,xh,vl,vh,a,jerk=row; h=nxt[0]-t
        if not 0<h<=DT:return GeomResult(False,-1,'time',k)
        if not (-(1<<63)<xl<=xh<(1<<63) and 0<=vl<=vh<=20*S and -8*S<=a<=0
                and 0<=jerk<=8*S):return GeomResult(False,-1,'numeric',k)
        # |a(u)-a(h/2)| <= J |u-h/2| + 1 LSB. Twice integrated
        # absolute error <= J*h³/8 + h²/2 LSB; stop clipping is monotone.
        inflate=ceildiv(jerk*h*h*h,8*T*T*T)+ceildiv(h*h,2*T*T)
        for i,o in enumerate(objects):
            ol,oh,ovl,ovh=states[i]
            pieces=[0,h]
            event=o.event-(t-origin)
            if 0<event<h:pieces.insert(1,event)
            exl,exh,evl,evh=xl-inflate,xh+inflate,vl,vh
            ahead=ol>=xh
            for left,right in zip(pieces,pieces[1:]):
                width=right-left
                oa=o.a if t-origin+left<o.event else o.after_a
                if ahead: g=swept(ol-exh-o.length,ovl,oa,evh,a,width)
                else:g=swept(exl-oh-o.length,evl,a,ovh,oa,width)
                minimum=min(minimum,g-reserve)
                if g<reserve:return GeomResult(False,g-reserve,'separation',k+1)
                ol,ovl=advance(ol,ovl,oa,width);oh,ovh=advance(oh,ovh,oa,width,True)
                # Preflight proves true actor speed<=20 throughout the horizon.
                # Intersect outward rounding with that invariant; fractional
                # positive acceleration must not accumulate a spurious v>20
                # that would trip advance's guard on the next cell.
                ovh=min(20*S,ovh)
                exl,evl=advance(exl,evl,a,width);exh,evh=advance(exh,evh,a,width,True)
            states[i]=(ol,oh,ovl,ovh)
    return GeomResult(True,minimum,'ok',len(traj.rows)-1)

def b7_select(results):
    # A3/d2 finite jerk pool; instant candidates are diagnostic/mitigation only.
    pool=[i for i,r in enumerate(results) if i<16 and LIBRARY[i][1] and r.accept]
    if not pool:return 15,'MITIGATION'
    return min(pool,key=lambda i:(LIBRARY[i][0],LIBRARY[i][1],LIBRARY[i][2])),'CERT-FRONT/REAR-COND'

def lead_motion(ego,lead):
    return Motion(ego.lx,ego.lv,0,4800000,max(0,500000-ego.t),-4*S if lead=='braking' else 0)

@lru_cache(maxsize=4096)
def select(ego,lead,phase=0):
    # Early-out equals b7_select because library enumeration has A3 order.
    for cid in range(16):
        if not LIBRARY[cid][1]:continue
        tr=b4_mrmgen(ego.x,ego.v,ego.a,cid,phase)
        if b3_geom(tr,(lead_motion(ego,lead),)).accept:return cid,'CERT-FRONT/REAR-COND'
    return 15,'MITIGATION'

@dataclass(frozen=True)
class Certificate:
    snapshot: str
    trajectory: str
    t_a: int
    t_e: int
    capability: int = 1
    config: int = 1
    controller: int = 1
    scope: int = 1
    context: str = ''
    seal: str = ''

def cert_seal(c):
    return digest(pack_certificate(c,include_seal=False))

def context_digest(objects=(),lane=(-1800000,1800000)):
    return digest(pack_context(objects,lane))

def certify(p,expiry,objects=(),lane=(-1800000,1800000)):
    c=Certificate(digest(pack_ego(p.snapshot)),digest(pack_plan(p)),p.apply,expiry,
                  context=context_digest(objects,lane))
    return replace(c,seal=cert_seal(c))

def b9_cert(p,c,now,at_executor=False,issued=None,ack=False,expected_seq=None,expected_context=None,phase_reuse=False):
    if p is None or c is None:return 'timeout'
    if any(type(v) is not int or not 0<=v<=MASK for v in (now,c.t_a,c.t_e,p.seq,p.generated)):
        return 'range_schema'
    if (c.seal!=cert_seal(c) or c.snapshot!=digest(pack_ego(p.snapshot)) or c.trajectory!=digest(pack_plan(p))
            or c.t_a!=p.apply or (c.capability,c.config,c.controller,c.scope)!=(1,1,1,1)):return 'binding'
    if expected_seq is not None and p.seq!=expected_seq:return 'replay'
    if expected_context is not None and c.context!=expected_context:return 'context_binding'
    # Config1 is the short .5s P5 lease. A seal is binding, not authority to
    # extend a snapshot's validity. Executor/backup reuse retains original ta.
    if not 0<elapsed(c.t_e,p.generated)<=500000:return 'lease_bound'
    remaining=elapsed(c.t_e,now)
    if at_executor:
        if remaining<=0:return 'expiry_at_executor'
        if issued is not None and elapsed(now,issued)>=40000 and not ack:return 'ack_timeout'
        return 'committed' if ack and elapsed(now,p.apply)>=0 else 'pending'
    if not phase_reuse and elapsed(p.apply,now)<0:return 'late_apply'
    if remaining<=20000 or elapsed(c.t_e,p.apply)<=20000:return 'expiry'
    return 'ok'

@dataclass(frozen=True)
class Supervisor:
    mode: str = 'L3'
    good: int = 0
    backup: tuple = ()
    pending: tuple = ()
    ingress: Ingress = Ingress()
    fault_latched: bool = False
    events: tuple = ()
    events_lost: int = 0

def b8_fsm(state,accept,v,reusable=False,fallback=True,capability=True,reset=False,health=True):
    if reset or not health:
        return replace(state,mode='HOLD' if v==0 else 'L3',good=0,pending=(),backup=(),fault_latched=True)
    if accept:
        good=min(3,state.good+1)
        return replace(state,good=good,mode='L0' if good==3 else 'RECOVERY',fault_latched=False)
    mode='HOLD' if v==0 else 'L1' if reusable and capability else 'L2' if fallback and capability else 'L3'
    return replace(state,mode=mode,good=0,pending=(),fault_latched=True)

@dataclass(frozen=True)
class Recorder:
    events: tuple = ()
    lost: int = 0
    capacity: int = 64

def b10_rec(state,event):
    if not 1<=state.capacity<=1024:raise ValueError('capacity')
    if not (isinstance(event,tuple) and len(event)<=4 and all(
            type(v) is int and -(1<<63)<v<(1<<63) or isinstance(v,str) and len(v)<=32 for v in event)):
        return replace(state,lost=min(MASK,state.lost+1))
    events=state.events+(event,)
    return Recorder(events[-state.capacity:],min(MASK,state.lost+int(len(events)>state.capacity)),state.capacity)

def b13_health(words=(),parities=(),lane_pair=(True,True),fsm_onehot=1,bist=True):
    if len(words)!=len(parities) or any(type(w) is not int or not 0<=w<=MASK for w in words):return False
    if any((w.bit_count()&1)!=p for w,p in zip(words,parities)):return False
    if lane_pair[0]!=lane_pair[1] or not (0<fsm_onehot<64 and fsm_onehot&(fsm_onehot-1)==0):return False
    if bist:
        tr=b4_mrmgen(0,S,0,0)
        if not tr.accept or tr.stop!=1100000 or tr.rows[-1]!=(3100000,766660,766670,0,0,0,0):return False
        clear=b3_geom(tr,(Motion(20*S,0),))
        blocked=b3_geom(tr,(Motion(4*S,0),))
        if not clear.accept or blocked.accept:return False
    return True

def reaction_safe(ego,rear_ftti=1<<30):
    if rear_ftti<=285000:return False
    # Conservative coast .285 then brake8, front brakes4 immediately.
    xh,vh=advance(ego.x,ego.v,0,285000,True)
    ll,lv=advance(ego.lx,ego.lv,-4*S,285000)
    return (swept(ego.lx-ego.x-4800000,ego.lv,-4*S,ego.v,0,285000)>=500000
            and swept(ll-xh-4800000,lv,-4*S,vh,-8*S,3000000)>=500000)

def phase_state(p,when):
    h=elapsed(when,p.apply)
    if h<0:return p.x,p.v
    x,v=p.x,p.v
    # Continuous B4 replay at the ORIGINAL epoch; no timestamp refresh.
    for t in range(0,min(h,12800000),20000):
        step=min(20000,h-t)
        b,j,_=LIBRARY[p.tail]
        a=p.a if t<DT else profile_a(p.tail,t-DT,p.a)
        signed=0 if t<DT or a==-b else -j if a>-b else j
        if not j and t>=DT:a=-b
        x,v=continuous_advance(x,v,a,signed,-b,step)
    return x,v

def reusable(state,now,ego):
    if not state.backup:return False
    p,c=state.backup
    phase=elapsed(now,p.apply)
    if phase<0:return False
    if b9_cert(p,c,now,phase_reuse=True)!='ok' or elapsed(c.t_e,now)<=120000:return False
    px,pv=phase_state(p,now)
    # n floors in v contribute <= h*n*(n-1)/2 to x, in addition to n x
    # floors and <=11 LSB at the single clipped stop. Keep the existing640
    # minimum for ordinary short leases; bound long imported phases too.
    n=min(640,ceildiv(phase,20000))
    x_error=max(640,n+ceildiv(20000*n*(n-1),2*T)+11)
    return abs(ego.x-px)+50000+x_error<=160000 and abs(ego.v-pv)+50000+640<=200000

def nominal_geom(p,lead):
    if p is None:return False
    snap=p.snapshot; delay=max(0,elapsed(p.apply,snap.t))
    if delay>500000:return False
    lm=lead_motion(snap,lead)
    # Split actor's braking event before apply.
    first=min(delay,lm.event)
    lx,lv=advance(lm.x,lm.v,lm.a,first)
    lx,lv=advance(lx,lv,lm.after_a,delay-first)
    tr=b4_mrmgen(p.x,p.v,p.a,15)
    obj=Motion(lx,lv,lm.a,lm.length,max(0,lm.event-delay),lm.after_a)
    return b3_geom(tr,(obj,)).accept

def plan_tail(p,lead):
    """Certify the tail in APPLY coordinates, including delay before its prefix."""
    snap=p.snapshot;delay=max(0,elapsed(p.apply,snap.t))
    if delay>100000:return 15,'MITIGATION'
    lm=lead_motion(snap,lead);first=min(delay,lm.event)
    lx,lv=advance(lm.x,lm.v,lm.a,first)
    lx,lv=advance(lx,lv,lm.after_a,delay-first)
    return select(Ego(p.apply,p.x,p.v,p.a,lx,lv),lead)

def propagated_objects(objects,delay,ego_x):
    result=[]
    for o in objects:
        h=min(delay,o.event)
        upper=o.x<ego_x
        x,v=advance(o.x,o.v,o.a,h,upper)
        x,v=advance(x,v,o.after_a,delay-h,upper)
        result.append(replace(o,x=x,v=v,event=max(0,o.event-delay)))
    return tuple(result)

def select_world(ego,objects,lane):
    for cid in range(16):
        if LIBRARY[cid][1] and b3_geom(b4_mrmgen(ego.x,ego.v,ego.a,cid),objects,lane).accept:
            return cid,'CERT-FRONT/REAR-COND'
    return 15,'MITIGATION'

def live_ego_valid(now,ego):
    """Supervisor requires a state estimate projected to its decision epoch.

    Dated measurements may be checked by B2 directly, but are not a live state
    from which to publish a new MRM or verify a running backup. Missing/invalid
    live ego is a WORLD/ego fault, distinct from a rejected planner snapshot.
    """
    if type(now) is not int or not 0<=now<=MASK or not isinstance(ego,Ego):return False
    values=(ego.t,ego.x,ego.v,ego.a,ego.lx,ego.lv)
    if any(type(v) is not int or not -(1<<63)<v<(1<<63) for v in values):return False
    return (ego.t==now and abs(ego.x)<=10000*S and abs(ego.lx)<=10000*S
            and 0<=ego.v<=10*S and 0<=ego.lv<=10*S and -8*S<=ego.a<=0)

def tsmx_cycle(state,inputs):
    """Pure 100ms supervisor transaction. Executor delivery is an explicit input.

    now/ego/pkt/cert/lead, capability, rear_ftti, reset, health and ack.
    ack applies to the previously issued immutable pending plan, before admission.
    """
    now=inputs['now'];ego=inputs['ego'];pkt=inputs.get('pkt');c=inputs.get('cert')
    live_ok=live_ego_valid(now,ego)
    clock_bad=live_ok and state.ingress.last_time>=0 and elapsed(now,state.ingress.last_time)<0
    if not live_ok or clock_bad:
        reason='clock_reset' if clock_bad else 'ego_live'
        # Unknown live speed cannot justify HOLD. Force the independent L3
        # brake path and discard every certificate before any geometry/hash work.
        state=b8_fsm(state,False,S,capability=False,health=False)
        if type(now) is int and 0<=now<=MASK:
            state=replace(state,ingress=replace(state.ingress,last_time=now))
        rec=b10_rec(Recorder(state.events,state.events_lost),(now,reason,'L3',15))
        state=replace(state,events=rec.events,events_lost=rec.lost)
        return state,dict(accept=False,reason=reason,mode='L3',candidate=15,label='MITIGATION',
                          independent_brake=True,commit=reason,heartbeat=False)
    explicit_world='objects' in inputs or 'lane' in inputs
    objects=tuple(inputs.get('objects',()))
    lane=inputs.get('lane',(-1800000,1800000))
    context=context_digest(objects,lane)
    effective_objects=objects if 'objects' in inputs else (lead_motion(ego,inputs.get('lead','stationary')),)
    cap=inputs.get('capability',True)
    health=inputs.get('health',True) and b13_health(**inputs.get('health_inputs',{}))
    commit='no_pending'
    if state.pending:
        issued,p,old=state.pending
        commit=b9_cert(p,old,now,True,issued,inputs.get('ack',False),p.seq)
        if commit=='committed':state=replace(state,backup=(p,old),pending=())
        elif commit!='pending':state=replace(state,pending=())
    ing,reason=b1_ingress(state.ingress,now,ego,pkt)
    p=pkt.plan if pkt else None
    if reason=='ok':reason=b9_cert(p,c,now,expected_context=context)
    if reason=='ok' and not b2_splice(ego,p):reason='splice'
    if reason=='ok' and not reaction_safe(ego,inputs.get('rear_ftti',1<<30)):reason='ftti_budget'
    if reason=='ok' and not nominal_geom(p,inputs.get('lead','stationary')):reason='geometry'
    if not cap:reason='capability'
    if not health:reason='health'
    if inputs.get('reset'):reason='reset'
    cid,label=(select_world(ego,effective_objects,lane) if explicit_world else select(ego,inputs.get('lead','stationary')))
    tail=15
    if reason=='ok':
        if explicit_world:
            delay=max(0,elapsed(p.apply,ego.t))
            xl,vl=advance(ego.x,ego.v,ego.a,delay)
            xh,vh=advance(ego.x,ego.v,ego.a,delay,True)
            bridge=Trajectory(True,((0,ego.x,ego.x,ego.v,ego.v,ego.a,0),
                                    (delay,xl,xh,vl,vh,ego.a,0)),-1,'bridge')
            bridge_ok=delay==0 or b3_geom(bridge,effective_objects,lane).accept
            future=propagated_objects(effective_objects,delay,ego.x)
            tail,_=select_world(Ego(p.apply,p.x,p.v,p.a,ego.lx,ego.lv),future,lane)
            if not bridge_ok:tail=15
        else:tail,_=plan_tail(p,inputs.get('lead','stationary'))
        if tail==15:reason='no_backup'
    ok=reason=='ok'
    reuse=reusable(state,now,ego) and cap and health
    state=b8_fsm(state,ok,ego.v,reuse,cid!=15,cap,inputs.get('reset',False),health)
    if ok:
        # Seal actual mild tail before publishing; mitigation is never a backup.
        pp=replace(p,tail=tail)
        state=replace(state,ingress=ing,pending=(now,pp,certify(pp,c.t_e,objects,lane)) if tail!=15 else ())
    else:state=replace(state,ingress=replace(state.ingress,last_time=now))
    rec=b10_rec(Recorder(state.events,state.events_lost),(now,reason,state.mode,cid))
    state=replace(state,events=rec.events,events_lost=rec.lost)
    return state,dict(accept=ok,reason=reason,mode=state.mode,candidate=cid,label=label,
                      independent_brake=not ok,commit=commit,heartbeat=health)
