"""Fast regression of every fault after monitor correction, separate from full suite."""
import subprocess
from pathlib import Path
H=Path(__file__).resolve().parent
R=H.parents[2]/'rtl/codec'
out=H/'focused';out.mkdir(exist_ok=True)
jobs=[int(s,16) for s in (H/'jobs.mem').read_text().splitlines()]
beats=(H/'beats.mem').read_text().splitlines()
selected=[];selected_beats=[];cursor=0;seen={}
for job in jobs:
    nb=job>>329;op=(job>>289)&255;n=(job>>297)&0xffffffff
    fault=(job>>288)&1
    choose=fault or seen.get(op,0)<2 or n==32768
    seen[op]=seen.get(op,0)+1
    if choose:selected.append(job);selected_beats.extend(beats[cursor:cursor+nb])
    cursor+=nb
(out/'jobs.mem').write_text(''.join(f'{x:091x}\n' for x in selected))
(out/'beats.mem').write_text('\n'.join(selected_beats)+'\n')
(out/'vectors_meta.svh').write_text(f'localparam integer N={len(selected)}, B={len(selected_beats)};\n')
(out/'tb_m_tsmx_codec.sv').write_text((H/'tb_m_tsmx_codec.sv').read_text())
with (out/'compile.log').open('w') as f:
    p=subprocess.run(['iverilog','-g2012','-s','tb_m_tsmx_codec','-o','simulation.vvp',str(R/'m_tsmx_codec_core.sv'),str(R/'m_tsmx_codec.sv'),'tb_m_tsmx_codec.sv'],cwd=out,stdout=f,stderr=f)
assert p.returncode==0
with (out/'simulation.log').open('w') as f:p=subprocess.run(['vvp','simulation.vvp'],cwd=out,stdout=f,stderr=f,timeout=120)
print((out/'simulation.log').read_text()[-2500:])
assert p.returncode==0
