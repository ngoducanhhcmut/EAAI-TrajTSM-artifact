#!/bin/bash
# Claude 04/11: ZCU106 TSM-X bitstream build (retry on the transient Vivado common.tcl read error).
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board; export TSMX_MHZ=187.5; mkdir -p log187
for try in 1 2 3; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log log187/build.log -source build_tsmx_zcu106.tcl > log187/build.console.txt 2>&1
  rc=$?
  [ -f out_187.5/system_wrapper_tsmx.bit ] && break
  grep -q "couldn.t read file\|rt-undefined" log187/build.log || break
  mv log187/build.log log187/build.try$try.log; sleep 20
done
echo "rc=$rc tries=$try $(date)" > log187/build.done
