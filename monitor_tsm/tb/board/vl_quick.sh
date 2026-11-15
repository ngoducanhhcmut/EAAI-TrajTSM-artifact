#!/bin/bash
# Claude 04/11: compile the stream bench and run a short smoke (LIMIT jobs of FILE).
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw; B=$H/tb/board; I=$H/tb/integ
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
flock /tmp/bev_vl_compile.lock verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_tsmx_stream -GLANES=2 -I$I -Mdir $B/obj_stream $SRC $B/tb_tsmx_stream.sv > $B/quick_compile.log 2>&1 || { echo COMPILE_FAIL; tail -20 $B/quick_compile.log; exit 1; }
$B/obj_stream/Vtb_tsmx_stream +LIMIT=${1:-5} +FILE=${2:-vectors.mem} +ALLOW_INACTIVE > $B/quick.txt 2>&1; echo "rc=$?"
grep -v "^ASSERT" $B/quick.txt | tail -25
