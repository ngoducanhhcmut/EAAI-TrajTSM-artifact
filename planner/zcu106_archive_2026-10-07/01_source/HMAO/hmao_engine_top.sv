// =============================================================================
// FILE        : hmao_engine_top.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 6 (Multi-Stage Pipeline)
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : Top-level of HMAO Engine.
//               Instantiates and connects:
//               1. Pre-Processing Unit (CRC32, Kinematic check, BBox)
//               2. Adaptive Margin Controller (LUT-based, always combinational)
//               3. Stage 1 Zonotope Generator (16 generators, 50 steps)
//               4. ADMM Solver (15-stage unrolled, parallel with Stage 1)
//               5. Stage 1 Collision Checker (SAT)
//               6. Stage 2 Zonotope Generator (32 generators, 100 steps)
//               7. Stage 2 Collision Checker (SAT)
//               8. Control FSM (Hamming-3 state encoding)
//               9. Output Register Stage
//               10. Watchdog Timer (independent ring oscillator)
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module hmao_engine_top #(
  // v2 (04/10/2026): tham so bo kiem tra va cham (chon tren tap TRAIN nuScenes, VH AK.15)
  parameter int unsigned TSM_K_LONG         = 255,  // bien doc   = long_margin * K / 256 (~2,05 m)
  parameter int unsigned TSM_K_LAT          = 64,   // bien ngang = lateral_margin * K / 256 (~0,39 m)
  parameter int unsigned TSM_S1_CHECK_STEPS = 21    // buoc 0..20 = 0..2,0 s (chan troi Traj du doan)
) (
  input  logic          clk,        // 400 MHz ASIL-D
  input  logic          rst_n,      // Synchronous active-low

  // =========================================================================
  // CONTROL INPUT
  // =========================================================================
  input  logic          hmao_start,         // Single pulse from RISCV DCLS

  // =========================================================================
  // UNCERTAINTY VECTOR (from CDC module, ASIL-D side)
  // Spec Ref: Section 3.3
  // =========================================================================
  input  logic [7:0]    gps_quality,        // 0=bad, 255=good
  input  logic [7:0]    camera_quality,
  input  logic [7:0]    road_friction,
  input  logic [7:0]    actuator_health,
  input  logic [7:0]    weather_severity,

  // =========================================================================
  // AXI4 READ-ONLY MASTER (→ Trajectory Buffer & World Model via SMPU)
  // Spec Ref: Section 3.1, 3.2 - Master ID = 0x1A
  // =========================================================================
  axi4_ro_if.master     axi_ro,

  // =========================================================================
  // INTERNAL PIPELINE BUS (to/from sub-modules via interface)
  // =========================================================================
  hmao_pipe_if          pipe,

  // =========================================================================
  // WATCHDOG (independent ring oscillator clock)
  // Spec Ref: Section 9.3
  // =========================================================================
  input  logic          wdt_clk,            // Ring oscillator (NOT hmao_clk)

  // =========================================================================
  // OUTPUTS
  // =========================================================================
  output logic          hmao_complete,      // Edge-triggered IRQ → RISCV
  output logic          hmao_decision_out,  // 1=GRANT, 0=VETO (default=VETO)
  output logic [63:0]   hmao_violation_out, // Violation flags
  output logic [31:0]   hmao_status_out,    // Status register
  output logic [31:0]   hmao_latency_out,   // Cycle count of last verification
  output logic [15:0]   lateral_margin_out, // Q8.8 meters
  output logic [15:0]   long_margin_out,    // Q8.8 meters
  output logic [15:0]   time_margin_out,    // Q8.8 seconds

  // IRQ clear (from RISCV, written to REG_OFF_IRQ_CLEAR)
  input  logic          irq_clear,

  // =========================================================================
  // DEBUG OUTPUTS (test/monitoring only - non-safety)
  // =========================================================================
  output logic          debug_start_preproc, // Pulsed when FSM/preproc launched
  output logic [6:0]    debug_fsm_state_encoded, // Raw Hamming-encoded FSM state
  output logic          debug_hmao_start_received, // Monitoring: is hmao_start input HIGH?
  output logic          debug_preproc_valid,   // Preproc completion signal to FSM
  output logic          debug_preproc_error,   // Preproc error signal to FSM

  // =========================================================================
  // FAULT OUTPUTS (→ Fault Manager → SFI → FMU)
  // Spec Ref: Section 4.4
  // =========================================================================
  output hmao_fault_t   fault_out,
  output logic          fault_valid_out
);

  // ===========================================================================
  // INTERNAL SIGNALS
  // ===========================================================================

  // FSM state
  hmao_fsm_state_t      fsm_state, fsm_next;

  // FSM control signals to sub-modules
  logic                 start_preproc;
  logic                 start_s1;
  logic                 start_s2;
  logic                 start_admm;
  logic                 output_grant;
  logic                 output_veto;

  // Watchdog
  logic                 wdt_s1_timeout;
  logic                 wdt_s2_timeout;

  // Cycle counter for latency measurement
  logic [31:0]          cycle_counter;
  logic                 counter_en;

  // Violation / fault collection
  hmao_violation_t      violation_reg;
  hmao_fault_t          fault_reg;

  // Intermediate fault signals (collected from sub-modules, ORed into fault_reg)
  logic                 s1_zono_overflow, s1_sat_overflow, s2_zono_overflow;
  logic                 s1_zono_err, s2_zono_err;
  logic                 preproc_crc_fail, preproc_kinematic_fail, preproc_fmt_fail;
  logic                 admm_diverge_fault, wdt_fault;
  // preproc_crc_fail_gated: 1-cycle delayed, cleared on hmao_start.
  // WHY: preproc_crc_fail is sticky between runs (only resets in PP_CRC).
  //      Without gating, FSM enters FSM_PREPROC at cycle N+1 and sees stale
  //      crc_error=1 → FSM_ERROR before the new run's PP_CRC even starts.
  //      Clearing on hmao_start (cycle N) ensures crc_error=0 at cycle N+1.
  logic                 preproc_crc_fail_gated;
  logic                 preproc_fmt_fail_gated;

  // Sticky latches: hold one-cycle Stage 1 pipeline pulses until FSM reads them.
  // Required because SAT and ADMM complete 100k-600k cycles before zonotope gen,
  // so by the time FSM enters STAGE1_CHECK their one-cycle pulses are long gone.
  logic                 s1_no_collision_latch;
  logic                 s1_potential_latch;
  logic                 admm_done_latch;
  logic                 admm_diverged_latch;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_no_collision_latch <= 1'b0;
      s1_potential_latch    <= 1'b0;
      admm_done_latch       <= 1'b0;
      admm_diverged_latch   <= 1'b0;
    end else begin
      // Set on rising pulse
      if (pipe.s1_no_collision)      s1_no_collision_latch <= 1'b1;
      if (pipe.s1_potential_collide) s1_potential_latch    <= 1'b1;
      if (pipe.admm_done)            admm_done_latch       <= 1'b1;
      if (pipe.admm_diverged)        admm_diverged_latch   <= 1'b1;
      // Clear when FSM reaches a terminal or idle state (new run starts)
      if (fsm_state == FSM_IDLE || fsm_state == FSM_OUTPUT_GRANT ||
          fsm_state == FSM_OUTPUT_VETO || fsm_state == FSM_ERROR ||
          fsm_state == FSM_STAGE2_COMP) begin
        s1_no_collision_latch <= 1'b0;
        s1_potential_latch    <= 1'b0;
        admm_done_latch       <= 1'b0;
        admm_diverged_latch   <= 1'b0;
      end
    end
  end

  // Decision register (safe default = VETO = 0)
  logic                 decision_reg;

  // IRQ generation
  logic                 complete_latch;
  logic                 complete_edge;

  // ── Cach A: Constant-time completion (ASIL-D deterministic latency) ───────
  // All NORMAL completions (GRANT or non-fault VETO) fire hmao_complete at
  // exactly HMAO_FIXED_LATENCY_CY cycles after hmao_start, regardless of path.
  // Fault path (FSM_ERROR: WDT/CRC) bypasses padding and fires immediately so
  // MRM response is not delayed by the padding counter.
  // Formal property: ∀ normal input: hmao_complete ↑ at cycle HMAO_FIXED_LATENCY_CY
  // Measured VETO WCET: 1,412,296 cy  → 1,500,000 cy adds 6% guard margin.
