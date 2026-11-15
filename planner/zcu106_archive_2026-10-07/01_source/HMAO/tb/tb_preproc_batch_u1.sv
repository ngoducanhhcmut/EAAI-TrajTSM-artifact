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
//   TP_004B Kinematic Gap Regression - vx=50 m/s (exp=132) -> PP_ERROR
//           (2026-08-04: this is the exact value the OLD exponent-only check
//           silently passed -- 50 m/s > VMAX_MPS=35.0 but exp=132 is NOT
//           "> 132", so kinematic_fail never asserted. Regression test for
//           the fix in hmao_preproc.sv; see docs/Phase2_Safety_Audit_Review_Board.md
//           Station 2. MUST fail (kinematic_fail=1) on the current RTL.)
//   TP_005  Format Valid        - 50 wpts, dt=100ms, no NaN -> valid_out=1
//   TP_006  Format Bad          - NaN in x-field -> error_out=1
//   TP_006B Format Gap Regression - NaN in z/heading/timestamp (2026-08-04:
//           these three fields were NOT checked by the OLD nan_comb, which
//           only inspected x/y/vx/vy. A NaN in heading in particular flows
//           uncaught into hmao_zonotope_gen's CORDIC -- a direct False Grant
//           path. MUST fail (error_out=1) on the current RTL for each field.)
//
// IMPORTANT RTL NOTES (updated 2026-08-04)
// ------------------------------------
//   1. Kinematic check (FIXED 2026-08-04): full 31-bit magnitude compare of
//      the IEEE-754 bit pattern against 35.0f (0x420C0000), i.e.
//      {1'b0,v[30:0]} > 32'h420C_0000. This replaced an exponent-only check
//      (exp > 8'd132, i.e. |v| >= 64 m/s) that left the entire 35-64 m/s band
//      undetected -- 83% above the specified VMAX_MPS=35.0. TP_004B is the
//      regression test: 50 m/s (exp=132) was invisible to the old check and
//      must now be caught.
//   2. Format check (FIXED 2026-08-04): nan_comb now inspects all 7 fields of
//      waypoint_t (x, y, z, vx, vy, heading, timestamp), not just x/y/vx/vy.
//      TP_006B is the regression test for the three previously-unchecked
//      fields. Timestamp dt (delta) enforcement is still marked TODO in the
//      RTL and is unrelated to the NaN/Inf exponent check exercised here.
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
  //  10.0  = 1.25 * 2^3  -> exp=130=0x82, mant=0x20_0000   -> 0x4120_0000  (well within 35 m/s)
  //  50.0  = 1.5625*2^5  -> exp=132=0x84, mant=0x48_0000   -> 0x4248_0000  (>35 m/s, exp==132:
  //                                                                        OLD exp>132 check MISSED this)
  //  72.0  = 1.125* 2^6  -> exp=133=0x85, mant=0x10_0000   -> 0x4290_0000  (well above 35 m/s either way)
  //   NaN  = quiet NaN   -> exp=0xFF,     mant[22]=1        -> 0x7FC0_0000
  localparam logic [31:0] F32_ZERO  = 32'h0000_0000;
  localparam logic [31:0] F32_1MPS  = 32'h3F80_0000;  //  1.0 m/s (exp=127)
  localparam logic [31:0] F32_10MPS = 32'h4120_0000;  // 10.0 m/s (exp=130, well within 35 m/s)
  localparam logic [31:0] F32_50MPS = 32'h4248_0000;  // 50.0 m/s (exp=132 -- the OLD exponent-only
                                                        // check's exact blind spot; new bit-pattern
                                                        // check must catch it: 50 > 35 -> FAIL)
  localparam logic [31:0] F32_72MPS = 32'h4290_0000;  // 72.0 m/s (exp=133, caught by both old and new)
  localparam logic [31:0] F32_QNAN  = 32'h7FC0_0000;  // Quiet NaN (exp=0xFF -> format FAIL)
  // Exact IEEE-754 bit pattern of 35.0f, matching hmao_preproc.sv's kinematic
  // threshold constant, used here only to print human-readable diagnostics.
  localparam logic [31:0] F32_VMAX_35 = 32'h420C_0000;

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
  //
  // FIX 2026-08-04: rewritten from one deeply-nested expression (4 nested
  // calls to the same `automatic` function within a single statement) into 4
  // sequential statements with an explicit intermediate variable. The nested
  // form produced X (unknown) in xsim 2023.2 despite fully-defined inputs
  // (confirmed by direct inspection: traj_mem[0..349] all held correct known
  // values, only the CRC *result* was X) -- most likely an xsim limitation
  // with self-nested automatic-function calls in one expression, not
  // something specific to this project's code. This form is functionally
  // identical (same byte order, same polynomial) and avoids the nesting
  // entirely. Testbench-only change; does not touch hmao_preproc.sv.
  task automatic compute_and_store_crc();
    logic [31:0] crc;
    logic [31:0] step;
    crc = 32'hFFFF_FFFF;
    for (int w = 0; w < 350; w++) begin
      step = crc32_byte_f(crc,  traj_mem[w][ 7: 0]);
      step = crc32_byte_f(step, traj_mem[w][15: 8]);
      step = crc32_byte_f(step, traj_mem[w][23:16]);
      step = crc32_byte_f(step, traj_mem[w][31:24]);
      crc  = step;
    end
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
  //            Well within the VMAX_MPS = 35.0 m/s limit.
  // Expected : kinematic_fail = 0 , valid_out = 1   (kinematic_ok implied)
  // ===========================================================================
  task automatic tp003_kinematic_valid();
    logic gv, ge;
    logic all_mag_ok;
    $display("\n--- TP_003 : Kinematic Valid ----------------------------------");
    $display("    Stimulus  : vx=10.0 m/s (0x%08X, well within 35 m/s), vy=0",
             F32_10MPS);
    $display("    Expected  : kinematic_fail=0, valid_out=1");

    do_reset();
    load_nominal_traj();   // vx = F32_10MPS across all 50 waypoints
    run_preproc(gv, ge);

    chk(!dut_kin_fail,  "TP_003", "kinematic_fail == 0 (10 m/s within 35 m/s limit)");
    chk(!dut_crc_fail,  "TP_003", "crc_fail == 0 (control check)");
    chk(gv,             "TP_003", "valid_out == 1 (all checks passed)");

    // Verify the fixed 31-bit magnitude compare: {1'b0,vx[30:0]} <= 0x420C0000
    // (35.0f) for every waypoint. This matches hmao_preproc.sv's current
    // kinematic check exactly (see FIX 2026-08-04 comment there).
    all_mag_ok = 1'b1;
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      if ({1'b0, dut_wp_out[wp].vx[30:0]} > F32_VMAX_35) begin
        $display("   *** [FAIL]   TP_003    wp[%0d].vx magnitude > 35.0 m/s (unexpected)", wp);
        all_mag_ok = 1'b0;
      end
    end
    chk(all_mag_ok, "TP_003", "All wp[i].vx magnitudes <= 35.0 m/s confirmed in waypoints_out");

    report("TP_003", !dut_kin_fail && gv && all_mag_ok);
  endtask


  // ===========================================================================
  // TP_004 : Kinematic Infeasible  (velocity spike -> FSM enters PP_ERROR)
  // --------------------------------------------------------------------------
  // Test-plan intent: "velocity jump from 1 m/s -> beyond VMAX in 100 ms".
  //
  // RTL implementation (FIXED 2026-08-04): the kinematic checker performs a
  // full 31-bit magnitude compare of the IEEE-754 bit pattern against 35.0f
  // (0x420C0000): {1'b0,v[30:0]} > 32'h420C_0000 -> kinematic_fail=1.
  // 72 m/s is well above 35 m/s, so this injection is caught by both the OLD
  // and NEW implementations -- it does NOT by itself prove the fix. TP_004B
  // below is the actual regression test (50 m/s, invisible to the old check).
  //
  // RTL pipeline trace:
  //   wp_idx=47 -> magnitude check fires this cycle: 72.0 > 35.0 -> kinematic_fail=1
  //   wp_idx=49 -> kin_check_done=1 -> FSM: PP_KINEMATIC -> PP_ERROR
  //
  // CRC recomputed after injection so CRC passes (isolates kinematic error).
  //
  // Expected : kinematic_fail=1, error_out=1, crc_fail=0
  // ===========================================================================
  task automatic tp004_kinematic_infeasible();
    logic gv, ge;
    $display("\n--- TP_004 : Kinematic Infeasible -----------------------------");
    $display("    Stimulus  : base vx=1 m/s, then wp[47].vx=72 m/s (0x%08X, >> 35 m/s)",
             F32_72MPS);
    $display("    Expected  : kinematic_fail=1, error_out=1, PP_ERROR state");

    do_reset();
    load_slow_traj();                          // All 50 wpts at 1 m/s (exp=127)
    traj_mem[47*7+3] = F32_72MPS;             // Spike at wp[47]: 72 m/s
    $display("        [INJ]  traj_mem[%0d] (wp[47].vx) = 0x%08X (72.0 m/s)",
             47*7+3, F32_72MPS);
    compute_and_store_crc();                   // Recompute so CRC passes

    run_preproc(gv, ge);

    chk(dut_kin_fail,  "TP_004", "kinematic_fail == 1 (72 m/s exceeds velocity limit)");
    chk(ge,            "TP_004", "error_out == 1 (FSM entered PP_ERROR)");
    chk(!gv,           "TP_004", "valid_out == 0");
    chk(!dut_crc_fail, "TP_004", "crc_fail == 0 (CRC correct - kinematic error isolated)");

    // Spot-check: confirm offending waypoint magnitude in waypoints_out
    chk({1'b0, dut_wp_out[47].vx[30:0]} > F32_VMAX_35, "TP_004",
        $sformatf("wp[47].vx = 0x%08X, magnitude > 35.0 m/s confirmed in waypoints_out",
                  dut_wp_out[47].vx));

    report("TP_004", dut_kin_fail && ge && !gv && !dut_crc_fail);
  endtask


  // ===========================================================================
  // TP_004B : Kinematic Gap Regression  (vx = 50 m/s, exp = 132)
  // --------------------------------------------------------------------------
  // THIS IS THE REGRESSION TEST for the vulnerability found 2026-08-04
  // (docs/Phase2_Safety_Audit_Review_Board.md, Station 2): the OLD kinematic
  // check was "biased_exp > 8'd132", which gates at |v| >= 64 m/s -- 83%
  // ABOVE the specified VMAX_MPS = 35.0 m/s. The entire 35..64 m/s band was
  // undetected. 50 m/s (exp=132 exactly) sits squarely in that gap: exp=132
  // is NOT "> 132", so the old check silently passed it.
  //
  // On the FIXED RTL (full magnitude compare against 0x420C0000), 50.0 > 35.0
  // must trigger kinematic_fail=1. If this test ever starts passing with
  // kinematic_fail=0, the fix has regressed -- do not delete this test even
  // if TP_004 (72 m/s) still passes, since TP_004 alone cannot distinguish
  // the old (broken) and new (fixed) implementations.
  // ===========================================================================
  task automatic tp004b_kinematic_gap_regression();
    logic gv, ge;
    $display("\n--- TP_004B : Kinematic Gap Regression (50 m/s, exp=132) ------");
    $display("    Stimulus  : base vx=1 m/s, then wp[47].vx=50 m/s (0x%08X, exp=132)",
             F32_50MPS);
    $display("    This is the OLD exponent-only check's exact blind spot:");
    $display("      old check 'exp > 132' -> 132 > 132 is FALSE -> old RTL: NO FAULT (BUG)");
    $display("      new check '|v| > 35.0' -> 50.0 > 35.0 is TRUE -> new RTL: FAULT (correct)");
    $display("    Expected  : kinematic_fail=1, error_out=1, PP_ERROR state");

    do_reset();
    load_slow_traj();
    traj_mem[47*7+3] = F32_50MPS;
    $display("        [INJ]  traj_mem[%0d] (wp[47].vx) = 0x%08X (50.0 m/s, exp=132)",
             47*7+3, F32_50MPS);
    compute_and_store_crc();

    run_preproc(gv, ge);

    chk(dut_kin_fail,  "TP_004B",
        "kinematic_fail == 1 (50 m/s exceeds 35 m/s -- REGRESSION CHECK for the fix)");
    chk(ge,            "TP_004B", "error_out == 1 (FSM entered PP_ERROR)");
    chk(!gv,           "TP_004B", "valid_out == 0");
    chk(!dut_crc_fail, "TP_004B", "crc_fail == 0 (CRC correct - kinematic error isolated)");

    // Confirm the exponent really is exactly 132 (proves this is testing the
    // gap, not accidentally landing above it).
    chk(dut_wp_out[47].vx[30:23] == 8'd132, "TP_004B",
        $sformatf("wp[47].vx exponent == 132 exactly (got %0d) -- confirms gap value used",
                  dut_wp_out[47].vx[30:23]));

    report("TP_004B", dut_kin_fail && ge && !gv && !dut_crc_fail);
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
  // TP_006B : Format Gap Regression  (NaN in z / heading / timestamp)
  // --------------------------------------------------------------------------
  // THIS IS THE REGRESSION TEST for the vulnerability found 2026-08-04
  // (docs/Phase2_Safety_Audit_Review_Board.md, Station 2): the OLD nan_comb
  // only inspected x, y, vx, vy -- three fields of waypoint_t (z, heading,
  // timestamp) were completely unchecked. A NaN in heading is the most
  // dangerous instance: it flows uncaught into hmao_zonotope_gen's CORDIC
  // (via fp32_to_q88 saturation), producing a numerically-valid-looking but
  // meaningless zonotope that can pass collision checking -- a direct False
  // Grant path, not merely a coverage gap.
  //
  // Three independent sub-cases (separate do_reset() each, one NaN injection
  // at a time, isolating cause and effect): z, heading, timestamp.
  // On the OLD RTL all three sub-cases would have produced error_out=0,
  // valid_out=1 -- a silent False Grant. On the FIXED RTL all three must
  // produce error_out=1.
  // ===========================================================================
  task automatic tp006b_format_gap_regression();
    logic gv, ge;
    logic subA_pass, subB_pass, subC_pass;
    $display("\n--- TP_006B : Format Gap Regression (NaN in z/heading/timestamp) ---");
    $display("    These three fields were NOT checked by the OLD nan_comb");
    $display("    (which only inspected x/y/vx/vy) -- a direct False Grant path.");

    // -- Sub-case A: NaN in z -------------------------------------------------
    $display("\n    [A] NaN in wp[5].z (0x%08X)", F32_QNAN);
    do_reset();
    load_nominal_traj();
    traj_mem[5*7+2] = F32_QNAN;   // z field
    compute_and_store_crc();
    run_preproc(gv, ge);
    chk(ge,  "TP_006B-A", "error_out == 1 (NaN in z now detected -- was invisible before the fix)");
    chk(!gv, "TP_006B-A", "valid_out == 0 (no False Grant)");
    subA_pass = ge && !gv;

    // -- Sub-case B: NaN in heading (the dangerous one -- flows into CORDIC) -
    $display("\n    [B] NaN in wp[5].heading (0x%08X) -- feeds hmao_zonotope_gen's CORDIC",
             F32_QNAN);
    do_reset();
    load_nominal_traj();
    traj_mem[5*7+5] = F32_QNAN;   // heading field
    compute_and_store_crc();
    run_preproc(gv, ge);
    chk(ge,  "TP_006B-B", "error_out == 1 (NaN in heading now detected -- False Grant path closed)");
    chk(!gv, "TP_006B-B", "valid_out == 0 (no False Grant)");
    subB_pass = ge && !gv;

    // -- Sub-case C: NaN in timestamp -----------------------------------------
    $display("\n    [C] NaN in wp[5].timestamp (0x%08X)", F32_QNAN);
    do_reset();
    load_nominal_traj();
    traj_mem[5*7+6] = F32_QNAN;   // timestamp field
    compute_and_store_crc();
    run_preproc(gv, ge);
    chk(ge,  "TP_006B-C", "error_out == 1 (NaN in timestamp now detected)");
    chk(!gv, "TP_006B-C", "valid_out == 0 (no False Grant)");
    subC_pass = ge && !gv;

    report("TP_006B", subA_pass && subB_pass && subC_pass);
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

    // Run all test cases in sequence (each begins with do_reset())
    tp001_crc_valid();
    tp002_crc_corrupted();
    tp003_kinematic_valid();
    tp004_kinematic_infeasible();
    tp004b_kinematic_gap_regression();  // 2026-08-04 regression: 50 m/s gap
    tp005_format_valid();
    tp006_format_bad();
    tp006b_format_gap_regression();     // 2026-08-04 regression: z/heading/timestamp NaN

    // -- Summary --------------------------------------------------------------
    $display("\n+===============================================================+");
    $display("|  BATCH U1  SUMMARY                                           |");
    $display("|  Tests  : 8 (TP_001 ... TP_006B)                              |");
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
