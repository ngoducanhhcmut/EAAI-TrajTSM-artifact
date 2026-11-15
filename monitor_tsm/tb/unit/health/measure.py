"""Capacity1 and legal/illegal elaboration checks, plus no-stall BIST budget replay."""
import json,re
from run import HERE,HW,call
def main():
    files=[str(HW/'rtl'/x) for x in (HW/'rtl/filelist_R11.f').read_text().splitlines() if x and not x.startswith('//')]
    cmd=['iverilog','-g2012','-s','tb_m_tsmx_health','-I',str(HERE),'-Ptb_m_tsmx_health.WORD_LIMIT=1','-o',str(HERE/'param.vvp')]+files+[str(HERE/'tb_m_tsmx_health.sv')]
    r=call(cmd,'param_compile.log');assert r['returncode']==0
    r=call(['vvp',str(HERE/'param.vvp'),'+START=324','+END=384'],'param_simulation.log',300)
    assert r['returncode']==0,(HERE/r['log']).read_text()[-3000:]
    results=dict(capacity1=r,illegal=[])
    for p in [0,1025]:
        r=call(['iverilog','-g2012','-s','m_tsmx_health',f'-Pm_tsmx_health.PARA_HEALTH_WORDS={p}','-o',str(HERE/'invalid.vvp'),str(HW/'rtl/health/m_tsmx_health.sv')],f'invalid_{p}.log')
        assert r['returncode']!=0 and 'm_tsmx_bad_health_para' in (HERE/r['log']).read_text()
        results['illegal'].append(r)
    cmd=['iverilog','-g2012','-s','tb_m_tsmx_health','-I',str(HERE),'-o',str(HERE/'measure.vvp')]+files+[str(HERE/'tb_m_tsmx_health.sv')]
    r=call(cmd,'measure_compile.log');assert r['returncode']==0
    n=json.loads((HERE/'vectors.json').read_text())['total']
    r=call(['vvp',str(HERE/'measure.vvp'),f'+START={n-2}',f'+END={n}','+NO_STALL=1'],'measure.log',300)
    assert r['returncode']==0,(HERE/r['log']).read_text()[-3000:]
    results['budget']=r
    s=(HERE/'measure.log').read_text();results['measure']=re.findall(r'MEASURE.*',s)
    results['jobs']=re.findall(r'JOB.*',s)
    (HERE/'measure.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
if __name__=='__main__':main()
