# R6 manual rule inspection
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

| Rule | Inspection/result |
|---|---|
| R-001 | Claims tied to commands/logs; missing lint/Verilator/synthesis explicit. |
| R-002/009/018 | Only new R6-owned deliverable paths; accepted RTL/golden/spec unchanged. |
| R-003 | User-named VLSIT_RTL_Design_Rule.md v2 read. |
| R-004 | Gap scan executed, six template-heading BLOCKs recorded in decisions2. |
| R-005/006 | Designer explicitly delegates gap resolution and disallows questions. |
| R-007 | Header project/author/version match user instruction. |
| R-008 | New RTL generation; no existing baseline modified. |
| R-010/022 | Verification lives only in tb/unit/mrmgen; filelist excludes TB. |
| R-011/013 | HIE-02 functional leaf and fixed ABI/SI constant warnings explained in header/decisions13. |
| R-012/019 | Rule checker PASS; case/casez alternatives all have defined defaults. |
| R-014/015 | Lint command attempted; no tool, no installation; install options in README. |
| R-016 | This rule matrix and R6_RULES.md record manual/mechanical/tool coverage. |
| R-017 | Skill-generated filelist augmented with accepted arithmetic dependencies. |
| R-020 | Moore example/skeleton read; output decoder, next-state process, FF process. |
| R-021 | No skill examples changed or delivered; templates are read-only inputs. |
| R-023 | Stimulus/oracle from spec/golden; fixture converter checks immutable expected outputs. |
| R-024/025 | 32 checks; hit counts and mutant outcomes in unit logs/results. |
| R-026 | Failure cause diagnosed against golden; reason-enum transcription fixed only in RTL. |
| NAM-01 | Zero-based row/cell index and static grid-decoder loop. |
| NAM-05 | No active-low non-reset ports. |
| COM-01/P8 | Each output/next-state signal has one combinational owner, each reg one FF owner. |
| SEQ-02 | Next-state/data computed combinationally, FF only captures. |
| SEQ-04/RST-01 | All validity/control/payload reset asynchronously active-low. |
| RST-02/RST-04 | Synchronizer and DFT reset control owned by wrapper per spec7. |
| CLK-01/P28 | Single core domain; no CDC in this leaf. |
| P9 | Automatic functions are deterministic with no side effects. |
| P15 | No clock gating/derived clocks. |
| P16 | State uses core rising edge only. |
| PRT-01 | Custom ready/valid channels per5.3, no AMBA interface. |
| TYP-03/P5 | default_nettype none; Icarus elaboration finds no undeclared nets. |
| ARI-01/02 | Explicit160 sign extension, bounded unsigned two's-complement math; field slicing intentional. |
| COM-05/P23 | Inspected acyclic comb logic; dependency graph closes only through registers. |
| COM-07 | All combinational outputs default; no latch found by inspection; lint unverified. |
| SCP-02/CHK-11 | No synthesis, timing, area, formal, CDC/RDC, DFT or tapeout signoff claim. |

Actual arithmetic child is accepted R2 and is not revised here. Compiler warnings
about Icarus constant-select sensitivity are simulator limitations, not latches.
Script warning locations and complete warning text are retained in R6_RULES.md.
