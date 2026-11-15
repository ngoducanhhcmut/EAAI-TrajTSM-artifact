# R1 — TSM-X RTL wave 1
Project TSM-X; author TSMX project; version0.1; date2026-10-29.

| Block | Golden passed/total | Directed rows | Assertions | Output mutants killed | RTL source mutants killed | Rule findings | Lint | Latency / spec bound |
|---|---:|---:|---:|---:|---:|---|---|---|
| B7 m_tsmx_sel | 128/128 | 65536 masks | 26 | 26/26 | 4/4 | 0E/0W/0I | Not run, R-015 | 1 / <=64 cycles |
| B8 m_tsmx_supervisor | 128/128 | 8192 combinations | 30 | 30/30 | 4/4 | 0E/0W/0I | Not run, R-015 | 1 / <=32 cycles |
| B10 m_tsmx_rec | 128/128 | 1704 total packed operations | 36 | 36/36 | 4/4 | 0E/0W/0I | Not run, R-015 | 1 write, 1 read / write<=2 cycles |

All physical output fields are compared bit-exact; B10 retained Events are read
and compared in full, oldest first. Fixture SHA256 and applicable semantic fixture
fields/digests are cross-checked during conversion; fixture hashes are not RTL ports.
B8 nonphysical retained fields are checked unchanged during conversion.
Baseline assertion failures:0; assertions never exercised:0, in all three logs.
Immediate assertions cite spec5.3/5.5.7/8/10/9.2 and print their own hit counts.
Every assertion fails with nonzero exit on its own DUT-output stuck-X injection.
Functional source mutants cover selection/masking/label, threshold/health/precedence,
response stalls, invalid append, ring head, lost wrap and read/write collision.

B10 additionally passes depths1,3,64,1024 with overwrite and complete indexed drain.
Corner cases include zero/four fields, empty/max strings, signed integer boundaries,
invalid schema/count/length/padding, saturated lost, pre-write read collisions,
write progress during a stalled log response, out-of-range reads and reset in flight.
Supplementary depth runs exercise a subset; full assertion activity uses golden depth4.
Latency is acceptance-to-valid production; consumer stalls may extend response hold.
No ready-consumer replacement on the same edge: steady throughput one request/2clocks.

Icarus12.0(devel), `C:/iverilog/bin/iverilog -g2012` plus vvp: PASS.
Icarus constant-select sensitivity notices are accepted simulator notices (all bits
included), not lint. Exact compile/run commands and exit codes are in TB logs.
VLSIT v2 rule check: PASS for each block and full source set, 0ERROR/0WARN/0INFO.
R-004 scoped gap scan reports14 missing-template BLOCKs: resolved under delegation,
DEV-002; no behavioral gap remains. R-005/R-006 gates superseded by user delegation.
R-012/R-019 script-clean; R-022..025 simulation-verified; manual rule matrix and
R-001..026 outcomes: [R1_RULES.md](R1_RULES.md). Decisions: [R1_DECISIONS.md](R1_DECISIONS.md).
R-014 attempted for all tops; **lint not run (R-015)**: no Verilator/slang found.
Options: OSS CAD Suite, MSYS2 Verilator, WSL Verilator, Conda; nothing installed.
Synthesis, STA, RAM inference, formal, CDC/RDC/DFT signoff were not run.

Reproduce from repository root with the located Python3 interpreter:
`python tsmx_hw/tb/unit/check_R1.py`
`python tsmx_hw/tb/unit/run_R1.py`
RTL aggregate filelist: `tsmx_hw/rtl/filelist_R1.f` (3 independent tops).
Per-block evidence: `tsmx_hw/tb/unit/<blk>/{compile,simulation,mutant_run}.log`,
`assertions.json`, `mutants/M*.log`, `source_mutants/*.{sv,log}`, `vectors.mem`.
Machine summaries: `tsmx_hw/tb/unit/R1_{vectors,results}.json`.
No golden/spec/vector/verify source was edited by this work.
