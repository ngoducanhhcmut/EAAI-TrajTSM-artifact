# R11 — B13 health monitor and BIST
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

RTL: health/m_tsmx_health.sv, m_tsmx_health_bist.sv, m_tsmx_health_lane.sv.
Core preserves spec5.5.11 aggregate channels; lane integrates a dedicated accepted
B4/B3 pair. PARA_HEALTH_WORDS1..1024, default1024; wire ABI remains33824 bits.
Generated filelist_R11.f includes accepted arith, mrmgen and geom dependencies.
Only owned health/R11 directories/files were written; accepted sources unchanged.

Icarus: **2586/2586 vectors PASS**, all healthy output bits compared,41 disjoint shards.
128 semantic golden +128 legacy +68 directed +60 boundary +2200 seeded random
+2 full BIST budget cases; there are0 B13 rows in edges.ports.jsonl.
Golden imported unchanged; legacy metadata conversion validates full diagnostics.
Fixture hashes, seed1113 and counts: ../tb/unit/health/vectors.json.
Seven injected BIST-resource failures reject: accept,stop,terminal row,count,
stop_valid,clear geometry and blocked geometry. Request/response stalls pass.
Reset during dedicated arithmetic aborts the job; fresh BIST passes after reset.
Capacity1 boundary replay:60/60 PASS; capacities0 and1025 fail elaboration.

Assertions:26 named immediate checks, all exercised; failures0/inactive0.
26/26 sampled-observation mutants killed by the corresponding named assertion.
4/4 functional source mutants killed: parity,lane equality,onehot,BIST stop.
Sensitivity tests include scoreboard relations; no physical coverage claim.
Evidence: simulation.log,results.json,mutants.json,source_mutants.json,final.json
under ../tb/unit/health; shard logs retain every job and assertion hit count.

**MEASURED** production latency2..3088 clocks; public II3..3090 including stalls.
Real no-stall BIST:2064 clocks with0 words;3088 with1024 protected words.
No-stall BIST job interval2065..3089 clocks; job latency/II printed in measure.log.
3088 < spec10.3 B13 budget65536: **within budget** for the dedicated integration.
Arbitrary external stalls are excluded from this budget; no whole-system WCET claim.
One dedicated pair is reused sequentially, versus spec13's two-pair estimate;
this explicit scheduling decision meets the measured budget (DECISIONS9).

Resource structure: one accepted B4 ARITH plus one accepted B3 geometry lane.
12 private divider pipelines:6xs96,4xs128,2xs160; no shared global arithmetic.
Owned monitor has XOR/comparison/constant-index logic, no variable multiplier.
Accepted reports enumerate76 ARITH multiplication operators plus2 B4 constant
sites, and65 statically expanded B3 product sites. Sharing/function expansion,
mapped multiplier/DSP count and area are unmeasured; products reach s160.
Owned request/trajectory payload registers total170148 bits, excluding control;
accepted dependency storage is additional. No RAM mapping or PPA signoff claim.

VLSIT v2 checker: **RESULT: PASS,0ERROR/8WARN/0INFO**, three owned RTL files.
2 HIE-02 warnings: functional adapter and inactive illegal-parameter guard;
6 PAR-03 warnings: fixed golden/SI constants; headers and DECISIONS12 justify each.
Filelist's undefined diagnostic-cell warning is intentional (DECISIONS16).
R-012/019 mechanical pass; R-017 generated filelist; R-022..025 simulation verified.
R-005/006 approval gates superseded by designer delegation; manual IDs in R11_MANUAL.
Icarus full-lane elaboration PASS,0errors/0warnings (elaborate_final.log).
**R-014/015: lint not run — no Verilator/slang found; WSL access denied.**
**Verilator5 --binary --timing --assert compile/simulation NOT VERIFIED.**
No installation performed. Routes: OSS CAD Suite,MSYS2,WSL,Conda; portable
run_verilator.py is supplied. Synthesis/STA/formal/CDC/RDC/DFT signoff not run.

Reproduce: unit gen_vectors.py,run.py,source_mutants.py,measure.py,finalize.py.
Exact commands and tool limitations are in ../tb/unit/health/README.md.
Decisions and SPEC-ISSUE are in R11_DECISIONS.md; rule/manual matrices accompany it.
PASS health: golden=2586/2586 assertions=26 mutants=26/26 source=4/4
