"""Supplement all S1b record packers with FORMATS domain/width endpoints.

Nonproduction record types use diagnostic raw ops, preserving outer byte padding.
Original numeric-invalid values remain hash material, never an admission claim.
"""
import sys
sys.dont_write_bytecode=True
import subprocess,json,hashlib,zlib
from pathlib import Path
from dataclasses import replace
import gen_vectors as v
g=v.g
H=Path(__file__).resolve().parent
R=H.parents[2]/'rtl/codec'
out=H/'format_boundaries';out.mkdir(exist_ok=True)
rows=[]
def add(data,op=6):
    ok=v.valid(op,data)
    crc=zlib.crc32(data) if ok and op in (0,5) else 0
    sha=int(hashlib.sha256(data).hexdigest(),16) if ok and op not in (0,5) else 0
    if ok and op not in (0,5):assert sha==int(g.digest(data),16)
    rows.append((op,data,((not ok)<<288)|(crc<<256)|sha))
e=g.Ego(0,0,0,0,0,0)
p=g.Plan(0,e,0,0,0,0,0)
for k,vals in dict(t=(0,0xffffffff),x=(-10000*g.S,10000*g.S,-10070*g.S,10070*g.S),
    v=(0,10*g.S,10050000),a=(-8*g.S,0),lx=(-10000*g.S,10000*g.S),lv=(0,20*g.S)).items():
    for n in vals:add(g.pack_ego(replace(e,**{k:n})),1)
for k,vals in dict(seq=(0,0xffffffff),generated=(0,0xffffffff),apply=(0,0xffffffff),
    x=(-10070*g.S,10070*g.S),v=(0,10*g.S),a=(-8*g.S,0),tail=(0,15,255),
    compute=(0,100000,0xffffffff),count=(0,128,255),schema=(0,1,0xffffffff)).items():
    for n in vals:add(g.pack_plan(replace(p,**{k:n})),2)
for i in range(3):
    for n in (0,0xffffffff):
        ids=[0,0,0];ids[i]=n;add(g.pack_packet_body(p,ids),0)
for n in (0,1,0xffffffff):add(g.pack_packet_body(p,schema=n),0)
m=g.Motion(0,0,0,1,0,0)
for k,vals in dict(x=(-(1<<63),-10000*g.S,10000*g.S,(1<<63)-1),
    v=(0,20*g.S,(1<<31)-1),a=(-8*g.S,2*g.S,-(1<<31),(1<<31)-1),
    length=(1,20*g.S,(1<<63)-1),event=(0,12800000,0xffffffff),
    after_a=(-8*g.S,2*g.S,-(1<<31),(1<<31)-1)).items():
    for n in vals:
        obj=replace(m,**{k:n});add(g.pack_motion(obj));add(g.pack_context((obj,)),3)
for index in range(6):
    for n in (-(1<<63),-10000*g.S,0,10000*g.S,(1<<63)-1):
        fields=[-1800000,1800000,0,950000,50000,500000];fields[index]=n
        add(g.pack_lane(fields[:2],*fields[2:]))
for lane in ((-10000*g.S,10000*g.S),(-(1<<63),(1<<63)-1)):
    add(g.pack_context((),lane),3)
# Every Row field: physical bounds and full wire extrema.
row=(0,0,0,0,0,0,0)
limits=[(0,12800000,-(1<<31),(1<<31)-1),
    (-10070*g.S,10070*g.S,-(1<<63),(1<<63)-1),
    (-10070*g.S,10070*g.S,-(1<<63),(1<<63)-1),
    (0,10*g.S,20200000,45600000,-(1<<31),(1<<31)-1),
    (0,10*g.S,20200000,45600000,-(1<<31),(1<<31)-1),
    (-8*g.S,0,-(1<<31),(1<<31)-1),(-8*g.S,0,8*g.S,-(1<<31),(1<<31)-1)]
for i,vals in enumerate(limits):
    for n in vals:
        r=list(row);r[i]=n;add(g.pack_row(r))
for accept in (False,True):
    for stop in (-1,0,12800000):
        for n in (0,1,129):add(g.pack_trajectory(dict(accept=accept,reason='ok',stop=stop,rows=[row]*n)))
for reason in (g.REASONS[0],g.REASONS[-1]):
    for margin in (-(1<<63),(1<<63)-1):add(g.pack_geom(dict(accept=True,margin=margin,reason=reason,steps=255)))
