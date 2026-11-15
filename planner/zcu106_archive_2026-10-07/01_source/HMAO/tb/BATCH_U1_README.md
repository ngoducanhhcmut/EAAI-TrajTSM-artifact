# ============================================================
# HMAO Preproc – Batch U1 Build & Run Guide (Verilator)
# ============================================================

## File list required for compilation
```
hmao_pkg.sv               # Package (types, enums, constants)
hmao_preproc.sv           # DUT
tb_preproc_batch_u1.sv    # This testbench (includes axi4_ro_if inline)
```

> If your project already has a separate `axi4_ro_if.sv`, either:
> - Remove the `interface ... endinterface` block at the top of the testbench, OR
> - Guard both with the same `\`ifndef AXI4_RO_IF_DEFINED` guard already present.

---

## Build command (Verilator 5.x)

```bash
verilator --cc --exe --build --assert --coverage \
  --top-module tb_preproc_batch_u1 \
  -DSIMULATION \
  hmao_pkg.sv \
  hmao_preproc.sv \
  tb_preproc_batch_u1.sv \
  -o sim_preproc_u1 \
  --Mdir obj_dir_u1

./obj_dir_u1/Vtb_preproc_batch_u1
```

### Flags explained
| Flag | Purpose |
|------|---------|
| `--assert` | Enable SystemVerilog SVA (ap_mutex, ap_latency, etc.) |
| `--coverage` | Enable toggle + line coverage (defines `COVERAGE`) |
| `--build` | Compile & link in one step |

---

## Expected console output (all pass)

```
╔══════════════════════════════════════════════════════╗
║  HMAO Engine – Unit Test Batch U1                   ║
...
━━━ TP_001 : CRC32 Valid ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        [CRC]  traj_mem[350] = 0xXXXXXXXX (freshly computed)
        [RST]  Reset released, DUT idle.
        [RUN]  Completed in NNNNN cycles | valid=1 error=0
        [OK ]  TP_001     crc_fail == 0  (CRC matched)
        [OK ]  TP_001     valid_out == 1 (preproc completed OK)
...
[PASS] TP_001      ──────────────────────────────────
...
[PASS] TP_006      ──────────────────────────────────

╔══════════════════════════════════════════════════════╗
║  BATCH U1  SUMMARY                                  ║
║  PASS   : 6                                         ║
║  FAIL   : 0                                         ║
║  STATUS : ✓  ALL PASSED                             ║
╚══════════════════════════════════════════════════════╝
```

---

## Coverage report

```bash
# After simulation, generate coverage report
verilator_coverage --annotate annotated/ coverage.dat
```

Target thresholds:
- Line/code coverage : 100 %
- Toggle coverage    : ≥ 98 %
- FSM state coverage : ≥ 95 % (all 8 PP_xxx states hit across 6 tests)

### FSM states exercised per test case

| State       | TP_001 | TP_002 | TP_003 | TP_004 | TP_005 | TP_006 |
|-------------|--------|--------|--------|--------|--------|--------|
| PP_IDLE     | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| PP_FETCH    | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| PP_CRC      | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| PP_KINEMATIC| ✓ | – | ✓ | ✓ | ✓ | ✓ |
| PP_FORMAT   | ✓ | – | ✓ | – | ✓ | ✓ |
| PP_BBOX     | ✓ | – | ✓ | – | ✓ | – |
| PP_DONE     | ✓ | – | ✓ | – | ✓ | – |
| PP_ERROR    | – | ✓ | – | ✓ | – | ✓ |

(TP_002 goes directly CRC→ERROR; TP_004 goes KINEMATIC→ERROR; TP_006 goes FORMAT→ERROR)

---

## RTL Notes / Known Limitations (v12.0 skeleton)

1. **Kinematic exponent check** catches |vx| or |vy| with float32 exponent > 132,
   i.e., magnitudes ≥ 64 m/s. The secondary magnitude² threshold covers 35…63 m/s.
   TP_004 uses 72 m/s (exp=133) to exercise the fast-path.

2. **Timestamp delta check** is marked TODO in the RTL FORMAT step. TP_006
   documents the intended non-uniform-timestamp scenario (Injection A) and uses
   NaN injection (Injection B) to exercise the currently implemented error path.
   When the Δt check is added to RTL, remove Injection B and rely on Injection A alone.

3. **crc_fail persistence** – the signal is sticky until rst_n. `do_reset()` is
   called at the start of every test case to guarantee a clean baseline.

4. **kinematic_fail** clears automatically when FSM returns to PP_IDLE (one cycle
   after error_out pulses). The extra `@(posedge clk)` at the end of `run_preproc`
   lets the register clear before the next test begins.
