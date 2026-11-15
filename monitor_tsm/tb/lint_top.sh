#!/bin/bash
# Claude 30/10: Verilator lint of the full top filelist; prints engine/health/io findings.
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
F=$(grep -v '^//' rtl/filelist_top.f | grep -v '^$' | sed 's#^#rtl/#' | tr '\n' ' ')
verilator --lint-only -Wall -Wno-WIDTHCONCAT --top-module m_tsmx_top $F > /tmp/lint_top.log 2>&1
echo "errors=$(grep -c '%Error' /tmp/lint_top.log) warnings=$(grep -c '%Warning' /tmp/lint_top.log)"
grep -E '%Error' /tmp/lint_top.log | head -5 | cut -c1-220
grep -E '%Warning' /tmp/lint_top.log | grep -E 'engine|health|io\.sv' | head -10 | cut -c1-220
