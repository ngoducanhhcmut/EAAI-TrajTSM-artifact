#!/usr/bin/env bash
set -e

SIM=/mnt/c/Users/TransformerDA/Downloads/HMAO/sim

echo "=== Running HMAO simulation ==="
cd "$SIM/obj_dir"

# Run with 120-second timeout; simulation produces FST waveform
timeout 120 ./Vtb_hmao_soc 2>&1 | tee "$SIM/sim_output.log" || {
    EC=$?
    if [ $EC -eq 124 ]; then
        echo "=== Simulation timed out after 120s ==="
    else
        echo "=== Simulation exited with code $EC ==="
    fi
}

echo "=== Files after simulation ==="
ls -lh "$SIM/obj_dir/"*.fst 2>/dev/null || echo "No FST file found"
ls -lh "$SIM/obj_dir/"*.vcd 2>/dev/null || echo "No VCD file found"
ls -lh "$SIM/"*.log 2>/dev/null || echo "No log file"
