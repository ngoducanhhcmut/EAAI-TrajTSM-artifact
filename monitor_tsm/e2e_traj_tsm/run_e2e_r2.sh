#!/bin/bash
# Claude 07/11/2026: rerun the combined Traj+TSM RTL simulation with the GRU sigmoid/tanh LUT init files present in the
# working directory (r1 failed: $readmem file not found -> wrong waypoints, frame 0 delta -4.16 m). Reuses obj_e2e.
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/e2e_traj_tsm
start=$(date +%s)
nice -n 5 ./obj_e2e/Vtb_e2e_traj_tsm +PLANNER_VEC=../../../tb/e2e/vec/ > verilator_run_r2.log 2>&1
echo "rc=$? elapsed_s=$(( $(date +%s)-start )) $(date)" > e2e_r2.done
