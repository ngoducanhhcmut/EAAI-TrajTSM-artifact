#!/usr/bin/env bash
SIM=/mnt/c/Users/TransformerDA/Downloads/HMAO/sim

cd "$SIM/obj_dir_notrace"
cp "$SIM/imem_fw.hex" ./imem_fw.hex

echo "[sim] Running NO-TRACE simulation (fast mode)..."
time timeout 300 ./Vtb_hmao_soc 2>&1 | tee "$SIM/sim_fast.log"
EC=${PIPESTATUS[0]}
echo ""
echo "[sim] Exit code: $EC"
