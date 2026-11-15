"""Regenerate vectors/TB, run Icarus and assertion/functional mutation campaigns.

From repository root: py -3.13 -B tsmx_hw/tb/unit/csr/run.py
Verilator 5: from this directory, run the command recorded in README.md.
"""
import sys,subprocess,json,shutil
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
RTL=ROOT/'rtl/csr/m_tsmx_csr.sv'
TB=HERE/'tb_m_tsmx_csr.sv'
def run(cmd,log,cwd=HERE):
    p=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True)
    log.write_text('COMMAND: '+subprocess.list2cmdline(list(map(str,cmd)))+'\n'+p.stdout+p.stderr)
    return p
def compile_design(rtl,out,log):
    p=run(['iverilog','-g2012','-s','tb_m_tsmx_csr','-I',HERE,'-o',out,rtl,TB],log)
    if p.returncode:raise RuntimeError(log.read_text())
def main():
    for script in ('gen_vectors.py','build_tb.py'):
        p=run([sys.executable,'-B',HERE/script],HERE/(script+'.log'))
        if p.returncode:raise RuntimeError(p.stdout+p.stderr)
    sim=HERE/'sim.vvp';compile_design(RTL,sim,HERE/'compile.log')
    p=run(['vvp',sim],HERE/'simulation.log')
    if p.returncode or 'PASS csr:' not in p.stdout:raise RuntimeError(p.stdout+p.stderr)
    print(next(x for x in p.stdout.splitlines() if x.startswith('PASS csr:')),flush=True)
    checks=json.loads((HERE/'assertions.json').read_text())
    mutants=HERE/'mutants';mutants.mkdir(exist_ok=True)
    killed=[]
    for idx,c in enumerate(checks):
        p=run(['vvp',sim,f'+MUTANT={idx}'],mutants/f'{idx:02}_{c["name"]}.log')
        ok=p.returncode!=0 and f'ASSERT_FAIL {idx} {c["name"]}' in p.stdout
        killed.append(dict(id=idx,name=c['name'],killed=ok,exit=p.returncode,kind=c['kind'],target=c['target']))
        if not ok:raise RuntimeError(f'Assertion mutant {idx} not detected by its own assertion: '+p.stdout)
    print(f'Assertion mutants killed: {len(killed)}/{len(checks)}',flush=True)
    source=RTL.read_text()
    changes=[
      ('w1c_set_loses','w_irq_sts_nxt = w_irq_sts_nxt | w_irq_set |','w_irq_sts_nxt = w_irq_sts_nxt | 8\'h00 |'),
      ('ignore_byte_strobes','{LPARA_BYTE_W{reg_wstrb[idx]}}',"{LPARA_BYTE_W{1'b1}}"),
      ('aw_requires_w',"i_rst_n_core && !reg_aw_full && !reg_bvalid;","i_rst_n_core && !reg_aw_full && !reg_bvalid && i_axi_wvalid;"),
      ('ro_write_okay',"default: w_bad = 1'b1;","default: w_bad = 1'b0;"),
      ('enable_without_bist','(w_active || !reg_config_valid)','(w_active)'),
      ('fault_counter_rollover',"!i_sts_data[114] && (reg_fault_cnt != 32'hffffffff)","!i_sts_data[114]"),
      ('status_not_atomic',"w_sts_nxt[7] = i_sts_data[74];","w_sts_nxt[7] = i_sts_data[75];"),
      ('reserved_read_leak',"{31'b0,reg_en}","{31'h7fffffff,reg_en}"),
    ]
    srcdir=HERE/'source_mutants';srcdir.mkdir(exist_ok=True);source_results=[]
    for name,old,new in changes:
        assert source.count(old)==1,(name,source.count(old))
        path=srcdir/(name+'.sv');path.write_text(source.replace(old,new))
        out=srcdir/(name+'.vvp');compile_design(path,out,srcdir/(name+'_compile.log'))
        p=run(['vvp',out],srcdir/(name+'.log'))
        ok=p.returncode!=0 and 'ASSERT_FAIL' in p.stdout
        source_results.append(dict(name=name,old=old,new=new,killed=ok,exit=p.returncode))
        if not ok:raise RuntimeError(f'Source mutant {name} survived')
    print(f'Functional source mutants killed: {len(source_results)}/{len(changes)}',flush=True)
    (HERE/'mutation_summary.json').write_text(json.dumps(dict(assertions=killed,source=source_results),indent=2)+'\n')
    if shutil.which('verilator'):
        p=run(['verilator','--binary','--timing','--assert','-Wno-fatal','--top-module','tb_m_tsmx_csr','--Mdir',HERE/'obj_dir','-I'+str(HERE),RTL,TB],HERE/'verilator_compile.log')
        if p.returncode:raise RuntimeError('Verilator compile failed: '+p.stdout+p.stderr)
        exe=HERE/'obj_dir/Vtb_m_tsmx_csr'
        if not exe.exists():exe=exe.with_suffix('.exe')
        p=run([exe],HERE/'verilator_simulation.log')
        if p.returncode or 'PASS csr:' not in p.stdout:raise RuntimeError(p.stdout+p.stderr)
    else:(HERE/'verilator_compile.log').write_text('NOT RUN: Verilator 5 is not installed; R-015.\n')
if __name__=='__main__':main()
