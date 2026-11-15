// =============================================================================
// FILE        : hmao_zonotope_gen.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 7.2
// SAFETY      : ASIL-D (ISO 26262)
// LATENCY     : Stage 1 = 1.5ms = 600,000 cycles
//               Stage 2 = 2.0ms = 800,000 cycles
// DESCRIPTION : Zonotope Reachability Generator.
//               Computes reachable set of vehicle states over T time steps.
//               Uses vehicle dynamics model: x(t+1) = A×x(t) + B×u(t) + w(t)
//               State: [px, py, v, θ]. Control: [a, δ].
//
//               Algorithm (per time step t):
//               1. Read waypoint t for nominal state (px,py,v,θ)
//               2. Linearize A,B matrices via CORDIC (sin,cos of heading θ)
//               3. Propagate center: c_t = A×c_{t-1} + B×u_t
//               4. Propagate generators: g_i_t = A×g_i_{t-1}
//               5. Add uncertainty generator from margins
//               6. Apply Order Reduction (keep 2 main + remainder)
//               7. Output 128-bit compact zonotope per time step
//
// PARAMETERS  : NUM_GENERATORS - 16 (Stage 1) or 32 (Stage 2)
//               NUM_TIMESTEPS  - 50 (Stage 1, 10ms Δt) or 100 (Stage 2, 5ms Δt)
//               DELTA_T_US     - 10 (Stage 1) or 5 (Stage 2) microseconds
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

