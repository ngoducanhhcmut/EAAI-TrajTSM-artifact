# R2 manual rule inspection
Project TSM-X; author TSMX project; version 0.1; 2026-10-29.

| Rule(s) | Inspection / outcome |
|---|---|
| R-001 | Report distinguishes executed simulation/checks from unavailable lint/Verilator and physical signoff. |
| R-002,008,009 | New arithmetic deliverables only; accepted SEL, other blocks and reference sources untouched. No modification gate applies to the new block. |
| R-003,007 | Read named VLSIT v2 rules; supplied TSM-X/TSMX project/0.1 headers. |
| R-004..006 | Gap scan recorded six missing template headings; resolved under explicit designer delegation, decisions1/2. |
| R-010,018,022 | RTL and verification source sets separate; filelist contains only two synthesizable modules. Logs/scripts confined to owned unit directory. |
| R-011,013,020 | Moore example, skeleton and SEL read. Grouped combinational process is documented for Icarus; HIE-02/PAR-03 findings explained in decisions12 and headers. |
| R-012,019 | Mechanical script prints PASS; all three-or-more-way selections use case. |
| R-014,015 | Lint attempted, exit3; R-015 no lint tool. Nothing installed. |
| R-016,017 | Script-generated filelist, mechanical report and this manual matrix provided. |
| R-021 | Reference examples were read, never copied with a known prohibited construct and not modified; user ownership excludes skill/reference edits. |
| R-023 | Model-derived arithmetic expectations; protocol from5.3/7; encoding from9.2. No expected mathematical result derives from RTL. |
| R-024,025 | 26 immediate assertions; hit counts checked across exhaustive disjoint simulation ranges. Per-assertion output-wire and six functional RTL mutants must fail nonzero. |
| R-026 | Identified failures resolved under delegation: shared-function Icarus sensitivity; TB watchdog must stop counting at first response, including undefined opcodes. Numerical oracle was not weakened. |
| NAM-01,05 | Replicated instances0..5; pipeline/gen arrays begin0. Only reset inputs are active-low. |
| COM-01,06/P9 | One combinational driver per next-state/output; deterministic automatic functions, no external writes or static state. |
| SEQ-02,04 | Next state entirely combinational; all state, payload and pipeline-valid registers reset. |
| RST-01,02 | Core rising edge, asynchronous active-low assertion; synchronizer/DFT reset override owned by wrapper (spec7). No local reset generation. |
| CLK-01/P28 | Single domain only; no crossing or synchronizer chain inside these leaves. |
| P15,16 | No gated/derived clocks or opposite-edge state. |
| PRT-01 | Project ready/valid channels, no standard bus; internal divider pipeline has no backpressure and requires a scheduled consumer. |
| TYP-03/P5 | Explicit ports/nets and default_nettype none; Icarus elaborates. Full lint not run. |
| ARI-01,02 | Unsigned vectors, explicit sign comparison/extension, wider result checked before narrowing. S96/S128/S160 and S112/U88 ramp bounds inspected against5.5.1. Some ABI/time containers remain160 as documented. |
| COM-05/P8/P23 | Driver and dependency inspection finds no feedback through combinational logic; the arithmetic process is ordered. Icarus settles and simulations execute; lint remains unavailable. |
| SCP-02,CHK-11 | No synthesis, STA, formal, CDC/RDC, DFT insertion, mapped area/power or target-library reset inference claim. Integration timing is open. |

Mechanical warning decisions: HIE-02 applies to the system top, not this functional
leaf. Eight PAR-03 occurrences are fixed ABI width or coefficients of golden's SI
quadratic; the scale and coefficient meanings are documented in R2_DECISIONS12.
No latch warning or error is waived. Icarus constant-select sensitivity messages
include all bits in sensitivity and are simulator notices, not lint results.
