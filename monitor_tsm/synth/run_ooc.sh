#!/bin/bash
cd /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/synth
/c/Vivado/Vivado/2023.2/bin/vivado.bat -mode batch -notrace -nojournal -log ooc.log -source ooc_blocks.tcl > ooc_console.txt 2>&1
echo "rc=$?" > ooc.done
