#!/bin/bash
# Claude 04/11: system bench of tsmx_board_top (shim + TSM-X) with the xsdb register sequence.
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw; B=$H/tb/board; I=$H/tb/integ
cd $I
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
if [ "$3" != "nocompile" ]; then
flock /tmp/bev_vl_compile.lock verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_board_top -Mdir $B/obj_boardtop $SRC $H/board/rtl/tsmx_board_shim.v $H/board/rtl/tsmx_board_top.v $B/tb_board_top.sv > $B/boardtop_compile.log 2>&1 || { echo COMPILE_FAIL; grep -m5 "%Error" $B/boardtop_compile.log; exit 1; }
fi
$B/obj_boardtop/Vtb_board_top +FILE=${1:-vectors.mem} +SEQ=$H/board/vectors/${2:-smoke5}_seq.mem +LIMIT=${4:-5} > $B/boardtop_${2:-smoke5}.txt 2>&1; echo "rc=$?"
grep -E "BOARDSIM|ERR|PASS|Fatal" $B/boardtop_${2:-smoke5}.txt | tail -15
