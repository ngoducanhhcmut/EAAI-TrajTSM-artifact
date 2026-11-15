"""Independent rational continuous-motion oracle. Never imported by golden."""
from fractions import Fraction as F

def adv(x,v,a,h):
    t=min(h,-v/a) if a<0 else h
    return x+v*t+a*t*t/2,max(F(0),v+a*h)

def minimum(g,va,aa,vb,ab,h):
    cuts=sorted({F(0),h,*[-v/a for v,a in ((va,aa),(vb,ab)) if a<0 and 0<-v/a<h]})
    result=g
    for l,r in zip(cuts,cuts[1:]):
        xa,ua=adv(F(0),va,aa,l);xb,ub=adv(F(0),vb,ab,l)
        gap=g+xa-xb;rv=ua-ub
        ra=(aa if ua>0 else max(0,aa))-(ab if ub>0 else max(0,ab))
        ts=[F(0),r-l]
        if ra and 0<-rv/ra<r-l:ts.append(-rv/ra)
        result=min(result,*(gap+rv*t+ra*t*t/2 for t in ts))
    return result

def ramp(x,v,a,j,target,h):
    if v==0:return (x,x),(F(0),F(0))
    if j==0:
        xx,vv=adv(x,v,a,h)
        return (xx,xx),(vv,vv)
    tau=min(h,abs((target-a)/j)) if j else F(0)
    def pos(t):
        u=min(t,tau)
        return x+v*t+a*t*t/2+j*(t**3-(t-u)**3)/6
    def vel(t):
        u=min(t,tau)
        return v+a*t+j*(u*t-u*u/2)
    if vel(h)>=0:return (pos(h),pos(h)),(vel(h),vel(h))
    lo,hi=F(0),h
    # Isolate first zero; monotone v, endpoint position error bounded by v0*width.
    for _ in range(45):
        mid=(lo+hi)/2
        if vel(mid)>=0:lo=mid
        else:hi=mid
    return (pos(lo),pos(lo)+v*(hi-lo)),(F(0),F(0))

def splice(e,p,S):
    d=F(max(0,((p.apply-e.t+2**31)%2**32)-2**31),S)
    if d>F(1,10):return False
    xs=[];vs=[]
    for dx in (-F(1,20),F(1,20)):
        for dv in (-F(1,20),F(1,20)):
            for da in (-F(1,10),F(1,10)):
                x,v=adv(F(e.x,S)+dx,max(F(0),F(e.v,S)+dv),min(F(0),max(F(-8),F(e.a,S)+da)),d)
                xs.append(x);vs.append(v)
    return (min(xs)>=F(p.x,S)-F(4,25) and max(xs)<=F(p.x,S)+F(4,25)
            and min(vs)>=F(p.v,S)-F(1,5) and max(vs)<=F(p.v,S)+F(1,5))
