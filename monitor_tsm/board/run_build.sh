#!/bin/bash
# Claude 04/11: ZCU106 TSM-X bitstream build (retry on the transient Vivado common.tcl read error).
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board
for try in 1 2 3; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log build.log -source build_tsmx_zcu106.tcl > build.console.txt 2>&1
  rc=$?
  [ -f out/system_wrapper_tsmx.bit ] && break
  grep -q "couldn't read file\|rt-undefined" build.log || break
  mv build.log build.try$try.log; sleep 20
done
echo "rc=$rc tries=$try $(date)" > build.done
