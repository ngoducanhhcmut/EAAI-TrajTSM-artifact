# R6 report - continuous MRM generator
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

RTL: `mrmgen/m_tsmx_mrmgen.sv`, one context, PARA_MAX_CELLS=128.
Top instantiates eight independent copies for G=8; private accepted ARITH unchanged.
Filelist `filelist_R6.f` includes both accepted arithmetic files before B4.

Icarus12 PASS: **2575/2575 jobs, 43617/43617 rows**, all output bits compared.
Sources:128 full golden fixtures +128 independently verified legacy hex cases,
80 directed +39 boundary +2200 seeded random. Edge file contains0 B4 rows.
Reasons exercised: ok1020,range217,horizon1338. phase_alignment is unreachable
following golden's grid admission. Physical min/max/sentinels and overflow-domain
positions reject before arithmetic; legal B4 arithmetic cannot overflow s64.
Additional parameter smoke PASS: PARA_MAX_CELLS=1 accepts limit1/rejects limit2.

32 named assertions: all exercised; failures0, never exercised0.
32/32 sampled DUT-output mutants killed by their corresponding named assertion.
4/4 functional source mutants killed: disabled jerk, instant start, row stall, range.
One deleted redundant instant assignment was equivalent; replaced with real mutant.
Reset is tested during private arithmetic and row stalls; aborted work is drained.
Evidence: `../tb/unit/mrmgen/{results.json,simulation.log,mutants.json,measure.json}`.
Per-job cycles and every assertion hit count are retained in shard logs.

MEASURED production latency2..2936 cycles over all2575 jobs, excluding row stalls.
MEASURED no-stall80 directed cases: latency718..2918, job II719..2919 cycles.
Normal regression II6..3066 includes deliberately inserted consumer stalls.
MEASURED maximum no-stall row gap70 cycles vs spec10.3 C4=1280: **within budget**.
Observed job max2936 vs candidate budget163840: **within budget**.
These are RTL-cycle observations, not a synthesis timing or whole-system WCET proof.

Row ready/valid payload401 = cid8,epoch32,index8,Row352,last1.
Row352={zero64,phase32,xlo64,xhi64,vlo32,vhi32,a32,jerk32}, following golden packing.
Index increases as B3 consumes adjacent endpoints; terminal metadata commits rows.
last1 denotes appended successful endpoint; reject/count delimits partial streams.

Rule check PASS:0ERROR/9WARN/0INFO; HIE-02 functional leaf and8 fixed-ABI/SI
PAR-03 warnings justified in module header/decisions13. R6_RULES/R6_MANUAL retained.
R-012/019 script-clean; R-022..025 verified; R-005/006 delegated; manual IDs inspected.
R-014 attempted: **lint not run (R-015)**, no Verilator/slang; WSL access denied.
**Verilator5 compile/simulation NOT VERIFIED**; portable command in unit README.
Install options: OSS CAD Suite, MSYS2, WSL, Conda. Nothing installed.

Resources: one private ARITH; six structural dividers (paired96/128/160), exceeding
spec13's two160/context estimate. No pruning/mapped-area claim. Parent has2
constant multiplier expressions; shared ARITH has76 source multiplication operators
(before function expansion/constant folding/sharing). Physical multiplier count
unmeasured. Ramp xn160/xd136/vn112/vd88; other products96/128; profile product64.
Spec13's16-multiplier estimate and187.5MHz require synthesis/STA confirmation.
No synthesis, formal, CDC/RDC, DFT or physical signoff performed.

Reproduce: unit gen_vectors.py, run.py, run.py --mutants-only, measure.py;
parameter smoke command and tool commands are in unit README. Decisions in R6_DECISIONS.
PASS mrmgen: golden=2575/2575 rows=43617 assertions=32 mutants=32/32 source=4/4
