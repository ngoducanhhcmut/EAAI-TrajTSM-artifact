#!/bin/bash
# Claude 10/11/2026: full VCU118 joint build (licence active). Retries only the early BD-creation flake.
export TEMP='C:\Users\TransformerDA\AppData\Local\Temp' TMP='C:\Users\TransformerDA\AppData\Local\Temp'; unset TMPDIR
V=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/vcu118; cd $V
L=$V/build_joint.status; echo "start $(date) DDR=${VCU118_DDR:-083}" > $L
for i in 1 2 3 4 5 6; do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log build_joint.log -source build_vcu118_joint.tcl > build_joint.console.txt 2>&1
  rc=$?
  echo "try $i rc=$rc $(date) $(grep -h '###RESULT\|###BIT\|###ERROR' build_joint.log | tr '\n' ' ')" >> $L
  grep -q "###ADDR" build_joint.log && break
done
echo "DONE rc=$rc $(date)" >> $L
