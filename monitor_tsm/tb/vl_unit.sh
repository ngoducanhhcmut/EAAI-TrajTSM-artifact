#!/bin/bash
# Claude: independent Verilator lint + simulation of one TSM-X unit block. usage: vl_unit.sh <blk> [extra rtl files]
source ~/oss-cad-suite/environment >/dev/null 2>&1
R=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
b=$1; shift
cd $R/tb/unit/$b
echo "== LINT $b"
verilator --lint-only -Wall --top-module m_tsmx_$b $R/rtl/$b/m_tsmx_$b.sv "$@" 2>&1 | grep -E "%(Warning|Error)" | head -20
echo "lint_lines=$(verilator --lint-only -Wall --top-module m_tsmx_$b $R/rtl/$b/m_tsmx_$b.sv "$@" 2>&1 | grep -cE '%(Warning|Error)')"
echo "== SIM $b"
rm -rf /tmp/vl_$b; verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --assert -j 4 --top-module tb_m_tsmx_$b -Mdir /tmp/vl_$b \
  $R/rtl/$b/m_tsmx_$b.sv "$@" tb_m_tsmx_$b.sv > /tmp/vl_$b.compile.log 2>&1 || { tail -20 /tmp/vl_$b.compile.log; exit 1; }
/tmp/vl_$b/Vtb_m_tsmx_$b 2>&1 | tail -6
