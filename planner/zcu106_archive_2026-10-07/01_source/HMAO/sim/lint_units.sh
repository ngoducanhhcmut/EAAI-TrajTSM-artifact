#!/usr/bin/env bash
HMAO=/mnt/c/Users/TransformerDA/Downloads/HMAO
RISCV=$HMAO/RISCV-RV32IM-Processor-main/sources_1/new
TB=$HMAO/tb

# Common flags
VFLAGS="--lint-only --sv --timing -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-BLKANDNBLK \
  -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -Wno-UNSIGNED -Wno-PINCONNECTEMPTY"

PKG="$HMAO/hmao_pkg.sv $HMAO/hmao_interfaces.sv"

run_lint() {
  local name=$1
  local top=$2
  shift 2
  local files="$@"

  result=$(verilator $VFLAGS --top-module $top $PKG $files 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name"
    echo "$result" | grep -E "^%Error" | head -5
  fi
}

echo "=== Unit Testbench Lint Check ==="

run_lint "U1 preproc_batch1" "tb_preproc_batch_u1" \
  "$HMAO/hmao_preproc.sv" "$TB/tb_preproc_batch_u1.sv"

run_lint "U2 preproc_batch2" "tb_preproc_batch_u2" \
  "$HMAO/hmao_preproc.sv" "$TB/tb_preproc_batch_u2.sv"

run_lint "U3 adaptive_margin" "tb_hmao_adaptive_margin_U3" \
  "$HMAO/hmao_adaptive_margin.sv" "$TB/tb_hmao_adaptive_margin_U3.sv"

run_lint "U4 zonotope_gen1" "tb_hmao_zonotope_gen_u4" \
  "$HMAO/hmao_zonotope_gen.sv" "$TB/tb_hmao_zonotope_gen_u4.sv"

run_lint "U5 zonotope_gen2" "tb_hmao_zonotope_gen_u5" \
  "$HMAO/hmao_zonotope_gen.sv" "$TB/tb_hmao_zonotope_gen_u5.sv"

run_lint "U6 admm_u6" "tb_hmao_admm_u6" \
  "$HMAO/hmao_admm_solver.sv" "$TB/tb_hmao_admm_u6.sv"

run_lint "U7 admm_u7" "tb_hmao_admm_u7" \
  "$HMAO/hmao_admm_solver.sv" "$TB/tb_hmao_admm_u7.sv"

run_lint "U8 collision_sat_u8" "tb_hmao_collision_sat_u8" \
  "$HMAO/hmao_collision_sat.sv" "$TB/tb_hmao_collision_sat_u8.sv"

run_lint "U9 collision_sat_u9" "tb_hmao_collision_sat_u9" \
  "$HMAO/hmao_collision_sat.sv" "$TB/tb_hmao_collision_sat_u9.sv"

run_lint "U10 fsm_u10" "tb_u10_hmao_fsm" \
  "$HMAO/hmao_fsm.sv" "$TB/tb_u10_hmao_fsm.sv"

run_lint "U11 fsm_u11" "tb_u11_hmao_fsm" \
  "$HMAO/hmao_fsm.sv" "$TB/tb_u11_hmao_fsm.sv"

run_lint "U12 wdt" "tb_u12_wdt" \
  "$HMAO/hmao_safety_modules.sv" "$TB/tb_u12_wdt.sv"

run_lint "U13 hmao_engine" "tb_hmao_u13" \
  -y "$RISCV" \
  "$HMAO/hmao_fsm.sv" "$HMAO/hmao_preproc.sv" "$HMAO/hmao_zonotope_gen.sv" \
  "$HMAO/hmao_admm_solver.sv" "$HMAO/hmao_collision_sat.sv" \
  "$HMAO/hmao_adaptive_margin.sv" "$HMAO/hmao_axi_arbiter.sv" \
  "$HMAO/hmao_engine_top.sv" "$HMAO/hmao_safety_modules.sv" \
  "$TB/tb_hmao_u13.sv"

run_lint "U14 axi_arbiter" "tb_hmao_axi_arbiter_u14" \
  "$HMAO/hmao_axi_arbiter.sv" "$TB/tb_hmao_axi_arbiter_u14.sv"

echo "=== Done ==="
