// =============================================================================
//  trajectory_sanity_checker.sv
//  Planning Accelerator — Waypoint Sanity & Safety Checker
// =============================================================================
//
//  Vivado synthesis does NOT support real/shortreal types (Synth 8-27).
//  All FP32 arithmetic is implemented as pure logic (IEEE-754 bit manipulation).
//  Helper functions: fp32_lt, fp32_abs, fp32_neg, fp32_mul, fp32_add, fp32_sub.
//  sqrt avoided via squared Menger curvature comparison.
//
//  CHECK INDEX  BIT   DESCRIPTION
//   NAN/INF      [0]   Any waypoint x/y/v contains IEEE-754 NaN or ±Inf
//   SPEED        [1]   v[i] < CSR_V_MIN  or  v[i] > CSR_V_MAX
//   ACCEL        [2]   |Δv| > CSR_A_MAX * DT   (longitudinal)
//   CURVATURE    [3]   κ > CSR_CURV_MAX  (Menger, squared comparison)
//   COLLISION    [4]   min-clearance to any OBJ < CSR_MIN_CLEAR
//   LANE         [5]   any wp outside lane corridor + margin
//
//  DEPENDENCIES: rtl/include/planning_pkg.sv
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module trajectory_sanity_checker
  import planning_pkg::*;
