#!/bin/bash
# Claude 03/11: synth r12 (A8 a in [-8,+2]) after r17 PASS; wait for the BEV block synth to free RAM first.
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/synth
until [ -f ../../../BEV/streampetr_hw/build/vivado/block_query/synth.done ]; do sleep 120; done
for try in 1 2 3; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log synth_r12.log -source ooc_m_tsmx_top_p2.tcl > synth_r12.console.txt 2>&1
  [ -f m_tsmx_top_p2/utilization.rpt ] || ls m_tsmx_top_p2/*util* >/dev/null 2>&1 && break
  grep -q "couldn't read file\|rt-undefined" synth_r12.log || break
  mv synth_r12.log synth_r12.try$try.log; sleep 20
done
rm -rf m_tsmx_top_p2_r12_a8; cp -r m_tsmx_top_p2 m_tsmx_top_p2_r12_a8
echo "done tries=$try $(date)" > synth_r12.done
