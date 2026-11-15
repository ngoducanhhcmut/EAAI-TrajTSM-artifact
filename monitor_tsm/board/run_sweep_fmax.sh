#!/bin/bash
# Claude 06/11/2026: TSM-X (P=G=2) Fmax sweep on ZCU106. 166.7 MHz routed with WNS -1.056 ns => estimate
# Fmax ~141.7 MHz. PL0 = IOPLL(3000 MHz)/N, so candidates are 150 (N=20), 142.857 (21), 136.364 (22), 130.435 (23).
# Order: 142.857 first; pass -> try 150; fail -> 136.364, then 130.435. One Vivado at a time (RAM);
# waits for the BEV F1 image synth to finish first.
B=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board
BEVDONE=/c/Users/TransformerDA/Downloads/vla_new_arch/BEV/streampetr_hw/build/vivado/block_image_f1/synth.done
cd $B
until [ -f $BEVDONE ]; do sleep 300; done
sleep 60
build() {  # $1 = MHz string; returns 0 iff bitstream with WNS>=0, WHS>=0
  local f=$1 L=log_$1
  mkdir -p $L
  for try in 1 2 3; do
    TSMX_MHZ=$f /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log $L/build.log -source build_tsmx_zcu106.tcl > $L/build.console.txt 2>&1
    rc=$?
    [ -f out_$f/system_wrapper_tsmx.bit ] && break
    grep -q "couldn.t read file\|rt-undefined" $L/build.log || break
    mv $L/build.log $L/build.try$try.log; sleep 20
  done
  echo "rc=$rc tries=$try $(date) $(grep -h '###RESULT\|###FREQ' $L/build.log | tr '\n' ' ')" > $L/build.done
  echo "$f $(cat $L/build.done)" >> sweep.log
  [ -f out_$f/system_wrapper_tsmx.bit ]
}
echo "sweep start $(date)" >> sweep.log
if build 142.857143; then
  if build 150; then best=150; else best=142.857143; fi
else
  if build 136.363636; then best=136.363636
  elif build 130.434783; then best=130.434783
  else best=100; fi
fi
echo "BEST=$best $(date)" >> sweep.log
echo "BEST=$best" > sweep.done
