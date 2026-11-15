"""REQ-TSMX-010/020 oracle conversion; run from any directory, no golden writes."""
# Project: TSM-X; Author: TSMX project; Version: 0.1.
import sys
sys.dont_write_bytecode = True
import json, random, hashlib
from pathlib import Path
from dataclasses import replace, asdict
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(ROOT/'golden'), str(ROOT.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g
import vectors as fixtures

def plan(d):
    return None if d is None else g.Plan(**{**d, 'snapshot': g.Ego(**d['snapshot'])})

def pack(p,c,now=0,at_executor=False,issued=None,ack=False,expected_seq=None,
         expected_context=None,phase_reuse=False):
    # Same vector conversion as SEL: semantic fields, not fixture hex offsets.
    fields = [(p is not None,1),(g._nested(g.pack_plan(p),560)[0] if p else 0,560),
              (g._nested(g.pack_certificate(c),1217)[0],1217),(now,32),
              (at_executor,1),(issued is not None,1),(issued or 0,32),(ack,1),
              (expected_seq is not None,1),(expected_seq or 0,32),
              (expected_context is not None,1),(int(expected_context or '0',16),256),
              (phase_reuse,1),(int(g.digest(g.pack_ego(p.snapshot)),16) if p else 0,256),
              (int(g.digest(g.pack_plan(p)),16) if p else 0,256),
              (int(g.cert_seal(c),16) if c else 0,256)]
    n=0
    for v,w in fields: n=(n<<w)|(int(v)&((1<<w)-1))
    assert n.bit_length()<=2904
    return n

jobs=[]; counts={}; reasons={}; adapter=[]
def add(p,c,group='extra',name='',expected=None,local_flip=None,**kw):
    reason=g.b9_cert(p,c,**kw)
    if expected is not None: assert reason==expected,(name,reason,expected)
    for v in [kw['now']]+([c.t_a,c.t_e,p.seq,p.generated] if p and c else []):
        if type(v) is not int or not 0<=v<=g.MASK:
            assert reason=='range_schema'; adapter.append(name); return
    word=pack(p,c,**kw)
    if local_flip is not None:
        word ^= 1<<local_flip
        reason='binding' # bad trusted-local result is a binding mismatch
    jobs.append((word,g.REASONS.index(reason),name or group))
    counts[group]=counts.get(group,0)+1; reasons[reason]=reasons.get(reason,0)+1

def main():
    ports=[json.loads(l) for l in (ROOT/'vectors/b9.ports.jsonl').read_text().splitlines()]
    meta=json.loads((ROOT/'vectors/b9.json').read_text())
    hexes=(ROOT/'vectors/b9.hex').read_text().splitlines()
    assert len(ports)==len(hexes)==meta['n']
    for r,h in zip(ports,hexes):
        decoded={f['name']:(int(h,16)>>f['lsb'])&((1<<f['bits'])-1) for f in meta['fields']}
        row=[decoded[k] if not s else decoded[k]-(1<<w) if decoded[k]>>(w-1) else decoded[k]
             for k,w,s in fixtures.FIELDS[:9]]
        out,_=fixtures.evaluate('b9',row)
        assert all(decoded[f[0]]==v&((1<<f[1])-1) for f,v in zip(fixtures.FIELDS[9:],out))
        d=r['input']; p=plan(d['plan']); c=g.Certificate(**d['cert'])
        assert g.zlib.crc32(r['output']['reason'].encode())==decoded['reason_crc32']
        assert int(g.digest(asdict(c)),16)==decoded['output_digest']
        add(p,c,group='golden',name=str(r['index']),now=d['now'],expected=r['output']['reason'])
    for r in map(json.loads,(ROOT/'vectors/edges.ports.jsonl').read_text().splitlines()):
        if r.get('block')!='b9': continue
        d=r['input'].copy(); p=plan(d.pop('plan')); c=g.Certificate(**d.pop('cert'))
        if r['name'].startswith('wrap_'): d['at_executor']=True
        add(p,c,group='edge',name=r['name'],expected=r['output']['reason'],**d)
    rng=random.Random(9009)
    for i in range(2600):
        base=rng.choice([0,1,0x7fffffff,0x80000000,0xffff0000,g.MASK,rng.getrandbits(32)])
        e=g.Ego(base,rng.choice([-10000*g.S,0,10000*g.S]),rng.randrange(10*g.S+1),-rng.randrange(8*g.S+1),100*g.S,0)
        apply=(base+rng.choice([-1,0,1,19999,20000,20001,39999,40000,40001,100000,0x80000000]))&g.MASK
        p=g.Plan(rng.getrandbits(32),e,base,apply,e.x,e.v,e.a)
        expiry=(base+rng.choice([-1,0,1,19999,20000,20001,120000,499999,500000,500001,0x7fffffff,0x80000000]))&g.MASK
        c=g.certify(p,expiry)
        kw=dict(now=(base+rng.choice([-1,0,1,19999,20000,20001,39999,40000,40001,499999,500000,500001,0x80000000]))&g.MASK,
                at_executor=bool(rng.getrandbits(1)), issued=rng.choice([None,base]),ack=bool(rng.getrandbits(1)),
                expected_seq=rng.choice([None,p.seq]),expected_context=rng.choice([None,c.context]),phase_reuse=bool(rng.getrandbits(1)))
        mutation=i%26
        if mutation<10:
            key=['snapshot','trajectory','t_a','capability','config','controller','scope','context','seal','t_e'][mutation]
            value=getattr(c,key); c=replace(c,**{key:(('f' if value[0]!='f' else '0')+value[1:]) if isinstance(value,str) else (value+1)&g.MASK})
            if mutation%2: c=replace(c,seal=g.cert_seal(c))
        if mutation==10: kw['expected_seq']=p.seq^1
        if mutation==11: kw['expected_context']='00'*32
        if mutation==12: p=None
        if mutation==13: c=None
        add(p,c,name=f'random_{i}',**kw)
    # Exact boundary microseconds, including uninterrupted 20ms subcycle sequences.
    for base in [0,0xffff0000,0x7fffffff]:
        e=g.Ego(base,0,g.S,0,30*g.S,0)
        for offset in [-1,0,1,20000,40000,100000]:
            p=g.Plan(7,e,base,(base+offset)&g.MASK,0,g.S,0)
            for lease in [0,1,20000,20001,499999,500000,500001]:
                c=g.certify(p,(base+lease)&g.MASK)
                for t in [0,19999,20000,20001,39999,40000,40001,59999,60000,offset-1,offset,offset+1,lease-1,lease,lease+1]:
                    for executor in [False,True]:
                        for ack in [False,True]:
                            add(p,c,group='boundary',now=(base+t)&g.MASK,at_executor=executor,issued=base,ack=ack,expected_seq=7,expected_context=c.context)
    e=g.Ego(0,0,0,0,30000000,0);p=g.Plan(1,e,0,0,0,0,0);c=g.certify(p,500000)
    # Isolate each strict margin term: the other term must be safely above margin.
    for base in [0,0xffff0000,0x7fffffff]:
        pp=replace(p,generated=base,apply=base)
        cc=g.certify(pp,(base+500000)&g.MASK)
        for remaining in [19999,20000,20001]:
            add(pp,cc,group='isolated',name=f'remaining_{base}_{remaining}',
                now=(base+500000-remaining)&g.MASK,phase_reuse=True)
        for tail in [19999,20000,20001]:
            pp=replace(p,generated=base,apply=(base+500000-tail)&g.MASK)
            cc=g.certify(pp,(base+500000)&g.MASK)
            add(pp,cc,group='isolated',name=f'tail_{base}_{tail}',now=base)
    # Every Config1 version field exercises both u32 extremes and resealed mismatch.
    for key in ['capability','config','controller','scope']:
        for value in [0,1,2,0x7fffffff,0x80000000,g.MASK]:
            cc=replace(c,**{key:value});cc=replace(cc,seal=g.cert_seal(cc))
            add(p,cc,group='isolated',name=f'version_{key}_{value}',now=0)
    # Packed plan members are bound by the supplied digest, not revalidated in B9.
    for key,width in [('seq',32),('generated',32),('apply',32),('x',64),('v',32),('a',32),('tail',8),('compute',32),('count',8),('schema',32)]:
        for value in [0,(1<<(width-1))-1,1<<(width-1),(1<<width)-1]:
            pp=replace(p,**{key:value});cc=g.certify(pp,500000)
            add(pp,cc,group='isolated',name=f'plan_{key}_{value}',now=0)
    # Deliberate overlapping faults verify that ordered return preserves priority.
    for executor in [False,True]:
        bad=replace(c,config=2)
        add(None,bad,group='precedence',now=500000,at_executor=executor,expected_seq=2,expected_context='00'*32)
        add(p,bad,group='precedence',now=500000,at_executor=executor,expected_seq=2,expected_context='00'*32)
        add(p,c,group='precedence',now=500000,at_executor=executor,expected_seq=2,expected_context='00'*32)
        add(p,c,group='precedence',now=500000,at_executor=executor,expected_context='00'*32)
        add(p,g.certify(p,500001),group='precedence',now=500001,at_executor=executor,issued=0)
    # Guarantee every reason, binding component, trusted-local hash and precedence.
    for key in ['snapshot','trajectory','seal','context']:
        bad=replace(c,**{key:'00'*32});add(p,bad,now=0,expected_context=c.context)
    for key in ['capability','config','controller','scope','t_a']:
        bad=replace(c,**{key:2});bad=replace(bad,seal=g.cert_seal(bad));add(p,bad,now=0)
    for bit in [0,255,256,511,512,767]: add(p,c,now=0,local_flip=bit)
    for p0,c0 in [(None,c),(p,None),(None,None)]: add(p0,c0,now=0)
    for v in [-1,1<<32,g.NAN,True]:
        add(p,c,now=v,name=f'adapter_now_{v}')
        for key in ['t_a','t_e']: add(p,replace(c,**{key:v}),now=0,name=f'adapter_{key}_{v}')
        for key in ['seq','generated']: add(replace(p,**{key:v}),c,now=0,name=f'adapter_{key}_{v}')
    # Every bit in each hash is observed by the checker.
    for bit in range(768): add(p,c,now=0,local_flip=bit)
    HERE.joinpath('vectors.mem').write_text(''.join(f'{a:0726x}{b:02x}\n' for a,b,_ in jobs))
    HERE.joinpath('vectors_meta.svh').write_text(f'localparam integer N={len(jobs)};\n')
    result=dict(seed=9009,total=len(jobs),counts=counts,reasons=reasons,adapter_rejects=adapter,
                sources={n:hashlib.sha256((ROOT/'vectors'/n).read_bytes()).hexdigest() for n in ['b9.hex','b9.json','b9.ports.jsonl','edges.ports.jsonl']})
    HERE.joinpath('vectors.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

if __name__=='__main__': main()
