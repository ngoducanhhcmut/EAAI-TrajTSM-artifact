"""TSM-X / TSMX project / v0.1. Golden-derived REQ-TSMX-005 fixtures."""
import sys
sys.dont_write_bytecode = True
import json, random, hashlib
from dataclasses import replace
from pathlib import Path
HERE = Path(__file__).resolve().parent
HW = HERE.parents[2]
sys.path[:0] = [str(HW/'golden'), str(HW.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g
import vectors as conversion

def objects(inp):
    e = g.Ego(**inp['ego'])
    p = dict(inp['plan']); p['snapshot'] = g.Ego(**p['snapshot'])
    return e, g.Plan(**p)

def main():
    rows=[]; counts={}; digests={}
    def add(e,p,kind,expected=None):
        result=g.b2_splice(e,p)
        if expected is not None: assert result == expected
        word=int.from_bytes(g.pack_ego(e)+g.pack_plan(p),'big')
        rows.append((word,int(result),kind))
        counts[kind]=counts.get(kind,0)+1
    # Full semantic ports plus all relevant edge fixtures; no diagnostic hash substituted.
    for name in ('b2.ports.jsonl','edges.ports.jsonl'):
        path=HW/'vectors'/name;digests[name]=hashlib.sha256(path.read_bytes()).hexdigest()
        for line in path.read_text().splitlines():
            obj=json.loads(line)
            if name.startswith('edges') and obj['block']!='b2': continue
            add(*objects(obj['input']), 'edge' if name.startswith('edges') else 'golden',obj['output']['accept'])
    # Decode the accepted summary ABI with its metadata, then reuse vectors.evaluate
    # construction to recover the actual immutable B2 request.
    meta=json.loads((HW/'vectors/b2.json').read_text())
    for line in (HW/'vectors/b2.hex').read_text().splitlines():
        word=int(line,16); values=[]
        for fld in meta['fields']:
            val=(word>>fld['lsb'])&((1<<fld['bits'])-1)
            if fld['signed'] and val>>(fld['bits']-1): val-=1<<fld['bits']
            values.append(val)
        x,v,a,ox,ov,now,cid,fault,seq=values[:9]
        out,_=conversion.evaluate('b2',values[:9])
        assert out==values[9:]
        e=g.Ego(now,x,v,a,ox,ov); px,pv=g.advance(x,v,a,g.DT)
        p=g.Plan(seq,e,now,(now+g.DT)&g.MASK,px+(200000 if fault%2 else 0),pv,a)
        add(e,p,'hex',bool(values[9]))
    rng=random.Random(0x5253504c)
    def nominal(x=0,v=1000000,a=0,t=0,h=100000):
        e=g.Ego(t,x,v,a,30000000,0)
        px,pv=g.advance(x,v,a,h)
        return e,g.Plan(1,e,t,(t+h)&g.MASK,px,pv,a)
    # FORMATS endpoints, both sentinels, range +/-1, serial wrap/half-wrap.
    e,p=nominal()
    for fld,vals in {'x':[-(1<<63),-(1<<63)+1,-10000000001,-10000000000,10000000000,10000000001,(1<<63)-1],
                     'v':[-(1<<31),-1,0,1,49999,50000,50001,10000000,10000001,(1<<31)-1],
                     'a':[-(1<<31),-8000001,-8000000,-7999999,-100001,-100000,-1,0,1,1900000,1999999,2000000,2000001,(1<<31)-1]}.items():
        for val in vals:
            add(replace(e,**{fld:val}),p,'boundary')
            add(e,replace(p,**{fld:val}),'boundary')
    for t in (0,1,0x7fffffff,0xfffffff0,0xffffffff):
        for h in (-1,0,1,99999,100000,100001,0x7fffffff,0x80000000):
            ee,pp=nominal(t=t,h=0)
            add(ee,replace(pp,apply=(t+h)&g.MASK),'boundary')
    # Stop clipping, v=0 clamps, acceleration clamps, directed division residues.
    for v in (0,1,49999,50000,50001,100000,799999,800000,800001,10000000):
        for a in (0,-1,-100000,-7999999,-8000000,1,100000,1950000,2000000):
            for h in (0,1,99999,100000):
                ee,pp=nominal(v=v,a=a,h=h,t=0xfffffff0)
                add(ee,pp,'directed')
    # Exact equality and +/-1 at every reachable tube constraint.
    for _ in range(150):
        ee,pp=nominal(v=rng.randrange(10000001),a=-rng.randrange(8000001),h=rng.randrange(100001))
        points=[g.advance(ee.x+dx,max(0,ee.v+dv),min(2000000,max(-8000000,ee.a+da)),g.elapsed(pp.apply,ee.t),up)
                for dx in (-50000,50000) for dv in (-50000,50000) for da in (-100000,100000) for up in (False,True)]
        for fld,idx,tube in [('x',0,160000),('v',1,200000)]:
            for bound in (min(z[idx] for z in points)+tube,max(z[idx] for z in points)-tube):
                for delta in (-1,0,1): add(ee,replace(pp,**{fld:bound+delta}),'equality')
    for i in range(2400):
        ee,pp=nominal(x=rng.randrange(-10000000000,10000000001),v=rng.randrange(10000001),
                      a=-rng.randrange(8000001),t=rng.getrandbits(32),h=rng.randrange(100001))
        pp=replace(pp,x=pp.x+rng.randrange(-200001,200002),v=pp.v+rng.randrange(-250001,250002))
        if i%7==0: pp=replace(pp,apply=(ee.t+rng.choice([-1,100001,0x80000000]))&g.MASK)
        # Ignored metadata must not change B2's result, including snapshots and schema.
        if i%11==0: pp=replace(pp,seq=rng.getrandbits(32),schema=rng.getrandbits(32),tail=255)
        add(ee,pp,'random')
    # A8 (02/11): random positive ego/plan acceleration after the legacy stream
    rng2=random.Random(0x41385053)
    for i in range(800):
        ee,pp=nominal(x=rng2.randrange(-10000000000,10000000001),v=rng2.randrange(10000001),
                      a=rng2.randrange(1,2000001),t=rng2.getrandbits(32),h=rng2.randrange(100001))
        pp=replace(pp,x=pp.x+rng2.randrange(-200001,200002),v=pp.v+rng2.randrange(-250001,250002),a=rng2.randrange(-8000000,2000001))
        add(ee,pp,'random_apos')
    (HERE/'vectors.mem').write_text(''.join(f'{((w<<1)|v):0205x}\n' for w,v,_ in rows))
    (HERE/'vectors_meta.svh').write_text(f'localparam N={len(rows)}, GOLDEN={counts["golden"]}, EDGES={counts["edge"]}, HEX={counts["hex"]};\n')
    (HERE/'vectors.json').write_text(json.dumps(dict(seed='0x5253504c',total=len(rows),counts=counts,accept=sum(v for _,v,_ in rows),sha256=digests),indent=2)+'\n')
    print(json.dumps(dict(total=len(rows),counts=counts)))
if __name__=='__main__': main()
