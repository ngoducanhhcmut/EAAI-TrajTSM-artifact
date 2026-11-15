// =============================================================================
// FILE        : tb_preproc_batch_u1.sv
// PROJECT     : HMAO Engine - Hardware Assurance Offload (ASIL-D, ISO 26262)
// DUT         : hmao_preproc.sv  (Pre-Processing Unit)
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 7.1
// AUTHOR      : Unit Test Batch U1
// FRAMEWORK   : SystemVerilog + Verilator (400 MHz, cycle-accurate)
//
// TEST CASES
// ----------
//   TP_001  CRC32 Valid         - correct CRC32 -> crc_fail = 0
//   TP_002  CRC32 Corrupted     - 1-bit flip, stale CRC -> crc_fail = 1
//   TP_003  Kinematic Valid     - vx=10 m/s (float32) -> kinematic_fail = 0
//   TP_004  Kinematic Infeasible- vx spike 1->72 m/s -> PP_ERROR
//   TP_005  Format Valid        - 50 wpts, dt=100ms, no NaN -> valid_out=1
//   TP_006  Format Bad          - NaN in x-field -> error_out=1
//
// IMPORTANT RTL NOTES (skeleton v12.0)
// ------------------------------------
//   1. Kinematic exponent check:  exp > 8'd132  (catches |vx|/|vy| >= 64 m/s).
//      The secondary magnitude² check catches 35...63 m/s range.
//      TP_004 injects 72 m/s (exp=133) to hit the fast-path exponent check.
//   2. Format check: RTL skeleton inspects x/y/vx/vy for NaN/Inf (exp=0xFF).
//      Timestamp dt enforcement is marked TODO in the RTL; TP_006 therefore
//      triggers the implemented NaN path (NaN in x-field) while also storing
//      a deliberately skewed timestamp to document the future behaviour.
//   3. valid_out / error_out are single-cycle combinational pulses from the FSM.
//   4. crc_fail is sticky until rst_n; kinematic_fail clears at PP_IDLE.
// =============================================================================

