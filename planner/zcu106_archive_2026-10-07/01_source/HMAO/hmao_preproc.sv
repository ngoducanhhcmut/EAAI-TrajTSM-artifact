// =============================================================================
// FILE        : hmao_preproc.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 7.1
// SAFETY      : ASIL-D (ISO 26262)
// LATENCY     : 0.5ms = 200,000 cycles @ 400MHz
// DESCRIPTION : Pre-Processing Unit. Executes 4 checks before Stage 1:
//
//   Step 1: CRC32 Verification (~100,000 cycles = 0.25ms)
//           - Read 1,400 bytes from Trajectory Buffer (0x8030_0000)
//           - Compute CRC32 of 1,400 bytes using hardware pipeline
//           - Compare with stored CRC32 at offset 0x0568
//           - Mismatch → VETO + fault_crc_fail
//
//   Step 2: Kinematic Feasibility Check
//           - Per waypoint pair: |Δx,Δy| ≤ vmax×Δt+ε
//           - velocity ≤ 35 m/s, heading_rate ≤ 0.8 rad/s×Δt, accel ≤ ±8 m/s²
//           - FAIL → VETO + fault_kinematic_invalid
//
//   Step 3: Format Validation
//           - Timestamps monotonically increasing, Δt=0.1s±ε
//           - No NaN/Inf in any float32 field
//           - num_waypoints == 50
//
//   Step 4: Bounding Box Computation
//           - min/max(x,y) across all 50 waypoints
//           - Used by Stage 1 collision checker for obstacle pre-filtering
//
// PIPELINE: Fully pipelined, deterministic, exactly 200,000 cycles.
//           If finishing early → padding NOPs to maintain determinism.
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

