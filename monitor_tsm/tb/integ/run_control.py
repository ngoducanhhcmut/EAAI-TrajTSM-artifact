"""I1 control test runner; --timers-only or --deadline-only selects one category."""
import argparse,sys
from pathlib import Path
from run import run,HERE,ROOT
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['iverilog','verilator','xsim'],default='iverilog');ap.add_argument('--lanes',type=int,default=2);ap.add_argument('--timers-only',action='store_true');ap.add_argument('--deadline-only',action='store_true');ap.add_argument('--skip-compile',action='store_true');a=ap.parse_args()
    files=[ROOT/'rtl'/x for x in (ROOT/'rtl/filelist_top.f').read_text().splitlines() if x and not x.startswith('//')]
    physical=not a.timers_only
    top='tb_tsmx_control_phy' if physical else 'tb_tsmx_control'
    tb=HERE/(top+'.sv')
    if a.tool=='iverilog':
        binary=HERE/f'control_{a.lanes}{"_phy" if physical else ""}.vvp'
        cmd=['iverilog','-g2012','-s',top,'-P',f'{top}.LANES={a.lanes}','-o',binary]+files+[tb]
        sim=['vvp','-i',binary]
    elif a.tool=='verilator':
        build=HERE/f'obj_control_{a.lanes}'
        cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','-j','4','--top-module','tb_tsmx_control_phy',f'-GLANES={a.lanes}','-Mdir',build]+files+[HERE/'tb_tsmx_control_phy.sv']
        sim=[build/'Vtb_tsmx_control_phy']
    else:
        b=Path('C:/Vivado/Vivado/2023.2/bin')
        if not a.skip_compile:
            tmp=HERE/f'tb_control_xsim_{a.lanes}.sv';tmp.write_text(tb.read_text().replace('LANES=2;',f'LANES={a.lanes};'))
            if run([b/'xvlog.bat','--sv']+files+[tmp],'control_xvlog.log'):return 1
        cmd=[b/'xelab.bat','--snapshot',f'control_{a.lanes}','--mt','4',f'work.{top}']
        sim=[b/'xsim.bat',f'control_{a.lanes}','--runall']
    if not a.skip_compile and run(cmd,f'control_compile_{a.tool}_{a.lanes}.log'):return 1
    arg='TIMERS_ONLY' if a.timers_only else 'DEADLINE_ONLY' if a.deadline_only else ''
    if arg:sim+=['--testplusarg',arg] if a.tool=='xsim' else ['+'+arg]
    log=f'control_{a.tool}_{a.lanes}_{arg.lower() or "physical_all"}.log';rc=run(sim,log)
    result=(HERE/log).read_text();print(result[-2400:])
    return rc or (1 if 'Fatal:' in result or 'FATAL:' in result or 'PASS ' not in result else 0)
if __name__=='__main__':sys.exit(main())
