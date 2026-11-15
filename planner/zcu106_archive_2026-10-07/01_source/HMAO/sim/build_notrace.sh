#!/usr/bin/env bash
set -e

HMAO=/mnt/c/Users/TransformerDA/Downloads/HMAO
RISCV=$HMAO/RISCV-RV32IM-Processor-main/sources_1/new
SIM=$HMAO/sim

echo "=== Building Verilator binary WITHOUT trace (for speed) ==="
mkdir -p "$SIM/obj_dir_notrace"
cp "$SIM/imem_fw.hex" "$SIM/obj_dir_notrace/imem_fw.hex"

verilator --binary --sv --timing \
  -Wno-lint -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-BLKANDNBLK \
  -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND \
  -Wno-WIDTHTRUNC -Wno-UNSIGNED \
  -y "$RISCV" \
  --top-module tb_hmao_soc \
  --Mdir "$SIM/obj_dir_notrace" \
  -j 4 \
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

echo "=== Build complete ==="
ls -lh "$SIM/obj_dir_notrace/Vtb_hmao_soc"
