"""Compile unmodified integration bench; keep all outputs here."""
import subprocess,json
from packetizer import HERE,HW
def main():
    sources=[str(HW/'rtl'/s) for s in (HW/'rtl/filelist_top.f').read_text().splitlines() if s and not s.startswith('//')]
    cmd=['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_m_tsmx_top',
         '-P','tb_m_tsmx_top.LANES=2','-I',str(HW/'tb/integ'),'-o',str(HERE/'smoke.vvp')]+sources+[str(HW/'tb/integ/tb_m_tsmx_top.sv')]
    with (HERE/'icarus_compile.log').open('w') as f:
        f.write(subprocess.list2cmdline(cmd)+'\n');f.flush()
        p=subprocess.run(cmd,cwd=HERE,stdout=f,stderr=subprocess.STDOUT,timeout=60)
    result=dict(compile_exit=p.returncode,simulated_jobs=0,status='compile failed')
    if p.returncode==0:
        with (HERE/'icarus_smoke.log').open('w') as f:
            try:
                p=subprocess.run(['C:/iverilog/bin/vvp.exe','-i',str(HERE/'smoke.vvp'),
                                  '+FILE=cosim_0103.mem','+LIMIT=2','+ALLOW_INACTIVE'],
                                  cwd=HERE,stdout=f,stderr=subprocess.STDOUT,timeout=60)
                result.update(simulation_exit=p.returncode,status='see simulation log')
            except subprocess.TimeoutExpired:result['status']='simulation stopped after 60 s; agreement unresolved'
    (HERE/'smoke.json').write_text(json.dumps(result,indent=2))
    print(result)
if __name__=='__main__':main()
