#!/bin/bash
# Claude 10/11/2026: C/D rerun with the ACK-hold executor model (separate binary; B keeps running on obj_chain).
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
B=$H/tb/board; I=$H/tb/integ; L=$B/vl_chain; mkdir -p $L
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
X=$B/obj_chain2/Vtb_tsmx_chain
s=$(date +%s)
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_tsmx_chain -GLANES=2 -I$I -Mdir $B/obj_chain2 $SRC $B/tb_tsmx_chain.sv > $L/compile2.log 2>&1
echo "compile2 rc=$? s=$(( $(date +%s)-s ))" >> $L/summary2.txt
F=reg300_j133_142.mem
run() { n=$1; shift; s=$(date +%s); stdbuf -oL $X +LIMIT=10 +FILE=$F +ALLOW_INACTIVE "$@" > $L/$n.txt 2>&1; echo "$n rc=$? s=$(( $(date +%s)-s ))" >> $L/summary2.txt; }
run C2_tick_ackhold +TICK +EXEC_ACK +ACK_HOLD +ACKDLY=1000 +SOFT &
run D2_tick_ackhold_stall50ms +TICK +EXEC_ACK +ACK_HOLD +ACKDLY=1000 +TXSTALL=5000000 +SOFT &
wait
echo DONE2 >> $L/summary2.txt