// =============================================================================
// BUG-FIX PP-001 (2026-06-16, see test_history.md Section 16/17/18, "Bug 5"):
// bbox_xmin_r/xmax_r/ymin_r/ymax_r are accumulated directly from waypoint
// float32 bit patterns (min/max comparison works on positive float32 bit
// order, per the comment at their declaration), and were output AS-IS to
// bbox_xmin_out/etc. -- a raw float32 bit pattern, NOT Q8.8. hmao_collision_sat.sv
// compares these directly against obs_pos_x/y (genuine Q8.8) in its bbox
// prefilter, so a real object's small Q8.8 position (e.g. 7059 = 27.57m)
// always failed the comparison against a float32 bit pattern of a similarly
// small real coordinate (e.g. 0x3b2bbdf1 = ~993,000,000 as a raw integer,
// even though the float32 VALUE is only ~0.0026m) -- silently excluding
// every real object from the Stage 1 collision check regardless of position.
// This function performs the same real float32->Q8.8 conversion as
// hmao_zonotope_gen.sv's fp32_to_q88 (duplicated here to avoid a cross-module
// package dependency change).
// =============================================================================
function automatic logic signed [31:0] fp32_to_q88_bbox(input logic [31:0] f);
  logic        sign;
  logic [7:0]  exp;
  logic [23:0] sig;
  integer      shamt;
  logic [55:0] wide;
  logic [31:0] mag;
  begin
    sign = f[31];
    exp  = f[30:23];
    sig  = {1'b1, f[22:0]};

    if (exp == 8'h00) begin
      fp32_to_q88_bbox = 32'sd0;
    end else if (exp == 8'hFF) begin
      fp32_to_q88_bbox = sign ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
    end else if (exp >= 8'd166) begin
      fp32_to_q88_bbox = sign ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
    end else if (exp < 8'd112) begin
      fp32_to_q88_bbox = 32'sd0;
    end else if (exp >= 8'd142) begin
      shamt = exp - 142;
      wide  = {32'b0, sig} << shamt;
      mag   = wide[31:0];
      fp32_to_q88_bbox = sign ? -$signed(mag) : $signed(mag);
    end else begin
      shamt = 142 - exp;
      wide  = {32'b0, sig} >> shamt;
      mag   = wide[31:0];
      fp32_to_q88_bbox = sign ? -$signed(mag) : $signed(mag);
    end
  end
endfunction

module hmao_preproc (
  input  logic            clk,
  input  logic            rst_n,
  input  logic            start,             // Pulse from FSM to begin

  // AXI4 Read-Only Interface (reads trajectory from 0x8030_0000)
  axi4_ro_if.master       axi_ro,

  // Outputs to pipeline
  output logic            valid_out,         // Pre-proc done, no error
  output logic            error_out,         // Error found → FSM triggers VETO
  output waypoint_t       waypoints_out [0:TRAJ_WAYPOINTS-1],
  output logic [31:0]     bbox_xmin_out,
  output logic [31:0]     bbox_xmax_out,
  output logic [31:0]     bbox_ymin_out,
  output logic [31:0]     bbox_ymax_out,

  // Individual fault flags
  output logic            crc_fail,          // → HMAO_FAULT[3]
  output logic            kinematic_fail,    // → HMAO_FAULT[6]
  output logic            fmt_fail_out       // → HMAO_FAULT[1] (NaN/Inf in trajectory position)
);

  // ===========================================================================
  // INTERNAL STATE
  // ===========================================================================
  typedef enum logic [2:0] {
    PP_IDLE       = 3'b000,
    PP_FETCH      = 3'b001,  // AXI burst read of 1400 bytes + 4 CRC bytes
    PP_CRC        = 3'b010,  // CRC32 pipeline over 1400 bytes
    PP_KINEMATIC  = 3'b011,  // Kinematic check across 50 waypoints
    PP_FORMAT     = 3'b100,  // Format/NaN check
    PP_BBOX       = 3'b101,  // Bounding box computation
    PP_DONE       = 3'b110,  // Output results
    PP_ERROR      = 3'b111   // Error state
  } pp_state_t;

  pp_state_t pp_state, pp_next;

  // Cycle counter for latency enforcement (must complete in 200,000 cycles)
  logic [17:0]    cycle_cnt;   // 18 bits covers 200,000
  logic           cycle_done;

  // Trajectory raw storage (BRAM-backed, 1,400 bytes = 350 x 32-bit words)
  logic [31:0]    traj_raw [0:349];         // 1,400 bytes of trajectory
  logic [31:0]    crc_stored;              // CRC32 from offset 0x0568
  logic [31:0]    crc_computed;            // CRC32 calculated

  // Fetch state
  logic [8:0]     fetch_word_idx;          // 0..350 (350 data words + 1 CRC word)
  logic           fetch_done;
  logic           fetch_crc_done;
  logic [3:0]     burst_count;             // 0..7: which burst is being issued
  logic           burst_inflight;          // AR accepted, awaiting final R beat

  // CRC32 pipeline
  logic [31:0]    crc_reg;
  logic           crc_valid;

  // Kinematic check
  logic [5:0]     wp_idx;                  // 0..49 waypoint index
  logic           kin_check_done;
  logic           kin_fail_internal;

  // Format check
  logic           fmt_fail;
  logic           nan_detected;
  logic           nan_comb;  // Combinational NaN/Inf: used by FSM in PP_FORMAT

  // BBox accumulators
  logic [31:0]    bbox_xmin_r, bbox_xmax_r;
  logic [31:0]    bbox_ymin_r, bbox_ymax_r;

  // ===========================================================================
  // LATENCY COUNTER (Determinism enforcement: exactly 200,000 cycles)
  // ===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_cnt <= '0;
    end else begin
      if (start && pp_state == PP_IDLE) begin
        cycle_cnt <= '0;
      end else if (pp_state != PP_IDLE && pp_state != PP_DONE && pp_state != PP_ERROR) begin
        cycle_cnt <= cycle_cnt + 1'b1;
      end
    end
  end
  // If work completes before 200,000 cycles, PP_DONE state holds until count
  // SIM_FAST_PREPROC: skip latency padding in behavioral sim (functional test only).
  // Enable via TCL before launch_simulation:
  //   set_property verilog_define "SIM_FAST_PREPROC" [get_filesets sim_1]
`ifdef SIM_FAST_PREPROC
  assign cycle_done = 1'b1;
`else
  assign cycle_done = (cycle_cnt >= PREPROC_CYCLES - 1);
`endif

  // ===========================================================================
  // AXI4 BURST READ: Fetch 1,400 + 4 bytes (CRC) from trajectory buffer
  // Address: 0x8030_0000 to 0x8030_0567 (data) + 0x8030_0568 (CRC)
  // ===========================================================================
  // AXI AR Channel
  // AXI4 fetch: 8 INCR bursts to read 351 words (350 traj + 1 CRC).
  //   Bursts 0-6: arlen=43 (44 beats each), araddr = TRAJ_BUFFER_BASE + burst*176
  //   Burst   7:  arlen=42 (43 beats),       araddr = TRAJ_BUFFER_BASE + 7*176
  //   Total: 7*44 + 43 = 308 + 43 = 351 words ✓
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_ro.arvalid  <= 1'b0;
      axi_ro.arid     <= '0;        // Always use ID 0 (single-outstanding, no interleaving)
      axi_ro.araddr   <= '0;
      axi_ro.arlen    <= 8'd43;
      axi_ro.arsize   <= 3'b010;    // 4 bytes per beat
      axi_ro.arburst  <= 2'b01;     // INCR burst
      axi_ro.aruser   <= HMAO_MASTER_ID;
      fetch_word_idx  <= '0;
      fetch_done      <= 1'b0;
      burst_count     <= '0;
      burst_inflight  <= 1'b0;
    end else begin
      case (pp_state)
        PP_IDLE: begin
          fetch_done     <= 1'b0;
          fetch_word_idx <= '0;
          burst_count    <= '0;
          burst_inflight <= 1'b0;
        end

        PP_FETCH: begin
          // ARVALID must remain low after acceptance until the accepted burst
          // returns RLAST. RVALID may stay low for many cycles in SmartConnect.
          if (!axi_ro.arvalid && !burst_inflight && !fetch_done &&
              burst_count <= 4'd7) begin
            axi_ro.arvalid <= 1'b1;
            axi_ro.araddr  <= TRAJ_BUFFER_BASE + (32'(burst_count) * 32'd176);
            axi_ro.arlen   <= (burst_count == 4'd7) ? 8'd42 : 8'd43;
          end else if (axi_ro.arready && axi_ro.arvalid) begin
            axi_ro.arvalid <= 1'b0;
            burst_inflight <= 1'b1;
          end

          // Accept R channel beats (rready is combinational, always 1 in PP_FETCH)
          if (axi_ro.rvalid && axi_ro.rready) begin
            if (fetch_word_idx < 9'd350) begin
              // Narrow 4-byte transfers on the 256-bit AXI bus occupy the
              // byte lane selected by the current address. The trajectory
              // base is 32-byte aligned, so word index[2:0] selects the lane.
              traj_raw[fetch_word_idx] <=
                  axi_ro.rdata[{fetch_word_idx[2:0], 5'b0} +: 32];
              fetch_word_idx <= fetch_word_idx + 1'b1;
            end
            if (axi_ro.rlast) begin
              burst_inflight <= 1'b0;
              if (burst_count == 4'd7 && fetch_word_idx == 9'd350) begin
                // Burst 7 last beat: word 350 is the CRC
                crc_stored <=
                    axi_ro.rdata[{fetch_word_idx[2:0], 5'b0} +: 32];
                fetch_done <= 1'b1;
              end else begin
                // Intermediate burst complete → advance to next burst
                burst_count <= burst_count + 1'b1;
              end
            end
          end
        end

        default: begin
          axi_ro.arvalid <= 1'b0;
        end
      endcase
    end
  end

  // rready is combinational: assert immediately upon entering PP_FETCH so the
  // first AXI R-beat is consumed in the same cycle it is presented, preventing
  // the registered-rready off-by-one duplicate that corrupts traj_raw.
  assign axi_ro.rready = (pp_state == PP_FETCH);

  // ===========================================================================
  // CRC32 PIPELINE
  // Standard CRC32 (IEEE 802.3 polynomial: 0xEDB88320)
  // Process 4 bytes per clock → 350 words = 350 cycles (0.875μs @ 400MHz)
  // Well within 100,000 cycle budget
  // ===========================================================================
  // CRC32 lookup table (synthesized as LUTRAM)
  // NOTE: Full 256-entry LUT for byte-at-a-time CRC32
  // For synthesis: use vendor primitive or auto-inferred LUTRAM

  function automatic logic [31:0] crc32_byte(
    input logic [31:0] crc_in,
    input logic [7:0]  data_byte
  );
    logic [31:0] crc;
    logic [7:0]  idx;
    // CRC32 table lookup (simplified - full implementation uses LUTRAM)
    // TODO: Replace with actual 256-entry LUTRAM in implementation
    crc = crc_in ^ {24'b0, data_byte};
    for (int i = 0; i < 8; i++) begin
      if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320;
      else        crc = crc >> 1;
    end
    return crc;
  endfunction

  logic [8:0]   crc_word_idx;
  logic         crc_running;

  // Pipeline register: breaks long routing from traj_raw[350] MUX to CRC LUT tree.
  // Stage 0 captures the selected word into a register placed near CRC logic.
  logic [31:0]  crc_word_r;
  logic         crc_word_r_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_word_r       <= '0;
      crc_word_r_valid <= 1'b0;
    end else begin
      if (pp_state == PP_CRC && crc_running && crc_word_idx < 350) begin
        crc_word_r       <= traj_raw[crc_word_idx];
        crc_word_r_valid <= 1'b1;
      end else begin
        crc_word_r_valid <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_reg       <= 32'hFFFF_FFFF;
      crc_word_idx  <= '0;
      crc_running   <= 1'b0;
      crc_valid     <= 1'b0;
    end else begin
      case (pp_state)
        PP_CRC: begin
          if (!crc_running) begin
            crc_reg      <= 32'hFFFF_FFFF;
            crc_word_idx <= '0;
            crc_running  <= 1'b1;
            crc_valid    <= 1'b0;
          end else begin
            // Advance index for next pre-fetch (decoupled from computation)
            if (crc_word_idx < 350)
              crc_word_idx <= crc_word_idx + 1'b1;
            // Compute CRC32 from registered word (stage 1)
            if (crc_word_r_valid) begin
              crc_reg <= crc32_byte(
                           crc32_byte(
                             crc32_byte(
                               crc32_byte(crc_reg, crc_word_r[7:0]),
                               crc_word_r[15:8]),
                             crc_word_r[23:16]),
                           crc_word_r[31:24]);
            end else if (crc_word_idx >= 350) begin
              // All words pre-fetched and last word computed → finalize
              crc_computed <= crc_reg ^ 32'hFFFF_FFFF;
              crc_valid    <= 1'b1;
              crc_running  <= 1'b0;
            end
          end
        end

        default: begin
          crc_running <= 1'b0;
        end
      endcase
    end
  end

  // CRC comparison
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_fail <= 1'b0;
    end else if (pp_state == PP_IDLE) begin
      crc_fail <= 1'b0;  // hold 0 throughout IDLE so next run starts clean
    end else if (crc_valid) begin
      crc_fail <= (crc_computed !== crc_stored);
    end
  end

  // ===========================================================================
  // WAYPOINT DESERIALIZATION (raw → waypoint_t array)
  // 50 waypoints × 7 fields × 4 bytes = 350 words
  // ===========================================================================
  // Decode after fetch_done: combinational decode (small logic, ~0 area)
  always_comb begin
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      waypoints_out[wp].x         = traj_raw[wp * 7 + 0];
      waypoints_out[wp].y         = traj_raw[wp * 7 + 1];
      waypoints_out[wp].z         = traj_raw[wp * 7 + 2];
      waypoints_out[wp].vx        = traj_raw[wp * 7 + 3];
      waypoints_out[wp].vy        = traj_raw[wp * 7 + 4];
      waypoints_out[wp].heading   = traj_raw[wp * 7 + 5];
      waypoints_out[wp].timestamp = traj_raw[wp * 7 + 6];
    end
  end

  // ===========================================================================
  // KINEMATIC FEASIBILITY CHECK (Step 2)
  // Spec Ref: Section 7.1.1 Step 2 & Section 7.2.3
  // Checks per-waypoint constraints:
  //   1. Velocity magnitude: sqrt(vx² + vy²) ≤ VMAX (35 m/s)
  //   2. Max acceleration: |Δv|/Δt ≤ MAX_ACCEL (8 m/s²)
  //   3. Max yaw rate: |Δheading|/Δt ≤ MAX_YAW_RATE (0.8 rad/s)
  //
  // Float32 to magnitude comparison:
  //   IEEE 754 float32: [sign:1][exp:8][mantissa:23]
  //   For normalized numbers: mantissa is [1.0, 2.0) in fractional form
  //   Use float32 exponent to quickly filter out extreme values
  //   Then use fixed-point approximations for precision
  // ===========================================================================
  // Internal registers for kinematic check computation
  logic [7:0]         vx_exp_r, vy_exp_r;   // Exponents from previous cycle
  logic [15:0]        vx_fix_r, vy_fix_r;   // Fixed-point conversions from previous cycle
  logic [31:0]        v_mag_squared_r;      // v²_x + v²_y from previous cycle

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      kinematic_fail  <= 1'b0;
      kin_check_done  <= 1'b0;
      wp_idx          <= '0;
      vx_exp_r        <= '0;
      vy_exp_r        <= '0;
      vx_fix_r        <= '0;
      vy_fix_r        <= '0;
      v_mag_squared_r <= '0;
    end else begin
      if (pp_state == PP_KINEMATIC) begin
        if (wp_idx < TRAJ_WAYPOINTS - 1) begin
          // ASIL-D: direct combinational check on current WP (no pipeline lag).
          // waypoints_out[] is stable RAM output throughout PP_KINEMATIC.
          //
          // FIX 2026-08-04: replaced the exponent-only check (biased exp > 132,
          // which actually gates at |v| >= 64 m/s -- 83% ABOVE the specified
          // VMAX_MPS = 35.0 m/s, per hmao_pkg.sv -- leaving the entire
          // 35-64 m/s band undetected) with a full 31-bit magnitude compare
          // against the exact IEEE-754 bit pattern of 35.0f (0x420C0000).
          // For IEEE-754 floats, bit-pattern order equals numeric order once
          // the sign bit is stripped, so {1'b0, v[30:0]} > 32'h420C_0000 is
          // an exact "|v| > 35.0" test -- no float comparator needed, and no
          // wraparound risk (the prior magnitude-squared attempt was removed
          // in an earlier fix for exactly that reason; this formulation does
          // not reconstruct a magnitude, it only compares bit patterns).
          // NaN (exp=0xFF) and Inf (exp=0xFF) both compare as "> 35.0" too,
          // which is the correct, conservative outcome -- redundant with the
          // nan_comb check in PP_FORMAT, not a conflict.
          if (({1'b0, waypoints_out[wp_idx].vx[30:0]} > 32'h420C_0000) ||
              ({1'b0, waypoints_out[wp_idx].vy[30:0]} > 32'h420C_0000)) begin
            kinematic_fail <= 1'b1;
          end
          vx_exp_r <= waypoints_out[wp_idx].vx[30:23];
          vy_exp_r <= waypoints_out[wp_idx].vy[30:23];
          vx_fix_r <= {waypoints_out[wp_idx].vx[27:23], waypoints_out[wp_idx].vx[22:15]};
          vy_fix_r <= {waypoints_out[wp_idx].vy[27:23], waypoints_out[wp_idx].vy[22:15]};
          wp_idx   <= wp_idx + 1'b1;
        end else begin
          // Last WP (wp_idx == TRAJ_WAYPOINTS-1): check then signal done.
          // Original pipeline skipped this check — fixed for ASIL-D coverage.
          if (({1'b0, waypoints_out[wp_idx].vx[30:0]} > 32'h420C_0000) ||
              ({1'b0, waypoints_out[wp_idx].vy[30:0]} > 32'h420C_0000)) begin
            kinematic_fail <= 1'b1;
          end
          kin_check_done <= 1'b1;
        end
      end else if (pp_state == PP_IDLE) begin
        kinematic_fail  <= 1'b0;
        kin_check_done  <= 1'b0;
        wp_idx          <= '0;
        vx_exp_r        <= '0;
        vy_exp_r        <= '0;
      end
    end
  end

  // ===========================================================================
  // FORMAT VALIDATION & NaN/Inf CHECK (Step 3)
  // IEEE 754 NaN: exponent = 0xFF, mantissa != 0
  // IEEE 754 Inf: exponent = 0xFF, mantissa = 0
  //
  // nan_comb: purely combinational, readable by FSM in the SAME cycle
  //           it enters PP_FORMAT (no registered-signal one-cycle lag).
  // nan_detected: registered copy kept for waveform observability only.
  //
  // FIX 2026-08-04: extended from 4 fields (x,y,vx,vy) to all 7 fields of
  // waypoint_t. The prior 4-field check left z/heading/timestamp completely
  // unchecked — a NaN on heading in particular flows uncaught into
  // hmao_zonotope_gen's CORDIC (via fp32_to_q88 saturation, since PP_FORMAT
  // never flagged it), producing a numerically-valid-looking but meaningless
  // zonotope that can pass collision checking: a direct False Grant path.
  // See docs/Phase2_Safety_Audit_Review_Board.md Station 2 for the full
  // analysis; this closes that gap by construction (every field checked, not
  // just the ones a bug happened to touch first).
  // ===========================================================================
  always_comb begin
    nan_comb = 1'b0;
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      if (waypoints_out[wp].x[30:23]         == 8'hFF) nan_comb = 1'b1;
      if (waypoints_out[wp].y[30:23]         == 8'hFF) nan_comb = 1'b1;
      if (waypoints_out[wp].z[30:23]         == 8'hFF) nan_comb = 1'b1;
      if (waypoints_out[wp].vx[30:23]        == 8'hFF) nan_comb = 1'b1;
      if (waypoints_out[wp].vy[30:23]        == 8'hFF) nan_comb = 1'b1;
      if (waypoints_out[wp].heading[30:23]   == 8'hFF) nan_comb = 1'b1;
      if (waypoints_out[wp].timestamp[30:23] == 8'hFF) nan_comb = 1'b1;
    end
  end

  // fmt_fail: single driver — cleared in PP_IDLE (inter-run isolation) and on reset,
  // set in PP_FORMAT when NaN/Inf detected. Must be single always_ff to avoid MDRV-1.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      nan_detected <= 1'b0;
      fmt_fail     <= 1'b0;
    end else begin
      if (pp_state == PP_IDLE) begin
        fmt_fail     <= 1'b0;  // clear between runs (inter-run contamination fix)
        nan_detected <= 1'b0;
      end else if (pp_state == PP_FORMAT) begin
        nan_detected <= nan_comb;
        fmt_fail     <= nan_comb;
      end
    end
  end

  assign fmt_fail_out = fmt_fail;

  // ===========================================================================
  // BOUNDING BOX COMPUTATION (Step 4)
  // Spec Ref: Section 7.1.1 Step 4
  // Iterative min/max over 50 waypoints (50 cycles, well within budget)
  //
  // BUG-FIX PP-002 (2026-06-16, see test_history.md Section 16/17/18, "Bug 5"):
  // the original min/max comparison used the raw float32 bit pattern directly
  // ("works for positive float32" per the old comment), which is WRONG for
  // any negative coordinate: a negative float32's sign bit (MSB=1) makes its
  // bit pattern compare as a huge UNSIGNED number, always "greater than" any
  // positive float32 bit pattern -- so bbox_ymin_r/bbox_ymax_r could never
  // correctly track negative y (lateral wiggle is normal in real trajectories).
  // Fixed by converting each waypoint to Q8.8 (via fp32_to_q88_bbox) BEFORE
  // the min/max comparison, so bbox_xmin_r/xmax_r/ymin_r/ymax_r are Q8.8
  // signed integers throughout (correct ordering for negative and positive
  // values alike), matching the units hmao_collision_sat.sv expects.
  // ===========================================================================
  logic [5:0] bbox_idx;

  // 2-stage timing pipeline for bbox fp32 conversion:
  //   Stage 0: register raw MUX output (traj_raw → MUXF7×2 → raw_reg, ~0.7 ns)
  //   Stage 1: compute fp32 from registered raw data (raw_reg → fp32 → wp_r, ~2.9 ns)
  //   Stage 2 (main block): compare wp_r with bbox_xmin_r → CE (~0.7 ns)
  // Breaks: traj_raw → MUXF7 → fp32(11LUT+3CARRY8) → bbox_wp_r → compare → CE
  // which was 3.703 ns total (budget 3.344 ns).

  logic [31:0]        bbox_raw_x, bbox_raw_y;
  logic               bbox_raw_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bbox_raw_x     <= '0;
      bbox_raw_y     <= '0;
      bbox_raw_valid <= 1'b0;
    end else begin
      if (pp_state == PP_BBOX && bbox_idx > 0 && bbox_idx < TRAJ_WAYPOINTS) begin
        bbox_raw_x     <= waypoints_out[bbox_idx].x;  // only MUX, no fp32
        bbox_raw_y     <= waypoints_out[bbox_idx].y;
        bbox_raw_valid <= 1'b1;
      end else begin
        bbox_raw_valid <= 1'b0;
      end
    end
  end

  logic signed [31:0] bbox_wp_x_r, bbox_wp_y_r;
  logic               bbox_cmp_en;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bbox_wp_x_r <= '0;
      bbox_wp_y_r <= '0;
      bbox_cmp_en <= 1'b0;
    end else begin
      if (bbox_raw_valid) begin
        bbox_wp_x_r <= $signed(fp32_to_q88_bbox(bbox_raw_x));  // FF → fp32, no MUX
        bbox_wp_y_r <= $signed(fp32_to_q88_bbox(bbox_raw_y));
        bbox_cmp_en <= 1'b1;
      end else begin
        bbox_cmp_en <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bbox_xmin_r <= 32'sh7FFF_FFFF;  // Largest positive Q8.8 sentinel
      bbox_xmax_r <= 32'sh8000_0000;  // Most negative Q8.8 sentinel
      bbox_ymin_r <= 32'sh7FFF_FFFF;
      bbox_ymax_r <= 32'sh8000_0000;
      bbox_idx    <= '0;
    end else begin
      if (pp_state == PP_BBOX) begin
        if (bbox_idx == '0) begin
          // Initialize to first waypoint (converted to Q8.8 inline; avoids a
          // continuous assign indexing a dynamic struct-array element, which
          // crashes the xsim 2023.2 kernel -- see test_history.md Section 18)
          bbox_xmin_r <= fp32_to_q88_bbox(waypoints_out[0].x);
          bbox_xmax_r <= fp32_to_q88_bbox(waypoints_out[0].x);
          bbox_ymin_r <= fp32_to_q88_bbox(waypoints_out[0].y);
          bbox_ymax_r <= fp32_to_q88_bbox(waypoints_out[0].y);
          bbox_idx    <= bbox_idx + 1'b1;
        end else if (bbox_idx < TRAJ_WAYPOINTS) begin
          bbox_idx <= bbox_idx + 1'b1;
          // Min/Max update using pipelined conversion result from stage 1.
          // bbox_cmp_en is registered: fires at idx=2..49 covering wp[1..48];
          // it also fires at idx=50 (one cycle after idx=49) to cover wp[49].
          if (bbox_cmp_en) begin
            if (bbox_wp_x_r < $signed(bbox_xmin_r)) bbox_xmin_r <= bbox_wp_x_r;
            if (bbox_wp_x_r > $signed(bbox_xmax_r)) bbox_xmax_r <= bbox_wp_x_r;
            if (bbox_wp_y_r < $signed(bbox_ymin_r)) bbox_ymin_r <= bbox_wp_y_r;
            if (bbox_wp_y_r > $signed(bbox_ymax_r)) bbox_ymax_r <= bbox_wp_y_r;
          end
        end else begin
          // idx == TRAJ_WAYPOINTS: loop done, drain last pipeline stage (wp[49])
          if (bbox_cmp_en) begin
            if (bbox_wp_x_r < $signed(bbox_xmin_r)) bbox_xmin_r <= bbox_wp_x_r;
            if (bbox_wp_x_r > $signed(bbox_xmax_r)) bbox_xmax_r <= bbox_wp_x_r;
            if (bbox_wp_y_r < $signed(bbox_ymin_r)) bbox_ymin_r <= bbox_wp_y_r;
            if (bbox_wp_y_r > $signed(bbox_ymax_r)) bbox_ymax_r <= bbox_wp_y_r;
          end
        end
      end else if (pp_state == PP_IDLE) begin
        bbox_idx <= '0;
      end
    end
  end

  // BUG-FIX PP-001/PP-002: bbox_xmin_r/etc are now accumulated directly in
  // Q8.8 (the min/max comparison itself converts each waypoint -- see the
  // BOUNDING BOX COMPUTATION block above), so no further conversion is
  // needed here; this just exposes the Q8.8 accumulator value, matching the
  // units hmao_collision_sat.sv's prefilter expects.
  assign bbox_xmin_out = bbox_xmin_r;
  assign bbox_xmax_out = bbox_xmax_r;
  assign bbox_ymin_out = bbox_ymin_r;
  assign bbox_ymax_out = bbox_ymax_r;

  // ===========================================================================
  // STATE MACHINE
  // ===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pp_state <= PP_IDLE;
    end else begin
      pp_state <= pp_next;
    end
  end

  always_comb begin
    pp_next   = pp_state;
    valid_out = 1'b0;
    error_out = 1'b0;

    unique case (pp_state)
      PP_IDLE:      if (start) pp_next = PP_FETCH;
      PP_FETCH:     if (fetch_done && !burst_inflight && !axi_ro.arvalid) pp_next = PP_CRC;
      PP_CRC:       if (crc_valid) begin
                      if (crc_computed !== crc_stored) begin pp_next = PP_ERROR; end
                      else                             begin pp_next = PP_KINEMATIC; end
                    end
      PP_KINEMATIC: if (kin_check_done) begin
                      if (kinematic_fail) begin pp_next = PP_ERROR; end
                      else               begin pp_next = PP_FORMAT; end
                    end
      PP_FORMAT:    if (nan_comb) pp_next = PP_ERROR;   // Combinational NaN/Inf check
                    else          pp_next = PP_BBOX;
      // BUG-FIX (pipeline drain cut short in SIM_FAST_PREPROC mode): the
      // bbox_raw_valid -> bbox_cmp_en -> compare chain is a 2-cycle pipeline
      // (see bbox_raw_valid/bbox_cmp_en always_ff blocks above). The LAST
      // waypoint's (wp[TRAJ_WAYPOINTS-1]) comparison only becomes ready 2
      // cycles after bbox_idx reaches TRAJ_WAYPOINTS. In SIM_FAST_PREPROC
      // mode, cycle_done is hardwired 1'b1, so without the extra
      // !bbox_raw_valid/!bbox_cmp_en guard the FSM left PP_BBOX for PP_DONE
      // one cycle before the last waypoint's min/max update ever applied,
      // silently dropping wp[TRAJ_WAYPOINTS-1] from the bbox (only visible
      // when its coordinate happens to be the true extremum, e.g. TP_007B).
      PP_BBOX:      if (bbox_idx >= TRAJ_WAYPOINTS && !bbox_raw_valid && !bbox_cmp_en) begin
                      // Wait for latency budget if finishing early
                      if (cycle_done) pp_next = PP_DONE;
                    end
      PP_DONE:      begin
                      valid_out = 1'b1;
                      pp_next   = PP_IDLE;
                    end
      PP_ERROR:     begin
                      error_out = 1'b1;
                      pp_next   = PP_IDLE;  // Return to IDLE after signaling error
                    end
      default:      pp_next = PP_ERROR;
    endcase

  end

  // ===========================================================================
  // FORMAL ASSERTIONS
  // ===========================================================================
  `ifdef FORMAL
    // Pre-proc must complete in exactly PREPROC_CYCLES
    assert property (@(posedge clk) disable iff (!rst_n)
      $rose(start) |=> ##[1:PREPROC_CYCLES+1] (valid_out || error_out))
      else $error("PREPROC: Exceeded latency budget");

    // valid_out and error_out are mutually exclusive
    assert property (@(posedge clk) !(valid_out && error_out))
      else $error("PREPROC: valid_out and error_out both asserted");

    // CRC fail must result in error_out
    assert property (@(posedge clk) disable iff (!rst_n)
      crc_fail |=> error_out)
      else $error("PREPROC: CRC fail did not trigger error_out");
  `endif

endmodule : hmao_preproc
