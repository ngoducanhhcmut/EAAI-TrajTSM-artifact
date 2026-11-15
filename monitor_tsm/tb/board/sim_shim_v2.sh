#!/bin/bash
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
cd /tmp && rm -rf shimv2 && mkdir shimv2 && cd shimv2
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_shim_v2 $H/board/rtl/tsmx_board_shim_v2.v $H/tb/board/tb_shim_v2.sv -Mdir obj > c.log 2>&1 || { tail -20 c.log; exit 1; }
./obj/Vtb_shim_v2 | tail -15
