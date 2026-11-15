#!/bin/sh
# Build SoC day du (scripts/build_board_v2d.tcl), thu lai toi da 3 lan neu Vivado loi nap IP Integrator
# (loi moi truong chap chon: "couldn't read file .../scripts/ipintegrator/*.tcl", "Failed to load feature").
cd "$(dirname "$0")/.."
L=reports/board_fix_validation/build_full.log
for n in 1 2 3; do
  echo "lan $n bat dau $(date +%H:%M:%S)"
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -source scripts/build_board_v2d.tcl -log $L -journal reports/board_fix_validation/build_full.jou > reports/board_fix_validation/build_full.stdout 2>&1
  rc=$?
  if grep -qE "Failed to load feature 'ipintegrator'|Error in initialization of Rule object|Error sourcing TCL file: couldn't read file" $L; then
    echo "lan $n: loi moi truong IPI, thu lai"; sleep 10; continue
  fi
  echo "lan $n: exit=$rc $(date +%H:%M:%S)"; break
done
grep -E "^###|ERROR" $L | tail -20
