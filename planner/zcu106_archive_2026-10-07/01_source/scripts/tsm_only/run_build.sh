#!/bin/sh
# Chay build_tsm_only.tcl, thu lai toi da 3 lan neu Vivado loi nap Block Design (loi moi truong, chap chon).
cd "$(dirname "$0")/.."
for n in 1 2 3; do
  rm -rf hw_tsm_only/prj
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -source hw_tsm_only/build_tsm_only.tcl -log hw_tsm_only/build.log > hw_tsm_only/build.stdout 2>&1
  rc=$?
  if grep -qE "Failed to load feature 'ipintegrator'|Error in initialization of Rule object|Error sourcing TCL file: couldn't read file" hw_tsm_only/build.log; then
    echo "lan $n: loi moi truong IPI, thu lai"; sleep 5; continue
  fi
  echo "lan $n: exit=$rc $(date +%H:%M:%S)"; break
done
grep -E "^###|ERROR" hw_tsm_only/build.log | tail -25
