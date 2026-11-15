#!/bin/bash
# Claude 07/11/2026: waypoint-corruption mutant on the combined Traj+TSM RTL bench. Reuses obj_e2e (same build as the
# 35/35 baseline r2). The pass/fail criteria of run_mutant.py are then applied to verilator_mutant.log by check_mutant_r1.py.
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/e2e_traj_tsm
start=$(date +%s)
nice -n 5 ./obj_e2e/Vtb_e2e_traj_tsm +PLANNER_VEC=../../../tb/e2e/vec/ +MUTANT_WAYPOINT > verilator_mutant.log 2>&1
echo "rc=$? elapsed_s=$(( $(date +%s)-start )) $(date)" > mutant_r1.done
