# W6 RTL SEU pilot
INCOMPLETE: the required >=20 classifiable injections have not completed; unrun coverage is UNRESOLVED.
Scope: P=G=2; frozen seed/workload/bit strata in [CAMPAIGN.md](CAMPAIGN.md:1).
Actual attempts: 3; completed classifiable injections: 3; counts: `{"MASKED": 3}`.
Overall SDC-UNSAFE: 0.00% [0.00, 70.76] (exact two-sided CP 95%); DC: UNRESOLVED.
| Unit | Eligible bits | Actual n | Unsafe rate [CP95%, %] | DC |
|---|---:|---:|---|---|
| arith | 19012 | 1 | 0.00% [0.00, 97.50] | UNRESOLVED |
| cert | 2914 | 0 | UNRESOLVED | UNRESOLVED |
| codec | 2441 | 0 | UNRESOLVED | UNRESOLVED |
| engine | 72952 | 1 | 0.00% [0.00, 97.50] | UNRESOLVED |
| geom | 40508 | 1 | 0.00% [0.00, 97.50] | UNRESOLVED |
| geom_su | 13488 | 0 | UNRESOLVED | UNRESOLVED |
| health | 34384 | 0 | UNRESOLVED | UNRESOLVED |
| ingress | 1717 | 0 | UNRESOLVED | UNRESOLVED |
| mrmgen | 4300 | 0 | UNRESOLVED | UNRESOLVED |
| selection | 18 | 0 | UNRESOLVED | UNRESOLVED |
| supervisor | 10 | 0 | UNRESOLVED | UNRESOLVED |
| sweep | 19008 | 0 | UNRESOLVED | UNRESOLVED |
Measured attempt wall time: median 16.67s, range 16.20-16.98s; per-attempt logs are retained.
Unfaulted baselines: job0=UNRESOLVED/1800.03s, job1=MASKED/19.19s, job2=UNRESOLVED/1800.04s, job3=UNRESOLVED/1800.03s; external limits are not hardware detection (execution_status.json).
Unsafe case inventory and register-local hardening proposals: [unsafe_cases.md](unsafe_cases.md:1) (0 recorded cases; proposals only).
Probe evidence: [deposit_probe.log](deposit_probe.log:2); actual deposit is at [tb_fault.sv](tb_fault.sv:128).
Deadline classification requires the RTL flag; hardware action: `rtl/top/m_tsmx_engine.sv:1124`.
Verilator 5 compile/readback/campaign: UNRESOLVED here; exact Claude commands and nominal six-hour budget are in CAMPAIGN.md.
Physical-mode duplicate containment is UNRESOLVED: direct-mode guard at `rtl/top/m_tsmx_engine.sv:901`; see RUN_NOTES.md.
Partial results are not an estimate for the full registered workload; inactive storage and RAM exclusions also limit generalization.
Missing/unknown artifacts and external timeouts stay UNRESOLVED; no campaign gate or RTL hardening was applied.
