#!/bin/bash
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/proof/watchdog
source ~/oss-cad-suite/environment
sby -f wd_cover.sby > sby_cover.log 2>&1; echo "cover rc=$?" > checks.done
sby -f wd_ctl.sby > sby_ctl.log 2>&1; echo "ctl rc=$?" >> checks.done
