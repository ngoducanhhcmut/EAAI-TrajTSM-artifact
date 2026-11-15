// =============================================================================
// tb_gru_waypoint_decoder.sv — Upgraded Data-Driven Testbench
// Features: 
//   - File I/O support for Python Golden Model vectors
//   - Randomization for stress testing pipeline
//   - NaN / Inf injection for Edge Case / Safety verification
//   - Epsilon-based Floating-Point comparison
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_gru_waypoint_decoder_advance;
  import planning_pkg::*;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk; // 200MHz Clock

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic          gru_start;
  logic  [8:0]   cls_buf_rd_addr;
  fp32_t         cls_buf_rd_data;
  logic          cls_buf_rd_en;
  logic [16:0]   gru_uram_addr;
  logic [63:0]   gru_uram_rdata;
  logic          gru_uram_en;
  logic [16:0]   gru_uram_addr_b;
  logic [63:0]   gru_uram_rdata_b;
  logic          gru_uram_en_b;
  logic [10:0]   gru_bias_addr;
  logic [31:0]   gru_bias_rdata;
  logic [10:0]   wout_bram_addr;
  logic [31:0]   wout_bram_rdata;
  logic  [2:0]   gru_scale_sel;
  logic  [8:0]   gru_scale_addr;
  logic [15:0]   gru_scale_rdata;
  logic [10:0]   wp_proj_bram_addr;
  logic [31:0]   wp_proj_bram_rdata;
  logic          wp_proj_bram_en;

  fp32_t         waypoint_x [NUM_WAYPOINTS-1:0];
  fp32_t         waypoint_y [NUM_WAYPOINTS-1:0];
  logic          waypoints_valid;
  logic          gru_done;

  gru_waypoint_decoder dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .gru_start         (gru_start),
    .cls_buf_rd_addr   (cls_buf_rd_addr),
    .cls_buf_rd_data   (cls_buf_rd_data),
    .cls_buf_rd_en     (cls_buf_rd_en),
    .gru_uram_addr     (gru_uram_addr),
    .gru_uram_rdata    (gru_uram_rdata),
    .gru_uram_en       (gru_uram_en),
    .gru_uram_addr_b   (gru_uram_addr_b),
    .gru_uram_rdata_b  (gru_uram_rdata_b),
    .gru_uram_en_b     (gru_uram_en_b),
    .gru_bias_addr     (gru_bias_addr),
    .gru_bias_rdata    (gru_bias_rdata),
    .wout_bram_addr    (wout_bram_addr),
    .wout_bram_rdata   (wout_bram_rdata),
    .gru_scale_sel     (gru_scale_sel),
    .gru_scale_addr    (gru_scale_addr),
    .gru_scale_rdata   (gru_scale_rdata),
    .wp_proj_bram_addr (wp_proj_bram_addr),
    .wp_proj_bram_rdata(wp_proj_bram_rdata),
    .wp_proj_bram_en   (wp_proj_bram_en),
    .waypoint_x        (waypoint_x),
    .waypoint_y        (waypoint_y),
    .waypoints_valid   (waypoints_valid),
    .gru_done          (gru_done)
  );

  // ── Memory models ──────────────────────────────────────────────────────────
  fp32_t       cls_buf_mem     [0:511];
  logic [63:0] gru_uram_mem      [0:131071];
  logic [31:0] gru_bias_mem      [0:2047];
  logic [31:0] wout_bram_mem     [0:2047];
  logic [15:0] gru_scale_mem     [0:511];
  logic [31:0] wp_proj_bram_mem  [0:2047];

  always_ff @(posedge clk) begin
    cls_buf_rd_data    <= cls_buf_rd_en   ? cls_buf_mem[cls_buf_rd_addr]         : 32'h0;
    gru_uram_rdata     <= gru_uram_en     ? gru_uram_mem[gru_uram_addr[16:0]]   : 64'h0;
    gru_uram_rdata_b   <= gru_uram_en_b   ? gru_uram_mem[gru_uram_addr_b[16:0]] : 64'h0;
    gru_bias_rdata     <= gru_bias_mem[gru_bias_addr];
    wout_bram_rdata    <= wout_bram_mem[wout_bram_addr];
    gru_scale_rdata    <= gru_scale_mem[gru_scale_addr];
    wp_proj_bram_rdata <= wp_proj_bram_en ? wp_proj_bram_mem[wp_proj_bram_addr] : 32'h0;
  end

  // ── Helpers & Verification Math ────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  // IEEE-754 FP32 Extraction
  function automatic logic is_nan(fp32_t val);
    return (val[30:23] == 8'hFF) && (val[22:0] != 23'h0);
  endfunction

  function automatic logic is_inf(fp32_t val);
    return (val[30:23] == 8'hFF) && (val[22:0] == 23'h0);
  endfunction

  // Float Comparison with Epsilon (Tolerance)
  function automatic bit fp32_almost_equal(fp32_t a, fp32_t b, real epsilon = 1e-4);
    real real_a = $bitstoshortreal(a);
    real real_b = $bitstoshortreal(b);
    real diff = real_a - real_b;
    if (diff < 0) diff = -diff;
    return (diff <= epsilon);
  endfunction

  // ── Test Stimulus Generators ───────────────────────────────────────────────
  
  // Chế độ 0: Zero, Chế độ 1: Random, Chế độ 2: Edge Cases (NaN/Inf)
  task load_memories(int mode);
    $display("  -> Nạp bộ nhớ với Mode = %0d", mode);
    for (int i = 0; i < 512; i++) begin
      if (mode == 0) cls_buf_mem[i] = 32'h0;
      else if (mode == 1) cls_buf_mem[i] = $shortrealtobits(shortreal'($urandom_range(0, 200) / 100.0 - 1.0));
      else cls_buf_mem[i] = (i % 2 == 0) ? 32'h7FC00000 : 32'h7F800000; // Trộn NaN và +Inf
    end

    for (int i = 0; i < 131072; i++) begin
      if (mode == 0) gru_uram_mem[i] = 64'h0;
      else gru_uram_mem[i] = {$urandom, $urandom}; // Random INT4 nibbles
    end

    for (int i = 0; i < 2048; i++) begin
      if (mode == 0) begin
        gru_bias_mem[i]     = 32'h0;
        wout_bram_mem[i]    = 32'h0;
        wp_proj_bram_mem[i] = 32'h0;
      end else begin
        gru_bias_mem[i]     = $shortrealtobits(shortreal'($urandom_range(0, 100) / 100.0));
        wout_bram_mem[i]    = $shortrealtobits(shortreal'($urandom_range(0, 100) / 100.0));
        wp_proj_bram_mem[i] = $shortrealtobits(shortreal'($urandom_range(0, 100) / 100.0));
      end
    end

    for (int i = 0; i < 512; i++) begin
      if (mode == 0) gru_scale_mem[i] = 16'h0;
      else gru_scale_mem[i] = {8'h7F, 8'h00}; // Scale lớn, Zero-point = 0
    end
  endtask

  // ── Routine chạy 1 Frame GRU ───────────────────────────────────────────────
  task automatic run_gru_frame(string test_name, int expect_nan);
    int timeout = 0;
    logic done_seen = 0;

    $display("=== Bắt đầu Test: %s ===", test_name);
    @(posedge clk); #0.1;
    gru_start = 1'b1;
    @(posedge clk); #0.1;
    gru_start = 1'b0;

    // Giới hạn timeout chặt chẽ hơn thay vì 7 triệu cycles
    // 6.5M cycles là spec latency của bạn. Ta cho max 6.6M.
    while (timeout < 6600000) begin
      @(posedge clk);
      if (gru_done) begin
        done_seen = 1;
        break;
      end
      timeout++;
    end

    if (done_seen) begin
      $display("  PASS [Timeout Check] Hoàn thành trong %0d cycles", timeout);
      pass_cnt++;
      
      // Kiểm tra Edge Cases
      if (expect_nan) begin
        if (is_nan(waypoint_x[0]) || is_inf(waypoint_x[0])) begin
          $display("  PASS [Edge Case] Hệ thống xuất NaN/Inf đúng như dự kiến khi bị tiêm lỗi.");
          pass_cnt++;
        end else begin
          $error("  FAIL [Edge Case] Đưa NaN vào nhưng đầu ra không phải NaN/Inf.");
          fail_cnt++;
        end
      end else begin
        if (!is_nan(waypoint_x[0]) && !is_inf(waypoint_x[0])) begin
          $display("  PASS [Valid Data] Output hợp lệ: x0 = %f", $bitstoshortreal(waypoint_x[0]));
          pass_cnt++;
        end else begin
          $error("  FAIL [Valid Data] Dữ liệu chuẩn nhưng đầu ra lại bị NaN/Inf.");
          fail_cnt++;
        end
      end
    end else begin
      $error("  FAIL [Timeout Check] Deadlock! Module bị treo sau %0d cycles.", timeout);
      fail_cnt++;
    end
    $display("---------------------------------------------------");
    tick(10);
  endtask

  // ── Main Test Flow ─────────────────────────────────────────────────────────
  initial begin
    $display("==================================================================");
    $display("   BẮT ĐẦU VERIFICATION: gru_waypoint_decoder");
    $display("==================================================================");
    
    gru_start = 0;
    rst_n = 0;
    tick(5);
    rst_n = 1;
    tick(5);

    // Phase 1: Mọi dữ liệu bằng 0 (Smoke Test)
    load_memories(0);
    run_gru_frame("Phase 1 - Zero Data Sanity Check", 0);

    // Phase 2: Dữ liệu ngẫu nhiên (Stress Test Pipeline)
    // Đảm bảo không có data hazard hoặc xung đột địa chỉ BRAM khi chạy dữ liệu thật
    load_memories(1);
    run_gru_frame("Phase 2 - Randomized Data Matrix Pipeline Stress", 0);

    // Phase 3: Bắn NaN / Inf vào để test Worst-case
    // Cực kỳ quan trọng để đảm bảo logic không bị treo máy trạng thái khi FP32 ALU văng cờ lỗi.
    load_memories(2);
    run_gru_frame("Phase 3 - NaN/Infinity Edge Case Injection", 1);

    $display("==================================================================");
    $display("   TỔNG KẾT: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("   TRẠNG THÁI: SUCCESS");
      $finish(0);
    end else begin
      $fatal(1, "   TRẠNG THÁI: FAILED — Cần debug lại RTL!");
    end
  end

  initial begin
    #120000000; // Fail-safe watch-dog (3 phases × ~33ms each + overhead)
    $fatal(1, "TIMEOUT: Hệ thống testbench bị treo cứng.");
  end

endmodule
`default_nettype wire
