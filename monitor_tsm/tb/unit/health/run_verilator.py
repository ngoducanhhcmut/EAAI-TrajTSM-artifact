"""Run Verilator5 on the same SV/fixtures; all generated files remain in this unit folder."""
import subprocess,shutil,json
from pathlib import Path
from run import HERE,HW,call
def main():
    tool=shutil.which('verilator') or shutil.which('verilator_bin')
    if not tool:raise SystemExit('Verilator5 unavailable; no compile/simulation claim')
    v=subprocess.check_output([tool,'--version'],text=True)
    assert 'Verilator 5.' in v,v
    files=[str(HW/'rtl'/x) for x in (HW/'rtl/filelist_R11.f').read_text().splitlines() if x and not x.startswith('//')]
    cmd=[tool,'--binary','--timing','--assert','-Wno-fatal','--top-module','tb_m_tsmx_health','-I'+str(HERE),'--Mdir',str(HERE/'obj_dir')]+files+[str(HERE/'tb_m_tsmx_health.sv')]
    r=call(cmd,'verilator_compile.log',1800);assert r['returncode']==0
    exe=HERE/'obj_dir/Vtb_m_tsmx_health'
    if not exe.exists():exe=exe.with_suffix('.exe')
    r=call([str(exe)],'verilator_simulation.log',1800);assert r['returncode']==0
    mutants=[]
    for i in range(26):
        r=call([str(exe),f'+MUTANT={i}','+END=1'],f'verilator_mutant_{i:02}.log')
        assert r['returncode']!=0 and f'ASSERT_FAIL {i} ' in (HERE/r['log']).read_text()
        mutants.append(r)
    (HERE/'verilator_mutants.json').write_text(json.dumps(mutants,indent=2)+'\n')
if __name__=='__main__':main()
