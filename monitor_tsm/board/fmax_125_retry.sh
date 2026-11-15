#!/bin/bash
# Claude 10/11/2026: user chose to fallback 125 MHz if 130.434783 fails. create_bd_design fails
# sporadically on this PC (spurious "couldn't read file"/rule-init errors); retry only that failure.
export TEMP='C:\Users\TransformerDA\AppData\Local\Temp' TMP='C:\Users\TransformerDA\AppData\Local\Temp'; unset TMPDIR
B=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board; cd $B
f=125; L=$B/fmax_125.log; echo "start $(date)" > $L
for i in 1 2 3 4 5 6; do
  sleep 60
  LG=log_$f; rm -rf $LG out_$f prj_$f; mkdir -p $LG
  TSMX_MHZ=$f /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log $LG/build.log -source build_tsmx_zcu106.tcl > $LG/build.console.txt 2>&1
  rc=$?
  echo "try $i rc=$rc $(date) $(grep -h '###RESULT\|###FREQ' $LG/build.log | tr '\n' ' ')" >> $L
  grep -q "create_bd_design' failed" $LG/build.log || break
done
echo "$f try$i rc=$rc $(date) $(grep -h '###RESULT\|###FREQ' $LG/build.log | tr '\n' ' ')" >> sweep.log
if [ -f out_$f/system_wrapper_tsmx.bit ]; then echo "FMAX_BEST=$f" > fmax_125.done; else echo "FMAX_BEST=none" > fmax_125.done; fi
cat fmax_125.done >> $L
