#!/bin/bash
# Claude 10/11/2026: ingress contention on a long decision (job 0 of reg300_j133_142: 650,031 cycles).
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
B=$H/tb/board; I=$H/tb/integ; L=$B/vl_chain3; mkdir -p $L
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_tsmx_chain -GLANES=2 -I$I -Mdir $B/obj_chain3 $SRC $B/tb_tsmx_chain.sv > $L/compile3.log 2>&1
echo "compile3 rc=$?" >> $L/summary.txt
X=$B/obj_chain3/Vtb_tsmx_chain
stdbuf -oL $X +ALLOW_INACTIVE +LIMIT=1 +FILE=reg300_j133_142.mem +CONTEND=3 +SOFT > $L/E2_contend_long.txt 2>&1; echo "E2_contend_long rc=$?" >> $L/summary.txt
stdbuf -oL $X +ALLOW_INACTIVE +LIMIT=1 +FILE=reg300_j133_142.mem > $L/E2_nocontend_long.txt 2>&1; echo "E2_nocontend_long rc=$?" >> $L/summary.txt
