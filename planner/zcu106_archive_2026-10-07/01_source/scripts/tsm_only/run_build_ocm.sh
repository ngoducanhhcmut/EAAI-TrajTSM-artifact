#!/bin/sh
# Chay build_tsm_ocm.tcl, thu lai toi da 3 lan neu Vivado loi nap Block Design (loi moi truong, chap chon).
cd "$(dirname "$0")/.."
for n in 1 2 3; do
  rm -rf hw_tsm_only/prj_ocm
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -source hw_tsm_only/build_tsm_ocm.tcl -log hw_tsm_only/build_ocm.log > hw_tsm_only/build_ocm.stdout 2>&1
  rc=$?
  if grep -qE "Failed to load feature 'ipintegrator'|Error in initialization of Rule object|Error sourcing TCL file: couldn't read file" hw_tsm_only/build_ocm.log; then
    echo "lan $n: loi moi truong IPI, thu lai"; sleep 5; continue
  fi
  echo "lan $n: exit=$rc $(date +%H:%M:%S)"; break
done
grep -E "^###|ERROR" hw_tsm_only/build_ocm.log | tail -25