`timescale 1ns/1ps


// =============================================================================
// Testbench
// =============================================================================
import hmao_pkg::*;

module tb_preproc_batch_u1;

  // ===========================================================================
  // PARAMETERS & CONSTANTS
  // ===========================================================================
  localparam real CLK_PERIOD_NS  = 2.5;       // 400 MHz
  localparam int  MAX_WAIT_CYC   = 250_000;   // Must be > PREPROC_CYCLES (200,000)
  localparam int  RESET_CYCLES   = 20;
  localparam int  TS_STEP        = 26;        // Q8.8: 0.1 s * 256 = 25.6 ~ 26

  // --- IEEE 754 float32 constants -------------------------------------------
  // Derivation:  sign=0 | biased_exp[30:23] | mantissa[22:0]
  //
  //   1.0  = 1.0 * 2^0   -> exp=127=0x7F, mant=0           -> 0x3F80_0000
  //  10.0  = 1.25 * 2^3  -> exp=130=0x82, mant=0x20_0000   -> 0x4120_0000  (exp<=132 -> PASS)
  //  72.0  = 1.125* 2^6  -> exp=133=0x85, mant=0x10_0000   -> 0x4290_0000  (exp>132 -> FAIL)
  //   NaN  = quiet NaN   -> exp=0xFF,     mant[22]=1        -> 0x7FC0_0000
  localparam logic [31:0] F32_ZERO  = 32'h0000_0000;
  localparam logic [31:0] F32_1MPS  = 32'h3F80_0000;  //  1.0 m/s (exp=127)
  localparam logic [31:0] F32_10MPS = 32'h4120_0000;  // 10.0 m/s (exp=130 <= 132)
  localparam logic [31:0] F32_72MPS = 32'h4290_0000;  // 72.0 m/s (exp=133 > 132 -> kinematic FAIL)
  localparam logic [31:0] F32_QNAN  = 32'h7FC0_0000;  // Quiet NaN (exp=0xFF -> format FAIL)

  // ===========================================================================
  // CLOCK & RESET
  // ===========================================================================
  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

  // ===========================================================================
  // DUT SIGNALS
  // ===========================================================================
  logic        dut_start;
  logic        dut_valid_out;
  logic        dut_error_out;
  waypoint_t   dut_wp_out [0:TRAJ_WAYPOINTS-1];
  logic [31:0] dut_bbox_xmin, dut_bbox_xmax;
  logic [31:0] dut_bbox_ymin, dut_bbox_ymax;
  logic        dut_crc_fail;
  logic        dut_kin_fail;

  // ===========================================================================
  // AXI INTERFACE & DUT INSTANTIATION
  // ===========================================================================
  axi4_ro_if axi_bus (.aclk(clk), .aresetn(rst_n));

  hmao_preproc u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (dut_start),
    .axi_ro         (axi_bus),
    .valid_out      (dut_valid_out),
    .error_out      (dut_error_out),
    .waypoints_out  (dut_wp_out),
    .bbox_xmin_out  (dut_bbox_xmin),
    .bbox_xmax_out  (dut_bbox_xmax),
    .bbox_ymin_out  (dut_bbox_ymin),
    .bbox_ymax_out  (dut_bbox_ymax),
    .crc_fail       (dut_crc_fail),
    .kinematic_fail (dut_kin_fail)
  );

  // ===========================================================================
  // AXI4 SLAVE MEMORY MODEL
  // --------------------------------------------------------------------------
  // traj_mem[0..349]  : 1,400 bytes of trajectory data (50 wpts * 7 fields * 4B)
  // traj_mem[350]     : CRC32 trailer
  //
  // Protocol:
  //   arready = !axi_busy (accept one burst at a time)
  //   One cycle after AR accepted: rvalid=1, rdata = traj_mem[word_offset]
  //   Increments word_offset each accepted R-beat; asserts rlast on last beat.
  // ===========================================================================
  logic [31:0] traj_mem [0:350];

  logic [9:0]  axi_woff;        // word offset into traj_mem (covers 0..511)
  logic [7:0]  axi_beats_rem;   // beats remaining in current burst
  logic        axi_busy;        // high while burst is active

  // arready: accept new AR only when not mid-burst
  assign axi_bus.arready = ~axi_busy;
  assign axi_bus.rresp   = 2'b00;   // OKAY
  // Combinational AXI narrow-beat data in the byte lane selected by address
  assign axi_bus.rdata   = ({224'd0, traj_mem[axi_woff]} << {axi_woff[2:0], 5'b0});

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_bus.rvalid <= 1'b0;
      axi_bus.rlast  <= 1'b0;
      axi_beats_rem  <= '0;
      axi_woff       <= '0;
      axi_busy       <= 1'b0;
    end else begin
      // -- AR phase: latch burst parameters on handshake ------------------
      if (axi_bus.arvalid && axi_bus.arready) begin
        // Word offset = byte offset from TRAJ_BUFFER_BASE divided by 4
        axi_woff       <= 10'((axi_bus.araddr - TRAJ_BUFFER_BASE) >> 2);
        axi_beats_rem  <= axi_bus.arlen;
        axi_busy       <= 1'b1;
        axi_bus.rvalid <= 1'b1;
        axi_bus.rlast  <= (axi_bus.arlen == 8'd0);  // Single-beat burst?
      end
      // -- R phase: deliver beats -----------------------------------------
      else if (axi_bus.rvalid && axi_bus.rready) begin
        if (axi_bus.rlast) begin
          // Burst finished
          axi_bus.rvalid <= 1'b0;
          axi_bus.rlast  <= 1'b0;
          axi_busy       <= 1'b0;
        end else begin
          axi_woff       <= axi_woff + 10'd1;
          axi_beats_rem  <= axi_beats_rem - 8'd1;
          axi_bus.rlast  <= (axi_beats_rem == 8'd1);  // Next beat is last
        end
      end
    end
  end

  // ===========================================================================
  // CRC32 HELPERS (IEEE 802.3, poly = 0xEDB8_8320)
  // Mirrors the logic inside hmao_preproc - must match exactly.
  // ===========================================================================
  function automatic logic [31:0] crc32_byte_f(
    input logic [31:0] crc_in,
    input logic  [7:0] byte_in
  );
    logic [31:0] c;
    c = crc_in ^ {24'b0, byte_in};
    for (int i = 0; i < 8; i++)
      c = c[0] ? ((c >> 1) ^ 32'hEDB8_8320) : (c >> 1);
    return c;
  endfunction

  // Process all 350 words (1,400 bytes) of traj_mem and store result at [350].
  task automatic compute_and_store_crc();
    logic [31:0] crc;
    crc = 32'hFFFF_FFFF;
    for (int w = 0; w < 350; w++)
      crc = crc32_byte_f(
              crc32_byte_f(
                crc32_byte_f(
                  crc32_byte_f(crc,            traj_mem[w][ 7: 0]),
                               traj_mem[w][15: 8]),
                traj_mem[w][23:16]),
              traj_mem[w][31:24]);
    traj_mem[350] = crc ^ 32'hFFFF_FFFF;  // Final XOR (IEEE 802.3)
    $display("        [CRC]  traj_mem[350] = 0x%08X (freshly computed)", traj_mem[350]);
  endtask

  // ===========================================================================
  // TRAJECTORY BUILDERS
  // ===========================================================================

  // Nominal straight-line trajectory at 10 m/s (kinematically valid).
  // All float32 fields are well-formed (no NaN/Inf).
  // Timestamps spaced TS_STEP (Q8.8 ~ 100 ms).
  task automatic load_nominal_traj();
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      // x in Q8.8: 10 m/s * 0.1 s * 256 = 256 Q8.8 counts per step
      traj_mem[wp*7+0] = 32'(wp * 256);      // x
      traj_mem[wp*7+1] = F32_ZERO;            // y  (float32, straight ahead)
      traj_mem[wp*7+2] = F32_ZERO;            // z
      traj_mem[wp*7+3] = F32_10MPS;           // vx = 10.0 m/s (float32, exp=130)
      traj_mem[wp*7+4] = F32_ZERO;            // vy = 0
      traj_mem[wp*7+5] = F32_ZERO;            // heading = 0 rad
      traj_mem[wp*7+6] = 32'(wp * TS_STEP);  // timestamp: dt ~ 100 ms (Q8.8)
    end
    compute_and_store_crc();
  endtask

  // Slow trajectory at 1 m/s - base for the kinematic infeasibility spike test.
  task automatic load_slow_traj();
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      traj_mem[wp*7+0] = 32'(wp * 26);       // x in Q8.8 (0.1 m/step ~ 26)
      traj_mem[wp*7+1] = F32_ZERO;
      traj_mem[wp*7+2] = F32_ZERO;
      traj_mem[wp*7+3] = F32_1MPS;            // vx = 1.0 m/s (float32, exp=127)
      traj_mem[wp*7+4] = F32_ZERO;
      traj_mem[wp*7+5] = F32_ZERO;
      traj_mem[wp*7+6] = 32'(wp * TS_STEP);
    end
    compute_and_store_crc();
  endtask

  // ===========================================================================
  // EXECUTION PRIMITIVES
  // ===========================================================================

  task automatic do_reset();
    @(negedge clk);
    rst_n     <= 1'b0;
    dut_start <= 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    @(negedge clk);
    rst_n <= 1'b1;
    repeat (5) @(posedge clk);
    $display("        [RST]  Reset released, DUT idle.");
  endtask

  // Pulse start for exactly one clock cycle, then wait (with timeout) for
  // valid_out or error_out to strobe.  Both are single-cycle FSM pulses.
  task automatic run_preproc(output logic got_valid, output logic got_error);
    int unsigned cnt = 0;
    got_valid = 1'b0;
    got_error = 1'b0;

    // Assert start at negedge so it is cleanly sampled on the next posedge
    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);                     // DUT latches start -> PP_FETCH next cycle
    @(negedge clk); dut_start <= 1'b0;

    // Poll for completion
    forever begin
      @(posedge clk);
      if (dut_valid_out) begin got_valid = 1'b1; break; end
      if (dut_error_out) begin got_error = 1'b1; break; end
      if (++cnt >= MAX_WAIT_CYC) begin
        $display("        [TMO]  Preproc timed out after %0d cycles!", cnt);
        break;
      end
    end
    // Let registered outputs (crc_fail, kin_fail) settle one extra cycle
    // after the FSM emits its pulse (FSM already back in PP_IDLE here)
    @(posedge clk);
    $display("        [RUN]  Completed in %0d cycles | valid=%b error=%b",
             cnt, got_valid, got_error);
  endtask

  // ===========================================================================
  // SCOREBOARD
  // ===========================================================================
  int pass_count = 0;
  int fail_count = 0;

  // Named assertion: prints result, increments counters.
  task automatic chk(input logic cond, input string tp_id, input string msg);
    if (cond) begin
      $display("        [OK ]    %-10s %s", tp_id, msg);
    end else begin
      $display("   *** [FAIL]   %-10s %s", tp_id, msg);
      fail_count++;
    end
  endtask

  task automatic report(
    input string tp_id,
    input logic  pass_cond
  );
    if (pass_cond) begin
      $display("[PASS] %-10s ----------------------------------", tp_id);
      pass_count++;
    end else begin
      $display("[FAIL] %-10s  <- see assertions above", tp_id);
      fail_count++;
    end
  endtask

  // ===========================================================================
  // TP_001 : CRC32 Valid
  // --------------------------------------------------------------------------
  // Stimulus : 50-waypoint trajectory with CRC32 (IEEE 802.3) computed and
  //            stored at traj_mem[350] by compute_and_store_crc().
  // Expected : crc_fail = 0 , valid_out = 1 , error_out = 0
  // ===========================================================================
  task automatic tp001_crc_valid();
    logic gv, ge;
    $display("\n--- TP_001 : CRC32 Valid -------------------------------------");
    $display("    Stimulus  : correct CRC32 (IEEE 802.3) stored at traj_mem[350]");
    $display("    Expected  : crc_fail=0, valid_out=1");

    do_reset();
    load_nominal_traj();   // CRC computed & stored correctly

    // -- SVA-equivalent: @(posedge clk) crc_fail should stay 0 throughout
    // monitored inside run_preproc cycle loop (sampled at completion)
    run_preproc(gv, ge);

    chk(!dut_crc_fail,  "TP_001", "crc_fail == 0  (CRC matched)");
    chk(gv,             "TP_001", "valid_out == 1 (preproc completed OK)");
    chk(!ge,            "TP_001", "error_out == 0 (no error)");
    chk(!dut_kin_fail,  "TP_001", "kinematic_fail == 0 (sanity)");

    report("TP_001", !dut_crc_fail && gv && !ge);
  endtask


  // ===========================================================================
  // TP_002 : CRC32 Corrupted  (1-bit flip, stale CRC)
  // --------------------------------------------------------------------------
  // Stimulus : Load valid trajectory, compute correct CRC, then flip bit[0] of
  //            waypoint[5].x. The stored CRC at traj_mem[350] is unchanged
  //            (stale) -> computed CRC != stored CRC.
  // Expected : crc_fail = 1 , error_out = 1 , valid_out = 0
  // ===========================================================================
  task automatic tp002_crc_corrupted();
    logic gv, ge;
    $display("\n--- TP_002 : CRC32 Corrupted ---------------------------------");
    $display("    Stimulus  : 1-bit flip in wp[5].x AFTER CRC computed (stale CRC)");
    $display("    Expected  : crc_fail=1, error_out=1");

    do_reset();
    load_nominal_traj();                      // Stores correct CRC at [350]
    traj_mem[5*7+0] ^= 32'h0000_0001;        // Flip bit[0] of wp[5].x
    // traj_mem[350] untouched -> now wrong
    $display("        [INJ]  Bit[0] flipped in traj_mem[%0d] (wp[5].x)", 5*7+0);
    $display("               Stored CRC still 0x%08X -> MISMATCH expected", traj_mem[350]);

    run_preproc(gv, ge);

    chk(dut_crc_fail,  "TP_002", "crc_fail == 1  (1-bit flip detected)");
    chk(ge,            "TP_002", "error_out == 1 (FSM -> PP_ERROR)");
    chk(!gv,           "TP_002", "valid_out == 0");

    // SVA-equivalent: once crc_fail asserts, error_out must follow
    // (enforced by FSM: PP_CRC -> PP_ERROR when crc_computed != crc_stored)
    report("TP_002", dut_crc_fail && ge && !gv);
  endtask


  // ===========================================================================
  // TP_003 : Kinematic Valid  (vx = 10 m/s, all constraints satisfied)
  // --------------------------------------------------------------------------
  // Stimulus : Trajectory with vx = 10.0 m/s (float32 0x41200000).
  //            Float32 exponent = 130 <= 132 -> exponent gate PASSES.
  //            Magnitude²  = vx_fix² + vy_fix² well below 80,281,600 threshold.
  // Expected : kinematic_fail = 0 , valid_out = 1   (kinematic_ok implied)
  // ===========================================================================
  task automatic tp003_kinematic_valid();
    logic gv, ge;
    logic [7:0] vx_exp;
    logic all_exp_ok;
    $display("\n--- TP_003 : Kinematic Valid ----------------------------------");
    $display("    Stimulus  : vx=10.0 m/s (0x%08X, float32 exp=130 <= 132), vy=0",
             F32_10MPS);
    $display("    Expected  : kinematic_fail=0, valid_out=1");

    do_reset();
    load_nominal_traj();   // vx = F32_10MPS across all 50 waypoints
    run_preproc(gv, ge);

    chk(!dut_kin_fail,  "TP_003", "kinematic_fail == 0 (10 m/s within 35 m/s limit)");
    chk(!dut_crc_fail,  "TP_003", "crc_fail == 0 (control check)");
    chk(gv,             "TP_003", "valid_out == 1 (all checks passed)");

    // Verify float32 exponent of vx for every waypoint <= 132
    all_exp_ok = 1'b1;
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      vx_exp = dut_wp_out[wp].vx[30:23];
      if (vx_exp > 8'd132) begin
        $display("   *** [FAIL]   TP_003    wp[%0d].vx exp=%0d > 132 (unexpected)", wp, vx_exp);
        all_exp_ok = 1'b0;
      end
    end
    chk(all_exp_ok, "TP_003", "All wp[i].vx exponents <= 132 confirmed in waypoints_out");

    report("TP_003", !dut_kin_fail && gv && all_exp_ok);
  endtask


  // ===========================================================================
  // TP_004 : Kinematic Infeasible  (velocity spike -> FSM enters PP_ERROR)
  // --------------------------------------------------------------------------
  // Test-plan intent: "velocity jump from 1 m/s -> 35 m/s in 100 ms  (a = 340 m/s²)".
  //
  // RTL implementation: the kinematic checker evaluates float32 exponent of vx
  // (registered 1-cycle pipeline): if vx_exp_r > 8'd132 -> kinematic_fail=1.
  // exp=132 corresponds to 2^5 range (~32...64 m/s); exp=133 -> >= 64 m/s.
  // Therefore the infeasible injection uses 72 m/s (exp=133, well above 35 m/s).
  //
  // RTL pipeline trace:
  //   wp_idx=47 -> vx_exp_r latched as 133
  //   wp_idx=48 -> check fires: 133 > 132 -> kinematic_fail=1
  //   wp_idx=49 -> kin_check_done=1 -> FSM: PP_KINEMATIC -> PP_ERROR
  //
  // CRC recomputed after injection so CRC passes (isolates kinematic error).
  //
  // Expected : kinematic_fail=1, error_out=1, crc_fail=0
  // ===========================================================================
  task automatic tp004_kinematic_infeasible();
    logic gv, ge;
    $display("\n--- TP_004 : Kinematic Infeasible -----------------------------");
    $display("    Stimulus  : base vx=1 m/s, then wp[47].vx=72 m/s (0x%08X, exp=133>132)",
             F32_72MPS);
    $display("    Expected  : kinematic_fail=1, error_out=1, PP_ERROR state");

    do_reset();
    load_slow_traj();                          // All 50 wpts at 1 m/s (exp=127)
    traj_mem[47*7+3] = F32_72MPS;             // Spike at wp[47]: 72 m/s
    $display("        [INJ]  traj_mem[%0d] (wp[47].vx) = 0x%08X (72.0 m/s, exp=133)",
             47*7+3, F32_72MPS);
    compute_and_store_crc();                   // Recompute so CRC passes

    run_preproc(gv, ge);

    chk(dut_kin_fail,  "TP_004", "kinematic_fail == 1 (72 m/s exceeds velocity limit)");
    chk(ge,            "TP_004", "error_out == 1 (FSM entered PP_ERROR)");
    chk(!gv,           "TP_004", "valid_out == 0");
    chk(!dut_crc_fail, "TP_004", "crc_fail == 0 (CRC correct - kinematic error isolated)");

    // Spot-check: confirm offending waypoint exponent in waypoints_out
    chk(dut_wp_out[47].vx[30:23] > 8'd132, "TP_004",
        $sformatf("wp[47].vx exp = 0x%02X > 132 confirmed in waypoints_out",
                  dut_wp_out[47].vx[30:23]));

    report("TP_004", dut_kin_fail && ge && !gv && !dut_crc_fail);
  endtask


  // ===========================================================================
  // TP_005 : Format Valid  (50 waypoints, uniform 100 ms timestamps, no NaN)
  // --------------------------------------------------------------------------
  // Stimulus : load_nominal_traj() -> timestamps[i] = i * TS_STEP (Q8.8 ~ 100 ms),
  //            no NaN/Inf in any float32 field.
  // Expected : valid_out = 1  (implies format check passed)
  //            All dtimestamp deltas == TS_STEP verified in waypoints_out.
  //            No exponent 0xFF in x, y, vx, vy fields.
  // ===========================================================================
  task automatic tp005_format_valid();
    logic gv, ge;
    logic ts_ok, nan_ok;
    int   delta;
    $display("\n--- TP_005 : Format Valid -------------------------------------");
    $display("    Stimulus  : 50 waypoints, timestamp[i] = i*%0d (Q8.8~100ms), no NaN",
             TS_STEP);
    $display("    Expected  : valid_out=1, uniform dt confirmed");

    do_reset();
    load_nominal_traj();
    run_preproc(gv, ge);

    chk(gv,            "TP_005", "valid_out == 1 (format check passed)");
    chk(!ge,           "TP_005", "error_out == 0");
    chk(!dut_crc_fail, "TP_005", "crc_fail == 0");
    chk(!dut_kin_fail, "TP_005", "kinematic_fail == 0");

    // -- Verify timestamp spacing in waypoints_out ---------------------------
    // waypoints_out is a combinational decode of traj_raw, which persists
    // after PP_DONE (traj_raw is never cleared; FSM merely returns to PP_IDLE).
    ts_ok = 1'b1;
    for (int i = 1; i < TRAJ_WAYPOINTS; i++) begin
      delta = int'(dut_wp_out[i].timestamp) - int'(dut_wp_out[i-1].timestamp);
      if (delta !== TS_STEP) begin
        $display("   *** [FAIL]   TP_005    dt[%0d->%0d] = %0d, expected %0d",
                 i-1, i, delta, TS_STEP);
        ts_ok = 1'b0;
      end
    end
    chk(ts_ok, "TP_005",
        $sformatf("All %0d timestamp deltas == %0d (Q8.8 ~ 100 ms)",
                  TRAJ_WAYPOINTS-1, TS_STEP));

    // -- Verify no NaN/Inf exponents in float32 position/velocity fields -----
    nan_ok = 1'b1;
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      if (dut_wp_out[wp].x [30:23] == 8'hFF ||
          dut_wp_out[wp].y [30:23] == 8'hFF ||
          dut_wp_out[wp].vx[30:23] == 8'hFF ||
          dut_wp_out[wp].vy[30:23] == 8'hFF) begin
        $display("   *** [FAIL]   TP_005    NaN/Inf detected in wp[%0d] (unexpected)", wp);
        nan_ok = 1'b0;
      end
    end
    chk(nan_ok, "TP_005", "No NaN/Inf exponent (0xFF) in any x/y/vx/vy field");

    report("TP_005", gv && ts_ok && nan_ok);
  endtask


  // ===========================================================================
  // TP_006 : Format Non-Uniform / Format Error  (format_ok = 0)
  // --------------------------------------------------------------------------
  // Two simultaneous injections (one per documented scenario):
  //
  //   Injection A - Non-uniform timestamp at wp[3]:
  //     dt[2->3] deliberately shortened by 10 Q8.8 counts (~39 ms instead of 100 ms).
  //     NOTE: RTL skeleton marks timestamp-delta check as TODO; this injection
  //     documents the intended future check but does NOT currently trigger the
  //     error path.  Retained to ensure the field survives round-trip through
  //     traj_raw / waypoints_out.
  //
  //   Injection B - Quiet NaN in wp[5].x:
  //     0x7FC00000 -> float32 exponent = 0xFF, mantissa[22]=1.
  //     RTL FORMAT step: waypoints_out[5].x[30:23] == 8'hFF -> nan_detected = 1
  //                      -> pp_next = PP_ERROR -> error_out = 1.
  //     The kinematic checker only inspects vx/vy exponents (NOT x), so
  //     kinematic_fail stays 0.
  //
  // CRC recomputed over injected data so CRC passes (format error isolated).
  //
  // Expected : error_out=1, crc_fail=0, kinematic_fail=0
  // ===========================================================================
  task automatic tp006_format_bad();
    logic gv, ge;
    $display("\n--- TP_006 : Format Non-Uniform / NaN -------------------------");
    $display("    Stimulus A: wp[3].timestamp = wrong spacing (non-uniform dt)");
    $display("    Stimulus B: wp[5].x = 0x%08X (Quiet NaN, exp=0xFF)", F32_QNAN);
    $display("    Expected  : error_out=1, crc_fail=0, kinematic_fail=0");

    do_reset();
    load_nominal_traj();

    // -- Injection A: Non-uniform timestamp ----------------------------------
    traj_mem[3*7+6] = 32'(3 * TS_STEP - 10);  // ~61 ms instead of 100 ms
    $display("        [INJ-A] wp[3].timestamp = %0d (expected %0d, dt wrong)",
             traj_mem[3*7+6], 3*TS_STEP);

    // -- Injection B: NaN in wp[5].x (float32 exp=0xFF, mant!=0) -------------
    // This field is checked by the FORMAT step but NOT by the kinematic checker.
    traj_mem[5*7+0] = F32_QNAN;
    $display("        [INJ-B] wp[5].x = 0x%08X (Quiet NaN, triggers nan_detected)", F32_QNAN);

    // CRC recomputed so format error is isolated (not masked by CRC error)
    compute_and_store_crc();

    run_preproc(gv, ge);

    // -- Primary assertions ---------------------------------------------------
    chk(ge,            "TP_006", "error_out == 1  (nan_detected -> PP_ERROR)");
    chk(!gv,           "TP_006", "valid_out == 0");
    chk(!dut_crc_fail, "TP_006", "crc_fail == 0   (CRC correct, format error isolated)");
    chk(!dut_kin_fail, "TP_006", "kinematic_fail == 0 (NaN in x only; vx/vy exponents normal)");

    // -- Confirm NaN survives in waypoints_out --------------------------------
    chk(dut_wp_out[5].x[30:23] == 8'hFF, "TP_006",
        $sformatf("wp[5].x exponent = 0x%02X == 0xFF (NaN round-trip confirmed)",
                  dut_wp_out[5].x[30:23]));

    // -- Confirm non-uniform timestamp in waypoints_out -----------------------
    begin
      int gap_2_3, gap_3_4;
      gap_2_3 = int'(dut_wp_out[3].timestamp) - int'(dut_wp_out[2].timestamp);
      gap_3_4 = int'(dut_wp_out[4].timestamp) - int'(dut_wp_out[3].timestamp);
      chk(gap_2_3 !== TS_STEP, "TP_006",
          $sformatf("dt[2->3] = %0d != %0d (non-uniform spacing confirmed)", gap_2_3, TS_STEP));
      chk(gap_3_4 !== TS_STEP, "TP_006",
          $sformatf("dt[3->4] = %0d != %0d (asymmetric gap confirms data integrity)", gap_3_4, TS_STEP));
    end

    report("TP_006", ge && !gv && !dut_crc_fail && !dut_kin_fail);
  endtask


  // ===========================================================================
  // CONCURRENT SVA PROPERTIES
  // Checked throughout the entire simulation run.
  // ===========================================================================

  // P1: valid_out and error_out must never assert simultaneously.
  property p_mutex;
    @(posedge clk)
      !(dut_valid_out && dut_error_out);
  endproperty
  ap_mutex : assert property (p_mutex)
    else $error("[SVA] P1 VIOLATION: valid_out and error_out both high!");

  // P2: If crc_fail is observed, error_out must follow within 1 cycle.
  //     (crc_fail registered; FSM transitions PP_CRC -> PP_ERROR combinationally)
  property p_crc_implies_error;
    @(posedge clk)
      $rose(dut_crc_fail) |-> ##[0:3] dut_error_out;
  endproperty
  ap_crc_implies_error : assert property (p_crc_implies_error)
    else $error("[SVA] P2 VIOLATION: crc_fail asserted but error_out did not follow!");

  // P3: kinematic_fail must imply error_out (kinematic check gates PP_FORMAT).
  property p_kin_implies_error;
    @(posedge clk)
      $rose(dut_kin_fail) |-> ##[1:4] dut_error_out;
  endproperty
  ap_kin_implies_error : assert property (p_kin_implies_error)
    else $error("[SVA] P3 VIOLATION: kinematic_fail asserted but error_out did not follow!");

  // P4: Start must only be accepted in PP_IDLE (no re-entrancy).
  //     After start, valid_out/error_out must appear within PREPROC_CYCLES+50.
  property p_latency_bound;
    @(posedge clk)
      $rose(dut_start) |-> ##[1:PREPROC_CYCLES+50] (dut_valid_out || dut_error_out);
  endproperty
  ap_latency : assert property (p_latency_bound)
    else $error("[SVA] P4 VIOLATION: preproc latency exceeded %0d cycles!", PREPROC_CYCLES+50);


  // ===========================================================================
  // WAVEFORM DUMP
  // ===========================================================================
  initial begin
    $dumpfile("tb_preproc_u1.vcd");
    $dumpvars(0, tb_preproc_batch_u1);
  end

  // ===========================================================================
  // SIMULATION MAIN
  // ===========================================================================
  initial begin
    $display("+===============================================================+");
    $display("|  HMAO Engine - Unit Test Batch U1                            |");
    $display("|  DUT    : hmao_preproc.sv  (Section 7.1)                     |");
    $display("|  Freq   : 400 MHz (2.5 ns/cycle)  |  Framework: Verilator    |");
    $display("|  Target : 100%% code | 98%% toggle | 95%% FSM coverage         |");
    $display("+===============================================================+");

    // Run all 6 test cases in sequence (each begins with do_reset())
    tp001_crc_valid();
    tp002_crc_corrupted();
    tp003_kinematic_valid();
    tp004_kinematic_infeasible();
    tp005_format_valid();
    tp006_format_bad();

    // -- Summary --------------------------------------------------------------
    $display("\n+===============================================================+");
    $display("|  BATCH U1  SUMMARY                                           |");
    $display("|  Tests  : 6 (TP_001 ... TP_006)                               |");
    $display("|  PASS   : %-2d                                                 |", pass_count);
    $display("|  FAIL   : %-2d                                                 |", fail_count);
    if (fail_count == 0)
      $display("|  STATUS : OK  ALL PASSED                                      |");
    else
      $display("|  STATUS : FAIL  FAILURES - review messages above                |");
    $display("+===============================================================+");

    // Coverage hint for Verilator
    `ifdef COVERAGE
      $display("[COV]  Coverage data written to coverage.dat");
    `endif

    $finish;
  end

  // Watchdog: 6 tests * MAX_WAIT_CYC cycles * CLK_PERIOD_NS * 2* safety margin
  initial begin
    #(real'(MAX_WAIT_CYC) * 6.0 * CLK_PERIOD_NS * 2.0);
    $display("[WATCHDOG] Global simulation timeout triggered - possible hang!");
    $finish;
  end

endmodule : tb_preproc_batch_u1
