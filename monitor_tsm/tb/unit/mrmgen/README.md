# R6 unit reproduction
Project TSM-X; author TSMX project; version 0.1.

From repository root:

```powershell
py -3.13 -B tsmx_hw/tb/unit/mrmgen/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/mrmgen/run.py
py -3.13 -B tsmx_hw/tb/unit/mrmgen/run.py --mutants-only
py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_rtl_check.py check tsmx_hw/rtl/mrmgen
py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_lint_rtl.py lint tsmx_hw/rtl/filelist_R6.f --top m_tsmx_mrmgen
```

`run.py` compiles Icarus with `-g2012` and executes disjoint exhaustive shards,
then records results.json/simulation.log. The second command with --mutants-only
runs all32 sampled DUT-output mutants plus four independent functional source
mutants. Logs preserve commands, assertion names and nonzero killed-mutant exits.
No copy of accepted arithmetic is edited, including for mutation runs.

The fixture converter imports golden and vectors.evaluate, independently validates
full semantic fixture output, and emits jobs.mem/rows.mem and vector counts.
All readmemh paths are relative to this TB directory.

Verilator5 command, run **from this directory** on a system with that tool:

```sh
verilator --binary --timing --assert -Wno-fatal --top-module tb_m_tsmx_mrmgen \
  -I. --Mdir obj_dir ../../../rtl/arith/m_tsmx_arith_div.sv \
  ../../../rtl/arith/m_tsmx_arith.sv ../../../rtl/mrmgen/m_tsmx_mrmgen.sv \
  tb_m_tsmx_mrmgen.sv
./obj_dir/Vtb_m_tsmx_mrmgen
./obj_dir/Vtb_m_tsmx_mrmgen +MUTANT=0 +LIMIT=2
```

Repeat +MUTANT=0..31; each must exit nonzero with matching ASSERT_FAIL.
The Icarus and Verilator commands use identical RTL and expected data.
Verilator compilation/execution was unavailable in this environment and is not
claimed as passing. No force/release, associative arrays, X-only mutants or
simulator-specific RTL branches are used. Icarus constant-select sensitivity
messages mean the complete vector is included in always_comb sensitivity.

Ready/valid contract: one accepted request until all rows and terminal response
are consumed. Row payload401 = cid8,epoch32,index8,Row352,last1.
Row352 = zero64,phase32,xlo64,xhi64,vlo32,vhi32,midpoint_a32,jerk32.
Rows have monotonic index and phase, and remain stable under row stalls.
`last` identifies only the successful appended endpoint; rejection is delimited
by terminal metadata with the exact partial count. B3 must defer authorization
until terminal accept. Request fields are x64,v32,a32,cid8,phase32,limit8.
Response50 = accept1,reason8,stop_valid1,stop32,row_count8; invalid outputs0.
Eight independent instances implement G=8; this unit has one context.

No-stall timing uses +NOSTALL=1 (or the measurement utility), which keeps both
consumers ready while production is active. Normal regression independently
exercises deterministic row stalls, three-cycle terminal stalls and reset during
arithmetic. Watchdogs enforce job163840 cycles excluding modeled stalls.
Only baseline runs require every stall assertion to have a nonzero hit count.

Lint tool install options reported by the skill: OSS CAD Suite, MSYS2 Verilator,
WSL Verilator, or Conda Verilator; no tool is installed by this task.

Additional commands from the repository root:

```powershell
py -3.13 -B tsmx_hw/tb/unit/mrmgen/measure.py
iverilog -g2012 -s tb_mrmgen_param -o tsmx_hw/tb/unit/mrmgen/param.vvp tsmx_hw/rtl/arith/m_tsmx_arith_div.sv tsmx_hw/rtl/arith/m_tsmx_arith.sv tsmx_hw/rtl/mrmgen/m_tsmx_mrmgen.sv tsmx_hw/tb/unit/mrmgen/tb_mrmgen_param.sv
vvp tsmx_hw/tb/unit/mrmgen/param.vvp
```
