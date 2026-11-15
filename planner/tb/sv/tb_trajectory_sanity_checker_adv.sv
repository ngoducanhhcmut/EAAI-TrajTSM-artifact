// =============================================================================
// tb_trajectory_sanity_checker.sv — Comprehensive Testbench
// Covers NaN/INF, Speed, Accel, Curvature, Collision, Lane, and E-Stop Fallback.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_trajectory_sanity_checker_adv;
  localparam int NUM_WP       = 4;
  localparam int MAX_OBJ      = 16;
  localparam int NUM_LANE_PTS = 4;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic [31:0]  wp_x  [0:NUM_WP-1];
  logic [31:0]  wp_y  [0:NUM_WP-1];
  logic [31:0]  wp_v  [0:NUM_WP-1];
  logic         wp_valid;

  logic [31:0]  obj_cx  [0:MAX_OBJ-1];
  logic [31:0]  obj_cy  [0:MAX_OBJ-1];
  logic [31:0]  obj_hl  [0:MAX_OBJ-1];
  logic [31:0]  obj_hw  [0:MAX_OBJ-1];
  logic  [4:0]  obj_cnt;

  logic [31:0]  lane_left_y  [0:NUM_LANE_PTS-1];
  logic [31:0]  lane_right_y [0:NUM_LANE_PTS-1];

  logic [31:0]  csr_v_min;
  logic [31:0]  csr_v_max;
  logic [31:0]  csr_a_max;
  logic [31:0]  csr_curv_max;
  logic [31:0]  csr_min_clear;
  logic [31:0]  csr_lane_margin;

  logic         traj_valid;
  logic  [5:0]  fault_flags;
  logic         result_valid;

  logic [31:0]  fb_x [0:NUM_WP-1];
  logic [31:0]  fb_y [0:NUM_WP-1];
  logic [31:0]  fb_v [0:NUM_WP-1];
  logic         fb_valid;

  trajectory_sanity_checker #(
    .NUM_WP      (NUM_WP),
    .MAX_OBJ     (MAX_OBJ),
    .NUM_LANE_PTS(NUM_LANE_PTS)
  ) dut (.*); // Dùng .* để nối nhanh các port trùng tên

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;
  logic estop_err;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  // [SỬA LỖI CHÍ MẠNG] - Ép về shortreal (32-bit float) trước khi lấy bit
  function automatic logic [31:0] real_to_fp32(input real v);
    shortreal sv = shortreal'(v);
    return $shortrealtobits(sv);
  endfunction

  // Chuyển ngược lại từ 32-bit bit pattern sang số thực để dễ verify
  function automatic real fp32_to_real(input logic [31:0] bits);
    return real'($bitstoshortreal(bits));
  endfunction

  task reset_waypoints();
    for (int i = 0; i < NUM_WP; i++) begin
      wp_x[i] = real_to_fp32(real'(i * 5)); // 0, 5, 10, 15
      wp_y[i] = real_to_fp32(0.0);
      wp_v[i] = real_to_fp32(5.0);
    end
    obj_cnt = 0;
  endtask

  task run_check(output logic detected);
    detected = 1'b0;
    @(posedge clk); #0.1;
    wp_valid = 1'b1;
    @(posedge clk); #0.1;
    wp_valid = 1'b0;

    for (int i = 0; i < 500; i++) begin
      @(posedge clk); #0.1;
      if (result_valid) begin
        detected = 1'b1;
        break;
      end
    end
  endtask

  task run_and_check(input string test_name, input logic [5:0] exp_faults, input logic exp_traj_valid);
    logic det;
    run_check(det);
    if (!det) begin
      $error("  FAIL [%-30s] No result_valid triggered (Timeout)!", test_name);
      fail_cnt++;
    end else begin
      if (traj_valid === exp_traj_valid && fault_flags === exp_faults) begin
        $display("  PASS [%-30s] traj_valid=%0b, faults=%06b", test_name, traj_valid, fault_flags);
        pass_cnt++;
      end else begin
        $error("  FAIL [%-30s] Expected traj=%0b faults=%06b. Got traj=%0b faults=%06b", 
               test_name, exp_traj_valid, exp_faults, traj_valid, fault_flags);
        fail_cnt++;
      end
    end
  endtask

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("===============================================================");
    $display("=== TB: TRAJECTORY SANITY CHECKER (COMPREHENSIVE) ===");
    $display("===============================================================");
    wp_valid = 0;

    // Default CSRs
    csr_v_min      = real_to_fp32(0.0);
    csr_v_max      = real_to_fp32(30.0);    // 30 m/s max
    csr_a_max      = real_to_fp32(5.0);     // 5 m/s^2 max. DT=0.1 => dV_max = 0.5
    csr_curv_max   = real_to_fp32(0.5);     // 0.5 rad/m
    csr_min_clear  = real_to_fp32(1.0);     // 1m
    csr_lane_margin= real_to_fp32(0.5);     // 0.5m

    for (int i = 0; i < MAX_OBJ; i++) begin
      obj_cx[i] = real_to_fp32(1000.0); obj_cy[i] = real_to_fp32(1000.0);
      obj_hl[i] = real_to_fp32(1.0);    obj_hw[i] = real_to_fp32(1.0);
    end

    for (int i = 0; i < NUM_LANE_PTS; i++) begin
      lane_left_y[i]  = real_to_fp32(-5.0);
      lane_right_y[i] = real_to_fp32( 5.0);
    end

    rst_n = 0; tick(3);
    rst_n = 1; tick(2);

    $display("\n--- CATEGORY 1: BASELINE & DATA INTEGRITY ---");
    // T1: Normal Trajectory
    reset_waypoints();
    run_and_check("T1_Valid_Straight_Path", 6'b000000, 1'b1);

    // T2: NaN Detection (Check 0)
    reset_waypoints();
    wp_x[2] = 32'h7FC00000; // IEEE-754 NaN
    run_and_check("T2_Detect_NaN", 6'b000001, 1'b0);

    // T3: INF Detection (Check 0)
    // +INF in wp_v[3] correctly raises NaN/INF flag[0].
    // It also exceeds v_max (flag[1]) and causes |Δv|=INF > a_max*DT (flag[2]).
    reset_waypoints();
    wp_v[3] = 32'h7F800000; // IEEE-754 +INF
    run_and_check("T3_Detect_INF", 6'b000111, 1'b0);


    $display("\n--- CATEGORY 2: KINEMATICS (SPEED & ACCEL) ---");
    // T4: Over Speed Limit (Check 1)
    // wp_v[1]=35 > v_max=30 → speed fault (flag[1]).
    // Also |Δv| = |35-5|=30 > a_max*DT=0.5 → accel fault (flag[2]).
    reset_waypoints();
    wp_v[1] = real_to_fp32(35.0); // 35 > 30
    run_and_check("T4_Over_Speed_Limit", 6'b000110, 1'b0);

    // T5: Jerky Acceleration (Check 2) - dV_max allowed is 0.5
    reset_waypoints();
    wp_v[2] = real_to_fp32(6.0); // WP1=5.0, WP2=6.0. Delta=1.0 > 0.5
    run_and_check("T5_Sudden_Acceleration", 6'b000100, 1'b0);

    // T6: Hard Braking (Check 2)
    reset_waypoints();
    wp_v[1] = real_to_fp32(2.0); // WP0=5.0, WP1=2.0. Delta=-3.0. Abs(Delta)=3.0 > 0.5
    run_and_check("T6_Sudden_Deceleration", 6'b000100, 1'b0);


    $display("\n--- CATEGORY 3: GEOMETRY (CURVATURE) ---");
    // T7: High Curvature (Check 3) - Tạo khúc cua gắt 90 độ
    reset_waypoints();
    wp_x[1] = real_to_fp32(1.0); wp_y[1] = real_to_fp32(0.0);
    wp_x[2] = real_to_fp32(1.0); wp_y[2] = real_to_fp32(1.0); // Quẹo gắt
    wp_x[3] = real_to_fp32(1.0); wp_y[3] = real_to_fp32(2.0);
    run_and_check("T7_Sharp_Turn_Curvature", 6'b001000, 1'b0);


    $display("\n--- CATEGORY 4: ENVIRONMENT (COLLISION & LANE) ---");
    // T8: Collision Detection (Check 4)
    reset_waypoints();
    obj_cnt = 1;
    obj_cx[0] = real_to_fp32(5.5); // Nằm ngay sát mốc WP1(5.0)
    obj_cy[0] = real_to_fp32(0.0);
    obj_hl[0] = real_to_fp32(0.1); obj_hw[0] = real_to_fp32(0.1);
    // Khoảng cách thực = 0.5. Clear min cho phép = 1.0 => Xảy ra va chạm
    run_and_check("T8_Obstacle_Collision", 6'b010000, 1'b0);
    obj_cnt = 0; // Reset vật cản

    // T9: Lane Departure (Check 5)
    reset_waypoints();
    wp_y[3] = real_to_fp32(5.6); // Làn phải là 5.0, margin = 0.5. Giới hạn là 5.5.
    run_and_check("T9_Lane_Departure", 6'b100000, 1'b0);


    $display("\n--- CATEGORY 5: MULTIPLE FAULTS & E-STOP ---");
    // T10: Kích hoạt nhiều lỗi cùng lúc (Speed + Lane)
    reset_waypoints();
    wp_v[1] = real_to_fp32(40.0); // Lỗi tốc độ và gia tốc
    wp_y[2] = real_to_fp32(-6.0); // Lỗi làn
    run_and_check("T10_Multiple_Faults", 6'b100110, 1'b0);

    // T11: Verify E-Stop Fallback Trajectory Math
    begin
      real exp_v, got_v;
      estop_err = 1'b0;
      exp_v = 5.0; // Vận tốc ban đầu tại WP0

      $display("  [Verifying Fallback E-Stop Generation]");
      for (int i = 0; i < NUM_WP; i++) begin
        got_v = fp32_to_real(fb_v[i]);
        if (got_v > exp_v + 0.001 || got_v < exp_v - 0.001) begin
           $error("    WP[%0d] E-Stop Speed mismatch! Exp: %f, Got: %f", i, exp_v, got_v);
           estop_err = 1'b1;
        end
        // Tính cho node tiếp theo: v_next = v_cur - (a_max * DT)
        exp_v = exp_v - (5.0 * 0.1); 
        if (exp_v < 0.0) exp_v = 0.0;
      end
      
      if (!estop_err) begin
        $display("  PASS [%-30s] Math matches deceleration curve.", "T11_E_Stop_Verification");
        pass_cnt++;
      end else begin
        fail_cnt++;
      end
    end

    $display("\n===============================================================");
    $display("=== SUMMARY: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("=== RESULT:  SUCCESS! RTL IS ROBUST.");
      $finish(0);
    end else begin
      $fatal(1, "=== RESULT:  FAILED! Review RTL or Testbench logic.");
    end
  end

  initial begin
    #100000;
    $fatal(1, "TIMEOUT: simulation exceeded 100 us");
  end

endmodule
`default_nettype wire
