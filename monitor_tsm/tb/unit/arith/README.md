# R2 arithmetic unit verification
Project TSM-X; author TSMX project; version0.1.

From the repository root:
```powershell
$env:PYTHONPATH='tsmx_hw/golden;tsm2_pilot/vendor'
py -3.13 -B tsmx_hw/tb/unit/arith/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/arith/check.py
py -3.13 -B tsmx_hw/tb/unit/arith/run.py
```

`run.py` compiles with Icarus, executes all vectors in disjoint ranges with eight
independent simulator processes, verifies aggregate assertion activity, and runs
26 assertion-specific output mutants plus six functional source mutants.
`simulation.log` contains the aggregate result; `shards/S*.log` retain each exact
range and simulation output. `results.json` retains hits and measured latency.
`mutants.json` and `mutants/`, `source_mutants/` retain individual nonzero failures.
`--baseline-only` and `--mutants-only` select verification phases.

To run the entire TB as one simulation, from **this directory**:
```powershell
iverilog -g2012 -s tb_m_tsmx_arith -I . -o sim.vvp ../../../rtl/arith/m_tsmx_arith_div.sv ../../../rtl/arith/m_tsmx_arith.sv tb_m_tsmx_arith.sv
vvp sim.vvp
```
Optional `+START=k +LIMIT=n` covers exactly vector indices k..k+n-1. Mutation
`+MUTANT=i` must fail assertion i. Partial runs do not claim complete assertion
activity; the Python runner enforces it over the exhaustive combined run.
Every `$readmemh` pathname is relative to this directory, for both simulators.

Portable Verilator5 invocation from this directory (requires installed tools):
```sh
verilator --binary --timing --assert -Wno-fatal --top-module tb_m_tsmx_arith -I. ../../../rtl/arith/m_tsmx_arith_div.sv ../../../rtl/arith/m_tsmx_arith.sv tb_m_tsmx_arith.sv
./obj_dir/Vtb_m_tsmx_arith
```
Verilator is unavailable on this machine; this command is provided for reproduction,
not as an executed verification claim. The TB uses no force, X-based mutants,
unsupported break, Icarus-only task, or simulation-specific DUT implementation.

`build_rtl.py` regenerates the main RTL from reviewed fixed templates, including
the repetitive width-specific pipeline instances. The divider is hand-written.
Normal verification does not regenerate or modify RTL.

The raw divider exposes i_valid/i_num/i_den/i_up and o_valid/o_fault/o_data. It has
II1 with six/eight/ten restoring stages after its input register for96/128/160 bits.
Output validity is not stallable: callers must retain tags and reserve storage.
The packed public ARITH interface is stallable and single-outstanding; see the
operation/latency table in `../../../rtl/R2_REPORT.md` and the domain decisions.
