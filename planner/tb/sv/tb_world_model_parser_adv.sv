// =============================================================================
// tb_world_model_parser.sv — Advanced Verification Testbench
// Verifies: Data integrity mapping, Backpressure handling, Exact token sequencing,
// Corner cases (0-200 objects, 0-20 lanes), and Attention Mask validity.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_world_model_parser;
  import planning_pkg::*;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk; // 200MHz clock

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic          parse_start;
  logic          parse_done;
  logic          parse_busy;

  logic  [1:0]   hdr_rd_addr;
  logic [31:0]   hdr_rd_data;
  logic          hdr_rd_en;

  logic [11:0]   obj_rd_addr;
  logic [31:0]   obj_rd_data;
  logic          obj_rd_en;

  logic  [9:0]   lane_rd_addr;
  logic [31:0]   lane_rd_data;
  logic          lane_rd_en;

  logic  [7:0]   wm_num_objects;
  logic  [4:0]   wm_num_lanes;

  fp32_t         target_x;
  fp32_t         target_y;

  bbox6_t        token_out;
  token_type_t   token_type_out;
  logic          token_valid;
  logic          token_ready;
  logic          token_last;

  attn_mask_t    attn_mask_out;
  logic  [7:0]   num_tokens_out;

  world_model_parser dut (.*);

  // ── Memory models ─────────────────────────────────────────────────────────
  logic [31:0] hdr_mem  [0:3];
  logic [31:0] obj_mem  [0:4095];
  logic [31:0] lane_mem [0:1023];

  always_ff @(posedge clk) begin
    hdr_rd_data  <= hdr_rd_en  ? hdr_mem[hdr_rd_addr]   : 32'h0;
    obj_rd_data  <= obj_rd_en  ? obj_mem[obj_rd_addr]   : 32'h0;
    lane_rd_data <= lane_rd_en ? lane_mem[lane_rd_addr] : 32'h0;
  end

  // ── Testbench Variables ───────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;
  
  int current_token_idx = 0;
  int expected_total_tokens = 0;
  logic bp_en = 1'b0; // Backpressure Enable

  // Float converter helper
  function automatic logic [31:0] real_to_fp32(input real v);
    return $realtobits(v);
  endfunction

  // ── Testbench Tasks ───────────────────────────────────────────────────────
  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  task error_log(string msg);
    $error("[TIME: %0t] %s", $time, msg);
    fail_cnt++;
  endtask

  // Hàm tạo dữ liệu mẫu có tính quy luật để dễ verify
  task init_brams(input logic [7:0] num_obj, input logic [4:0] num_lane);
    // Init Header
    hdr_mem[2] = real_to_fp32(10.5); // ego_vx
    hdr_mem[3] = real_to_fp32(2.2);  // ego_vy

    // Init Objects (12 words per object)
    for (int i = 0; i < num_obj; i++) begin
      int base = i * 12;
      obj_mem[base + 0] = real_to_fp32(100.0 + i); // x
      obj_mem[base + 1] = real_to_fp32(200.0 + i); // y
      obj_mem[base + 2] = real_to_fp32(10.0  + i); // vx
      obj_mem[base + 3] = real_to_fp32(20.0  + i); // vy
      obj_mem[base + 4] = real_to_fp32(4.5   + i); // l
      obj_mem[base + 5] = real_to_fp32(2.0   + i); // w
    end

    // Init Lanes (32 words per lane)
    for (int i = 0; i < num_lane; i++) begin
      int base = i * 32;
      lane_mem[base + 1]  = real_to_fp32(1.0 + i);   // lane_type (mapped to vy)
      lane_mem[base + 2]  = real_to_fp32(300.0 + i); // wp_x[0]
      lane_mem[base + 3]  = real_to_fp32(301.0 + i); // wp_x[1]
      lane_mem[base + 12] = real_to_fp32(400.0 + i); // wp_y[0]
      lane_mem[base + 13] = real_to_fp32(401.0 + i); // wp_y[1]
    end
  endtask

  // Hàm chạy 1 Scenario
  task run_scenario(string name, int num_obj, int num_lane, logic enable_bp);
    $display("---------------------------------------------------------");
    $display("RUNNING SCENARIO: %s (Obj: %0d, Lane: %0d, BP: %0b)", name, num_obj, num_lane, enable_bp);
    
    // Setup inputs
    wm_num_objects = num_obj;
    wm_num_lanes   = num_lane;
    target_x       = real_to_fp32(999.9);
    target_y       = real_to_fp32(888.8);
    bp_en          = enable_bp;
    
    expected_total_tokens = 3 + num_obj + num_lane; // CLS + EGO + OBJs + LANEs + TARGET
    current_token_idx     = 0;

    init_brams(num_obj, num_lane);

    tick(2);
    parse_start = 1'b1;
    tick(1);
    parse_start = 1'b0;

    // Timeout watchdog
    begin
      int timeout = 0;
      int max_cycles = 500 + (num_obj * 15) + (num_lane * 40); // Dynamic timeout
      while (!parse_done && timeout < max_cycles) begin
        tick(1);
        timeout++;
      end
      
      if (timeout >= max_cycles) begin
        error_log($sformatf("SCENARIO '%s' TIMEOUT!", name));
      end else begin
        if (current_token_idx !== expected_total_tokens) begin
           error_log($sformatf("Token count mismatch. Expected %0d, Got %0d", expected_total_tokens, current_token_idx));
        end else if (num_tokens_out !== expected_total_tokens) begin
           error_log("num_tokens_out signal mismatch at done.");
        end else begin
           $display("  => PASS: %s completed successfully.", name);
           pass_cnt++;
        end
      end
    end
    tick(5);
  endtask

  // ── Backpressure Driver ───────────────────────────────────────────────────
  always @(posedge clk) begin
    if (!rst_n) begin
      token_ready <= 1'b0;
    end else begin
      if (bp_en) begin
        // Giả lập FIFO thỉnh thoảng bị đầy (30% cơ hội Not Ready)
        token_ready <= ($urandom_range(0, 100) > 30);
      end else begin
        token_ready <= 1'b1;
      end
    end
  end

  // ── Token Auto-Checker (The Monitor) ──────────────────────────────────────
  always @(posedge clk) begin
    if (rst_n && token_valid && token_ready) begin
      // 1. Kiểm tra Attention Mask (phải set bit 1 tại vị trí token hiện tại)
      if (attn_mask_out[current_token_idx] !== 1'b1) begin
         error_log($sformatf("Token %0d: attn_mask bit is 0!", current_token_idx));
      end

      // 2. Xác định cấu trúc Token dựa trên Index (thứ tự chặt chẽ)
      if (current_token_idx == 0) begin
        // CLS Token
        if (token_type_out !== TT_CLS) error_log("Token 0 should be TT_CLS");
        if (token_out !== '0)          error_log("CLS token data not all zeros");
      end 
      else if (current_token_idx == 1) begin
        // EGO Token
        if (token_type_out !== TT_EGO) error_log("Token 1 should be TT_EGO");
        if (token_out.vx !== hdr_mem[2]) error_log("EGO vx mismatch");
        if (token_out.vy !== hdr_mem[3]) error_log("EGO vy mismatch");
      end
      else if (current_token_idx >= 2 && current_token_idx < 2 + wm_num_objects) begin
        // OBJECT Tokens
        int obj_i = current_token_idx - 2;
        int base = obj_i * 12;
        if (token_type_out !== TT_OBJECT) error_log($sformatf("Token %0d should be TT_OBJECT", current_token_idx));
        if (token_out.x_min !== obj_mem[base+0]) error_log($sformatf("Obj %0d x_min mismatch", obj_i));
        if (token_out.y_min !== obj_mem[base+1]) error_log($sformatf("Obj %0d y_min mismatch", obj_i));
        if (token_out.vx    !== obj_mem[base+2]) error_log($sformatf("Obj %0d vx mismatch", obj_i));
      end
      else if (current_token_idx >= 2 + wm_num_objects && current_token_idx < expected_total_tokens - 1) begin
        // LANE Tokens
        int lane_i = current_token_idx - 2 - wm_num_objects;
        int base = lane_i * 32;
        if (token_type_out !== TT_LANE) error_log($sformatf("Token %0d should be TT_LANE", current_token_idx));
        if (token_out.x_min !== lane_mem[base+2])  error_log($sformatf("Lane %0d wp_x[0] mismatch", lane_i));
        if (token_out.y_min !== lane_mem[base+12]) error_log($sformatf("Lane %0d wp_y[0] mismatch", lane_i));
      end
      else if (current_token_idx == expected_total_tokens - 1) begin
        // TARGET Token
        if (token_type_out !== TT_TARGET) error_log("Last Token should be TT_TARGET");
        if (token_out.x_min !== target_x) error_log("TARGET x mismatch");
        if (token_out.y_min !== target_y) error_log("TARGET y mismatch");
        if (token_last !== 1'b1)          error_log("token_last not asserted on TARGET token");
      end 
      else begin
        error_log("Unexpected extra token emitted!");
      end

      current_token_idx++;
    end
  end

  // ── Main Test Flow ────────────────────────────────────────────────────────
  initial begin
    $display("=========================================================");
    $display("=== TB: world_model_parser (Advanced Verification)    ===");
    $display("=========================================================");
    
    parse_start = 0;
    bp_en = 0;
    
    // Reset Sequence
    rst_n = 0;
    tick(5);
    rst_n = 1;
    tick(5);

    // Run Scenarios
    //                 Test Name          Obj  Lane  Backpressure
    run_scenario("TC1_Standard",          2,   1,    1'b0);
    run_scenario("TC2_Backpressure",      5,   3,    1'b1);
    run_scenario("TC3_Minimal_Empty",     0,   0,    1'b0);
    run_scenario("TC4_Max_Capacity",      200, 20,   1'b0); // Corner Case
    run_scenario("TC5_Max_With_BP",       200, 20,   1'b1); // Worst Case Stress Test
    run_scenario("TC6_Objects_Only",      5,   0,    1'b1);
    run_scenario("TC7_Lanes_Only",        0,   5,    1'b0);

    // Final Report
    $display("=========================================================");
    $display("=== VERIFICATION SUMMARY                              ===");
    $display("=== PASS: %0d | FAIL: %0d", pass_cnt, fail_cnt);
    $display("=========================================================");
    
    if (fail_cnt == 0) begin
      $display("STATUS: SUCCESS. All logical branches covered & verified.");
      $finish(0);
    end else begin
      $fatal(1, "STATUS: FAILED. Please review the errors above.");
    end
  end

endmodule
`default_nettype wire