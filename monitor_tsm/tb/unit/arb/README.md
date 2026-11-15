# R10 command authority mux
Project TSM-X; author TSMX project; version0.1.

From the repository root, with Python3.13 and Icarus on PATH:

```powershell
py -3.13 -B tsmx_hw/tb/unit/arb/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/arb/build_tb.py
py -3.13 -B tsmx_hw/tb/unit/arb/run.py --mutants
py -3.13 -B tsmx_hw/tb/unit/arb/check.py
```

Python adds `tsmx_hw/golden;tsm2_pilot/vendor` to sys.path and disables bytecode
writes. All readmemh paths are relative to this TB directory; run.py sets cwd.
The synthesis filelist includes only the arb leaf: no arithmetic lanes are needed.

Verilator5 replay, when installed:

```powershell
py -3.13 -B tsmx_hw/tb/unit/arb/run.py --verilator
```

This invokes `verilator --binary --timing --assert -Wno-fatal --top-module
tb_m_tsmx_arb` with the same RTL/TB and runs the generated executable. The runner
records build/simulation logs. The portable SV uses immediate assertions and
binary observation-wire mutations; no force, X-dependent mutations or RTL macros.
Verilator execution is presently unverified because the tool is unavailable.

The declared Command port is1997 bits, but golden fields total1897: upper100
bits are zero; source is[1896:1894]. See R10_DECISIONS.md for all bit-layout and
source-code choices. Top must supply authorized immutable records and drive
i_override on subcycle faults; this unit cannot monitor expiry from a sampled now.
System/edge vectors are golden state projections through the documented mux map.

Evidence: vectors.json/mem, assertions.json, compile.log, simulation.log,
results.json, mutants/M*.log and source_mutants/*.{sv,log,vvp}. The reset-aborted
directed job is assertion-checked but is not counted as a completed vector.
