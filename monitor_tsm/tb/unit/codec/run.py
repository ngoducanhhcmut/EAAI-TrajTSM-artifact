"""Reproduce generation, Icarus baseline, assertion/source mutants and VLSIT checks."""
import sys
sys.dont_write_bytecode=True
import subprocess,json,shutil,os
from pathlib import Path
HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
RTL=REPO/'tsmx_hw/rtl'
SKILL=REPO/'.agents/skills/vlsit-rtl-generator/scripts'
os.chdir(HERE)
def run(args,log,timeout=120):
    with open(log,'w',encoding='utf-8') as f:
        f.write('COMMAND: '+subprocess.list2cmdline([str(x) for x in args])+'\n');f.flush()
        p=subprocess.run([str(x) for x in args],stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
        f.write(f'\nEXIT: {p.returncode}\n')
    return p.returncode
def compile_to(out,core=None):
    return run(['iverilog','-g2012','-s','tb_m_tsmx_codec','-o',out,
        core or RTL/'codec/m_tsmx_codec_core.sv',RTL/'codec/m_tsmx_codec.sv','tb_m_tsmx_codec.sv'],str(out)+'.compile.log')
def main():
    if '--checks-only' in sys.argv:
        checks();return
    for f in ('gen_vectors.py','build_tb.py'):
        assert run([sys.executable,'-B',f],f+'.log')==0
    assert compile_to('simulation.vvp')==0
    if '--mutants-only' not in sys.argv:
        print('Running full codec baseline',flush=True)
        assert run(['vvp','simulation.vvp','+NOGAPS'],'simulation.log',1800)==0
        assert 'PASS codec:' in Path('simulation.log').read_text()
        for supplement in ('focus_faults.py','format_boundaries.py'):
            assert run([sys.executable,'-B',supplement],supplement+'.log',300)==0
    if '--baseline-only' in sys.argv:return
    results=[]
    Path('mutants').mkdir(exist_ok=True)
    for i in range(30):
        log=f'mutants/M{i:02}.log'
        rc=run(['vvp','simulation.vvp',f'+MUTANT={i}'],log,120)
        text=Path(log).read_text()
        killed=rc!=0 and f'ASSERT_FAIL {i} ' in text and f'INJECT {i} ' in text
        results.append(dict(id=i,killed=killed,exit=rc))
        assert killed,(i,text[-1000:])
        print(f'Assertion mutant {i}: killed',flush=True)
    source=(RTL/'codec/m_tsmx_codec_core.sv').read_text()
    mutations=[('crc_polynomial',"32'hedb88320","32'hedb88321"),
        ('sha_iv',"32'h6a09e667","32'h6a09e666"),
        ('sha_round',"32'h428a2f98","32'h428a2f99"),
        ('padding',"32'h80000000","32'h40000000"),
        ('response_stall','if (i_rsp_ready) begin',"if (1'b1) begin"),
        ('sha_length',"w_word=32'(reg_len<<3)","w_word=32'(reg_len<<2)")]
    src_results=[]
    Path('source_mutants').mkdir(exist_ok=True)
    for name,old,new in mutations:
        assert old in source
        p=Path('source_mutants')/(name+'.sv');p.write_text(source.replace(old,new,1))
        out=p.with_suffix('.vvp');assert compile_to(out,p)==0
        log=p.with_suffix('.log');rc=run(['vvp',out],log,120)
        killed=rc!=0 and 'ASSERT_FAIL' in log.read_text()
        src_results.append(dict(name=name,old=old,new=new,killed=killed,exit=rc))
        assert killed,name
        print(f'Source mutant {name}: killed',flush=True)
    Path('mutants.json').write_text(json.dumps(dict(assertions=results,source=src_results),indent=2)+'\n')
    checks()
def checks():
    for action,args in [('gaps',['vlsit_spec_gaps.py','gaps',REPO/'tsmx_hw/spec/TSMX_Design_Specification.md']),
       ('rules',['vlsit_rtl_check.py','check',RTL/'codec']),
       ('coverage',['vlsit_rtl_check.py','coverage']),
       ('filelist',['vlsit_lint_rtl.py','filelist',RTL/'codec','--out',RTL/'filelist_R3.f','--top','m_tsmx_codec']),
       ('lint',['vlsit_lint_rtl.py','lint',RTL/'filelist_R3.f','--top','m_tsmx_codec'])]:
        run([sys.executable,SKILL/args[0],*args[1:]],action+'.log')
    verilator=shutil.which('verilator')
    if verilator:
        rc=run([verilator,'--binary','--timing','--assert','-Wno-fatal','--top-module','tb_m_tsmx_codec',
            RTL/'codec/m_tsmx_codec_core.sv',RTL/'codec/m_tsmx_codec.sv','tb_m_tsmx_codec.sv'],'verilator_compile.log',600)
        if rc==0:run([HERE/'obj_dir/Vtb_m_tsmx_codec'],'verilator_simulation.log',600)
    else:Path('verilator_compile.log').write_text('NOT RUN: Verilator5 unavailable; no tool installed.\n')
if __name__=='__main__':main()
