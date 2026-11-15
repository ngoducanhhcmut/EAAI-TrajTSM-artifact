"""Spec15: mutate copies of I1-owned engine only; accepted leaf files are untouched."""
import argparse,json,subprocess,sys
from run import HERE,ROOT,run
source=ROOT/'rtl/top/m_tsmx_engine.sv'
ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['iverilog','verilator'],default='iverilog');a=ap.parse_args()
text=source.read_text()
cases=[('fsm_twohot',"ENUM_ST_IDLE = 76'h2,","ENUM_ST_IDLE = 76'h3,",18),
       ('brake_low','o_brake=!i_rst_n_core || reg_override || w_arb_brake || reg_final_rsp[9];',
        "o_brake=1'b0;",17)]
results=[]
for name,old,new,assertion in cases:
    folder=HERE/'mutants'/name;folder.mkdir(exist_ok=True)
    assert text.count(old)==1
    copy=folder/source.name;copy.write_text(text.replace(old,new))
    files=[ROOT/'rtl'/x for x in (ROOT/'rtl/filelist_top.f').read_text().splitlines()
           if x and not x.startswith('//')]
    files=[copy if x==source else x for x in files]
    if a.tool=='iverilog':
        binary=folder/'mutant.vvp'
        cmd=['iverilog','-g2012','-s','tb_m_tsmx_top','-I',HERE,'-o',binary]
        sim=['vvp','-i',binary]
    else:
        build=folder/'obj';binary=build/'Vtb_m_tsmx_top'
        cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','-j','4',
             '--top-module','tb_m_tsmx_top',f'-I{HERE}','-Mdir',build]
        sim=[binary]
    rc=run(cmd+files+[HERE/'tb_m_tsmx_top.sv'],str(folder/'compile.log'))
    if rc:raise SystemExit(rc)
    rc=run(sim+['+FILE=smoke.mem','+LIMIT=2'],str(folder/'simulation.log'))
    result=(folder/'simulation.log').read_text()
    killed=rc!=0 and f'ASSERT_FAIL {assertion} ' in result
    results.append(dict(name=name,assertion=assertion,killed=killed,exit=rc))
    print(name,'killed=',killed)
(HERE/'source_mutants.json').write_text(json.dumps(results,indent=2))
sys.exit(0 if all(x['killed'] for x in results) else 1)
