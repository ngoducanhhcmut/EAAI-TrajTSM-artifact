#!/usr/bin/env bash
SIM=/mnt/c/Users/TransformerDA/Downloads/HMAO/sim

cd "$SIM/obj_dir"
echo "[sim] starting binary..." >&2

# Run with unbuffered output and direct capture
stdbuf -oL -eL timeout 120 ./Vtb_hmao_soc > "$SIM/sim_output.log" 2>&1
EC=$?

echo "[sim] exit code: $EC" >&2
echo "=== sim_output.log ==="
cat "$SIM/sim_output.log"

echo ""
echo "=== VCD size ==="
ls -lh "$SIM/obj_dir/hmao_soc_tb.vcd" 2>/dev/null || echo "No VCD"

echo ""
echo "=== First line of VCD (to see sim time reached) ==="
head -5 "$SIM/obj_dir/hmao_soc_tb.vcd" 2>/dev/null

echo ""
echo "=== Last lines of VCD (max sim time) ==="
tail -5 "$SIM/obj_dir/hmao_soc_tb.vcd" 2>/dev/null
