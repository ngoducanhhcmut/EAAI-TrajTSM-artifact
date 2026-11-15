import random,time,json
from fractions import Fraction as F
from dataclasses import replace
from tsmx_golden import model as g
import oracle

def run(out,n=1000000):
    rng=random.Random(1947283103);counts={};errors=[];accepted={};margin=None
    started=time.perf_counter();badcount=0
    for i in range(n):
        block=('b2','b3','b4','b7')[i%4]
        counts[block]=counts.get(block,0)+1
        ok=False;safe=True;m=None
        try:
            if block=='b2':
                t=(0xffff0000 if i%128==0 else rng.randrange(15000000))
                v=rng.choice((0,1,10*g.S)) if i%16==0 else rng.randrange(10*g.S+1)
                a=-rng.randrange(8*g.S+1);x=rng.choice((-10000*g.S,10000*g.S,0)) if i%64==0 else rng.randrange(-9999*g.S,9999*g.S)
                e=g.Ego(t,x,v,a,0,0);d=rng.randrange(100002)
                xx,vv=g.advance(x,v,a,d)
                p=g.Plan(1,e,t,(t+d)&g.MASK,xx+rng.randrange(-180001,180002),max(0,min(10*g.S,vv+rng.randrange(-210000,210001))),a)
                if i%1024==0:p=replace(p,x=(1<<63)-1)
                ok=g.b2_splice(e,p)
                if ok:safe=oracle.splice(e,p,g.S)
            elif block in ('b3','b7'):
                v=rng.randrange(10*g.S+1);a=-rng.randrange(8*g.S+1)
                h=rng.choice((1,100000,99999));x=rng.randrange(-9990*g.S,9990*g.S)
                xl,vl=g.advance(x,v,a,h);xh,vh=g.advance(x,v,a,h,True)
                tr=g.Trajectory(True,((0,x,x,v,v,a,0),(h,xl,xh,vl,vh,a,0)),-1,'cell')
                lv=rng.randrange(10*g.S+1);la=-rng.randrange(8*g.S+1)
                gap=rng.choice((0,1,499999,500000,500001)) if i%32==1 else rng.randrange(-g.S,40*g.S)
                o=g.Motion(x+4800000+gap,lv,la,4800000,h,la)
                # Preserve ODD on extreme actor placement; out-of-ODD must reject.
                num=33 if i%1024==1 else 32 if i%256==1 else 1
                lane=(-g.S,g.S) if i%128==1 else (-1800000,1800000)
                result=g.b3_geom(tr,(o,)*num,lane=lane)
                if block=='b7':
                    pool=[g.GeomResult(False,-1,'none',0)]*16
                    cid=rng.randrange(16);pool[cid]=result
                    choice,label=g.b7_select(pool)
                    ok=label!='MITIGATION'
                    safe=not ok or choice==cid and g.LIBRARY[cid][1]>0
                else:ok=result.accept
                if ok:
                    # Determine initial side exactly, include footprint + .5 reserve.
                    exact=(oracle.minimum(F(gap,g.S),F(lv,g.S),F(la,g.S),F(v,g.S),F(a,g.S),F(h,g.T))
                           if o.x>=x else oracle.minimum(F(x-o.x-4800000,g.S),F(v,g.S),F(a,g.S),F(lv,g.S),F(la,g.S),F(h,g.T)))
                    m=exact-F(1,2)
                    safe=safe and m>=0 and lane[0]<=-g.S and lane[1]>=g.S
            else:
                v=rng.choice((0,1,10*g.S)) if i%32==2 else rng.randrange(10*g.S+1)
                a=-rng.randrange(8*g.S+1);cid=rng.randrange(16)
                x=rng.choice((-10000*g.S,10000*g.S,0)) if i%64==2 else rng.randrange(-9000*g.S,9000*g.S)
                if i%1024==2:v=(1<<31)-1
                tr=g.b4_mrmgen(x,v,a,cid);ok=tr.accept
                if ok:
                    # Exact Fraction integration, independent of golden numerators.
                    xlo=xhi=F(x,g.S);vlo=vhi=F(v,g.S)
                    b,j,_=g.LIBRARY[cid];target=F(-b,g.S);initial=F(a,g.S)
                    for row,nxt in zip(tr.rows,tr.rows[1:]):
                        t=row[0];h=F(nxt[0]-t,g.T)
                        change=F(j,g.S)*max(F(0),F(t-g.DT,g.T))
                        start=initial if t<g.DT else target if not j else min(F(0),max(initial-change,min(initial+change,target)))
                        jerk=F(0) if t<g.DT or start==target else F(-j if start>target else j,g.S)
                        # Stop/hold has zero velocity; x remains constant even if commanded a<0.
                        (ll,lh),(vl1,vl2)=oracle.ramp(xlo,vlo,start,jerk,target,h)
                        (hl,hh),(vh1,vh2)=oracle.ramp(xhi,vhi,start,jerk,target,h)
                        xlo,xhi,vlo,vhi=ll,hh,vl1,vh2
                        if not (F(nxt[1],g.S)<=xlo<=xhi<=F(nxt[2],g.S)
                                and F(nxt[3],g.S)<=vlo<=vhi<=F(nxt[4],g.S)):
                            safe=False;break
                    safe=safe and tr.rows[-1][4]==0 and tr.rows[-1][0]>=tr.stop+2*g.T
            if ok:
                accepted[block]=accepted.get(block,0)+1
                if m is not None:margin=m if margin is None else min(margin,m)
            if ok and not safe:
                badcount+=1
                if len(errors)<100:errors.append(dict(index=i,block=block,kind='unsafe_accept'))
        except Exception as exc:
            badcount+=1
            if len(errors)<100:errors.append(dict(index=i,block=block,kind=type(exc).__name__,message=str(exc)))
        if (i+1)%10000==0:
            result=dict(inputs=i+1,counts=counts,accepted=accepted,counterexamples=badcount,examples=errors,
                        min_separation_residual=str(margin),seconds=time.perf_counter()-started,
                        gate='PASS' if not badcount and i+1>=1000000 else 'FAIL' if badcount else 'INCONCLUSIVE')
            (out/'v2_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
            if (i+1)%50000==0:print('V2',i+1,'counterexamples',len(errors),'seconds',round(result['seconds']),flush=True)
    return result
