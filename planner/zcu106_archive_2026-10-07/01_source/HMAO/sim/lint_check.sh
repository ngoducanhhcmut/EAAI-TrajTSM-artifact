#!/usr/bin/env bash
HMAO=/mnt/c/Users/TransformerDA/Downloads/HMAO
RISCV=$HMAO/RISCV-RV32IM-Processor-main/sources_1/new

echo "=== Verilator Lint/Syntax Check ==="
verilator --lint-only --sv --timing \
  -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-BLKANDNBLK \
  -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND \
  -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-PINCONNECTEMPTY \
  -y "$RISCV" \
  --top-module tb_hmao_soc \
  "$HMAO/hmao_pkg.sv" \
  "$HMAO/hmao_interfaces.sv" \
  "$HMAO/hmao_fsm.sv" \
  "$HMAO/hmao_preproc.sv" \
  "$HMAO/hmao_zonotope_gen.sv" \
  "$HMAO/hmao_admm_solver.sv" \
  "$HMAO/hmao_collision_sat.sv" \
  "$HMAO/hmao_adaptive_margin.sv" \
  "$HMAO/hmao_axi_arbiter.sv" \
  "$HMAO/hmao_engine_top.sv" \
  "$HMAO/hmao_safety_modules.sv" \
  "$HMAO/riscv_dcls_wrapper.sv" \
  "$HMAO/hmao_soc_top.sv" \
  "$HMAO/tb/tb_hmao_soc.sv" \
  2>&1
echo "=== LINT EXIT CODE: $?"
