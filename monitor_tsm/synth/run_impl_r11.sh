#!/bin/bash
# Claude 02/11: run the r11 OOC implementation once regression r15 has passed (all four steps rc=0).
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/synth
S=../tb/integ/vl_claude_r15_geomsu06/summary.txt
until grep -q DONE_REG $S 2>/dev/null; do sleep 120; done
if [ "$(grep -c 'rc=0' $S)" != "4" ]; then echo "r15 not all PASS, implementation skipped" > impl_r11.done; exit 1; fi
for try in 1 2 3; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log impl_r11.log -source impl_m_tsmx_top_p2.tcl > impl_r11.console.txt 2>&1
  [ -f m_tsmx_top_p2_impl/timing.rpt ] && break
  grep -q "couldn't read file\|rt-undefined" impl_r11.log || break
  mv impl_r11.log impl_r11.try$try.log; sleep 20
done
echo "done rc=$? tries=$try" > impl_r11.done
