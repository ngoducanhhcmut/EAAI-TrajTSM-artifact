#!/usr/bin/env python3
# =============================================================================
# FILE    : dsp_cycle_savings.py
# PROJECT : HMAO Engine – Batch U9 Bonus Report
# PURPOSE : Compute and visualise the clock-cycle savings achieved by the
#           8-DSP parallel SAT architecture vs a hypothetical 1-DSP serial
#           baseline.  Covers realistic Stage-1 AND Stage-2 workloads.
# =============================================================================

from dataclasses import dataclass, field
from typing import List

# ─── Constants ────────────────────────────────────────────────────────────────
CLK_FREQ_HZ   = 400_000_000       # 400 MHz (HMAO Spec §1.3)
CLK_PERIOD_NS = 1e9 / CLK_FREQ_HZ  # 2.5 ns

# Stage-1 collision budget (Spec §11.2)
# S1_COLLISION_CYCLES = 800,000 (2.0 ms) – SAT checker sub-budget
# But SAT must also fit within the TOTAL Stage-1 budget of 1,600,000 (4.0 ms)
# We use the SAT sub-budget as the constraint here.
# NOTE: 100 obstacles × 50 zon × 6-cycle AXI fetch = 30,000 AXI cycles additional.
#       Total SAT+AXI for 8-DSP = 100×(6+150) = 15,600 cy (well within budget).
#       The advantage is most visible when N_obs or N_zon scales up.
S1_COLLISION_BUDGET_CYCLES = 800_000    # 2.0 ms – SAT sub-budget (Spec §11.2)
S2_COLLISION_BUDGET_CYCLES = 600_000    # 1.5 ms – Stage-2 SAT sub-budget

# Per-(obstacle, zonotope) cycle costs
#  8-DSP parallel : AXES(1) + PROJECT_parallel(1) + DECIDE(1) = 3 cycles
#  1-DSP serial   : AXES(1) + PROJECT×8(8) + DECIDE(1)        = 10 cycles
COST_8DSP = 3
COST_1DSP = 10

# ─── Workload Configurations ──────────────────────────────────────────────────
@dataclass
class Workload:
    name      : str
    n_obs     : int        # number of obstacles to check
    n_zon     : int        # number of zonotopes (timesteps) per obstacle
    budget    : int        # cycle budget for this workload
    n_conf0   : int = 0    # obstacles skipped by confidence=0 gate
    n_prefilter: int = 0   # obstacles skipped by bounding-box pre-filter

AXI_FETCH_CYCLES_PER_OBS = 6   # AR_ACK + BEAT1 + BEAT2 (≈ 6 cycles per obstacle)

WORKLOADS = [
    Workload("Stage-1  (100 obs × 50 zon)",  100,  50, S1_COLLISION_BUDGET_CYCLES,
             n_conf0=5, n_prefilter=30),
    Workload("Stage-2  ( 16 obs × 100 zon)",  16, 100, S2_COLLISION_BUDGET_CYCLES,
             n_conf0=0, n_prefilter=2),
    Workload("Stress   (500 obs × 100 zon)", 500, 100, S1_COLLISION_BUDGET_CYCLES,
             n_conf0=20, n_prefilter=100),
    Workload("Unit-Test (  1 obs ×   4 zon)",   1,   4, 9999,
             n_conf0=0, n_prefilter=0),
]

# ─── Helpers ──────────────────────────────────────────────────────────────────
def cycles_to_us(c: int) -> float:
    return c * CLK_PERIOD_NS / 1_000.0

def pct(a: int, b: int) -> float:
    return 100.0 * a / b if b else 0.0

def bar(value: int, maximum: int, width: int = 40, char: str = "█") -> str:
    filled = max(0, min(width, round(width * value / maximum)))
    return char * filled + "░" * (width - filled)

# ─── Per-workload analysis ─────────────────────────────────────────────────────
@dataclass
class Result:
    wl          : Workload
    pairs_full  : int    # obs×zon pairs that go through full SAT
    pairs_skipped: int
    cyc_8dsp    : int
    cyc_1dsp    : int
    saved       : int
    pct_saved   : float
    budget_use_8: float  # % of budget used by 8-DSP
    budget_use_1: float  # % of budget used by 1-DSP
    over_budget_1: bool

