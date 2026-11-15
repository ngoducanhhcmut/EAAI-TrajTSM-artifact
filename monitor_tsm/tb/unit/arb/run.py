"""TSM-X / TSMX project / v0.1. Reproduce Icarus/Verilator and mutation evidence."""
import sys
sys.dont_write_bytecode=True
import json
import shutil
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
RTL=ROOT/'rtl/arb/m_tsmx_arb.sv'
TB=HERE/'tb_m_tsmx_arb.sv'


def run(cmd,log,timeout=120):
    r=subprocess.run([str(c) for c in cmd],cwd=HERE,stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT,text=True,timeout=timeout)
    log.write_text('COMMAND '+subprocess.list2cmdline([str(c) for c in cmd])+'\n'+r.stdout+
                   f'\nEXIT {r.returncode}\n',encoding='utf8')
    return r


def main():
    verilator='--verilator' in sys.argv
    if verilator:
        tool=shutil.which('verilator')
        if not tool:
            print('Verilator5 unavailable: build/simulation NOT RUN'); return 3
        cmd=[tool,'--binary','--timing','--assert','-Wno-fatal','--top-module','tb_m_tsmx_arb',
             '--Mdir',HERE/'obj_dir','-I'+str(HERE),RTL,TB]
        r=run(cmd,HERE/'verilator_compile.log',600)
        if r.returncode: raise RuntimeError(r.stdout)
        exe=HERE/'obj_dir/Vtb_m_tsmx_arb'
        if not exe.exists(): exe=exe.with_suffix('.exe')
        r=run([exe],HERE/'verilator_simulation.log')
        if r.returncode: raise RuntimeError(r.stdout)
        print(r.stdout); return 0
    tool=shutil.which('iverilog'); vvp=shutil.which('vvp')
    if not tool or not vvp: raise RuntimeError('Icarus is required')
    run([tool,'-V'],HERE/'tool_version.log')
    exe=HERE/'sim.vvp'
    cmd=[tool,'-g2012','-s','tb_m_tsmx_arb','-I',HERE,'-o',exe,RTL,TB]
    r=run(cmd,HERE/'compile.log')
    if r.returncode: raise RuntimeError(r.stdout)
    r=run([vvp,exe],HERE/'simulation.log')
    if r.returncode or 'PASS arb:' not in r.stdout: raise RuntimeError(r.stdout)
    print(r.stdout[-350:])
    results=dict(baseline=True,assertions=36,mutants=[],source_mutants=[])
    if '--mutants' in sys.argv:
        folder=HERE/'mutants';folder.mkdir(exist_ok=True)
        for p in json.loads((HERE/'assertions.json').read_text()):
            n=p['id']; r=run([vvp,exe,f'+MUTANT={n}'],folder/f'M{n:02}.log')
            killed=r.returncode!=0 and f'ASSERT_FAIL {n} {p["name"]}' in r.stdout
            results['mutants'].append(dict(id=n,name=p['name'],killed=killed,exit=r.returncode))
            if not killed: raise RuntimeError(f'mutant{n}: '+r.stdout)
        folder=HERE/'source_mutants';folder.mkdir(exist_ok=True)
        original=RTL.read_text()
        mutations=[
            ('wrong_L3_profile',"w_cmd_cand = 8'(LPARA_MIT_ID);","w_cmd_cand = 8'd0;"),
            ('wrong_backup_apply','w_apply = w_plan[239:208];','w_apply = w_now;'),
            ('wrong_expiry','w_expiry = w_cert[671:640];',"w_expiry = 32'd0;"),
            ('missing_pending_guard','w_pending_valid && w_pending_cert[1216]',"1'b1"),
            ('instant_selected','LPARA_FINITE[w_cand[3:0]]',"1'b1"),
            ('stall_ignored','if (i_rsp_ready)',"if (1'b1)"),
            ('override_not_sticky',"if (i_override) w_brake_nxt = 1'b1;","if (i_override) w_brake_nxt = reg_brake;"),
            ('drop_hash_bit','w_cert = w_pending_cert;','w_cert = w_pending_cert ^ 1217\'d1;'),
            ('no_immediate_override','!i_rst_n_core || i_override || reg_brake','!i_rst_n_core || reg_brake'),
        ]
        for name,old,new in mutations:
            assert original.count(old)==1,(name,old)
            path=folder/f'{name}.sv';path.write_text(original.replace(old,new),encoding='ascii')
            output=folder/f'{name}.vvp'
            c=cmd.copy(); c[c.index('-o')+1]=output; c[-2]=path
            r=run(c,folder/f'{name}_compile.log')
            if r.returncode: raise RuntimeError(r.stdout)
            r=run([vvp,output],folder/f'{name}.log')
            killed=r.returncode!=0 and ('ASSERT_FAIL' in r.stdout or 'asynchronous override missed' in r.stdout)
            results['source_mutants'].append(dict(name=name,killed=killed,exit=r.returncode))
            if not killed: raise RuntimeError(name+': '+r.stdout)
    (HERE/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf8')
    print(f'Mutants killed {len(results["mutants"])}/{len(results["mutants"])}; source mutants {len(results["source_mutants"])}/{len(results["source_mutants"])}')
    return 0


if __name__=='__main__': sys.exit(main())
