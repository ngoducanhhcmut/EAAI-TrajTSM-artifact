"""Spec 5.5.11/9.2 B13 semantic and legacy conversion; independent golden oracle."""
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
    for v,w in fields:n=(n<<w)|(int(v)&((1<<w)-1))
    return n
def main():
    cases=[];sources=Counter();hashes={};cache={}
    def emit(d,src,out=None):
        # Schema preserves original Python guards before any field narrowing.
        words=d.get('words',[]);par=d.get('parities',[]);oh=d.get('fsm_onehot',1)
        lane=d.get('lane_pair',[True,True]);bist=d.get('bist',True)
        schema=(all(type(w) is int and 0<=w<=g.MASK for w in words)
                and type(oh) is int and 0<=oh<64
                and all(p in (0,1) for p in par) and len(lane)==2)
        key=json.dumps(d,sort_keys=True)
        if key not in cache:cache[key]=bool(g.b13_health(**d))
        exp=cache[key]
        if out is not None:assert out['healthy']==exp,(src,d,out,exp)
        if len(words)>1024 or len(par)>1024:schema=False
        req=pack([(schema,1),(min(len(words),2047),11),(min(len(par),2047),11)]
                 +[(w,32) for w in words[:1024]]+[(0,32)]*max(0,1024-len(words))
                 +[(p,1) for p in par[:1024]]+[(0,1)]*max(0,1024-len(par))
                 +[(bool(lane[0]),1),(bool(lane[1]),1),(oh,6),(bist,1)])
        expected=exp and schema and len(words)<=1024 and len(par)<=1024
        cases.append((req,expected,src));sources[src]+=1
    for name in ['b13.ports.jsonl','edges.ports.jsonl']:
        p=HW/'vectors'/name;hashes[name]=hashlib.sha256(p.read_bytes()).hexdigest()
        for line in p.read_text().splitlines():
            f=json.loads(line)
            if name.startswith('edges') and f['block']!='b13':continue
            emit(f['input'],'edge' if name.startswith('edges') else 'golden',f['output'])
    meta=json.loads((HW/'vectors/b13.json').read_text())
    for line in (HW/'vectors/b13.hex').read_text().splitlines():
        word=int(line,16);vals=[]
        for f in meta['fields']:
            v=(word>>f['lsb'])&((1<<f['bits'])-1)
            if f['signed'] and v>>(f['bits']-1):v-=1<<f['bits']
            vals.append(v)
        full,_=legacy.evaluate("b13",vals[:9]);assert vals[9:]==full
        seq,fault=vals[8],vals[7]
        # Same canonical conversion as SEL: fixture metadata drives extraction.
        exp=g.b13_health((seq,),(seq.bit_count()&1,),fsm_onehot=3 if fault%2 else 1)
        assert vals[9]==exp
        emit(dict(words=[seq],parities=[seq.bit_count()&1],fsm_onehot=3 if fault%2 else 1),'legacy')
    for oh in range(64):emit(dict(fsm_onehot=oh,bist=False),'directed')
    for lp in [[0,0],[1,1],[0,1],[1,0]]:emit(dict(lane_pair=lp,bist=False),'directed')
    for n in [0,1,2,31,32,1023,1024,1025]:
        for mismatch in [False,True]:
            w=[0xffffffff]*n;p=[0]*n
            if mismatch:p=p+[0]
            emit(dict(words=w,parities=p,bist=False),'boundary')
    for w in [-(1<<63),-(1<<31),-1,0,1,0x7fffffff,0x80000000,0xffffffff,1<<32,(1<<63)-1]:
        for p in [0,1,2,-1]:emit(dict(words=[w],parities=[p],bist=False),'boundary')
    for oh in [-1,64,65,1<<32]:emit(dict(fsm_onehot=oh,bist=False),'boundary')
    rng=random.Random(1113)
    for i in range(2200):
        n=rng.choice([0,1,2,7,31,32,127,1023,1024])
        w=[rng.getrandbits(32) for _ in range(n)];p=[v.bit_count()&1 for v in w]
        oh=1<<rng.randrange(6);lp=[1,1]
        kind=i%7
        if kind==1 and n:p[rng.randrange(n)]^=1
        if kind==2:p.append(0)
        if kind==3:oh=rng.randrange(64)
        if kind==4:lp=[0,1]
        if kind==5 and n:w[rng.randrange(n)]=1<<32
        emit(dict(words=w,parities=p,fsm_onehot=oh,lane_pair=lp,bist=False),'random')
    for n in [0,1024]:
        emit(dict(words=[0]*n,parities=[0]*n,bist=True),'budget')
    (HERE/'jobs.mem').write_text(''.join(f'{pack([(r,33824),(e,1)]):08457x}\n' for r,e,_ in cases))
    (HERE/'vectors_meta.svh').write_text(f'localparam N={len(cases)};\n')
    (HERE/'vectors.json').write_text(json.dumps(dict(total=len(cases),sources=sources,sha256=hashes,seed=1113),indent=2)+'\n')
    # Retain independently generated subresource records for injected BIST faults.
    tr=g.b4_mrmgen(0,g.S,0,0)
    rows=[int.from_bytes(g.pack_row(r),'big') for r in tr.rows]
    traj=pack([(tr.accept,1),(0,8),(tr.stop>=0,1),(tr.stop,32),(len(rows),8)]
              +[(r,352) for r in rows]+[(0,352)]*(129-len(rows)))
    (HERE/'bist.mem').write_text(f'{traj:011365x}\n')
    print(json.dumps(dict(total=len(cases),sources=sources)))
if __name__=='__main__':main()
