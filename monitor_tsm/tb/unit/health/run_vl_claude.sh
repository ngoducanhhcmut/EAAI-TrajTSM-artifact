#!/bin/bash
# Claude 30/10: lint + Verilator unit run for health v0.2.
source ~/oss-cad-suite/environment >/dev/null 2>&1
R=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
cd $R
F=$(grep -v '^//' rtl/filelist_R11.f | sed 's#^#rtl/#' | tr '\n' ' ')
echo "lint=$(verilator --lint-only -Wall --top-module m_tsmx_health_lane $F 2>&1 | grep -cE '%(Warning|Error)')"
verilator --lint-only -Wall --top-module m_tsmx_health_lane $F 2>&1 | grep -E '%(Warning|Error)' | grep -E 'health' | head -8 | cut -c1-200
cd tb/unit/health; rm -rf obj_dir; python3 -B run_verilator.py; echo "rc=$?"
grep -E "PASS|FAIL|Fatal|ASSERT" verilator_simulation.log | tail -5 | cut -c1-200
