#!/bin/bash
# Claude 10/11/2026: detached Git-bash login shells set TEMP=TMP=/tmp, which Windows Vivado cannot use
# (create_bd_design then fails with spurious "couldn't read file ..."). Restore the Windows temp dir.
export TEMP='C:\Users\TransformerDA\AppData\Local\Temp' TMP='C:\Users\TransformerDA\AppData\Local\Temp'
unset TMPDIR
exec /c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board/fmax_0911b.sh
