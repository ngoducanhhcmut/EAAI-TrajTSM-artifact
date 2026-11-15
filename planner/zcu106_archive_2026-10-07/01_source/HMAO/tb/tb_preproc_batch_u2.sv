// =============================================================================
// FILE        : tb_preproc_batch_u2.sv
// PROJECT     : HMAO Engine - Hardware Assurance Offload (ASIL-D, ISO 26262)
// DUT         : hmao_preproc.sv  (Pre-Processing Unit)
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 7.1
// AUTHOR      : Unit Test Batch U2
// FRAMEWORK   : SystemVerilog + Verilator (400 MHz, cycle-accurate)
//
// TEST CASES
// ----------
//   TP_007  BBox Calculation         - extremal coords, verify xmin/xmax/ymin/ymax
//   TP_008  FSM Happy Path           - full state-transition trace + ~200 000-cycle timing
//   TP_009  AXI Double-Burst Guard   - arvalid LOW until rlast; exactly 8 AR beats
//   TP_010  Cycle Counter Reset Guard- start during PP_BBOX must NOT reset cycle_cnt
//   TP_011  Fast Error Exit          - error_out in exactly 1 cycle after CRC mismatch
//   TP_012  Watchdog Timeout         - AXI bus hang -> stuck PP_FETCH -> external WDT reset
//
// IMPORTANT RTL NOTES (skeleton v12.0)
// -------------------------------------
//   * BBox logic uses raw unsigned integer compare on float32 bits.
//     Works correctly ONLY for positive floats (sign=0).
//     TP_007-A uses positive floats to test the implemented behaviour.
//     TP_007-B injects negative floats and DOCUMENTS the resulting RTL bug.
//
//   * FSM transition path includes PP_FORMAT (single-cycle pass) between
//     PP_KINEMATIC and PP_BBOX; TP_008 verifies all 7 states.
//
//   * crc_valid -> pp_next=PP_ERROR is combinational (via always_comb).
//     The FSM FF therefore samples PP_ERROR one cycle after crc_valid.
//     -> error_out must assert exactly 1 cycle after crc_valid (TP_011).
//
//   * hmao_preproc has NO internal watchdog.  TP_012 demonstrates the hang
//     and shows the external watchdog (WDT_STAGE1_CYCLES = 1 800 000) is
//     the mandatory safety net at system level.
//
// COMPILE EXAMPLE (sim/build_notrace.sh or build_sim.sh)
// -------------------------------------------------------
//   vltr --sv --assert --timing \
//     -I. hmao_pkg.sv hmao_preproc.sv tb_preproc_batch_u2.sv \
//     --exe --build -o sim_u2
//   ./obj_dir/sim_u2
// =============================================================================

