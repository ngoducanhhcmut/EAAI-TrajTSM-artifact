"""Render <=30 lines from actual pilot records; never invent missing runs."""
import collections,json,statistics
from classify import summary
from gen_faults import HERE,dump

def main():
    path=HERE/'results.jsonl'
    rows=[json.loads(s) for s in path.read_text().splitlines() if s.strip()] if path.exists() else []
    inventory=json.loads((HERE/'inventory.json').read_text())
    units=inventory['population']
    widths={r['path']:r['width'] for r in inventory['registers']}
    total=summary(rows)
    def fmt(s):
        if not s['n']:return 'UNRESOLVED'
        return f"{100*s['unsafe_rate']:.2f}% [{100*s['cp95'][0]:.2f}, {100*s['cp95'][1]:.2f}]"
    def dc(s):return 'UNRESOLVED' if s['dc'] is None else f"{100*s['dc']:.2f}%"
    lines=['# W6 RTL SEU pilot',
           'Scope: P=G=2; frozen seed/workload/bit strata in [CAMPAIGN.md](CAMPAIGN.md:1).',
           f"Actual attempts: {len(rows)}; completed classifiable injections: {total['n']}; counts: `{json.dumps(total['counts'],sort_keys=True)}`.",
           f"Overall SDC-UNSAFE: {fmt(total)} (exact two-sided CP 95%); DC: {dc(total)}.",
           '| Unit | Eligible bits | Actual n | Unsafe rate [CP95%, %] | DC |',
           '|---|---:|---:|---|---|']
    if total['n']<20:
        lines.insert(1,'INCOMPLETE: the required >=20 classifiable injections have not completed; unrun coverage is UNRESOLVED.')
    for unit,pop in units.items():
        s=summary([r for r in rows if r['unit']==unit])
        lines.append(f"| {unit} | {pop} | {s['n']} | {fmt(s)} | {dc(s)} |")
    if rows:
        wall=[r['wall_seconds'] for r in rows]
        lines.append(f"Measured attempt wall time: median {statistics.median(wall):.2f}s, range {min(wall):.2f}-{max(wall):.2f}s; per-attempt logs are retained.")
    baseline_status={}
    for i in range(4):
        p=HERE/f'iverilog_baseline_{i}.json'
        baseline_status[i]=json.loads(p.read_text()) if p.exists() else dict(**{'class':'UNRESOLVED'},reason='no completed record')
    dump('execution_status.json',dict(baselines=baseline_status,pilot_completed=total['n'],pilot_required=20))
    labels=[]
    for i,b in baseline_status.items():
        timing=f"/{b['wall_seconds']:.2f}s" if 'wall_seconds' in b else ''
        labels.append(f"job{i}={b['class']}{timing}")
    lines.append('Unfaulted baselines: '+', '.join(labels)+'; external limits are not hardware detection (execution_status.json).')
    unsafe=[r for r in rows if r['class']=='SDC-UNSAFE']
    dump('unsafe_cases.json',unsafe)
    cases=['# Unsafe cases (all registered observations)']
    for r in sorted(unsafe,key=lambda r:r['id']):
        proposal='dual-rail encoding with fail-closed comparison' if 'fsm' in r['path'] or widths[r['path']]<=8 else 'a residue/parity code checked before the register authorizes a decision'
        cases.append(f"- ID {r['id']}: {r['unit']}, `{r['path']}[{r['bit']}]`, cycle {r['cycle']}, job {r['job']} ({r['source']}:{r['line']}); propose {proposal} on this register only. No RTL edit.")
    if not unsafe:cases.append('No SDC-UNSAFE case in the recorded pilot; no hardening efficacy is claimed.')
    (HERE/'unsafe_cases.md').write_text('\n'.join(cases)+'\n')
    lines += [f"Unsafe case inventory and register-local hardening proposals: [unsafe_cases.md](unsafe_cases.md:1) ({len(unsafe)} recorded cases; proposals only).",
              'Probe evidence: [deposit_probe.log](deposit_probe.log:2); actual deposit is at [tb_fault.sv](tb_fault.sv:128).',
              'Deadline classification requires the RTL flag; hardware action: `rtl/top/m_tsmx_engine.sv:1124`.',
              'Verilator 5 compile/readback/campaign: UNRESOLVED here; exact Claude commands and nominal six-hour budget are in CAMPAIGN.md.',
              'Physical-mode duplicate containment is UNRESOLVED: direct-mode guard at `rtl/top/m_tsmx_engine.sv:901`; see RUN_NOTES.md.',
              ('Partial results are not an estimate for the full registered workload; inactive storage and RAM exclusions also limit generalization.' if total['n']<24 else 'Intervals describe the registered equal-unit mixture, not all silicon bits; inactive storage and RAM exclusions limit generalization.'),
              'Missing/unknown artifacts and external timeouts stay UNRESOLVED; no campaign gate or RTL hardening was applied.']
    assert len(lines)<=30
    (HERE/'REPORT.md').write_text('\n'.join(lines)+'\n')
    dump('results.summary.json',dict(overall=total,units={u:summary([r for r in rows if r['unit']==u]) for u in units},unsafe=unsafe))
    print('\n'.join(lines))

if __name__=='__main__':main()