def analyse(wl: Workload) -> Result:
    # Skipped pairs: conf=0 obstacles skip ALL zonotopes (no SAT at all)
    #                prefilter obstacles also skip all zonotopes
    pairs_skipped = (wl.n_conf0 + wl.n_prefilter) * wl.n_zon
    pairs_full    = max(0, wl.n_obs * wl.n_zon - pairs_skipped)

    # AXI fetch: paid once per obstacle (including skipped ones – fetch happens before gate)
    cyc_axi   = wl.n_obs * AXI_FETCH_CYCLES_PER_OBS

    cyc_8dsp  = cyc_axi + pairs_full * COST_8DSP
    cyc_1dsp  = cyc_axi + pairs_full * COST_1DSP
    saved     = cyc_1dsp - cyc_8dsp

    return Result(
        wl            = wl,
        pairs_full    = pairs_full,
        pairs_skipped = pairs_skipped,
        cyc_8dsp      = cyc_8dsp,
        cyc_1dsp      = cyc_1dsp,
        saved         = saved,
        pct_saved     = pct(saved, cyc_1dsp),
        budget_use_8  = pct(cyc_8dsp, wl.budget),
        budget_use_1  = pct(cyc_1dsp, wl.budget),
        over_budget_1 = cyc_1dsp > wl.budget,
    )

# ─── Print header ──────────────────────────────────────────────────────────────
def sep(char="═", width=70):
    print(char * width)

def print_header():
    sep()
    print("  HMAO Engine – DSP Parallel vs Serial Cycle-Savings Report")
    print("  Spec Ref: HMAO_Engine_Full_Spec v12.0 §7.4.2 (SAT DSP48E2)")
    sep()
    print(f"  Clock frequency  : {CLK_FREQ_HZ/1e6:.0f} MHz  ({CLK_PERIOD_NS:.1f} ns / cycle)")
    print(f"  1-DSP serial cost: {COST_1DSP} cycles per (obs, zonotope) pair")
    print(f"    = AXES(1) + 8×PROJECT_serial(8) + DECIDE(1)")
    print(f"  8-DSP parallel   : {COST_8DSP} cycles per (obs, zonotope) pair")
    print(f"    = AXES(1) + 1×PROJECT_parallel(1) + DECIDE(1)")
    print(f"  Speedup factor   : {COST_1DSP}/{COST_8DSP} = {COST_1DSP/COST_8DSP:.2f}×")
    sep("─")

def print_result(r: Result):
    w = r.wl
    axi_cyc = w.n_obs * AXI_FETCH_CYCLES_PER_OBS
    print(f"\n  ◆  {w.name}")
    print(f"     Obstacles         : {w.n_obs:>6}  "
          f"(conf=0 skipped: {w.n_conf0}, bbox-skip: {w.n_prefilter})")
    print(f"     Zonotopes/obs     : {w.n_zon:>6}")
    print(f"     Full-SAT pairs    : {r.pairs_full:>6}  (skipped: {r.pairs_skipped})")
    print(f"     AXI fetch cycles  : {axi_cyc:>6}  (constant, {AXI_FETCH_CYCLES_PER_OBS} cy × {w.n_obs} obs)")
    print()
    # Cycles table
    print(f"     {'Architecture':<25} {'Cycles (AXI+SAT)':>16}  {'Time (µs)':>10}  {'Budget %':>9}")
    print(f"     {'─'*25}  {'─'*16}  {'─'*10}  {'─'*9}")
    bud_str8 = f"{r.budget_use_8:6.1f}%  {'✓' if not r.over_budget_1 or r.budget_use_8<=100 else '⚠'}"
    bud_str1 = f"{r.budget_use_1:6.1f}%  {'⚠ OVER BUDGET' if r.over_budget_1 else '✓'}"
    print(f"     {'1-DSP serial':<25} {r.cyc_1dsp:>16,}  {cycles_to_us(r.cyc_1dsp):>10.2f}  {bud_str1}")
    print(f"     {'8-DSP parallel':<25} {r.cyc_8dsp:>16,}  {cycles_to_us(r.cyc_8dsp):>10.2f}  {bud_str8}")
    print(f"     {'SAVED (SAT only)':<25} {r.saved:>16,}  {cycles_to_us(r.saved):>10.2f}  {r.pct_saved:5.1f}%")
    # Budget bar
    max_bar = max(r.cyc_8dsp, r.cyc_1dsp, w.budget)
    print()
    print(f"     Budget {cycles_to_us(w.budget):.0f} µs:")
    print(f"     1-DSP  [{bar(r.cyc_1dsp, max_bar)}] {cycles_to_us(r.cyc_1dsp):.1f} µs")
    print(f"     8-DSP  [{bar(r.cyc_8dsp, max_bar)}] {cycles_to_us(r.cyc_8dsp):.1f} µs")
    print(f"     Budget [{bar(w.budget,   max_bar, char='─')}] {cycles_to_us(w.budget):.1f} µs limit")

