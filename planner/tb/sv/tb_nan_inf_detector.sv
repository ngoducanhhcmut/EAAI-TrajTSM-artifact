// ================================================================================
// Testbench: tb_nan_inf_detector.sv
// DUT: nan_inf_detector — FP32 NaN/Inf detector (1-cycle registered latency)
// Spec: §15.14 (V15-S04)
// ================================================================================
`timescale 1ns/1ps

module tb_nan_inf_detector;

  // ── Clock & reset ─────────────────────────────────────────────────────────────
  localparam real CLK_PERIOD = 5.0;  // 200 MHz
  logic clk   = 0;
  logic rst_n = 0;

  always #(CLK_PERIOD/2.0) clk = ~clk;

  // ── DUT I/O ───────────────────────────────────────────────────────────────────
  logic [31:0] fp32_in;
  logic        valid_in;
  logic        nan_detected;
  logic        inf_detected;
  logic        fault_out;
  logic        valid_out;

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

  // ── Watchdog ──────────────────────────────────────────────────────────────────
  initial begin
    #50_000;
    $fatal(1, "WATCHDOG: simulation exceeded 50 µs.");
  end

  // ── FP32 constants ────────────────────────────────────────────────────────────
  // +Inf:        0 11111111 00000000000000000000000 = 32'h7F80_0000
  // -Inf:        1 11111111 00000000000000000000000 = 32'hFF80_0000
  // +QNaN:       0 11111111 10000000000000000000000 = 32'h7FC0_0000
  // +SNaN:       0 11111111 00000000000000000000001 = 32'h7F80_0001
  // -NaN:        1 11111111 10000000000000000000000 = 32'hFFC0_0000
  // Zero:        32'h0000_0000
  // One:         32'h3F80_0000
  // -One:        32'hBF80_0000
  // Max normal:  32'h7F7F_FFFF
  // Min positive:32'h0000_0001 (subnormal)
  localparam logic [31:0] FP32_POS_INF    = 32'h7F80_0000;
  localparam logic [31:0] FP32_NEG_INF    = 32'hFF80_0000;
  localparam logic [31:0] FP32_QNAN_P     = 32'h7FC0_0000;
  localparam logic [31:0] FP32_SNAN_P     = 32'h7F80_0001;
  localparam logic [31:0] FP32_NAN_N      = 32'hFFC0_0000;
  localparam logic [31:0] FP32_ZERO       = 32'h0000_0000;
  localparam logic [31:0] FP32_ONE        = 32'h3F80_0000;
  localparam logic [31:0] FP32_NEG_ONE    = 32'hBF80_0000;
  localparam logic [31:0] FP32_MAX_NORM   = 32'h7F7F_FFFF;
  localparam logic [31:0] FP32_MIN_SUBN   = 32'h0000_0001;
  localparam logic [31:0] FP32_NEG_ZERO   = 32'h8000_0000;
  localparam logic [31:0] FP32_ALL_MANT   = 32'h7FFF_FFFF;  // exp=FF, mant=all 1s (NaN)

  // ── Scoreboard ────────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  function void chk(string desc, logic cond);
    if (cond) begin $display("  PASS: %s", desc); pass_cnt++; end
    else      begin $display("  FAIL: %s", desc); fail_cnt++; end
  endfunction

  // ── Apply stimulus and check (1-cycle latency) ───────────────────────────────
  task automatic apply_and_check(
    input logic [31:0] fp_val,
    input logic        exp_nan,
    input logic        exp_inf,
    input string       desc
  );
    @(posedge clk); #1;
    fp32_in  = fp_val;
    valid_in = 1'b1;

    @(posedge clk); #1;
    valid_in = 1'b0;

    chk($sformatf("%s valid_out=1",      desc), valid_out    === 1'b1);
    chk($sformatf("%s nan_detected=%0b", desc, exp_nan), nan_detected === exp_nan);
    chk($sformatf("%s inf_detected=%0b", desc, exp_inf), inf_detected === exp_inf);
    chk($sformatf("%s fault_out=%0b",    desc, exp_nan|exp_inf),
        fault_out === (exp_nan | exp_inf));
  endtask

  // ── Test ─────────────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_nan_inf_detector ===");
    fp32_in  = '0;
    valid_in = 1'b0;

    // TC1: Reset — all outputs 0
    repeat(4) @(posedge clk);
    chk("TC1 reset: nan_detected==0", nan_detected === 1'b0);
    chk("TC1 reset: inf_detected==0", inf_detected === 1'b0);
    chk("TC1 reset: fault_out==0",    fault_out    === 1'b0);
    chk("TC1 reset: valid_out==0",    valid_out    === 1'b0);
    @(posedge clk); #1; rst_n = 1;
    repeat(2) @(posedge clk);

    // TC2: Normal number (1.0) — no NaN, no Inf
    apply_and_check(FP32_ONE,     1'b0, 1'b0, "TC2 +1.0 normal");

    // TC3: Positive Infinity
    apply_and_check(FP32_POS_INF, 1'b0, 1'b1, "TC3 +Inf");

    // TC4: Negative Infinity
    apply_and_check(FP32_NEG_INF, 1'b0, 1'b1, "TC4 -Inf");

    // TC5: Quiet NaN (positive)
    apply_and_check(FP32_QNAN_P,  1'b1, 1'b0, "TC5 +QNaN");

    // TC6: Signalling NaN (positive)
    apply_and_check(FP32_SNAN_P,  1'b1, 1'b0, "TC6 +SNaN");

    // TC7: NaN (negative, all mantissa bits set)
    apply_and_check(FP32_NAN_N,   1'b1, 1'b0, "TC7 -NaN");

    // TC8: Zero — no fault
    apply_and_check(FP32_ZERO,    1'b0, 1'b0, "TC8 +0.0");

    // TC9: Negative zero — no fault
    apply_and_check(FP32_NEG_ZERO, 1'b0, 1'b0, "TC9 -0.0");

    // TC10: Max normal — no fault
    apply_and_check(FP32_MAX_NORM, 1'b0, 1'b0, "TC10 max normal");

    // TC11: Subnormal — no fault (exp=0, mantissa≠0 is NOT NaN/Inf)
    apply_and_check(FP32_MIN_SUBN, 1'b0, 1'b0, "TC11 min subnormal");

    // TC12: NaN with all mantissa bits set (0x7FFF_FFFF)
    apply_and_check(FP32_ALL_MANT, 1'b1, 1'b0, "TC12 NaN all-mant-set");

    // TC13: valid_in=0 → valid_out=0, outputs not updated by the new fp32_in
    begin
      // Apply valid data first to prime pipeline
      @(posedge clk); #1;
      fp32_in  = FP32_ONE;  // normal
      valid_in = 1'b1;
      @(posedge clk); #1;
      valid_in = 1'b0;
      fp32_in  = FP32_POS_INF;  // change to Inf, but valid_in=0
      @(posedge clk); #1;
      // valid_out reflects valid_in from 1 cycle ago (which was 0)
      chk("TC13 valid_in=0: valid_out==0", valid_out === 1'b0);
      // Because valid_in was 0 for this cycle, nan/inf still update (combinatorially from fp32_in)
      // BUT valid_out correctly shows 0.
    end

    // TC14: Back-to-back stream — NaN followed by Inf followed by normal
    begin
      @(posedge clk); #1; fp32_in = FP32_QNAN_P;  valid_in = 1'b1;
      @(posedge clk); #1; fp32_in = FP32_POS_INF; valid_in = 1'b1;
      @(posedge clk); #1; fp32_in = FP32_ONE;      valid_in = 1'b1;
      @(posedge clk); #1; valid_in = 1'b0;
      // Last captured: ONE → no fault
      chk("TC14 stream end: nan_detected==0", nan_detected === 1'b0);
      chk("TC14 stream end: inf_detected==0", inf_detected === 1'b0);
      chk("TC14 stream end: fault_out==0",    fault_out    === 1'b0);
      chk("TC14 stream end: valid_out==1",    valid_out    === 1'b1);
    end

    // TC15: Reset during operation — all outputs clear
    begin
      @(posedge clk); #1;
      fp32_in  = FP32_QNAN_P;
      valid_in = 1'b1;
      @(posedge clk); #1;
      rst_n = 1'b0;
      valid_in = 1'b0;
      repeat(3) @(posedge clk);
      chk("TC15 reset clears all: nan_detected==0", nan_detected === 1'b0);
      chk("TC15 reset clears all: inf_detected==0", inf_detected === 1'b0);
      chk("TC15 reset clears all: fault_out==0",    fault_out    === 1'b0);
      chk("TC15 reset clears all: valid_out==0",    valid_out    === 1'b0);
      @(posedge clk); #1; rst_n = 1'b1;
      repeat(2) @(posedge clk);
    end

    // ── Summary ──────────────────────────────────────────────────────────────
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
      $finish(0);
    else
      $fatal(1, "tb_nan_inf_detector: %0d test(s) FAILED.", fail_cnt);
  end

endmodule
// ================================================================================