#(
  parameter int unsigned NUM_WP        = 4,
  parameter int unsigned MAX_OBJ       = 16,
  parameter int unsigned NUM_LANE_PTS  = 4,
  // DT as FP32 bit-pattern; default 0.1s = 0x3DCCCCCD
  parameter logic [31:0] DT_FP32       = 32'h3DCCCCCD
)(
  input  wire  clk,
  input  wire  rst_n,

  input  wire  [31:0] wp_x  [0:NUM_WP-1],
  input  wire  [31:0] wp_y  [0:NUM_WP-1],
  input  wire  [31:0] wp_v  [0:NUM_WP-1],
  input  wire         wp_valid,

  input  wire  [31:0] obj_cx   [0:MAX_OBJ-1],
  input  wire  [31:0] obj_cy   [0:MAX_OBJ-1],
  input  wire  [31:0] obj_hl   [0:MAX_OBJ-1],
  input  wire  [31:0] obj_hw   [0:MAX_OBJ-1],
  input  wire  [4:0]  obj_cnt,

  input  wire  [31:0] lane_left_y  [0:NUM_LANE_PTS-1],
  input  wire  [31:0] lane_right_y [0:NUM_LANE_PTS-1],

  input  wire  [31:0] csr_v_min,
  input  wire  [31:0] csr_v_max,
  input  wire  [31:0] csr_a_max,
  input  wire  [31:0] csr_curv_max,
  input  wire  [31:0] csr_min_clear,
  input  wire  [31:0] csr_lane_margin,

  output logic        traj_valid,
  output logic [5:0]  fault_flags,
  output logic        result_valid,

  output logic [31:0] fb_x [0:NUM_WP-1],
  output logic [31:0] fb_y [0:NUM_WP-1],
  output logic [31:0] fb_v [0:NUM_WP-1],
  output logic        fb_valid
);

  // ===========================================================================
  // FP32 pure-logic helpers — no real/shortreal types anywhere
  // Denormals treated as zero.  Rounding: truncate (toward zero).
  // ===========================================================================

  // Ordered less-than: (a < b) → 1 ; NaN inputs → 0
  function automatic logic fp32_lt(input logic [31:0] a, input logic [31:0] b);
    if ((&a[30:23] && |a[22:0]) || (&b[30:23] && |b[22:0])) return 1'b0; // NaN
    if (!a[30:0] && !b[30:0]) return 1'b0;        // ±0 == ±0
    if ( a[31] && !b[31])     return 1'b1;         // neg < pos
    if (!a[31] &&  b[31])     return 1'b0;         // pos > neg
    if (!a[31])               return a[30:0] < b[30:0]; // both positive
    return a[30:0] > b[30:0];                            // both negative
  endfunction

  // Absolute value (clear sign bit)
  function automatic logic [31:0] fp32_abs(input logic [31:0] a);
    fp32_abs = {1'b0, a[30:0]};
  endfunction

  // Negate (flip sign bit)
  function automatic logic [31:0] fp32_neg(input logic [31:0] a);
    fp32_neg = {~a[31], a[30:0]};
  endfunction

  // ── Two-stage fp32_add pipeline support ──────────────────────────────────────
  // Splits the ~25-LUT fp32_add into two ~12-LUT halves to close 185 MHz timing.
  // Stage 1 (fp32_add_s1): magnitude compare, operand swap, exponent diff, alignment shift.
  // Stage 2 (fp32_add_s2): mantissa add/sub, leading-zero normalize, result pack.
  typedef struct packed {
    logic        is_special;   // 1 → return special_val directly in stage 2
    logic [31:0] special_val;  // pre-computed result for NaN/Inf/zero inputs
    logic        same_sign;    // 1 → add mantissas; 0 → subtract
    logic        s_r;          // result sign (sign of the larger-magnitude operand)
    logic  [9:0] e_tmp;        // larger operand exponent, 10-bit (bit 9:8 used as headroom)
    logic [24:0] ma_h;         // larger mantissa: {2'b01, m_large}
    logic [24:0] mb_shf;       // smaller mantissa: {2'b01, m_small} >> diff (aligned)
  } fp32_pipe_t;               // total 95 bits per pipeline register

  function automatic fp32_pipe_t fp32_add_s1(input logic [31:0] a, input logic [31:0] b);
    fp32_pipe_t p;
    logic        s_a, s_b;
    logic [7:0]  e_a, e_b;
    logic [22:0] m_a, m_b;
    logic [7:0]  diff;
    p.is_special  = 1'b0;  p.special_val = '0;
    p.same_sign   = 1'b0;  p.s_r         = 1'b0;
    p.e_tmp       = '0;    p.ma_h        = '0;   p.mb_shf = '0;
    s_a = a[31]; e_a = a[30:23]; m_a = a[22:0];
    s_b = b[31]; e_b = b[30:23]; m_b = b[22:0];
    // Special cases
    if ((&e_a && |m_a) || (&e_b && |m_b)) begin
      p.is_special = 1'b1; p.special_val = 32'h7FC00000; return p;
    end
    if (&e_a && &e_b) begin
      p.is_special  = 1'b1;
      p.special_val = (s_a == s_b) ? {s_a, 8'hFF, 23'b0} : 32'h7FC00000;
      return p;
    end
    if (&e_a) begin p.is_special = 1'b1; p.special_val = a; return p; end
    if (&e_b) begin p.is_special = 1'b1; p.special_val = b; return p; end
    if (!e_a) begin p.is_special = 1'b1; p.special_val = b; return p; end
    if (!e_b) begin p.is_special = 1'b1; p.special_val = a; return p; end
    // Ensure |a| >= |b|; swap if needed
    if ({e_b, m_b} > {e_a, m_a}) begin
      logic [7:0]  et; logic [22:0] mt; logic st;
      st = s_a; s_a = s_b; s_b = st;
      et = e_a; e_a = e_b; e_b = et;
      mt = m_a; m_a = m_b; m_b = mt;
    end
    diff     = e_a - e_b;
    p.ma_h   = {2'b01, m_a};
    p.mb_shf = (diff >= 8'd25) ? 25'b0 : 25'({2'b01, m_b} >> diff);
    p.e_tmp  = {2'b0, e_a};
    p.same_sign = (s_a == s_b);
    p.s_r    = s_a;
    return p;
  endfunction

  function automatic logic [31:0] fp32_add_s2(input fp32_pipe_t p);
    logic [25:0] s_sum;
    logic signed [9:0] e_tmp;
    logic [7:0]  e_r;
    logic [22:0] m_r;
    logic [4:0]  lzc;
    logic signed [9:0] e_clamp;
    if (p.is_special) return p.special_val;
    e_tmp = $signed(p.e_tmp);
    if (p.same_sign) begin
      s_sum = {1'b0, p.ma_h} + {1'b0, p.mb_shf};
      if      (s_sum[25]) begin e_tmp++; m_r = s_sum[24:2]; end
      else if (s_sum[24]) begin e_tmp++; m_r = s_sum[23:1]; end
      else                begin          m_r = s_sum[22:0];  end
    end else begin
      s_sum = {1'b0, p.ma_h} - {1'b0, p.mb_shf};
      if (!s_sum[24:0]) return 32'b0;
      casez (s_sum[23:0])
        24'b1???????????????????????: lzc = 5'd0;
        24'b01??????????????????????: lzc = 5'd1;
        24'b001?????????????????????: lzc = 5'd2;
        24'b0001????????????????????: lzc = 5'd3;
        24'b00001???????????????????: lzc = 5'd4;
        24'b000001??????????????????: lzc = 5'd5;
        24'b0000001?????????????????: lzc = 5'd6;
        24'b00000001????????????????: lzc = 5'd7;
        24'b000000001???????????????: lzc = 5'd8;
        24'b0000000001??????????????: lzc = 5'd9;
        24'b00000000001?????????????: lzc = 5'd10;
        24'b000000000001????????????: lzc = 5'd11;
        24'b0000000000001???????????: lzc = 5'd12;
        24'b00000000000001??????????: lzc = 5'd13;
        24'b000000000000001?????????: lzc = 5'd14;
        24'b0000000000000001????????: lzc = 5'd15;
        24'b00000000000000001???????: lzc = 5'd16;
        24'b000000000000000001??????: lzc = 5'd17;
        24'b0000000000000000001?????: lzc = 5'd18;
        24'b00000000000000000001????: lzc = 5'd19;
        24'b000000000000000000001???: lzc = 5'd20;
        24'b0000000000000000000001??: lzc = 5'd21;
        24'b00000000000000000000001?: lzc = 5'd22;
        default                      : lzc = 5'd23;
      endcase
      if (e_tmp - 10'sd1 < $signed({5'b0, lzc})) begin
        e_clamp = e_tmp - 10'sd1;
        lzc = (e_tmp > 10'sd1) ? e_clamp[4:0] : 5'd0;
      end
      s_sum  = s_sum << lzc;
      e_tmp -= $signed({5'b0, lzc});
      m_r    = s_sum[22:0];
    end
    if (e_tmp <= 10'sd0)   return {p.s_r, 31'b0};
    if (e_tmp >= 10'sd255) return {p.s_r, 8'hFF, 23'b0};
    e_r = e_tmp[7:0];
    fp32_add_s2 = {p.s_r, e_r, m_r};
  endfunction

  // Multiply
  function automatic logic [31:0] fp32_mul(input logic [31:0] a, input logic [31:0] b);
    logic        s_r;
    logic [7:0]  e_a, e_b;
    logic [22:0] m_a, m_b;
    logic [47:0] prod;
    logic signed [9:0] e_sum;
    logic [7:0]  e_r;
    logic [22:0] m_r;

    s_r = a[31] ^ b[31];
    e_a = a[30:23]; m_a = a[22:0];
    e_b = b[30:23]; m_b = b[22:0];

    if ((&e_a && |m_a) || (&e_b && |m_b)) return 32'h7FC00000; // NaN
    if (!e_a || !e_b)                      return {s_r, 31'b0}; // zero/denorm
    if (&e_a || &e_b)                      return {s_r, 8'hFF, 23'b0}; // Inf

    prod  = {1'b1, m_a} * {1'b1, m_b};
    e_sum = $signed({2'b0, e_a}) + $signed({2'b0, e_b}) - 10'sd127;

    if (prod[47]) begin e_sum++; m_r = prod[46:24]; end
    else               m_r = prod[45:23];

    if (e_sum >= 10'sd255) return {s_r, 8'hFF, 23'b0};
    if (e_sum <= 10'sd0)   return {s_r, 31'b0};
    e_r = e_sum[7:0];
    fp32_mul = {s_r, e_r, m_r};
  endfunction

  // Add (works for subtraction via negated b)
  function automatic logic [31:0] fp32_add(input logic [31:0] a, input logic [31:0] b);
    logic s_a, s_b, s_r;
    logic [7:0]  e_a, e_b;
    logic [22:0] m_a, m_b;
    logic [24:0] ma_h, mb_shf;
    logic [7:0]  diff;
    logic [25:0] s_sum;
    logic signed [9:0] e_tmp;
    logic [7:0]  e_r;
    logic [22:0] m_r;
    logic [4:0]  lzc;  // leading-zero count for parallel normalization
    logic signed [9:0] e_clamp; // temp for clamped exponent slice

    s_a = a[31]; e_a = a[30:23]; m_a = a[22:0];
    s_b = b[31]; e_b = b[30:23]; m_b = b[22:0];

    // Special cases
    if ((&e_a && |m_a) || (&e_b && |m_b)) return 32'h7FC00000; // NaN
    if (&e_a && &e_b) begin
      if (s_a == s_b) return {s_a, 8'hFF, 23'b0}; // ±Inf + ±Inf
      else            return 32'h7FC00000;           // Inf - Inf → NaN
    end
    if (&e_a) return a;
    if (&e_b) return b;
    if (!e_a) return b;   // a is zero/denorm
    if (!e_b) return a;   // b is zero/denorm

    // Ensure |a| >= |b| (compare magnitude = {exp, mant})
    if ({e_b, m_b} > {e_a, m_a}) begin
      // swap
      s_r = s_a; s_a = s_b; s_b = s_r;
      begin logic [7:0] et; et=e_a; e_a=e_b; e_b=et; end
      begin logic [22:0] mt; mt=m_a; m_a=m_b; m_b=mt; end
    end

    diff  = e_a - e_b;
    ma_h  = {2'b01, m_a};
    mb_shf = (diff >= 8'd25) ? 25'b0 : ({2'b01, m_b} >> diff);
    e_tmp = $signed({2'b0, e_a});

    if (s_a == s_b) begin
      // Same sign: add mantissas.
      // Hidden bits of ma_h / mb_shf sit at bit23.  After addition:
      //   s_sum[25]=1 : two-bit carry  → e+2, mantissa = [24:2]
      //   s_sum[24]=1 : one-bit carry  → e+1, mantissa = [23:1]
      //   else         : no carry      → e unchanged, mantissa = [22:0]
      s_r   = s_a;
      s_sum = {1'b0, ma_h} + {1'b0, mb_shf};
      if      (s_sum[25]) begin e_tmp++; m_r = s_sum[24:2]; end
      else if (s_sum[24]) begin e_tmp++; m_r = s_sum[23:1]; end
      else                begin          m_r = s_sum[22:0];  end
    end else begin
      // Different signs: subtract (|a| >= |b| guaranteed)
      // Hidden bits sit at bit23; normalize until s_sum[23] = 1.
      s_r   = s_a;
      s_sum = {1'b0, ma_h} - {1'b0, mb_shf};
      if (!s_sum[24:0]) return 32'b0; // exact zero
      // Parallel LZC + barrel shift (replaces 24-deep sequential loop).
      // s_sum[24] is always 0 in subtraction path (|a|>=|b| guaranteed).
      // We count leading zeros in s_sum[23:0] to find how far to shift left
      // so the hidden bit lands at position 23.
      casez (s_sum[23:0])
        24'b1???????????????????????: lzc = 5'd0;
        24'b01??????????????????????: lzc = 5'd1;
        24'b001?????????????????????: lzc = 5'd2;
        24'b0001????????????????????: lzc = 5'd3;
        24'b00001???????????????????: lzc = 5'd4;
        24'b000001??????????????????: lzc = 5'd5;
        24'b0000001?????????????????: lzc = 5'd6;
        24'b00000001????????????????: lzc = 5'd7;
        24'b000000001???????????????: lzc = 5'd8;
        24'b0000000001??????????????: lzc = 5'd9;
        24'b00000000001?????????????: lzc = 5'd10;
        24'b000000000001????????????: lzc = 5'd11;
        24'b0000000000001???????????: lzc = 5'd12;
        24'b00000000000001??????????: lzc = 5'd13;
        24'b000000000000001?????????: lzc = 5'd14;
        24'b0000000000000001????????: lzc = 5'd15;
        24'b00000000000000001???????: lzc = 5'd16;
        24'b000000000000000001??????: lzc = 5'd17;
        24'b0000000000000000001?????: lzc = 5'd18;
        24'b00000000000000000001????: lzc = 5'd19;
        24'b000000000000000000001???: lzc = 5'd20;
        24'b0000000000000000000001??: lzc = 5'd21;
        24'b00000000000000000000001?: lzc = 5'd22;
        default                      : lzc = 5'd23;
      endcase
      // Clamp shift so exponent stays >= 1 (denormal boundary).
      // e_tmp is always >= 1 here (zero/denorm inputs already returned).
      if (e_tmp - 10'sd1 < $signed({5'b0, lzc})) begin
        e_clamp = e_tmp - 10'sd1;
        lzc = (e_tmp > 10'sd1) ? e_clamp[4:0] : 5'd0;
      end
      // Single barrel shift — ~5 LUT levels vs 24 sequential mux levels.
      s_sum  = s_sum << lzc;
      e_tmp -= $signed({5'b0, lzc});
      m_r    = s_sum[22:0];
    end

    if (e_tmp <= 10'sd0)   return {s_r, 31'b0};
    if (e_tmp >= 10'sd255) return {s_r, 8'hFF, 23'b0};
    e_r = e_tmp[7:0];
    fp32_add = {s_r, e_r, m_r};
  endfunction

  // Subtract
  function automatic logic [31:0] fp32_sub(input logic [31:0] a, input logic [31:0] b);
    fp32_sub = fp32_add(a, fp32_neg(b));
  endfunction

  // Point-to-AABB min-distance-squared (FP32 bit patterns throughout)
  function automatic logic [31:0] fp32_aabb_dist_sq(
    input logic [31:0] px, input logic [31:0] py,
    input logic [31:0] cx, input logic [31:0] cy,
    input logic [31:0] hl, input logic [31:0] hw
  );
    logic [31:0] dx, dy, ex, ey;
    logic [31:0] zero = 32'b0;
    dx = fp32_abs(fp32_sub(px, cx));
    ex = fp32_lt(hl, dx) ? fp32_sub(dx, hl) : zero;  // max(dx-hl, 0)
    dy = fp32_abs(fp32_sub(py, cy));
    ey = fp32_lt(hw, dy) ? fp32_sub(dy, hw) : zero;
    fp32_aabb_dist_sq = fp32_add(fp32_mul(ex, ex), fp32_mul(ey, ey));
  endfunction

  // ===========================================================================
  // State machine
  // ===========================================================================

  typedef enum logic [4:0] {
    ST_IDLE           = 5'd0,
    ST_CHK_NAN        = 5'd1,
    ST_CHK_SPEED      = 5'd2,
    ST_CHK_ACCEL      = 5'd3,
    ST_CURV_LOAD      = 5'd4,
    ST_CURV_DIFF      = 5'd5,
    ST_CURV_MUL_CROSS = 5'd6,
    ST_CURV_ACC_CROSS = 5'd7,
    ST_CURV_MUL_NORM  = 5'd8,
    ST_CURV_ACC_NORM  = 5'd9,
    ST_CURV_DIFF2        = 5'd18,  // split: dy2, dac_x, dac_y
    ST_CURV_DIFF_S1      = 5'd19,  // fp32_add stage-1 for DIFF (alignment)
    ST_CURV_DIFF2_S1     = 5'd20,  // fp32_add stage-1 for DIFF2 (alignment)
    ST_CURV_ACC_CROSS_S1 = 5'd21,  // fp32_add stage-1 for ACC_CROSS (alignment)
    ST_CURV_PREP_A    = 5'd15,  // pipeline: cm2 + cross²
    ST_CURV_PREP_B    = 5'd16,  // pipeline: rhs1 + lhs
    ST_CURV_PREP_C    = 5'd17,  // pipeline: rhs2
    ST_CURV_CMP       = 5'd10,
    ST_COLL_DIST      = 5'd11,
    ST_COLL_CMP       = 5'd12,
    ST_CHK_LANE       = 5'd13,
    ST_DONE           = 5'd14
  } state_t;

  state_t state_r;

  localparam int WP_W   = $clog2(NUM_WP);
  localparam int OBJ_W  = $clog2(MAX_OBJ);
  localparam logic [WP_W-1:0]  WP_LAST  = WP_W'(NUM_WP  - 1);
  localparam logic [WP_W-1:0]  WP_LAST2 = WP_W'(NUM_WP  - 2);
  localparam logic [OBJ_W-1:0] OBJ_LAST = OBJ_W'(MAX_OBJ - 1);

  // FP32 constant: 4.0 = 0x40800000
  localparam logic [31:0] FP32_FOUR = 32'h40800000;

  logic [$clog2(NUM_WP)-1:0]   idx_wp_r;
  logic [$clog2(MAX_OBJ)-1:0]  idx_obj_r;

  logic [31:0] wp_x_r [0:NUM_WP-1];
  logic [31:0] wp_y_r [0:NUM_WP-1];
  logic [31:0] wp_v_r [0:NUM_WP-1];
  logic [5:0]  fault_r;

  logic [31:0] fb_x_r [0:NUM_WP-1];
  logic [31:0] fb_y_r [0:NUM_WP-1];
  logic [31:0] fb_v_r [0:NUM_WP-1];
  logic        fb_valid_r;

  logic [31:0] curv_abs_cross_r;
  logic [31:0] curv_ds1_sq_r;
  logic [31:0] curv_ds2_sq_r;
  logic [31:0] curv_dac_sq_r;
  logic        curv_valid_r;
  logic        curv_metric_valid_r;
  logic [31:0] curv_ax_r, curv_ay_r, curv_bx_r, curv_by_r, curv_cx_r, curv_cy_r;
  logic [31:0] curv_dx1_r, curv_dy1_r, curv_dx2_r, curv_dy2_r;
  logic [31:0] curv_dac_x_r, curv_dac_y_r;
  logic [31:0] curv_cross_mul0_r, curv_cross_mul1_r;
  logic [31:0] curv_ds1_x_sq_r, curv_ds1_y_sq_r;
  logic [31:0] curv_ds2_x_sq_r, curv_ds2_y_sq_r;
  logic [31:0] curv_dac_x_sq_r, curv_dac_y_sq_r;

  logic [31:0] coll_dist_sq_r;
  logic [31:0] coll_min_sq_r;

  // Pipeline registers for fp32_add two-stage pipeline (DIFF, DIFF2, ACC_CROSS)
  fp32_pipe_t dx1_pipe_r, dy1_pipe_r, dx2_pipe_r;          // ST_CURV_DIFF_S1 outputs
  fp32_pipe_t dy2_pipe_r, dac_x_pipe_r, dac_y_pipe_r;      // ST_CURV_DIFF2_S1 outputs
  fp32_pipe_t abs_cross_pipe_r;                              // ST_CURV_ACC_CROSS_S1 output

  // Pipeline registers for ST_CURV_CMP multi-cycle multiply
  logic [31:0] curv_cm2_r;      // csr_curv_max²
  logic [31:0] curv_cross_sq_r; // curv_abs_cross²
  logic [31:0] curv_lhs_r;      // 4 * curv_abs_cross²
  logic [31:0] curv_rhs1_r;     // cm2 * curv_ds1_sq
  logic [31:0] curv_rhs2_r;     // cm2 * curv_ds1_sq * curv_ds2_sq

  // ===========================================================================
  // E-stop fallback trajectory
  // ===========================================================================

  task automatic build_estop_traj();
    logic [31:0] v_cur, v_next, a_dt;
    int i;
    v_cur = wp_v_r[0];
    a_dt  = fp32_mul(csr_a_max, DT_FP32); // a_max * DT
    for (i = 0; i < NUM_WP; i++) begin
      fb_x[i] <= 32'b0;
      fb_y[i] <= 32'b0;
      fb_v[i] <= v_cur;
      v_next = fp32_sub(v_cur, a_dt);
      v_cur  = fp32_lt(v_next, 32'b0) ? 32'b0 : v_next; // clamp ≥ 0
    end
    fb_valid <= 1'b1;
  endtask

  // ===========================================================================
  // FSM
  // ===========================================================================

  always_ff @(posedge clk) begin : fsm_seq
    if (!rst_n) begin
      state_r      <= ST_IDLE;
      idx_wp_r     <= '0;
      idx_obj_r    <= '0;
      fault_r      <= 6'b0;
      traj_valid   <= 1'b0;
      fault_flags  <= 6'b0;
      result_valid <= 1'b0;
      fb_valid_r   <= 1'b0;
      fb_valid     <= 1'b0;
      curv_abs_cross_r <= '0;
      curv_ds1_sq_r    <= '0;
      curv_ds2_sq_r    <= '0;
      curv_dac_sq_r    <= '0;
      curv_valid_r     <= 1'b0;
      curv_metric_valid_r <= 1'b0;
      curv_ax_r        <= '0;
      curv_ay_r        <= '0;
      curv_bx_r        <= '0;
      curv_by_r        <= '0;
      curv_cx_r        <= '0;
      curv_cy_r        <= '0;
      curv_dx1_r       <= '0;
      curv_dy1_r       <= '0;
      curv_dx2_r       <= '0;
      curv_dy2_r       <= '0;
      curv_dac_x_r     <= '0;
      curv_dac_y_r     <= '0;
      curv_cross_mul0_r <= '0;
      curv_cross_mul1_r <= '0;
      curv_ds1_x_sq_r   <= '0;
      curv_ds1_y_sq_r   <= '0;
      curv_ds2_x_sq_r   <= '0;
      curv_ds2_y_sq_r   <= '0;
      curv_dac_x_sq_r   <= '0;
      curv_dac_y_sq_r   <= '0;
      coll_dist_sq_r   <= '0;
      coll_min_sq_r    <= '0;
      dx1_pipe_r       <= '0;  dy1_pipe_r   <= '0;  dx2_pipe_r      <= '0;
      dy2_pipe_r       <= '0;  dac_x_pipe_r <= '0;  dac_y_pipe_r    <= '0;
      abs_cross_pipe_r <= '0;
      for (int i = 0; i < NUM_WP; i++) begin
        wp_x_r[i] <= '0; wp_y_r[i] <= '0; wp_v_r[i] <= '0;
        fb_x_r[i] <= '0; fb_y_r[i] <= '0; fb_v_r[i] <= '0;
        fb_x[i]   <= '0; fb_y[i]   <= '0; fb_v[i]   <= '0;
      end
    end else begin
      result_valid <= 1'b0;

      unique case (state_r)

        ST_IDLE: begin
          if (wp_valid) begin
            for (int i = 0; i < NUM_WP; i++) begin
              wp_x_r[i] <= wp_x[i];
              wp_y_r[i] <= wp_y[i];
              wp_v_r[i] <= wp_v[i];
            end
            fault_r   <= 6'b0;
            idx_wp_r  <= '0;
            idx_obj_r <= '0;
            state_r   <= ST_CHK_NAN;
          end
        end

        // CHECK 0: NaN/Inf — exponent all-ones
        ST_CHK_NAN: begin
          if (&wp_x_r[idx_wp_r][30:23] ||
              &wp_y_r[idx_wp_r][30:23] ||
              &wp_v_r[idx_wp_r][30:23])
            fault_r[0] <= 1'b1;

          if (idx_wp_r == WP_LAST) begin idx_wp_r <= '0; state_r <= ST_CHK_SPEED; end
          else                          idx_wp_r <= idx_wp_r + 1'b1;
        end

        // CHECK 1: Speed bounds
        ST_CHK_SPEED: begin
          if (fp32_lt(wp_v_r[idx_wp_r], csr_v_min) ||
              fp32_lt(csr_v_max, wp_v_r[idx_wp_r]))
            fault_r[1] <= 1'b1;

          if (idx_wp_r == WP_LAST) begin idx_wp_r <= '0; state_r <= ST_CHK_ACCEL; end
          else                          idx_wp_r <= idx_wp_r + 1'b1;
        end

        // CHECK 2: Acceleration |Δv| > a_max * DT
        ST_CHK_ACCEL: begin
          if (idx_wp_r < WP_LAST) begin
            logic [31:0] dv, abs_dv, a_max_dt;
            dv       = fp32_sub(wp_v_r[idx_wp_r + 1'b1], wp_v_r[idx_wp_r]);
            abs_dv   = fp32_abs(dv);
            a_max_dt = fp32_mul(csr_a_max, DT_FP32);
            if (fp32_lt(a_max_dt, abs_dv)) fault_r[2] <= 1'b1;
          end

          if (idx_wp_r == WP_LAST) begin idx_wp_r <= '0; state_r <= ST_CURV_LOAD; end
          else                          idx_wp_r <= idx_wp_r + 1'b1;
        end

        // CHECK 3: Curvature via squared Menger formula
        // Split across 4 states to keep the FP32 helper chain out of one cycle.
        // κ > κ_max  ⟺  (2|cross_val|)² > κ_max² · |AB|² · |BC|² · |AC|²
        ST_CURV_LOAD: begin
          if (idx_wp_r < WP_LAST2) begin
            curv_ax_r        <= wp_x_r[idx_wp_r];
            curv_ay_r        <= wp_y_r[idx_wp_r];
            curv_bx_r        <= wp_x_r[idx_wp_r+1'b1];
            curv_by_r        <= wp_y_r[idx_wp_r+1'b1];
            curv_cx_r        <= wp_x_r[idx_wp_r+2'd2];
            curv_cy_r        <= wp_y_r[idx_wp_r+2'd2];
            curv_valid_r     <= 1'b1;
          end else begin
            curv_valid_r     <= 1'b0;
          end
          curv_metric_valid_r <= 1'b0;
          state_r <= ST_CURV_DIFF_S1;
        end

        // Stage 1: compute alignment (magnitude compare + barrel shift) for DIFF
        ST_CURV_DIFF_S1: begin
          if (curv_valid_r) begin
            dx1_pipe_r <= fp32_add_s1(curv_bx_r, fp32_neg(curv_ax_r));
            dy1_pipe_r <= fp32_add_s1(curv_by_r, fp32_neg(curv_ay_r));
            dx2_pipe_r <= fp32_add_s1(curv_cx_r, fp32_neg(curv_bx_r));
          end
          state_r <= ST_CURV_DIFF;
        end

        // Stage 2: add/sub + normalize for DIFF (uses pipe regs from DIFF_S1)
        ST_CURV_DIFF: begin
          if (curv_valid_r) begin
            curv_dx1_r <= fp32_add_s2(dx1_pipe_r);
            curv_dy1_r <= fp32_add_s2(dy1_pipe_r);
            curv_dx2_r <= fp32_add_s2(dx2_pipe_r);
          end
          state_r <= ST_CURV_DIFF2_S1;
        end

        // Stage 1: compute alignment for DIFF2
        ST_CURV_DIFF2_S1: begin
          if (curv_valid_r) begin
            dy2_pipe_r   <= fp32_add_s1(curv_cy_r, fp32_neg(curv_by_r));
            dac_x_pipe_r <= fp32_add_s1(curv_cx_r, fp32_neg(curv_ax_r));
            dac_y_pipe_r <= fp32_add_s1(curv_cy_r, fp32_neg(curv_ay_r));
          end
          state_r <= ST_CURV_DIFF2;
        end

        // Stage 2: add/sub + normalize for DIFF2
        ST_CURV_DIFF2: begin
          if (curv_valid_r) begin
            curv_dy2_r   <= fp32_add_s2(dy2_pipe_r);
            curv_dac_x_r <= fp32_add_s2(dac_x_pipe_r);
            curv_dac_y_r <= fp32_add_s2(dac_y_pipe_r);
          end
          state_r <= ST_CURV_MUL_CROSS;
        end

        ST_CURV_MUL_CROSS: begin
          if (curv_valid_r) begin
            curv_cross_mul0_r <= fp32_mul(curv_dx1_r, curv_dy2_r);
            curv_cross_mul1_r <= fp32_mul(curv_dy1_r, curv_dx2_r);
          end
          state_r <= ST_CURV_ACC_CROSS_S1;
        end

        // Stage 1: alignment for abs(cross_mul0 - cross_mul1)
        ST_CURV_ACC_CROSS_S1: begin
          if (curv_valid_r)
            abs_cross_pipe_r <= fp32_add_s1(curv_cross_mul0_r, fp32_neg(curv_cross_mul1_r));
          state_r <= ST_CURV_ACC_CROSS;
        end

        // Stage 2: complete the cross subtraction + all the muls (unchanged)
        ST_CURV_ACC_CROSS: begin
          if (curv_valid_r) begin
            curv_abs_cross_r <= fp32_abs(fp32_add_s2(abs_cross_pipe_r));
            curv_ds1_x_sq_r  <= fp32_mul(curv_dx1_r, curv_dx1_r);
            curv_ds1_y_sq_r  <= fp32_mul(curv_dy1_r, curv_dy1_r);
            curv_ds2_x_sq_r  <= fp32_mul(curv_dx2_r, curv_dx2_r);
            curv_ds2_y_sq_r  <= fp32_mul(curv_dy2_r, curv_dy2_r);
            curv_dac_x_sq_r  <= fp32_mul(curv_dac_x_r, curv_dac_x_r);
            curv_dac_y_sq_r  <= fp32_mul(curv_dac_y_r, curv_dac_y_r);
          end
          state_r <= ST_CURV_MUL_NORM;
        end

        ST_CURV_MUL_NORM: begin
          if (curv_valid_r) begin
            curv_ds1_sq_r <= fp32_add(curv_ds1_x_sq_r, curv_ds1_y_sq_r);
            curv_ds2_sq_r <= fp32_add(curv_ds2_x_sq_r, curv_ds2_y_sq_r);
            curv_dac_sq_r <= fp32_add(curv_dac_x_sq_r, curv_dac_y_sq_r);
          end
          state_r <= ST_CURV_ACC_NORM;
        end

        ST_CURV_ACC_NORM: begin
          localparam logic [31:0] EPS_SQ = 32'h1A83126F;
          if (curv_valid_r) begin
            curv_dac_sq_r       <= fp32_lt(curv_dac_sq_r, EPS_SQ) ? EPS_SQ : curv_dac_sq_r;
            curv_metric_valid_r <= fp32_lt(EPS_SQ, curv_ds1_sq_r) && fp32_lt(EPS_SQ, curv_ds2_sq_r);
          end else begin
            curv_metric_valid_r <= 1'b0;
          end
          state_r <= ST_CURV_PREP_A;
        end

        // Pipeline stages: break 3-deep fp32_mul chain into 1 mul/cycle
        ST_CURV_PREP_A: begin
          if (curv_metric_valid_r) begin
            curv_cm2_r      <= fp32_mul(csr_curv_max, csr_curv_max);
            curv_cross_sq_r <= fp32_mul(curv_abs_cross_r, curv_abs_cross_r);
          end
          state_r <= ST_CURV_PREP_B;
        end

        ST_CURV_PREP_B: begin
          if (curv_metric_valid_r) begin
            curv_rhs1_r <= fp32_mul(curv_cm2_r, curv_ds1_sq_r);
            curv_lhs_r  <= fp32_mul(FP32_FOUR, curv_cross_sq_r);
          end
          state_r <= ST_CURV_PREP_C;
        end

        ST_CURV_PREP_C: begin
          if (curv_metric_valid_r)
            curv_rhs2_r <= fp32_mul(curv_rhs1_r, curv_ds2_sq_r);
          state_r <= ST_CURV_CMP;
        end

        ST_CURV_CMP: begin
          if (curv_metric_valid_r) begin
            logic [31:0] rhs;
            rhs = fp32_mul(curv_rhs2_r, curv_dac_sq_r);  // final mul: 1 DSP pair only
            if (fp32_lt(rhs, curv_lhs_r)) fault_r[3] <= 1'b1;
          end

          if (idx_wp_r >= WP_LAST2) begin
            idx_wp_r  <= '0;
            idx_obj_r <= '0;
            state_r   <= ST_COLL_DIST;
          end else begin
            idx_wp_r <= idx_wp_r + 1'b1;
            state_r  <= ST_CURV_LOAD;
          end
        end

        // CHECK 4: Collision clearance split over 2 states.
        ST_COLL_DIST: begin
          if (idx_obj_r < obj_cnt) begin
            coll_dist_sq_r <= fp32_aabb_dist_sq(
              wp_x_r[idx_wp_r], wp_y_r[idx_wp_r],
              obj_cx[idx_obj_r], obj_cy[idx_obj_r],
              obj_hl[idx_obj_r], obj_hw[idx_obj_r]);
            coll_min_sq_r <= fp32_mul(csr_min_clear, csr_min_clear);
          end else begin
            coll_dist_sq_r <= '0;
            coll_min_sq_r  <= '0;
          end
          state_r <= ST_COLL_CMP;
        end

        ST_COLL_CMP: begin
          if (idx_obj_r < obj_cnt && fp32_lt(coll_dist_sq_r, coll_min_sq_r))
            fault_r[4] <= 1'b1;

          if (idx_obj_r == OBJ_LAST || idx_obj_r == OBJ_W'(obj_cnt) - 1) begin
            idx_obj_r <= '0;
            if (idx_wp_r == WP_LAST) begin idx_wp_r <= '0; state_r <= ST_CHK_LANE; end
            else begin
              idx_wp_r <= idx_wp_r + 1'b1;
              state_r  <= ST_COLL_DIST;
            end
          end else begin
            idx_obj_r <= idx_obj_r + 1'b1;
            state_r   <= ST_COLL_DIST;
          end
        end

        // CHECK 5: Lane boundary
        ST_CHK_LANE: begin
          begin
            logic [31:0] py, l_left, l_right;
            py      = wp_y_r[idx_wp_r];
            l_left  = fp32_sub(lane_left_y[idx_wp_r],  csr_lane_margin);
            l_right = fp32_add(lane_right_y[idx_wp_r], csr_lane_margin);
            // Fault if py is OUTSIDE lane bounds: py < l_left OR l_right < py
            if (fp32_lt(py, l_left) || fp32_lt(l_right, py)) fault_r[5] <= 1'b1;
          end

            if (idx_wp_r == WP_LAST) begin idx_wp_r <= '0; state_r <= ST_DONE; end
            else                          idx_wp_r <= idx_wp_r + 1'b1;
        end

        ST_DONE: begin
          fault_flags  <= fault_r;
          result_valid <= 1'b1;

          if (fault_r == 6'b0) begin
            traj_valid <= 1'b1;
            for (int i = 0; i < NUM_WP; i++) begin
              fb_x[i] <= wp_x_r[i];
              fb_y[i] <= wp_y_r[i];
              fb_v[i] <= wp_v_r[i];
            end
            fb_valid <= 1'b1;
          end else begin
            traj_valid <= 1'b0;
            build_estop_traj();  // writes fb_x/y/v and fb_valid directly
          end

          state_r  <= ST_IDLE;
        end

        default: state_r <= ST_IDLE;
      endcase
    end
  end : fsm_seq

  // synthesis translate_off
  always_ff @(posedge clk) begin
    if (result_valid) begin
      if (|fault_flags)
        $display("[TSC] t=%0t  FAULT flags=%06b  traj_valid=%0b",
                 $time, fault_flags, traj_valid);
      else
        $display("[TSC] t=%0t  PASS  traj_valid=1", $time);
    end
  end
  // synthesis translate_on

endmodule : trajectory_sanity_checker

`default_nettype wire
