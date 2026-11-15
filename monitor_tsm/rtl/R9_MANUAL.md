# R9 manual rule inspection
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

Authority: `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md` v2.
Module example: Mealy FSM example, skeleton, accepted SEL. Outputs/controller are
separate combinational processes and one next-state/register process pair.

| Rule | Inspection / result |
|---|---|
| NAM-01 | No replicated objects in cert; dependency generates start at zero. |
| NAM-05 | Only active-low signal is the explicitly named reset. |
| COM-01 | Each output has one process; internal signals each have one owner. |
| SEQ-02 | Request/state/response next values in p_com_ctrl; p_ff_ctrl only registers. |
| SEQ-04 | All local state and dependency validity reset, no stale authorization. |
| RST-01 | Uniform async active-low reset; same core domain. |
| RST-02 | Release synchronization owned by SoC wrapper, spec7; no leaf synchronizer. |
| CLK-01/P28 | No CDC or launch/synchronizer stages in this leaf. |
| P9 | No new functions or function side effects. |
| P15 | No derived/gated clocks. |
| P16 | All state on rising edge of core. TB falling edges only drive stimulus. |
| PRT-01 | Custom project valid/ready interface, exact spec5.3 names; no AMBA claim. |
| SCP-02 | No synthesis result; Config1 defaults, filelist and simulator commands recorded. |
| CHK-11 | Unit elaboration/simulation only; STA/area/formal/CDC/RDC/DFT signoff pending. |
| TYP-03/P5 | default_nettype none, Icarus elaboration finds no undeclared net. |
| COM-05/P23 | Hand inspection: only registered state feeds back; no logical comb loop. |
| ARI-01/02/03 | u32 serial subtracts explicitly narrowed; sign tested independently. |
| P8 | One register process owns all cert state, no output multiple drivers. |
| HIE-02 | Justified functional-leaf warning in header; system top stays structural. |
| PAR-01/02 | Typed parameters, documented locked values; localparams in port list. |
| COM-07 | Defaults on all comb paths; no latch by inspection, lint unavailable. |
| RST-03/04 | Technology reset mapping/scan override remain wrapper/implementation work. |
| HIE-06/07 | No new RAM or technology cells. Dependency is generic accepted arithmetic. |

Skill matrix: R-001 evidence in logs; R-002/003/007/009/010/011/018/020/022/023
inspected; R-004 six template gaps recorded; R-005/006 and question gates delegated;
R-008 not applicable (new module); R-012/019 script PASS; R-013 one warning justified;
R-014 attempted, R-015 lint not run; R-016 this matrix and R9_REPORT;
R-017 generated filelist includes both arithmetic dependencies;
R-024/025 simulation assertions and mutation evidence; R-026 no unresolved failure.
R-021 no example modifications: examples are read-only inputs for this scoped task.

No mapped resource count or physical timing is inferred from Python or simulation.
