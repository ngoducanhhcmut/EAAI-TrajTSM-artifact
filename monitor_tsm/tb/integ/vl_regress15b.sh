#!/bin/bash
# 02/11: r17 rerun of the A8 parts after TB fixes (apos limit 360; worst-case row count is a plusarg).
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1
T=tsmx_hw/tb/integ; L=$T/vl_claude_r17_a8_apos
echo "== rerun $(date)" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --file worst.mem --limit 1 --allow-inactive --worst --tag worst2b > $L/worst2b.txt 2>&1; echo "worst2b rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --file apos.mem --limit 360 --allow-inactive --tag apos2b > $L/aposb.txt 2>&1; echo "apos rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --file worst_apos.mem --limit 1 --allow-inactive --worst --worst-rows 93 --tag worsta2b > $L/worst_aposb.txt 2>&1; echo "worst_apos rc=$?" >> $L/summary.txt
echo DONE_REG2 >> $L/summary.txt
