#!/bin/bash
# Claude 30/10: worst-case timing at P=G=8 on the current RTL only.
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1
T=tsmx_hw/tb/integ; L=$T/vl_claude; mkdir -p $L
python3 -B $T/run.py --tool verilator --lanes 2 --file worst.mem --limit 1 --allow-inactive --worst --tag worst2 > $L/worst2.txt 2>&1; echo "worst2 rc=$?" >> $L/summary.txt
echo DONE2 >> $L/summary.txt
