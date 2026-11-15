# B2 splice unit verification
TSM-X / TSMX project / version0.1.

From repository root:
```powershell
$env:PYTHONPATH='tsmx_hw/golden;tsm2_pilot/vendor'
py -3.13 -B tsmx_hw/tb/unit/splice/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/splice/make_tb.py
py -3.13 -B tsmx_hw/tb/unit/splice/run.py
```
run.py compiles Icarus, runs disjoint exhaustive shards, checks all24 assertion
mutants and five copied-source mutants. Logs include commands and exit status.
vectors.json records input hashes/seed/counts; results.json is the aggregate.
Each job prints production cycles. UNSTALLED prints separately measured latency
and initiation interval with continuous requests and response ready asserted.
The general II line includes the deliberately injected stalls/idle/reset work.

From this TB directory, with Verilator5 and a C++ toolchain installed:
```sh
verilator --binary --timing --assert -Wno-fatal --top-module tb_m_tsmx_splice -I. ../../../rtl/arith/m_tsmx_arith_div.sv ../../../rtl/arith/m_tsmx_arith.sv ../../../rtl/splice/m_tsmx_splice.sv tb_m_tsmx_splice.sv
./obj_dir/Vtb_m_tsmx_splice
./obj_dir/Vtb_m_tsmx_splice +MUTANT=0 +LIMIT=10
```
Repeat MUTANT=0..23, expecting nonzero exit with the matching ASSERT_FAIL ID.
Verilator/slang were unavailable during this handoff, so this command is supplied
for reproduction and is not evidence of an executed Verilator compile/run.
readmemh always resolves vectors.mem relative to this TB directory.

Rule/lint reproduction from repository root:
```powershell
py -3.13 -B .agents/skills/vlsit-rtl-generator/scripts/vlsit_rtl_check.py check tsmx_hw/rtl/splice
py -3.13 -B .agents/skills/vlsit-rtl-generator/scripts/vlsit_lint_rtl.py lint tsmx_hw/rtl/filelist_R5.f --top m_tsmx_splice
```
