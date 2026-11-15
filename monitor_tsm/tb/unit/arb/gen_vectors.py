"""TSM-X / TSMX project / 0.1. REQ-TSMX-024, spec5.5.13/6.2/9.2.

Golden supplies system transitions and all record serialization. The source mux
projection is specified in README and spec5.5.13, not implemented in model.py.
No golden/spec/vector source is modified. Run with py -3.13 -B.
"""
import sys
sys.dont_write_bytecode = True
import hashlib
import itertools
import json
import random
from dataclasses import asdict, replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(ROOT/'golden'), str(ROOT.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g
import vectors as fixtures


def plan(d):
    return g.Plan(**{**d, 'snapshot': g.Ego(**d['snapshot'])})


def supervisor(d):
    d = d.copy()
    d['ingress'] = g.Ingress(**{**d['ingress'], 'signature': tuple(d['ingress']['signature'])})
    d['events'] = tuple(tuple(x) for x in d['events'])
    d['pending'] = tuple(d['pending'])
    d['backup'] = tuple(d['backup'])
    if d['pending']:
        t, p, c = d['pending']; d['pending'] = (t, plan(p), g.Certificate(**c))
    if d['backup']:
        p, c = d['backup']; d['backup'] = (plan(p), g.Certificate(**c))
    return g.Supervisor(**d)


def inputs(d):
    d = d.copy(); d['ego'] = g.Ego(**d['ego'])
    if d.get('cert'): d['cert'] = g.Certificate(**d['cert'])
    if d.get('pkt'):
        p = d['pkt']; d['pkt'] = g.Packet(plan(p['plan']), p['crc'], tuple(p['snapshot_ids']), p['schema'])
    if 'objects' in d: d['objects'] = tuple(g.Motion(**o) for o in d['objects'])
    if 'lane' in d: d['lane'] = tuple(d['lane'])
    return d


def record(p, width):
    return g._nested(p, width)[0]


jobs = []; counts = {}; sources = {}; rejects = {}


def add(mode, candidate, label, now, ego, pending=None, backup=None, override=False,
        pv=None, bv=None, group='extra', name=''):
    pv = bool(pending) if pv is None else pv
    bv = bool(backup) if bv is None else bv
    pp, pc = pending if pending else (None, None)
    bp, bc = backup if backup else (None, None)
    fields = [(mode, 3), (candidate, 8), (label, 8), (now, 32), (pv, 1),
              (record(g.pack_plan(pp),560) if pp else 0,560),
              (record(g.pack_certificate(pc),1217),1217), (bv,1),
              (record(g.pack_plan(bp),560) if bp else 0,560),
              (record(g.pack_certificate(bc),1217),1217), (record(g.pack_ego(ego),256),256)]
    req = 0
    for value, width in fields: req = (req << width) | (int(value) & ((1<<width)-1))
    reason = 'ok'; p = c = None
    # Independent contract oracle, using semantic records rather than RTL slices.
    if override:
        source = 3; reason = 'override'
    elif mode in (0,5) and pv and pp and pc:
        source = 0; p,c = pp,pc
    elif mode == 1 and bv and bp and bc:
        source = 1; p,c = bp,bc
    elif mode == 2 and candidate in [i for i in range(16) if g.LIBRARY[i][1]] and label == 1:
        source = 2
    elif mode == 4:
        source = 4
    else:
        source = 3
        reason = ('missing_pending' if mode in (0,5) else 'missing_backup' if mode==1 else
                  'fallback' if mode==2 else 'mode' if mode>5 else 'mitigation')
    cmode = 3 if source==3 else mode
    cid = p.tail if p else candidate if source==2 else 15
    clabel = 1 if source in (0,1,2) else 2
    if p is None:
        p = g.Plan(0,ego,now,now,ego.x,ego.v,ego.a,tail=cid,compute=0,count=0)
    command = dict(source=source,mode=g.MODES[cmode],label=clabel,candidate=cid,
                   seq=p.seq,apply=p.apply,expiry=c.t_e if c else (now+g.DT)&g.MASK,
                   plan=p,certificate=c,parking=source==4,override=source==3)
    # pack_command handles nested dataclasses and byte padding exactly as golden ABI.
    # SPEC-ISSUE: listed Command fields sum1897, not declared W_CMD1997.
    # Keep declared physical port, right-align golden record, zero the spare MSB100.
    rsp = record(g.pack_command(command),1897)
    jobs.append((req,rsp,int(override),int(source==3),name))
    counts[group] = counts.get(group,0)+1
    sources[source] = sources.get(source,0)+1
    rejects[reason] = rejects.get(reason,0)+1


def project(row, group):
    d = row['input']; s,o = g.tsmx_cycle(supervisor(d['state']), inputs(d['inputs']))
    # JSON normalization removes tuple/list representation differences only.
    actual = json.loads(json.dumps(dict(state=asdict(s),outputs=o)))
    assert actual == row['output'], row.get('name',row.get('index'))
    p = s.pending[1:] if s.pending else None
    b = s.backup if s.backup else None
    add(g.MODES.index(s.mode),o['candidate'],1 if o['label']=='CERT-FRONT/REAR-COND' else 2,
        d['inputs']['now'],g.Ego(**d['inputs']['ego']),p,b,group=group,
        name=row.get('name',str(row.get('index'))))


def main():
    meta = json.loads((ROOT/'vectors/system.json').read_text())
    raw = (ROOT/'vectors/system.hex').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==meta['sha256']
    rows = [json.loads(l) for l in (ROOT/'vectors/system.ports.jsonl').read_text().splitlines()]
    words = [int(l,16) for l in raw.splitlines()]
    assert len(rows)==len(words)==meta['n']
    for r,w in zip(rows,words):
        decoded = {f['name']:(w>>f['lsb'])&((1<<f['bits'])-1) for f in meta['fields']}
        out = r['output']['outputs']
        assert decoded['accept']==out['accept'] and decoded['selected']==out['candidate']
        assert decoded['mode']==g.MODES.index(out['mode'])
        assert decoded['reason_crc32']==g.zlib.crc32(out['reason'].encode())
        assert decoded['output_digest']==int(g.digest(out),16)
        # Reuse golden vectors.py's conversion of the nine summary input scalars.
        vals = []
        for key,width,signed in fixtures.FIELDS[:9]:
            v=decoded[key]; vals.append(v-(1<<width) if signed and v>>(width-1) else v)
        summary,_ = fixtures.evaluate('system',vals,supervisor(r['input']['state']))
        assert summary[0]==decoded['accept'] and summary[1]==decoded['selected']
        project(r,'golden')
    for r in map(json.loads,(ROOT/'vectors/edges.ports.jsonl').read_text().splitlines()):
        if r['block']=='system': project(r,'edge')
    rng = random.Random(101024)
    for i in range(2600):
        now = rng.choice([0,1,0x7fffffff,0x80000000,g.MASK,rng.getrandbits(32)])
        e = g.Ego(now,rng.choice([-10000*g.S,0,10000*g.S,rng.randrange(-100*g.S,100*g.S)]),
                  rng.choice([0,10*g.S,rng.randrange(10*g.S)]),-rng.randrange(8*g.S+1),100*g.S,0)
        ps=[]
        for j in range(2):
            p = g.Plan(rng.getrandbits(32),e,(now-100000)&g.MASK,
                       (now+rng.choice([-100000,-1,0,1,100000]))&g.MASK,
                       e.x,e.v,e.a,tail=rng.choice([k for k in range(16) if g.LIBRARY[k][1]]))
            ps.append((p,g.certify(p,(now+400000)&g.MASK)))
        mode = i%8
        add(mode,rng.choice([0,1,2,3,7,11,14,15,16,127,255]),rng.choice([0,1,2,255]),
            now,e,ps[0] if rng.randrange(3) else None,ps[1] if rng.randrange(3) else None,
            override=i%17==0, pv=bool(rng.getrandbits(1)),bv=bool(rng.getrandbits(1)),name=f'random{i}')
    # Exhaustive authority precedence and all selector byte encodings, including instant IDs.
    e=g.Ego(0xffffffff,-10000*g.S,10*g.S,-8*g.S,10000*g.S,10*g.S)
    p=g.Plan(g.MASK,e,0xffff0000,0xfffffff0,e.x,e.v,e.a,tail=6)
    c=g.certify(p,123456); b=replace(p,tail=10,seq=0); bc=g.certify(b,234567)
    for mode,pv,bv,ov in itertools.product(range(8),range(2),range(2),range(2)):
        add(mode,0,1,e.t,e,(p,c),(b,bc),ov,pv,bv,group='boundary')
    for cid,label in itertools.product(range(256),[0,1,2,255]):
        add(2,cid,label,e.t,e,group='boundary')
    # Record forwarding is bit-exact even for unusual patterns: caller flags are authority.
    for bit in range(256):
        changed=replace(c,context=f'{1<<bit:064x}',seal=f'{((1<<256)-1)^(1<<bit):064x}')
        add(0,15,2,e.t,e,(p,changed),(b,bc),group='binding_bits')
    # B9 timer rejects are projected to override, never folded into transport validity.
    statuses={}
    for base in [0,0xffff0000]:
        e=replace(e,t=base); p=replace(p,snapshot=e,generated=base,apply=(base+20000)&g.MASK)
        c=g.certify(p,(base+100000)&g.MASK)
        for dt in [0,19999,20000,20001,39999,40000,40001,99999,100000,100001]:
            for ack in [False,True]:
                now=(base+dt)&g.MASK
                status=g.b9_cert(p,c,now,True,base,ack,p.seq)
                statuses[status]=statuses.get(status,0)+1
                add(0,0,1,now,e,(p,c),override=status not in ('pending','committed'),group='timer')
    # Original invalid numeric values are adapter rejects, not falsely admitted by masking.
    invalid=0
    for x in [g.NAN,-10000*g.S-1,10000*g.S+1]:
        assert not g.live_ego_valid(0,replace(e,t=0,x=x)); invalid+=1
    for v in [-1,10*g.S+1,1<<31]:
        assert not g.live_ego_valid(0,replace(e,t=0,v=v)); invalid+=1
    # A previously issued nominal frame may finish transport after its expiry.
    # The timer revokes via override; the frame itself must stay unchanged.
    e=replace(e,t=0); p=replace(p,snapshot=e,generated=0,apply=20000)
    c=g.certify(p,100000)
    assert g.b9_cert(p,c,0,True,0,False,p.seq)=='pending'
    assert g.b9_cert(p,c,100000,True,0,True,p.seq)=='expiry_at_executor'
    expiry_stall=len(jobs)
    add(0,0,1,0,e,(p,c),group='expiry_stall',name='expiry_during_stalled_egress')
    (HERE/'vectors.mem').write_text(''.join(f'{((q<<1999)|(r<<2)|(ov<<1)|br):01466x}\n' for q,r,ov,br,_ in jobs),encoding='ascii')
    (HERE/'vectors_meta.svh').write_text(f'localparam integer N={len(jobs)};\nlocalparam integer GOLDEN={counts["golden"]};\nlocalparam integer EDGES={counts["edge"]};\nlocalparam integer EXPIRY_STALL={expiry_stall};\n',encoding='ascii')
    info=dict(total=len(jobs),counts=counts,sources=sources,rejects=rejects,timer_statuses=statuses,
              adapter_rejects=invalid,seed=101024,fixture_sha256=meta['sha256'],
              names=[x[-1] for x in jobs])
    (HERE/'vectors.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:v for k,v in info.items() if k!='names'}))


if __name__=='__main__': main()
