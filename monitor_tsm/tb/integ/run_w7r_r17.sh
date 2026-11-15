#!/bin/bash
# Claude 06/11/2026: W7r nuScenes RTL replay (771 plans from 300 frames: planner T, human H, unsafe U) on the final
# r17 binary (obj_2, LANES=2), primary and VA files in parallel. Focused replay: +ALLOW_INACTIVE (see eval_nuscenes/rtl/REPORT.md).
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/tb/integ
R=../../eval_nuscenes/rtl
O=vl_claude_r17_a8_apos
for f in nuscenes nuscenes_va; do
  ( echo "COMMAND: ./obj_2/Vtb_m_tsmx_top +FILE=$R/$f.mem +LIMIT=771 +ALLOW_INACTIVE start $(date)" > $O/w7r_$f.txt
    stdbuf -oL ./obj_2/Vtb_m_tsmx_top +FILE=$R/$f.mem +LIMIT=771 +ALLOW_INACTIVE >> $O/w7r_$f.txt 2>&1
    echo "rc=$? end $(date)" >> $O/w7r_$f.txt; echo done > $O/w7r_$f.done ) &
done
wait
