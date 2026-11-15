# I1 manual rule disposition
Project TSM-X; author TSMX project; version0.1;2026-10-30.

Scope is I1-owned top sources. Accepted leaves retain their accepted reports.
Rules v2: `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md`.

| Manual rule | Inspection / limit |
|---|---|
| NAM-01 | generate indices and repeated instance suffixes start at0 |
| NAM-05 | Owned active-low signals are core resets with `_n_core` |
| COM-01 | Decode/output/state each have one source; pure math decodes use assigns |
| SEQ-02 | Owned controllers compute next-state separately from always_ff storage |
| SEQ-04 | Valid/control, engine authorization and staging counts reset explicitly |
| RST-01 | Async active-low core reset; release comes from owned rst wrapper |
| RST-02 | m_tsmx_rst contains the two-stage core reset release synchronizer |
| CLK-01 | Single core domain; external source synchronization is a SoC assumption |
| P9 | f_s32/f_s64/f_lt/f_diff/f_abs automatic, pure bit-vector operations |
| P15 | No derived/gated functional clock in owned RTL |
| P16 | State uses rising core edges only |
| P28 | Reset synchronizer stages are dedicated flops; no intervening logic |
| PRT-01 | Exact spec AXI signal names retained under NAM-02 (axi prefix) |
| SCP-02 | Simulation/filelists recorded; synthesis environment/signoff unavailable |
| CHK-11 | Functional work is partial; STA/PPA/CDC/RDC/DFT/formal not performed |

Mechanical checker: I1_RULES.md, no errors. HIE-02 warnings refer to functional
children rather than the structural m_tsmx_top; PAR-03 literals encode fixed ABI
slices, SI constants and enumerated arithmetic ops. Module headers record these
waivers (reviewer: delegated I1 integration author). No inferred latch is waived.
The undefined bad-health-parameter instance emitted by filelist discovery is an
intentional invalid-elaboration guard in an accepted leaf, inactive at default.
No accepted source was edited to suppress it.

Lint-only checks TYP-03/COM-05/ARI-01/P5/P8/P23 remain **not covered by lint**;
Icarus elaboration and source inspection do not substitute for dedicated lint.
Rule-checker COM-07 inspection is likewise not a claim of synthesis latch analysis.
R-001..026 dispositions and incomplete simulation categories are in I1_REPORT.md.
