"""Expand canonical fixtures into complete semantic block ports for R/I.

Run AFTER golden/vectors.py. This does not invent an RTL port assignment.
Each JSONL row corresponds one-to-one with the .hex row, not additional cases.
"""
import sys,json
from pathlib import Path
from dataclasses import asdict,replace
HERE=Path(__file__).resolve().parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(HERE.parent/'golden'))
import vectors
from tsmx_golden import model as g

def expand(block):
    meta=json.loads((HERE/(block+'.json')).read_text())
    state=None;lines=[]
    for index,line in enumerate((HERE/(block+'.hex')).read_text().splitlines()):
        word=int(line,16);vals=[]
        for field in meta['fields'][:9]:
            val=(word>>field['lsb'])&((1<<field['bits'])-1)
            if field['signed'] and val>>(field['bits']-1):val-=1<<field['bits']
            vals.append(val)
        x,v,a,ox,ov,now,cid,fault,seq=vals
        e=g.Ego(now,x,v,a,ox,ov);px,pv=g.advance(x,v,a,g.DT)
        p=g.Plan(seq,e,now,(now+g.DT)&g.MASK,px,pv,a);c=g.certify(p,(now+500000)&g.MASK)
        tr=g.b4_mrmgen(x,v,a,cid)
        if block=='b1':
            pkt=g.packet(p)
            if fault%2:pkt=replace(pkt,crc=pkt.crc^1)
            args=dict(state=asdict(g.Ingress()),now=now,ego=asdict(e),pkt=asdict(pkt))
            st,why=g.b1_ingress(g.Ingress(),now,e,pkt);out=dict(state=asdict(st),reason=why)
        elif block=='b2':
            pp=replace(p,x=p.x+(200000 if fault%2 else 0))
            args=dict(ego=asdict(e),plan=asdict(pp));out=dict(accept=g.b2_splice(e,pp))
        elif block=='b3':
            obs=(g.Motion(ox,ov,0,4800000,0,-4*g.S),)
            args=dict(traj=asdict(tr),objects=[asdict(o) for o in obs],lane=[-1800000,1800000])
            out=asdict(g.b3_geom(tr,obs))
        elif block=='b4':
            args=dict(x=x,v=v,a=a,cid=cid,phase=0,limit=128);out=asdict(tr)
        elif block=='b7':
            results=[g.GeomResult(k==cid and not fault%2,0,'fixture',1) for k in range(16)]
            args=dict(results=[asdict(r) for r in results]);ch,lab=g.b7_select(results);out=dict(candidate=ch,label=lab)
        elif block=='b8':
            inp=dict(accept=not fault%2,v=v,reusable=fault%3==0,fallback=cid!=15,reset=fault==7)
            args=dict(state=asdict(g.Supervisor()),**inp);out=asdict(g.b8_fsm(g.Supervisor(),**inp))
        elif block=='b9':
            if fault%2:c=replace(c,config=2)
            args=dict(plan=asdict(p),cert=asdict(c),now=now);out=dict(reason=g.b9_cert(p,c,now))
        elif block=='b10':
            events=[(now,k,fault) for k in range(8)];rec=g.Recorder(capacity=4)
            args=dict(state=asdict(rec),events=events)
            for ev in events:rec=g.b10_rec(rec,ev)
            out=asdict(rec)
        elif block=='b13':
            args=dict(words=[seq],parities=[seq.bit_count()&1],fsm_onehot=3 if fault%2 else 1)
            out=dict(healthy=g.b13_health(**args))
        else:
            state=state or g.Supervisor()
            inp=dict(now=now,ego=e,pkt=None if fault%2 else g.packet(p),cert=c)
            args=dict(state=asdict(state),inputs=dict(now=now,ego=asdict(e),pkt=asdict(inp['pkt']) if inp['pkt'] else None,cert=asdict(c)))
            state,outputs=g.tsmx_cycle(state,inp);out=dict(state=asdict(state),outputs=outputs)
        lines.append(json.dumps(dict(index=index,input=args,output=out),sort_keys=True,separators=(',',':')))
    (HERE/(block+'.ports.jsonl')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
    meta['semantic_ports']=block+'.ports.jsonl'
    meta['semantic_format']='Signed integers follow golden/FORMATS.md; hashes are 256-bit hex; row=phase(u32),xlo(s64),xhi(s64),vlo(s32),vhi(s32),a(s32),jerk(s32). Dynamic tuples carry bounded counts.'
    (HERE/(block+'.json')).write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':
    for block in vectors.BLOCKS:expand(block)
