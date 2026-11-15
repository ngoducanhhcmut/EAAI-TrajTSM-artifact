// =============================================================================
// tb_hmao_cdc_bridge.sv — Unit Testbench for hmao_cdc_bridge
// Tests FP32 waypoint CDC crossing: PL clock domain → HMAO clock domain
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_hmao_cdc_bridge;
  import planning_pkg::*;

  // Two distinct clocks (different frequencies)
  logic pl_clk   = 1'b0;
  logic hmao_clk = 1'b0;
  logic pl_rst_n, hmao_rst_n;

  always #2.5  pl_clk   = ~pl_clk;   // 200 MHz PL clock
  always #5.0  hmao_clk = ~hmao_clk; // 100 MHz HMAO clock

  // ── DUT ports ─────────────────────────────────────────────────────────────
  fp32_t  pl_waypoint_x   [NUM_WAYPOINTS-1:0];
  fp32_t  pl_waypoint_y   [NUM_WAYPOINTS-1:0];
  logic   pl_waypoints_valid;
  logic   pl_sanity_pass;

  fp32_t  hmao_waypoint_x [NUM_WAYPOINTS-1:0];
  fp32_t  hmao_waypoint_y [NUM_WAYPOINTS-1:0];
  logic   hmao_waypoints_valid;
  logic   hmao_sanity_pass;

  hmao_cdc_bridge dut (
    .pl_clk              (pl_clk),
    .pl_rst_n            (pl_rst_n),
    .pl_waypoint_x       (pl_waypoint_x),
    .pl_waypoint_y       (pl_waypoint_y),
    .pl_waypoints_valid  (pl_waypoints_valid),
    .pl_sanity_pass      (pl_sanity_pass),
    .hmao_clk            (hmao_clk),
    .hmao_rst_n          (hmao_rst_n),
    .hmao_waypoint_x     (hmao_waypoint_x),
    .hmao_waypoint_y     (hmao_waypoint_y),
    .hmao_waypoints_valid(hmao_waypoints_valid),
    .hmao_sanity_pass    (hmao_sanity_pass)
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick_pl(input int n = 1);
    repeat(n) @(posedge pl_clk); #0.1;
  endtask

  task tick_hmao(input int n = 1);
    repeat(n) @(posedge hmao_clk); #0.1;
  endtask

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_hex(input string name, input logic [31:0] got, input logic [31:0] exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = 0x%08h", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=0x%08h exp=0x%08h", name, got, exp);
      fail_cnt++;
    end
  endtask

  function automatic logic [31:0] real_to_fp32(input real v);
    return $realtobits(v);
  endfunction

  // Drive new waypoints from PL domain
  task set_pl_waypoints(
    input real x0, y0, x1, y1, x2, y2, x3, y3,
    input logic sanity
  );
    @(posedge pl_clk); #0.1;
    pl_waypoint_x[0] = real_to_fp32(x0);
    pl_waypoint_y[0] = real_to_fp32(y0);
    pl_waypoint_x[1] = real_to_fp32(x1);
    pl_waypoint_y[1] = real_to_fp32(y1);
    pl_waypoint_x[2] = real_to_fp32(x2);
    pl_waypoint_y[2] = real_to_fp32(y2);
    pl_waypoint_x[3] = real_to_fp32(x3);
    pl_waypoint_y[3] = real_to_fp32(y3);
    pl_sanity_pass   = sanity;
    pl_waypoints_valid = 1'b1;
    @(posedge pl_clk); #0.1;
    pl_waypoints_valid = 1'b0;
  endtask

  // Wait for hmao_waypoints_valid with timeout
  task wait_hmao_valid(output logic detected);
    detected = 1'b0;
    for (int i = 0; i < 40; i++) begin
      @(posedge hmao_clk); #0.1;
      if (hmao_waypoints_valid) begin
        detected = 1'b1;
        break;
      end
    end
  endtask

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_hmao_cdc_bridge : hmao_cdc_bridge ===");

    pl_waypoints_valid = 0;
    pl_sanity_pass     = 0;
    for (int i = 0; i < NUM_WAYPOINTS; i++) begin
      pl_waypoint_x[i] = 32'h0;
      pl_waypoint_y[i] = 32'h0;
    end
    pl_rst_n   = 0;
    hmao_rst_n = 0;
    tick_pl(3);
    tick_hmao(3);
    pl_rst_n   = 1;
    hmao_rst_n = 1;
    tick_pl(2);
    tick_hmao(2);

    // T1: After reset, hmao_waypoints_valid = 0
    check_bit("after_reset_hmao_valid", hmao_waypoints_valid, 1'b0);

    // T2: Drive waypoints from PL domain, verify they appear in HMAO domain
    set_pl_waypoints(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 1'b1);

    begin
      logic detected;
      wait_hmao_valid(detected);
      check_bit("wp_crosses_cdc", detected, 1'b1);
      if (detected) begin
        tick_hmao(1);  // wait one hmao_clk for registered outputs (sanity_r, data_r) to settle
        // Check wp[0] data crossed correctly
        check_hex("wp0_x_crossed", hmao_waypoint_x[0], real_to_fp32(1.0));
        check_hex("wp0_y_crossed", hmao_waypoint_y[0], real_to_fp32(2.0));
        check_hex("wp3_x_crossed", hmao_waypoint_x[3], real_to_fp32(7.0));
        check_hex("wp3_y_crossed", hmao_waypoint_y[3], real_to_fp32(8.0));
        check_bit("sanity_crossed", hmao_sanity_pass,  1'b1);
      end
    end

    // T3: Second set of waypoints
    tick_pl(5);
    set_pl_waypoints(10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 1'b0);
    begin
      logic detected;
      wait_hmao_valid(detected);
      check_bit("wp2_crosses_cdc", detected, 1'b1);
      if (detected) begin
        tick_hmao(1);  // wait for registered outputs to settle
        check_hex("wp2_x0", hmao_waypoint_x[0], real_to_fp32(10.0));
        check_bit("sanity2_cleared", hmao_sanity_pass, 1'b0);
      end
    end

    // T4: Sanity_pass = 1 propagates correctly
    tick_pl(5);
    set_pl_waypoints(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1'b1);
    begin
      logic detected;
      wait_hmao_valid(detected);
      if (detected) begin
        tick_hmao(1);  // wait for registered outputs to settle
        check_bit("sanity_pass_crosses", hmao_sanity_pass, 1'b1);
      end else begin
        $error("  FAIL [%-30s] timed out", "wp3_crosses_cdc");
        fail_cnt++;
      end
    end

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: hmao_cdc_bridge");
      $finish(0);
    end else
      $fatal(1, "FAIL: hmao_cdc_bridge — %0d test(s) failed", fail_cnt);
  end

  initial begin
    #100000;
    $fatal(1, "TIMEOUT: simulation exceeded 100 us");
  end

endmodule
`default_nettype wire
