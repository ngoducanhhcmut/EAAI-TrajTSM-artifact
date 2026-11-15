// =============================================================================
// FILE        : tb_hmao_edge_cases.sv
// PROJECT     : VLA-HMAO Edge Case / Boundary Condition Test
// DATE        : 2026-06-16
// DESCRIPTION : Tests 7 boundary-condition hex files through HMAO RTL.
//               Verifies correct GRANT/VETO decisions and fault bits.
//
// EC-01  Nominal sample_00 (vx≈8.4 m/s)            → GRANT  faults=0x00
// EC-02  Stationary (vx=vy=0)                        → GRANT  faults=0x00
// EC-03  vx=32.0 m/s (biased_exp=132, AT limit)     → GRANT  faults=0x00
// EC-04  vx=64.0 m/s (biased_exp=133, OVER limit)   → VETO   faults=0x01 (kinematic)
// EC-05  vx=35.0 m/s (VMAX clamp point)             → GRANT  faults=0x00
// EC-06  CRC corrupted (byte[0] ^= 0xFF)             → VETO   faults=0x08 (crc_fail)
// EC-07  CRC = 0x00000000 (zero CRC)                 → VETO   faults=0x08 (crc_fail)
// =============================================================================

`timescale 1ns/1ps
import planning_pkg::*;
import hmao_pkg::*;

module tb_hmao_edge_cases;

  // ===========================================================================
  // CLOCKS
  // ===========================================================================
  localparam real PL_CLK_HALF   = 2.5;    // 200 MHz
  localparam real HMAO_CLK_HALF = 1.25;   // 400 MHz
  localparam real WDT_CLK_HALF  = 1.5;    // ~333 MHz

  logic pl_clk   = 1'b0;
  logic hmao_clk = 1'b0;
  logic wdt_clk  = 1'b0;

  always #(PL_CLK_HALF)   pl_clk   = ~pl_clk;
  always #(HMAO_CLK_HALF) hmao_clk = ~hmao_clk;
  always #(WDT_CLK_HALF)  wdt_clk  = ~wdt_clk;

  // ===========================================================================
  // RESETS
  // ===========================================================================
  logic pl_rst_n   = 1'b0;
  logic hmao_rst_n = 1'b0;

  initial begin
    repeat(20) @(posedge pl_clk);   pl_rst_n   = 1'b1;
    repeat(5)  @(posedge hmao_clk); hmao_rst_n = 1'b1;
  end

  // ===========================================================================
  // SCOREBOARD
  // ===========================================================================
  int pass_cnt = 0;
  int fail_cnt = 0;

  task automatic check(input string name, input logic cond);
    if (cond) begin
      $display("  PASS | %s", name);
      pass_cnt++;
    end else begin
      $error("  FAIL | %s", name);
      fail_cnt++;
    end
  endtask

  // ===========================================================================
  // CDC BRIDGE SIGNALS (pl_clk domain)
  // ===========================================================================
  fp32_t pl_wp_x   [NUM_WAYPOINTS-1:0];
  fp32_t pl_wp_y   [NUM_WAYPOINTS-1:0];
  logic  pl_valid  = 1'b0;
  logic  pl_sanity = 1'b1;

  fp32_t hmao_wp_x  [NUM_WAYPOINTS-1:0];
  fp32_t hmao_wp_y  [NUM_WAYPOINTS-1:0];
  logic  hmao_wp_valid;
  logic  hmao_sanity;

  hmao_cdc_bridge u_cdc (
    .pl_clk              (pl_clk),
    .pl_rst_n            (pl_rst_n),
    .pl_waypoint_x       (pl_wp_x),
    .pl_waypoint_y       (pl_wp_y),
    .pl_waypoints_valid  (pl_valid),
    .pl_sanity_pass      (pl_sanity),
    .hmao_clk            (hmao_clk),
    .hmao_rst_n          (hmao_rst_n),
    .hmao_waypoint_x     (hmao_wp_x),
    .hmao_waypoint_y     (hmao_wp_y),
    .hmao_waypoints_valid(hmao_wp_valid),
    .hmao_sanity_pass    (hmao_sanity)
  );

  // ===========================================================================
  // HMAO ENGINE SIGNALS
  // ===========================================================================
  logic       hmao_start    = 1'b0;
  logic [7:0] gps_quality   = 8'd200;
  logic [7:0] cam_quality   = 8'd200;
  logic [7:0] road_friction = 8'd200;
  logic [7:0] act_health    = 8'd255;
  logic [7:0] weather       = 8'd0;

  logic        hmao_complete;
  logic        hmao_decision;
  logic [63:0] hmao_violation;
  logic [31:0] hmao_status;
  logic [31:0] hmao_latency;
  logic [15:0] lat_margin, long_margin, time_margin;
  logic        irq_clear = 1'b0;
  hmao_fault_t fault_out;
  logic        fault_valid;
  logic        dbg_start_preproc, dbg_preproc_valid, dbg_preproc_error;
  logic [6:0]  dbg_fsm_raw;
  logic        dbg_hmao_start_rx;

  // ===========================================================================
  // AXI MEMORY MODEL
  // ===========================================================================
  logic [31:0] traj_mem [0:350];
  logic [31:0] wm_mem   [0:511];   // all zeros → no obstacles

  logic [31:0]  hmao_araddr;
  logic [7:0]   hmao_arlen;
  logic [2:0]   hmao_arsize;
  logic [1:0]   hmao_arburst;
  logic         hmao_arvalid;
  logic [7:0]   hmao_aruser;
  logic         hmao_arready;
  logic [255:0] hmao_rdata;
  logic [1:0]   hmao_rresp  = 2'b00;
  logic         hmao_rlast  = 1'b0;
  logic         hmao_rvalid = 1'b0;
  logic         hmao_rready;

  logic [7:0]  axi_beats_rem;
  logic [10:0] axi_beat_woff;
  logic        axi_in_traj_rgn;
  logic        axi_in_wm_rgn;
  logic        axi_wm_wide;

  logic ar_accepted;
  assign ar_accepted = hmao_arvalid && hmao_arready;

  always_comb begin
    if (axi_in_traj_rgn)
      hmao_rdata = ({224'd0, traj_mem[axi_beat_woff]} << {axi_beat_woff[2:0], 5'b0});
    else if (axi_in_wm_rgn)
      hmao_rdata = {wm_mem[axi_beat_woff+7], wm_mem[axi_beat_woff+6],
                    wm_mem[axi_beat_woff+5], wm_mem[axi_beat_woff+4],
                    wm_mem[axi_beat_woff+3], wm_mem[axi_beat_woff+2],
                    wm_mem[axi_beat_woff+1], wm_mem[axi_beat_woff+0]};
    else
      hmao_rdata = '0;
  end

  always_ff @(posedge hmao_clk) begin
    if (!hmao_rst_n) begin
      hmao_rvalid <= 1'b0; hmao_rlast <= 1'b0; hmao_rresp <= 2'b00;
      axi_beats_rem <= '0; axi_beat_woff <= '0;
      axi_in_traj_rgn <= 1'b0; axi_in_wm_rgn <= 1'b0; axi_wm_wide <= 1'b0;
    end else begin
      if (ar_accepted) begin
        axi_beats_rem   <= hmao_arlen;
        axi_in_traj_rgn <= (hmao_araddr >= TRAJ_BUFFER_BASE &&
                            hmao_araddr <  TRAJ_BUFFER_BASE + 32'h0578);
        axi_in_wm_rgn   <= (hmao_araddr >= WORLD_MODEL_BASE &&
                            hmao_araddr <  WORLD_MODEL_BASE + 32'h0020_0000);
        axi_wm_wide     <= (hmao_arsize == 3'b101);
        if (hmao_araddr >= WORLD_MODEL_BASE)
          axi_beat_woff <= 11'((hmao_araddr - WORLD_MODEL_BASE) >> 2);
        else
          axi_beat_woff <= 11'((hmao_araddr - TRAJ_BUFFER_BASE) >> 2);
      end
      if (ar_accepted) begin
        hmao_rvalid <= 1'b1;
        hmao_rlast  <= (hmao_arlen == 8'd0);
        hmao_rresp  <= 2'b00;
      end else if (hmao_rvalid && hmao_rready) begin
        if (hmao_rlast) begin
          hmao_rvalid <= 1'b0; hmao_rlast <= 1'b0;
        end else begin
          axi_beat_woff <= axi_beat_woff + (axi_wm_wide ? 11'd8 : 11'd1);
          axi_beats_rem <= axi_beats_rem - 1'b1;
          hmao_rlast    <= (axi_beats_rem == 8'd1);
        end
      end
    end
  end
  assign hmao_arready = !hmao_rvalid;

  // ===========================================================================
  // DUT: hmao_engine_top
  // ===========================================================================
  axi4_ro_if #(.ADDR_W(AXI_ADDR_W), .DATA_W(AXI_DATA_W), .ID_W(AXI_ID_W))
    u_axi_ro (.aclk(hmao_clk), .aresetn(hmao_rst_n));
  hmao_pipe_if u_pipe();

  hmao_engine_top u_hmao (
    .clk                       (hmao_clk),
    .rst_n                     (hmao_rst_n),
    .hmao_start                (hmao_start),
    .gps_quality               (gps_quality),
    .camera_quality            (cam_quality),
    .road_friction             (road_friction),
    .actuator_health           (act_health),
    .weather_severity          (weather),
    .axi_ro                    (u_axi_ro),
    .pipe                      (u_pipe),
    .wdt_clk                   (wdt_clk),
    .hmao_complete             (hmao_complete),
    .hmao_decision_out         (hmao_decision),
    .hmao_violation_out        (hmao_violation),
    .hmao_status_out           (hmao_status),
    .hmao_latency_out          (hmao_latency),
    .lateral_margin_out        (lat_margin),
    .long_margin_out           (long_margin),
    .time_margin_out           (time_margin),
    .irq_clear                 (irq_clear),
    .debug_start_preproc       (dbg_start_preproc),
    .debug_fsm_state_encoded   (dbg_fsm_raw),
    .debug_hmao_start_received (dbg_hmao_start_rx),
    .debug_preproc_valid       (dbg_preproc_valid),
    .debug_preproc_error       (dbg_preproc_error),
    .fault_out                 (fault_out),
    .fault_valid_out           (fault_valid)
  );

  assign hmao_araddr  = u_axi_ro.araddr;
  assign hmao_arlen   = u_axi_ro.arlen;
  assign hmao_arsize  = u_axi_ro.arsize;
  assign hmao_arburst = u_axi_ro.arburst;
  assign hmao_arvalid = u_axi_ro.arvalid;
  assign hmao_aruser  = u_axi_ro.aruser;
  assign hmao_rready  = u_axi_ro.rready;
  assign u_axi_ro.arready = hmao_arready;
  assign u_axi_ro.rid     = '0;
  assign u_axi_ro.rdata   = hmao_rdata;
  assign u_axi_ro.rresp   = hmao_rresp;
  assign u_axi_ro.rlast   = hmao_rlast;
  assign u_axi_ro.rvalid  = hmao_rvalid;

  // ===========================================================================
  // HELPER TASKS
  // ===========================================================================
  task automatic cdc_send_wps(
    input fp32_t wx[NUM_WAYPOINTS-1:0],
    input fp32_t wy[NUM_WAYPOINTS-1:0],
    input logic  sanity
  );
    @(posedge pl_clk);
    for (int w = 0; w < NUM_WAYPOINTS; w++) begin
      pl_wp_x[w] <= wx[w]; pl_wp_y[w] <= wy[w];
    end
    pl_sanity <= sanity; pl_valid <= 1'b1;
    @(posedge pl_clk);
    pl_valid <= 1'b0;
  endtask

  task automatic cdc_wait_valid(input int timeout_cy, output logic ok);
    ok = 1'b0;
    for (int c = 0; c < timeout_cy; c++) begin
      @(posedge hmao_clk);
      if (hmao_wp_valid) begin ok = 1'b1; return; end
    end
  endtask

  // Hard-reset both clock domains.
  // Called before each test case to clear WDT accumulators, sticky fault bits
  // (kinematic_fail, crc_fail), complete_latch, and FSM state.
  task automatic reset_dut();
    pl_rst_n   = 1'b0;
    hmao_rst_n = 1'b0;
    irq_clear  = 1'b0;
    hmao_start = 1'b0;
    repeat(20) @(posedge pl_clk);
    pl_rst_n   = 1'b1;
    repeat(5)  @(posedge hmao_clk);
    hmao_rst_n = 1'b1;
    repeat(20) @(posedge hmao_clk);
  endtask

  task automatic run_hmao_engine(
    input  int   timeout_cy,
    output logic ok,
    output logic decision,
    output logic [7:0] fault_bits
  );
    ok = 1'b0; decision = 1'b0; fault_bits = 8'h0;
    @(posedge hmao_clk);
    hmao_start <= 1'b1;
    @(posedge hmao_clk);
    hmao_start <= 1'b0;
    for (int c = 0; c < timeout_cy; c++) begin
      @(posedge hmao_clk);
      if (hmao_complete) begin ok = 1'b1; break; end
    end
    @(posedge hmao_clk);
    if (ok) begin
      decision   = hmao_decision;
      fault_bits = fault_out;
    end
  endtask

  task automatic extract_gru_wps(
    output fp32_t wx[NUM_WAYPOINTS-1:0],
    output fp32_t wy[NUM_WAYPOINTS-1:0]
  );
    automatic int idx[4] = '{5, 10, 15, 20};
    for (int k = 0; k < NUM_WAYPOINTS; k++) begin
      wx[k] = traj_mem[idx[k] * 7 + 0];
      wy[k] = traj_mem[idx[k] * 7 + 1];
    end
  endtask

  // Run one edge case: load hex, drive CDC, run HMAO, check decision + faults
  task automatic run_edge_case(
    input string  ec_id,
    input string  hex_path,
    input string  description,
    input logic   expect_grant,    // 1=expect GRANT, 0=expect VETO
    input logic [7:0] expect_faults
  );
    fp32_t gru_wp_x[NUM_WAYPOINTS-1:0];
    fp32_t gru_wp_y[NUM_WAYPOINTS-1:0];
    logic  cdc_ok, hmao_ok, decision;
    logic [7:0] fault_bits;

    $display("\n  ┌─ %s: %s", ec_id, description);

    // Full DUT reset before each case: clears WDT, sticky preproc bits, FSM state.
    reset_dut();

    // Load hex
    $readmemh(hex_path, traj_mem);
    foreach (wm_mem[i]) wm_mem[i] = 32'h0;

    // Show stored CRC from hex
    $display("  │  CRC stored=0x%08h", traj_mem[350]);

    // Extract GRU waypoints from buffer
    extract_gru_wps(gru_wp_x, gru_wp_y);
    $display("  │  GRU_WP[0] x=%.4f y=%.4f",
             $bitstoshortreal(gru_wp_x[0]), $bitstoshortreal(gru_wp_y[0]));

    // CDC bridge
    cdc_send_wps(gru_wp_x, gru_wp_y, 1'b1);
    cdc_wait_valid(500, cdc_ok);

    // HMAO engine (8M cycles = 20ms @ 400MHz timeout)
    run_hmao_engine(8_000_000, hmao_ok, decision, fault_bits);

    if (hmao_ok) begin
      $display("  │  Decision=%s  Faults=0x%02h  Latency=%0d cy",
               decision ? "GRANT" : "VETO", fault_bits, hmao_latency);
      $display("  │  Expected=%s  ExpFaults=0x%02h",
               expect_grant ? "GRANT" : "VETO", expect_faults);
    end

    check({ec_id, "_cdc_ok"},     cdc_ok);
    check({ec_id, "_hmao_done"},  hmao_ok);
    check({ec_id, "_decision"},   decision == expect_grant);
    check({ec_id, "_faults"},     fault_bits == expect_faults);
    $display("  └─ %s %s", ec_id, (decision == expect_grant && fault_bits == expect_faults) ? "PASS" : "FAIL");
  endtask

  // ===========================================================================
  // MAIN TEST FLOW
  // ===========================================================================
  initial begin
    for (int w = 0; w < NUM_WAYPOINTS; w++) begin
      pl_wp_x[w] = '0; pl_wp_y[w] = '0;
    end
    pl_valid = 1'b0; pl_sanity = 1'b1;

    // Let reset signals settle from declaration initializers
    repeat(5) @(posedge hmao_clk);

    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║  HMAO Edge Case / Boundary Condition Test  (7 cases)        ║");
    $display("║  Verifies exact GRANT/VETO decisions and fault bits         ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    $display("");
    $display("  kinematic_invalid threshold: biased_exp > 132 = |v| >= 64 m/s");
    $display("  traj_crc_fail: stored CRC != computed CRC32 over 1400 bytes");
    $display("");

    // ── EC-01: Nominal (sample_00) ────────────────────────────────────────────
    run_edge_case("EC01", "sw/hmao_payloads/traj_ec01.hex",
      "Nominal sample_00  vx=8.4m/s  biased_exp=130",
      1'b1, 8'h00);
    repeat(20) @(posedge hmao_clk);

    // ── EC-02: Stationary (all zeros) ─────────────────────────────────────────
    run_edge_case("EC02", "sw/hmao_payloads/traj_ec02.hex",
      "Stationary  vx=vy=0  biased_exp=0",
      1'b1, 8'h00);
    repeat(20) @(posedge hmao_clk);

    // ── EC-03: vx=32.0 m/s exactly (biased_exp=132, AT limit → PASS) ─────────
    run_edge_case("EC03", "sw/hmao_payloads/traj_ec03.hex",
      "vx=32.0m/s  biased_exp=132  AT kinematic limit  → GRANT",
      1'b1, 8'h00);
    repeat(20) @(posedge hmao_clk);

    // ── EC-04: vx=64.0 m/s (biased_exp=133, OVER limit → VETO) ──────────────
    run_edge_case("EC04", "sw/hmao_payloads/traj_ec04.hex",
      "vx=64.0m/s  biased_exp=133  OVER kinematic limit  → VETO(kinematic_invalid)",
      1'b0, 8'h01);   // fault bit 0 = kinematic_invalid
    repeat(20) @(posedge hmao_clk);

    // ── EC-05: vx=35.0 m/s (VMAX clamp point, biased_exp=132 → PASS) ─────────
    run_edge_case("EC05", "sw/hmao_payloads/traj_ec05.hex",
      "vx=35.0m/s  biased_exp=132  VMAX clamp boundary  → GRANT",
      1'b1, 8'h00);
    repeat(20) @(posedge hmao_clk);

    // ── EC-06: CRC corrupted (byte[0] ^= 0xFF) ────────────────────────────────
    run_edge_case("EC06", "sw/hmao_payloads/traj_ec06.hex",
      "CRC CORRUPTED: byte[0] flipped  → VETO(traj_crc_fail)",
      1'b0, 8'h08);   // fault bit 3 = trajectory_crc_fail
    repeat(20) @(posedge hmao_clk);

    // ── EC-07: CRC = 0x00000000 (zero CRC, wrong) ────────────────────────────
    run_edge_case("EC07", "sw/hmao_payloads/traj_ec07.hex",
      "CRC = 0x00000000  wrong CRC  → VETO(traj_crc_fail)",
      1'b0, 8'h08);   // fault bit 3 = trajectory_crc_fail

    // ── Summary ───────────────────────────────────────────────────────────────
    repeat(5) @(posedge hmao_clk);
    $display("");
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║  HMAO Edge Case Results                                     ║");
    $display("╠══════════════════════════════════════════════════════════════╣");
    $display("║  PASS: %-3d  FAIL: %-3d  TOTAL: %-3d",
             pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    if (fail_cnt == 0)
      $display("║  ALL PASS — kinematic + CRC boundaries verified in RTL     ║");
    else
      $display("║  FAILURES DETECTED — check log above                       ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
