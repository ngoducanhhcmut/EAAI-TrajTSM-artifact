# R10 — m_tsmx_arb command authority mux
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

Top: `arb/m_tsmx_arb.sv`; filelist: `filelist_R10.f` (script-generated).
Req3863; rsp1997; separate i_override/o_brake; locked profiles16/mitigation15.
L0/RECOVERY=pending; L1=backup; L2=finite-jerk selector; L3=id15; HOLD=parking.
Original nominal/backup Plan/Certificate/apply/expiry/hash bits are preserved.
Override bypasses backpressure and is retained until a new safe command; a held
frame never changes on override. Top/B9 owns time, admission, reuse and ACK checks.

**Icarus12 PASS arb: golden=128/128 edges=14/14 extra=3985/3985 all=4127/4127.**
Every response bit and brake checked; all128 system fixtures and14 system edges
replayed through unmodified golden, with complete state/telemetry agreement.
These are command projections of golden states, not an independent golden arb.
Extras:2600 random,1088 exhaustive/boundary,256 hash patterns,40 B9 timer cases,
one explicit expiry-during-stalled-egress case. Seed101024; six original invalid
numeric scalars rejected before packing and excluded from RTL-vector totals.
Directed tests include all modes, absent records, all byte selector/label codes,
u32 wrap, FORMATS bounds, queued producer, stalled override and reset abort.

**Assertions36/36 exercised; failures0, never exercised0.**
Assertion output-wire mutants killed36/36, each by its own targeted assertion;
independently compiled RTL source mutants killed9/9. Every mutant exits nonzero.
Evidence: `../tb/unit/arb/{simulation.log,assertions.json,results.json,vectors.json,
mutants/M*.log,source_mutants/*}`; exact commands and exit codes retained.

**MEASURED latency1..1 cycles/job; unstalled II2; exercised stalled II2..7.**
Acceptance edge is cycle1, matching SEL.4130 accepted jobs include two queued
directed completions and one reset-aborted job beyond the4127 completed vectors.
Independent override asserted without a clock in the directed test; sticky state
updates on the next edge. One-cycle production is below spec5.5.13 limit2 and
spec10.3 shared CSR/arbiter/stall allocation16384: **not over budget** for this leaf.
At187.5MHz, one cycle=5.333ns; arbitrary stalls extend II; full-system timing unproved.

Resources by RTL inspection:0 multipliers,0 dividers, one32-bit constant adder,
1997 payload bits+2 FSM bits+1 brake bit before synthesis pruning. There are no
arithmetic lanes or numerical primitives; accepted arithmetic need not be instantiated.
Mux widths:Plan560,Certificate1217,epoch32,Ego256. No mapped area/PPA claim.

**SPEC-ISSUE:** listed Command fields/golden packer total1897, versus W_CMD1997.
Preserve port1997, right-align exact golden1897 bits, zero upper100. Delegated
source codes/local fallback Plan envelope and caller obligations: R10_DECISIONS4..10.
Top/executor must adopt this documented layout; no spec/golden/dependency edited.

VLSIT v2 rule check PASS:0ERROR/0WARN/0INFO. R-001..026/manual coverage:
R10_MANUAL.md; tool evidence: R10_RULES/COVERAGE/GAPS/LINT.md.
Six gap-scan formatting BLOCKs resolved under delegation; header HIE-02 justified.
**R-015: lint not run; Verilator5 build/simulation not run (tool unavailable).**
Required lint script attempted, exit3. Install options: OSS CAD Suite, MSYS2,
WSL or Conda; nothing installed. `--binary --timing --assert` replay is supplied,
but Verilator compatibility remains unverified. Icarus sensitivity notices are benign.
No synthesis/STA/formal/CDC/RDC/DFT or full-system WCET signoff performed.

Reproduce from root: `py -3.13 -B tsmx_hw/tb/unit/arb/gen_vectors.py`, then
that folder's `build_tb.py`, `run.py --mutants`, `check.py`; see unit README.md.
