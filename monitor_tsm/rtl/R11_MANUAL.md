# R11 rule-ID and manual inspection
Rules: VLSIT_RTL_Design_Rule.md v2 at the designer-supplied skill path.

| Rule or group | Current inspection/result |
|---|---|
| R-001 | Claims bounded by retained commands/logs; Verilator and signoff unverified |
| R-002/009/018 | Only owned health RTL/TB and R11-named deliverables created |
| R-003/004 | Full rule read; six template-heading gaps scanned and resolved in decisions2 |
| R-005/006 | Supervisor delegation explicitly supersedes question/approval gates |
| R-007 | Project TSM-X, author TSMX project, version0.1 in all RTL headers |
| R-008 | New-block generation, no modification of accepted RTL |
| R-010/022/023 | Separate requested TB; oracle imports golden and clause references |
| R-011/013 | Functional-leaf HIE-02 and fixed ABI/SI constants explained in headers/decisions |
| R-012/019 | Final mechanical report R11_RULES.md |
| R-014/015 | Lint attempted; no Verilator/slang; R-015, lint not run |
| R-016/017 | Rule matrix and generated filelist_R11.f, leaf dependencies included |
| R-020/021 | Moore example/skeleton/SEL read; examples not changed under ownership limits |
| R-024/025 | 26 named checks with hit counts; failures/inactive checks terminate nonzero |
| R-026 | Clear packing/TB failures resolved from specified fields under delegation |
| NAM-01/05 | Array slots and instance indexing start at0; no other active-low signals |
| COM-01 | One owner per net; dependency outputs and derived ready/valid are separate |
| SEQ-02/04 | Next values in combinational logic; control and payload reset explicitly |
| RST-01 | Consistent asynchronous active-low assertion, rising-edge operation |
| RST-02/04 | Wrapper owns synchronized reset release and DFT reset override |
| CLK-01/P28 | Single core domain; no internal crossing or synchronizer |
| P9 | No owned functions with side effects |
| P15/P16 | No derived/gated clocks; no falling-edge functional state |
| PRT-01 | Project valid/ready channels; no AMBA interface on this block |
| TYP-03/P5 | default_nettype none and successful Icarus elaboration; no full lint |
| ARI-01/P8/P23 | Sizing/one-driver/acyclic structure inspected; no independent lint confirmation |
| SCP-02/CHK-11 | Synthesis/STA/formal/CDC/RDC/DFT/technology signoff not performed |

Owned hardware performs XOR parity, unsigned comparisons and constant-scaled
address indexing only. Arithmetic used by BIST remains in private accepted blocks.
No slash/modulo arithmetic, signed/two-state declarations, implicit nets, hidden
reset/cancel signals, latches, X/Z outputs or simulator-specific RTL branches.