`timescale 1ns/1ps



// =============================================================================
// TESTBENCH
// =============================================================================
import hmao_pkg::*;

module tb_preproc_batch_u2;

  // ===========================================================================
  // PARAMETERS & IEEE 754 FLOAT32 CONSTANTS
  // ===========================================================================
  localparam real CLK_PERIOD_NS  = 2.5;       // 400 MHz
  localparam int  MAX_WAIT_CYC   = 250_000;   // poll timeout (must exceed 200 000)
  localparam int  RESET_CYCLES   = 20;
  localparam int  TS_STEP        = 26;         // Q8.8 ~ 100 ms  (26/256 ~ 0.1015 s)

  // Positive-only floats used in TP_007-A (correct unsigned comparison)
  //   0.5  = 0_01111110_00000000000000000000000 = 0x3F00_0000
  //   1.0  = 0_01111111_00000000000000000000000 = 0x3F80_0000
  //   2.0  = 0_10000000_00000000000000000000000 = 0x4000_0000
  //   5.0  = 0_10000001_01000000000000000000000 = 0x40A0_0000
  //   7.5  = 0_10000001_11100000000000000000000 = 0x40F0_0000
  //  10.0  = 0_10000010_01000000000000000000000 = 0x4120_0000
  localparam logic [31:0] F32_ZERO   = 32'h0000_0000;
  localparam logic [31:0] F32_0P5    = 32'h3F00_0000;  //  0.5 m
  localparam logic [31:0] F32_1P0    = 32'h3F80_0000;  //  1.0 m
  localparam logic [31:0] F32_2P0    = 32'h4000_0000;  //  2.0 m
  localparam logic [31:0] F32_5P0    = 32'h40A0_0000;  //  5.0 m
  localparam logic [31:0] F32_7P5    = 32'h40F0_0000;  //  7.5 m
  localparam logic [31:0] F32_10P0   = 32'h4120_0000;  // 10.0 m

  // Velocity constants (must have exp <= 132 to pass kinematic check)
  localparam logic [31:0] F32_10MPS  = 32'h4120_0000;  // 10.0 m/s, exp=130

  // Negative floats for TP_007-B (real coordinates fed to the DUT as float32)
  //  -3.0 = 1_10000000_10000000000000000000000 = 0xC040_0000
  //  -5.0 = 1_10000001_01000000000000000000000 = 0xC0A0_0000
  localparam logic [31:0] F32_NEG3P0 = 32'hC040_0000;
  localparam logic [31:0] F32_NEG5P0 = 32'hC0A0_0000;

  // BUG-FIX (test golden values): bbox_x/y_min/max_out are Q8.8 (value*256),
  // NOT raw float32 bit patterns -- see BUG-FIX PP-001 in hmao_preproc.sv
  // (2026-06-16), which converts internally via fp32_to_q88_bbox() before
  // ever comparing/outputting bbox values. This TB predates that fix and
  // was still comparing against F32_* bit patterns.
  localparam logic signed [31:0] Q88_0P5   = 32'sd128;    //   0.5 m * 256
  localparam logic signed [31:0] Q88_1P0   = 32'sd256;    //   1.0 m * 256
  localparam logic signed [31:0] Q88_2P0   = 32'sd512;    //   2.0 m * 256
  localparam logic signed [31:0] Q88_7P5   = 32'sd1920;   //   7.5 m * 256
  localparam logic signed [31:0] Q88_10P0  = 32'sd2560;   //  10.0 m * 256
  localparam logic signed [31:0] Q88_NEG3P0 = -32'sd768;  //  -3.0 m * 256
  localparam logic signed [31:0] Q88_NEG5P0 = -32'sd1280; //  -5.0 m * 256

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
  // Extends U1 slave with axi_freeze capability:
  //   axi_freeze = 1 -> slave never accepts AR, never drives rvalid.
  //                    Simulates bus-hang for TP_012 watchdog test.
  // ===========================================================================
  logic [31:0] traj_mem [0:350];   // [0..349] = 1400-byte payload, [350] = CRC32

  logic [9:0]  axi_woff;           // word offset into traj_mem
  logic [7:0]  axi_beats_rem;      // beats remaining in current burst
  logic        axi_busy;           // asserted while burst is in flight
  logic        axi_freeze = 1'b0;  // TB-controlled: freeze AXI slave (TP_012)

  // arready: accept only when not mid-burst AND not frozen
  assign axi_bus.arready = (~axi_busy) & (~axi_freeze);
  assign axi_bus.rresp   = 2'b00;
  assign axi_bus.rdata   = ({224'd0, traj_mem[axi_woff]} << {axi_woff[2:0], 5'b0});  // shifted into the address-selected byte lane

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_bus.rvalid <= 1'b0;
      axi_bus.rlast  <= 1'b0;
      axi_beats_rem  <= '0;
      axi_woff       <= '0;
      axi_busy       <= 1'b0;
    end else if (axi_freeze) begin
      // Frozen: pull all outputs low, release busy so arready would be 0 via !axi_freeze
      axi_bus.rvalid <= 1'b0;
      axi_bus.rlast  <= 1'b0;
      axi_busy       <= 1'b0;
    end else begin
      // AR phase: latch burst params on handshake
      if (axi_bus.arvalid && axi_bus.arready) begin
        axi_woff       <= 10'((axi_bus.araddr - TRAJ_BUFFER_BASE) >> 2);
        axi_beats_rem  <= axi_bus.arlen;
        axi_busy       <= 1'b1;
        axi_bus.rvalid <= 1'b1;
        axi_bus.rlast  <= (axi_bus.arlen == 8'd0);
      end
      // R phase: deliver beats
      else if (axi_bus.rvalid && axi_bus.rready) begin
        if (axi_bus.rlast) begin
          axi_bus.rvalid <= 1'b0;
          axi_bus.rlast  <= 1'b0;
          axi_busy       <= 1'b0;
        end else begin
          axi_woff       <= axi_woff + 10'd1;
          axi_beats_rem  <= axi_beats_rem - 8'd1;
          axi_bus.rlast  <= (axi_beats_rem == 8'd1);  // pre-assert rlast one beat early
        end
      end
    end
  end

  // ===========================================================================
  // CRC32 HELPER FUNCTIONS (mirrors hmao_preproc, IEEE 802.3 poly = 0xEDB88320)
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

  // Process all 350 words of traj_mem and store final CRC at traj_mem[350].
  task automatic compute_and_store_crc();
    logic [31:0] crc;
    crc = 32'hFFFF_FFFF;
    for (int w = 0; w < 350; w++)
      crc = crc32_byte_f(crc32_byte_f(crc32_byte_f(crc32_byte_f(
              crc,             traj_mem[w][ 7: 0]),
              traj_mem[w][15:  8]),
              traj_mem[w][23: 16]),
              traj_mem[w][31: 24]);
    traj_mem[350] = crc ^ 32'hFFFF_FFFF;
    $display("        [CRC]  traj_mem[350] = 0x%08X (freshly computed)", traj_mem[350]);
  endtask

  // ===========================================================================
  // TRAJECTORY BUILDERS
  // ===========================================================================

  // Standard 10 m/s straight-line trajectory (used as base for most tests)
  task automatic load_nominal_traj();
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      traj_mem[wp*7+0] = 32'(wp * 256);      // x in Q8.8 (positive, incr each step)
      traj_mem[wp*7+1] = F32_ZERO;            // y = 0
      traj_mem[wp*7+2] = F32_ZERO;            // z = 0
      traj_mem[wp*7+3] = F32_10MPS;           // vx = 10.0 m/s (exp=130 <= 132 -> kinematic OK)
      traj_mem[wp*7+4] = F32_ZERO;            // vy = 0
      traj_mem[wp*7+5] = F32_ZERO;            // heading = 0
      traj_mem[wp*7+6] = 32'(wp * TS_STEP);  // timestamp (Q8.8, uniform dt ~ 100 ms)
    end
    compute_and_store_crc();
  endtask

  // BBox trajectory - all-positive floats (RTL unsigned compare is valid here).
  // Range: x in [F32_1P0, F32_10P0]   y in [F32_0P5, F32_7P5]
  //   wp[0]   : xmin=1.0 m, ymin=0.5 m  (initialise accumulators)
  //   wp[1]   : xmax=10.0 m, ymax=7.5 m  (drive max update)
  //   wp[2..49]: 5.0 m / 2.0 m           (intermediate; not extreme)
  // Expected BBox: xmin=F32_1P0, xmax=F32_10P0, ymin=F32_0P5, ymax=F32_7P5
  task automatic load_bbox_traj_positive();
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      case (wp)
        0: begin
          traj_mem[wp*7+0] = F32_1P0;   // xmin candidate
          traj_mem[wp*7+1] = F32_0P5;   // ymin candidate
        end
        1: begin
          traj_mem[wp*7+0] = F32_10P0;  // xmax candidate
          traj_mem[wp*7+1] = F32_7P5;   // ymax candidate
        end
        default: begin
          traj_mem[wp*7+0] = F32_5P0;   // intermediate  (2.0 < 5.0 < 10.0 in uint)
          traj_mem[wp*7+1] = F32_2P0;   // intermediate
        end
      endcase
      traj_mem[wp*7+2] = F32_ZERO;      // z
      traj_mem[wp*7+3] = F32_ZERO;      // vx = 0 m/s  (exp=0 <= 132 -> kinematic pass)
      traj_mem[wp*7+4] = F32_ZERO;      // vy = 0
      traj_mem[wp*7+5] = F32_ZERO;      // heading
      traj_mem[wp*7+6] = 32'(wp * TS_STEP);
    end
    compute_and_store_crc();
  endtask

  // BBox trajectory - MIXED-SIGN floats (exposes RTL unsigned-compare limitation).
  // Range: x in [-5.0, +10.0]   y in [-3.0, +7.5]
  //   wp[0]  : x=-5.0 (0xC0A0_0000), y=+7.5
  //   wp[49] : x=+10.0,               y=-3.0 (0xC040_0000)
  //   others : x=+2.0, y=+1.0
  //
  // RTL behaviour with unsigned compare (documented bug):
  //   Negative float32 has sign bit=1 -> high unsigned magnitude.
  //   0xC0A0_0000 (-5.0) > 0x4120_0000 (+10.0) in unsigned arithmetic.
  //   Therefore: after iteration the RTL will produce
  //     xmin = +2.0  (WRONG - should be -5.0)
  //     xmax = -5.0  (WRONG - should be +10.0)
  task automatic load_bbox_traj_signed();
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      case (wp)
        0: begin
          traj_mem[wp*7+0] = F32_NEG5P0; // intended xmin (-5.0)
          traj_mem[wp*7+1] = F32_7P5;    // intended ymax
        end
        49: begin
          traj_mem[wp*7+0] = F32_10P0;   // intended xmax (+10.0)
          traj_mem[wp*7+1] = F32_NEG3P0; // intended ymin (-3.0)
        end
        default: begin
          traj_mem[wp*7+0] = F32_2P0;    // intermediate positive
          traj_mem[wp*7+1] = F32_1P0;
        end
      endcase
      traj_mem[wp*7+2] = F32_ZERO;
      traj_mem[wp*7+3] = F32_ZERO;       // vx = 0 (exp=0 -> kinematic pass)
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
    rst_n      <= 1'b0;
    dut_start  <= 1'b0;
    axi_freeze <= 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    @(negedge clk);
    rst_n <= 1'b1;
    repeat (5) @(posedge clk);
    $display("        [RST]  Reset released - DUT idle.");
  endtask

  // Pulse start, poll for valid_out / error_out.
  // Returns got_valid, got_error, and cycle count from start pulse.
  task automatic run_preproc(
    output logic       got_valid,
    output logic       got_error,
    output int unsigned elapsed_cycles
  );
    int unsigned cnt = 0;
    got_valid      = 1'b0;
    got_error      = 1'b0;
    elapsed_cycles = 0;

    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);                      // DUT latches start
    @(negedge clk); dut_start <= 1'b0;

    forever begin
      @(posedge clk);
      cnt++;
      if (dut_valid_out) begin
        got_valid      = 1'b1;
        elapsed_cycles = cnt;
        break;
      end
      if (dut_error_out) begin
        got_error      = 1'b1;
        elapsed_cycles = cnt;
        break;
      end
      if (cnt >= MAX_WAIT_CYC) begin
        $display("        [TMO]  Preproc timed out after %0d cycles!", cnt);
        elapsed_cycles = cnt;
        break;
      end
    end
    @(posedge clk);  // let registered outputs (crc_fail, kin_fail) settle
    $display("        [RUN]  Completed in %0d cycles | valid=%b error=%b",
             elapsed_cycles, got_valid, got_error);
  endtask

  // ===========================================================================
  // SCOREBOARD
  // ===========================================================================
  int pass_count = 0;
  int fail_count = 0;

  task automatic chk(input logic cond, input string tp_id, input string msg);
    if (cond) $display("        [OK ]    %-10s %s", tp_id, msg);
    else      begin
      $display("   *** [FAIL]   %-10s %s", tp_id, msg);
      fail_count++;
    end
  endtask

  task automatic report(input string tp_id, input logic pass_cond);
    if (pass_cond) begin
      $display("[PASS] %-10s ----------------------------------", tp_id);
      pass_count++;
    end else begin
      $display("[FAIL] %-10s  <- see assertions above", tp_id);
      fail_count++;
    end
  endtask

  // ===========================================================================
  // CONCURRENT SVA PROPERTIES (active for the entire simulation)
  // ===========================================================================

  //
  // G1 - valid_out/error_out mutual exclusion (replicated from U1 for U2 coverage)
  //
  property p_mutex_u2;
    @(posedge clk)
      !(dut_valid_out && dut_error_out);
  endproperty
  ag_mutex_u2 : assert property (p_mutex_u2)
    else $error("[SVA-G1] VIOLATION: valid_out and error_out both HIGH!");

  //
  // TP_009 - AXI no-double-burst
  // After every AR channel handshake, arvalid must deassert and remain low until
  // the corresponding rlast beat completes (rlast & rvalid & rready).
  //
  property p_axi_no_double_burst;
    @(posedge clk)
      (axi_bus.arvalid && axi_bus.arready)
        |=> (!axi_bus.arvalid)
              throughout
                (!(axi_bus.rlast && axi_bus.rvalid && axi_bus.rready))[->1];
  endproperty
  ap_axi_no_double_burst : assert property (p_axi_no_double_burst)
    else $error("[SVA-TP009] DOUBLE-BURST: arvalid re-asserted before rlast beat consumed!");

  //
  // TP_010 - cycle_cnt must NOT reset while DUT is processing (outside PP_IDLE)
  // The RTL only resets cycle_cnt when (start && pp_state==PP_IDLE).
  // If start arrives in PP_BBOX, cycle_cnt must keep incrementing (never hit 0).
  //
  property p_no_cnt_reset_outside_idle;
    @(posedge clk)
      (u_dut.pp_state == u_dut.PP_BBOX && dut_start)
        |=> (u_dut.cycle_cnt != 18'd0);
  endproperty
  ap_no_cnt_reset_in_bbox : assert property (p_no_cnt_reset_outside_idle)
    else $error("[SVA-TP010] cycle_cnt RESET while DUT was in PP_BBOX - spec violation!");

  //
  // TP_011 - Fast error exit: exactly 1-cycle latency from CRC mismatch to error_out
  // RTL trace: crc_valid asserts (T) -> pp_next=PP_ERROR resolved combinationally (T)
  //            -> pp_state registered to PP_ERROR (T+1) -> error_out=1 (T+1)
  //
  property p_fast_crc_error_exit;
    @(posedge clk)
      (u_dut.crc_valid && (u_dut.crc_computed !== u_dut.crc_stored))
        |-> ##1 dut_error_out;
  endproperty
  ap_fast_crc_error : assert property (p_fast_crc_error_exit)
    else $error("[SVA-TP011] FAST-EXIT: error_out NOT asserted 1 cycle after CRC mismatch!");

  //
  // Extra - crc_fail implies error_out within 2 cycles (covers registered crc_fail path)
  //
  // crc_fail and error_out assert in the SAME cycle (T+1 relative to crc_valid at T).
  // Use ##[0:2] so simultaneous assertion is accepted.
  property p_crc_fail_implies_error;
    @(posedge clk)
      $rose(dut_crc_fail) |-> ##[0:2] dut_error_out;
  endproperty
  ap_crc_fail_implies_error : assert property (p_crc_fail_implies_error)
    else $error("[SVA] crc_fail asserted but error_out did not follow within 0-2 cycles!");


  // ===========================================================================
  // TP_007 : Bounding Box Calculation
  // --------------------------------------------------------------------------
  // Loads 50 waypoints with extremal coordinates, verifies bbox_xmin/xmax/ymin/ymax.
  //
  // Sub-test A - All-positive floats (RTL int-compare is valid):
  //   x in [1.0, 10.0] m  (F32_1P0 ... F32_10P0)
  //   y in [0.5,  7.5] m  (F32_0P5 ... F32_7P5)
  //   Expected: xmin=F32_1P0, xmax=F32_10P0, ymin=F32_0P5, ymax=F32_7P5
  //
  // Sub-test B - Mixed-sign floats (exposes RTL unsigned-compare bug):
  //   x in [-5.0, 10.0] m   y in [-3.0, 7.5] m
  //   Correct expected: xmin=F32_NEG5P0, xmax=F32_10P0, ymin=F32_NEG3P0, ymax=F32_7P5
  //   RTL actual (unsigned bug): xmin!=NEG5P0 OR xmax!=10P0 (inverted due to sign bit)
  //   -> DOCUMENTS bug; does not block overall pass/fail of TP_007
  // ===========================================================================
  task automatic tp007_bbox_calculation();
    logic gv, ge;
    int unsigned cyc;
    logic sub_a_pass;

    $display("\n--- TP_007 : BBox Calculation ----------------------------------");

    // --- Sub-test A : positive floats ----------------------------------------
    $display("    [A]  Positive-only coords  xin[1.0, 10.0] m  yin[0.5, 7.5] m");
    $display("         vx=vy=0 (kinematic safe).  CRC correct.  Expected: normal BBox.");

    do_reset();
    load_bbox_traj_positive();
    run_preproc(gv, ge, cyc);

    chk(gv,            "TP_007A", "valid_out == 1  (all steps passed)");
    chk(!ge,           "TP_007A", "error_out == 0");
    chk(!dut_crc_fail, "TP_007A", "crc_fail == 0");
    chk(!dut_kin_fail, "TP_007A", "kinematic_fail == 0 (vx=vy=0)");

    chk($signed(dut_bbox_xmin) == Q88_1P0,  "TP_007A",
        $sformatf("bbox_xmin = 0x%08X == Q8.8(1.0)=0x%08X", dut_bbox_xmin, Q88_1P0));
    chk($signed(dut_bbox_xmax) == Q88_10P0, "TP_007A",
        $sformatf("bbox_xmax = 0x%08X == Q8.8(10.0)=0x%08X", dut_bbox_xmax, Q88_10P0));
    chk($signed(dut_bbox_ymin) == Q88_0P5,  "TP_007A",
        $sformatf("bbox_ymin = 0x%08X == Q8.8(0.5)=0x%08X", dut_bbox_ymin, Q88_0P5));
    chk($signed(dut_bbox_ymax) == Q88_7P5,  "TP_007A",
        $sformatf("bbox_ymax = 0x%08X == Q8.8(7.5)=0x%08X", dut_bbox_ymax, Q88_7P5));

    sub_a_pass = gv && !ge && !dut_crc_fail &&
                 $signed(dut_bbox_xmin) == Q88_1P0  &&
                 $signed(dut_bbox_xmax) == Q88_10P0 &&
                 $signed(dut_bbox_ymin) == Q88_0P5  &&
                 $signed(dut_bbox_ymax) == Q88_7P5;

    // --- Sub-test B : mixed-sign floats --------------------------------------
    // BUG-FIX (stale test doc): this used to document an "unsigned compare"
    // bug against raw float32 bit patterns. BUG-FIX PP-001 (2026-06-16)
    // replaced that with fp32_to_q88_bbox() + a $signed() min/max compare
    // (see hmao_preproc.sv:52-84, 561-572), which handles sign correctly.
    // This sub-test now verifies correct signed Q8.8 behavior directly and
    // contributes to the overall TP_007 pass/fail (no longer "informational").
    $display("    [B]  Mixed-sign coords  xin[-5.0, 10.0] m  yin[-3.0, 7.5] m");
    $display("         Verifies signed Q8.8 min/max via fp32_to_q88_bbox (BUG-FIX PP-001).");

    do_reset();
    load_bbox_traj_signed();
    run_preproc(gv, ge, cyc);

    chk(gv, "TP_007B", "valid_out == 1 (no CRC/kinematic error)");

    begin
      logic correct_xmin, correct_xmax, correct_ymin, correct_ymax;
      logic sub_b_pass;
      correct_xmin = ($signed(dut_bbox_xmin) == Q88_NEG5P0);
      correct_xmax = ($signed(dut_bbox_xmax) == Q88_10P0);
      correct_ymin = ($signed(dut_bbox_ymin) == Q88_NEG3P0);
      correct_ymax = ($signed(dut_bbox_ymax) == Q88_7P5);

      chk(correct_xmin, "TP_007B",
          $sformatf("bbox_xmin = 0x%08X == Q8.8(-5.0)=0x%08X", dut_bbox_xmin, Q88_NEG5P0));
      chk(correct_xmax, "TP_007B",
          $sformatf("bbox_xmax = 0x%08X == Q8.8(+10.0)=0x%08X", dut_bbox_xmax, Q88_10P0));
      chk(correct_ymin, "TP_007B",
          $sformatf("bbox_ymin = 0x%08X == Q8.8(-3.0)=0x%08X", dut_bbox_ymin, Q88_NEG3P0));
      chk(correct_ymax, "TP_007B",
          $sformatf("bbox_ymax = 0x%08X == Q8.8(+7.5)=0x%08X", dut_bbox_ymax, Q88_7P5));

      sub_b_pass = gv && correct_xmin && correct_xmax && correct_ymin && correct_ymax;
      sub_a_pass = sub_a_pass && sub_b_pass;
    end

    report("TP_007", sub_a_pass);
  endtask


  // ===========================================================================
  // TP_008 : FSM Happy Path
  // --------------------------------------------------------------------------
  // Trace full state-transition sequence via hierarchical reference to pp_state.
  // Expected: PP_IDLE->PP_FETCH->PP_CRC->PP_KINEMATIC->PP_FORMAT->PP_BBOX->PP_DONE
  // Timing: valid_out must assert at cycle 200 000 +/- 500 from start pulse.
  // ===========================================================================
  task automatic tp008_fsm_happy_path();
    logic gv = 1'b0, ge = 1'b0;
    int unsigned cyc_done = 0;

    // Transition flags  (set by the monitor loop as each state is first entered)
    logic saw_idle   = 1'b0;
    logic saw_fetch  = 1'b0;
    logic saw_crc    = 1'b0;
    logic saw_kin    = 1'b0;
    logic saw_fmt    = 1'b0;
    logic saw_bbox   = 1'b0;
    logic saw_done   = 1'b0;

    // Consecutive-order flags (A->B means B was first seen while last state was A)
    logic ok_idle_to_fetch  = 1'b0;
    logic ok_fetch_to_crc   = 1'b0;
    logic ok_crc_to_kin     = 1'b0;
    logic ok_kin_to_fmt     = 1'b0;
    logic ok_fmt_to_bbox    = 1'b0;
    logic ok_bbox_to_done   = 1'b0;

    $display("\n--- TP_008 : FSM Happy Path ------------------------------------");
    $display("    Expected path  : IDLE->FETCH->CRC->KINEMATIC->FORMAT->BBOX->DONE");
    $display("    Timing target  : valid_out at 200 001 +/- 500 cycles from start");

    do_reset();
    load_nominal_traj();

    // Pulse start
    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);
    @(negedge clk); dut_start <= 1'b0;

    begin : fsm_monitor
      // Track which state was active "last cycle"
      logic [2:0] prev_state;
      int unsigned cnt;
      prev_state = 3'(u_dut.PP_IDLE);  // initial state before first posedge
      cnt = 0;

      forever begin
        @(posedge clk);
        cnt++;

        // Update transition flags based on current pp_state and prev_state
        case (u_dut.pp_state)
          u_dut.PP_IDLE:      saw_idle  = 1'b1;
          u_dut.PP_FETCH:     begin
            saw_fetch = 1'b1;
            if (prev_state == 3'(u_dut.PP_IDLE))    ok_idle_to_fetch = 1'b1;
          end
          u_dut.PP_CRC:       begin
            saw_crc = 1'b1;
            if (prev_state == 3'(u_dut.PP_FETCH))   ok_fetch_to_crc = 1'b1;
          end
          u_dut.PP_KINEMATIC: begin
            saw_kin = 1'b1;
            if (prev_state == 3'(u_dut.PP_CRC))     ok_crc_to_kin = 1'b1;
          end
          u_dut.PP_FORMAT:    begin
            saw_fmt = 1'b1;
            if (prev_state == 3'(u_dut.PP_KINEMATIC)) ok_kin_to_fmt = 1'b1;
          end
          u_dut.PP_BBOX:      begin
            saw_bbox = 1'b1;
            if (prev_state == 3'(u_dut.PP_FORMAT))  ok_fmt_to_bbox = 1'b1;
          end
          u_dut.PP_DONE:      begin
            saw_done = 1'b1;
            if (prev_state == 3'(u_dut.PP_BBOX))    ok_bbox_to_done = 1'b1;
            cyc_done = cnt;
          end
          default: ;  // PP_ERROR should not appear in happy path
        endcase

        prev_state = 3'(u_dut.pp_state);

        if (dut_valid_out) begin gv = 1'b1; break; end
        if (dut_error_out) begin ge = 1'b1; break; end
        if (cnt >= MAX_WAIT_CYC) begin
          $display("        [TMO]  TP_008 monitor timed out after %0d cycles!", cnt);
          break;
        end
      end
    end

    $display("        [FSM]  States seen: IDLE=%0b FETCH=%0b CRC=%0b KIN=%0b FMT=%0b BBOX=%0b DONE=%0b",
             saw_idle, saw_fetch, saw_crc, saw_kin, saw_fmt, saw_bbox, saw_done);
`ifdef SIM_FAST_PREPROC
    $display("        [CYC]  valid_out cycle = %0d  (SIM_FAST_PREPROC: timing check skipped)", cyc_done);
