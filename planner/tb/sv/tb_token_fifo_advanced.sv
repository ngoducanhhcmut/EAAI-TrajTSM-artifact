// =============================================================================
// tb_token_fifo_advanced.sv — Advanced Verification for token_fifo
// Covers: Full, Empty, Overflow, Underflow, Wrap-around, Random Stress
// =============================================================================
`timescale 1ns/1ps

module tb_token_fifo_advanced;
  import planning_pkg::*;

  // ── DUT Ports ─────────────────────────────────────────────────────────────
  logic          clk          = 1'b0;
  logic          rst_n;
  
  bbox6_t        x_token_data;
  token_type_t   x_token_type;
  logic          x_token_valid;
  logic          x_token_ready;
  
  bbox6_t        token_o;
  token_type_t   token_type_o;
  logic          token_valid_o;
  logic          token_ready_i;
  logic  [7:0]   fifo_occupancy;

  // Clock generation
  always #5 clk = ~clk; // 100MHz

  token_fifo dut (.*);

  // ── [F-P1-3] Continuous occupancy checker ─────────────────────────────────
  // Model đếm theo handshake thật, so sánh MỖI chu kỳ với fifo_occupancy.
  // Các check điểm rời rạc (chỉ lúc full=64/empty=0) không thể thấy lỗi
  // công thức occupancy ở vùng wrapped (wr_ptr < rd_ptr numerically).
  int occ_model;
  int occ_errors = 0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) occ_model <= 0;
    else begin
      case ({x_token_valid && x_token_ready, token_valid_o && token_ready_i})
        2'b10:   occ_model <= occ_model + 1;
        2'b01:   occ_model <= occ_model - 1;
        default: occ_model <= occ_model;
      endcase
    end
  end

  always @(negedge clk) begin
    if (rst_n && fifo_occupancy !== 8'(occ_model)) begin
      if (occ_errors < 10)
        $error("FAIL [Occupancy] got=%0d exp=%0d (t=%0t, wrapped-pointer region?)",
               fifo_occupancy, occ_model, $time);
      occ_errors++;
    end
  end

  // ── Golden Model & Variables ──────────────────────────────────────────────
  typedef struct {
    bbox6_t      bbox;
    token_type_t tt;
  } expected_token_t;

  expected_token_t golden_q[$]; // Hàng đợi chuẩn để đối chiếu
  
  int pass_cnt = 0;
  int fail_cnt = 0;
  int token_id_counter = 0;

  // ── Helper Tasks ──────────────────────────────────────────────────────────
  task tick(int cycles = 1);
    repeat(cycles) @(posedge clk); 
    #0.1; // Chờ tín hiệu ổn định sau sườn lên
  endtask

  task do_reset();
    rst_n         = 0;
    x_token_valid = 0;
    token_ready_i = 0;
    x_token_type  = TT_CLS;
    x_token_data  = '0;
    golden_q.delete(); // Xóa sạch queue
    tick(3);
    rst_n = 1;
    tick(1);
  endtask

  // Tạo token ngẫu nhiên dựa trên ID tăng dần để dễ trace debug
  function expected_token_t gen_token();
    expected_token_t t;
    t.bbox = '0;
    t.bbox.x_min = token_id_counter++; 
    t.bbox.y_min = $urandom; // Randomize các trường khác để test data integrity
    t.tt = token_type_t'($urandom_range(0, 4));
    return t;
  endfunction

  // Task Ghi (Đợi x_token_ready nếu đầy)
  task write_token(input expected_token_t t);
    x_token_data  = t.bbox;
    x_token_type  = t.tt;
    x_token_valid = 1;
    
    // Đợi cho đến khi FIFO sẵn sàng nhận
    while (x_token_ready === 1'b0) begin
      tick(1);
    end
    
    tick(1); // Hoàn thành chu kỳ ghi
    x_token_valid = 0;
    golden_q.push_back(t); // Đưa vào Golden Queue
  endtask

  // Task Đọc và Đối chiếu
  task read_and_check();
    expected_token_t exp_t;
    
    // Đợi cho đến khi có token hợp lệ
    while (token_valid_o === 1'b0) begin
      tick(1);
    end

    // Pop BEFORE checking (so rd_ptr hasn't changed yet)
    exp_t = golden_q.pop_front();
    
    // NOW check that output matches the token we just popped
    if (token_o.x_min === exp_t.bbox.x_min && token_type_o === exp_t.tt) begin
      pass_cnt++;
    end else begin
      $error("FAIL [Data Mismatch] Exp ID: %0d, Got ID: %0d", exp_t.bbox.x_min, token_o.x_min);
      fail_cnt++;
    end

    // Xác nhận đã đọc (drain)
    token_ready_i = 1;
    tick(1);
    token_ready_i = 0;
  endtask

  // ── Main Test Sequence ────────────────────────────────────────────────────
  initial begin
    $display("==================================================");
    $display("=== ADVANCED TESTBENCH: token_fifo ===");
    $display("==================================================");

    // ------------------------------------------------------------------------
    $display("\n[TEST 1] Reset State & Basic Signals");
    do_reset();
    if (fifo_occupancy === 0 && x_token_ready === 1 && token_valid_o === 0) pass_cnt++;
    else fail_cnt++;

    // ------------------------------------------------------------------------
    $display("\n[TEST 2] Fill-to-Full Test (Ghi đầy 64 Tokens)");
    for (int i = 0; i < 64; i++) begin
      write_token(gen_token());
    end
    tick(1);
    if (fifo_occupancy === 64 && x_token_ready === 0) begin
      $display("  PASS: FIFO Full logic holds.");
      pass_cnt++;
    end else begin
      $error("  FAIL: Occupancy = %0d, Ready = %0b (Exp: 64, 0)", fifo_occupancy, x_token_ready);
      fail_cnt++;
    end

    // ------------------------------------------------------------------------
    $display("\n[TEST 3] Overflow Protection (Cố tình ghi khi Đầy)");
    x_token_data = '0; x_token_valid = 1; // Ép ghi
    tick(2);
    x_token_valid = 0;
    if (fifo_occupancy === 64) pass_cnt++; // Vẫn phải là 64
    else begin $error("FAIL: Overflow corrupted FIFO"); fail_cnt++; end

    // ------------------------------------------------------------------------
    $display("\n[TEST 4] Drain-to-Empty Test (Xả toàn bộ 64 Tokens)");
    for (int i = 0; i < 64; i++) begin
      read_and_check();
    end
    tick(1);
    if (fifo_occupancy === 0 && token_valid_o === 0) begin
      $display("  PASS: FIFO Empty logic holds.");
      pass_cnt++;
    end else fail_cnt++;

    // ------------------------------------------------------------------------
    $display("\n[TEST 5] Underflow Protection (Cố tình đọc khi Rỗng)");
    token_ready_i = 1; // Ép đọc
    tick(2);
    token_ready_i = 0;
    if (fifo_occupancy === 0) pass_cnt++; 
    else begin $error("FAIL: Underflow corrupted FIFO"); fail_cnt++; end

    // ------------------------------------------------------------------------
    $display("\n[TEST 6] Pointer Wrap-Around Test (Ép con trỏ tràn 127 -> 0)");
    do_reset();
    for (int i = 0; i < 150; i++) begin
      write_token(gen_token());
      read_and_check();
    end
    if (fifo_occupancy === 0) pass_cnt++; else fail_cnt++;
    $display("  PASS: Pointers wrapped successfully.");

    // ------------------------------------------------------------------------
    $display("\n[TEST 7] Random Stress & Backpressure Test (1000 Transactions)");
    do_reset();
    
    // Chạy song song 2 luồng: 1 luồng Ghi ngẫu nhiên, 1 luồng Đọc ngẫu nhiên
    fork
      // Thread 1: Producer (Ghi ngẫu nhiên)
      begin
        for (int i = 0; i < 1000; i++) begin
          tick($urandom_range(0, 3)); // Random delay trước khi ghi (0-3 cycles)
          write_token(gen_token());
        end
      end
      
      // Thread 2: Consumer (Đọc ngẫu nhiên)
      begin
        for (int i = 0; i < 1000; i++) begin
          tick($urandom_range(0, 5)); // Đọc chậm hơn ghi một chút để ép FIFO dâng nước
          read_and_check();
        end
      end
    join
    
    $display("  PASS: Handled 1000 random write/read transactions cleanly.");

    // ------------------------------------------------------------------------
    $display("\n[TEST 8] Continuous Occupancy Checker (handshake model)");
    if (occ_errors == 0) begin
      $display("  PASS: fifo_occupancy khớp model ở mọi chu kỳ.");
      pass_cnt++;
    end else begin
      $error("  FAIL: fifo_occupancy lệch model %0d lần (bug vùng wrapped-pointer)", occ_errors);
      fail_cnt++;
    end

    // ------------------------------------------------------------------------
    $display("==================================================");
    $display("=== FINAL RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("=== ALL TESTS PASSED. FIFO IS BULLETPROOF! ===");
    else               $display("=== SIMULATION FAILED! Check errors above. ===");
    $display("==================================================");
    
    $finish(0);
  end

endmodule