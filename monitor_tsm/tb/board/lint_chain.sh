#!/bin/bash
source ~/oss-cad-suite/environment >/dev/null 2>&1
H=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
cd $H/tb/integ
SRC=$(grep -v '^//' $H/rtl/filelist_top.f | grep . | sed "s#^#$H/rtl/#")
verilator --lint-only --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_tsmx_chain -GLANES=2 -I$H/tb/integ $SRC $H/tb/board/tb_tsmx_chain.sv 2>&1 | grep -E "%Error" | head -20
echo lint_done