`else
    $display("        [CYC]  valid_out cycle = %0d  (target: 200 001 +/- 500)", cyc_done);
`endif

    // State-transition assertions
    chk(ok_idle_to_fetch,  "TP_008", "PP_IDLE -> PP_FETCH  transition observed");
    chk(ok_fetch_to_crc,   "TP_008", "PP_FETCH -> PP_CRC   transition observed");
    chk(ok_crc_to_kin,     "TP_008", "PP_CRC -> PP_KINEMATIC transition observed");
    chk(ok_kin_to_fmt,     "TP_008", "PP_KINEMATIC -> PP_FORMAT transition observed");
    chk(ok_fmt_to_bbox,    "TP_008", "PP_FORMAT -> PP_BBOX  transition observed");
    chk(ok_bbox_to_done,   "TP_008", "PP_BBOX -> PP_DONE    transition observed");
    chk(gv,                "TP_008", "valid_out == 1  (preproc_valid asserted in PP_DONE)");
    chk(!ge,               "TP_008", "error_out == 0  (happy path, no error)");
    chk(!dut_crc_fail,     "TP_008", "crc_fail == 0");
    chk(!dut_kin_fail,     "TP_008", "kinematic_fail == 0");

    // Timing check: valid_out between [200 000, 200 500] cycles from start
    // (200 001 nominal + up to 499 cycles AXI handshake slack)
    // SIM_FAST_PREPROC: cycle_done=1 immediately -> DUT exits early (~825 cycles).
    // Skip timing assertion; only functional checks matter in fast-sim mode.
