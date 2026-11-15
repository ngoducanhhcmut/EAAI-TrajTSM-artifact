#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
command -v verilator >/dev/null
verilator --version
# Behavioral XPM model is scoped to this harness; no production RTL edits.
# Override JOBS_BUILD to limit compiler RAM use. No SIMULATION fast-path define.
verilator --binary --timing --assert -Wno-fatal -DSYNTHESIS -DASSERT_ON \
  +incdir+../../../rtl/include +incdir+../../../rtl/src/bert_v2 +incdir+. --top-module tb_e2e_traj_tsm \
  --Mdir obj_e2e -j "${JOBS_BUILD:-2}" -f sources.f xpm_memory_e2e.sv \
  > verilator_build.log 2>&1
exec ./obj_e2e/Vtb_e2e_traj_tsm +PLANNER_VEC=../../../tb/e2e/vec/ "$@"
