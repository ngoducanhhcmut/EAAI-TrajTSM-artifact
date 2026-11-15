# R4 — m_tsmx_csr
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

| Check | Verified result |
|---|---|
| Golden system fixtures | 128/128; SHA256 and semantic hex fields checked |
| Physical outputs | All 10 outputs bit-exact on 53603/53603 cycles |
| Register contract | All 52 JSON registers; reset/access/strobes/side effects |
| Random stimulus | 2400 bus operations; seed 0x54345352; concurrent snapshots |
| Directed tests | AW/W skew, all stalls, W1C races, RO errors, reserved zero |
| Additional corners | BIST/enable, active protection, reset aborts, saturation |
| Boundary tests | Every CSR_UPDATE field min/max; all register byte lanes |
| Assertions | 59/59 exercised; failures 0; never exercised 0 |
| Interface fault mutants | 59/59 killed by their own assertions, nonzero exits |
| Functional RTL mutants | 8/8 killed; exact replacements and logs retained |
| VLSIT rule checker | PASS: 0 errors, 0 warnings, 0 info |
| Lint | **Not run, R-015:** no Verilator/slang installed |
| Verilator 5 binary run | **Not run:** executable unavailable; command in TB README |
| Icarus | iverilog -g2012 / vvp, baseline and every mutant executed |

Read latency 1 cycle; write latency 2 cycles from the last AW/W handshake;
both satisfy 5.5.12's <=4-cycle response bound. Ready consumers permit read II2
and paired-write II3. Arbitrary channel skew/stalls extend host transaction time,
not status updates. Section 10.3 allocates 16384 cycles for CSR/arbiter/stalls;
this bus leaf never gates decision execution or independent status snapshots.
377 declared state bits before optimization; Config1 locked values decode as
constants. No RAM, multipliers, dividers, clock gates or CDC. Synthesis and STA
were not run; no inferred cell count, area, power or timing signoff is claimed.

Rule-ID disposition (VLSIT_RTL_Design_Rule.md v2):
- R-001/003/004/007/009/010/012/013/017/018/019/020/022..025: inspected/pass;
  mechanical findings are in csr/rule_check.md, assertion hits in simulation.log.
- R-002/008: new CSR outputs only, no preexisting source replacement.
- R-005/006/026: delegated supervisor resolutions in R4_DECISIONS.md.
- R-011: no SHOULD deviation; protocol prefix follows spec under NAM-02.
- R-014/015: lint not run; install options: OSS CAD Suite, MSYS2, WSL or Conda.
- R-016: this report; R-021: shared example unchanged, no copied rule violation.
- Manual NAM-01/05, COM-01, SEQ-02/04, RST-01: inspected/pass.
- Manual RST-02, CLK-01, P28: synchronized leaf reset assumed; no CDC present.
- Manual P9/P15/P16: no functions, gated clocks, or both-edge functional state.
- Manual PRT-01: spec i_axi/o_axi names retained (NAM-02); PROT ignored by policy.
- Manual SCP-02/CHK-11: synthesis, libraries, CDC/RDC, scan, formal and STA pending.
- TYP-03/COM-05/ARI-01/P5/P8/P23: source inspection and Icarus elaboration pass;
  dedicated lint coverage is unavailable, not represented as completed lint.

Reproduce: `py -3.13 -B tsmx_hw/tb/unit/csr/run.py` from repository root.
Filelist: `tsmx_hw/rtl/filelist_R4.f`; top: `m_tsmx_csr`; parameters 16/32.
Rule command: `py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_rtl_check.py check tsmx_hw/rtl/csr`.
Lint command: `py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_lint_rtl.py lint tsmx_hw/rtl/filelist_R4.f --top m_tsmx_csr --log tsmx_hw/rtl/csr/lint.log`.
