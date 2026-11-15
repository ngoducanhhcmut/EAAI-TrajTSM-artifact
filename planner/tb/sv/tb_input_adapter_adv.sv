// =============================================================================
// tb_input_adapter.sv — Nâng cấp (Full Coverage & Corner Cases)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_input_adapter_adv;
  import planning_pkg::*;

  localparam int MAX_TOKS = 64;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk; // Chu kỳ 5ns (200MHz)

  // ── DUT ports ─────────────────────────────────────────────────────────────
  bbox6_t        token_in;
  token_type_t   token_type;
  logic          token_valid;
  logic          token_ready;

  bbox6_t        bbox_out [MAX_TOKS-1:0];
  logic  [7:0]   num_valid_tokens;
  fp32_t         target_x, target_y;
  attn_mask_t    attn_mask_out;
  logic          valid_out;

  // BUG-FIX (missing port): input_adapter.sv has a `clear_frame` input that
  // is the ONLY path (besides rst_n) which brings frame_complete/
  // num_tokens_cnt/token_write_idx back to 0 (see input_adapter.sv:35-42).
  // This TB left it unconnected (floating -> read as 0/false inside the
  // DUT's `if (clear_frame)`), so frame_complete latched permanently after
  // the first frame and never released token_ready again. TC1..TC5 are
  // explicitly written as "back-to-back, no rst_n" (see TC2 comment), so
  // the DUT is expected to self-clear.
  //
  // Timing: clear_frame must be combinational with valid_out (=frame_complete),
  // NOT registered -- the DUT samples clear_frame on the SAME edge that
  // valid_out first reads 1, clearing frame_complete by the very next cycle.
  // A registered (1-cycle-delayed) version arrives a cycle too late for the
  // "_1_cycle_valid_check" assertion in wait_and_check_frame().
  logic clear_frame;
  assign clear_frame = valid_out;

  input_adapter dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .clear_frame       (clear_frame),
    .token_in          (token_in),
    .token_type        (token_type),
    .token_valid       (token_valid),
    .token_ready       (token_ready),
    .bbox_out          (bbox_out),
    .num_valid_tokens  (num_valid_tokens),
    .target_x          (target_x),
    .target_y          (target_y),
    .attn_mask_out     (attn_mask_out),
    .valid_out         (valid_out)
  );

  // ── Helpers & Trackers ────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  [PASS] %-35s = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-35s got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_int(input string name, input int got, input int exp);
    if (got === exp) begin
      $display("  [PASS] %-35s = %0d", name, got);
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-35s got=%0d exp=%0d", name, got, exp);
      fail_cnt++;
    end
  endtask

  function automatic logic [31:0] real_to_fp32(input real v);
    return $realtobits(v);
  endfunction

  // Task gửi 1 token (Không dùng while(!ready) để có thể test ép tràn)
  task send_token_beat(
    input token_type_t ttype,
    input real x, input real y, 
    input logic force_valid = 1'b0 // Dùng để ép cấp valid ngay cả khi !ready
  );
    if (!token_ready && !force_valid) begin
      int timeout = 0;
      while (!token_ready && timeout < 100) begin
        @(posedge clk); timeout++;
      end
    end
    
    token_in        = '0; // Clear all fields
    token_in.x_min  = real_to_fp32(x);
    token_in.y_min  = real_to_fp32(y);
    token_type      = ttype;
    token_valid     = 1'b1;
    
    @(posedge clk); #0.1;
    token_valid     = 1'b0;
  endtask

  // Task đợi và kiểm tra output + tính chất 1-cycle
  task wait_and_check_frame(
    input string tc_name, 
    input int exp_tokens, 
    input logic [63:0] exp_mask,
    input real exp_tgt_x, 
    input real exp_tgt_y
  );
    int wait_cycles = 0;
    $display("--- Checking %s ---", tc_name);
    
    // Đợi valid_out lên 1
    while (!valid_out && wait_cycles < 50) begin
      tick(1);
      wait_cycles++;
    end

    if (wait_cycles >= 50) begin
      $error("  [FAIL] %s - TIMEOUT waiting for valid_out", tc_name);
      fail_cnt++;
      return;
    end

    // Ngay tại cycle valid_out == 1
    $display("  [INFO] valid_out triggered after %0d idle cycles", wait_cycles);
    check_int({tc_name, "_num_tokens"}, int'(num_valid_tokens), exp_tokens);
    check_bit({tc_name, "_mask_match"}, attn_mask_out === exp_mask, 1'b1);
    check_int({tc_name, "_tgt_x"}, int'(target_x), int'(real_to_fp32(exp_tgt_x)));
    check_int({tc_name, "_tgt_y"}, int'(target_y), int'(real_to_fp32(exp_tgt_y)));

    // Nhảy sang cycle tiếp theo để check tính chất auto-clear (1-cycle valid)
    tick(1);
    check_bit({tc_name, "_1_cycle_valid_check"}, valid_out, 1'b0);
    check_int({tc_name, "_auto_reset_count"}, int'(num_valid_tokens), 0);
  endtask

  // ── KỊCH BẢN TEST CHÍNH ────────────────────────────────────────────────────
  initial begin
    $display("=================================================");
    $display("=== STARTING ADVANCED TB FOR INPUT_ADAPTER ===");
    $display("=================================================");
    
    // Khởi tạo
    token_in    = '0;
    token_type  = TT_CLS;
    token_valid = 0;
    rst_n       = 0;
    tick(5);
    rst_n       = 1;
    tick(2);

    // =========================================================================
    // TC1: STANDARD FRAME & TIMEOUT LOGIC
    // Gửi 3 tokens, đợi timeout 8 chu kỳ
    // =========================================================================
    $display("\n>>> TC1: Standard Frame (3 tokens) & Timeout logic");
    send_token_beat(TT_CLS,    0.0,  0.0);
    send_token_beat(TT_EGO,    1.0,  2.0);
    send_token_beat(TT_TARGET, 10.0, 20.0);
    
    // Mong đợi: 3 tokens, mask = 64'h0000_0000_0000_0007
    wait_and_check_frame("TC1", 3, 64'h0000_0000_0000_0007, 10.0, 20.0);


    // =========================================================================
    // TC2: BACK-TO-BACK FRAMES (NO RESET)
    // Đảm bảo logic tự dọn dẹp biến nội bộ hoạt động đúng
    // =========================================================================
    $display("\n>>> TC2: Back-to-Back Frame (2 tokens, NO Hardware Reset)");
    // KHÔNG gán rst_n = 0 ở đây
    send_token_beat(TT_OBJECT, 5.0, 5.0);
    send_token_beat(TT_TARGET, 8.0, 8.0);
    
    // Nếu auto-reset lỗi, num_tokens sẽ cộng dồn thành 5. Đúng phải là 2.
    wait_and_check_frame("TC2", 2, 64'h0000_0000_0000_0003, 8.0, 8.0);


    // =========================================================================
    // TC3: STAGGERED TOKENS (INTERRUPTED DATA STREAM)
    // Kiểm tra idle_timeout có bị reset khi có token chèn ngang không
    // =========================================================================
    $display("\n>>> TC3: Staggered Stream (Timeout Interruption)");
    send_token_beat(TT_CLS, 0.0, 0.0);
    
    tick(4); // Nghỉ 4 cycles (chưa đủ 8 cycles để timeout)
    check_bit("TC3_no_early_valid_1", valid_out, 1'b0); // Đảm bảo chưa xuất valid
    
    send_token_beat(TT_TARGET, 15.0, -5.0);
    
    tick(5); // Lại nghỉ 5 cycles
    check_bit("TC3_no_early_valid_2", valid_out, 1'b0);
    
    send_token_beat(TT_OBJECT, 1.0, 1.0);
    
    // Lần này để yên cho timeout tự chạy hết
    wait_and_check_frame("TC3", 3, 64'h0000_0000_0000_0007, 15.0, -5.0);


    // =========================================================================
    // TC4: OVERFLOW PREVENTION (MAX 64 TOKENS)
    // Bơm 65 tokens liên tục, kiểm tra token_ready và xem có bị ghi đè rác không
    // =========================================================================
    $display("\n>>> TC4: Buffer Overflow Prevention (65 tokens)");
    for (int i = 0; i < 65; i++) begin
      if (i == 63) begin
        // Token thứ 64 (index 63) là TARGET để lưu tọa độ
        send_token_beat(TT_TARGET, 99.0, 99.0);
      end else begin
        // Cố tình ép gửi bằng force_valid=1 kể cả khi token_ready xuống 0 ở token thứ 65
        send_token_beat(TT_OBJECT, real'(i), real'(i), 1'b1);
      end
    end
    
    // Check ngay lập tức token_ready phải xuống 0
    check_bit("TC4_ready_deasserted", token_ready, 1'b0);
    
    // Chờ frame complete
    // Mong đợi: chỉ lấy đúng 64 tokens, mask full 1, Target không bị ghi đè bởi token 65
    wait_and_check_frame("TC4", 64, {64{1'b1}}, 99.0, 99.0);


    // =========================================================================
    // TC5: IDLE NO TOKENS
    // =========================================================================
    $display("\n>>> TC5: Empty Frame Idle Timeout");
    tick(20); // Vượt qua 8 cycles timeout
    // Trạng thái num_tokens_cnt == 0 không được phép kích hoạt valid_out
    check_bit("TC5_valid_stays_low", valid_out, 1'b0);


    // ── TỔNG KẾT ─────────────────────────────────────────────────────────────
    $display("\n=================================================");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    $display("=================================================");
    if (fail_cnt == 0) begin
      $display("SUCCESS: Tất cả các luồng logic và Edge-cases đã được pass!");
      $finish(0);
    end else begin
      $fatal(1, "FAILURE: input_adapter — %0d test(s) failed", fail_cnt);
    end
  end

  // Watchdog Timer
  initial begin
    #50000;
    $fatal(1, "CRITICAL: Mô phỏng bị treo (Timeout 50us). Kiểm tra lại tín hiệu rst_n hoặc logic while-loop.");
  end

endmodule
`default_nettype wire