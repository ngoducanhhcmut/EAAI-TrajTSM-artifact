#!/bin/bash
# Claude 10/11/2026: user: "nếu khó thì an toàn hơn 125 cũng đc". Run 125 MHz only if 130.434783 gave no bitstream.
B=/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/board
while [ ! -f $B/fmax_130.done ]; do sleep 120; done
grep -q "FMAX_BEST=none" $B/fmax_130.done && exec $B/fmax_125_retry.sh
