#!/bin/bash
# Claude 04/11 (r3: ACK only with the engine idle, as on the board). arg1 = run list: "sub" or "full"
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
B=$H/tb/board; I=$H/tb/integ; L=$B/vl_stream_r3; mkdir -p $L
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
X=$B/obj_stream3/Vtb_tsmx_stream
if [ ! -x $X ] || [ $B/tb_tsmx_stream.sv -nt $X ]; then
  start=$(date +%s)
  flock /tmp/bev_vl_compile.lock verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_tsmx_stream -GLANES=2 -I$I -Mdir $B/obj_stream3 $SRC $B/tb_tsmx_stream.sv > $L/compile.log 2>&1
  echo "compile rc=$? s=$(( $(date +%s)-start ))" >> $L/summary.txt
fi
if [ "$1" = sub ]; then
  $X +LIMIT=10 +FILE=reg300_j133_142.mem +ALLOW_INACTIVE > $L/sub133.txt 2>&1; echo "sub133 rc=$?" >> $L/summary.txt
else
  $X +LIMIT=261 +FILE=reg300_board.mem +ALLOW_INACTIVE > $L/reg300_board.txt 2>&1; echo "reg300_board rc=$?" >> $L/summary.txt
fi
echo DONE_$1 >> $L/summary.txt
