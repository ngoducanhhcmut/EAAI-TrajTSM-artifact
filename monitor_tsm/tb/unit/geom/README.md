# R7 geometry lane reproduction
Project TSM-X; author TSMX project; version0.1.

From the repository root, Python3.13:
```
py -3.13 -B tsmx_hw/tb/unit/geom/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/geom/check.py
py -3.13 -B tsmx_hw/tb/unit/geom/run.py
py -3.13 -B tsmx_hw/tb/unit/geom/source_mutants.py
```
`build_rtl.py` and `build_tb.py` regenerate owned sources; they are not simulation
dependencies. `run.py` compiles using Icarus and runs disjoint exhaustive shards
and26 independent assertion mutants, with nonzero failure exit status. The random
seed is7007. `vectors.json` preserves source hashes, source counts and reject reasons.
Every full81-bit response is compared. All mem paths are relative to this TB folder.
`--resume` reuses PASS logs: use only with unchanged compiled RTL and vector contents.
Limited slices may leave assertions inactive; the default complete TB and the shard
aggregator fail on any inactive assertion. `run.py` also tests reset during active
divider work (`+RESET_MID=1 +LIMIT=3`) and independently replays all stalled edges.
The source mutation command additionally checks missing stationary points, omitted
jerk inflation, and a missing terminal-endpoint numeric guard. Each must fail the
full-response assertion. `stalled_edges.log` records all34 edge cases with periodic
input bubbles and response stalls: `vvp sim.vvp +START=128 +LIMIT=34` from this folder.

Verilator5 command, from `tsmx_hw/tb/unit/geom`:
```
verilator --binary --timing --assert -Wno-fatal --top-module tb_m_tsmx_geom -I. --Mdir obj_dir ../../../rtl/arith/m_tsmx_arith_div.sv ../../../rtl/geom/m_tsmx_geom_adv.sv ../../../rtl/geom/m_tsmx_geom_swept.sv ../../../rtl/geom/m_tsmx_geom.sv tb_m_tsmx_geom.sv
./obj_dir/Vtb_m_tsmx_geom +NOSTALL=1
```
Verilator was not available in this run; this command is provided for reproduction,
not represented as an executed check. Lint also was not run (R-015). Available
installation routes are OSS CAD Suite, MSYS2, WSL Linux packages, or conda-forge;
the scoped lint log contains the discovery output and suggested commands.

`JOB` lines give measured request-to-response clocks; `ACTOR_II` measures adjacent
actor dispatches within a row, including an event split. Full-load directed cases
contain128 cells×32 actors and a row where all32 events split the cell. Public
job II includes whole-trajectory service, terminal/row arrival and response hold;
it is distinct from the S1b actor-cell II48. Synthesis, formal and STA were not run.
