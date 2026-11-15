#!/bin/bash
# Claude 30/10: OOC synth then LUT histogram for each block given.
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/synth
for t in "$@"; do
  rm -f $t.done; ./run_one.sh $t
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log hist_$t.log -source lut_hist.tcl -tclargs $t/post_synth.dcp $t/lut_hist.txt > /dev/null 2>&1
  echo hist >> $t.done
done
