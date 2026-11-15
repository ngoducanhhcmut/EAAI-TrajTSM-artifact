#!/bin/bash
# Claude 10/11/2026: VCU118 joint build, DDR4 062 variant (MT40A256M16LY-062E), up to 25 BD-flake retries. Retries only the early BD-creation flake.
export TEMP='C:\Users\TransformerDA\AppData\Local\Temp' TMP='C:\Users\TransformerDA\AppData\Local\Temp'; unset TMPDIR
V=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/vcu118; cd $V; export VCU118_DDR=062
L=$V/build_joint062.status; echo "start $(date) DDR=${VCU118_DDR:-083}" > $L
for i in $(seq 1 25); do
  /c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log build_joint062.log -source build_vcu118_joint.tcl > build_joint062.console.txt 2>&1
  rc=$?; sleep 20
  echo "try $i rc=$rc $(date) $(grep -h '###RESULT\|###BIT\|###ERROR' build_joint062.log | tr '\n' ' ')" >> $L
  grep -q "###ADDR" build_joint062.log && break
done
echo "DONE rc=$rc $(date)" >> $L
