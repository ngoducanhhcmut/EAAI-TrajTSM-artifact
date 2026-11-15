#!/bin/bash
# Claude 05/11/2026: W7r nuScenes jobs through the final RTL (r17 Verilator binary tb/integ/obj_2, P=G=2), no recompile.
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/tb/integ
R=../../eval_nuscenes/rtl
for f in nuscenes nuscenes_va; do
  OUT=$R/vl_r17_$f.txt
  echo "COMMAND: ./obj_2/Vtb_m_tsmx_top +FILE=$R/$f.mem +LIMIT=771 +ALLOW_INACTIVE  start $(date)" > $OUT
  stdbuf -oL ./obj_2/Vtb_m_tsmx_top +FILE=$R/$f.mem +LIMIT=771 +ALLOW_INACTIVE >> $OUT 2>&1
  echo "rc=$? end $(date)" >> $OUT
done
echo done > $R/vl_r17.done
