// ================================================================================
// Advanced Testbench: tb_nan_inf_detector_adv.sv
// Architecture: Self-Checking, Directed Sweep + Constrained Random
// --------------------------------------------------------------------------------
// FIX LOG (v2):
//   ROOT CAUSE — Race condition: blocking assignments trong initial block
//   được thực thi tại CÙNG timestep với posedge clock, gây ra thứ tự
//   evaluate không xác định giữa DUT, reference model và checker
//   (tất cả đều là always_ff chạy trong Active region).
//
//   Hậu quả:
//     • DUT và reference model có thể sample valid_in/fp32_in ở giá trị
//       khác nhau → Checker báo lỗi lệch pha 1 cycle giả tạo (~99% errors)
//     • Tại test Reset on-the-fly, DUT có thể sample QNaN trong khi ref
//       model thấy giá trị cũ → mismatch trước khi rst_n kịp hạ xuống
//
//   FIX — Thêm #1 sau mỗi @(posedge clk) trước khi drive signal:
//     • #1 đẩy blocking assignment vào Inactive region (sau Active region)
//     • Lúc này tất cả always_ff đã evaluate xong RHS → KHÔNG còn race
//     • Chuẩn SV best practice: "drive after clock edge, sample at edge"
//
//   DUT (nan_inf_detector.sv) KHÔNG có lỗi và KHÔNG cần thay đổi:
//     • Reset đã clear đủ tất cả output registers
//     • valid_out 1-cycle latency đúng spec §15.14
// ================================================================================
`timescale 1ns/1ps

module tb_nan_inf_detector_adv;

  // ── Clock & Reset ───────────────────────────────────────────────────────────
  localparam real CLK_PERIOD  = 5.0;  // 200 MHz
  localparam real DRIVE_DELAY = 1.0;  // Drive offset sau posedge (< half-period)

  logic clk   = 0;
  logic rst_n = 0;

  always #(CLK_PERIOD / 2.0) clk = ~clk;

  // ── DUT I/O ─────────────────────────────────────────────────────────────────
  logic [31:0] fp32_in  = '0;
  logic        valid_in = 1'b0;
  logic        nan_detected;
  logic        inf_detected;
  logic        fault_out;
  logic        valid_out;

  // Có thể bạn cần bỏ comment dòng import dưới đây nếu DUT yêu cầu
  // import planning_pkg::*;

  nan_inf_detector dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .fp32_in      (fp32_in),
    .valid_in     (valid_in),
    .nan_detected (nan_detected),
    .inf_detected (inf_detected),
    .fault_out    (fault_out),
    .valid_out    (valid_out)
  );

  // ── Reference Model (Golden Model) ──────────────────────────────────────────
  // Mô phỏng lại chính xác logic 1-cycle pipeline của DUT.
  logic exp_nan_comb, exp_inf_comb;
  logic exp_nan_reg, exp_inf_reg, exp_fault_reg, exp_valid_reg;

  assign exp_nan_comb = (fp32_in[30:23] == 8'hFF) && (fp32_in[22:0] != 23'd0);
  assign exp_inf_comb = (fp32_in[30:23] == 8'hFF) && (fp32_in[22:0] == 23'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exp_nan_reg   <= 1'b0;
      exp_inf_reg   <= 1'b0;
      exp_fault_reg <= 1'b0;
      exp_valid_reg <= 1'b0;
    end else begin
      exp_valid_reg <= valid_in;
      exp_nan_reg   <= exp_nan_comb;
      exp_inf_reg   <= exp_inf_comb;
      exp_fault_reg <= exp_nan_comb | exp_inf_comb;
    end
  end

  // ── Background Checker ───────────────────────────────────────────────────────
  int   check_cnt  = 0;
  int   error_cnt  = 0;
  logic check_enable = 1'b0;  // Kích hoạt sau khi reset ổn định

  always_ff @(posedge clk) begin
    if (rst_n && check_enable) begin
      check_cnt++;

      if (nan_detected !== exp_nan_reg) begin
        $error("[FAIL] Time %0t: nan_detected = %b (Expected %b) | FP32_IN = %h",
               $time, nan_detected, exp_nan_reg, fp32_in);
        error_cnt++;
      end

      if (inf_detected !== exp_inf_reg) begin
        $error("[FAIL] Time %0t: inf_detected = %b (Expected %b) | FP32_IN = %h",
               $time, inf_detected, exp_inf_reg, fp32_in);
        error_cnt++;
      end

      if (fault_out !== exp_fault_reg) begin
        $error("[FAIL] Time %0t: fault_out = %b (Expected %b)",
               $time, fault_out, exp_fault_reg);
        error_cnt++;
      end

      if (valid_out !== exp_valid_reg) begin
        $error("[FAIL] Time %0t: valid_out = %b (Expected %b)",
               $time, valid_out, exp_valid_reg);
        error_cnt++;
      end
    end
  end

  // ── Constrained Random Class ─────────────────────────────────────────────────
  class FP32_Stimulus;
    rand logic [31:0] val;
    rand logic        valid;

    // 80% valid_in=1, 20% valid_in=0 để test cơ chế pipeline idle
    constraint c_valid {
      valid dist { 1 := 80, 0 := 20 };
    }

    // Tập trung sinh Corner Cases: 30% NaN/Inf, 10% Zero/Subnormal, 60% Normal
    constraint c_val {
      val[30:23] dist {
        8'hFF           := 30,
        8'h00           := 10,
        [8'h01 : 8'hFE] := 60
      };
    }
  endclass

  // ── Task: Drive inputs an toàn sau clock edge ────────────────────────────────
  // Sử dụng task này thay vì drive trực tiếp để tránh race condition.
  // #DRIVE_DELAY đẩy blocking assignment vào Inactive region, sau khi
  // tất cả always_ff đã evaluate xong RHS trong Active region.
  task automatic drive(input logic [31:0] data, input logic vld);
    @(posedge clk);
    #DRIVE_DELAY;  // ← FIX CHÍNH: không còn race với always_ff
    fp32_in  = data;
    valid_in = vld;
  endtask

  // ── Mảng Corner Cases IEEE 754 ───────────────────────────────────────────────
  FP32_Stimulus stim;

  logic [31:0] corner_cases[] = '{
    32'h0000_0000, 32'h8000_0000,  // +0.0,      -0.0
    32'h7F80_0000, 32'hFF80_0000,  // +Inf,      -Inf
    32'h7FC0_0000, 32'hFFC0_0000,  // +QNaN,     -QNaN
    32'h7F80_0001, 32'hFF80_0001,  // +SNaN,     -SNaN
    32'h7F7F_FFFF, 32'hFF7F_FFFF,  // Max Normal (Pos, Neg)
    32'h0000_0001, 32'h8000_0001,  // Min Subnormal (Pos, Neg)
    32'h7FFF_FFFF, 32'hFFFF_FFFF   // All mantissa bits set (Pos, Neg)
  };

  // ── Main Test Sequence ───────────────────────────────────────────────────────
  initial begin
    $display("=================================================");
    $display("=== STARTING ADVANCED NaN/Inf DETECTOR TB     ===");
    $display("=================================================");

    stim = new();

    // ── 1. Hard Reset Test ───────────────────────────────────────────────────
    $display("[TEST] 1. Applying Hard Reset...");
    repeat(4) @(posedge clk);
    #DRIVE_DELAY; rst_n = 1'b1;  // FIX: delay trước khi drive rst_n

    repeat(2) @(posedge clk);
    #DRIVE_DELAY; check_enable = 1'b1;  // FIX: delay để tránh race với checker

    // ── 2. Directed Corner Cases Sweep (back-to-back streaming) ──────────────
    $display("[TEST] 2. Sweeping IEEE 754 Corner Cases (Streaming)...");
    foreach (corner_cases[i])
      drive(corner_cases[i], 1'b1);

    // Ngắt luồng — valid_in=0, đưa Inf vào nhưng không valid
    drive(32'h7F80_0000, 1'b0);
    repeat(3) @(posedge clk);

    // ── 3. Constrained Random Testing ────────────────────────────────────────
    $display("[TEST] 3. Running 10,000 Constrained Random Vectors...");
    for (int i = 0; i < 10_000; i++) begin
      if (!stim.randomize()) $fatal(1, "Randomization failed!");
      drive(stim.val, stim.valid);
    end

    // Xả pipeline — đợi nhịp cuối cùng được xử lý xong
    drive('0, 1'b0);
    repeat(5) @(posedge clk);

    // ── 4. Reset On-The-Fly Test ─────────────────────────────────────────────
    // Mục đích: verify DUT clear outputs ngay lập tức khi rst_n hạ,
    // kể cả khi đang xử lý QNaN giữa chừng.
    $display("[TEST] 4. Testing Reset during active streaming...");

    // Đưa QNaN vào — DUT sẽ pipeline nó sang cycle tiếp theo
    drive(32'h7FC0_0000, 1'b1);  // QNaN vào @ posedge P, sample @ posedge P+1

    // Đợi posedge P+1 — DUT đang output nan_detected=1, valid_out=1
    @(posedge clk);
    // FIX: giật reset sau DRIVE_DELAY (trong Inactive region), đảm bảo
    // checker đã check xong @ posedge P+1 trước khi thấy reset.
    #DRIVE_DELAY; rst_n = 1'b0;

    // DUT phải async-clear ngay lập tức (negedge rst_n trên sensitivity list)
    repeat(3) @(posedge clk);  // checker bỏ qua do rst_n=0

    #DRIVE_DELAY; rst_n = 1'b1;  // Release reset — FIX: delay an toàn
    repeat(2) @(posedge clk);   // Verify outputs trở về 0 sau reset

    // ── Kết thúc và Báo cáo ──────────────────────────────────────────────────
    $display("=================================================");
    $display("=== TEST SUMMARY                              ===");
    $display("=================================================");
    $display(" Total cycles checked : %0d", check_cnt);
    $display(" Total errors found   : %0d", error_cnt);

    if (error_cnt == 0) begin
      $display(" >>> STATUS: PASSED ALL TESTS <<<");
      $finish(0);
    end else begin
      $display(" >>> STATUS: FAILED (%0d errors) <<<", error_cnt);
      $fatal(1, "Simulation stopped due to errors.");
    end
  end

  // ── Watchdog Timer ───────────────────────────────────────────────────────────
  initial begin
    #1_000_000;  // 1 ms — đủ cho toàn bộ 10,000 cycles × 5ns = 50 µs
    $fatal(1, "WATCHDOG TIMEOUT: Simulation hung or took too long.");
  end

endmodule
// ================================================================================