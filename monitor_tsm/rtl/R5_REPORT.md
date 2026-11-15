# R5 — m_tsmx_splice
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

RTL: `splice/m_tsmx_splice.sv`; req816={Ego256,Plan560}, rsp1=accept.
One outstanding request; immutable snapshot;16 directed corner advances through
one private unchanged accepted m_tsmx_arith instance. Full closed-tube test.
Reset aborts both engines; invalid output is zero; response holds under stall.

Icarus PASS: golden128/128, B2 edges18/18, decoded hex128/128,
additional4494/4494, total4768/4768. Every output bit compared against golden.
Extras: random2400,boundary94,directed200,equality1800; seed0x5253504c.
FORMATS min/max/sentinels, overflow attempts, serial wrap/negative/half-wrap,
stop/clamps, tube equality +/-1, ignored metadata and reset-in-flight covered.
24 assertions exercised: failures0, never exercised0. Output-wire mutants24/24
killed with matching assertion ID and nonzero exit; copied-source mutants5/5
killed (dx, tube, delay equality, corner omission, stalled response drop).
Initial128 fixtures alone did not kill dx/corner mutations; equality cases do.
Evidence: `../tb/unit/splice/{simulation.log,results.json,vectors.json}`;
shard, assertion-mutant and source-mutant logs retain commands and exit codes.

MEASURED production latency (SEL convention, accepting edge=cycle1):
guard reject2 cycles; full16-job corner sweep178 cycles, including pose rejects.
MEASURED unstalled II: guard3 cycles; full sweep179 cycles. Programmed stall/idle
regression II3..183 is separate from these continuously offered measurements.
Spec5.5.4/10.3 B2 budget12288 clocks/admission: maximum178 is UNDER budget.
Consumer stalls extend hold/II; no core frequency/STA or full-system WCET claim.

VLSIT v2 rule check PASS:0ERROR/8WARN/0INFO. HIE-02(1): functional leaf;
PAR-03(7): fixed ABI extension widths32/96 and constant position-limit factor10.
Header/decisions justify each warning. Moore skeleton/examples used; example
rule check PASS. R5_RULES.md, R5_EXAMPLES.md and R5_MANUAL.md retain evidence.
R-012/019 clean; R-022..025 simulation verified; R-005/006 designer-delegated.
R-017 generated filelist_R5.f includes both accepted arithmetic files.
R-014 attempted: **lint not run (R-015)**, no Verilator/slang; Icarus elaboration
passed. **Verilator5 compile/simulation unverified**; WSL access denied.
No tool installed. Options: OSS CAD Suite, MSYS2, WSL or Conda Verilator.
Portable --binary --timing --assert command is in the unit README.md.

Resources before synthesis: splice816-bit snapshot,4-bit job index,accept bit,
FSM;64-bit add/compare/mux logic, no variable multiplier/divider in splice itself.
Private unspecialized ARITH has6 divider pipelines: paired96/128/160; op3 activates
the96-bit pair. Reachable op3 has6 variable product occurrences (five96-bit,
one160-bit container), plus constant scales. Full engine retains additional
swept/ramp multiplier cones; mapped counts/sharing/pruning need synthesis.
Section13 helper divider estimate2 versus unspecialized6 disclosed as SPEC-ISSUE.
No accepted source changed; no ARITH-ISSUE wrapper needed. No synthesis, STA,
formal, CDC/RDC, DFT, mapped area or physical signoff performed.

Reproduce: `py -3.13 -B tsmx_hw/tb/unit/splice/gen_vectors.py`, then same folder's
`make_tb.py` and `run.py`; rule/lint commands and Verilator command in README.md.
