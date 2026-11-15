#!/bin/bash
# Claude 10/11/2026: implementation-only retries (spurious "couldn't read file ... No error" in IP regeneration).
export TEMP='C:\Users\TransformerDA\AppData\Local\Temp' TMP='C:\Users\TransformerDA\AppData\Local\Temp'; unset TMPDIR
V=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/vcu118; cd $V
L=$V/impl_joint.status; echo "start $(date)" > $L
for i in $(seq 1 8); do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log impl_joint.log -source impl_only.tcl > impl_joint.console.txt 2>&1
  echo "try $i $(date) $(grep -h '###RESULT\|###BIT\|###ERROR' impl_joint.log | tr '\n' ' ')" >> $L
  grep -q "###RESULT" impl_joint.log && break
  grep -rqs "couldn't read file\|Failed to load feature\|Error in initialization" impl_joint.log prj_joint/vcu118_joint.runs/impl_1/runme.log || break
  sleep 30
done
echo "DONE $(date)" >> $L
