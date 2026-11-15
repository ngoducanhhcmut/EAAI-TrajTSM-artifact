#!/bin/bash
# Claude 30/10: OOC synth per block; retries Vivado's transient "couldn't read file" start failures.
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/synth
for t in "$@"; do
  rm -f $t/util.rpt $t/util_hier.rpt $t/timing.rpt $t.done
  for try in 1 2 3; do
    /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log $t.log -source ooc_$t.tcl > $t.console.txt 2>&1
    rc=$?
    if [ -f $t/util.rpt ]; then break; fi
    grep -q "couldn't read file\|rt-undefined" $t.log || break
    mv $t.log $t.try$try.log; sleep 20
  done
  echo "rc=$rc tries=$try" > $t.done
done
