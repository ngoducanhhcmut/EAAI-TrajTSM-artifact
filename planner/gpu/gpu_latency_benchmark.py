"""
GPU latency benchmark for VLA-Traj planning model.

Measures per-inference latency distribution (mean, std, P50/P95/P99/max)
using torch.cuda.Event for GPU-accurate timing. Batch size = 1 (automotive
real-time setting: one scene processed per inference call).

Usage (local GPU or cloud):
  python gpu_latency_benchmark.py --weights weights/planT_converted.pt
  python gpu_latency_benchmark.py --weights weights/planT_converted.pt --n-runs 2000
  python gpu_latency_benchmark.py --smoke  # random weights, no file needed

Output: console report + gpu_latency_results.json
"""

import argparse
import json
import time
import os
import sys
import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model.fp32_model import build_model, PlanningModel, MAX_SEQ_LEN

# ── Config ────────────────────────────────────────────────────────────────────
FPGA_WCET_MS   = 58.4        # planning_pkg.sv TOTAL_LATENCY_CY / 185 MHz
FPGA_FREQ_MHZ  = 185
FPGA_CYCLES    = 10_800_000
N_WARMUP       = 200         # throw-away warmup iterations (GPU JIT + cache warm)
N_RUNS_DEFAULT = 1000        # measurement iterations
SEQ_LEN        = 64          # MAX_SEQ_LEN from planning_pkg.sv
INPUT_DIM      = 6           # bbox6_t: (x_min, y_min, x_max, y_max, vx, vy)


def load_model(weights_path: str, device: torch.device) -> PlanningModel:
    model = build_model()
    ckpt  = torch.load(weights_path, map_location=device)
    sd    = ckpt["model"] if "model" in ckpt else ckpt
    missing, _ = model.load_state_dict(sd, strict=False)
    if missing:
        print(f"  Note: {len(missing)} keys use random init (wp_proj — latency unaffected): {missing}")
    model.eval()
    model.to(device)
    return model


def make_dummy_input(device: torch.device):
    """Single-scene input (batch=1), seq_len=64, typical automotive token count."""
    tokens = torch.randn(1, SEQ_LEN, INPUT_DIM, device=device)
    mask   = torch.zeros(1, SEQ_LEN, dtype=torch.bool, device=device)
    mask[0, 20:] = True   # 20 valid tokens, 44 padding (realistic scene density)
    return tokens, mask


def benchmark_gpu(model: PlanningModel, device: torch.device,
                  n_warmup: int, n_runs: int) -> np.ndarray:
    """
    Returns array of per-inference latencies in milliseconds.
    Uses torch.cuda.Event for sub-millisecond GPU-accurate measurement
    (wall-clock time.perf_counter() includes Python overhead; Events do not).
    """
    tokens, mask = make_dummy_input(device)

    # Pre-allocate Event pairs to avoid allocation jitter during measurement
    starts = [torch.cuda.Event(enable_timing=True) for _ in range(n_runs)]
    ends   = [torch.cuda.Event(enable_timing=True) for _ in range(n_runs)]

    # Warmup: let CUDA JIT compile, fill caches, stabilise clocks
    print(f"Warming up ({n_warmup} iterations)...")
    with torch.no_grad():
        for _ in range(n_warmup):
            _ = model(tokens, mask)
    torch.cuda.synchronize()

    # Measurement
    print(f"Measuring ({n_runs} iterations)...")
    with torch.no_grad():
        for i in range(n_runs):
            starts[i].record()
            _ = model(tokens, mask)
            ends[i].record()
    torch.cuda.synchronize()   # wait for all kernels to finish

    latencies_ms = np.array([
        starts[i].elapsed_time(ends[i]) for i in range(n_runs)
    ])
    return latencies_ms


def benchmark_cpu(model: PlanningModel, n_warmup: int, n_runs: int) -> np.ndarray:
    """CPU fallback — uses perf_counter (no CUDA Events available)."""
    device = torch.device("cpu")
    tokens, mask = make_dummy_input(device)
    model = model.to(device)

    print(f"CPU warmup ({n_warmup} iterations)...")
    with torch.no_grad():
        for _ in range(n_warmup):
            _ = model(tokens, mask)

    print(f"CPU measuring ({n_runs} iterations)...")
    latencies_ms = []
    with torch.no_grad():
        for _ in range(n_runs):
            t0 = time.perf_counter()
            _ = model(tokens, mask)
            t1 = time.perf_counter()
            latencies_ms.append((t1 - t0) * 1000.0)
    return np.array(latencies_ms)


