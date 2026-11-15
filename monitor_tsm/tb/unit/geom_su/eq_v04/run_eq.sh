#!/bin/bash
source ~/oss-cad-suite/environment >/dev/null 2>&1
R=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
cd $R/tb/unit/geom_su/eq_v04
echo "== LINT v0.4"
verilator --lint-only -Wall --top-module m_tsmx_geom_su $R/rtl/geom/m_tsmx_geom_su.sv 2>&1 | grep -E "%(Warning|Error)" | head -20
rm -rf /tmp/vl_su_eq; verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O3 -j 2 --top-module tb_eq -Mdir /tmp/vl_su_eq \
  ref_v03.sv $R/rtl/geom/m_tsmx_geom_su.sv tb_eq.sv > /tmp/vl_su_eq.compile.log 2>&1 || { tail -20 /tmp/vl_su_eq.compile.log; exit 1; }
/tmp/vl_su_eq/Vtb_eq +N=${1:-2000000} 2>&1 | tail -8
