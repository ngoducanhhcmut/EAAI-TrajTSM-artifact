#!/usr/bin/env bash
HMAO=/mnt/c/Users/TransformerDA/Downloads/HMAO
BINARY=$HMAO/sim/obj_dir/Vtb_hmao_soc

if [ -f "$BINARY" ]; then
    echo "Binary exists: $(ls -la $BINARY)"
    echo "--- Source files newer than binary ---"
    find $HMAO -maxdepth 3 \( -name "*.sv" -o -name "*.v" \) -newer "$BINARY" 2>/dev/null | grep -v obj_dir | sort
    NEWER_COUNT=$(find $HMAO -maxdepth 3 \( -name "*.sv" -o -name "*.v" \) -newer "$BINARY" 2>/dev/null | grep -v obj_dir | wc -l)
    echo "--- $NEWER_COUNT file(s) newer than binary ---"
else
    echo "Binary does NOT exist, rebuild needed"
fi
