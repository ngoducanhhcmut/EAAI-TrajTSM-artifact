#!/bin/bash
# Claude 04/11: ZCU106 board attempt, OOC impl at 100 MHz with congestion directives.
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/synth
for try in 1 2 3; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log impl_100.log -source impl_m_tsmx_top_p2_100.tcl > impl_100.console.txt 2>&1
  [ -f m_tsmx_top_p2_impl_100/timing.rpt ] && break
  grep -q "couldn't read file\|rt-undefined" impl_100.log || break
  mv impl_100.log impl_100.try$try.log; sleep 20
done
echo "done tries=$try $(date)" > impl_100.done