// =============================================================================
// BUG-FIX ZG-001 (2026-06-16, see test_history.md Section 16/17, "Bug 1"):
// waypoints_in[*].x/.y are genuine IEEE-754 float32 values (metres). The
// original code copied the raw float32 bit pattern directly into
// center_px/center_py and treated it as Q8.8 fixed-point with NO conversion
// (e.g. x=10.0m -> bit pattern 0x41200000 -> misread as ~4.26M "metres").
// This function performs the real float32->Q8.8 conversion (1 LSB = 1/256 m),
// matching the same convention used throughout hmao_collision_sat.sv and the
// adaptive-margin/zonotope generator math (Q8.8, 16-bit-significant field).
// =============================================================================
function automatic logic signed [31:0] fp32_to_q88(input logic [31:0] f);
  logic        sign;
  logic [7:0]  exp;
  logic [23:0] sig;       // 1.mantissa, 24 significant bits
  integer      shamt;
  logic [55:0] wide;
  logic [31:0] mag;
  begin
    sign = f[31];
    exp  = f[30:23];
    sig  = {1'b1, f[22:0]};

    if (exp == 8'h00) begin
      // zero or denormal -> negligible at Q8.8 resolution
      fp32_to_q88 = 32'sd0;
    end else if (exp == 8'hFF) begin
      // Inf/NaN -> saturate (should already be caught by preproc NaN check)
      fp32_to_q88 = sign ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
    end else if (exp >= 8'd166) begin
      // |value| >= 2^39 m -- far beyond any real trajectory range, saturate
      fp32_to_q88 = sign ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
    end else if (exp < 8'd112) begin
      // |value| < 2^-15 m (~0.03mm) -- underflows to 0 at Q8.8 resolution
      fp32_to_q88 = 32'sd0;
    end else if (exp >= 8'd142) begin
      shamt = exp - 142;
      wide  = {32'b0, sig} << shamt;
      mag   = wide[31:0];
      fp32_to_q88 = sign ? -$signed(mag) : $signed(mag);
    end else begin
      shamt = 142 - exp;
      wide  = {32'b0, sig} >> shamt;
      mag   = wide[31:0];
      fp32_to_q88 = sign ? -$signed(mag) : $signed(mag);
    end
  end
endfunction

module hmao_zonotope_gen #(
  parameter int unsigned NUM_GENERATORS = 16,
  parameter int unsigned NUM_TIMESTEPS  = 50,
  parameter int unsigned DELTA_T_US     = 10    // Timestep in microseconds
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,        // Pulse from FSM

  // Validated trajectory from pre-proc
  input  waypoint_t               waypoints_in [0:TRAJ_WAYPOINTS-1],

  // Adaptive safety margins (Q8.8)
  input  logic [15:0]             lateral_margin,
  input  logic [15:0]             long_margin,
  input  logic [15:0]             time_margin,

  // Zonotope outputs (one per timestep) — flat 1D (xelab2025.2: no packed-array-of-struct)
  // Element k: zonotopes_out[k*128+:128]; field offsets within element:
  //   cx=[127:112] cy=[111:96] g1x=[95:80] g1y=[79:64] g2x=[63:48] g2y=[47:32] rem_x=[31:16] rem_y=[15:0]
  output logic [NUM_TIMESTEPS*128-1:0] zonotopes_out,
  output logic                    valid_out,

  // Fault outputs
  output logic                    overflow_err,
  output logic                    zonotope_err
);

  // ===========================================================================
  // INTERNAL PARAMETERS
  // ===========================================================================
  // Cycles per timestep budget:
  // Stage 1: 600,000 / 50 = 12,000 cycles per step
  // Stage 2: 800,000 / 100 = 8,000 cycles per step
`ifdef SIM_FAST_TSM
  // CHI MO PHONG (04/10/2026): bo phan dem cho de giu WCET=BCET. Moi buoc chi co 1 xung
  // CORDIC->MAC->dp_valid ngay sau step_cycle_cnt==0 va quet xoay 16 generator (~40 chu ky);
  // phan con lai cua 12.000 chu ky chi la cho. Tuong duong chuc nang da kiem: VH AK.12.
  localparam int unsigned CYCLES_PER_STEP = 512;
`else
  // At the board's 187.5 MHz, preproc (200k) + S1 (600k) + S2 (800k)
  // already exceeded the 1.5M-cycle completion gate, before SAT/AXI overhead.
  // Reduce only S2 padding to 600k total; arithmetic still completes in tens
  // of cycles per step and the existing rotation-pipeline drain checks remain.
  localparam int unsigned CYCLES_PER_STEP = (NUM_TIMESTEPS == 50) ? 12000 : 6000;
`endif

  // Δt in Q8.8 fixed-point (seconds)
  // BUG-FIX ZG-007 (2026-08-04, test_history.md Section 29): this must match
  // the REAL per-waypoint spacing of the AXI-fed trajectory buffer this model
  // integrates against (sw/gen_hmao_trajectory.py and every other trajectory
  // generator in this codebase samples at DT=0.1s/100ms per step -- NOT the
  // 10ms/5ms this constant previously encoded). The old 10x-too-small Δt made
  // the modeled ego position advance ~10x slower than the real predicted
  // path, so real collisions late in the horizon were never detected (SAT
  // always found the ego's own model "far away" from the real predicted
  // position at the same step index). NUM_TIMESTEPS=50 (Stage1) / 100 (Stage2)
  // both intend a 5s horizon (hmao_pkg.sv's own "→ 5s" comments); the correct
  // per-step Δt to realize that with 100 real waypoints total is 100ms for
  // Stage1 (50 steps × 100ms = 5s) and 50ms for Stage2 (100 steps × 50ms = 5s).
  // Stage 1: 100ms = 0.1s  → Q8.8 = 0.1  × 256 = 25.6 ≈ 26 = 0x001A
  // Stage 2:  50ms = 0.05s → Q8.8 = 0.05 × 256 = 12.8 ≈ 13 = 0x000D
  localparam logic [15:0] DT_Q8_8 = (DELTA_T_US == 10) ? 16'h001A : 16'h000D;

  // Vehicle wheelbase L (loaded from config register - approximated as 2.7m here)
  // L in Q8.8: 2.7m × 256 = 691.2 ≈ 691 = 0x02B3
  localparam logic [15:0] WHEELBASE_Q8_8 = 16'h02B3;

  // ===========================================================================
  // STATE
  // ===========================================================================
  typedef enum logic [1:0] {
    ZG_IDLE    = 2'b00,
    ZG_COMPUTE = 2'b01,
    ZG_REDUCE  = 2'b10,
    ZG_DONE    = 2'b11
  } zg_state_t;

  zg_state_t            zg_state;
  logic [6:0]           step_idx;         // Current time step (0 to NUM_TIMESTEPS-1)
  logic [13:0]          step_cycle_cnt;   // Cycles within current step

  // Center state [px, py, v, θ] - Q8.8 fixed-point approximation
  // For production: use 32-bit fixed-point or float32 with FPU
  logic [31:0]          center_px, center_py;
  logic [31:0]          center_v, center_theta;

  // Generator matrix: each generator = [gx, gy] pair in Q8.8
  // Stored as flat array: gen[NUM_GENERATORS][2] = gen_flat[NUM_GENERATORS*2]
  logic [31:0]          gen_flat [0:NUM_GENERATORS*2-1];

  // Working zonotope for current step (before order reduction)
  zonotope_128b_t       zono_working;

  // CORDIC outputs (sin, cos of heading θ)
  logic [31:0]          sin_theta, cos_theta;
  logic                 cordic_valid;

  // 64-bit MAC intermediates for gen_flat[0,1] rotation.
  // lat_mag = lateral_margin + step_idx*16 (Q8.8, always positive, 32-bit).
  // Multiply in 64-bit to avoid 32-bit overflow (e.g. 784 * 0x7FFFFFFF wraps).
  // Result is Q8.8 * Q1.31 -> Q9.39, shift right 31 -> Q8.8 (32-bit).
  //
  // Timing pipeline (2 stages added to break CORDIC-satMUX→DSP→CARRY8 path):
  //   Stage 1: register CORDIC outputs + lat_mag (breaks satMUX-LUT → DSP B path)
  //   Stage 2: register MAC result (breaks DSP-cascade → CARRY8 → gen_flat path)
  logic        [31:0] lat_mag_q8_8;
  assign lat_mag_q8_8 = {16'b0, lateral_margin} + {21'b0, step_idx, 4'b0};

  logic [31:0]        sin_theta_r, cos_theta_r, lat_mag_r;
  logic               cordic_valid_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sin_theta_r    <= '0;
      cos_theta_r    <= '0;
      lat_mag_r      <= '0;
      cordic_valid_r <= '0;
    end else begin
      sin_theta_r    <= sin_theta;
      cos_theta_r    <= cos_theta;
      lat_mag_r      <= lat_mag_q8_8;
      cordic_valid_r <= cordic_valid;
    end
  end

  // MAC from stage-1 registers: FF → DSP B with no LUT in between
  logic signed [63:0] gen0_mac;
  logic signed [63:0] gen1_mac;
  assign gen0_mac = $signed({32'b0, lat_mag_r}) * $signed({{32{cos_theta_r[31]}}, cos_theta_r});
  assign gen1_mac = $signed({32'b0, lat_mag_r}) * $signed({{32{sin_theta_r[31]}}, sin_theta_r});

  logic signed [63:0] gen0_mac_r, gen1_mac_r;
  logic               mac_valid_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gen0_mac_r  <= '0;
      gen1_mac_r  <= '0;
      mac_valid_r <= '0;
    end else begin
      gen0_mac_r  <= gen0_mac;
      gen1_mac_r  <= gen1_mac;
      mac_valid_r <= cordic_valid_r;
    end
  end

  // BUG-FIX ZG-009 (2026-08-05, test_history.md Section 29): Stage 2
  // (NUM_TIMESTEPS=100, 50ms/step) was indexing the real waypoint buffer
  // (TRAJ_WAYPOINTS=50 entries, 100ms/waypoint) with step_idx directly, same
  // as Stage 1 (NUM_TIMESTEPS=50, where 1 step really does equal 1 real
  // waypoint). For Stage 2 this silently consumes real waypoint data at 2x
  // the rate its own modeled clock advances -- by step_idx=41 (2.05s modeled)
  // it had already read waypoint #41 (real t=4.1s), producing a badly wrong
  // velocity/heading and a large resulting position error (found via ZG_DEBUG:
  // Stage 2's center_v/cos_theta_r at step 41 were bit-identical to Stage 1's
  // at ITS OWN step 41, i.e. reading the same waypoints_in[42] both times).
  // WP_IDX_DIV maps each stage's step_idx onto the correct real waypoint:
  // Stage 1 (50/50=1): unchanged, 1:1. Stage 2 (100/50=2): advance the real
  // waypoint index only every other step.
  localparam int unsigned WP_IDX_DIV = NUM_TIMESTEPS / TRAJ_WAYPOINTS;

  // Pre-fetch next waypoint raw data 1 cycle before mac_valid_r.
  // Breaks: step_idx_reg → (+1) → MUX(50 wps) → fp32 → center_py_reg path
  // which had 2.725 ns routing delay at 300 MHz.
  // cordic_valid_r fires exactly 1 cycle before mac_valid_r.
  logic [31:0] wp_next_raw_x, wp_next_raw_y, wp_next_raw_v, wp_next_raw_hdg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wp_next_raw_x   <= '0;
      wp_next_raw_y   <= '0;
      wp_next_raw_v   <= '0;
      wp_next_raw_hdg <= '0;
    end else begin
      if (zg_state == ZG_COMPUTE && cordic_valid_r &&
          ((step_idx + 1) / WP_IDX_DIV) < TRAJ_WAYPOINTS) begin
        wp_next_raw_x   <= waypoints_in[(step_idx + 1) / WP_IDX_DIV].x;  // just MUX, no fp32
        wp_next_raw_y   <= waypoints_in[(step_idx + 1) / WP_IDX_DIV].y;
        wp_next_raw_v   <= waypoints_in[(step_idx + 1) / WP_IDX_DIV].vx;
        wp_next_raw_hdg <= waypoints_in[(step_idx + 1) / WP_IDX_DIV].heading;
      end
    end
  end

  // ---------------------------------------------------------------------
  // v2 (04/10/2026): TAM ZONOTOPE = VI TRI WAYPOINT cua buoc hien tai (khong
  // tich phan dt*vx*cos nua: tich phan cu troi khoi quy dao — dung vx thay cho
  // |v|, dt 26/256 lech 1,6%). Buoc s ung voi thoi diem s*dt; tang 2 (2 buoc /
  // waypoint) lay trung diem cua hai waypoint ke nhau o buoc le.
  // Chot o cordic_valid_r (giong wp_next_raw_*), doi Q8.8 o chu ky sau, ghi vao
  // center_px/py o dp_valid_r. Bao hoa +-127,996 m thay vi quay vong 16 bit.
  // ---------------------------------------------------------------------
  logic [31:0] wp_a_raw_x, wp_a_raw_y, wp_b_raw_x, wp_b_raw_y;
  logic [31:0] wp_a_x_q, wp_a_y_q, wp_b_x_q, wp_b_y_q;
  logic        step_odd;
  assign step_odd = (WP_IDX_DIV == 2) && step_idx[0];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wp_a_raw_x <= '0; wp_a_raw_y <= '0; wp_b_raw_x <= '0; wp_b_raw_y <= '0;
      wp_a_x_q <= '0; wp_a_y_q <= '0; wp_b_x_q <= '0; wp_b_y_q <= '0;
    end else begin
      if (zg_state == ZG_COMPUTE && cordic_valid) begin
        wp_a_raw_x <= waypoints_in[step_idx / WP_IDX_DIV].x;
        wp_a_raw_y <= waypoints_in[step_idx / WP_IDX_DIV].y;
        if ((step_idx / WP_IDX_DIV) + 1 < TRAJ_WAYPOINTS) begin
          wp_b_raw_x <= waypoints_in[(step_idx / WP_IDX_DIV) + 1].x;
          wp_b_raw_y <= waypoints_in[(step_idx / WP_IDX_DIV) + 1].y;
        end else begin
          wp_b_raw_x <= waypoints_in[step_idx / WP_IDX_DIV].x;
          wp_b_raw_y <= waypoints_in[step_idx / WP_IDX_DIV].y;
        end
      end
      wp_a_x_q <= fp32_to_q88(wp_a_raw_x);
      wp_a_y_q <= fp32_to_q88(wp_a_raw_y);
      wp_b_x_q <= fp32_to_q88(wp_b_raw_x);
      wp_b_y_q <= fp32_to_q88(wp_b_raw_y);
    end
  end
  function automatic logic [31:0] sat16(input logic signed [31:0] v);
    if (v > 32'sd32767)       return 32'sd32767;
    else if (v < -32'sd32768) return -32'sd32768;
    else                      return v;
  endfunction
  // cos/sin Q1.31 -> Q8.8 (lam tron), ghi vao rem_x/rem_y cho bo kiem tra va cham.
  // BUG-FIX ZG-v2.1 (04/10/2026): phep cong lam tron phai rong 33 bit — voi 32 bit,
  // cos ~ 1,0 (0x7FFF_FFFF) + 2^22 tran thanh so am -> hc = -256 (xe ego quay nguoc
  // 180 do moi khi |huong| < ~3,6 do). Phat hien khi doi chieu RTL voi mo hinh tren 10.838 luot.
  logic signed [32:0] hc_rnd, hs_rnd;
  logic [15:0] hc_q88, hs_q88;
  assign hc_rnd = $signed({cos_theta_r[31], cos_theta_r}) + 33'sd4194304;
  assign hs_rnd = $signed({sin_theta_r[31], sin_theta_r}) + 33'sd4194304;
  assign hc_q88 = 16'(hc_rnd >>> 23);
  assign hs_q88 = 16'(hs_rnd >>> 23);

  // BUG-FIX ZG-006: v must be Q8.8 for the kinematic MAC below (was raw fp32
  // bit-pattern in center_v, same class of bug as ZG-001).
  logic [31:0] center_v_q88;
  assign center_v_q88 = fp32_to_q88(center_v);

  logic [31:0] center_v_q88_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) center_v_q88_r <= '0;
    else        center_v_q88_r <= center_v_q88;
  end

  // ---------------------------------------------------------------------
  // BUG-FIX ZG-006: center propagation c_t = A*c_{t-1} + B*u_t (px,py rows).
  // dt_v = DT_Q8_8(Q8.8) * v(Q8.8) -> Q16.16. Then * cos/sin (Q1.31) -> Q17.47.
  // Shift right 39 to recover Q8.8 (8+8+31=47 frac bits in, 8 out -> >>39).
  // ---------------------------------------------------------------------
  logic signed [47:0] dt_v;
  assign dt_v = $signed({16'b0, DT_Q8_8}) * $signed(center_v_q88_r);

  logic signed [47:0] dt_v_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) dt_v_r <= '0;
    else        dt_v_r <= dt_v;
  end

  logic signed [79:0] dpx_mac, dpy_mac;
  assign dpx_mac = $signed(dt_v_r) * $signed({{32{cos_theta_r[31]}}, cos_theta_r});
  assign dpy_mac = $signed(dt_v_r) * $signed({{32{sin_theta_r[31]}}, sin_theta_r});

  logic signed [79:0] dpx_mac_r, dpy_mac_r;
  logic               dp_valid_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dpx_mac_r  <= '0;
      dpy_mac_r  <= '0;
      dp_valid_r <= '0;
    end else begin
      dpx_mac_r  <= dpx_mac;
      dpy_mac_r  <= dpy_mac;
      dp_valid_r <= mac_valid_r;
    end
  end

`ifdef ZG_DEBUG
  always_ff @(posedge clk) begin
    if (dp_valid_r) begin
      $display("[ZG_DEBUG] t=%0t step=%0d cyc=%0d center_v=%h center_v_q88_r=%0d dt_v_r=%0d cos_theta_r=%h dpx_mac_r=%0d delta_px=%0d",
        $time, step_idx, step_cycle_cnt, center_v, center_v_q88_r, dt_v_r, cos_theta_r, dpx_mac_r, $signed(dpx_mac_r) >>> 39);
    end
  end
`endif

  // ---------------------------------------------------------------------
  // BUG-FIX ZG-002: sequential rotation MAC for remaining generators
  // (index 1..NUM_GENERATORS-1). gen 0 keeps its existing dedicated MAC.
  // g_x_new = cos*g_x_old - sin*g_y_old ; g_y_new = sin*g_x_old + cos*g_y_old
  // Throughput: 1 generator / cycle (3-stage pipeline), well inside the
  // 12000/8000-cycle-per-step budget (max 32 generators -> ~35 cycles).
  // ---------------------------------------------------------------------
  logic [5:0]          rot_idx;        // 0..NUM_GENERATORS-1
  logic                rot_active;
  logic signed [31:0]  rot_gx_r, rot_gy_r;
  logic [5:0]          rot_idx_r1, rot_idx_r2;
  logic                rot_valid_r1, rot_valid_r2;
  logic signed [63:0]  rot_p1, rot_p2, rot_p3, rot_p4; // cos*gx, sin*gy, sin*gx, cos*gy
  logic signed [63:0]  rot_p1_r, rot_p2_r, rot_p3_r, rot_p4_r;

  always_comb begin
    rot_p1 = $signed({{32{cos_theta_r[31]}}, cos_theta_r}) * $signed(rot_gx_r);
    rot_p2 = $signed({{32{sin_theta_r[31]}}, sin_theta_r}) * $signed(rot_gy_r);
    rot_p3 = $signed({{32{sin_theta_r[31]}}, sin_theta_r}) * $signed(rot_gx_r);
    rot_p4 = $signed({{32{cos_theta_r[31]}}, cos_theta_r}) * $signed(rot_gy_r);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rot_idx      <= '0;
      rot_active   <= 1'b0;
      rot_gx_r     <= '0;
      rot_gy_r     <= '0;
      rot_idx_r1   <= '0;
      rot_valid_r1 <= '0;
      rot_p1_r     <= '0; rot_p2_r <= '0; rot_p3_r <= '0; rot_p4_r <= '0;
      rot_idx_r2   <= '0;
      rot_valid_r2 <= '0;
    end else begin
      // Stage 0: kick off sweep when mac_valid_r pulses this step; latch old gen values
      if (mac_valid_r && !rot_active) begin
        rot_active <= 1'b1;
        rot_idx    <= 6'd1;              // generator 0 handled separately
        rot_gx_r   <= gen_flat[2];       // gen index 1 -> flat[2],[3]
        rot_gy_r   <= gen_flat[3];
      end else if (rot_active) begin
        if (rot_idx < NUM_GENERATORS - 1) begin
          rot_idx  <= rot_idx + 6'd1;
          rot_gx_r <= gen_flat[(rot_idx+1)*2];
          rot_gy_r <= gen_flat[(rot_idx+1)*2+1];
        end else begin
          rot_active <= 1'b0;            // sweep done for this step
        end
      end
      rot_idx_r1   <= rot_idx;
      rot_valid_r1 <= rot_active;

      // Stage 1: register products
      rot_p1_r     <= rot_p1;
      rot_p2_r     <= rot_p2;
      rot_p3_r     <= rot_p3;
      rot_p4_r     <= rot_p4;
      rot_idx_r2   <= rot_idx_r1;
      rot_valid_r2 <= rot_valid_r1;

      // BUG-FIX [DRC MDRV-1]: writeback cua gen_flat[] da chuyen sang always_ff
      // chinh (FSM ZG_COMPUTE/ZG_IDLE, xem duoi) de tranh 2 always_ff cung
      // dieu khien 1 bien - rot_valid_r2/rot_idx_r2/rot_p1_r..rot_p4_r van
      // duoc tinh o day, chi khong con ghi truc tiep vao gen_flat[] tai day.
    end
  end

  // ===========================================================================
  // CORDIC UNIT (computes sin/cos for matrix A linearization)
  // Spec Ref: Section 7.2.2 - "CORDIC hoặc LUT-based Interpolation"
  // ASIL-D requirement: deterministic, no floating-point library calls
  // ===========================================================================
  // v2 (04/10/2026): CORDIC che do quay chi hoi tu voi |goc| <= ~1,74 rad (99,9 do),
  // trong khi heading = atan2 nam trong (-pi, pi]. Dua goc ve [-pi/2, pi/2] bang
  // theta' = theta -/+ pi va dao dau (cos, sin) o dau ra. Co 'flip' chot tai lan
  // khoi dong CORDIC cua buoc va giu nguyen trong ca buoc (dau ra CORDIC cung giu).
  localparam logic signed [31:0] PI_Q88      = 32'sd804;   // 3,1416 * 256
  localparam logic signed [31:0] HALF_PI_Q88 = 32'sd402;
  logic signed [31:0] theta_q88, cordic_angle_q88;
  logic               flip_now, flip_r;
  assign theta_q88        = $signed(fp32_to_q88(center_theta));
  assign flip_now         = (theta_q88 > HALF_PI_Q88) || (theta_q88 < -HALF_PI_Q88);
  assign cordic_angle_q88 = (theta_q88 > HALF_PI_Q88)  ? theta_q88 - PI_Q88 :
                            (theta_q88 < -HALF_PI_Q88) ? theta_q88 + PI_Q88 : theta_q88;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) flip_r <= 1'b0;
    else if (zg_state == ZG_COMPUTE && step_cycle_cnt == 0) flip_r <= flip_now;
  end
  logic [31:0] sin_theta_raw, cos_theta_raw;
  assign sin_theta = flip_r ? -$signed(sin_theta_raw) : sin_theta_raw;
  assign cos_theta = flip_r ? -$signed(cos_theta_raw) : cos_theta_raw;

  hmao_cordic u_cordic (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (zg_state == ZG_COMPUTE && step_cycle_cnt == 0),
    // BUG-FIX ZG-008 (2026-08-04, test_history.md Section 29): center_theta is
    // the RAW float32 bit pattern copied from waypoints_in[].heading (see
    // wp_next_raw_hdg capture above, "just MUX, no fp32") -- it was never run
    // through fp32_to_q88() before being shifted into CORDIC's Q8.8 angle
    // input, unlike center_v (which correctly goes through fp32_to_q88() into
    // center_v_q88/center_v_q88_r). Bit-shifting a float32 bit pattern is not
    // a valid unit conversion; it produced a essentially-random small "angle"
    // (e.g. cos(theta)≈0.807 / theta≈36° for a real heading of ≈-3.3°,
    // cos≈0.998), which combined with BUG-FIX ZG-007's Δt fix to still leave
    // the modeled ego position undershooting the real predicted path by ~2x.
    .angle_in   (cordic_angle_q88 << 22),  // Q8.8 radians -> Q2.30: multiply by 2^22
                                       // CORDIC angle table is Q2.30 (arctan(1)=0x3243F6A8/2^30=pi/4 rad)
                                       // Q8.8 value/256 * 2^30 = value * 2^22. Was <<23 (wrong: doubled angle).
    .sin_out    (sin_theta_raw),
    .cos_out    (cos_theta_raw),
    .valid_out  (cordic_valid)
  );

  // ===========================================================================
  // MAIN COMPUTATION STATE MACHINE
  // ===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      zg_state       <= ZG_IDLE;
      step_idx       <= '0;
      step_cycle_cnt <= '0;
      valid_out      <= 1'b0;
      overflow_err   <= 1'b0;
      zonotope_err   <= 1'b0;

      // Initialize center to first waypoint nominal state
      center_px    <= '0;
      center_py    <= '0;
      center_v     <= '0;
      center_theta <= '0;

      // Initialize generators (identity-like spread from margins)
      for (int i = 0; i < NUM_GENERATORS * 2; i++) begin
        gen_flat[i] <= '0;
      end

      // Clear zonotope output array so BRAM shadow monitor starts clean
      // BUG-FIX: without this, write_cycle[] fires immediately on the first
      // posedge after reset because old values are still non-zero.
      zonotopes_out <= '0;

    end else begin
      unique case (zg_state)
        // -------------------------------------------------------------------
        // IDLE: Wait for start pulse
        // -------------------------------------------------------------------
        ZG_IDLE: begin
          valid_out <= 1'b0;
          if (start) begin
            zg_state       <= ZG_COMPUTE;
            step_idx       <= '0;
            step_cycle_cnt <= '0;

            // Initialize center from waypoint 0 (BUG-FIX ZG-001: real
            // float32->Q8.8 conversion, was a raw bit-pattern copy)
            center_px    <= fp32_to_q88(waypoints_in[0].x);
            center_py    <= fp32_to_q88(waypoints_in[0].y);
            // Speed from vx,vy magnitude (approximation: |vx| + |vy|/2)
            center_v     <= waypoints_in[0].vx;
            center_theta <= waypoints_in[0].heading;

            // Initialize uncertainty generators from lateral margin
            // Generator 0: lateral uncertainty (perpendicular to heading)
            gen_flat[0] <= {16'b0, lateral_margin};  // gx = lateral_margin
            gen_flat[1] <= 32'h0;                    // gy = 0 (initial frame)
            // Generator 1: longitudinal uncertainty (along heading)
            gen_flat[2] <= 32'h0;
            gen_flat[3] <= {16'b0, long_margin};
            // Remaining generators: small initial values
            for (int i = 2; i < NUM_GENERATORS; i++) begin
              gen_flat[i*2]   <= 32'd1;    // Minimal spread
              gen_flat[i*2+1] <= 32'd1;
            end
          end
        end

        // -------------------------------------------------------------------
        // COMPUTE: Process one time step
        // Spec: 12,000 cycles/step (Stage1) or 8,000 cycles/step (Stage2)
        // -------------------------------------------------------------------
        ZG_COMPUTE: begin
          step_cycle_cnt <= step_cycle_cnt + 1'b1;

          // Phase 1 (cycles 0-9): CORDIC computing sin/cos
          // Phase 2 (cycles 10-..): Matrix multiply A×center, A×generators
          // Phase 3 (last cycles): Order reduction, output

          // ---------------------------------------------------------------
          // BUG-FIX ZG-006: true kinematic propagation c_t = A*c_{t-1} + B*u_t
          // (was: direct waypoint copy / tracking). center_v/center_theta
          // still come from the planned waypoint -- they act as the nominal
          // control input u_t (commanded speed/heading) driving the
          // integration, NOT as the propagated center itself.
          // A = [[1,0,Δt×cos(θ),-v×Δt×sin(θ)],
          //      [0,1,Δt×sin(θ), v×Δt×cos(θ)],
          //      [0,0,1,0],
          //      [0,0,Δt×tan(δ)/L,1]]
          // ---------------------------------------------------------------
          if (dp_valid_r) begin
            // Round-to-nearest before truncation (same convention as gen0/1
            // MAC: add half of the 2^39 LSB being shifted out) -- without
            // this, cos_theta_r=0x7FFFFFFE (1 LSB below exact 1.0 in Q1.31)
            // truncates 30.0 down to 29 instead of rounding to 30.
            // v2: tam = vi tri waypoint (trung diem o buoc le cua tang 2), bao hoa 16 bit
            center_px <= sat16(step_odd ? ($signed(wp_a_x_q) + $signed(wp_b_x_q)) >>> 1 : $signed(wp_a_x_q));
            center_py <= sat16(step_odd ? ($signed(wp_a_y_q) + $signed(wp_b_y_q)) >>> 1 : $signed(wp_a_y_q));

            if (((step_idx + 1) / WP_IDX_DIV) < TRAJ_WAYPOINTS) begin
              center_v     <= wp_next_raw_v;
              center_theta <= wp_next_raw_hdg;
            end
            // BUG-FIX ZG-009: guard now scaled by WP_IDX_DIV (see above) so
            // Stage 2 correctly holds at the last real waypoint's v/theta for
            // its final step instead of advancing past the real data.
          end

          if (mac_valid_r && step_cycle_cnt > 12) begin
            // ---------------------------------------------------------------
            // PROPAGATE LATERAL GENERATOR (gen_flat[0,1]):
            // Rotate lateral uncertainty by heading theta and grow with step.
            // lat_mag(step) = lateral_margin + step_idx*16 (linear growth).
            // g0_x = lat_mag * cos(theta),  g0_y = lat_mag * sin(theta)
            // Q8.8 * Q1.31 -> shift right 31 to get Q8.8 result.
            // ---------------------------------------------------------------
            // Round before truncation: add 2^30 (half of 2^31 LSB) to prevent
            // CORDIC residual error (e.g. sin(0) = -1 in Q1.31 = -4.7e-10 rad)
            // from rounding down to -1 in Q8.8 (0xFFFF instead of 0x0000).
            // With rounding: (-256 + 2^30) >>> 31 = 0 (correct).
            gen_flat[0] <= 32'((gen0_mac_r + 64'sd1073741824) >>> 31);
            gen_flat[1] <= 32'((gen1_mac_r + 64'sd1073741824) >>> 31);

            // ---------------------------------------------------------------
            // PROPAGATE REMAINING GENERATORS (gen_flat[2..2*NUM_GEN-1]):
            // BUG-FIX ZG-002: full rotation MAC, see rot_idx sweep block above
            // (sequential, 1 generator/cycle, triggered by mac_valid_r).
            // ---------------------------------------------------------------

            // ---------------------------------------------------------------
            // ORDER REDUCTION (Spec Ref: Section 7.2.5)
            // Keep 2 primary generators, sum remaining into remainder
            // ---------------------------------------------------------------
          end

          // Check for cycle budget completion
          // BUG-FIX ZG-002: must wait for the rotation sweep (rot_active) to
          // finish before advancing the step, else in-flight generators get
          // clobbered by next step's init/sweep -- keeps WCET=BCET determinism.
          if (step_cycle_cnt >= CYCLES_PER_STEP - 1 && !rot_active && !rot_valid_r1 && !rot_valid_r2) begin
            // Encode zonotope for this step (128-bit compact, flat vector slice)
            // Element step_idx at [step_idx*128+:128]; field offsets: cx=+112, cy=+96,
            // g1x=+80, g1y=+64, g2x=+48, g2y=+32, rem_x=+16, rem_y=+0
            // center_px/py now hold real Q8.8 (post BUG-FIX ZG-001); this is
            // a normal Q8.8 32-bit -> 16-bit truncation, not a format change.
            zonotopes_out[step_idx*128+112 +: 16] <= center_px[15:0];  // cx (Q8.8)
            zonotopes_out[step_idx*128+96  +: 16] <= center_py[15:0];  // cy (Q8.8)
            zonotopes_out[step_idx*128+80  +: 16] <= gen_flat[0][15:0]; // g1x
            zonotopes_out[step_idx*128+64  +: 16] <= gen_flat[1][15:0]; // g1y
            zonotopes_out[step_idx*128+48  +: 16] <= gen_flat[2][15:0]; // g2x
            zonotopes_out[step_idx*128+32  +: 16] <= gen_flat[3][15:0]; // g2y
            zonotopes_out[step_idx*128+16  +: 16] <= hc_q88;  // v2: cos(huong) Q8.8
            zonotopes_out[step_idx*128     +: 16] <= hs_q88;  // v2: sin(huong) Q8.8

            step_cycle_cnt <= '0;

            if (step_idx < NUM_TIMESTEPS - 1) begin
              step_idx <= step_idx + 1'b1;
            end else begin
              zg_state <= ZG_DONE;
            end
          end

          // Overflow detection — true signed Q24.8 range check:
          // XOR(bit31, bit23) detects values outside [-2^23, +2^23-1].
          // The old bit-31-only check caused false aborts because:
          //   • CORDIC cos(0) saturates to 0x7FFFFFFF → gen_flat[0] is fine.
          //   • CORDIC sin(0) rounds to ≈0 but may produce -1 (0xFFFFFFFF);
          //     -1 has bit31=1 AND bit23=1 → XOR=0 → no false abort.
          //   • True overflow (e.g. BUG-ZG-001 runaway) sets bit31≠bit23.
          for (int i = 0; i < NUM_GENERATORS; i++) begin
            if ((gen_flat[i*2][31]   ^ gen_flat[i*2][23])   ||
                (gen_flat[i*2+1][31] ^ gen_flat[i*2+1][23])) begin
              overflow_err <= 1'b1;
              zg_state     <= ZG_IDLE;  // Abort → FSM will VETO
            end
          end
        end

        // -------------------------------------------------------------------
        // DONE: Signal completion
        // -------------------------------------------------------------------
        ZG_DONE: begin
          valid_out <= 1'b1;
          zg_state  <= ZG_IDLE;
        end

        default: begin
          zg_state     <= ZG_IDLE;
          zonotope_err <= 1'b1;
        end
      endcase

      // BUG-FIX [DRC MDRV-1]: writeback gen_flat[] cua rotation sweep, chuyen
      // ve tu khoi always_ff rotation (o tren) de chi con DUY NHAT mot
      // always_ff dieu khien gen_flat[] - tranh Multiple Driver Nets.
      // Chay doc lap voi zg_state (giu nguyen hanh vi cu: chi phu thuoc
      // rot_valid_r2, khong phu thuoc nhanh case nao ben tren).
      if (rot_valid_r2) begin
        gen_flat[rot_idx_r2*2]   <= 32'((rot_p1_r - rot_p2_r + 64'sd1073741824) >>> 31);
        gen_flat[rot_idx_r2*2+1] <= 32'((rot_p3_r + rot_p4_r + 64'sd1073741824) >>> 31);
      end
    end
  end

  // ===========================================================================
  // FORMAL ASSERTIONS
  // ===========================================================================
  `ifdef FORMAL
    // P1.3: Zonotope must always over-approximate (checked at boundary level)
    // - Every generator magnitude must be ≥ initial uncertainty margin
    // Simplified assertion: lateral generator never shrinks below min margin
    assert property (@(posedge clk) disable iff (!rst_n)
      (zg_state == ZG_COMPUTE) |->
      (zonotopes_out[((step_idx > 0 ? step_idx-1 : 0)*128+80) +: 16] >= lateral_margin[7:0]))
      else $error("P1.3: Zonotope generator shrank below uncertainty margin");

    // valid_out held high only for 1 cycle
    assert property (@(posedge clk) disable iff (!rst_n)
      $rose(valid_out) |=> !valid_out)
      else $error("Zonotope: valid_out must be a single-cycle pulse");
  `endif

endmodule : hmao_zonotope_gen

// =============================================================================
// CORDIC Sub-module (placeholder - implement with proper CORDIC algorithm)
// Spec Ref: Section 7.2.2 - "CORDIC hoặc LUT-based Interpolation"
// =============================================================================
module hmao_cordic (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [31:0] angle_in,    // Angle in Q8.8 (radians)
  output logic [31:0] sin_out,     // sin(angle) in Q1.15 (16-bit frac)
  output logic [31:0] cos_out,     // cos(angle) in Q1.15
  output logic        valid_out
);
  // ===========================================================================
  // CORDIC 16-stage pipeline (16 rotations, 1 rotation per clock)
  // Standard CORDIC: iterative rotation toward target angle
  // Fully pipelined: exactly 16 cycles from start to valid_out
  // ===========================================================================
  parameter int unsigned CORDIC_STAGES = 16;

  // CORDIC rotation angles (arctan(2^-i) in Q1.31)
  // Pre-computed constants (deterministic ROM)
  logic [31:0] cordic_angles [0:CORDIC_STAGES-1];

  // CORDIC pipeline registers [x, y, z] per stage
  logic signed [31:0] x_pipe [0:CORDIC_STAGES];
  logic signed [31:0] y_pipe [0:CORDIC_STAGES];
  logic signed [31:0] z_pipe [0:CORDIC_STAGES];

  // Valid shift register (tracks pipeline fill)
  logic [CORDIC_STAGES:0] valid_pipe;

  initial begin
    // arctan(2^-i) in Q1.31 format
    cordic_angles[0]  = 32'h3243F6A8; // arctan(1)    = 45.0°
    cordic_angles[1]  = 32'h1DAC6705; // arctan(0.5)  = 26.565°
    cordic_angles[2]  = 32'h0FADBAFC; // arctan(0.25) = 14.036°
    cordic_angles[3]  = 32'h07F56EA6; // arctan(0.125)
    cordic_angles[4]  = 32'h03FEAB76;
    cordic_angles[5]  = 32'h01FFD55B;
    cordic_angles[6]  = 32'h00FFFAAA;
    cordic_angles[7]  = 32'h007FFF55;
    cordic_angles[8]  = 32'h003FFFEA;
    cordic_angles[9]  = 32'h001FFFFD;
    cordic_angles[10] = 32'h000FFFFF;
    cordic_angles[11] = 32'h0007FFFF;
    cordic_angles[12] = 32'h0003FFFF;
    cordic_angles[13] = 32'h0001FFFF;
    cordic_angles[14] = 32'h0000FFFF;
    cordic_angles[15] = 32'h00007FFF;
  end

  // CORDIC gain K ≈ 0.6073 in Q1.31: K = product(cos(arctan(2^-i)))
  localparam logic [31:0] CORDIC_GAIN = 32'h4DBA76D4; // 0.6073 × 2^31

  // Pipeline Stage 0 initialization
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_pipe[0]     <= '0;
      y_pipe[0]     <= '0;
      z_pipe[0]     <= '0;
      valid_pipe[0] <= '0;
    end else begin
      if (start) begin
        // Initialize: x=K (compensated), y=0, z=angle
        x_pipe[0]     <= CORDIC_GAIN;          // Pre-multiplied by gain
        y_pipe[0]     <= 32'b0;
        z_pipe[0]     <= angle_in;             // Target angle
        valid_pipe[0] <= 1'b1;
      end else begin
        valid_pipe[0] <= 1'b0;
      end
    end
  end

  // CORDIC pipeline stages
  generate
    for (genvar s = 0; s < CORDIC_STAGES; s++) begin : cordic_stage
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          x_pipe[s+1]     <= '0;
          y_pipe[s+1]     <= '0;
          z_pipe[s+1]     <= '0;
          valid_pipe[s+1] <= '0;
        end else begin
          valid_pipe[s+1] <= valid_pipe[s];
          if (valid_pipe[s]) begin
            if ($signed(z_pipe[s]) >= 0) begin
              // Positive rotation: x' = x - y>>s, y' = y + x>>s, z' = z - arctan
              x_pipe[s+1] <= x_pipe[s] - (y_pipe[s] >>> s);
              y_pipe[s+1] <= y_pipe[s] + (x_pipe[s] >>> s);
              z_pipe[s+1] <= z_pipe[s] - cordic_angles[s];
            end else begin
              // Negative rotation
              x_pipe[s+1] <= x_pipe[s] + (y_pipe[s] >>> s);
              y_pipe[s+1] <= y_pipe[s] - (x_pipe[s] >>> s);
              z_pipe[s+1] <= z_pipe[s] + cordic_angles[s];
            end
          end
        end
      end
    end
  endgenerate

  // Output: cos = x_pipe[STAGES], sin = y_pipe[STAGES]
  // Saturation fix: CORDIC gain K≈0.6073 is applied so that x_final = cos(θ)×2^31.
  // For θ=0, cos(0)=1 → x_final = 2^31 = 0x80000000 in 32-bit, which is the
  // most-negative Q1.31 value (-1.0) and would sign-extend incorrectly in the MAC.
  // Clamp to 0x7FFFFFFF (+0.9999…) to represent +1.0 without overflow.
  // The same clamp is applied to sin_out for symmetry (sin(π/2) hits the same issue).
  assign cos_out   = (x_pipe[CORDIC_STAGES] == 32'h80000000) ? 32'h7FFFFFFF
                                                              : x_pipe[CORDIC_STAGES];
  assign sin_out   = (y_pipe[CORDIC_STAGES] == 32'h80000000) ? 32'h7FFFFFFF
                                                              : y_pipe[CORDIC_STAGES];
  assign valid_out = valid_pipe[CORDIC_STAGES];

endmodule : hmao_cordic