for k,vals in dict(seq=(-1,0,0xffffffff),last_time=(-1,0,0xffffffff),last_sample=(-1,0,0xffffffff),
    signature=((),(-(1<<63),-(1<<31),-(1<<31),0),((1<<63)-1,(1<<31)-1,(1<<31)-1,255)),
    freeze_since=(0,0xffffffff),freeze_x=(-(1<<63),(1<<63)-1)).items():
    for n in vals:add(g.pack_ingress(replace(g.Ingress(),**{k:n})))
for event in ((),(0,),(-(1<<63)+1,),((1<<63)-1,),(-(1<<63),),(1<<63,),
    ('',),('A'*32,),('A'*33,),('\u00e9',),(0,-1,'','A'*32),(1,2,3,4,5)):
    add(g.pack_event(event));add(g.pack_event(event),5)
c=g.certify(p,0)
add(g.pack_certificate(None));add(g.pack_packet(None))
for s in ('','0'*64,'f'*64):
    for k in ('snapshot','trajectory','context','seal'):
        cert=replace(c,**{k:s});add(g.pack_certificate(cert));add(g.pack_certificate(cert,False),4)
for k in ('t_a','t_e','capability','config','controller','scope'):
    for n in (0,0xffffffff):add(g.pack_certificate(replace(c,**{k:n}),False),4)
response=dict(accept=False,reason='ok',mode='L0',candidate=0,label='CERT-FRONT/REAR-COND',independent_brake=False,commit='ok',heartbeat=False)
for b in (False,True):
    rsp={**response,'accept':b,'heartbeat':b,'independent_brake':b,'candidate':15 if b else 0,
        'reason':g.REASONS[-1] if b else 'ok','commit':g.REASONS[-1] if b else 'ok',
        'mode':'RECOVERY' if b else 'L0','label':'MITIGATION' if b else 'CERT-FRONT/REAR-COND'}
    add(g.pack_top_rsp(rsp))
    update=dict(response=rsp,busy=b,pending=b,backup=b,healthy=b,bist_done=b,cycles=0xffffffff if b else 0,lost=0xffffffff if b else 0,irq_set=255 if b else 0)
    add(g.pack_csr_update(update))
    for source in (0,7):
        cmd=dict(source=source,mode=rsp['mode'],label=255 if b else 0,candidate=255 if b else 0,
            seq=0xffffffff if b else 0,apply=0xffffffff if b else 0,expiry=0xffffffff if b else 0,
            plan=p,certificate=c if b else None,parking=b,override=b)
        add(g.pack_command(cmd))
jobs=[];beats=[]
for op,data,expected in rows:
    chunks=[data[i:i+4] for i in range(0,len(data),4)] or [b'']
    jobs.append((len(chunks)<<329)|(len(data)<<297)|(op<<289)|expected)
    for i,chunk in enumerate(chunks):beats.append((op<<37)|((i==0)<<36)|((i==len(chunks)-1)<<35)|(len(chunk)<<32)|int.from_bytes(chunk.ljust(4,b'\0'),'big'))
(out/'jobs.mem').write_text(''.join(f'{x:091x}\n' for x in jobs))
(out/'beats.mem').write_text(''.join(f'{x:012x}\n' for x in beats))
(out/'vectors_meta.svh').write_text(f'localparam integer N={len(jobs)}, B={len(beats)};\n')
(out/'tb_m_tsmx_codec.sv').write_text((H/'tb_m_tsmx_codec.sv').read_text())
with (out/'compile.log').open('w') as f:q=subprocess.run(['iverilog','-g2012','-s','tb_m_tsmx_codec','-o','simulation.vvp',str(R/'m_tsmx_codec_core.sv'),str(R/'m_tsmx_codec.sv'),'tb_m_tsmx_codec.sv'],cwd=out,stdout=f,stderr=f)
assert q.returncode==0
with (out/'simulation.log').open('w') as f:q=subprocess.run(['vvp','simulation.vvp'],cwd=out,stdout=f,stderr=f,timeout=180)
text=(out/'simulation.log').read_text();print(text[-2500:])
# This supplement has no raw CRC production jobs with fault flag, unlike the main suite.
assert q.returncode==0
(out/'summary.json').write_text(json.dumps(dict(jobs=len(jobs),beats=len(beats)))+'\n')