`ifdef SIM_FAST_TSM
  // CHI MO PHONG (04/10/2026): bo dem do tre co dinh -> hmao_complete len ngay khi quyet dinh
  // duoc chot (bo dem bao hoa nen dieu kien == van dung). Bo dem chi dieu khien THOI DIEM bao
  // xong, khong tham gia quyet dinh / co vi pham. Tuong duong chuc nang da kiem: VH AK.12.
  localparam int HMAO_FIXED_LATENCY_CY = 2;
`else
  localparam int HMAO_FIXED_LATENCY_CY = 1_500_000;
`endif

  logic [20:0]          global_timer;       // Counts from hmao_start (21-bit: covers 2M cy)
  logic                 decision_latched_r; // Normal decision captured, waiting for timer
  logic                 fault_fire_r;       // Fault decision: fires complete immediately

  // ===========================================================================
  // INTERNAL AXI INTERFACES (for arbiter)
  // ===========================================================================
  axi4_ro_if #(
    .ADDR_W  (AXI_ADDR_W),
    .DATA_W  (AXI_DATA_W),
    .ID_W    (AXI_ID_W)
  ) axi_preproc (
    .aclk    (clk),
    .aresetn (rst_n)
  );

  axi4_ro_if #(
    .ADDR_W  (AXI_ADDR_W),
    .DATA_W  (AXI_DATA_W),
    .ID_W    (AXI_ID_W)
  ) axi_sat1 (
    .aclk    (clk),
    .aresetn (rst_n)
  );

  axi4_ro_if #(
    .ADDR_W  (AXI_ADDR_W),
    .DATA_W  (AXI_DATA_W),
    .ID_W    (AXI_ID_W)
  ) axi_admm (
    .aclk    (clk),
    .aresetn (rst_n)
  );

  // Dedicated AXI interface for Stage 2 collision checker.
  // Stage 1 (axi_sat1) and Stage 2 (axi_sat2) NEVER run concurrently
  // (different FSM branches), but SV structural rules forbid sharing modport.
  axi4_ro_if #(
    .ADDR_W  (AXI_ADDR_W),
    .DATA_W  (AXI_DATA_W),
    .ID_W    (AXI_ID_W)
  ) axi_sat2 (
    .aclk    (clk),
    .aresetn (rst_n)
  );

  // ===========================================================================
  // SUB-MODULE INSTANTIATION
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // 0. AXI4 ARBITER (multiplexes 4 master ports to single slave)
  // Spec Ref: Section 2.2 - Shared AXI bus arbitration
  // Priority: PREPROC > SAT1 > SAT2 > ADMM
  // ---------------------------------------------------------------------------
  hmao_axi_arbiter u_arbiter (
    .clk       (clk),
    .rst_n     (rst_n),
    .m0_preproc(axi_preproc.slave),
    .m1_sat1   (axi_sat1.slave),
    .m2_sat2   (axi_sat2.slave),
    .m3_admm   (axi_admm.slave),
    .s_mem     (axi_ro)
  );

  // ---------------------------------------------------------------------------
  // 1. PRE-PROCESSING UNIT
  // Spec Ref: Section 7.1 - 0.5ms = 200,000 cycles
  //           CRC32, Kinematic check, Format validation, BBox computation
  // ---------------------------------------------------------------------------
  hmao_preproc u_preproc (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (start_preproc),

    // AXI4 for reading trajectory buffer (via arbiter)
    .axi_ro         (axi_preproc.master),

    // Outputs to pipeline
    .valid_out      (pipe.preproc_valid),
    .error_out      (pipe.preproc_error),
    .waypoints_out  (pipe.waypoints),
    .bbox_xmin_out  (pipe.bbox_xmin),
    .bbox_xmax_out  (pipe.bbox_xmax),
    .bbox_ymin_out  (pipe.bbox_ymin),
    .bbox_ymax_out  (pipe.bbox_ymax),

    // Fault outputs (via intermediate signals → ORed into fault_reg)
    .crc_fail       (preproc_crc_fail),
    .kinematic_fail (preproc_kinematic_fail),
    .fmt_fail_out   (preproc_fmt_fail)
  );

  // ---------------------------------------------------------------------------
  // 2. ADAPTIVE MARGIN CONTROLLER
  // Spec Ref: Section 8 - Always combinational (no latency in pipeline)
  // ---------------------------------------------------------------------------
  hmao_adaptive_margin u_margin (
    .clk              (clk),
    .rst_n            (rst_n),

    // Uncertainty vector inputs
    .gps_quality      (gps_quality),
    .camera_quality   (camera_quality),
    .road_friction    (road_friction),
    .actuator_health  (actuator_health),
    .weather_severity (weather_severity),

    // Margin outputs (Q8.8)
    .lateral_margin   (pipe.lateral_margin),
    .long_margin      (pipe.long_margin),
    .time_margin      (pipe.time_margin)
  );

  // Connect margin to output registers
  assign lateral_margin_out = pipe.lateral_margin;
  assign long_margin_out    = pipe.long_margin;
  assign time_margin_out    = pipe.time_margin;

  // ---------------------------------------------------------------------------
  // 3. STAGE 1 ZONOTOPE GENERATOR (Coarse - 16 generators, 50 steps)
  // Spec Ref: Section 7.2 - 1.5ms = 600,000 cycles
  // ---------------------------------------------------------------------------
  hmao_zonotope_gen #(
    .NUM_GENERATORS  (STAGE1_GENERATORS),
    .NUM_TIMESTEPS   (STAGE1_TIMESTEPS),
    .DELTA_T_US      (10)               // 10ms timestep
  ) u_s1_zonotope (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (start_s1),

    // Validated trajectory
    .waypoints_in    (pipe.waypoints),

    // Adaptive margins
    .lateral_margin  (pipe.lateral_margin),
    .long_margin     (pipe.long_margin),
    .time_margin     (pipe.time_margin),

    // Zonotope outputs
    .zonotopes_out   (pipe.s1_zonotopes),
    .valid_out       (pipe.s1_zono_valid),

    // Fault (Stage 1 zonotope)
    .overflow_err    (s1_zono_overflow),
    .zonotope_err    (s1_zono_err)
  );

  // ---------------------------------------------------------------------------
  // 4. ADMM SOLVER (Parallel with Stage 1, 15-stage unrolled pipeline)
  // Spec Ref: Section 7.3 - Starts simultaneously with Stage 1
  // ---------------------------------------------------------------------------
  hmao_admm_solver u_admm (
    .clk                  (clk),
    .rst_n                (rst_n),
    .start                (start_admm),    // Same trigger as Stage 1

    // Trajectory & world model access
    .waypoints_in         (pipe.waypoints),
    .axi_ro               (axi_admm.master),        // Via arbiter

    // Safe distance threshold
    .d_safe_q8_8          (pipe.long_margin),

    // Outputs
    .collision_possible   (pipe.admm_collision_possible),
    .done                 (pipe.admm_done),
    .diverged             (pipe.admm_diverged),

    // Fault (via intermediate signal → ORed into fault_reg)
    .admm_diverge_fault   (admm_diverge_fault)
  );

  // ---------------------------------------------------------------------------
  // v2 (04/10/2026): HOP XE EGO cho bo kiem tra va cham.
  // Nua kich thuoc xe (Renault Zoe nuScenes 4,084 x 1,730 m) + bien an toan lay tu
  // khoi bien thich nghi: b = margin * K / 256 (K chon tren tap TRAIN, VH AK.15).
  // Danh sach nghi ngo cua tang 1 duoc chot khi tang 1 xong de tang 2 doc.
  // ---------------------------------------------------------------------------
  localparam logic [15:0] EGO_HALF_LEN_Q88 = 16'd523;   // 2,042 m
  localparam logic [15:0] EGO_HALF_WID_Q88 = 16'd221;   // 0,865 m
  logic [15:0] ego_half_len, ego_half_wid;
  logic [23:0] blong_prod, blat_prod;
  assign blong_prod   = pipe.long_margin    * 8'(TSM_K_LONG);
  assign blat_prod    = pipe.lateral_margin * 8'(TSM_K_LAT);
  assign ego_half_len = EGO_HALF_LEN_Q88 + blong_prod[23:8];
  assign ego_half_wid = EGO_HALF_WID_Q88 + blat_prod[23:8];

  logic [4:0]                       s1_suspicious_cnt, s1_cnt_q;
  logic [MAX_SUSPICIOUS_OBS*16-1:0] s1_list_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_cnt_q  <= '0;
      s1_list_q <= '0;
    end else if (pipe.s1_no_collision || pipe.s1_potential_collide) begin
      s1_cnt_q  <= s1_suspicious_cnt;
      s1_list_q <= pipe.s1_suspicious_ids;
    end
  end

  // ---------------------------------------------------------------------------
  // 5. STAGE 1 COLLISION CHECKER (SAT)
  // Spec Ref: Section 7.4 - 2.0ms = 800,000 cycles
  // ---------------------------------------------------------------------------
  hmao_collision_sat #(
    .NUM_ZONOTOPES   (STAGE1_TIMESTEPS),
    .NUM_GENERATORS  (STAGE1_GENERATORS),
    .MAX_OBSTACLES   (100),              // Coarse scan: 100 obstacles
    .LIST_MODE       (0),
    .STEP_DT_Q16     (6554),             // 0,1 s / buoc
    .MAX_CHECK_STEPS (TSM_S1_CHECK_STEPS)
  ) u_s1_checker (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (pipe.s1_zono_valid),

    // Zonotopes from Stage 1
    .zonotopes_in    (pipe.s1_zonotopes),

    // World model access (via arbiter)
    .axi_ro          (axi_sat1.master),

    // Pre-filter bounding box
    .bbox_xmin       (pipe.bbox_xmin),
    .bbox_xmax       (pipe.bbox_xmax),
    .bbox_ymin       (pipe.bbox_ymin),
    .bbox_ymax       (pipe.bbox_ymax),

    // v2: hop xe ego + (tang 1) khong dung danh sach
    .ego_half_len    (ego_half_len),
    .ego_half_wid    (ego_half_wid),
    .list_in         ('0),
    .list_cnt        (5'd0),

    // Outputs
    .no_collision    (pipe.s1_no_collision),
    .potential_coll  (pipe.s1_potential_collide),
    .suspicious_ids  (pipe.s1_suspicious_ids),
    .suspicious_cnt  (s1_suspicious_cnt),
    .violation_info  (violation_reg),

    // Fault (Stage 1 SAT)
    .overflow_err    (s1_sat_overflow)
  );

  // ---------------------------------------------------------------------------
  // 6. STAGE 2 ZONOTOPE GENERATOR (Fine - 32 generators, 100 steps)
  // Spec Ref: Section 7.2 - Only if Stage 1 returns POTENTIAL_COLLIDE
  //           2.0ms = 800,000 cycles
  // ---------------------------------------------------------------------------
  hmao_zonotope_gen #(
    .NUM_GENERATORS  (STAGE2_GENERATORS),
    .NUM_TIMESTEPS   (STAGE2_TIMESTEPS),
    .DELTA_T_US      (5)                // 5ms timestep
  ) u_s2_zonotope (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (start_s2),

    .waypoints_in    (pipe.waypoints),
    .lateral_margin  (pipe.lateral_margin),
    .long_margin     (pipe.long_margin),
    .time_margin     (pipe.time_margin),

    .zonotopes_out   (pipe.s2_zonotopes),
    .valid_out       (pipe.s2_zono_valid),
    .overflow_err    (s2_zono_overflow),
    .zonotope_err    (s2_zono_err)
  );

  // ---------------------------------------------------------------------------
  // 7. STAGE 2 COLLISION CHECKER (Fine SAT, suspicious list only)
  // Spec Ref: Section 7.4 - 1.0ms = 400,000 cycles
  // ---------------------------------------------------------------------------
  hmao_collision_sat #(
    .NUM_ZONOTOPES   (STAGE2_TIMESTEPS),
    .NUM_GENERATORS  (STAGE2_GENERATORS),
    .MAX_OBSTACLES   (MAX_SUSPICIOUS_OBS), // Fine check: only suspicious list
    .LIST_MODE       (1),                  // v2: doc DUNG danh sach nghi ngo cua tang 1
    .STEP_DT_Q16     (3277),               // 0,05 s / buoc
    .MAX_CHECK_STEPS (2 * TSM_S1_CHECK_STEPS)
  ) u_s2_checker (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (pipe.s2_zono_valid),

    .zonotopes_in    (pipe.s2_zonotopes),
    .axi_ro          (axi_sat2.master),  // Dedicated Stage 2 port (SAT1 not active in this FSM path)

    .bbox_xmin       (pipe.bbox_xmin),
    .bbox_xmax       (pipe.bbox_xmax),
    .bbox_ymin       (pipe.bbox_ymin),
    .bbox_ymax       (pipe.bbox_ymax),

    .ego_half_len    (ego_half_len),
    .ego_half_wid    (ego_half_wid),
    .list_in         (s1_list_q),
    .list_cnt        (s1_cnt_q),

    .no_collision    (pipe.s2_no_collision),
    .potential_coll  (pipe.s2_collision_confirmed), // Stage 2: potential → confirmed
    .suspicious_ids  (),
    .suspicious_cnt  (),
    .violation_info  (pipe.violation_info),
    .overflow_err    ()
  );

  // ---------------------------------------------------------------------------
  // 8. CONTROL FSM
  // Spec Ref: Section 9 - Hamming-3 encoded states
  // ---------------------------------------------------------------------------
  hmao_fsm u_fsm (
    .clk                (clk),
    .rst_n              (rst_n),

    // Trigger
    .hmao_start         (hmao_start),

    // Pipeline status inputs
    .preproc_valid      (pipe.preproc_valid),
    .preproc_error      (pipe.preproc_error),
    .s1_zono_valid      (pipe.s1_zono_valid),
    .s1_no_collision    (s1_no_collision_latch),   // Sticky: SAT fires ~600k cycles before FSM checks
    .s1_potential       (s1_potential_latch),       // Sticky: same reason
    .admm_done          (admm_done_latch),          // Sticky: ADMM fires 15 cycles after start
    .admm_diverged      (admm_diverged_latch),      // Sticky
    .s2_zono_valid      (pipe.s2_zono_valid),
    .s2_no_collision    (pipe.s2_no_collision),
    .s2_collision       (pipe.s2_collision_confirmed),

    // Fault inputs
    .crc_error          (fault_reg.trajectory_crc_fail),
    .numerical_error    (fault_reg.numerical_overflow | fault_reg.zonotope_error),
    .wdt_s1_timeout     (wdt_s1_timeout),
    .wdt_s2_timeout     (wdt_s2_timeout),

    // FSM state output
    .fsm_state_out      (fsm_state),

    // Control outputs to sub-modules
    .start_preproc      (start_preproc),
    .start_s1           (start_s1),
    .start_admm         (start_admm),
    .start_s2           (start_s2),
    .output_grant       (output_grant),
    .output_veto        (output_veto)
  );

  // ---------------------------------------------------------------------------
  // 9. WATCHDOG TIMER (Independent ring oscillator)
  // Spec Ref: Section 9.3, 13.1 (D1)
  // ---------------------------------------------------------------------------

  // ── WDT kick pulse stretcher ───────────────────────────────────────────────
  // Board clocks: TSM 187.5 MHz and watchdog 250 MHz. Keep kicks wide enough
  // for the two-flop CDC, also covering the older faster TSM simulation clocks.
  // Five TSM cycles are 26.67 ns on the board, versus a 4 ns watchdog period.
  logic [3:0] hmao_start_sr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) hmao_start_sr <= '0;
    else        hmao_start_sr <= {hmao_start_sr[2:0], hmao_start};
  end
  wire hmao_start_wide = hmao_start | |hmao_start_sr; // 5 cycles wide (1 + 4-bit SR)

  logic wdt_run_active;
  logic [15:0] wdt_clear_sr;
  logic wdt_s1_raw, wdt_s2_raw, wdt_total_raw, wdt_fault_raw;
  wire wdt_clear_wide = hmao_start | irq_clear | (|wdt_clear_sr);
  wire wdt_accept_fault = wdt_run_active && !wdt_clear_wide;
  wire wdt_monitor_s1 = wdt_run_active &&
      (fsm_state == FSM_STAGE1_COMP || fsm_state == FSM_STAGE1_CHECK) &&
      !output_grant && !output_veto;
  wire wdt_monitor_s2 = wdt_run_active &&
      (fsm_state == FSM_STAGE2_COMP || fsm_state == FSM_STAGE2_CHECK) &&
      !output_grant && !output_veto;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wdt_run_active <= 1'b0;
      wdt_clear_sr <= '0;
    end else begin
      if (hmao_start) wdt_run_active <= 1'b1;
      else if (irq_clear || hmao_complete) wdt_run_active <= 1'b0;
      // Stretch clear through both CDC chains and mask the returning stale
      // timeout while it clears. At 187.5/250 MHz, 16 TSM cycles is > 85 ns.
      if (hmao_start || irq_clear) wdt_clear_sr <= '1;
      else wdt_clear_sr <= {wdt_clear_sr[14:0], 1'b0};
    end
  end
  assign wdt_s1_timeout = (wdt_s1_raw | wdt_total_raw) && wdt_accept_fault;
  assign wdt_s2_timeout = (wdt_s2_raw | wdt_total_raw) && wdt_accept_fault;
  assign wdt_fault = wdt_fault_raw && wdt_accept_fault;

  hmao_watchdog u_wdt (
    .wdt_clk        (wdt_clk),      // Independent ring oscillator
    .sys_clk        (clk),          // For synchronizing timeout to sys domain
    .rst_n          (rst_n),

    // Kick signals: reset on hmao_start (stretched for CDC) AND stage start.
    // WHY stage kick: S1/S2 counters reset on their respective stage starts
    //     so each stage gets its full budget from when it actually begins.
    // The start kick arms the total timer before preproc can wait on AXI.
    // Stage enables independently prevent unused stages and idle time counting.
    .kick_s1        (start_s1 | hmao_start_wide),
    .kick_s2        (start_s2 | hmao_start_wide),
    .kick_total     (hmao_start_wide),
    .monitor_s1     (wdt_monitor_s1),
    .monitor_s2     (wdt_monitor_s2),
    .monitor_total  (wdt_run_active),
    .clear_timeout  (wdt_clear_wide),

    // Timeout outputs (synchronized to sys_clk)
    .s1_timeout     (wdt_s1_raw),
    .s2_timeout     (wdt_s2_raw),
    .total_timeout  (wdt_total_raw),

    // Fault (via intermediate signal → ORed into fault_reg)
    .wdt_fault      (wdt_fault_raw)
  );

  // Gate stale preproc_crc_fail: cleared on hmao_start, 1-cycle delayed otherwise.
  // WHY: At the cycle PP_ERROR is entered (error_out=1), crc_error must be 0 so
  //      FSM_STAGE1_COMP checks preproc_error first → FSM_OUTPUT_VETO, not FSM_ERROR.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || hmao_start)
      preproc_crc_fail_gated <= 1'b0;
    else
      preproc_crc_fail_gated <= preproc_crc_fail;
  end

  // Gate preproc_fmt_fail identically: at the cycle PP_ERROR is entered (error_out=1),
  // fmt_fail and error_out are set in the same posedge. Without gating,
  // numerical_error=1 and preproc_error=1 are simultaneous; FSM_STAGE1_COMP checks
  // numerical_error FIRST → FSM_ERROR (stuck). The 1-cycle gate ensures numerical_error=0
  // at error_out=1 cycle, so FSM takes preproc_error path → FSM_OUTPUT_VETO (correct).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || hmao_start)
      preproc_fmt_fail_gated <= 1'b0;
    else
      preproc_fmt_fail_gated <= preproc_fmt_fail;
  end

  // ---------------------------------------------------------------------------
  // Fault OR reduction (all sub-module fault sources → single fault_reg)
  // ---------------------------------------------------------------------------
  always_comb begin
    fault_reg.trajectory_crc_fail = preproc_crc_fail_gated;   // gated: stale cleared on hmao_start
    fault_reg.kinematic_invalid   = preproc_kinematic_fail;
    fault_reg.admm_divergence     = admm_diverge_fault;
    fault_reg.hmao_hang           = wdt_fault;
    fault_reg.numerical_overflow  = s1_zono_overflow | s1_sat_overflow | s2_zono_overflow | preproc_fmt_fail_gated;
    fault_reg.zonotope_error      = s1_zono_err | s2_zono_err;
    fault_reg.smpu_violation      = 1'b0;  // SMPU faults handled via soc_top safety path
  end

  // ── Sticky fault register ─────────────────────────────────────────────────
  // WHY: Transient faults (kinematic_invalid, trajectory_crc_fail) fire for
  //      only 1-2 cycles during preproc, then clear when PP_IDLE is re-entered.
  //      Without sticky capture, the CPU reading fault_out at 1.5M cycles (Cach A
  //      timer expiry) sees 0x00 — the fault cause of a VETO is invisible.
  //      ASIL-D requirement: FDC ≥ 99% means the CPU must always know WHY a
  //      VETO was issued (ISO 26262 Part 5, Table 1, diagnostic coverage).
  //      Clears only on irq_clear (CPU acknowledged the fault) or full reset.
  hmao_fault_t fault_sticky;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      fault_sticky <= '0;
    else if (irq_clear | hmao_start)
      fault_sticky <= '0;  // irq_clear: CPU ack; hmao_start: flush before new run (same cycle as gated clear)
    else
      fault_sticky <= fault_sticky | fault_reg;  // accumulate all faults since last irq_clear
  end

  // ---------------------------------------------------------------------------
  // 10. OUTPUT REGISTER STAGE
  // Spec Ref: Section 6.1 - 0.2ms = 80,000 cycles
  // ---------------------------------------------------------------------------

  // Decision register - safe default VETO
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decision_reg     <= DECISION_VETO;
      hmao_violation_out <= '0;
    end else begin
      if (irq_clear || hmao_start) begin
        decision_reg <= DECISION_VETO;
        hmao_violation_out <= '0;
      end else if (output_grant) begin
        decision_reg       <= DECISION_GRANT;
        hmao_violation_out <= '0;
      end else if (output_veto) begin
        decision_reg       <= DECISION_VETO;
        hmao_violation_out <= hmao_violation_t'(violation_reg);
      end
      // On FSM_ERROR: keep VETO (already 0 from default)
      if (fsm_state == FSM_ERROR || wdt_fault) begin
        decision_reg <= DECISION_VETO;
      end
    end
  end

  assign hmao_decision_out = decision_reg;

  // ── Global timer (resets on hmao_start, counts to HMAO_FIXED_LATENCY_CY) ─────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      global_timer       <= '0;
      decision_latched_r <= 1'b0;
      fault_fire_r       <= 1'b0;
    end else begin
      // Counter: reset on start, saturate at FIXED_LATENCY_CY
      if (hmao_start)
        global_timer <= '0;
      else if (global_timer < 21'(HMAO_FIXED_LATENCY_CY))
        global_timer <= global_timer + 1'b1;

      // Capture normal decision (grant OR non-fault veto) → arm timer gate
      if (hmao_start || irq_clear)
        decision_latched_r <= 1'b0;
      else if (output_grant || (output_veto && fsm_state != FSM_ERROR))
        decision_latched_r <= 1'b1;

      // Capture fault decision (FSM_ERROR: WDT/CRC) → fire immediately
      if (hmao_start || irq_clear)
        fault_fire_r <= 1'b0;
      else if ((output_veto && fsm_state == FSM_ERROR) || wdt_fault)
        fault_fire_r <= 1'b1;
    end
  end

  // Complete IRQ:
  //   Normal path  → fires when timer reaches HMAO_FIXED_LATENCY_CY (constant timing)
  //   Fault path   → fires immediately (FSM_ERROR, WDT/CRC: MRM must not be delayed)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      complete_latch <= 1'b0;
    end else begin
      if (hmao_start || irq_clear) begin
        complete_latch <= 1'b0;
      end else if (!complete_latch) begin
        if (fault_fire_r) begin
          complete_latch <= 1'b1;   // Fault: immediate
        end else if (decision_latched_r &&
                     global_timer == 21'(HMAO_FIXED_LATENCY_CY)) begin
          complete_latch <= 1'b1;   // Normal: exactly at fixed latency
        end
      end
    end
  end
  assign hmao_complete = complete_latch;

  // Latency counter
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_counter   <= '0;
      hmao_latency_out <= '0;
    end else begin
      if (hmao_start) begin
        cycle_counter <= '0;
      end else if (fsm_state == FSM_STAGE1_COMP || fsm_state == FSM_STAGE1_CHECK ||
                   fsm_state == FSM_STAGE2_COMP || fsm_state == FSM_STAGE2_CHECK) begin
        cycle_counter <= cycle_counter + 1'b1;
      end

      if (output_grant || output_veto) begin
        // Report fixed E2E latency (not compute-only) so PS sees constant value
        hmao_latency_out <= 32'(HMAO_FIXED_LATENCY_CY);
      end
    end
  end

  // Status register
  // Spec Ref: Section 5.2 - HMAO_STATUS[2:0] = decoded FSM state (3-bit index)
  // fsm_state is now 7-bit Hamming(7,4) encoded; decode_fsm_state() maps it
  // back to the 3-bit index that HMAO_STATUS[2:0] exposes to RISCV firmware.
  always_comb begin
    hmao_status_out             = '0;
    hmao_status_out[2:0]        = decode_fsm_state(fsm_state);  // Hamming decode
    hmao_status_out[3]          = fault_reg.trajectory_crc_fail;
    hmao_status_out[4]          = fault_reg.hmao_hang;
    hmao_status_out[5]          = fault_reg.numerical_overflow | fault_reg.zonotope_error;
    hmao_status_out[6]          = (fsm_state != FSM_IDLE) &&
                                   (fsm_state != FSM_OUTPUT_GRANT) &&
                                   (fsm_state != FSM_OUTPUT_VETO) &&
                                   (fsm_state != FSM_ERROR);
  end

  // Debug outputs (test/monitoring only - non-safety)
  assign debug_start_preproc = start_preproc;
  assign debug_fsm_state_encoded = fsm_state;
  assign debug_hmao_start_received = hmao_start;
  assign debug_preproc_valid = pipe.preproc_valid;
  assign debug_preproc_error = pipe.preproc_error;

  // Fault aggregation & output — reports sticky history so transient faults
  // (kinematic_invalid, trajectory_crc_fail) are visible to CPU after Cach A delay.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fault_out       <= '0;
      fault_valid_out <= '0;
    end else if (hmao_start || irq_clear) begin
      fault_out <= '0;
      fault_valid_out <= 1'b0;
    end else begin
      fault_out       <= fault_sticky | fault_reg;  // sticky history OR current
      fault_valid_out <= |(fault_sticky | fault_reg);
    end
  end

  // ===========================================================================
  // SYNTHESIZEABLE ASSERTIONS (ASIL-D)
  // Spec Ref: Section 15
  // ===========================================================================
  `ifdef FORMAL

    // P1.1: Zero False Negatives - if collision exists, output MUST be VETO
    // (Proven offline via zonotope over-approximation property P1.3)

    // P2.1: Bounded Latency ≤ 10ms (relaxed to ≤ FIXED_LATENCY_CY for normal path)
    assert property (@(posedge clk) disable iff (!rst_n)
      hmao_start |=> ##[1:MAX_TOTAL_CYCLES] (output_grant || output_veto || wdt_s1_timeout))
      else $error("P2.1 VIOLATION: HMAO exceeded 10ms latency budget");

    // P2.2: Constant-time completion (Cach A — ASIL-D deterministic latency)
    // Normal path: hmao_complete must fire exactly at HMAO_FIXED_LATENCY_CY cycles
    // after hmao_start (no earlier, no later), unless a fault forces early completion.
    assert property (@(posedge clk) disable iff (!rst_n)
      $rose(hmao_start) |->
        (!hmao_complete throughout ##[1:HMAO_FIXED_LATENCY_CY-1] 1'b1) or
        fault_fire_r)  // fault path allowed to fire before fixed latency
      else $error("P2.2 VIOLATION: hmao_complete fired before HMAO_FIXED_LATENCY_CY (no fault)");

    // P2.3: Determinism - same input → same output (checked via coverage)

    // D4: Margin bounds never violated (in u_margin)

    // Safe default at reset
    assert property (@(posedge clk) !rst_n |-> (decision_reg == 1'b0))
      else $error("Safe default: HMAO_DECISION must be VETO at reset");

    // FSM in ERROR → always VETO
    assert property (@(posedge clk) disable iff (!rst_n)
      (fsm_state == FSM_ERROR) |-> (decision_reg == 1'b0))
      else $error("FSM_ERROR must always result in VETO decision");

  `endif

endmodule : hmao_engine_top
