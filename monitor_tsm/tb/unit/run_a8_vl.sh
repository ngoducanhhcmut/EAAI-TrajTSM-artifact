#!/bin/bash
# Claude 02/11 A8: Verilator runs of the arith and geom unit benches (Icarus rejects an enum ?: assignment in arith).
source ~/oss-cad-suite/environment >/dev/null 2>&1
R=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
cd $R/tb/unit/arith
rm -rf /tmp/vl_a8_arith; verilator --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style -j 2 --top-module tb_m_tsmx_arith -I. -Mdir /tmp/vl_a8_arith \
  $R/rtl/arith/m_tsmx_arith_div.sv $R/rtl/arith/m_tsmx_arith.sv tb_m_tsmx_arith.sv > run_A8_vl.compile.log 2>&1 && /tmp/vl_a8_arith/Vtb_m_tsmx_arith > run_A8_vl.log 2>&1
echo "arith rc=$?" > $R/tb/unit/run_a8_vl.done
exit 0
cd $R/tb/unit/geom
rm -rf /tmp/vl_a8_geom; verilator --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style -j 2 --top-module tb_m_tsmx_geom -I. -Mdir /tmp/vl_a8_geom \
  $R/rtl/arith/m_tsmx_arith_div.sv $R/rtl/arith/m_tsmx_arith.sv $R/rtl/geom/m_tsmx_geom_su.sv $R/rtl/geom/m_tsmx_geom.sv tb_m_tsmx_geom.sv > run_A8_vl.compile.log 2>&1 && /tmp/vl_a8_geom/Vtb_m_tsmx_geom > run_A8_vl.log 2>&1
echo "geom rc=$?" >> $R/tb/unit/run_a8_vl.done
