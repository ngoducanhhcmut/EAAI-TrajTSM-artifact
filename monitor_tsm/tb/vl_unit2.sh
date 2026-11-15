#!/bin/bash
# Claude: Verilator lint + sim for a unit TB whose name differs from the module dir. usage: vl_unit2.sh <tbdir> <top_rtl_module> <rtl files...>
source ~/oss-cad-suite/environment >/dev/null 2>&1
R=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
d=$1; m=$2; shift 2
cd $R/tb/unit/$d
echo "lint_lines=$(verilator --lint-only -Wall --top-module $m "$@" 2>&1 | grep -cE '%(Warning|Error)')"
verilator --lint-only -Wall --top-module $m "$@" 2>&1 | grep -E '%(Warning|Error)' | head -8 | cut -c1-200
rm -rf /tmp/vl_$d; verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --assert -j 4 --top-module tb_$m -Mdir /tmp/vl_$d "$@" tb_$m.sv > /tmp/vl_$d.compile.log 2>&1 || { tail -20 /tmp/vl_$d.compile.log; exit 1; }
/tmp/vl_$d/Vtb_$m 2>&1 | tail -8
