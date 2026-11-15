#!/bin/bash
# Claude 04/11 (r2: with CTRL/BIST bring-up, 4 runs in parallel): board-equivalent (PARA_DIRECT=0, rx stream) regression of TSM-X at P=G=2.
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
B=$H/tb/board; I=$H/tb/integ; L=$B/vl_stream_r2; mkdir -p $L
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
start=$(date +%s)
flock /tmp/bev_vl_compile.lock verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_tsmx_stream -GLANES=2 -I$I -Mdir $B/obj_stream $SRC $B/tb_tsmx_stream.sv > $L/compile.log 2>&1
echo "compile rc=$? s=$(( $(date +%s)-start ))" >> $L/summary.txt
X=$B/obj_stream/Vtb_tsmx_stream
( $X +LIMIT=300 +FILE=vectors.mem +ALLOW_INACTIVE > $L/reg300.txt 2>&1; echo "reg300 rc=$?" >> $L/summary.txt ) &
( $X +LIMIT=1 +FILE=worst.mem +ALLOW_INACTIVE +WORST +WORST_ROWS=77 > $L/worst2.txt 2>&1; echo "worst2 rc=$?" >> $L/summary.txt ) &
( $X +LIMIT=360 +FILE=apos.mem +ALLOW_INACTIVE > $L/apos.txt 2>&1; echo "apos rc=$?" >> $L/summary.txt ) &
( $X +LIMIT=1 +FILE=worst_apos.mem +ALLOW_INACTIVE +WORST +WORST_ROWS=93 > $L/worst_apos.txt 2>&1; echo "worst_apos rc=$?" >> $L/summary.txt ) &
wait
echo DONE >> $L/summary.txt
