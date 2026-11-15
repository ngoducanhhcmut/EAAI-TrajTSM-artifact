#!/bin/bash
# Claude 30/10: rerun worst-case budget at 2 and 4 lanes after the LANES assertion relaxation.
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/tb/integ
bash vl_worst2.sh; bash vl_worst4.sh
echo DONE24 >> vl_claude/summary.txt
