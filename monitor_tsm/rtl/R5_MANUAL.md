# R5 rule inspection matrix
Project TSM-X; author TSMX project; version 0.1; date2026-10-29.

| Rule | Current-run inspection |
|---|---|
| R-001 | Report claims tied to saved simulator/check logs; unrun signoff disclosed. |
| R-002/009/018 | New files only in designer-authorized paths; originals unchanged. |
| R-003/007 | VLSIT v2 read; header values match designer. |
| R-004 | Gap script run: six formatting BLOCK findings resolved in decisions2. |
| R-005/006 | Designer delegation overrides question/approval gates. |
| R-008 | Generate mode; no baseline RTL modified. |
| R-010/022 | TB requested, isolated in tb/unit/splice; filelist design-only. |
| R-011/013 | HIE-02 and seven PAR-03 warnings justified in header/decisions10. |
| R-012/019 | Mechanical final rule check PASS; case for FSM's six branches. |
| R-014/015 | Lint attempted; no lint tool, R-015. Icarus elaboration is not lint. |
| R-016/017 | This matrix; filelist generated with skill script, includes arith. |
| R-020 | Moore example plus skeleton: state-only outputs, next-state, sequential. |
| R-021 | Example checked read-only; repository example sources not changed. |
| R-023 | Stimuli/expected from golden/spec; assertions cite5.3/7/9/10/REQ005. |
| R-024/025 | 24 assertions, hit counts, fatal failures/zero hits; mutant logs. |
| R-026 | Smoke failure analyzed as ABI slice transcription, fixed against9.2. |
| NAM-01 | No replicated instance groups; bit/array indexing starts0. |
| NAM-05 | No active-low non-reset port. |
| COM-01 | Outputs/process temporaries have exactly one owner. |
| SEQ-02 | w_*_nxt computed combinationally; always_ff only registers. |
| SEQ-04 | Every state/payload flop resets; no resetless consumption. |
| RST-01 | Async active-low reset, rising core clock consistently. |
| RST-02 | Leaf assumes synchronized reset release from SoC wrapper, section7. |
| CLK-01/P28 | Single synchronous domain; no CDC structures in this leaf. |
| P9 | Automatic deterministic compare functions, no side effects/state. |
| P15/P16 | No generated/gated clocks; positive edge only. |
| PRT-01 | Project custom handshake, no AMBA or other standard bus. |
| SCP-02 | No synthesis result; constraint/library/STA signoff not claimed. |
| CHK-11 | Source hygiene inspected; physical/DFT/CDC/RDC/equivalence pending. |
| ARI-01/02 | Sign extension explicit; ingress proof bounds all local additions. |
| TYP-03/P5 | default_nettype none and Icarus elaboration check declarations. |
| COM-05/P8/P23 | Dependency/driver inspection: no loops or multiple drivers. |

No full lint, synthesis, mapped resource inference, STA, formal equivalence,
CDC/RDC/DFT or physical signoff has been performed.
