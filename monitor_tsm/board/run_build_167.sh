#!/bin/bash
# Claude 05/11: 187.5 MHz unroutable (24,081 partial-conflict nets, WNS -6.5 ns); retry at 166.7 MHz. (orig 04/11): ZCU106 TSM-X bitstream build (retry on the transient Vivado common.tcl read error).
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board; export TSMX_MHZ=166.666666; mkdir -p log167
for try in 1 2 3; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log log167/build.log -source build_tsmx_zcu106.tcl > log167/build.console.txt 2>&1
  rc=$?
  [ -f out_166.666666/system_wrapper_tsmx.bit ] && break
  grep -q "couldn.t read file\|rt-undefined" log167/build.log || break
  mv log167/build.log log167/build.try$try.log; sleep 20
done
echo "rc=$rc tries=$try $(date)" > log167/build.done
