"""Run from any directory: python tsmx_hw/tb/unit/run_R1.py [--quick].

Artifacts, exact commands, exit statuses and mutation failures stay beside each TB.
No third-party Python dependency, no edits to golden/spec/vectors/verify.
"""
from pathlib import Path
import subprocess
import sys
import json

BASE=Path(__file__).resolve().parent
ROOT=BASE.parents[1]
IVERILOG=Path('C:/iverilog/bin/iverilog.exe')
VVP=Path('C:/iverilog/bin/vvp.exe')

SOURCE_MUTANTS={
    'sel':[
        ('candidate_zero_wrong',"LPARA_CAND_0 = 32'd0","LPARA_CAND_0 = 32'd1"),
        ('instant_mask_removed',"i_req_data & 16'(LPARA_ACCEPT_MASK)",'i_req_data'),
        ('mitigation_label_wrong',"LPARA_LABEL_MIT = 32'd2","LPARA_LABEL_MIT = 32'd1"),
        ('response_ignores_stall','if (i_rsp_ready)',"if (1'b1)"),
    ],
    'supervisor':[
        ('recovery_threshold_two',"LPARA_RECOVERY_GOOD = 32'd3","LPARA_RECOVERY_GOOD = 32'd2"),
        ('reuse_routes_l2',"5'b0001?: w_result = {3'(LPARA_MODE_L1)","5'b0001?: w_result = {3'(LPARA_MODE_L2)"),
        ('health_ignored','!i_req_data[0]',"1'b0"),
        ('response_ignores_stall','if (i_rsp_ready)',"if (1'b1)"),
    ],
    'rec':[
        ('lost_wraps','reg_lost != LPARA_LOST_MAX',"1'b1"),
        ('invalid_event_appended','if (w_event_ok) begin',"if (1'b1) begin"),
        ('head_never_advances',"w_head_nxt = $bits(w_head_nxt)'(reg_head + 10'd1);","w_head_nxt = 10'd0;"),
        ('collision_returns_new','w_log_data_nxt = reg_events[w_rd_addr];','w_log_data_nxt = (w_wr_en && w_wr_addr == w_rd_addr) ? i_req_data : reg_events[w_rd_addr];'),
    ],
}

def run(cmd,cwd,log):
    result=subprocess.run([str(x) for x in cmd],cwd=cwd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    log.write_text('COMMAND '+subprocess.list2cmdline([str(x) for x in cmd])+'\n'+result.stdout+f'\nEXIT {result.returncode}\n',encoding='utf-8')
    return result

def main():
    for script in ['convert_R1_vectors.py','build_R1_tb.py']:
        subprocess.run([sys.executable,str(BASE/script)],check=True)
    summary={}
    for blk in ['sel','supervisor','rec']:
        folder=BASE/blk
        cmd=[IVERILOG,'-g2012','-s',f'tb_m_tsmx_{blk}','-I',folder,'-o',folder/'sim.vvp',ROOT/f'rtl/{blk}/m_tsmx_{blk}.sv',folder/f'tb_m_tsmx_{blk}.sv']
        compiled=run(cmd,folder,folder/'compile.log')
        if compiled.returncode: raise RuntimeError(compiled.stdout)
        sim=run([VVP,folder/'sim.vvp'],folder,folder/'simulation.log')
        print(blk,sim.stdout[-1000:])
        if sim.returncode: raise RuntimeError(f'{blk} simulation failed')
        props=json.loads((folder/'assertions.json').read_text())
        kills=[]
        if '--quick' not in sys.argv:
            mutations=folder/'mutants'; mutations.mkdir(exist_ok=True)
            for prop in props:
                num=prop['id']
                r=run([VVP,folder/'sim.vvp',f'+MUTANT={num}'],folder,mutations/f'M{num:02d}.log')
                killed=r.returncode!=0 and f"ASSERT_FAIL {num} {prop['name']}" in r.stdout
                kills.append(killed)
                if not killed: raise RuntimeError(f'{blk} mutant {num} did not fail its target assertion:\n{r.stdout}')
            (folder/'mutant_run.log').write_text('DUT output stuck-X fault injection; no assertion expression is altered.\n'+''.join(f"M{p['id']:02d} {p['name']} net={p['injected_net']} KILLED exit_nonzero target_assertion_fired\n" for p in props),encoding='ascii')
        summary[blk]=dict(assertions=len(props),mutants_killed=sum(kills),mutants_total=len(kills))
        if '--quick' not in sys.argv:
            folder_mut=folder/'source_mutants';folder_mut.mkdir(exist_ok=True)
            original=(ROOT/f'rtl/{blk}/m_tsmx_{blk}.sv').read_text()
            for name,old,new in SOURCE_MUTANTS[blk]:
                assert original.count(old)==1,(blk,name)
                path=folder_mut/f'{name}.sv'
                path.write_text(original.replace(old,new),encoding='ascii')
                mutant_cmd=cmd[:]
                mutant_cmd[-2]=path
                executable=folder_mut/f'{name}.vvp'
                mutant_cmd[mutant_cmd.index('-o')+1]=executable
                r=run(mutant_cmd,folder,folder_mut/f'{name}_compile.log')
                if r.returncode: raise RuntimeError(r.stdout)
                r=run([VVP,executable],folder,folder_mut/f'{name}.log')
                if r.returncode==0 or 'ASSERT_FAIL' not in r.stdout:
                    raise RuntimeError(f'source mutant survived {blk}/{name}: {r.stdout}')
            summary[blk]['source_mutants_killed']=len(SOURCE_MUTANTS[blk])
            (folder_mut/'manifest.json').write_text(json.dumps(SOURCE_MUTANTS[blk],indent=2)+'\n')
        if blk=='rec':
            for depth in [1,3,64,1024]:
                depth_cmd=cmd[:]
                depth_cmd[4:4]=['-P',f'tb_m_tsmx_rec.DEPTH={depth}']
                output=folder/f'depth_{depth}.vvp'
                depth_cmd[depth_cmd.index('-o')+1]=output
                r=run(depth_cmd,folder,folder/f'depth_{depth}_compile.log')
                if r.returncode: raise RuntimeError(r.stdout)
                r=run([VVP,output],folder,folder/f'depth_{depth}.log')
                if r.returncode: raise RuntimeError(r.stdout)
    (BASE/'R1_results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary))

if __name__=='__main__': main()
