"""Pack every semantic golden vector into readmemh files, plus spec-directed cases.

No golden import: expected values for supplied cases come from ports.jsonl.
Directed expectations independently implement spec 5.5.7/8/10 and Event ABI 9.2.
"""
from pathlib import Path
import hashlib
import itertools
import json

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / 'tb/unit'
MODES = ['L0', 'L1', 'L2', 'L3', 'HOLD', 'RECOVERY']

def source(block):
    meta = json.loads((ROOT/f'vectors/{block}.json').read_text())
    data = (ROOT/f'vectors/{block}.hex').read_bytes()
    assert hashlib.sha256(data).hexdigest() == meta['sha256']
    words = [int(x, 16) for x in data.splitlines()]
    rows = [json.loads(x) for x in (ROOT/f'vectors/{block}.ports.jsonl').read_text().splitlines()]
    assert len(rows) == len(words) == meta['n']
    # Fixture metadata is deliberately not mistaken for physical module ports.
    fields = {x['name']: x for x in meta['fields']}
    for row, word in zip(rows, words):
        for name in ('accept', 'selected', 'mode', 'margin', 'output_digest'):
            f = fields[name]
            val = (word >> f['lsb']) & ((1 << f['bits'])-1)
            o = row['output']
            if block == 'b7' and name == 'selected': assert val == o['candidate']
            if block == 'b8' and name == 'mode': assert val == MODES.index(o['mode'])
            if block == 'b10' and name == 'margin': assert val == o['lost']
            if block in ('b8', 'b10') and name == 'output_digest':
                digest = hashlib.sha256(json.dumps(o, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
                assert val == int(digest, 16)
    return rows

def dump(blk, rows, width, golden):
    path = TB/blk
    path.mkdir(parents=True, exist_ok=True)
    (path/'vectors.mem').write_text(''.join(f'{r:0{(width+3)//4}x}\n' for r in rows), encoding='ascii')
    (path/'vectors_meta.svh').write_text(f'localparam integer N = {len(rows)};\nlocalparam integer GOLDEN = {golden};\n', encoding='ascii')
    return dict(rows=len(rows), golden=golden, bits=width)

def selector():
    src = source('b7')
    rows = []
    for r in src:
        mask = sum(int(x['accept']) << i for i, x in enumerate(r['input']['results']))
        o = r['output']
        expected = (o['candidate'] << 8) | (1 if o['label']=='CERT-FRONT/REAR-COND' else 2)
        rows.append((mask << 16) | expected)
    for mask in range(65536):
        ids = [i for i in range(16) if i % 4 != 3 and (mask >> i) & 1]
        rows.append((mask << 16) | ((ids[0] << 8) | 1 if ids else 0x0f02))
    return dump('sel', rows, 32, len(src))

def b8_input(i):
    s = i['state']
    fields = [(MODES.index(s['mode']) if isinstance(s['mode'], str) else s['mode'],3),
              (s['good'],2),(s['fault_latched'],1),(i['accept'],1),(i['v'],32),
              (i.get('reusable',False),1),(i.get('fallback',True),1),
              (i.get('capability',True),1),(i.get('reset',False),1),(i.get('health',True),1)]
    w = 0
    for v, bits in fields: w = (w << bits) | int(v)
    return w

def b8_expected(i):
    mode = i['state']['mode']
    invalid = isinstance(mode, int) and mode > 5
    if i.get('reset',False) or not i.get('health',True) or invalid:
        return ((4 if i['v']==0 else 3) << 5) | 7
    if i['accept']:
        good = min(3,i['state']['good']+1)
        return ((0 if good==3 else 5) << 5) | (good << 3)
    m = 4 if i['v']==0 else 1 if i.get('reusable',False) and i.get('capability',True) else 2 if i.get('fallback',True) and i.get('capability',True) else 3
    return (m << 5) | 6

def supervisor():
    src = source('b8'); rows = []
    for r in src:
        i,o = r['input'],r['output']
        clear = i.get('reset',False) or not i.get('health',True)
        e = (MODES.index(o['mode']) << 5) | (o['good'] << 3) | (int(o['fault_latched']) << 2) | (int(clear or not i['accept']) << 1) | int(clear)
        assert e == b8_expected(i)
        # Every remaining Supervisor field is owned by top and absent from the B8 ABI.
        for key in ('events','events_lost','ingress'): assert o[key] == i['state'][key]
        rows.append((b8_input(i) << 8) | e)
    for mode,good in itertools.product(range(8),range(4)):
        for fault,acc,zero,reuse,fb,cap,rst,health in itertools.product(range(2),repeat=8):
            i=dict(state=dict(mode=mode,good=good,fault_latched=fault),accept=acc,v=0 if zero else 10000000,reusable=reuse,fallback=fb,capability=cap,reset=rst,health=health)
            rows.append((b8_input(i) << 8) | b8_expected(i))
    return dump('supervisor',rows,52,len(src))

def event(values, valid=True):
    w = (int(valid) << 3) | min(len(values),7)
    for idx in range(4):
        field = 0
        if idx < len(values):
            v = values[idx]
            if isinstance(v,str):
                b = v.encode('utf-8')
                field = (1 << 262) | (min(len(b),63) << 256) | int.from_bytes(b[:32].ljust(32,b'\0'),'big')
            else: field = v & ((1<<64)-1)
        w = (w << 263) | field
    return w

def recorder():
    src=source('b10'); rows=[]
    # op=0 append, op=1 read, op=2 simultaneous append/read, op=3 seed lost for saturation.
    ring=[]; lost=0
    def add(op=0,e=0,idx=0,read=0,reset=False,expected_lost=None):
        nonlocal lost,ring
        if reset: ring=[];lost=0
        rows.append((int(reset) << 2156) | (op << 2154) | (e << 1098) | ((lost if expected_lost is None else expected_lost) << 1066) | (idx << 1056) | read)
    def append(e,valid=True,op=0,idx=0):
        nonlocal lost,ring
        old = ring[idx] if idx < len(ring) else 0
        if not valid or len(ring)==4: lost=min(0xffffffff,lost+1)
        if valid: ring=(ring+[e])[-4:]
        add(op,e,idx,old)
    for r in src:
        assert r['input']['state']==dict(capacity=4,events=[],lost=0)
        add(op=1,reset=True)
        for v in r['input']['events']: append(event(v))
        o=r['output'];assert o['capacity']==4 and o['lost']==lost
        assert ring == [event(v) for v in o['events']]
        for idx,e in enumerate(ring): add(1,idx=idx,read=e)
    add(op=1,reset=True)
    for v in ([],[''],['x'*32],[-(1<<63)+1,(1<<63)-1,'HOLD',0]): append(event(v))
    for idx,e in enumerate(ring): add(1,idx=idx,read=e)
    # Invalid schema/count/int lower bound/length/padding, all preserve ring.
    invalid=[event([1],False),event([1,2,3,4,5]),event([-(1<<63)]),event(['x'*33]),event([1]) | (1 << 853),event([1]) | 1,event(['a']) | (1 << 800)]
    for e in invalid: append(e,False)
    for k in range(12): append(event([k,'collision']),op=2,idx=k%4)
    for idx,e in enumerate(ring): add(1,idx=idx,read=e)
    add(1,idx=1023,read=0)
    lost=0xfffffffe; add(3)
    append(event([8])); append(event([9])); append(event([],False),False)
    # Reset after full ring and saturation; query must not expose stale RAM.
    add(op=1,reset=True); append(event(['after reset']))
    add(1,idx=0,read=ring[0])
    return dump('rec',rows,2157,len(src))

if __name__=='__main__':
    stats=dict(sel=selector(),supervisor=supervisor(),rec=recorder())
    (TB/'R1_vectors.json').write_text(json.dumps(stats,indent=2)+'\n')
    print(json.dumps(stats))
