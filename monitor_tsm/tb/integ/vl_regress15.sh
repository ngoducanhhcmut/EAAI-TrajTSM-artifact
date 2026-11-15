#!/bin/bash
# Claude 30/10: functional regression of final RTL (first 300 jobs at P=G=2) + control/timer at 8.
# 02/11: r17 = r11 + A8 (acceleration ODD [-8,+2] m/s^2: ingress/splice/arith op5/mrmgen/geom row/engine live-ego).
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1
T=tsmx_hw/tb/integ; L=$T/vl_claude_r17_a8_apos; mkdir -p $L
flock /tmp/bev_vl_compile.lock -c true; python3 -B $T/check.py > $L/check.txt 2>&1; echo "check rc=$?" >> $L/summary.txt
python3 -B $T/run_control.py --tool verilator --lanes 8 > $L/control8.txt 2>&1; echo "control8 rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --limit 300 --tag reg300 > $L/reg300.txt 2>&1; echo "reg300 rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --file worst.mem --limit 1 --allow-inactive --worst --tag worst2 > $L/worst2.txt 2>&1; echo "worst2 rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --file apos.mem --allow-inactive --tag apos2 > $L/apos.txt 2>&1; echo "apos rc=$?" >> $L/summary.txt
python3 -B $T/run.py --tool verilator --lanes 2 --file worst_apos.mem --limit 1 --allow-inactive --worst --tag worsta2 > $L/worst_apos.txt 2>&1; echo "worst_apos rc=$?" >> $L/summary.txt
echo DONE_REG >> $L/summary.txt
