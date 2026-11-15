"""Portable Icarus / Verilator5 integration replay. Writes only I1 TB evidence."""
import argparse,json,shutil,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
def run(cmd,log,cwd=HERE):
    original=list(cmd)
    if str(cmd[0]).endswith('.bat'):
        batch=HERE/(Path(log).stem+'.cmd')
        batch.write_text('@echo off\ncall '+' '.join('"'+str(x)+'"' for x in cmd)+'\nexit /b %errorlevel%\n')
        cmd=['cmd.exe','/d','/c',str(batch)]
    with (HERE/log).open('w') as f:
        f.write('COMMAND: '+subprocess.list2cmdline(list(map(str,original)))+'\n');f.flush()
        p=subprocess.run(list(map(str,cmd)),cwd=cwd,stdout=f,stderr=subprocess.STDOUT)
    return p.returncode
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['iverilog','verilator','xsim'],default='iverilog')
    ap.add_argument('--lanes',type=int,default=2);ap.add_argument('--limit',type=int);ap.add_argument('--compile-only',action='store_true');ap.add_argument('--skip-compile',action='store_true');ap.add_argument('--trace',action='store_true');ap.add_argument('--file',default='vectors.mem')
    ap.add_argument('--allow-inactive',action='store_true',help='focused diagnostic only; prints inactive checks')
    ap.add_argument('--bist-fault',action='store_true',help='use separate verification-only BIST fault source')
    ap.add_argument('--tag',default='',help='unique evidence name when running categories concurrently')
    ap.add_argument('--worst',action='store_true',help='require two complete sweeps, 32 objects, streaming and S1b budget')
    ap.add_argument('--worst-rows',type=int,default=77,help='A8: expected longest MRM tail (77 at a<=0, 93 at a=+2 m/s^2)')
    ap.add_argument('--synthesis',action='store_true',help='repeat identical datapath with SYNTHESIS defined')
    args=ap.parse_args()
    if args.synthesis and args.tool=='xsim':ap.error('--synthesis supports Icarus and Verilator only')
    if args.tool!='xsim' and not shutil.which(args.tool):print('Unavailable:',args.tool);return 3
    sources=[str(ROOT/'rtl'/x) for x in (ROOT/'rtl/filelist_top.f').read_text().splitlines() if x and not x.startswith('//')]
    tb=HERE/('tb_m_tsmx_top_bist.sv' if args.bist_fault else 'tb_m_tsmx_top.sv')
    suffix='_bist' if args.bist_fault else ''
    if args.synthesis:suffix+='_synthesis'
    evidence='_'+args.tool+('_'+args.tag if args.tag else '')
    if args.bist_fault:args.file='bist_fault.mem';args.limit=1
    if args.tool=='iverilog':
        binary=HERE/f'top_{args.lanes}{suffix}.vvp'
        cmd=['iverilog','-g2012','-s','tb_m_tsmx_top','-P',f'tb_m_tsmx_top.LANES={args.lanes}','-I',HERE,'-o',binary]+sources+[tb]
        sim=['vvp','-i',binary]
    elif args.tool=='xsim':
        bindir=Path('C:/Vivado/Vivado/2023.2/bin')
        if not args.skip_compile:
            tbfile=HERE/f'tb_xsim_{args.lanes}.sv'
            tbfile.write_text(tb.read_text().replace('LANES=2;',f'LANES={args.lanes};'))
            rc=run([bindir/'xvlog.bat','--sv','-i',HERE]+sources+[tbfile],f'xvlog_{args.lanes}.log')
            if rc:print('xvlog failed');return rc
        binary=f'top_{args.lanes}'
        cmd=[bindir/'xelab.bat','--snapshot',binary,'--mt','4','--timescale','1ns/1ps','work.tb_m_tsmx_top']
        sim=[bindir/'xsim.bat',binary,'--runall']
    else:
        build=HERE/f'obj_{args.lanes}{suffix}';binary=build/'Vtb_m_tsmx_top'
        cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','-j','4','--top-module','tb_m_tsmx_top',f'-GLANES={args.lanes}',f'-I{HERE}','-Mdir',build]+sources+[tb]
        sim=[binary]
    if args.synthesis:cmd.insert(1,'-DSYNTHESIS')
    if not args.skip_compile:
        rc=run(cmd,f'compile_{args.lanes}{suffix}{evidence}.log')
        if rc:print('Compile failed; see compile log');return rc
    if args.compile_only:return 0
    if args.limit:sim+=['--testplusarg',f'LIMIT={args.limit}'] if args.tool=='xsim' else [f'+LIMIT={args.limit}']
    sim+=['--testplusarg',f'FILE={args.file}'] if args.tool=='xsim' else [f'+FILE={args.file}']
    if args.trace:sim+=['--testplusarg','TRACE'] if args.tool=='xsim' else ['+TRACE']
    if args.allow_inactive:sim+=['--testplusarg','ALLOW_INACTIVE'] if args.tool=='xsim' else ['+ALLOW_INACTIVE']
    if args.worst:sim+=['--testplusarg','WORST'] if args.tool=='xsim' else ['+WORST']
    if args.worst:sim+=['--testplusarg',f'WORST_ROWS={args.worst_rows}'] if args.tool=='xsim' else [f'+WORST_ROWS={args.worst_rows}']
    rc=run(sim,f'simulation_{args.lanes}{suffix}{evidence}.log')
    result=(HERE/f'simulation_{args.lanes}{suffix}{evidence}.log').read_text()
    print(result[-4000:]);return rc if rc else (0 if 'PASS top jobs=' in result else 1)
if __name__=='__main__':sys.exit(main())
