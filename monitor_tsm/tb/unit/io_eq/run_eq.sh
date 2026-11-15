#!/bin/bash
# Claude 30/10: io v0.2 vs v0.1 cycle equivalence (Verilator).
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
echo "lint=$(verilator --lint-only -Wall --top-module m_tsmx_io rtl/top/m_tsmx_io.sv 2>&1 | grep -cE '%(Warning|Error)')"
verilator --lint-only -Wall --top-module m_tsmx_io rtl/top/m_tsmx_io.sv 2>&1 | grep -E '%(Warning|Error)' | head -5 | cut -c1-200
rm -rf /tmp/vl_ioeq
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -j 4 --top-module tb_io_eq -Mdir /tmp/vl_ioeq rtl/top/m_tsmx_io.sv tb/unit/io_eq/m_tsmx_io_old.sv tb/unit/io_eq/tb_io_eq.sv > /tmp/vl_ioeq.log 2>&1 || { tail -20 /tmp/vl_ioeq.log; exit 1; }
/tmp/vl_ioeq/Vtb_io_eq | grep -E 'IO_EQ|MISMATCH' | head
