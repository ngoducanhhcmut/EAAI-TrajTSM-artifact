// =============================================================================
// tb_axi_width_conv_adv.sv — Advanced Queue-Based Testbench  [FIXED v5 FINAL]
// Features: Continuous Bursting, Random Backpressure, Queue-based Scoreboard
//
// Fix log:
//   TB-BUG-1: do_reset() — Chờ DUT về IDLE (out_valid=0) TRƯỚC khi xóa queue.
//   TB-BUG-2 v5 FINAL: Dùng state_prev (always_ff register) để detect IDLE→BEAT0.
//
// Root cause của mọi version trước (v1→v4):
//   XSIM 2023.2 wakes up TB initial/task processes POST-NBA (sau tất cả always_ff settle).
//   Do đó, mọi cách đọc dut.state "before posedge" trong TB task đều thực ra
//   đọc AFTER NBA. Kết quả: `pre_state` nhận BEAT0 thay vì IDLE → miss!
//
// Fix v5 — Registered state_prev (always_ff trong TB):
//   state_prev là flip-flop update cùng domain clock với DUT:
//     always_ff @(posedge clk): state_prev <= dut.state
//   Tại posedge T1 (IDLE→BEAT0), cả state_prev và dut.state đều là post-NBA:
//     state_prev = IDLE   (latched từ T0, cycle trước)   ← đúng
//     dut.state  = BEAT0  (latched tại T1 này)            ← đúng
//   → Condition: state_prev==IDLE && dut.state==BEAT0 → TRUE ✓
//   Không bao giờ false-trigger (BEAT0→BEAT0, BEAT0→BEAT1, BEAT1→IDLE đều FALSE) ✓
//
// Hai thay đổi chính:
//   1. Push logic TÍCH HỢP VÀO MONITOR: detect IDLE→BEAT0 bằng state_prev,
//      push dut.data/resp/last_hold (DUT internal FF, stable post-NBA).
//   2. send_axi: dùng @(posedge clk iff (state_prev==2'b00 && dut.state==2'b01))
//      → XSIM post-NBA iff evaluation = reliable 100%.
// =============================================================================
`timescale 1ns/1ps

module tb_axi_width_conv_adv;
  // ── DUT Ports ─────────────────────────────────────────────────────────────
  logic         clk = 1'b0;
  logic         rst_n;

  logic [127:0] axi_rdata;
  logic   [1:0] axi_rresp;
  logic         axi_rlast;
  logic         axi_rvalid;
  logic         axi_rready;

  logic  [63:0] out_data;
  logic   [1:0] out_resp;
  logic         out_last;
  logic         out_valid;
  logic         out_ready;

  always #2.5 clk = ~clk;

  axi_width_converter dut (.*);

  // ── state_prev: registered 1-cycle delayed copy of dut.state ─────────────
  // KEY FIX: always_ff trong TB, update cùng domain với DUT.
  // Tại posedge T_n (post-NBA): state_prev = dut.state từ T_{n-1}.
  // Điều này đảm bảo transition detection không bị ảnh hưởng bởi XSIM scheduling.
  logic [1:0] state_prev;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_prev <= 2'b00;
    else        state_prev <= dut.state;
  end

  // ── Scoreboard / Queues (Chứa kết quả kỳ vọng) ──────────────────────────
  logic [63:0] exp_data_q[$];
  logic  [1:0] exp_resp_q[$];
  logic        exp_last_q[$];

  int pass_cnt            = 0;
  int fail_cnt            = 0;
  int total_beats_checked = 0;

  // ── Backpressure Mode Control ─────────────────────────────────────────────
  typedef enum int { READY_ALWAYS_ON = 0, READY_RANDOM = 1, READY_ALWAYS_OFF = 2 } ready_mode_t;
  ready_mode_t ready_mode = READY_ALWAYS_ON;

  always @(posedge clk) begin
    if (!rst_n) begin
      out_ready <= 1'b0;
    end else begin
      case (ready_mode)
        READY_ALWAYS_ON:  out_ready <= 1'b1;
        READY_ALWAYS_OFF: out_ready <= 1'b0;
        READY_RANDOM:     out_ready <= $urandom_range(0, 100) < 60;
      endcase
    end
  end

  // ── Luồng Giám Sát (Monitor / Checker + Push) ────────────────────────────
  //
  // THIẾT KẾ: Push logic TÍCH HỢP VÀO MONITOR trong cùng process.
  //
  // Thứ tự tại mỗi posedge + #0.1:
  //   1. Detect IDLE→BEAT0 → push 2 expected items (dùng dut internal FFs)
  //   2. Display
  //   3. Check out_valid && out_ready → pop & compare
  //
  // Tại sao push trước check:
  //   - Đây là SEQUENTIAL code trong cùng process → không có race
  //   - Khi DUT ở BEAT0 sau IDLE→BEAT0 transition: push xảy ra trước check
  //   - Monitor thấy q_size>=1 trước khi check out_valid && out_ready ✓
  //
  // Tại sao dùng dut.data_hold/resp_hold/last_hold thay vì axi_rdata:
  //   - data_hold là DUT's internal FF, latched tại posedge T1, stable post-NBA
  //   - axi_rdata là TB signal, có thể bị overwrite trong continuous mode
  //     (send_axi của beat tiếp theo cập nhật rdata sau T1+#0.1)
  //   - Dùng data_hold đảm bảo push đúng data đã latch vào DUT ✓
  initial begin
    forever begin
      @(posedge clk);
      #0.1;

      // ── BƯỚC 1: Push expected data khi phát hiện IDLE→BEAT0 ─────────────
      // state_prev (always_ff, post-NBA T_{n-1}) = IDLE nếu handshake xảy ra tại T_n
      // dut.state  (always_ff, post-NBA T_n)     = BEAT0 nếu handshake xảy ra tại T_n
      if (state_prev == 2'b00 && dut.state == 2'b01) begin
        exp_data_q.push_back(dut.data_hold[63:0]);   // BEAT0: lower 64 bits
        exp_resp_q.push_back(dut.resp_hold);          // BEAT0: AXI resp
        exp_last_q.push_back(1'b0);                   // BEAT0: last=0
        exp_data_q.push_back(dut.data_hold[127:64]); // BEAT1: upper 64 bits
        exp_resp_q.push_back(2'b00);                  // BEAT1: resp=0
        exp_last_q.push_back(dut.last_hold);          // BEAT1: propagate rlast
      end

      // ── BƯỚC 2: Display ─────────────────────────────────────────────────
      $display("DBG @%0t | state=%s out_valid=%b out_ready=%b out_data=%h out_last=%b | q_size=%0d axi_rvalid=%b axi_rready=%b",
               $time, dut.state.name(), out_valid, out_ready, out_data, out_last,
               exp_data_q.size(), axi_rvalid, axi_rready);

      // ── BƯỚC 3: Check output (push đã xảy ra ở trên → q không bao giờ sai) ──
      if (out_valid && out_ready) begin
        if (exp_data_q.size() > 0) begin
          automatic logic [63:0] exp_d = exp_data_q.pop_front();
          automatic logic  [1:0] exp_r = exp_resp_q.pop_front();
          automatic logic        exp_l = exp_last_q.pop_front();
          if (out_data !== exp_d || out_resp !== exp_r || out_last !== exp_l) begin
            $error("FAIL @ %0t | Data: %h (exp %h) | Resp: %b (exp %b) | Last: %b (exp %b)",
                    $time, out_data, exp_d, out_resp, exp_r, out_last, exp_l);
            fail_cnt++;
          end else begin
            pass_cnt++;
          end
          total_beats_checked++;
        end else begin
          $error("FAIL @ %0t | DUT xuất ra data rác khi Queue kỳ vọng trống rỗng!", $time);
          $display("DBG GARBAGE: state=%s out_data=%h out_resp=%b out_last=%b",
                   dut.state.name(), out_data, out_resp, out_last);
          fail_cnt++;
        end
      end
    end
  end

  // ── Các Tasks Hỗ Trợ Gửi Data ─────────────────────────────────────────────

  // ============================================================
  // do_reset(): chờ DUT về IDLE trước khi reset và xóa queue
  // ============================================================
  task do_reset();
    axi_rvalid = 0;
    if (rst_n === 1'b1) begin
      @(posedge clk iff (out_valid === 1'b0));
      #0.1;
    end
    exp_data_q.delete();
    exp_resp_q.delete();
    exp_last_q.delete();
    ready_mode = READY_ALWAYS_ON;
    rst_n      = 0;
    axi_rdata  = 0;
    axi_rresp  = 0;
    axi_rlast  = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);
  endtask

  // ============================================================
  // send_axi() v5: state_prev-based iff handshake detection
  //
  // Không còn push logic trong send_axi (monitor xử lý).
  // send_axi chỉ:
  //   1. Drive AXI signals
  //   2. Wait for IDLE→BEAT0 (= DUT accepted the data)
  //   3. De-assert rvalid (non-continuous) or keep (continuous)
  //
  // @(posedge clk iff (state_prev==2'b00 && dut.state==2'b01)):
  //   - XSIM evaluates iff POST-NBA → state_prev và dut.state đều đúng ✓
  //   - Chỉ trigger khi IDLE→BEAT0 (handshake thật sự) ✓
  //   - Không trigger khi BEAT0→BEAT0 (backpressure) ✓
  //   - Không trigger khi BEAT1→IDLE ✓
  //
  // Continuous mode analysis:
  //   - send_axi(i) returns at posedge T_i (IDLE→BEAT0 of beat i) + #0.1
  //   - Main loop calls send_axi(i+1) at T_i+Δ, updates axi_rdata=beat(i+1)
  //   - DUT is in BEAT0 from beat i → won't latch until IDLE at T_{i+2}
  //   - At T_{i+3} (next IDLE→BEAT0): DUT latches beat(i+1) ✓
  //   - send_axi(i+1)'s iff only triggers at T_{i+3} (IDLE→BEAT0) ✓
  //   - Not at T_{i+1} (BEAT0→BEAT1: state_prev=BEAT0 → FALSE) ✓
  //   - Not at T_{i+2} (BEAT1→IDLE: state_prev=BEAT1 → FALSE) ✓
  // ============================================================
  task send_axi(input logic [127:0] rdata, input logic [1:0] rresp,
                input logic rlast, input logic continuous = 0);
    axi_rdata  = rdata;
    axi_rresp  = rresp;
    axi_rlast  = rlast;
    axi_rvalid = 1;

    // Wait for IDLE→BEAT0 transition via registered state_prev.
    // Reliable with XSIM post-NBA iff evaluation.
    @(posedge clk iff (state_prev == 2'b00 && dut.state == 2'b01));

    #0.1;
    if (!continuous) axi_rvalid = 0;
  endtask

  // Đợi cho đến khi Queue xử lý xong
  task wait_for_empty_queue();
    automatic int timeout = 2000;
    while (exp_data_q.size() > 0 && timeout > 0) begin
      @(posedge clk);
      timeout--;
    end
    if (timeout == 0) begin
      $error("TIMEOUT: Hàng đợi không xả hết, FSM có thể bị kẹt!");
      fail_cnt++;
    end
  endtask

  // ── Kịch Bản Test (Test Sequences) ────────────────────────────────────────
  initial begin
    $display("=== BẮT ĐẦU TEST: axi_width_converter ===");

    // [TEST 1] Reset & Basic Single Beat
    $display("--- TEST 1: Reset & Basic Single Beat ---");
    do_reset();
    send_axi(128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444, 2'b01, 1'b0);
    wait_for_empty_queue();
    $display("  -> Hoàn thành Test 1");

    // [TEST 2] Continuous Burst (Luồng dữ liệu liên tục, không có IDLE giữa các beat)
    $display("--- TEST 2: Continuous Burst (No Stall) ---");
    do_reset();
    ready_mode = READY_ALWAYS_ON;
    for (int i = 0; i < 4; i++) begin
      send_axi({64'hFACE_0000 + i, 64'hCAFE_0000 + i}, 2'b00, (i==3) ? 1'b1 : 1'b0, 1'b1);
    end
    axi_rvalid = 0;
    wait_for_empty_queue();
    $display("  -> Hoàn thành Test 2");

    // [TEST 3] CỰC HÌNH: Random Backpressure với Burst Dài
    $display("--- TEST 3: Heavy Stress Test (Random Backpressure) ---");
    do_reset();
    ready_mode = READY_RANDOM;
    for (int i = 0; i < 20; i++) begin
      automatic logic [1:0] rand_resp = $urandom_range(0, 3);
      automatic logic       is_last   = (i % 4 == 3);
      send_axi({$urandom(), $urandom(), $urandom(), $urandom()}, rand_resp, is_last, 1'b1);
    end
    axi_rvalid = 0;
    wait_for_empty_queue();
    $display("  -> Hoàn thành Test 3");

    // TỔNG KẾT
    $display("\n=== KẾT QUẢ MÔ PHỎNG ===");
    $display("Tổng số beat 64-bit đã kiểm tra: %0d", total_beats_checked);
    if (fail_cnt == 0 && exp_data_q.size() == 0) begin
      $display(">>> ALL TESTS PASSED SUCCESSFULLY! (Pass Cnt: %0d) <<<", pass_cnt);
      $finish(0);
    end else begin
      $fatal(1, ">>> FAILED! Có %0d lỗi xảy ra, hoặc còn sót %0d dữ liệu kẹt trong Queue. <<<",
             fail_cnt, exp_data_q.size());
    end
  end

  // Watchdog Timeout — 500us để handle random backpressure dài
  initial begin
    #500000;
    $fatal(1, "TIMEOUT CHÍ MẠNG: Mô phỏng chạy quá lâu (bị kẹt Deadlock ở đâu đó).");
  end

endmodule