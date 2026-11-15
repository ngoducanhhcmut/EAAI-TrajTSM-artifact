#!/bin/bash
# Claude 09/11/2026: run fmax_0911b.sh only after the W10a shard replay has finished (RAM).
until [ -f /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuscenes/w10a/run_rtl_shards.done ]; do sleep 300; done
bash /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board/fmax_0911b.sh
