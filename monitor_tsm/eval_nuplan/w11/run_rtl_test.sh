#!/bin/bash
# Claude 07/11/2026 (W11): Verilator runs of the B4 (mrmgen) and B3 (geom) unit benches on every distinct nuPlan call.
# Each shard = original unit vector set + <=3000 nuPlan calls; the TB asserts the full response against the golden value.
# usage (WSL): bash run_rtl.sh [jobs=4]
source ~/oss-cad-suite/environment >/dev/null 2>&1
R=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw
W=$R/eval_nuplan/w11
J=${1:-4}
run_one() {
  d=$1; unit=$(basename $(dirname $d)); k=$(basename $d)
  case $unit in
    mrmgen) src="$R/rtl/arith/m_tsmx_arith_div.sv $R/rtl/arith/m_tsmx_arith.sv $R/rtl/mrmgen/m_tsmx_mrmgen.sv";;
    geom)   src="$R/rtl/arith/m_tsmx_arith_div.sv $R/rtl/arith/m_tsmx_arith.sv $R/rtl/geom/m_tsmx_geom_su.sv $R/rtl/geom/m_tsmx_geom.sv";;
  esac
  cd $d
  o=/tmp/w11_${unit}_$k
  rm -rf $o
  nice -n 10 verilator --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style -j 2 --top-module tb_m_tsmx_$unit -I. -Mdir $o \
    $src tb_m_tsmx_$unit.sv > compile.log 2>&1 || { echo "COMPILE_FAIL rc=$?" > run.log; echo 1 > run.done; return; }
  s=$(date +%s)
  nice -n 10 $o/Vtb_m_tsmx_$unit > run.log 2>&1
  echo "$? $(( $(date +%s)-s ))" > run.done
  rm -rf $o
}
export -f run_one; export R
ls -d $W/rtl/mrmgen/shard_0 | xargs -P $J -I{} bash -c 'run_one {}'
echo "rc=0 $(date)" > $W/rtl_runs_test.done
