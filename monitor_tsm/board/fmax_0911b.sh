#!/bin/bash
# Claude 09/11/2026 (b): Fmax retry after the stopped overnight chain (RTL unchanged: late-ACK edit reverted).
#  136.364 MHz first (its 17:12 attempt died on a transient Vivado file-read error), 130.435 MHz only if it fails.
B=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board
cd $B; L=$B/fmax_0911b.log; echo "start $(date)" > $L
build() {
  local f=$1 LG=log_$1
  rm -rf $LG out_$f; mkdir -p $LG
  TSMX_MHZ=$f /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log $LG/build.log -source build_tsmx_zcu106.tcl > $LG/build.console.txt 2>&1
  echo "rc=$? $(date) $(grep -h '###RESULT\|###FREQ' $LG/build.log | tr '\n' ' ')" > $LG/build.done
  echo "$f $(cat $LG/build.done)" >> sweep.log; echo "$f $(cat $LG/build.done)" >> $L
  [ -f out_$f/system_wrapper_tsmx.bit ]
}
if build 136.363636; then best=136.363636; elif build 130.434783; then best=130.434783; else best=none; fi
echo "FMAX_BEST=$best $(date)" >> $L; echo "FMAX_BEST=$best" > $B/fmax_0911b.done
