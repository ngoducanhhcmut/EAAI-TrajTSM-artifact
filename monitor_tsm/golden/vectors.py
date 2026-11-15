"""Portable bit-vector driver: py -3.13 -B golden/vectors.py --block b3 --n 5000 --out vectors/b3.hex."""
import sys,json,random,argparse,hashlib
from pathlib import Path
from dataclasses import replace
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from tsmx_golden import model as g

BLOCKS=('b1','b2','b3','b4','b7','b8','b9','b10','b13','system')
FIELDS=[('x',64,True),('v',32,False),('a',32,True),('object_x',64,True),
        ('object_v',32,False),('now',32,False),('candidate',8,False),('fault',8,False),
        ('seq',32,False),('accept',1,False),('selected',8,False),('mode',8,False),
        ('reason_crc32',32,False),('margin',64,True),('output_digest',256,False)]

def evaluate(block,row,state=None):
    x,v,a,ox,ov,now,cid,fault,seq=row
    e=g.Ego(now,x,v,a,ox,ov)
    px,pv=g.advance(x,v,a,g.DT)
    p=g.Plan(seq,e,now,(now+g.DT)&g.MASK,px,pv,a)
    c=g.certify(p,(now+500000)&g.MASK)
    tr=g.b4_mrmgen(x,v,a,cid)
    accept=0;selected=cid;mode=255;margin=0;reason='ok';extra={}
    if block=='b1':
        pkt=g.packet(p)
        if fault%2:pkt=replace(pkt,crc=pkt.crc^1)
        st,reason=g.b1_ingress(g.Ingress(),now,e,pkt)
        accept=reason=='ok';extra=g.asdict(st)
    elif block=='b2':
        accept=g.b2_splice(e,replace(p,x=p.x+(200000 if fault%2 else 0)))
    elif block=='b3':
        r=g.b3_geom(tr,(g.Motion(ox,ov,0,4800000,0,-4*g.S),))
        accept=r.accept;margin=r.margin;reason=r.reason;extra=g.asdict(r)
    elif block=='b4':
        accept=tr.accept;reason=tr.reason;margin=tr.rows[-1][2]-x if tr.rows else -1
        extra=g.asdict(tr)
    elif block=='b7':
        results=[g.GeomResult(k==cid and not fault%2,0,'fixture',1) for k in range(16)]
        selected,reason=g.b7_select(results);accept=selected!=15
    elif block=='b8':
        st=g.b8_fsm(g.Supervisor(),not fault%2,v,reusable=fault%3==0,fallback=cid!=15,reset=fault==7)
        mode=g.MODES.index(st.mode);accept=not st.fault_latched;extra=g.asdict(st)
    elif block=='b9':
        if fault%2:c=replace(c,config=2)
        reason=g.b9_cert(p,c,now);accept=reason=='ok';extra=g.asdict(c)
    elif block=='b10':
        st=g.Recorder(capacity=4)
        for k in range(8):st=g.b10_rec(st,(now,k,fault))
        accept=len(st.events)==4; margin=st.lost;extra=g.asdict(st)
    elif block=='b13':
        accept=g.b13_health((seq,),(seq.bit_count()&1,),fsm_onehot=3 if fault%2 else 1)
    else:
        state=state or g.Supervisor()
        state,extra=g.tsmx_cycle(state,dict(now=now,ego=e,pkt=None if fault%2 else g.packet(p),cert=c))
        accept=extra['accept'];selected=extra['candidate'];mode=g.MODES.index(extra['mode']);reason=extra['reason']
    return [int(accept),selected,mode,g.zlib.crc32(reason.encode()),margin,int((g.digest if block in ('b1','b9','system') else g.digest_json_legacy)(extra),16)],state

def dump(block,n,path):
    rng=random.Random(1947283105+BLOCKS.index(block));state=None
    total_bits=sum(w for _,w,_ in FIELDS);width=(total_bits+3)//4
    lines=[]
    for i in range(n):
        x=rng.randrange(-100*g.S,100*g.S);v=rng.randrange(10*g.S+1);a=-rng.randrange(8*g.S+1)
        row=[x,v,a,x+rng.randrange(4*g.S,60*g.S),rng.randrange(10*g.S+1),(i*g.DT)&g.MASK,i%16,i%8,i]
        values,state=evaluate(block,row,state)
        word=0
        for val,(_,bits,_) in zip(row+values,FIELDS):word=(word<<bits)|(val&((1<<bits)-1))
        lines.append(f'{word:0{width}x}')
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text('\n'.join(lines)+'\n',encoding='ascii')
    offset=total_bits;fields=[]
    for index,(name,bits,signed) in enumerate(FIELDS):
        offset-=bits;fields.append(dict(name=name,bits=bits,signed=signed,lsb=offset,direction='input' if index<9 else 'output'))
    meta=dict(version=1,block=block,n=n,seed=1947283105+BLOCKS.index(block),bit_order='MSB first, left zero pad to nibble',
              bits=total_bits,fields=fields,scale=1000000,mode=dict(enumerate(g.MODES)),
              description='S1b b1/b9/system use binary diagnostic hashes; other block output hashes retain trace-only legacy JSON. Fixed canonical fixture ports; evaluate() constructs full block-specific immutable I/O. output_digest is SHA256 of full output (including all B4 rows).',
              reason='IEEE CRC32 of ASCII reason',fault='b1 CRC flip; b2 x+0.2; b7 empty pool; b8 reset/failure; b9 config tamper; b13 non-onehot; system timeout',
              sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    path.with_suffix('.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')

def main():
    p=argparse.ArgumentParser();p.add_argument('--block',choices=BLOCKS,required=True);p.add_argument('--n',type=int,default=128);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();assert 0<a.n<=1000000;dump(a.block,a.n,a.out)

if __name__=='__main__':main()
