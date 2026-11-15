"""Run Icarus baseline, every assertion mutant and representative RTL source mutants."""
from pathlib import Path
import subprocess,sys,json,re,time,shutil
H=Path(__file__).resolve().parent
ROOT=H.parents[3]
RTL=ROOT/'tsmx_hw/rtl'
def run(cmd,log,timeout=600):
    t=time.monotonic()
    p=subprocess.run(list(map(str,cmd)),cwd=H,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    (H/log).write_text('COMMAND '+subprocess.list2cmdline(list(map(str,cmd)))+'\n'+p.stdout+f'\nEXIT {p.returncode}\nSECONDS {time.monotonic()-t:.3f}\n')
    return p.returncode,p.stdout
def compile(out,source=None):
    cmd=['iverilog','-g2012','-s','tb_m_tsmx_ingress','-I',H,'-o',H/out,
         RTL/'arith/m_tsmx_arith_div.sv',RTL/'arith/m_tsmx_arith.sv',
         source or RTL/'ingress/m_tsmx_ingress.sv',H/'tb_m_tsmx_ingress.sv']
    code,txt=run(cmd,out+'.compile.log');assert code==0,txt[-2000:]
def main():
    compile('sim.vvp')
    code,txt=run(['vvp',H/'sim.vvp'],'simulation.log');print(txt[-2400:],flush=True)
    assert code==0 and 'PASS ingress:' in txt
    hits={int(k):int(v) for k,v in re.findall(r'ASSERT_HITS (\d+) hits=(\d+)',txt)}
    assert len(hits)==27 and all(hits.values())
    baseline=dict(hits=hits,measure=re.findall(r'MEASURE (.*)',txt),pass_line=re.findall(r'PASS ingress:.*',txt)[0])
    (H/'results.json').write_text(json.dumps(baseline,indent=2)+'\n')
    if '--baseline-only' in sys.argv:return
    (H/'mutants').mkdir(exist_ok=True);(H/'source_mutants').mkdir(exist_ok=True)
    killed=[]
    for n in range(27):
        code,txt=run(['vvp',H/'sim.vvp',f'+MUTANT={n}'],f'mutants/M{n:02}.log')
        assert code!=0 and f'ASSERT_FAIL {n} ' in txt,(n,txt[-2000:])
        killed.append(n);print('assertion mutant killed',n,flush=True)
    originals=(RTL/'ingress/m_tsmx_ingress.sv').read_text()
    defects=[
      ('crc_bypass','w_reject[12]=(w_crc!=w_local_crc);',"w_reject[12]=1'b0;"),
      ('sequence_equal',"w_seq_age[31] || w_seq_age=='0","w_seq_age[31]"),
      ('age_boundary','w_ego_age>LPARA_AGE','w_ego_age>=LPARA_AGE'),
      ('freeze_boundary','w_distance>{33\'d0,LPARA_MOVE}','w_distance>={33\'d0,LPARA_MOVE}'),
      ('freeze_refresh','w_same ? w_freeze_since : w_now','w_now'),
      ('last_sample','1\'b1,w_snap_t,1\'b1,w_new_sig','1\'b1,w_now,1\'b1,w_new_sig'),
      ('stall','ENUM_ST_RESP: if (i_rsp_ready)',"ENUM_ST_RESP: if (1'b1)"),
      ('clock_priority','w_time_valid && w_arith_rsp[511]',"1'b0"),
    ]
    functional=[]
    for name,old,new in defects:
        assert originals.count(old)==1,(name,originals.count(old))
        p=H/'source_mutants'/f'{name}.sv';p.write_text(originals.replace(old,new))
        out=f'source_mutants/{name}.vvp';compile(out,p)
        code,txt=run(['vvp',H/out],f'source_mutants/{name}.log')
        assert code!=0 and ('ASSERT_FAIL' in txt or 'bounded progress' in txt),(name,txt[-1500:])
        functional.append(name);print('source mutant killed',name,flush=True)
    (H/'mutants.json').write_text(json.dumps(dict(assertions=killed,source=functional),indent=2)+'\n')
    print('MUTANTS PASS',len(killed),'/',27,'source',len(functional),'/',len(defects))
if __name__=='__main__':main()
