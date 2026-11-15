# R7 — m_tsmx_geom
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

Delivered: `geom/m_tsmx_geom.sv`, `m_tsmx_geom_adv.sv`, `m_tsmx_geom_swept.sv`;
generated synthesis filelist `filelist_R7.f`; TB/generator/scripts in `tb/unit/geom`.
One lane, defaults32 actors/128 cells; top suppliesP8. Private accepted divider unchanged.

Icarus: **2615/2615 full81-bit GeomResult vectors PASS** in29 disjoint shards:
128 golden +34 edges +128 legacy +49 directed +74 boundary +2200 random +2 budget.
Every golden/edge fixture is independently checked against the imported golden model.
All11 B3 result reasons occur. Seed7007; hashes/counts in `vectors.json`.
Separate stalled-edge replay: **34/34 PASS**; all response holds compared bit-exactly.
Reset during active divider work, followed by3 fresh jobs: **PASS** (`reset_mid.log`).
Assertions: **26/26 exercised**, zero failures/zero inactive in the aggregate run.
Mutants: **26/26 assertion-output mutants killed**, each by its named assertion;
**3/3 source mutants killed** (stationary point, inflation, endpoint numeric guard).
Evidence: `simulation.log`, `results.json`, `mutants.json`, `source_mutants.json`, logs.

**MEASURED cycles, not STA:** job latency4..83653 clocks; each job printed in shard logs.
Actor-cell II20..38 clocks, including both event pieces; **38 <= S1b II48: within budget**.
128-cell×32-actor burst job:83653 <=128×32×48=196608 clocks, including row fill/drain.
Row-start dispatch period <=667 clocks in the128-row load case.
All32 actors splitting one row:1230 clocks request-to-response, below1536 row/drain budget.
These measurements exclude arbitrary producer/consumer stalls; public job II includes
complete trajectory service and response hold. They do not prove top10ms or187.5MHz.

Resources, source-level before synthesis: **6 II1 dividers =4×s96 +2×s128** per lane,
versus section13's one of each: **divider resource target exceeded**.
Variable product sites after static loop expansion:32×64-bit preflight,4×96-bit
inflate,6×96-bit advance,23×128-bit swept (65 total, excluding constant coefficients
and index arithmetic). Sharing/pruning and mapped multiplier/DSP counts are unmeasured;
this exceeds the section13 eight-multiplier estimate before synthesis optimizations.
Rows129×352 bits plus32 object/interval contexts; greater storage than35-slot estimate.

Rule checker: **RESULT: PASS, 0 ERROR**, three owned RTL files (`R7_RULES.md`).
27 WARN:3 HIE-02 functional-leaf warnings;24 PAR-03 fixed SI/ABI/width constants.
Each location is listed in the rule report; rationale is in headers and DECISIONS16.
R-001/003/004/007/009/010/012/013/016..020/022..025 inspected or script-verified.
R-005/006/008 approval gates superseded by explicit designer delegation; R-021 no edits
to examples permitted/needed; R-026 converter failure analysis is in DECISIONS17.
R-014/015: **lint not run — no Verilator/slang available; WSL access denied**.
Actual Verilator5 `--binary --timing --assert` compilation is **NOT VERIFIED**.
Portable command and installation routes (OSS CAD Suite/MSYS2/WSL/conda) are in TB README.
No tool installed. Icarus elaboration/simulation passed; its constant-select notices
mean expanded sensitivity, not a lint or synthesis signoff result.
Manual coverage: NAM-01/05, COM-01, SEQ-02/04, RST-01, P9/P15/P16, PRT-01 inspected;
RST-02/04, CLK-01/P28 wrapper-owned/no lane CDC; SCP-02/CHK-11 signoff not performed.
Sizing/net/driver/loop checks lack independent lint confirmation; see DECISIONS16.
Synthesis, inferred RAM mapping, STA, formal equivalence, CDC/RDC and DFT were not run.

Reproduce from repo root: `py -3.13 -B tsmx_hw/tb/unit/geom/gen_vectors.py`, then
`check.py`, `run.py`, `source_mutants.py` in that same directory (README gives full paths).
SPEC-ISSUE/typed-ABI decisions and exact precedence are recorded in `R7_DECISIONS.md`.
