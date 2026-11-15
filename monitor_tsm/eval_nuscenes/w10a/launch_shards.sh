#!/bin/bash
# Claude 07/11/2026: the 8-shard RTL replay (48,790 jobs) was never started; launch it at low priority, log to run_rtl_shards.log.
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuscenes/w10a
start=$(date +%s)
nice -n 10 bash ./run_rtl_shards.sh > run_rtl_shards.log 2>&1
echo "rc=$? elapsed_s=$(( $(date +%s)-start )) $(date)" > run_rtl_shards.done
