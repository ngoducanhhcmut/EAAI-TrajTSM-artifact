"""S1b conversion plus independent zlib/hashlib oracle. Never modifies shared fixtures."""
import sys
sys.dont_write_bytecode=True
import json,random,hashlib,zlib
from dataclasses import replace
from pathlib import Path
HERE=Path(__file__).resolve().parent
HW=HERE.parents[2]
sys.path[:0]=[str(HW/'golden'),str(HW.parent/'tsm2_pilot/vendor')]
from tsmx_golden import model as g

def valid(op,data):
    sizes=[86,32,70,1049,120]
    if op>6 or len(data)>32768:return False
    if op<5 and len(data)!=sizes[op]:return False
    if op in (0,2) and int.from_bytes(data[66:70],'big')!=1:return False
    if op==0 and int.from_bytes(data[82:86],'big')!=1:return False
    if op==3:
        n=data[0]
        if n>32 or any(data[1+32*n:1025]) or data[-8:]!=bytes.fromhex('0000000100000001'):return False
    return True

def main():
    rng=random.Random(0x5233)
    jobs=[]; beats=[]; counts={}
    def add(op,data,source,custom=None,fault=None):
        ok=valid(op,data) if fault is None else not fault
        if ok:
            crc=zlib.crc32(data) if op in (0,5) else 0
            sha=0 if op in (0,5) else int(hashlib.sha256(data).hexdigest(),16)
            if op not in (0,5):assert sha==int(g.digest(data),16)
        else:crc=sha=0
        expected=((not ok)<<288)|(crc<<256)|sha
        words=[]
        if custom is None:
            chunks=[data[i:i+4] for i in range(0,len(data),4)] or [b'']
            for i,chunk in enumerate(chunks):
                words.append((op<<37)|((i==0)<<36)|((i==len(chunks)-1)<<35)|(len(chunk)<<32)|int.from_bytes(chunk.ljust(4,b'\0'),'big'))
        else:words=custom
        jobs.append((len(words)<<329)|(len(data)<<297)|(op<<289)|expected)
        beats.extend(words);counts[source]=counts.get(source,0)+1
    # Early error response exercises every error assertion before long randomized runs.
    add(7,b'','fault')
    # Complete relevant fixture trees, including retained pending/backup certificates.
    seen=0
    def walk(x):
        nonlocal seen
        if isinstance(x,dict):
            keys=set(x)
            if keys=={'t','x','v','a','lx','lv'}:
                add(1,g.pack_ego(x),'fixture');seen+=1
            if 'snapshot' in x and 'seq' in x and 'generated' in x:
                p=g.Plan(**{**x,'snapshot':g.Ego(**x['snapshot'])})
                add(2,g.pack_plan(p),'fixture')
                add(0,g.pack_packet_body(p),'fixture')
                assert g.packet(p).crc==zlib.crc32(g.pack_packet_body(p))
            if 'trajectory' in x and 't_a' in x and 'seal' in x:
                body=g.pack_certificate(x,False)
                assert int(g.cert_seal(x),16)==int.from_bytes(hashlib.sha256(body).digest(),'big')
                add(4,body,'fixture')
            if 'objects' in x and isinstance(x['objects'],list) and len(x['objects'])<=32:
                objs=tuple(g.Motion(**o) for o in x['objects'])
                lane=x.get('lane',[-1800000,1800000])
                if isinstance(lane,(tuple,list)) and len(lane)==2:add(3,g.pack_context(objs,lane),'fixture')
            for v in x.values():walk(v)
        elif isinstance(x,list):
            for v in x:walk(v)
    fixture_rows={}
    for stem in ('b1','b9','system','edges'):
        p=HW/'vectors'/f'{stem}.ports.jsonl'
        rows=[json.loads(line) for line in p.read_text().splitlines()]
        fixture_rows[stem]=len(rows)
        if stem!='edges':
            meta=json.loads(p.with_name(stem+'.json').read_text())
            assert hashlib.sha256(p.with_name(stem+'.hex').read_bytes()).hexdigest()==meta['sha256']
        for row in rows:walk(row)
    # Random typed records, including all allocated object counts and list order.
    for i in range(1000):
        e=g.Ego(rng.getrandbits(32),rng.randrange(-10**10,10**10),rng.randrange(10000001),-rng.randrange(8000001),rng.randrange(-10**10,10**10),rng.randrange(20000001))
        p=g.Plan(rng.getrandbits(32),e,rng.getrandbits(32),rng.getrandbits(32),e.x,e.v,e.a,tail=i%16,compute=rng.getrandbits(32),count=i%256)
        op=i%5
        objects=tuple(g.Motion(e.x+j,e.v,e.a,4800000,0,-4000000) for j in range(i%33))
        c=g.certify(p,rng.getrandbits(32),objects)
        data=(g.pack_packet_body(p,tuple(rng.getrandbits(32) for _ in range(3))),g.pack_ego(e),g.pack_plan(p),g.pack_context(objects),g.pack_certificate(c,False))[op]
        add(op,data,'random_record')
    # Bit-width boundaries include s64/s32/u32/u8 extremes and sentinel wrapping.
    base=g.Plan(0,g.Ego(0,0,0,0,0,0),0,0,0,0,0)
    for field,width,signed in [('t',32,False),('x',64,True),('v',32,True),('a',32,True),('lx',64,True),('lv',32,True)]:
        for v in (0,1,-1,-(1<<(width-1)),(1<<(width-1))-1,(1<<width)-1,1<<width):
            e=replace(base.snapshot,**{field:v});add(1,g.pack_ego(e),'field_boundary')
    for field,width in [('seq',32),('generated',32),('apply',32),('x',64),('v',32),('a',32),('tail',8),('compute',32),('count',8),('schema',32)]:
        for v in (0,1,-1,-(1<<(width-1)),(1<<(width-1))-1,(1<<width)-1,1<<width):
            add(2,g.pack_plan(replace(base,**{field:v})),'field_boundary')
    for n in range(33):
        objects=tuple(g.Motion(-(1<<63)+i,(1<<31)-1,-(1<<31),(1<<63)-1,0xffffffff,-1) for i in range(n))
        add(3,g.pack_context(objects,(-(1<<63),(1<<63)-1)),'field_boundary')
    c=g.certify(base,0)
    for field,width in [('snapshot',256),('trajectory',256),('context',256),('t_a',32),('t_e',32),('capability',32),('config',32),('controller',32),('scope',32)]:
        for v in (0,1,(1<<width)-1,1<<(width-1)):
            add(4,g.pack_certificate(replace(c,**{field:f'{v:064x}' if width==256 else v}),False),'field_boundary')
    # >=2000 raw randomized jobs. Full range sampled along with dense short messages.
    lengths=[0,1,2,3,4,31,32,55,56,57,63,64,65,70,86,119,120,127,128,129,1049,5683,32767,32768]
    lengths += [rng.randrange(32769) if i%32==0 else rng.randrange(257) for i in range(1050)]
    for n in lengths:
        data=rng.randbytes(n)
        for op in (5,6):add(op,data,'random_bytes')
    # Malformed size/op/start/count, changing opcode and canonical padding.
    for op in range(5):
        size=[86,32,70,1049,120][op]
        for n in (0,1,size-1,size+1):add(op,bytes(n),'fault')
    for bad in [(7<<37)|(1<<36)|(1<<35), (6<<37)|(1<<35)|(4<<32),
                (6<<37)|(1<<36)|(1<<35)|(5<<32),
                (6<<37)|(1<<36)|(1<<35)|(1<<32)|1]:
        add(6,b'','fault',custom=[bad],fault=True)
    add(6,b'','fault',custom=[(6<<37)|(1<<36)|(4<<32),(5<<37)|(1<<35)|(4<<32)],fault=True)
    add(6,b'','fault',custom=[(6<<37)|(1<<36)|(4<<32),(6<<37)|(1<<36)|(1<<35)|(4<<32)],fault=True)
    add(6,bytes(32769),'fault')
    for index in (0,100,1041,1048):
        b=bytearray(g.pack_context());b[index]^=255;add(3,bytes(b),'fault')
    # Known-answer tests, zero/FF/ASCII, leading-zero SHA digest search.
    for data in (b'',b'abc',b'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',bytes(64),b'\xff'*64):
        add(6,data,'kat');add(5,data,'kat')
    for n in range(10000):
        data=str(n).encode()
        if hashlib.sha256(data).digest()[0]==0:add(6,data,'leading_zero');break
    (HERE/'jobs.mem').write_text(''.join(f'{x:091x}\n' for x in jobs))
    (HERE/'beats.mem').write_text(''.join(f'{x:012x}\n' for x in beats))
    (HERE/'vectors_meta.svh').write_text(f'localparam integer N={len(jobs)}, B={len(beats)};\n')
    report=dict(jobs=len(jobs),beats=len(beats),counts=counts,fixture_rows=fixture_rows,seed=0x5233,max_bytes=32768)
    (HERE/'vectors.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report)
if __name__=='__main__':main()
