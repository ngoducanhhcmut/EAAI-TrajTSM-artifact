#!/bin/bash
# Claude 30/10: independent Verilator run of the I1 integration suite (README commands)
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1
T=tsmx_hw/tb/integ; L=$T/vl_claude; mkdir -p $L
python3 -B $T/check.py > $L/check.txt 2>&1; echo "check rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --tag full > $L/full2.txt 2>&1; echo "full2 rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 8 --file worst.mem --limit 1 --allow-inactive --worst --tag worst > $L/worst8.txt 2>&1; echo "worst8 rc=$?" >> $L/summary.txt
python3 -B $T/run_control.py --tool verilator --lanes 8 > $L/control8.txt 2>&1; echo "control8 rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 8 --limit 128 --allow-inactive --tag system > $L/system8.txt 2>&1; echo "system8 rc=$?" >> $L/summary.txt
echo DONE >> $L/summary.txt
