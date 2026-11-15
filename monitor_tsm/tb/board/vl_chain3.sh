#!/bin/bash
# Claude 10/11/2026: timing-chain measurement, short form (3 jobs = 200 ms of 1 us time base), binary obj_chain2.
#  B3 ACK at the next job (100 ms after the command, reference-bench executor)  -> 40 ms timeout detection
#  C3 executor holds ACK from 1 ms after command delivery                      -> commit at apply
#  D3 as C3 but the executor stalls TX for 50 ms after each response          -> timeout while command frame stalled
#  E  3 extra copies of the job-0 frame back-to-back during the job-0 decision -> ingress staging/backpressure
#  E0 same job without contention (reference latency)
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
B=$H/tb/board; I=$H/tb/integ; L=$B/vl_chain3; mkdir -p $L
cd $I
X=$B/obj_chain2/Vtb_tsmx_chain
F=reg300_j133_142.mem
run() { n=$1; shift; s=$(date +%s); stdbuf -oL $X +ALLOW_INACTIVE "$@" > $L/$n.txt 2>&1; echo "$n rc=$? s=$(( $(date +%s)-s ))" >> $L/summary.txt; }
run B3_tick_ack_next +LIMIT=3 +FILE=$F +TICK +SOFT &
run C3_tick_ackhold +LIMIT=3 +FILE=$F +TICK +EXEC_ACK +ACK_HOLD +ACKDLY=1000 +SOFT &
run D3_tick_ackhold_stall50ms +LIMIT=3 +FILE=$F +TICK +EXEC_ACK +ACK_HOLD +ACKDLY=1000 +TXSTALL=5000000 +SOFT &
( run E_contend +LIMIT=1 +FILE=smoke.mem +CONTEND=3 +SOFT; run E0_nocontend +LIMIT=1 +FILE=smoke.mem ) &
wait
echo DONE >> $L/summary.txt
