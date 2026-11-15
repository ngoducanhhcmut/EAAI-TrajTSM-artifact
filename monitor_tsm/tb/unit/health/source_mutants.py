"""Real source defects, isolated under this TB folder; dependencies stay read-only."""
import subprocess,json,time
from pathlib import Path
from run import HERE,HW,call
def main():
    src=(HW/'rtl/health/m_tsmx_health.sv').read_text()
    changes=[('parity','w_good_nxt=reg_good && w_par','w_good_nxt=reg_good',384,400),
             ('lane','reg_req[8]==reg_req[7]',"1'b1",320,324),
             ('onehot',"reg_req[6:1]!=6'd0","1'b0",0,1),
             ('stop',"LPARA_STOP = 32'd1100000","LPARA_STOP = 32'd1100001",0,1)]
    files=[HW/'rtl'/s for s in (HW/'rtl/filelist_R11.f').read_text().splitlines() if s and not s.startswith('//')]
    out=[]
    for name,old,new,start,end in changes:
        assert old in src
        folder=HERE/'source_mutants'/name;folder.mkdir(parents=True,exist_ok=True)
        altered=folder/'m_tsmx_health.sv';altered.write_text(src.replace(old,new,1))
        cmd=['iverilog','-g2012','-s','tb_m_tsmx_health','-I',str(HERE),'-o',str(folder/'sim.vvp')]+[str(altered if f.name==altered.name else f) for f in files]+[str(HERE/'tb_m_tsmx_health.sv')]
        r=call(cmd,f'source_mutants/{name}/compile.log');assert r['returncode']==0
        r=call(['vvp',str(folder/'sim.vvp'),f'+START={start}',f'+END={end}'],f'source_mutants/{name}/simulation.log')
        s=(HERE/r['log']).read_text();r.update(name=name,killed=r['returncode']!=0 and 'ASSERT_FAIL 7 ' in s)
        out.append(r);print(name,r['killed'],flush=True);assert r['killed'],s[-1500:]
    (HERE/'source_mutants.json').write_text(json.dumps(out,indent=2)+'\n')
if __name__=='__main__':main()
