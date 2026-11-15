"""Spec15: prove every named top assertion can fail on a sampled output fault."""
import argparse,json,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
(HERE/'mutants').mkdir(exist_ok=True)
rows=[]
ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['iverilog','verilator'],default='iverilog');a=ap.parse_args()
sim=['vvp','-i',str(HERE/'top_2.vvp')] if a.tool=='iverilog' else [str(HERE/'obj_2/Vtb_m_tsmx_top')]
for i in range(20):
    p=subprocess.run(sim+['+LIMIT=2','+FILE=smoke.mem',f'+MUTANT={i}'],cwd=HERE,capture_output=True,text=True,timeout=30)
    (HERE/'mutants'/f'M{i:02}.log').write_text(p.stdout+p.stderr)
    killed=p.returncode!=0 and f'ASSERT_FAIL {i} ' in p.stdout
    rows.append(dict(id=i,killed=killed,exit=p.returncode,kind='sampled DUT-output observation fault'))
(HERE/'mutants.json').write_text(json.dumps(rows,indent=2))
print('Top assertion observation mutants:',sum(r['killed'] for r in rows),'/',len(rows))
if not all(r['killed'] for r in rows):raise SystemExit(1)
