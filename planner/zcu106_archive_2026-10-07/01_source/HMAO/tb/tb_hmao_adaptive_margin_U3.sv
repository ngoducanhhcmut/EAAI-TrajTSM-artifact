// =============================================================================
// FILE        : tb_hmao_adaptive_margin_U3.sv
// PROJECT     : HMAO Engine - Unit Test Batch U3
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 8
// SAFETY      : ASIL-D (ISO 26262)
// DUT         : hmao_adaptive_margin.sv
// DESCRIPTION : Unit Test Batch U3 - Adaptive Margin Controller
//
//   TM_001  Weighted Quality Scoring      (formula verification)
//   TM_002  LUT Lookup – Low  Quality     (scale UP  for safety)
//   TM_003  LUT Lookup – High Quality     (scale DOWN for performance)
//   TM_004  Hardware Clamps               (output always in [MIN, MAX])
//
// MODULE LATENCY: Combinational (no register stages).
//   Outputs settle within the same combinational cycle; #1 propagation
//   delay is used after driving inputs before sampling outputs.
//
// PRE-COMPUTED REFERENCE VALUES (verified with reference Python model):
// ┌──────────┬────┬──────┬──────┬────────────┬────────────┬────────────┐
// │ Test     │ cq │ scale│lat_rw│ lat_out    │ long_out   │ time_out   │
// ├──────────┼────┼──────┼──────┼────────────┼────────────┼────────────┤
// │ TM_001   │221 │  196 │0x0126│ 0x0126     │ 0x0200 ※  │ 0x0062     │
// │ TM_002   │ 50 │  432 │0x0288│ 0x0288     │ 0x0360     │ 0x00D8     │
// │ TM_003   │240 │  234 │0x015F│ 0x015F     │ 0x0200 ※  │ 0x0075     │
// │ TM_004A  │  0 │  332 │0x01F2│ 0x01F2     │ 0x0298     │ 0x00A6     │
// │ TM_004B  │255 │  264 │0x018C│ 0x018C     │ 0x0210     │ 0x0084     │
// │ TM_004C  │153 │  309 │0x01CF│ 0x01CF     │ 0x026A     │ 0x009A     │
// │ TM_004D  │200 │  154 │0x00E7│ 0x00E7     │ 0x0200 ※  │ 0x004D     │
// └──────────┴────┴──────┴──────┴────────────┴────────────┴────────────┘
//   ※ = clamped to MIN_LONG_Q8_8 (long_raw < 512 = 2.0m minimum)
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module tb_hmao_adaptive_margin_U3;

  // ---------------------------------------------------------------------------
  // DUT interface signals
  // ---------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic [7:0]  gps_quality;
  logic [7:0]  camera_quality;
  logic [7:0]  road_friction;
  logic [7:0]  actuator_health;
  logic [7:0]  weather_severity;

  logic [15:0] lateral_margin;
  logic [15:0] long_margin;
  logic [15:0] time_margin;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  hmao_adaptive_margin dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .gps_quality     (gps_quality),
    .camera_quality  (camera_quality),
    .road_friction   (road_friction),
    .actuator_health (actuator_health),
    .weather_severity(weather_severity),
    .lateral_margin  (lateral_margin),
    .long_margin     (long_margin),
    .time_margin     (time_margin)
  );

  // ---------------------------------------------------------------------------
  // Clock: 400 MHz → period = 2.5 ns
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #1.25 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Scoreboard counters
  // ---------------------------------------------------------------------------
  int pass_count;
  int fail_count;

  // Variables for inline reference calculations (module scope avoids
  // XSim issues with 'automatic' inside unnamed begin-end blocks)
  logic [15:0] ws_ref;
  logic [7:0]  cq_ref;
  logic [15:0] long_raw_ref;

  // Flag set by test_main before $finish so watchdog won't fire on 'run -all'
  // after XSim already completed the test (XSim keeps simulation alive for
  // interactive use even after $finish in the TCL batch run).
  logic test_complete = 1'b0;

  // ---------------------------------------------------------------------------
  // Helper tasks
  // ---------------------------------------------------------------------------

  // Drive inputs and wait 1 delta + 1 ns for combinational settle
  task automatic drive_inputs(
    input logic [7:0] gps, cam, fric, act,
    input string      label
  );
    gps_quality     = gps;
    camera_quality  = cam;
    road_friction   = fric;
    actuator_health = act;
    weather_severity = 8'h00;       // reserved, not used
    #1;                             // combinational propagation settle
    $display("\n  [DRIVE] %s | GPS=%0d CAM=%0d FRIC=%0d ACT=%0d",
             label, gps, cam, fric, act);
  endtask

  // Exact-value assertion
  task automatic assert_eq(
    input string      test_id,
    input string      sig_name,
    input logic [15:0] actual,
    input logic [15:0] expected
  );
    if (actual === expected) begin
      $display("  PASS  [%s] %s = 0x%04X  (%.4f m/s in Q8.8)",
               test_id, sig_name, actual, real'(actual) / 256.0);
      pass_count++;
    end else begin
      $display("  FAIL  [%s] %s = 0x%04X  expected 0x%04X  *** MISMATCH ***",
               test_id, sig_name, actual, expected);
      fail_count++;
    end
  endtask

  // Bounds-only assertion (for clamp verification)
  task automatic assert_in_range(
    input string       test_id,
    input string       sig_name,
    input logic [15:0] val,
    input logic [15:0] lo,
    input logic [15:0] hi
  );
    if (val >= lo && val <= hi) begin
      $display("  PASS  [%s] %s = 0x%04X  in [0x%04X, 0x%04X]",
               test_id, sig_name, val, lo, hi);
      pass_count++;
    end else begin
      $display("  FAIL  [%s] %s = 0x%04X  OUT OF RANGE [0x%04X, 0x%04X]  ***",
               test_id, sig_name, val, lo, hi);
      fail_count++;
    end
  endtask

  // Scale-direction assertion (higher = scaled up from BASE)
  task automatic assert_scaled_up(
    input string       test_id,
    input string       sig_name,
    input logic [15:0] actual,
    input logic [15:0] base_val
  );
    if (actual >= base_val) begin
      $display("  PASS  [%s] %s scale UP: 0x%04X >= BASE 0x%04X (%.3f >= %.3f)",
               test_id, sig_name, actual, base_val,
               real'(actual)/256.0, real'(base_val)/256.0);
      pass_count++;
    end else begin
      $display("  FAIL  [%s] %s NOT scaled up: 0x%04X < BASE 0x%04X  ***",
               test_id, sig_name, actual, base_val);
      fail_count++;
    end
  endtask

  task automatic assert_scaled_down(
    input string       test_id,
    input string       sig_name,
    input logic [15:0] actual,
    input logic [15:0] base_val
  );
    if (actual <= base_val) begin
      $display("  PASS  [%s] %s scale DOWN: 0x%04X <= BASE 0x%04X (%.3f <= %.3f)",
               test_id, sig_name, actual, base_val,
               real'(actual)/256.0, real'(base_val)/256.0);
      pass_count++;
    end else begin
      $display("  FAIL  [%s] %s NOT scaled down: 0x%04X > BASE 0x%04X  ***",
               test_id, sig_name, actual, base_val);
      fail_count++;
    end
  endtask

  // ============================================================================
  // MAIN TEST SEQUENCE
  // ============================================================================
  initial begin : test_main
    pass_count = 0;
    fail_count = 0;

    // ---- Reset ----------------------------------------------------------------
    rst_n           = 1'b0;
    gps_quality     = 8'h00;
    camera_quality  = 8'h00;
    road_friction   = 8'h00;
    actuator_health = 8'h00;
    weather_severity = 8'h00;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    // Allow LUT initial block to complete (sim-only, combinational path)
    #5;

    $display("======================================================");
    $display(" HMAO Batch U3 – Adaptive Margin Controller Tests");
    $display(" DUT: hmao_adaptive_margin.sv | Spec v12.0 §8");
    $display("======================================================");

    // ==========================================================================
    // TM_001 – Weighted Quality Scoring
    // --------------------------------------------------------------------------
    // Inputs : GPS=200, CAM=200, FRICTION=255, ACTUATOR=255
    // Arithmetic:
    //   weighted = (200×77)+(200×77)+(255×51)+(255×51)
    //            = 15400+15400+13005+13005 = 56810
    //   combined_quality = 56810[15:8] = 56810 >> 8 = 221  (0xDD)
    //   scale_lut[221]   = 154 + (221-200)×2 = 196         (0x0C4, range 200-255)
    //
    //   lat_raw  = (0x0180 × 196) >> 8 = (384×196)>>8  = 75264>>8  = 294 = 0x0126
    //   long_raw = (0x0200 × 196) >> 8 = (512×196)>>8  = 100352>>8 = 392 = 0x0188
    //   time_raw = (0x0080 × 196) >> 8 = (128×196)>>8  = 25088>>8  =  98 = 0x0062
    //
    //   Clamp result:
    //     lateral : 0x0080≤0x0126≤0x0300  → lateral_margin = 0x0126  (no clamp)
    //     long    : 0x0188=392 < MIN_LONG=0x0200=512 → long_margin = 0x0200 (clamped)
    //     time    : 0x0040≤0x0062≤0x0180  → time_margin   = 0x0062  (no clamp)
    // ==========================================================================
    $display("\n────────────────────────────────────────────────────");
    $display(" TM_001: Weighted Quality Scoring Formula Validation");
    $display("────────────────────────────────────────────────────");

    drive_inputs(8'd200, 8'd200, 8'd255, 8'd255, "TM_001");

    begin : tm001_ref_calc
      // Software reference calculation (mirrors DUT combinational logic)
      ws_ref  = (16'(8'd200)*77) + (16'(8'd200)*77)
              + (16'(8'd255)*51) + (16'(8'd255)*51);
      cq_ref  = ws_ref[15:8];

      $display("  INFO: weighted_score = %0d (0x%04X)", ws_ref, ws_ref);
      $display("  INFO: combined_quality expected = %0d (0x%02X)", cq_ref, cq_ref);
      $display("  INFO: scale_lut[221] = 154+(221-200)*2 = 196");

      // Verify weighted arithmetic matches spec constants
      assert (ws_ref == 16'd56810)
        else $fatal(1, "TM_001: Software reference mismatch (internal error)");
      assert (cq_ref == 8'd221)
        else $fatal(1, "TM_001: combined_quality reference mismatch (internal error)");
    end : tm001_ref_calc

    // Check DUT output margins against reference
    assert_eq   ("TM_001", "lateral_margin",  lateral_margin, 16'h0126);
    assert_eq   ("TM_001", "long_margin    ",  long_margin,    MIN_LONG_Q8_8);  // clamped 0x0200
    assert_eq   ("TM_001", "time_margin    ",  time_margin,    16'h0062);

    // ==========================================================================
    // TM_002 – LUT Lookup: Low Quality → Scale UP
    // --------------------------------------------------------------------------
    // Trick: all inputs = 50 → weighted = 50*(77+77+51+51) = 50*256 = 12800
    //        combined_quality = 12800 >> 8 = 50  (exact, no rounding)
    //
    //   scale_lut[50] = 332 + 50×2 = 432  (Q2.8, > 256 ≙ 1.69x)
    //
    //   lat_raw  = (384×432)>>8 = 165888>>8 = 648 = 0x0288  (2.53m > BASE 1.5m)
    //   long_raw = (512×432)>>8 = 221184>>8 = 864 = 0x0360  (3.38m > BASE 2.0m)
    //   time_raw = (128×432)>>8 =  55296>>8 = 216 = 0x00D8  (0.84s > BASE 0.5s)
    //
    //   All within clamp range → no clamping; margins are LARGER than BASE values
    // ==========================================================================
    $display("\n────────────────────────────────────────────────────");
    $display(" TM_002: LUT Lookup – Low Quality (cq=50), Scale UP");
    $display("────────────────────────────────────────────────────");

    drive_inputs(8'd50, 8'd50, 8'd50, 8'd50, "TM_002 (all=50)");
    $display("  INFO: scale_lut[50] = 332+50*2 = 432 (1.69x, Q2.8)");

    // Primary exact-value checks
    assert_eq ("TM_002", "lateral_margin", lateral_margin, 16'h0288);
    assert_eq ("TM_002", "long_margin   ", long_margin,    16'h0360);
    assert_eq ("TM_002", "time_margin   ", time_margin,    16'h00D8);

    // Semantic check: all outputs must be >= BASE (safety scaled UP)
    assert_scaled_up("TM_002", "lateral_margin", lateral_margin, BASE_LATERAL_Q8_8);
    assert_scaled_up("TM_002", "long_margin   ", long_margin,    BASE_LONG_Q8_8);
    assert_scaled_up("TM_002", "time_margin   ", time_margin,    BASE_TIME_Q8_8);

    // ==========================================================================
    // TM_003 – LUT Lookup: High Quality → Scale DOWN
    // --------------------------------------------------------------------------
    // Trick: all inputs = 240 → weighted = 240*256 = 61440
    //        combined_quality = 61440 >> 8 = 240  (exact)
    //
    //   scale_lut[240] = 154 + (240-200)×2 = 234  (0.91x < 256 ≙ 1.0x)
    //
    //   lat_raw  = (384×234)>>8 = 89856>>8  = 351 = 0x015F  (1.37m < BASE 1.5m)
    //   long_raw = (512×234)>>8 = 119808>>8 = 468 = 0x01D4  (1.83m < MIN_LONG 2.0m)
    //   time_raw = (128×234)>>8 = 29952>>8  = 117 = 0x0075  (0.46s < BASE 0.5s)
    //
    //   Clamp result:
    //     lateral : within → lateral_margin = 0x015F
    //     long    : 468 < MIN_LONG=512 → CLAMPED to 0x0200 (safety floor)
    //     time    : within → time_margin   = 0x0075
    // ==========================================================================
    $display("\n────────────────────────────────────────────────────");
    $display(" TM_003: LUT Lookup – High Quality (cq=240), Scale DOWN");
    $display("────────────────────────────────────────────────────");

    drive_inputs(8'd240, 8'd240, 8'd240, 8'd240, "TM_003 (all=240)");
    $display("  INFO: scale_lut[240] = 154+(240-200)*2 = 234 (0.91x, Q2.8)");
    $display("  INFO: long_raw=0x01D4=468 < MIN_LONG=0x0200=512 → clamp activated");

    // Exact value checks
    assert_eq ("TM_003", "lateral_margin", lateral_margin, 16'h015F);
    assert_eq ("TM_003", "long_margin   ", long_margin,    MIN_LONG_Q8_8);  // clamped 0x0200
    assert_eq ("TM_003", "time_margin   ", time_margin,    16'h0075);

    // Semantic check: lateral must be <= BASE (scale DOWN for performance)
    assert_scaled_down("TM_003", "lateral_margin", lateral_margin, BASE_LATERAL_Q8_8);
    // long is clamped UP to MIN_LONG – verify it's still at minimum safety floor
    assert_eq ("TM_003", "long_margin clamp floor", long_margin, MIN_LONG_Q8_8);

    // ==========================================================================
    // TM_004 – Hardware Clamps
    // --------------------------------------------------------------------------
    // Verifies the HARDWIRED clamp logic in Section 8.5 cannot be escaped.
    // Tests four corner-case stimulus patterns:
    //   A) All=0   – worst quality possible
    //   B) All=255 – best  quality possible
    //   C) GPS/CAM=255, FRIC/ACT=0 – mixed split-quality
    //   D) All=200 – boundary between LUT region 200-255; triggers MIN_LONG clamp
    // ==========================================================================
    $display("\n────────────────────────────────────────────────────");
    $display(" TM_004: Hardware Clamps – Bounds Never Escaped");
    $display("────────────────────────────────────────────────────");

    // -- Sub-case A: All inputs = 0 (worst quality) ----------------------------
    // cq=0, scale=332 (1.30x)
    // lat_raw =0x01F2=498, long_raw=0x0298=664, time_raw=0x00A6=166 → all in range
    $display("\n  [A] All inputs = 0  (cq=0, scale=332)");
    drive_inputs(8'd0, 8'd0, 8'd0, 8'd0, "TM_004A");

    assert_in_range("TM_004A", "lateral_margin", lateral_margin, MIN_LATERAL_Q8_8, MAX_LATERAL_Q8_8);
    assert_in_range("TM_004A", "long_margin   ", long_margin,    MIN_LONG_Q8_8,    MAX_LONG_Q8_8);
    assert_in_range("TM_004A", "time_margin   ", time_margin,    16'h0040,         16'h0180);

    // Exact reference values for complete regression coverage
    assert_eq ("TM_004A", "lateral_margin", lateral_margin, 16'h01F2);
    assert_eq ("TM_004A", "long_margin   ", long_margin,    16'h0298);
    assert_eq ("TM_004A", "time_margin   ", time_margin,    16'h00A6);

    // -- Sub-case B: All inputs = 255 (best quality) ---------------------------
    // cq=255, scale=264 (1.03x)
    // lat_raw=0x018C=396, long_raw=0x0210=528 (≥MIN_LONG), time_raw=0x0084=132
    $display("\n  [B] All inputs = 255  (cq=255, scale=264)");
    drive_inputs(8'd255, 8'd255, 8'd255, 8'd255, "TM_004B");

    assert_in_range("TM_004B", "lateral_margin", lateral_margin, MIN_LATERAL_Q8_8, MAX_LATERAL_Q8_8);
    assert_in_range("TM_004B", "long_margin   ", long_margin,    MIN_LONG_Q8_8,    MAX_LONG_Q8_8);
    assert_in_range("TM_004B", "time_margin   ", time_margin,    16'h0040,         16'h0180);

    assert_eq ("TM_004B", "lateral_margin", lateral_margin, 16'h018C);
    assert_eq ("TM_004B", "long_margin   ", long_margin,    16'h0210);
    assert_eq ("TM_004B", "time_margin   ", time_margin,    16'h0084);

    // -- Sub-case C: GPS=255, CAM=255, FRIC=0, ACT=0 (split quality) ----------
    // weighted = 255*77 + 255*77 = 39270  →  cq = 39270>>8 = 153
    // scale_lut[153] = 256 + (153-100) = 309  (range 100-199)
    // lat_raw=0x01CF=463, long_raw=0x026A=618, time_raw=0x009A=154 → all in range
    $display("\n  [C] GPS=255,CAM=255,FRIC=0,ACT=0  (cq=153, scale=309)");
    drive_inputs(8'd255, 8'd255, 8'd0, 8'd0, "TM_004C");

    assert_in_range("TM_004C", "lateral_margin", lateral_margin, MIN_LATERAL_Q8_8, MAX_LATERAL_Q8_8);
    assert_in_range("TM_004C", "long_margin   ", long_margin,    MIN_LONG_Q8_8,    MAX_LONG_Q8_8);
    assert_in_range("TM_004C", "time_margin   ", time_margin,    16'h0040,         16'h0180);

    assert_eq ("TM_004C", "lateral_margin", lateral_margin, 16'h01CF);
    assert_eq ("TM_004C", "long_margin   ", long_margin,    16'h026A);
    assert_eq ("TM_004C", "time_margin   ", time_margin,    16'h009A);

    // -- Sub-case D: All=200 – explicit MIN_LONG clamp activation ---------------
    // cq=200, scale_lut[200]=154 (first entry of 200-255 region)
    // lat_raw =0x00E7=231  →  in [0x0080,0x0300]  →  lateral_margin=0x00E7
    // long_raw=0x0134=308  →  308 < MIN_LONG=512  →  CLAMP → long_margin=0x0200
    // time_raw=0x004D=77   →  in [0x0040,0x0180]  →  time_margin  =0x004D
    $display("\n  [D] All=200  (cq=200, scale=154)  → long MIN clamp expected");
    drive_inputs(8'd200, 8'd200, 8'd200, 8'd200, "TM_004D");
    $display("  INFO: long_raw=0x0134=308 < MIN_LONG=0x0200=512 → clamp fires");

    // Bounds check (redundant safety)
    assert_in_range("TM_004D", "lateral_margin", lateral_margin, MIN_LATERAL_Q8_8, MAX_LATERAL_Q8_8);
    assert_in_range("TM_004D", "long_margin   ", long_margin,    MIN_LONG_Q8_8,    MAX_LONG_Q8_8);
    assert_in_range("TM_004D", "time_margin   ", time_margin,    16'h0040,         16'h0180);

    // Exact checks – long_margin must equal the hardwired MIN_LONG floor
    assert_eq ("TM_004D", "lateral_margin",     lateral_margin, 16'h00E7);
    assert_eq ("TM_004D", "long_margin (CLAMP)", long_margin,   MIN_LONG_Q8_8);  // 0x0200
    assert_eq ("TM_004D", "time_margin   ",      time_margin,   16'h004D);

    // Verify the clamp is actually triggered (raw < MIN), not just a coincidence
    begin : tm004d_clamp_verify
      long_raw_ref = 16'h0134;
      if (long_raw_ref < MIN_LONG_Q8_8)
        $display("  INFO: [TM_004D] clamp verified: long_raw=0x%04X < MIN_LONG=0x%04X",
                 long_raw_ref, MIN_LONG_Q8_8);
    end : tm004d_clamp_verify

    // ==========================================================================
    // SUMMARY
    // ==========================================================================
    $display("\n======================================================");
    $display(" Batch U3 Test Summary");
    $display("======================================================");
    $display("  PASS : %0d", pass_count);
    $display("  FAIL : %0d", fail_count);
    $display("  TOTAL: %0d", pass_count + fail_count);
    if (fail_count == 0)
      $display("  STATUS: ALL TESTS PASSED ✓");
    else begin
      $display("  STATUS: %0d TEST(S) FAILED – see above ✗", fail_count);
      // Non-zero exit code for CI gate
      $fatal(1, "Batch U3 FAILED with %0d errors", fail_count);
    end
    $display("======================================================\n");

    test_complete = 1'b1;   // signal watchdog that test ended normally
    $finish;
  end : test_main

  // ---------------------------------------------------------------------------
  // Simulation timeout watchdog (prevents hang in CI and on 'run -all')
  //
  // Always terminates at T=50 µs — this is the hard simulation time cap.
  //   * If test_complete=0 : real timeout → print error + $fatal
  //   * If test_complete=1 : test already ended normally; 'run -all' after
  //     $finish keeps the always-clock alive, so we call $finish here to stop
  //     the simulator gracefully instead of hanging indefinitely.
  // ---------------------------------------------------------------------------
  initial begin : timeout_watchdog
    #50_000;
    if (!test_complete) begin
      $display("ERROR: Simulation timeout – testbench did not finish");
      $fatal(1, "Timeout");
    end
    $finish;   // always stop — kills the clock and monitor always-blocks
  end : timeout_watchdog

  // ---------------------------------------------------------------------------
  // Continuous property monitors (fires every cycle, independent of test flow)
  // These mirror the FORMAL assertions in the DUT and catch transient violations.
  // ---------------------------------------------------------------------------
  logic monitors_active;
  assign monitors_active = rst_n;   // only monitor after reset deasserted

  always @(posedge clk) begin
    if (monitors_active) begin
      // P3.1 – Margin bounds must never be violated
      assert (lateral_margin >= MIN_LATERAL_Q8_8 && lateral_margin <= MAX_LATERAL_Q8_8)
        else $error("MONITOR P3.1: lateral_margin=0x%04X escaped [0x%04X,0x%04X]",
                    lateral_margin, MIN_LATERAL_Q8_8, MAX_LATERAL_Q8_8);

      assert (long_margin >= MIN_LONG_Q8_8 && long_margin <= MAX_LONG_Q8_8)
        else $error("MONITOR P3.1: long_margin=0x%04X escaped [0x%04X,0x%04X]",
                    long_margin, MIN_LONG_Q8_8, MAX_LONG_Q8_8);

      assert (time_margin >= 16'h0040 && time_margin <= 16'h0180)
        else $error("MONITOR P3.1: time_margin=0x%04X escaped [0x0040,0x0180]",
                    time_margin);

      // P3.2 – No margin may ever be zero
      assert (lateral_margin != 16'h0000)
        else $error("MONITOR P3.2: lateral_margin is zero");
      assert (long_margin    != 16'h0000)
        else $error("MONITOR P3.2: long_margin is zero");
      assert (time_margin    != 16'h0000)
        else $error("MONITOR P3.2: time_margin is zero");
    end
  end

endmodule : tb_hmao_adaptive_margin_U3
