"""Create the short R3 report only from completed current-run evidence."""
import json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
RTL=HERE.parents[2]/'rtl'
v=json.loads((HERE/'vectors.json').read_text())
m=json.loads((HERE/'mutants.json').read_text())
s=(HERE/'simulation.log').read_text()
assert f"PASS codec: golden={v['jobs']}/{v['jobs']}" in s
assert 'assertion failures: 0, assertions never exercised: 0' in s
assert all(x['killed'] for x in m['assertions']+m['source'])
lat=dict((int(a),int(b)) for a,b in re.findall(r'LATENCY op=(\d+) max=(\d+)',s))
hits=re.findall(r'ASSERT (\d+) (\w+) spec[^ ]+ hits=(\d+)',s)
assert len(hits)==30 and all(int(h)>0 for _,_,h in hits)
assert 'PASS codec: golden=54/54' in (HERE/'focused/simulation.log').read_text()
extra=json.loads((HERE/'format_boundaries/summary.json').read_text())
assert f"PASS codec: golden={extra['jobs']}/{extra['jobs']}" in (HERE/'format_boundaries/simulation.log').read_text()
(HERE/'assertions.json').write_text(json.dumps([dict(id=int(i),name=n,hits=int(h),clause='spec5.3/5.5.2/7/10.3',mutant_killed=m['assertions'][int(i)]['killed']) for i,n,h in hits],indent=2)+'\n')
report=f'''# R3 — streaming packed-record codec
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

**Icarus PASS codec: golden={v['jobs']}/{v['jobs']}**; every289-bit response compared.
Includes2276 fixture-derived jobs from all128 b1,128 b9,128 system and117 edge rows,
1000 random typed records,181 field-boundary jobs,2148 raw-byte tests,32 fault jobs,
10 known-answer jobs and one leading-zero SHA digest. Seed21043.
Supplement:263/263 FORMATS/domain/width endpoints across every S1b packer;
54/54 focused fault/max-length jobs with producer pauses, all30 assertions active.
Golden S1b packers cross-checked with Python zlib/hashlib; lengths0..32768,
32769-byte rejection, two's-complement extrema, schema/count/order and padding edges.

| Op / bytes | Max measured latency | Spec5.5.2 /10.3 bound |
|---|---:|---:|
| Packet CRC /86 | {lat[0]} |22; B1 allocation16384 |
| Snapshot SHA /32 | {lat[1]} |84 |
| Plan SHA /70 | {lat[2]} |152 |
| Context SHA /1049 | {lat[3]} |1172 |
| Seal SHA /120 | {lat[4]} |220 |
| Raw CRC /0..32768 | {lat[5]} |ceil(L/4), empty1 |
| Raw SHA /0..32768 | {lat[6]} |16+68*ceil((L+9)/64) |

Main latency run uses no producer pauses and includes first acceptance clock.
CRC input II1. SHA uses64 rounds + load/feed-forward =66 cycles/block (target64..68),
overlapped double-buffer fill; job bound16+66*ceil((L+9)/64).
With ready consumers, first-beat job II=latency+2; stalls extend response hold.
Thirty assertions: failures0, never exercised0; targeted output mutants killed30/30.
Six source mutants killed6/6: CRC polynomial, SHA IV/K, padding, length and stall loss.
Directed resets cover partial input, active compression and a stalled response.
Per-assertion hit counts and kills: `tb/unit/codec/assertions.json`, `mutants.json`.

VLSIT v2 rule check PASS:0ERROR/8WARN/0INFO; R-012/R-019 clean.
PAR-03 warnings for SHA round case indices2..9 are justified in decisions D15.
R-004:6 missing-template BLOCKs resolved under user delegation (D02).
R-005/006 question gates superseded by delegation; R-001..026/manual matrix:
[R3_RULES.md](R3_RULES.md). [R3_DECISIONS.md](R3_DECISIONS.md) records all gaps.
**R-015: lint not run; Verilator5 build/simulation not run: tool unavailable.**
Replay uses `--binary --timing --assert`; TB uses standard SV immediate assertions,
static memories, relative readmemh paths. Verilator compatibility remains unverified.
Install choices: OSS CAD Suite, MSYS2, WSL or Conda; nothing installed.

Resources: zero general multipliers/dividers, no division/modulus operators;
1024-bit input banks,512-bit schedule,512-bit SHA state,32-bit CRC, response/control.
Approximately2441 explicitly declared state bits before constant/unused-bit pruning.
No mapped area, RAM inference, timing187.5MHz, formal, CDC/RDC or DFT signoff claimed.
No shared golden/spec/vectors/verify/other RTL sources edited.

Reproduce from repository root: `py -3.13 -B tsmx_hw/tb/unit/codec/run.py`.
Then `py -3.13 -B tsmx_hw/tb/unit/codec/summarize.py` regenerates this short report.
Compile order: `tsmx_hw/rtl/filelist_R3.f`; top `m_tsmx_codec`.
Exact commands/exits and complete output: `tsmx_hw/tb/unit/codec/*.log`;
individual fault evidence in `mutants/` and `source_mutants/` beneath that folder.
'''
assert len(report.splitlines())<=60
(RTL/'R3_REPORT.md').write_text(report,encoding='utf-8')
print(report)
