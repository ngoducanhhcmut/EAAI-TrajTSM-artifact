#!/bin/bash
# Claude 07/11/2026 (W11): Git-bash pipeline, launched detached. Waits for both nuPlan reruns, then
# determinism check -> golden re-derivation + RTL vectors -> Verilator unit benches (WSL) -> checker.
W=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuplan/w11
L=$W/pipeline.log
cd /c/Users/TransformerDA/Downloads/vla_new_arch
while [ ! -f $W/../logs/w11a/done ] || [ ! -f $W/../logs/w11b/done ]; do sleep 600; done
echo "nuplan done $(date)" > $L
python $W/check_determinism.py >> $L 2>&1; echo "determinism rc=$?" >> $L
py -3.13 -B $W/make_rtl_vectors.py >> $L 2>&1; echo "vectors rc=$?" >> $L
MSYS_NO_PATHCONV=1 wsl.exe -e bash /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuplan/w11/run_rtl.sh 4 >> $L 2>&1
python $W/check_rtl.py >> $L 2>&1; echo "check rc=$?" >> $L
echo done > $W/pipeline.done
