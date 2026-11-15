#!/bin/bash
# Claude 10/11/2026: timing-chain measurement on the board top (PARA_DIRECT=0, P=G=2), RTL unchanged.
#  A: reference bench timing (coarse 100 ms time, ACK at next job)          -> baseline host/decision/delivery cycles
#  B: 1 us time base, ACK at next job (100 ms after command)                  -> 40 ms ACK timeout detection latency
#  C: 1 us time base, executor ACK 1 ms after max(delivery, apply)            -> ACK commit latency
#  D: 1 us time base, executor stalled 50 ms after each response (TX ready 0) -> timeout/brake while command frame stalled
#  E: ingress contention: 3 extra frames back-to-back during job 0 decision   -> staging backpressure, decision unchanged
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
B=$H/tb/board; I=$H/tb/integ; L=$B/vl_chain; mkdir -p $L
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
X=$B/obj_chain/Vtb_tsmx_chain
start=$(date +%s)
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_tsmx_chain -GLANES=2 -I$I -Mdir $B/obj_chain $SRC $B/tb_tsmx_chain.sv > $L/compile.log 2>&1
echo "compile rc=$? s=$(( $(date +%s)-start ))" > $L/summary.txt
[ -x $X ] || { echo COMPILE_FAIL >> $L/summary.txt; exit 1; }
F=reg300_j133_142.mem
run() { n=$1; shift; s=$(date +%s); $X +LIMIT=10 +FILE=$F +ALLOW_INACTIVE "$@" > $L/$n.txt 2>&1; echo "$n rc=$? s=$(( $(date +%s)-s ))" >> $L/summary.txt; }
run A_ref
run B_tick_ack_next +TICK +SOFT &
run C_tick_exec_ack +TICK +EXEC_ACK +ACKDLY=1000 +SOFT &
run D_tick_exec_stall50ms +TICK +EXEC_ACK +ACKDLY=1000 +TXSTALL=5000000 +SOFT &
wait
s=$(date +%s); $X +LIMIT=1 +FILE=smoke.mem +ALLOW_INACTIVE +CONTEND=3 +SOFT > $L/E_contend.txt 2>&1; echo "E_contend rc=$? s=$(( $(date +%s)-s ))" >> $L/summary.txt
s=$(date +%s); $X +LIMIT=1 +FILE=smoke.mem +ALLOW_INACTIVE > $L/E_nocontend.txt 2>&1; echo "E_nocontend rc=$? s=$(( $(date +%s)-s ))" >> $L/summary.txt
echo DONE >> $L/summary.txt
