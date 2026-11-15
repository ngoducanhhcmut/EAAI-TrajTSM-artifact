# I1 integration acceptance record
Project TSM-X; author TSMX project; version0.1; updated2026-10-30 (I1b).

**INCOMPLETE: full acceptance is not established.** In-flight runs are not passes.
This file is written before long regressions so an interrupted run leaves evidence.

| Category | Confirmed evidence / status |
|---|---|
| CSR root cause | Old TB reversed pending/backup; full-word map corrected; D25 |
| Isolated CSR profile | Icarus PASS16; XSim2023.2 FAIL0/unknown next-state |
| Top CSR/AXI + fault smoke | PASS2/2; simulation_2_iverilog_smoke.log |
| Assertions |40/40 active;0 failures,0 inactive in fault smoke |
| Observation mutants |20/20 killed by named check; mutants.json |
| Owned RTL source mutants |2/2 killed: FSM twohot and brake low; source_mutants.json |
| Cached timer boundaries |19/19 PASS; control_iverilog_2_timers_only.log; cached state |
| Physical timer/deadline | Pending current execution; previous deadline log preserved |
| System replay | First1/128 PASS32862 clocks (0.175264ms); full replay pending |
| System edges |14 fixtures/15 physical jobs generated; execution pending |
| New multi-cycle sequences |500x6=3000 generated; execution pending |
| Reachable six-mode chain |8 additional jobs generated; execution pending |
| Timing at8/8 |32-object two-sweep run in progress; not a measured WCET yet |
| Math/hash helpers | PASS400/400 each; helpers_sim.log and hash_sim.log; D26/D29 |
| SYNTHESIS smoke | PASS2/2 with40 active checks; same outputs/11-clock latency |
| Rule check/filelist | PASS0 errors; HIE-02/PAR-03 warnings justified in headers/D3 |
| Lint | NOT RUN, R-015: no Verilator/slang; WSL access denied |

Cycle/ms conversion: cycles/187500; S1b budget1168034=6.229515ms;
deadline1875000=10ms. Neither value is a measured successful-decision WCET.
The legal10m/s stop+hold domain is <=7.6s;128 cells is the storage cap (D27).
Timing TB requires both16-candidate masks,32 actors, streaming and S1b cycle bound.
No sub-block modification is requested or made. XSim incompatibility remains a
simulator limitation; it does not justify changing accepted CSR behavior.

Reproduce from repository root (Linux: replace `py -3.13` with `python3`):
```sh
py -3.13 -B tsmx_hw/tb/integ/gen_sequences.py
py -3.13 -B tsmx_hw/tb/integ/build_tb.py
py -3.13 -B tsmx_hw/tb/integ/build_control_tb.py
py -3.13 -B tsmx_hw/tb/integ/check.py
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 2 --tag full
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 8 --limit 128 --allow-inactive --tag system
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 8 --skip-compile --file worst.mem --limit 1 --allow-inactive --worst --tag worst
py -3.13 -B tsmx_hw/tb/integ/run_control.py --tool verilator --lanes 8
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 2 --skip-compile --file smoke.mem --limit 2 --tag smoke
py -3.13 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 2 --bist-fault --allow-inactive --tag bist
py -3.13 -B tsmx_hw/tb/integ/probe_helpers.py
py -3.13 -B tsmx_hw/tb/integ/mutants.py --tool verilator
py -3.13 -B tsmx_hw/tb/integ/source_mutants.py --tool verilator
```
Verilator runner uses `--binary --timing --assert -Wno-fatal -j 4` with
`tb_m_tsmx_top -GLANES=2/8`, or `tb_tsmx_control_phy -GLANES=8`.
Full Verilator compilation/execution remains unverified in this environment.
Mutants support both tools; select the tool used to compile the baseline smoke.

Rule IDs: R-002/005/006/008/009 delegated I1-owned continuation (D1);
R-003/007/010/012/017/018/019/022 inspected/script clean;
R-011/013 HIE-02 functional wrappers, PAR-03 fixed ABI/SI literals justified;
R-014/015 lint unavailable (OSS CAD Suite/MSYS2/Conda installation options in I1_LINT.md);
R-024/02540 active assertions,20 observation+2 source mutants verified;
R-001/016 this evidence record; R-023 golden/spec-derived checks;
R-026 CSR mismatch traced before modification. R-004 prior gap disposition D2.
Manual NAM/COM/SEQ/RST/CLK hierarchy inspected; SCP-02/CHK-11 synthesis,
STA/PPA, CDC/RDC, DFT and formal are not run. R-020 examples read; R-021 unchanged.
