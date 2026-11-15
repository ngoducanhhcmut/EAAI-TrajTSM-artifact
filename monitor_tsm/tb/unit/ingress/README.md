# R8 ingress unit
Project TSM-X; author TSMX project; version0.1.

From repository root with Python3.13 and Icarus in PATH:

```powershell
py -3.13 -B tsmx_hw/tb/unit/ingress/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/ingress/build_tb.py
py -3.13 -B tsmx_hw/tb/unit/ingress/run.py
py -3.13 -B tsmx_hw/tb/unit/ingress/run_verilator.py
```

Generators import golden with bytecode disabled and add `tsmx_hw/golden` and
`tsm2_pilot/vendor` to the Python path. Memory reads are relative to this TB folder;
the runners set that working directory. Build recipe `build_rtl.py` recreates only
the owned RTL. No other block or fixture is generated/modified.

`run.py --baseline-only` skips mutations. Full run verifies every named assertion
against its targeted DUT-output-wire bit inversion and eight functional source
mutants. All simulator commands, compile warnings, exits and individual mutant
failures are retained in logs. `assertions.json` maps IDs/clauses/output bits;
`results.json` holds hits and measured latency/II. `vectors.json` retains fixture
checksums, semantic case names and reason coverage.

`run_verilator.py` builds with `--binary --timing --assert` and runs the identical
TB. It exits3 with a recorded limitation when the tool is missing. On Linux use
`python3 -B` for these scripts. No tool is installed automatically.

Unit latency counts the acceptance edge as cycle1, matching SEL/ARITH. Each JOB
line prints the measured cycle count. Minimum observed II is with no response
stall; selected vectors deliberately hold response three extra clocks. Reset
tests abort jobs at five different phases and require a clean drain afterward.
The top owns codec timing and persistent state; this unit only proposes a state.
