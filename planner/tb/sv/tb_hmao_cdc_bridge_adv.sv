// =============================================================================
// tb_hmao_cdc_bridge.sv — Advanced Unit Testbench for hmao_cdc_bridge
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_hmao_cdc_bridge;
  import planning_pkg::*;

  // ===========================================================================
  // 1. CLOCK GENERATION (With Asynchronous Phase Offset)
  // ===========================================================================
  logic pl_clk   = 1'b0;
  logic hmao_clk = 1'b0;
  logic pl_rst_n, hmao_rst_n;

  // 200 MHz PL clock (T = 5ns -> Half-period = 2.5ns)
  initial begin
    #1.23; // Tạo độ lệch pha (phase shift) ngẫu nhiên so với HMAO clock
    forever #2.5 pl_clk = ~pl_clk;
  end

  // 100 MHz HMAO clock (T = 10ns -> Half-period = 5.0ns)
  initial begin
    forever #5.0 hmao_clk = ~hmao_clk;
  end

  // ===========================================================================
  // 2. DUT CONNECTIONS
  // ===========================================================================
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

  // ===========================================================================
  // 3. CHECKERS & HELPERS
  // ===========================================================================
  int pass_cnt = 0;
  int fail_cnt = 0;

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  [PASS] %-35s = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-35s got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_hex(input string name, input logic [31:0] got, input logic [31:0] exp);
    if (got === exp) begin
      // $display("  [PASS] %-35s = 0x%08h", name, got); // Uncomment to see all data passes
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-35s got=0x%08h exp=0x%08h", name, got, exp);
      fail_cnt++;
    end
  endtask

  function automatic logic [31:0] real_to_fp32(input real v);
    return $realtobits(v);
  endfunction

  // Task gửi dữ liệu
  task send_pl_waypoints(
    input real x0, y0, x1, y1, x2, y2, x3, y3,
    input logic sanity
  );
    @(posedge pl_clk); #0.1;
    pl_waypoint_x[0] = real_to_fp32(x0); pl_waypoint_y[0] = real_to_fp32(y0);
    pl_waypoint_x[1] = real_to_fp32(x1); pl_waypoint_y[1] = real_to_fp32(y1);
    pl_waypoint_x[2] = real_to_fp32(x2); pl_waypoint_y[2] = real_to_fp32(y2);
    pl_waypoint_x[3] = real_to_fp32(x3); pl_waypoint_y[3] = real_to_fp32(y3);
    pl_sanity_pass   = sanity;
    pl_waypoints_valid = 1'b1;
    @(posedge pl_clk); #0.1;
    pl_waypoints_valid = 1'b0;
  endtask

  // Task chờ và verify TOÀN BỘ dữ liệu ở HMAO
  task verify_hmao_data(
    input string test_name,
    input real x0, y0, x1, y1, x2, y2, x3, y3,
    input logic sanity
  );
    logic detected = 0;
    // Timeout counter
    for (int i = 0; i < 50; i++) begin
      @(posedge hmao_clk); #0.1;
      if (hmao_waypoints_valid) begin
        detected = 1'b1;
        break;
      end
    end

    check_bit({test_name, " - Valid CDC Pulse"}, detected, 1'b1);
    
    if (detected) begin
      @(posedge hmao_clk); #0.1; // Chờ 1 cycle để data lọt vào thanh ghi đầu ra
      check_hex({test_name, " - WP[0].x"}, hmao_waypoint_x[0], real_to_fp32(x0));
      check_hex({test_name, " - WP[0].y"}, hmao_waypoint_y[0], real_to_fp32(y0));
      check_hex({test_name, " - WP[1].x"}, hmao_waypoint_x[1], real_to_fp32(x1));
      check_hex({test_name, " - WP[1].y"}, hmao_waypoint_y[1], real_to_fp32(y1));
      check_hex({test_name, " - WP[2].x"}, hmao_waypoint_x[2], real_to_fp32(x2));
      check_hex({test_name, " - WP[2].y"}, hmao_waypoint_y[2], real_to_fp32(y2));
      check_hex({test_name, " - WP[3].x"}, hmao_waypoint_x[3], real_to_fp32(x3));
      check_hex({test_name, " - WP[3].y"}, hmao_waypoint_y[3], real_to_fp32(y3));
      check_bit({test_name, " - Sanity"},  hmao_sanity_pass, sanity);
      $display("  [PASS] %s - All 8 FP32 coordinates verified successfully.", test_name);
    end
  endtask

  // ===========================================================================
  // 4. MAIN TEST SEQUENCES
  // ===========================================================================
  initial begin
    $display("===============================================================");
    $display("=== STARTING ADVANCED TB: hmao_cdc_bridge ===");
    $display("===============================================================");

    // Init
    pl_waypoints_valid = 0; pl_sanity_pass = 0;
    for (int i=0; i<NUM_WAYPOINTS; i++) begin
      pl_waypoint_x[i] = '0; pl_waypoint_y[i] = '0;
    end

    // --- TEST 1: System Reset ---
    $display("\n--- T1: System Reset & Initial State ---");
    pl_rst_n = 0; hmao_rst_n = 0;
    repeat(5) @(posedge pl_clk);
    pl_rst_n = 1; hmao_rst_n = 1;
    repeat(2) @(posedge hmao_clk);
    check_bit("T1 - Initial hmao_valid is 0", hmao_waypoints_valid, 1'b0);

    // --- TEST 2: Full Data Happy Path ---
    $display("\n--- T2: Full Array CDC Transfer ---");
    send_pl_waypoints(1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8, 1'b1);
    verify_hmao_data("T2", 1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8, 1'b1);

    // --- TEST 3: Glitch & Stability Test ---
    $display("\n--- T3: Input Glitch Rejection ---");
    // Wiggle inputs WITHOUT asserting valid
    for (int i=0; i<10; i++) begin
      @(posedge pl_clk); #0.1;
      pl_waypoint_x[0] = $urandom; 
      pl_waypoint_y[1] = $urandom;
    end
    // Chờ xem bên HMAO có bị lọt valid pulse nào không
    repeat(10) @(posedge hmao_clk); #0.1;
    check_bit("T3 - Valid remains 0 during glitch", hmao_waypoints_valid, 1'b0);
    // Data HMAO phải giữ nguyên giá trị của T2 (không bị nhiễu ghi đè)
    check_hex("T3 - WP[0].x stable", hmao_waypoint_x[0], real_to_fp32(1.1));

    // --- TEST 4: Back-to-Back Safe Transfer ---
    $display("\n--- T4: Back-to-Back Safe Transfers ---");
    send_pl_waypoints(10.0, 10.0, 20.0, 20.0, 30.0, 30.0, 40.0, 40.0, 1'b0);
    verify_hmao_data("T4_A", 10.0, 10.0, 20.0, 20.0, 30.0, 30.0, 40.0, 40.0, 1'b0);
    
    // Gửi ngay lập tức gói B sau khi gói A vừa hoàn thành
    send_pl_waypoints(99.0, 99.0, 88.0, 88.0, 77.0, 77.0, 66.0, 66.0, 1'b1);
    verify_hmao_data("T4_B", 99.0, 99.0, 88.0, 88.0, 77.0, 77.0, 66.0, 66.0, 1'b1);

    // --- TEST 5: In-Flight Reset (Cực kỳ quan trọng với CDC) ---
    $display("\n--- T5: In-Flight Asynchronous Reset ---");
    send_pl_waypoints(111.0, 222.0, 333.0, 444.0, 555.0, 666.0, 777.0, 888.0, 1'b1);
    // Chờ một chút để cờ toggle đang nằm giữa cầu CDC (chưa ra tới valid)
    @(posedge hmao_clk); 
    @(posedge hmao_clk); #0.1;
    hmao_rst_n = 0; // Đột ngột reset HMAO domain
    $display("  [INFO] Asserted hmao_rst_n mid-transfer");
    repeat(3) @(posedge hmao_clk);
    check_bit("T5 - hmao_valid blocked by reset", hmao_waypoints_valid, 1'b0);
    hmao_rst_n = 1;
    repeat(3) @(posedge hmao_clk);
    
    // Test recovery: Gửi data mới xem cầu CDC có bị deadlock không
    $display("  [INFO] Testing recovery after reset...");
    send_pl_waypoints(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1'b0);
    verify_hmao_data("T5_Recovery", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1'b0);

    // --- KẾT QUẢ ---
    $display("\n===============================================================");
    $display("=== SUMMARY: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("=== [SUCCESS] hmao_cdc_bridge passed all advanced tests! ===");
      $finish(0);
    end else begin
      $fatal(1, "=== [FAILED] hmao_cdc_bridge — %0d test(s) failed ===", fail_cnt);
    end
  end

  // ===========================================================================
  // 5. CONCURRENT ASSERTIONS (Bắt lỗi Overrun)
  // ===========================================================================
  // Thiết kế này không có tín hiệu Ack, PL phải đợi một khoảng an toàn (>= 4 HMAO clocks = 8 PL clocks).
  // Assertion này sẽ ném lỗi nếu logic phía PL bắn valid quá nhanh, gây mất dữ liệu.
  property p_safe_cdc_interval;
    @(posedge pl_clk) disable iff (!pl_rst_n)
      pl_waypoints_valid |=> !pl_waypoints_valid [*8];
  endproperty
  assert_safe_cdc: assert property(p_safe_cdc_interval) 
    else $error("CDC OVERRUN VIOLATION: pl_waypoints_valid asserted too quickly!");

  // Timeout Watchdog
  initial begin
    #50000;
    $fatal(1, "TIMEOUT: simulation exceeded 50 us");
  end

endmodule
`default_nettype wire