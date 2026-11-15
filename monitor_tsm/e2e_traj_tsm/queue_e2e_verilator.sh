#!/bin/bash
# Claude 06/11/2026: start the combined Traj+TSM RTL simulation (Verilator) once the 142.857 MHz TSM build has finished
# (host RAM is the limit; Vivado crashed under RAM pressure before). Runs inside WSL.
B=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board/log_142.857143/build.done
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/e2e_traj_tsm
until [ -f $B ]; do sleep 300; done
export PATH=$HOME/oss-cad-suite/bin:$PATH
cd $H
start=$(date +%s)
JOBS_BUILD=2 nice -n 5 bash run_verilator.sh > verilator_run.log 2>&1
echo "rc=$? elapsed_s=$(( $(date +%s)-start )) $(date)" > e2e_verilator.done
