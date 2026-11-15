#!/bin/bash
# Claude 05/11/2026: after mainB finishes, run the contract ablation stale_tsmxc on the same 64 scenarios.
HERE=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuplan
while [ ! -f $HERE/logs/mainB/done ]; do sleep 300; done
bash $HERE/run_w8c.sh mainC 8 stale_tsmxc
