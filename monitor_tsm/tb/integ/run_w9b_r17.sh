#!/bin/bash
# Claude 06/11/2026: W9b RTL runs on the final r17 binary: scene-0103 co-sim (207 jobs) and 0.1 s packet replay subset (2,513 jobs).
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/tb/integ
R=../../eval_nuscenes/w9b
O=vl_claude_r17_a8_apos
for spec in cosim_0103:207 replay_rtl_subset:2513; do
  f=${spec%:*}; n=${spec#*:}
  ( echo "COMMAND: ./obj_2/Vtb_m_tsmx_top +FILE=$R/$f.mem +LIMIT=$n +ALLOW_INACTIVE start $(date)" > $O/w9b_$f.txt
    stdbuf -oL ./obj_2/Vtb_m_tsmx_top +FILE=$R/$f.mem +LIMIT=$n +ALLOW_INACTIVE >> $O/w9b_$f.txt 2>&1
    echo "rc=$? end $(date)" >> $O/w9b_$f.txt; echo done > $O/w9b_$f.done ) &
done
wait
