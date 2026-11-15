# R11 health unit

Run from repository root (Python3.13):

```powershell
py -3.13 -B tsmx_hw/tb/unit/health/gen_vectors.py
py -3.13 -B tsmx_hw/tb/unit/health/run.py
py -3.13 -B tsmx_hw/tb/unit/health/source_mutants.py
py -3.13 -B tsmx_hw/tb/unit/health/measure.py
py -3.13 -B tsmx_hw/tb/unit/health/finalize.py
py -3.13 -B tsmx_hw/tb/unit/health/run_verilator.py
```

Python imports golden using `tsmx_hw/golden;tsm2_pilot/vendor`, with bytecode
disabled. Runtime mem paths are relative to this TB directory. The drivers set
that working directory automatically. No file in accepted dependencies is edited.
`build_rtl.py` reproduces only the three owned RTL files and is not needed to test.

The Icarus driver uses `-g2012`; Verilator uses `--binary --timing --assert`,
the same testbench and fixture files, and checks its version is5.x. There is no
X-dependent mutation, force, hierarchical reference, disable-fork or conditional
RTL behavior. Verilator is unavailable on the current host; its execution remains
unverified. `vlsit_lint_rtl.py lint` reports R-015 (lint not run).
Install routes printed by the locator are OSS CAD Suite, MSYS2, WSL or Conda.
Nothing was installed by this task.

```powershell
py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_rtl_check.py check tsmx_hw/rtl/health --report tsmx_hw/rtl/R11_RULES.md
py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_rtl_check.py coverage
py -3.13 .agents/skills/vlsit-rtl-generator/scripts/vlsit_lint_rtl.py lint tsmx_hw/rtl/filelist_R11.f --top m_tsmx_health_lane
```

`results.json`, `simulation.log`, `mutants.json` and `source_mutants.json` record
actual exit statuses, timing and assertion evidence. The driver fails on an absent
assertion hit or any unhealthy bit mismatch. Every job prints measured acceptance
to production cycles. II includes deliberately inserted consumer stalls, unless
`+NO_STALL=1` is passed. `+START=a +END=b` select disjoint vector slices; directed
BIST failure/reset tests always execute. `+MUTANT=k` injects one flipped sampled
observation into named check k; check8/15/25 additionally relate scoreboard/input
state to the interface. These tests establish checker sensitivity, not physical
diagnostic coverage. Real source mutants independently exercise logic defects.

The public core has the exact spec aggregate ports. The structural integration
top `m_tsmx_health_lane` connects it to one dedicated accepted B4/B3 pair through
`m_tsmx_health_bist`. This one-pair scheduling decision is documented in
`rtl/R11_DECISIONS.md`; it is assessed against the measured65536-clock budget.