def print_report(latencies_ms: np.ndarray, device_name: str):
    p50  = float(np.percentile(latencies_ms, 50))
    p95  = float(np.percentile(latencies_ms, 95))
    p99  = float(np.percentile(latencies_ms, 99))
    mean = float(np.mean(latencies_ms))
    std  = float(np.std(latencies_ms))
    mn   = float(np.min(latencies_ms))
    mx   = float(np.max(latencies_ms))

    jitter_ratio = mx / mn if mn > 0 else float("inf")

    print()
    print("=" * 60)
    print(f"  VLA-Traj GPU Latency Benchmark")
    print(f"  Device  : {device_name}")
    print(f"  Batch   : 1 (automotive real-time)")
    print(f"  Seq len : {SEQ_LEN} tokens (20 valid, 44 padding)")
    print(f"  Runs    : {len(latencies_ms)}")
    print("=" * 60)
    print(f"  Mean     : {mean:7.3f} ms")
    print(f"  Std dev  : {std:7.3f} ms   <- latency jitter")
    print(f"  Min      : {mn:7.3f} ms")
    print(f"  P50      : {p50:7.3f} ms")
    print(f"  P95      : {p95:7.3f} ms")
    print(f"  P99      : {p99:7.3f} ms")
    print(f"  Max      : {mx:7.3f} ms")
    print(f"  Jitter   : {jitter_ratio:.1f}x (max/min ratio)")
    print()
    print("  -- FPGA comparison ----------------------------------")
    print(f"  FPGA WCET: {FPGA_WCET_MS:.1f} ms  ({FPGA_FREQ_MHZ} MHz, "
          f"{FPGA_CYCLES:,} cycles)")
    print(f"  FPGA std : 0.000 ms  (WCET = BCET, cycle-exact FSM)")
    print(f"  FPGA jitter: 1.0x (deterministic)")
    print()

    speedup_mean = FPGA_WCET_MS / mean
    if speedup_mean > 1:
        print(f"  GPU is {speedup_mean:.1f}x faster than FPGA on mean latency.")
    else:
        print(f"  FPGA is {1/speedup_mean:.1f}x faster than GPU on mean latency.")

    gap_p99 = p99 / FPGA_WCET_MS
    print(f"  GPU P99 is {gap_p99:.2f}x the FPGA WCET.")
    print(f"  FPGA WCET bound is {'TIGHTER' if gap_p99 > 1 else 'LOOSER'} than GPU P99.")
    print("=" * 60)

    return {
        "device": device_name,
        "n_runs": int(len(latencies_ms)),
        "batch_size": 1,
        "seq_len": SEQ_LEN,
        "mean_ms":   round(mean, 4),
        "std_ms":    round(std,  4),
        "min_ms":    round(mn,   4),
        "p50_ms":    round(p50,  4),
        "p95_ms":    round(p95,  4),
        "p99_ms":    round(p99,  4),
        "max_ms":    round(mx,   4),
        "jitter_ratio_max_min": round(jitter_ratio, 2),
        "fpga_wcet_ms":  FPGA_WCET_MS,
        "fpga_std_ms":   0.0,
        "fpga_cycles":   FPGA_CYCLES,
        "fpga_freq_mhz": FPGA_FREQ_MHZ,
        "speedup_gpu_over_fpga_mean": round(FPGA_WCET_MS / mean, 2),
        "gpu_p99_vs_fpga_wcet_ratio": round(gap_p99, 3),
    }


def main():
    parser = argparse.ArgumentParser(description="VLA-Traj GPU latency benchmark")
    parser.add_argument("--weights", default=None,
                        help="Path to model weights .pt file")
    parser.add_argument("--n-runs",  type=int, default=N_RUNS_DEFAULT,
                        help=f"Number of timed inference runs (default: {N_RUNS_DEFAULT})")
    parser.add_argument("--warmup",  type=int, default=N_WARMUP,
                        help=f"Warmup iterations (default: {N_WARMUP})")
    parser.add_argument("--out", default="gpu_latency_results.json",
                        help="Output JSON file")
    parser.add_argument("--smoke", action="store_true",
                        help="Use random weights (no --weights file needed)")
    args = parser.parse_args()

    # Build model
    if args.smoke or args.weights is None:
        print("Using random weights (smoke mode — no real weights loaded).")
        model = build_model()
        model.eval()
    else:
        if not os.path.exists(args.weights):
            print(f"ERROR: weights file not found: {args.weights}", file=sys.stderr)
            sys.exit(1)
        print(f"Loading weights from {args.weights} ...")
        device_tmp = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        model = load_model(args.weights, device_tmp)

    # Select device
    if torch.cuda.is_available():
        device = torch.device("cuda")
        device_name = torch.cuda.get_device_name(0)
        print(f"CUDA device: {device_name}")
        latencies = benchmark_gpu(model, device, args.warmup, args.n_runs)
    else:
        print("WARNING: CUDA not available — falling back to CPU benchmark.")
        print("         Results will NOT reflect GPU performance.")
        device_name = "CPU (no CUDA)"
        latencies = benchmark_cpu(model, args.warmup, args.n_runs)

    results = print_report(latencies, device_name)

    # Save raw latency array alongside summary
    results["latencies_ms_raw"] = latencies.tolist()

    with open(args.out, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to {args.out}")


if __name__ == "__main__":
    main()
