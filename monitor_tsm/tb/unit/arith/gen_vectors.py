"""Golden-derived primitive vectors, plus complete B2/B3/B4 fixture call traces.

Run from any directory: py -3.13 -B gen_vectors.py. Never writes golden fixtures.
The contract guard is independent of the arithmetic result oracle (golden model).
"""
import sys, json, random, inspect, functools, hashlib
from collections import Counter
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
sys.path[:0]=[str(HW/'golden'),str(HW.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g

NAMES=('checked','ceildiv','disp','advance','swept','profile_a','ramp_integrals','continuous_advance','elapsed')
ORIG={n:getattr(g,n) for n in NAMES}
SIZES=(2,2,5,5,6,3,5,7,2)
seen={}; sources=Counter(); counts=Counter(); fixture_counts=Counter()

def fits(v,b): return -(1<<(b-1))<v<(1<<(b-1))
def motion(v,a): return 0<=v<=20*g.S and -8*g.S<=a<=2*g.S
def legal(op,q):
    if op not in range(9) or any(q[SIZES[op]:]): return False
    if op==0:return 1<=q[1]<=160 and fits(q[0],q[1])
    if op==1:return fits(q[0],160) and 0<q[1]<(1<<159)
    if op==2:return motion(*q[:2]) and 0<=q[2]<(1<<46) and 0<q[3]<(1<<24) and q[4] in (0,1)
    if op==3:return fits(q[0],64) and motion(*q[1:3]) and 0<=q[3]<=12800000 and q[4] in (0,1)
    if op==4:return fits(q[0],64) and motion(*q[1:3]) and motion(*q[3:5]) and 0<=q[5]<=12800000
    if op==5:return 0<=q[0]<16 and fits(q[1],32) and -8*g.S<=q[2]<=2*g.S  # A8 (02/11): op5 initial a in [-8,+2] (golden profile_a)
    if op==6:return motion(*q[:2]) and -8*g.S<=q[2]<=8*g.S and -8*g.S<=q[3]<=2*g.S and 0<=q[4]<=g.DT
    if op==7:return fits(q[0],64) and motion(*q[1:3]) and -8*g.S<=q[3]<=8*g.S and -8*g.S<=q[4]<=2*g.S and 0<=q[5]<=g.DT and q[6] in (0,1)
    return all(0<=v<=g.MASK for v in q[:2])

def emit(op,q,source='random',result=None):
    q=tuple(map(int,q))+(0,)*(12-len(q)); key=(op,q)
    if key in seen:return
    fault=not legal(op,q); out=()
    if not fault:
        try:
            out=ORIG[NAMES[op]](*q[:SIZES[op]]) if result is None else result
            out=out if isinstance(out,tuple) else (out,)
            if not all(fits(v,160) for v in out):fault=True
            if op in (2,4) and not fits(out[0],64):fault=True
            if op in (3,7) and not (fits(out[0],64) and fits(out[1],32)):fault=True
        except (ValueError,AssertionError,IndexError):fault=True
    out=(0,)*4 if fault else tuple(out)+(0,)*(4-len(out))
    req=op
    for v in q:req=(req<<160)|(v&((1<<160)-1))
    rsp=int(fault)
    for v in out:rsp=(rsp<<160)|(v&((1<<160)-1))
    seen[key]=(req<<641)|rsp
    sources[source]+=1; counts[str(op)]+=1

def trace_helpers():
    for op,name in enumerate(NAMES):
        original=ORIG[name]; sig=inspect.signature(original)
        @functools.wraps(original)
        def wrapped(*args,_fn=original,_sig=sig,_op=op,**kwargs):
            bound=_sig.bind(*args,**kwargs);bound.apply_defaults()
            vals=tuple(bound.arguments.values())
            result=_fn(*args,**kwargs)
            if all(type(v) in (int,bool) for v in vals) and not (_op==0 and vals[1]>160):
                emit(_op,vals,'fixture_helper',result)
            return result
        setattr(g,name,wrapped)

def run_fixture(block,row):
    d=dict(row['input']); expected=row['output']
    if block=='b2':
        e=g.Ego(**d['ego']);pd=dict(d['plan']);pd['snapshot']=g.Ego(**pd['snapshot'])
        actual={'accept':g.b2_splice(e,g.Plan(**pd))}
    elif block=='b3':
        td=dict(d.pop('traj'));td['rows']=tuple(tuple(r) for r in td['rows']);d['traj']=g.Trajectory(**td)
        d['objects']=tuple(g.Motion(**o) for o in d['objects'])
        actual=g.asdict(g.b3_geom(**d))
    else:actual=g.asdict(g.b4_mrmgen(**d))
    assert json.loads(json.dumps(actual))=={k:expected[k] for k in actual},(block,row.get('index',row.get('name')))
    fixture_counts[block]+=1

def main():
    rng=random.Random(0x5254534D)
    # Explicit signed-width endpoints, numeric sentinels and checked narrowing.
    for bits in (1,2,8,10,11,13,24,32,33,46,64,88,96,112,128,136,160):
        for v in (-(1<<(bits-1))-1,-(1<<(bits-1)),-(1<<(bits-1))+1,-1,0,1,(1<<(bits-1))-1,1<<(bits-1)):
            if -(1<<159)<=v<(1<<159):emit(0,(v,bits),'boundary')
    for n in (-(1<<159),-(1<<159)+1,-(1<<127)+1,-7,-1,0,1,7,(1<<159)-1):
        for d in (-1,0,1,2,3,(1<<95)-1,(1<<135)-1,(1<<159)-1):emit(1,(n,d),'boundary')
    for x in (-(1<<63),-(1<<63)+1,-10070000000,0,10070000000,(1<<63)-1):
        for v in (0,1,10000000,20000000):
            for a in (-8000000,0,2000000):
                for up in (0,1):emit(3,(x,v,a,12800000,up),'boundary')
    for cid in range(16):
        for t in (-2147483648,-2147483647,-1,0,1,100000,12800000,2147483647):
            for a in (-8000000,0,1,2000000,2000001):emit(5,(cid,t,a),'boundary')
    for a in (0,g.MASK,1<<31):
        for b in (0,g.MASK,1<<31):emit(8,(a,b),'boundary')
    # Each opcode receives >=2,000 random trials; paired rounding exercises both sides.
    for k in range(2200):
        x=rng.randint(-10070000000,10070000000);v=rng.randint(0,20000000)
        a=rng.randint(-8000000,2000000);h=rng.randint(0,100000);j=rng.choice((-8000000,-4000000,-2000000,0,2000000,4000000,8000000));target=rng.randint(-8000000,0)
        bits=rng.choice((32,64,96,128,160)); val=rng.randrange(-(1<<(bits-1))+1,1<<(bits-1))
        emit(0,(val,bits));emit(1,(rng.randrange(-(1<<159)+1,1<<159),rng.randrange(1,1<<136)))
        emit(2,(v,a,rng.randrange(1<<46),rng.randrange(1,1<<24),k%2))
        emit(3,(x,v,a,rng.randint(0,12800000),k%2))
        emit(4,(x,v,a,rng.randint(0,20000000),rng.randint(-8000000,2000000),rng.randint(0,12800000)))
        emit(5,(rng.randrange(16),rng.randint(-1000000,12800000),rng.randint(-8000000,0)))
        emit(6,(v,a,j,target,h));emit(7,(x,v,a,j,target,h,k%2));emit(8,(rng.randrange(1<<32),rng.randrange(1<<32)))
    # Stop brackets, capped/noncapped ramps, both directions and all endpoint velocities.
    for v in (0,1,99999,10000000,20000000):
        for a in (-8000000,-1,0,2000000):
            for j in (-8000000,0,8000000):
                for h in (0,1,99999,100000):
                    for up in (0,1):emit(7,(0,v,a,j,-2000000,h,up),'boundary')
    # Every consumed field gets width overflow, minimum, and domain violations.
    base=((1,64),(1,1),(1,0,1,1,0),(0,1,0,1,0),(0,1,0,1,0,1),(0,0,0),(1,0,0,0,1),(0,1,0,0,0,1,0),(0,0))
    for op,vals in enumerate(base):
        for i in range(SIZES[op]):
            for bad in (-(1<<159),-(1<<63),-(1<<31),(1<<31)-1,(1<<63)-1,(1<<159)-1,-1):
                q=list(vals);q[i]=bad;emit(op,q,'fault_boundary')
        q=list(vals)+[0]*(12-len(vals));q[-1]=1;emit(op,q,'padding_fault')
    for n in (0,1,(1<<46)-1,1<<46):
        for d in (0,1,(1<<24)-1,1<<24):
            for v in (0,20000000):
                for a in (-8000000,2000000):
                    for up in (0,1):emit(2,(v,a,n,d,up),'rational_boundary')
    emit(255,(),'opcode_fault')
    # Trace every helper used by the existing full semantic fixtures, deduplicated.
    trace_helpers()
    hashes={}
    for block in ('b2','b3','b4'):
        path=HW/'vectors'/f'{block}.ports.jsonl';hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
        for line in path.read_text().splitlines():run_fixture(block,json.loads(line))
    path=HW/'vectors/edges.ports.jsonl'
    hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
    for line in path.read_text().splitlines():
        row=json.loads(line)
        if row.get('block') in ('b2','b3','b4'):run_fixture(row['block'],row)
    (HERE/'vectors.mem').write_text(''.join(f'{v:0643x}\n' for v in seen.values()),encoding='ascii')
    (HERE/'vectors_meta.svh').write_text(f'localparam integer N={len(seen)};\n',encoding='ascii')
    summary=dict(total=len(seen),sources=sources,ops=counts,fixtures=fixture_counts,fixture_sha256=hashes,seed=0x5254534D)
    (HERE/'vectors.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
