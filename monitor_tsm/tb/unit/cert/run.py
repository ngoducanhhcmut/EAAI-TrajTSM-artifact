"""Reproduce RTL/TB checks, simulation and assertion/source mutation evidence."""
# Project: TSM-X; Author: TSMX project; Version: 0.1.
import sys
sys.dont_write_bytecode=True
import subprocess, shutil, json, re, argparse
from pathlib import Path
P=Path(__file__).resolve().parent
ROOT=P.parents[2].parent
RTL=ROOT/'tsmx_hw/rtl'
def run(cmd,name,timeout=180):
    try:
        r=subprocess.run(list(map(str,cmd)),cwd=P,capture_output=True,text=True,timeout=timeout)
        text=r.stdout+r.stderr; code=r.returncode
    except subprocess.TimeoutExpired as e:
        def decode(x): return x.decode(errors='replace') if isinstance(x,bytes) else (x or '')
        text=decode(e.stdout)+decode(e.stderr);code=124
    (P/name).write_text('COMMAND '+subprocess.list2cmdline(list(map(str,cmd)))+'\nEXIT '+str(code)+'\n'+text)
    return code,text
def compile_sv(source=RTL/'cert/m_tsmx_cert.sv',out=P/'sim.vvp',log='compile.log'):
    return run(['iverilog','-g2012','-s','tb_m_tsmx_cert','-I',P,'-o',out,
                RTL/'arith/m_tsmx_arith_div.sv',RTL/'arith/m_tsmx_arith.sv',source,P/'tb_m_tsmx_cert.sv'],log)
def main():
    a=argparse.ArgumentParser();a.add_argument('--mutants',action='store_true');args=a.parse_args()
    code,text=compile_sv();assert code==0,text[-4000:]
    code,text=run(['vvp',P/'sim.vvp'],'simulation.log',300)
    print(text[-2500:]);assert code==0
    assert 'PASS cert:' in text
    hits={name:int(n) for name,n in re.findall(r'ASSERT \d+ (\w+) hits=(\d+)',text)}
    (P/'assertions.json').write_text(json.dumps(hits,indent=2)+'\n')
    if args.mutants:
        result=[];(P/'mutants').mkdir(exist_ok=True)
        for i in range(30):
            code,text=run(['vvp',P/'sim.vvp',f'+MUTANT={i}'],f'mutants/{i:02}.log')
            assert code!=0 and f'ASSERT_FAIL {i} ' in text,(i,code,text[-1000:])
            result.append(dict(id=i,killed=True,exit=code))
        (P/'mutants.json').write_text(json.dumps(result,indent=2)+'\n')
        original=(RTL/'cert/m_tsmx_cert.sv').read_text()
        mutations=[('ack_strict','w_since >= PARA_ACK_US','w_since > PARA_ACK_US'),
                   ('expiry_equality',"(w_remain == 32'd0)","1'b0"),
                   ('lease_equality','> 160\'(PARA_LEASE_US)','>= 160\'(PARA_LEASE_US)'),
                   ('margin_equality','w_remain <= PARA_MARGIN_US','w_remain < PARA_MARGIN_US'),
                   ('context_ignored','w_context_valid && (w_cert[511:256] != w_context)',"1'b0"),
                   ('binding_version','w_cert[607:576] != PARA_VERSION',"1'b0"),
                   ('apply_early','w_ack && !w_phase[31]','w_ack'),
                   ('lease_wrong_epoch','i_req_data[2614:2583]','i_req_data[2582:2551]')]
        sr=[];(P/'source_mutants').mkdir(exist_ok=True)
        for name,old,new in mutations:
            assert old in original,old
            folder=P/'source_mutants'/name;folder.mkdir(exist_ok=True)
            source=folder/'m_tsmx_cert.sv';source.write_text(original.replace(old,new))
            code,text=compile_sv(source,folder/'sim.vvp',f'source_mutants/{name}/compile.log');assert code==0
            code,text=run(['vvp',folder/'sim.vvp'],f'source_mutants/{name}/simulation.log',300)
            assert code!=0 and ('ASSERT_FAIL' in text or 'mismatch' in text),(name,text[-1000:])
            sr.append(dict(name=name,killed=True,exit=code))
        (P/'source_mutants.json').write_text(json.dumps(sr,indent=2)+'\n')
        print('Mutants killed: assertions30/30 source8/8')
    verilator=shutil.which('verilator')
    if verilator:
        cmd=[verilator,'--binary','--timing','--assert','-Wno-fatal','--top-module','tb_m_tsmx_cert',
             '--Mdir',P/'obj_dir','-I'+str(P),RTL/'arith/m_tsmx_arith_div.sv',RTL/'arith/m_tsmx_arith.sv',
             RTL/'cert/m_tsmx_cert.sv',P/'tb_m_tsmx_cert.sv']
        code,text=run(cmd,'verilator_compile.log',300);assert code==0,text[-2000:]
        exe=P/'obj_dir/Vtb_m_tsmx_cert';exe=exe.with_suffix('.exe') if exe.with_suffix('.exe').exists() else exe
        code,text=run([exe],'verilator_simulation.log',300);assert code==0,text[-2000:]
    else: print('R-015: Verilator5 unavailable; build/simulation not run.')
if __name__=='__main__':main()
