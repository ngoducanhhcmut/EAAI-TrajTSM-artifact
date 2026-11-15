"""SU (G1c) vectors from golden disp_lb/disp_ub/advance_lb and the B3 inflation term."""
import sys,random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'golden')); sys.path.insert(0,str(ROOT.parent/'tsm2_pilot/vendor'))
from tsmx_golden import model as g
T=g.T; S=g.S
def u(x,b): return x&((1<<b)-1)
rng=random.Random(20261030); rows=[]
def add(mode,up,x,v,a,w,j):
    fault=0; xo=vo=disp=lin=infl=0
    if mode==1:
        if w>100000: fault=1
        else: infl=g.ceildiv(j*w*w*w,8*T*T*T)+g.ceildiv(w*w,2*T*T)
    else:
        if w>100000 or not (0<=v<=20*S and -8*S<=a<=2*S) or x==-(1<<63): fault=1
        else:
            disp=g.disp_ub(v,a,w) if up else g.disp_lb(v,a,w)
            lin=g.ceildiv(v*w,T) if up else (v*w)//T
            try: xo,vo=g.advance_lb(x,v,a,w,bool(up))
            except ValueError: fault=1; xo=vo=0
    word=0
    for val,b in ((mode,1),(up,1),(u(x,64),64),(v,32),(u(a,32),32),(w,32),(j,32),(fault,1),(u(xo,64),64),(vo,32),(disp,64),(lin,64),(infl,64)):
        word=(word<<b)|u(val,b)
    rows.append('%0121x'%word)
edge_v=[0,1,999999,1000000,1000001,20*S,20*S+1]
edge_a=[-8*S,-8*S-1,-1,0,1,2*S,2*S+1]
edge_w=[0,1,2,99999,100000,100001,50000]
for v in edge_v:
    for a in edge_a:
        for w in edge_w:
            for up in (0,1): add(0,up,rng.randrange(-10**10,10**10),v,a,w,0)
for x in ((1<<63)-1,(1<<63)-2,-(1<<63),-(1<<63)+1,0):
    for up in (0,1): add(0,up,x,20*S,2*S,100000,0); add(0,up,x,0,0,1,0)
for j in (0,1,2*S,4*S,8*S):
    for w in edge_w: add(1,0,0,0,0,w,j)
for i in range(20000):
    up=rng.randrange(2); v=rng.randrange(20*S+1); a=rng.randrange(-8*S,2*S+1)
    w=rng.choice((100000,rng.randrange(1,100001),rng.randrange(1,1000)))
    if i%7==0: v=rng.randrange(0,2000)  # stops early in the cell
    add(0,up,rng.randrange(-10**10,10**10),v,a,w,0)
for i in range(2000): add(1,0,0,0,0,rng.randrange(0,100001),rng.randrange(0,8*S+1))
Path(__file__).with_name('vectors.mem').write_text('\n'.join(rows)+'\n')
Path(__file__).with_name('vectors_meta.svh').write_text(f'localparam int N={len(rows)};\n')
print('rows',len(rows))
