"""G1c (Claude 30/10): soundness + conservatism of division-free B3 (swept_lb/advance_lb).
1) V2 B2/B3/B4/B7 random audit with the independent Fraction oracle (soundness.run).
2) Multi-cell implication on real B4 trajectories + event-split objects:
   new b3 ACCEPT must imply old (exact-rational, G1-proven) b3 ACCEPT.
3) Single-cell exact check of swept_lb against oracle.minimum (all sign cases)."""
import sys,json,random,pathlib,time
from fractions import Fraction as F
sys.path.insert(0,'tsmx_hw/verify'); sys.path.insert(0,'tsmx_hw/golden'); sys.path.insert(0,'tsm2_pilot/vendor')
from tsmx_golden import model as g
import importlib.util,soundness,oracle
out=pathlib.Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
n2=int(sys.argv[2]) if len(sys.argv)>2 else 200000
res={}
t0=time.time(); r=soundness.run(out,n=n2); res['v2']={k:r[k] for k in ('counts','accepted','counterexamples') if k in r}; res['v2_s']=round(time.time()-t0,1)
# old exact-rational B3, reconstructed from the G1 functions still in the module
def b3_old(traj,objects,lane=(-1800000,1800000)):
    saved=(g.swept_lb,g.advance_lb)
    try:
        g.swept_lb=g.swept; g.advance_lb=g.advance
        return g.b3_geom.__wrapped__(traj,objects,lane) if hasattr(g.b3_geom,'__wrapped__') else g.b3_geom(traj,objects,lane)
    finally:
        g.swept_lb,g.advance_lb=saved
rng=random.Random(20261030); N=int(sys.argv[3]) if len(sys.argv)>3 else 20000
both=new_only=old_only=neither=0; worst_drop=0; errs=0
for i in range(N):
    v=rng.randrange(10*g.S+1); a=-rng.randrange(8*g.S+1); cid=rng.choice([c for c in range(16) if g.LIBRARY[c][1]])
    x=rng.randrange(-100*g.S,100*g.S)
    tr=g.b4_mrmgen(x,v,a,cid)
    if not tr.accept: continue
    objs=[]
    for _ in range(rng.choice((1,1,2,4,8))):
        ahead=rng.random()<0.7
        ox=x+(1 if ahead else -1)*(4800000+rng.randrange(0,40*g.S))
        oa=rng.randrange(-8*g.S,2*g.S+1); ev=rng.randrange(0,3000000); af=rng.randrange(-8*g.S,2*g.S+1)
        ov=rng.randrange(0,15*g.S)
        objs.append(g.Motion(ox,ov,oa,4800000,ev,af))
    try:
        nr=g.b3_geom(tr,tuple(objs)); orr=b3_old(tr,tuple(objs))
    except Exception as e:
        errs+=1; continue
    if nr.accept and orr.accept: both+=1; worst_drop=max(worst_drop,orr.margin-nr.margin)
    elif nr.accept: new_only+=1
    elif orr.accept: old_only+=1
    else: neither+=1
res['multicell']=dict(n=N,both=both,new_only_UNSAFE=new_only,old_only=old_only,neither=neither,max_margin_drop_um=worst_drop,exceptions=errs)
# single-cell exact: swept_lb <= exact continuous min (oracle), all sign combos
bad=0;cnt=0;maxgap=F(0)
for i in range(N*5):
    va=rng.randrange(20*g.S+1); vb=rng.randrange(20*g.S+1)
    aa=rng.randrange(-8*g.S,2*g.S+1); ab=rng.randrange(-8*g.S,2*g.S+1)
    h=rng.choice((1,2,50000,99999,100000,rng.randrange(1,100001)))
    gap=rng.randrange(-g.S,40*g.S)
    lb=g.swept_lb(gap,va,aa,vb,ab,h)
    ex=oracle.minimum(F(gap,g.S),F(va,g.S),F(aa,g.S),F(vb,g.S),F(ab,g.S),F(h,g.T))
    cnt+=1
    if F(lb,g.S)>ex: bad+=1
    maxgap=max(maxgap,ex-F(lb,g.S))
res['single_cell']=dict(n=cnt,unsound=bad,max_conservatism_m=float(maxgap))
print(json.dumps(res,indent=1)); (out/'g1c_results.json').write_text(json.dumps(res,indent=1))
