#!/bin/bash
# Claude 05/11/2026: full 3,151-job integration set on the final RTL (r17 binary obj_2, P=G=2), for the manuscript.
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/tb/integ
OUT=vl_claude_r17_a8_apos/full3151.txt
echo "COMMAND: ./obj_2/Vtb_m_tsmx_top +FILE=vectors.mem  start $(date)" > $OUT
stdbuf -oL ./obj_2/Vtb_m_tsmx_top +FILE=vectors.mem >> $OUT 2>&1
echo "rc=$? end $(date)" >> $OUT
echo done > vl_claude_r17_a8_apos/full3151.done