def print_per_pair_breakdown():
    sep("─")
    print("\n  PER-PAIR CYCLE BREAKDOWN\n")
    headers = ["Stage", "DSP Count", "Axes/cycle", "Cycles/pair", "Speedup"]
    rows = [
        ["AXES",    "—",   "—",  "1",  "—"],
        ["PROJECT", "1",   "1",  "8", f"1×"],
        ["PROJECT", "8",   "8",  "1", f"8×"],
        ["DECIDE",  "—",   "—",  "1",  "—"],
    ]
    print(f"    {'Stage FSM':<12} {'Arch':<16} {'Axes/cycle':>10} {'Cycles':>8} {'vs serial':>10}")
    print(f"    {'─'*12}  {'─'*16}  {'─'*10}  {'─'*8}  {'─'*10}")
    print(f"    {'AXES':<12} {'(common)':<16} {'—':>10} {'1':>8} {'—':>10}")
    print(f"    {'PROJECT':<12} {'1-DSP serial':<16} {'1':>10} {'8':>8} {'1.0×':>10}")
    print(f"    {'PROJECT':<12} {'8-DSP parallel':<16} {'8':>10} {'1':>8} {'8.0×':>10}")
    print(f"    {'DECIDE':<12} {'(common)':<16} {'—':>10} {'1':>8} {'—':>10}")
    print(f"    {'─'*12}  {'─'*16}  {'─'*10}  {'─'*8}  {'─'*10}")
    print(f"    {'TOTAL':<12} {'1-DSP':<16} {'—':>10} {COST_1DSP:>8} {'1.0×':>10}")
    print(f"    {'TOTAL':<12} {'8-DSP':<16} {'—':>10} {COST_8DSP:>8} {COST_1DSP/COST_8DSP:.1f}×  ✓")

def print_gate_analysis():
    sep("─")
    print("\n  CONFIDENCE=0 GATE SAVINGS  (TSAT_008)\n")
    print("  Each confidence=0 obstacle saves:")
    for n_zon in [4, 50, 100]:
        # Serial vs parallel savings when obstacle is skipped (avoids all SAT)
        saved_8 = n_zon * COST_8DSP
        saved_1 = n_zon * COST_1DSP
        print(f"    {n_zon:>3} zonotopes skipped → {saved_8:>5} cycles (8-DSP) "
              f"or {saved_1:>5} cycles (1-DSP) saved")
    print()
    print("  In Stage-1 with 5 conf=0 obstacles (typical noisy world model):")
    saved = 5 * 50 * COST_8DSP
    print(f"    5 × 50 zon × {COST_8DSP} cy = {saved:,} cycles = "
          f"{cycles_to_us(saved):.2f} µs saved by confidence gate")

def print_conclusion(results: List[Result]):
    sep("─")
    print("\n  CONCLUSION\n")
    s1  = next(r for r in results if "Stage-1" in r.wl.name)
    s2  = next(r for r in results if "Stage-2" in r.wl.name)
    str = next(r for r in results if "Stress"  in r.wl.name)

    print(f"  ─ Normal workloads (within spec) ────────────────────────────")
    print(f"  Stage-1 budget  = {cycles_to_us(s1.wl.budget):.1f} µs  ({s1.wl.budget:,} cycles)")
    print(f"  8-DSP  SAT+AXI  = {cycles_to_us(s1.cyc_8dsp):.2f} µs  ({s1.budget_use_8:.2f}% of budget)  ✓")
    print(f"  1-DSP  SAT+AXI  = {cycles_to_us(s1.cyc_1dsp):.2f} µs  ({s1.budget_use_1:.2f}% of budget)  ✓")
    print()
    print(f"  ─ Stress workload: 500 obs × 100 zon ─────────────────────────")
    print(f"  Stage-1 budget  = {cycles_to_us(str.wl.budget):.1f} µs  ({str.wl.budget:,} cycles)")
    print(f"  8-DSP  SAT+AXI  = {cycles_to_us(str.cyc_8dsp):.2f} µs  ({str.budget_use_8:.1f}% of budget)")
    ob_str = "⚠ OVER BUDGET" if str.over_budget_1 else "✓ within budget"
    print(f"  1-DSP  SAT+AXI  = {cycles_to_us(str.cyc_1dsp):.2f} µs  ({str.budget_use_1:.1f}% of budget)  {ob_str}")
    if str.over_budget_1:
        over = str.cyc_1dsp - str.wl.budget
        print(f"  1-DSP exceeds budget by {over:,} cycles ({cycles_to_us(over):.2f} µs)")
        print(f"  → Would violate HMAO 10 ms hard deadline (ISO 26262 ASIL-D)")
    print()
    print("  Per-(obs,zon) pair: 8-DSP saves 7 cycles (70% reduction).")
    print("  With gating (conf=0 + bbox-prefilter), effective savings vary.")
    print(f"  Stage-1+Stage-2 combined SAT savings: "
          f"{s1.saved+s2.saved:,} cycles = {cycles_to_us(s1.saved+s2.saved):.2f} µs")
    print()
    sep()

# ─── Main ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    results = [analyse(w) for w in WORKLOADS]

    print_header()
    for r in results:
        print_result(r)

    print_per_pair_breakdown()
    print_gate_analysis()
    print_conclusion(results)
