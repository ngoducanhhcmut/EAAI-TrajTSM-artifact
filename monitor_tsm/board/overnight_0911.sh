#!/bin/bash
# Claude 09/11/2026: Git-bash chain, launched detached.
#  1. wait for the two nuPlan token reruns -> W11 pipeline (determinism, golden re-derivation + vectors, RTL unit benches, check)
#  2. Fmax: 136.364 MHz, and 130.435 MHz only if 136.364 fails (one Vivado at a time; same build() as run_sweep_fmax.sh)
R=/c/Users/TransformerDA/Downloads/vla_new_arch
N=$R/journalQ1/tsmx_hw/eval_nuplan; W=$N/w11; B=$R/journalQ1/tsmx_hw/board
L=$B/overnight_0911.log
echo "start $(date)" > $L
until [ -f $N/logs/w11a/tokens_blind_tsmx.done ] && [ -f $N/logs/w11b/tokens_stale_tsmxc.done ]; do sleep 300; done
echo "nuplan reruns done $(date)" >> $L
cd $R
python $W/check_determinism.py > $W/pipeline.log 2>&1; echo "determinism rc=$?" >> $W/pipeline.log
py -3.13 -B $W/make_rtl_vectors.py >> $W/pipeline.log 2>&1; echo "vectors rc=$?" >> $W/pipeline.log
MSYS_NO_PATHCONV=1 wsl.exe -e bash /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuplan/w11/run_rtl.sh 2 >> $W/pipeline.log 2>&1
python $W/check_rtl.py >> $W/pipeline.log 2>&1; echo "check rc=$?" >> $W/pipeline.log
echo done > $W/pipeline.done
echo "w11 pipeline done $(date)" >> $L
cd $B
build() {
  local f=$1 LG=log_$1
  mkdir -p $LG
  TSMX_MHZ=$f /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log $LG/build.log -source build_tsmx_zcu106.tcl > $LG/build.console.txt 2>&1
  echo "rc=$? $(date) $(grep -h '###RESULT\|###FREQ' $LG/build.log | tr '\n' ' ')" > $LG/build.done
  echo "$f $(cat $LG/build.done)" >> sweep.log
  [ -f out_$f/system_wrapper_tsmx.bit ]
}
if build 136.363636; then best=136.363636; elif build 130.434783; then best=130.434783; else best=none; fi
echo "FMAX_BEST=$best $(date)" >> $L
echo "FMAX_BEST=$best" > $B/overnight_0911.done
