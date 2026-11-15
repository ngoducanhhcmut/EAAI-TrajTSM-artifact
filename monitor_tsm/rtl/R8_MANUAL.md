# R8 manual rule inspection
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

| Rule | Result / evidence |
|---|---|
| R-001 | Only current Icarus/checker results claimed; lint/Verilator/physical signoff explicitly unverified. |
| R-002,008,009 | New owned ingress sources; no pre-existing design overwritten or other block edited. |
| R-003,007 | Named VLSIT v2 rule read; project/author/version supplied by user. |
| R-004..006 | Gap scan run before RTL; six title mismatches resolved by explicit delegation, decisions1/2. |
| R-010,018,022 | RTL and TB separated, filelist excludes verification; writes confined to R8 paths. |
| R-011,013,020 | Moore example/skeleton and SEL read; sole HIE-02 warning justified in header/decisions11. |
| R-012,019 | Final mechanical PASS; every selection of three or more branches uses case/casez. |
| R-014,015 | Lint attempted: exit3, no lint tool. Options in lint.log; nothing installed. |
| R-016,017 | Generated filelist_R8.f includes both ARITH files and ingress in dependency order. |
| R-021 | Reference examples inspected, not modified; ownership excludes changes to skills. |
| R-023 | Expected values from golden, handshake from5.3/7, packed ABI from9.2; no oracle from RTL. |
| R-024,025 | 27 clause-tagged immediate assertions, all active; all27 targeted output mutants fail their own assertion nonzero. Eight functional source mutants fail. |
| R-026 | Delegation resolves gaps. JSON tuple normalization and TB offset correction documented in decisions9. |
| NAM-01,05 | No replicated ingress instances; packed ranges start at0; only reset is active-low. |
| COM-01,SEQ-02 | Each next-state/output has one combinational owner; sequential process only registers next values. |
| SEQ-04,RST-01 | All ingress control/request/response state resets asynchronously active-low, rising core clock only. |
| RST-02,RST-04 | Wrapper supplies reset synchronizer and scan reset override; leaf generates neither. |
| CLK-01,P28 | One domain, no crossing or synchronizer stages inside ingress. |
| P9,COM-06 | Automatic position/numeric/range functions are deterministic and have no external writes/static state. |
| P15,P16 | No gating/derived clock or falling-edge state. |
| PRT-01 | Custom project ready/valid channel, no standard bus claim; names follow common5.3. |
| TYP-03,P5 | default_nettype none and explicit declarations; Icarus elaboration confirms no undeclared nets. Full lint unavailable. |
| ARI-01,02 | Modular32-bit ages, explicit65-bit sign extension and absolute delta, unsigned magnitude range comparisons. No variable division/modulo. |
| COM-05,P8,P23 | One driver per state; no combinational feedback identified by inspection; Icarus simulations settle. Tool lint remains open. |
| SCP-02,CHK-11 | No synthesis/STA/formal/CDC/RDC/DFT signoff;187.5MHz remains target, not measured frequency. |

R8_COVERAGE.md preserves the checker/manual/lint rule partition. R8_RULES.md lists
the final mechanical findings. All remaining verification evidence is confined to
`../tb/unit/ingress/`; accepted ARITH is instantiated unchanged, not recertified here.
