#!/bin/bash
# Claude 05/11/2026: W6 SEU campaign in Verilator (commands from CAMPAIGN.md), queued after the BEV F1 Verilator jobs
# because the 7 GB WSL VM cannot hold two large C++ compiles next to the nuPlan runs.
F1=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/BEV/streampetr_hw/build/codex/F1_image_ram/claude_vl_rest.done
while [ ! -f $F1 ]; do sleep 300; done
source ~/oss-cad-suite/environment >/dev/null 2>&1
mkdir -p /tmp/py3sys && ln -sf /usr/bin/python3 /tmp/py3sys/python3 && export PATH=/tmp/py3sys:$PATH
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1
L=tsmx_hw/fault/claude_verilator.log
echo "start $(date)" > $L
flock /tmp/bev_vl_compile.lock python3 -B tsmx_hw/fault/run_campaign.py --tool verilator --compile-only >> $L 2>&1
echo "compile rc=$? $(date)" >> $L
cd tsmx_hw/fault
./obj_fault/Vtb_fault +FILE=job1.mem +FAULT_ID=0 +FAULT_CYCLE=1 > verilator_deposit_probe.log 2>&1
echo "probe rc=$? $(grep -m1 PROBE verilator_deposit_probe.log)" >> claude_verilator.log
cd ../..
python3 -B tsmx_hw/fault/run_campaign.py --tool verilator --skip-compile --n 1440 --timeout 300 --results results_verilator.jsonl >> $L 2>&1
echo "campaign rc=$? $(date)" >> $L
python3 -B tsmx_hw/fault/classify.py tsmx_hw/fault/results_verilator.jsonl >> $L 2>&1
echo done > tsmx_hw/fault/claude_verilator.done
