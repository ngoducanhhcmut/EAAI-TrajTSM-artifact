# R3 rule inspection
TSM-X / TSMX project / version0.1 / 2026-10-29.
Rule source: `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`, v2.

| Skill rule | Result |
|---|---|
| R-001 | Results are confined to current command evidence under `tb/unit/codec`; absent tools/signoff are stated. |
| R-002, R-008, R-009 | New codec files only. Existing reference files remain read-only; changes to this run's sources are authorized by the task. |
| R-003 | Entire supplied VLSIT v2 rule file read before RTL. |
| R-004 | Gap scan run before RTL and replayed in `gaps.log`; six numbering/template gaps resolved in decisions D02. |
| R-005, R-006 | Question gates superseded by explicit user delegation; D01..D17 record supervisor decisions and SPEC-ISSUE extensions. |
| R-007 | Project TSM-X, author TSMX project, version0.1 in each RTL header. |
| R-010 | Design directory contains one module/file; TB, assertions and mutant copies are separate. Filelist contains only original design modules. |
| R-011, R-013 | No intentional SHOULD deviation. Eight PAR-03 heuristic warnings: case selectors6'd2/3/4/5/6/7/8/9 are explicit FIPS SHA round indices; named K constants contain the actual protocol constants. No INFO. |
| R-012, R-019 | Final `rules.log`: RESULT PASS, zero errors; three-or-more alternatives use case/casez. |
| R-014, R-015 | Lint attempted; no tool found, not run. Install choices OSS CAD Suite, MSYS2, WSL or Conda; none installed. |
| R-016 | This matrix and script `coverage.log` identify remaining manual/lint obligations. |
| R-017 | Skill-generated `rtl/filelist_R3.f` includes core then wrapper. |
| R-018 | Final files/evidence confined to codec directories, filelist_R3.f and R3_*.md. |
| R-020 | Skeleton and Moore/Mealy FSM examples read; state/output/next-state split followed. |
| R-021 | Reference examples inspected as style inputs; no changes made to shared skills. Their own lint was not possible without the lint tool. |
| R-022, R-023 | User explicitly requests TB. Independent golden/zlib/hashlib oracle and protocol contract define expected outputs; RTL is not the oracle. |
| R-024, R-025 | Explicit immediate assertions with per-ID hits, fatal failure/zero-hit exit, and targeted DUT-output injection. Exact completed results are in R3_REPORT.md and simulation/mutant logs. |
| R-026 | No unresolved failure attributed by guess to golden/spec. Known context-count and early-fault driver issues analyzed against the contract and recorded in D06/D07. |

Manual coverage from `vlsit_rtl_check.py coverage`:

| Design rule | Inspection |
|---|---|
| NAM-01 | SHA constants and buffer banks indexed from0. |
| NAM-05 | Only active-low signal is the prescribed reset. |
| COM-01 | Ports have one output process; core register state has one next-state and one sequential owner. |
| SEQ-02 | All register next values computed in p_com_ctrl; p_ff_state only resets/registers. |
| SEQ-04 | All control, occupancy, valid and payload state explicitly reset. |
| RST-01 | Single asynchronously asserted active-low reset convention throughout. |
| RST-02 | Synchronized release is an input requirement from the SoC wrapper, spec7; no local CDC. |
| CLK-01, P28 | One core clock, no crossing or synchronizer stages in this leaf. |
| P9 | rotr/crc_byte/sha_iv/sha_k are automatic, deterministic, and have no side effects. |
| P15, P16 | No clock gating/derived clocks; rising-edge registers only. |
| PRT-01 | Common project channel names follow spec5.3; no standard AXI/APB ports are present. |
| SCP-02 | No synthesis result claimed; parameters and tool commands recorded for elaboration/simulation only. |
| CHK-11 | Not tapeout signoff: synthesis/memory inference/STA/CDC/RDC/DFT/formal not run. |

TYP-03/P5: `default_nettype none` and Icarus elaboration provide limited evidence.
COM-05/P23: no register-free feedback was found by inspection; no lint proof.
ARI-01: unsigned vectors, explicit casts and intentional modulo32 sums inspected;
Verilator width analysis is still outstanding. P8: one sequential owner inspected;
no lint claim. Mechanical coverage and all findings appear verbatim in `rules.log`.