`ifdef SIM_FAST_PREPROC
    $display("        [INFO] TP_008 timing check skipped (SIM_FAST_PREPROC active)");
    chk(1'b1, "TP_008", "Timing: skipped (SIM_FAST_PREPROC - cycle_done held 1)");
    report("TP_008",
           ok_idle_to_fetch && ok_fetch_to_crc && ok_crc_to_kin &&
           ok_kin_to_fmt && ok_fmt_to_bbox && ok_bbox_to_done &&
           gv && !ge);
`else
    chk((cyc_done >= 200_000) && (cyc_done <= 200_500), "TP_008",
        $sformatf("Timing: valid_out at cycle %0d in [200 000, 200 500]", cyc_done));
    report("TP_008",
           ok_idle_to_fetch && ok_fetch_to_crc && ok_crc_to_kin &&
           ok_kin_to_fmt && ok_fmt_to_bbox && ok_bbox_to_done &&
           gv && !ge &&
           (cyc_done >= 200_000) && (cyc_done <= 200_500));
`endif
  endtask


  // ===========================================================================
  // TP_009 : AXI Double-Burst Protection
  // --------------------------------------------------------------------------
  // Runs nominal preproc while an imperative AR-channel monitor counts:
  //   * Total AR handshakes (expected: exactly 8)
  //   * Cases where arvalid is re-asserted before the previous rlast completed
  //     (expected: 0)
  // SVA ap_axi_no_double_burst enforces the property formally in parallel.
  // ===========================================================================
  task automatic tp009_axi_double_burst_protection();
    logic gv = 1'b0, ge = 1'b0;
    int unsigned cyc = 0;
    int ar_total     = 0;   // total AR handshakes counted
    int ar_while_busy = 0;  // arvalid re-asserted while burst in flight

    $display("\n--- TP_009 : AXI Double-Burst Protection -----------------------");
    $display("    Expected  : arvalid LOW after each AR accepted, until rlast=1");
    $display("    Expected  : exactly 8 AR bursts for 351 words (7x44 + 43 beats)");
    $display("    SVA       : ap_axi_no_double_burst runs concurrently");

    do_reset();
    load_nominal_traj();

    // Pulse start
    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);
    @(negedge clk); dut_start <= 1'b0;

    begin : ar_monitor
      logic burst_active = 1'b0;
      int cnt = 0;
      forever begin
        @(posedge clk);
        cnt++;

        // Detect AR handshake
        if (axi_bus.arvalid && axi_bus.arready) begin
          ar_total++;
          if (burst_active) begin
            ar_while_busy++;
            $display("   *** [WARN] TP_009 cycle %0d: arvalid asserted while burst still active!",
                     cnt);
          end
          burst_active = 1'b1;
          $display("        [AR]   Burst %0d accepted: addr=0x%08X len=%0d",
                   ar_total, axi_bus.araddr, axi_bus.arlen);
        end

        // Detect end of burst (rlast consumed)
        if (axi_bus.rlast && axi_bus.rvalid && axi_bus.rready)
          burst_active = 1'b0;

        if (dut_valid_out) begin gv = 1'b1; cyc = cnt; break; end
        if (dut_error_out) begin ge = 1'b1; cyc = cnt; break; end
        if (cnt >= MAX_WAIT_CYC) begin
          $display("        [TMO]  TP_009 monitor timed out!"); break;
        end
      end
    end

    $display("        [AXI]  Total AR handshakes : %0d (expected 8)", ar_total);
    $display("        [AXI]  Duplicate AR events : %0d (expected 0)", ar_while_busy);

    chk(gv,                      "TP_009", "Preproc completed valid_out=1");
    chk(!ge,                     "TP_009", "No error_out (data integrity OK)");
    chk(!dut_crc_fail,           "TP_009", "crc_fail=0 (no spurious reads)");
    chk(ar_total == 8,           "TP_009",
        $sformatf("Exactly 8 AR bursts issued (got %0d)", ar_total));
    chk(ar_while_busy == 0,      "TP_009",
        $sformatf("No duplicate AR while burst active (count=%0d)", ar_while_busy));

    report("TP_009", gv && !ge && (ar_total == 8) && (ar_while_busy == 0));
  endtask


  // ===========================================================================
  // TP_010 : Cycle Counter Reset Guard
  // --------------------------------------------------------------------------
  // RTL: cycle_cnt resets ONLY when (start && pp_state == PP_IDLE).
  //       A 'start' pulse in any other state must be ignored.
  // Test: Wait for DUT to enter PP_BBOX, inject a start pulse,
  //       verify cycle_cnt continues from its current value (not reset to 0).
  // SVA ap_no_cnt_reset_in_bbox enforces this in parallel.
  // ===========================================================================
  task automatic tp010_cycle_counter_reset_guard();
    logic gv = 1'b0, ge = 1'b0;
    int unsigned cyc = 0;
    logic        bbox_reached     = 1'b0;
    logic        start_injected   = 1'b0;
    logic        cnt_preserved    = 1'b0;
    logic [17:0] cnt_before_inj;
    logic [17:0] cnt_after_inj;

    $display("\n--- TP_010 : Cycle Counter Reset Guard -------------------------");
    $display("    Expected  : cycle_cnt NOT reset when start pulsed during PP_BBOX");
    $display("    RTL rule  : 'if (start && pp_state == PP_IDLE) cycle_cnt <= 0'");

    do_reset();
    load_nominal_traj();

    // Kick off main preproc run
    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);
    @(negedge clk); dut_start <= 1'b0;

    begin : tp010_loop
      int cnt = 0;
      forever begin
        @(posedge clk);
        cnt++;

        // Inject spurious start the FIRST time we see PP_BBOX
        if ((u_dut.pp_state == u_dut.PP_BBOX) && !start_injected) begin
          bbox_reached    = 1'b1;
          cnt_before_inj  = u_dut.cycle_cnt;  // sample AFTER this posedge update
          $display("        [INJ]  cycle %0d: pp_state=PP_BBOX, cycle_cnt=%0d. Injecting start.",
                   cnt, cnt_before_inj);

          // Drive start at negedge so DUT samples it at the next posedge
          @(negedge clk); dut_start <= 1'b1;
          @(posedge clk);                       // DUT: start=1, pp_state=PP_BBOX -> no reset
          cnt_after_inj = u_dut.cycle_cnt;      // should be cnt_before_inj + 1 (still counting)
          @(negedge clk); dut_start <= 1'b0;
          start_injected = 1'b1;

          // RTL correctly increments: cnt_after = cnt_before + 1 (not 0)
          cnt_preserved = (cnt_after_inj != 18'd0) &&
                          (cnt_after_inj == cnt_before_inj + 18'd1);
          $display("        [CHK]  cycle_cnt before=%0d  after=%0d  expected=%0d  preserved=%0b",
                   cnt_before_inj, cnt_after_inj,
                   cnt_before_inj + 18'd1, cnt_preserved);
        end

        if (dut_valid_out) begin gv = 1'b1; cyc = cnt; break; end
        if (dut_error_out) begin ge = 1'b1; break; end
        if (cnt >= MAX_WAIT_CYC) begin
          $display("        [TMO]  TP_010 monitor timed out!"); break;
        end
      end
    end

    chk(bbox_reached,   "TP_010", "DUT entered PP_BBOX (injection point confirmed)");
    chk(start_injected, "TP_010", "Spurious start pulse injected during PP_BBOX");
    chk(cnt_preserved,  "TP_010",
        $sformatf("cycle_cnt incremented (before=%0d, after=%0d): NOT reset to 0",
                  cnt_before_inj, cnt_after_inj));
    chk(gv,             "TP_010", "Preproc still completed valid_out=1 (not restarted)");
    chk(!ge,            "TP_010", "No error triggered by spurious start");

    report("TP_010", bbox_reached && cnt_preserved && gv && !ge);
  endtask


  // ===========================================================================
  // TP_011 : Fast Error Exit
  // --------------------------------------------------------------------------
  // Injects a 1-bit data corruption AFTER CRC is computed (stale CRC).
  // Measures the exact cycle gap between crc_valid (with mismatch) and error_out.
  // RTL path:
  //   T:   crc_valid asserts; pp_next = PP_ERROR resolved combinationally
  //   T+1: pp_state registered to PP_ERROR; error_out = 1 (combinational output)
  // Expected latency: exactly 1 clock cycle (no 0-cycle or 2+-cycle delay).
  // SVA ap_fast_crc_error enforces this concurrently.
  // ===========================================================================
  task automatic tp011_fast_error_exit();
    logic gv = 1'b0, ge = 1'b0;
    int unsigned crc_valid_cycle   = 0;
    int unsigned error_out_cycle   = 0;
    logic        mismatch_seen     = 1'b0;
    int          latency;

    $display("\n--- TP_011 : Fast Error Exit -----------------------------------");
    $display("    Stimulus  : 1-bit flip in wp[10].x AFTER CRC computed -> stale CRC");
    $display("    Expected  : error_out in exactly 1 cycle after crc_valid+mismatch");

    do_reset();
    load_nominal_traj();                        // correct CRC stored at [350]
    traj_mem[10*7+0] ^= 32'h0000_0001;         // flip bit[0] of wp[10].x
    // traj_mem[350] unchanged -> DUT will compute different CRC -> mismatch
    $display("        [INJ]  traj_mem[%0d] (wp[10].x) bit[0] flipped; CRC at [350] unchanged.",
             10*7);

    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);
    @(negedge clk); dut_start <= 1'b0;

    begin : tp011_monitor
      int cnt = 0;
      forever begin
        @(posedge clk);
        cnt++;

        // First occurrence of crc_valid with mismatch
        if (u_dut.crc_valid && !mismatch_seen) begin
          if (u_dut.crc_computed !== u_dut.crc_stored) begin
            mismatch_seen     = 1'b1;
            crc_valid_cycle   = cnt;
            $display("        [DET]  Cycle %0d: crc_valid=1, computed=0x%08X stored=0x%08X -> MISMATCH",
                     cnt, u_dut.crc_computed, u_dut.crc_stored);
            $display("               Expecting error_out at cycle %0d.", cnt + 1);
          end
        end

        // First occurrence of error_out
        if (dut_error_out && error_out_cycle == 0) begin
          error_out_cycle = cnt;
          ge = 1'b1;
          $display("        [DET]  Cycle %0d: error_out=1", cnt);
          break;
        end
        if (dut_valid_out) begin gv = 1'b1; break; end
        if (cnt >= MAX_WAIT_CYC) begin $display("        [TMO]  TP_011"); break; end
      end
    end

    @(posedge clk);  // settle crc_fail (registered one extra cycle)

    latency = int'(error_out_cycle) - int'(crc_valid_cycle);
    $display("        [LAT]  crc_valid_cycle=%0d  error_out_cycle=%0d  latency=%0d cycle(s)",
             crc_valid_cycle, error_out_cycle, latency);

    chk(mismatch_seen,  "TP_011", "CRC mismatch detected by DUT (crc_valid + computed!=stored)");
    chk(ge,             "TP_011", "error_out == 1 (FSM reached PP_ERROR)");
    chk(!gv,            "TP_011", "valid_out == 0 (no false positive)");
    chk(dut_crc_fail,   "TP_011", "crc_fail == 1 (fault flag registered after mismatch)");
    chk(latency == 1,   "TP_011",
        $sformatf("Error latency = %0d cycle (spec: exactly 1; got %0d)", latency, latency));

    report("TP_011", mismatch_seen && ge && !gv && dut_crc_fail && (latency == 1));
  endtask


  // ===========================================================================
  // TP_012 : Watchdog Timeout  (AXI bus hang)
  // --------------------------------------------------------------------------
  // Simulates a stuck AXI bus by asserting axi_freeze before preproc starts.
  // The DUT cannot receive any AXI data -> pp_state stays PP_FETCH indefinitely.
  // This replicates the fault class: "crc_valid never asserts" (because data
  // never arrives from memory).
  //
  // hmao_preproc has NO internal watchdog; it will hang forever.
  // The testbench acts as the external watchdog (WDT_STAGE1_CYCLES = 1 800 000).
  //
  // Acceptance criteria:
  //   1. DUT does NOT assert valid_out or error_out during the hang window.
  //   2. After WDT_STAGE1_CYCLES the external watchdog fires.
  //   3. External reset (rst_n=0) brings DUT back to PP_IDLE (safe state).
  //   4. Outputs are quiescent post-reset.
  // ===========================================================================
  localparam int WDT_CYC = WDT_STAGE1_CYCLES;  // 1 800 000  (4.5 ms @ 400 MHz)

  task automatic tp012_watchdog_timeout();
    logic wdt_fired         = 1'b0;
    logic stuck_no_valid    = 1'b1;
    logic safe_state_ok;
    logic internal_wdt_fired = 1'b0;
    int   internal_wdt_cycle = 0;

    $display("\n--- TP_012 : Watchdog Timeout (AXI bus hang) -------------------");
    $display("    Stimulus  : axi_freeze=1 before start -> DUT stuck in PP_FETCH");
    $display("    WDT limit : WDT_STAGE1_CYCLES = %0d cycles = %.2f ms @ 400 MHz",
             WDT_CYC, real'(WDT_CYC) * CLK_PERIOD_NS / 1_000_000.0);
    $display("    Expected  : no valid/error during hang, external reset -> PP_IDLE");

    do_reset();
    load_nominal_traj();

    // Freeze AXI slave BEFORE start: the slave will not assert arready
    axi_freeze = 1'b1;
    $display("        [INJ]  axi_freeze=1 - AXI slave frozen (simulating bus hang).");

    @(negedge clk); dut_start <= 1'b1;
    @(posedge clk);
    @(negedge clk); dut_start <= 1'b0;

    begin : wdt_monitor
      int cnt = 0;
      forever begin
        @(posedge clk);
        cnt++;

        // If DUT generates error_out early, an internal WDT may have fired
        if (dut_error_out && internal_wdt_cycle == 0) begin
          internal_wdt_fired = 1'b1;
          internal_wdt_cycle = cnt;
          $display("        [INFO] Cycle %0d: error_out asserted (possible internal WDT).",
                   cnt);
          break;
        end
        if (dut_valid_out) begin
          stuck_no_valid = 1'b0;
          $display("   *** [WARN] TP_012: valid_out unexpectedly at cycle %0d!", cnt);
          break;
        end

        // Testbench watchdog fires after WDT_CYC
        if (cnt >= WDT_CYC) begin
          wdt_fired = 1'b1;
          $display("        [WDT]  Cycle %0d: External watchdog fired! DUT hung for %.2f ms.",
                   cnt, real'(cnt) * CLK_PERIOD_NS / 1_000_000.0);
          $display("               pp_state=%0d (expected PP_FETCH=1).", u_dut.pp_state);
          break;
        end
      end
    end

    // External watchdog action: apply reset to restore safe state
    $display("        [WDT]  Applying external reset to restore safe state...");
    axi_freeze <= 1'b0;
    @(negedge clk);
    rst_n <= 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    @(negedge clk);
    rst_n <= 1'b1;
    repeat (10) @(posedge clk);

    // Verify DUT is back in PP_IDLE
    safe_state_ok = (u_dut.pp_state == u_dut.PP_IDLE);
    $display("        [RST]  Post-reset: pp_state=%0d (PP_IDLE=0), safe_state_ok=%0b",
             u_dut.pp_state, safe_state_ok);
    $display("               valid_out=%b error_out=%b (both must be 0)",
             dut_valid_out, dut_error_out);

    // Assertions
    chk(wdt_fired || internal_wdt_fired,   "TP_012",
        $sformatf("Watchdog condition detected (ext=%0b, int=%0b)", wdt_fired, internal_wdt_fired));
    chk(stuck_no_valid,                    "TP_012",
        "valid_out did NOT spuriously assert during hang (correct)");
    chk(safe_state_ok,                     "TP_012",
        "Post-reset pp_state == PP_IDLE (safe state restored)");
    chk(!dut_valid_out && !dut_error_out,  "TP_012",
        "Post-reset outputs quiescent (valid_out=0, error_out=0)");

    if (!internal_wdt_fired) begin
      $display("        [INFO] hmao_preproc has NO internal watchdog for PP_FETCH hang.");
      $display("               The system-level WDT (WDT_STAGE1_CYCLES=%0d) is the only", WDT_CYC);
      $display("               protection. Spec Section 9.3 requires parent FSM to monitor.");
    end else begin
      $display("        [INFO] DUT asserted error_out internally at cycle %0d.", internal_wdt_cycle);
      $display("               An internal watchdog appears to be implemented.");
    end

    report("TP_012", (wdt_fired || internal_wdt_fired) && stuck_no_valid && safe_state_ok);
  endtask


  // ===========================================================================
  // WAVEFORM DUMP
  // ===========================================================================
  initial begin
    $dumpfile("tb_preproc_u2.vcd");
    $dumpvars(0, tb_preproc_batch_u2);
  end

  // ===========================================================================
  // SIMULATION MAIN
  // ===========================================================================
  initial begin
    $display("+====================================================================+");
    $display("|  HMAO Engine - Unit Test Batch U2                                 |");
    $display("|  DUT    : hmao_preproc.sv  (Spec v12.0 Sec.7.1)                      |");
    $display("|  Freq   : 400 MHz (2.5 ns/cycle)  |  Framework : Verilator        |");
    $display("|  Tests  : TP_007 ... TP_012  (Geometry & FSM Reliability)           |");
    $display("|  Note   : TP_012 runs ~1.8 M cycles (~4.5 ms sim-time)            |");
    $display("+====================================================================+");

    tp007_bbox_calculation();
    tp008_fsm_happy_path();
    tp009_axi_double_burst_protection();
    tp010_cycle_counter_reset_guard();
    tp011_fast_error_exit();
    tp012_watchdog_timeout();   // longest test: runs WDT_STAGE1_CYCLES (1.8 M) cycles

    // -- Summary --------------------------------------------------------------
    $display("\n+====================================================================+");
    $display("|  BATCH U2  SUMMARY                                                |");
    $display("|  Tests  : 6 (TP_007 ... TP_012)                                    |");
    $display("|  PASS   : %-2d                                                      |", pass_count);
    $display("|  FAIL   : %-2d                                                      |", fail_count);
    if (fail_count == 0)
      $display("|  STATUS : OK  ALL PASSED                                           |");
    else
      $display("|  STATUS : FAIL  FAILURES - review assertions above                   |");
    $display("+====================================================================+");

    `ifdef COVERAGE
      $display("[COV] Coverage data written to coverage.dat");
    `endif

    $finish;
  end

  // ===========================================================================
  // GLOBAL SIMULATION WATCHDOG
  // Generous margin: 5 normal tests + TP_012 (1.8 M) + overhead
  // ===========================================================================
  localparam int GLOBAL_TIMEOUT_CYC = 5 * MAX_WAIT_CYC + WDT_STAGE1_CYCLES + 300_000;
  initial begin
    #(real'(GLOBAL_TIMEOUT_CYC) * CLK_PERIOD_NS);
    $display("[WATCHDOG] Global simulation hard timeout reached! Possible infinite hang.");
    $finish;
  end

endmodule : tb_preproc_batch_u2
