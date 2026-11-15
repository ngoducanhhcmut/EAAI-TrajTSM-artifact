#!/bin/bash
source ~/oss-cad-suite/environment >/dev/null 2>&1
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1
python3 -B tsmx_hw/tb/integ/run.py --tool verilator --lanes 2 --limit 34 --tag dbg > tsmx_hw/tb/integ/vl_claude/dbg.txt 2>&1; echo "rc=$?" >> tsmx_hw/tb/integ/vl_claude/dbg.txt
