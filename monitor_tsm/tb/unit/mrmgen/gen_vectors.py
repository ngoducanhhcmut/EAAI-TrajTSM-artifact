"""R6 oracle conversion. Read-only golden import; all artifacts stay beside this script."""
import sys,json,random,hashlib
from pathlib import Path
from collections import Counter
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
sys.path[:0]=[str(HW/'golden'),str(HW.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g
import vectors as legacy

def pack(fields):
    n=0
    for v,w in fields:n=(n<<w)|(v&((1<<w)-1))
    return n

def request(d):return pack((d[k],w) for k,w in zip(('x','v','a','cid','phase','limit'),(64,32,32,8,32,8)))
def response(o):return pack([(int(o.accept),1),(g.REASONS.index(o.reason),8),(int(o.stop>=0),1),(max(0,o.stop),32),(len(o.rows),8)])
def rowpack(d,k,row,last):
    # Golden pack_row is 288 bits, pack_trajectory zero-extends it into a 352-bit slot.
    raw=int.from_bytes(g.pack_row(row),'big')
    return pack([(d['cid'],8),(d['phase'],32),(k,8),(raw,352),(last,1)])

def main():
    cases=[];sources=Counter();reasons=Counter();hashes={}
    def emit(d,source,fixture=None):
        d=dict(phase=0,limit=128,**d) if 'phase' not in d and 'limit' not in d else dict(d)
        d.setdefault('phase',0);d.setdefault('limit',128)
        o=g.b4_mrmgen(**d)
        if fixture is not None:
            assert json.loads(json.dumps(g.asdict(o)))==fixture,(source,d)
        cases.append((d,o));sources[source]+=1;reasons[o.reason]+=1
    path=HW/'vectors/b4.ports.jsonl';hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
    for line in path.read_text().splitlines():
        f=json.loads(line);emit(f['input'],'golden',f['output'])
    path=HW/'vectors/edges.ports.jsonl';hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
    for line in path.read_text().splitlines():
        f=json.loads(line)
        if f['block']=='b4':emit(f['input'],'edge',f['output'])
    # Legacy hex is independently converted with accepted vectors.evaluate.
    meta=json.loads((HW/'vectors/b4.json').read_text());offsets=meta['fields']
    for line in (HW/'vectors/b4.hex').read_text().splitlines():
        word=int(line,16);vals=[]
        for f in offsets:
            v=(word>>f['lsb'])&((1<<f['bits'])-1)
            if f['signed'] and v>>(f['bits']-1):v-=1<<f['bits']
            vals.append(v)
        exp,_=legacy.evaluate('b4',vals[:9]);assert vals[9:]==exp
        x,v,a,ox,ov,now,cid,fault,seq=vals[:9]
        emit(dict(x=x,v=v,a=a,cid=cid),'legacy')
    # Every library entry, upward/downward ramp, stop bracket, parking, partial horizon.
    for cid in range(16):
        # A8 (02/11): positive start acceleration, incl. standstill creep under a>0
        for v,a in [(0,0),(1,0),(10000000,0),(10000000,-8000000),(99999,-1),(10000000,2000000),(0,2000000),(0,1),(99999,1999999)]:
            emit(dict(x=10000000000,v=v,a=a,cid=cid),'directed')
    # FORMATS extrema and just-outside admission; physical ports cannot encode s64 adapter NaN.
    for key,values in dict(x=[-(1<<63),-(1<<63)+1,-10000000001,-10000000000,10000000000,10000000001,(1<<63)-1],v=[-(1<<31),-1,0,1,10000000,10000001,(1<<31)-1],a=[-(1<<31),-8000001,-8000000,-1,0,1,(1<<31)-1],cid=[0,15,16,255],phase=[0,1,99999,100000,12800000,12800001,0xffffffff],limit=[0,1,20,21,128,129,255]).items():
        for value in values:
            d=dict(x=0,v=10000000,a=-8000000,cid=0,phase=0,limit=128);d[key]=value
            emit(d,'boundary')
    rng=random.Random(6006)
    for i in range(2200):
        d=dict(x=rng.randrange(-10000000000,10000000001),v=rng.randrange(10000001),a=-rng.randrange(8000001),cid=i%16,phase=rng.randrange(129)*100000,limit=rng.choice([1,2,3,21,64,128]))
        if i%9==0:d[rng.choice(['v','a','cid','phase','limit'])]=0xffffffff if i%2 else 255
        # Pack and re-decode malformed values to the actual physical-port integer meaning.
        for key,width,signed in [('x',64,True),('v',32,True),('a',32,True),('phase',32,True),('cid',8,False),('limit',8,False)]:
            value=d[key]&((1<<width)-1)
            d[key]=value-(1<<width) if signed and value>>(width-1) else value
        emit(d,'random')
    # A8 (02/11): random positive start acceleration (0, +2] m/s^2 after the legacy stream
    rng=random.Random(6008)
    for i in range(800):
        emit(dict(x=rng.randrange(-10000000000,10000000001),v=rng.choice([0,10000000,rng.randrange(10000001)]),a=rng.randrange(1,2000001),cid=i%16,phase=rng.randrange(129)*100000,limit=rng.choice([1,2,3,21,64,128])),'random_apos')
    rows=[];jobs=[]
    for d,o in cases:
        start=len(rows)
        for k,row in enumerate(o.rows):rows.append(rowpack(d,k,row,int(o.accept and k==len(o.rows)-1)))
        jobs.append((request(d)<<114)|(response(o)<<64)|(start<<32)|len(o.rows))
    (HERE/'jobs.mem').write_text(''.join(f'{w:073x}\n' for w in jobs))
    (HERE/'rows.mem').write_text(''.join(f'{w:0101x}\n' for w in rows))
    (HERE/'vectors_meta.svh').write_text(f'localparam N={len(jobs)}, R={len(rows)}, GOLDEN={sources["golden"]}, EDGE={sources["edge"]};\n')
    data=dict(total=len(jobs),rows=len(rows),sources=sources,reasons=reasons,seed=6006,sha256=hashes)
    (HERE/'vectors.json').write_text(json.dumps(data,indent=2)+'\n');print(json.dumps(data,indent=2))
if __name__=='__main__':main()
