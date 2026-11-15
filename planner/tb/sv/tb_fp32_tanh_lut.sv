// =============================================================================
// tb_fp32_tanh_lut.sv — Vivado xsim testbench for fp32_tanh_lut
// Module: fp32_tanh_lut (FP32 Tanh LUT, Spec §7.6)
// Pipeline latency: 3 cycles (stage1: saturate, stage2: LUTRAM lookup,
//                              stage3: output register)
//
// Tests:
//   T1  after_reset      : valid_out=0 after reset
//   T2  no_valid_in      : valid_out stays 0 with no input
//   T3  clamp_low        : x < -4.0 → y = -1.0 (FP32 = 0xBF800000)
//   T4  clamp_high       : x > +4.0 → y = +1.0 (FP32 = 0x3F800000)
//   T5  far_below        : x = -10.0 → clamp to -1.0
//   T6  far_above        : x = +10.0 → clamp to +1.0
//   T7  valid_latency    : valid_out appears exactly 3 cycles after valid_in
//   T8  exact_minus4     : x = -4.0 → in range, LUT used
//   T9  exact_plus4      : x = +4.0 → in range, LUT used
//   T10 zero_input       : x = 0.0 → tanh(0) = 0.0, LUT lookup
//   T11 pipeline_flush   : back-to-back valid inputs produce back-to-back valid outputs
// Usage: Vivado simulation, top = tb_fp32_tanh_lut
// Note: tanh_lut_init.hex must be present for LUT content correctness tests.
//       Tests T8/T9/T10 only check valid_out timing; LUT value accuracy
//       depends on hex init file content.
// =============================================================================
`timescale 1ns/1ps

module tb_fp32_tanh_lut;
  import planning_pkg::*;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic        clk     = 1'b0;
  logic        rst_n;
  logic [31:0] x_in;        // fp32_t
  logic        valid_in;
  logic [31:0] y_out;       // fp32_t
  logic        valid_out;

  // ── Clock: 200 MHz = 5 ns period ─────────────────────────────────────────
  always #2.5 clk = ~clk;

  // ── DUT ──────────────────────────────────────────────────────────────────
  fp32_tanh_lut dut (.*);

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  // FP32 IEEE 754 constants
  localparam logic [31:0] FP32_NEG4  = 32'hC0800000;   // -4.0
  localparam logic [31:0] FP32_POS4  = 32'h40800000;   // +4.0
  localparam logic [31:0] FP32_NEG5  = 32'hC0A00000;   // -5.0 (below range)
  localparam logic [31:0] FP32_POS5  = 32'h40A00000;   // +5.0 (above range)
  localparam logic [31:0] FP32_ZERO  = 32'h00000000;   // 0.0
  localparam logic [31:0] FP32_POS1  = 32'h3F800000;   // +1.0
  localparam logic [31:0] FP32_NEG1  = 32'hBF800000;   // -1.0
  localparam logic [31:0] FP32_NEG10 = 32'hC1200000;   // -10.0 (far below)
  localparam logic [31:0] FP32_POS10 = 32'h41200000;   // +10.0 (far above)

  task tick();
    @(posedge clk); #0.1;
  endtask

  task do_reset();
    rst_n    = 0;
    x_in     = FP32_ZERO;
    valid_in = 0;
    repeat(4) tick();
    rst_n = 1;
    tick();
  endtask

  // Drive one input, wait LATENCY cycles, capture output
  // Latency = 3 (stage1 reg + stage2 LUTRAM + stage3 output reg)
  localparam int LATENCY = 3;

  task drive_and_check(
    input string         name,
    input logic [31:0]   x,
    input logic          check_val,     // 1 = also check y_out value
    input logic [31:0]   expected_y     // only used if check_val=1
  );
    logic [31:0] got_y;
    logic        got_v;
    do_reset();

    x_in     = x;
    valid_in = 1;
    tick();             // cycle 1
    valid_in = 0;
    tick();             // cycle 2
    tick();             // cycle 3 — output should be valid after this edge

    got_v = valid_out;
    got_y = y_out;

    if (!got_v) begin
      $error("  FAIL [%-22s] valid_out=0 after 3 cycles (latency mismatch)", name);
      fail_cnt++;
      return;
    end

    if (check_val && (got_y !== expected_y)) begin
      $error("  FAIL [%-22s] x=0x%08h got_y=0x%08h exp_y=0x%08h", name, x, got_y, expected_y);
      fail_cnt++;
    end else begin
      $display("  PASS [%-22s] x=0x%08h valid_out=1 y=0x%08h", name, x, got_y);
      pass_cnt++;
    end
  endtask

  // ── Test sequence ─────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_fp32_tanh_lut : fp32_tanh_lut ===");

    // ─── T1: after_reset ────────────────────────────────────────────────────
    do_reset();
    if (valid_out === 1'b0) begin
      $display("  PASS [after_reset       ] valid_out=0");
      pass_cnt++;
    end else begin
      $error("  FAIL [after_reset       ] valid_out=%0b expected 0", valid_out);
      fail_cnt++;
    end

    // ─── T2: no_valid_in ────────────────────────────────────────────────────
    do_reset();
    x_in = FP32_ZERO; valid_in = 0;
    repeat(6) tick();
    if (valid_out === 1'b0) begin
      $display("  PASS [no_valid_in       ] valid_out=0 after 6 idle cycles");
      pass_cnt++;
    end else begin
      $error("  FAIL [no_valid_in       ] valid_out=%0b, expected 0", valid_out);
      fail_cnt++;
    end

    // ─── T3: clamp_low — x = -5.0 → below -4.0 → y = -1.0 (0xBF800000) ────
    drive_and_check("clamp_low",    FP32_NEG5,  1, FP32_NEG1);

    // ─── T4: clamp_high — x = +5.0 → above +4.0 → y = +1.0 (0x3F800000) ───
    drive_and_check("clamp_high",   FP32_POS5,  1, FP32_POS1);

    // ─── T5: far_below — x = -10.0 → clamp to -1.0 ─────────────────────────
    drive_and_check("far_below",    FP32_NEG10, 1, FP32_NEG1);

    // ─── T6: far_above — x = +10.0 → clamp to +1.0 ─────────────────────────
    drive_and_check("far_above",    FP32_POS10, 1, FP32_POS1);

    // ─── T7: valid_latency — 3 cycles exactly ───────────────────────────────
    do_reset();
    x_in = FP32_ZERO; valid_in = 1;
    tick();             // after clk edge 1: stage1 captures valid_in
    valid_in = 0;
    // After cycle 1: valid should NOT yet be out
    if (valid_out !== 1'b0) begin
      $error("  FAIL [valid_latency      ] valid_out=1 too early (after 1 cycle)");
      fail_cnt++;
    end else begin
      tick();           // cycle 2
      if (valid_out !== 1'b0) begin
        $error("  FAIL [valid_latency      ] valid_out=1 too early (after 2 cycles)");
        fail_cnt++;
      end else begin
        tick();         // cycle 3
        if (valid_out === 1'b1) begin
          $display("  PASS [valid_latency      ] valid_out=1 exactly at cycle 3");
          pass_cnt++;
        end else begin
          $error("  FAIL [valid_latency      ] valid_out=0 at cycle 3 (expected 1)");
          fail_cnt++;
        end
      end
    end

    // ─── T8: exact_minus4 — x = -4.0 → in range, LUT lookup ─────────────────
    drive_and_check("exact_minus4", FP32_NEG4,  0, 32'hx);

    // ─── T9: exact_plus4 — x = +4.0 → in range, LUT lookup ──────────────────
    drive_and_check("exact_plus4",  FP32_POS4,  0, 32'hx);

    // ─── T10: zero_input — x = 0.0 → LUT lookup ─────────────────────────────
    drive_and_check("zero_input",   FP32_ZERO,  0, 32'hx);

    // ─── T11: pipeline_flush — 5 back-to-back valid inputs ───────────────────
    // Outputs appear starting at cycle 3 (LATENCY) and continue for 5 cycles.
    // Collect during the send loop AND drain: total window = 5 + LATENCY cycles.
    do_reset();
    begin
      int valid_count;
      valid_count = 0;
      x_in = FP32_ZERO;
      // Send 5 pulses and collect simultaneously (first outputs appear at cycle 3)
      repeat(5) begin
        valid_in = 1;
        if (valid_out) valid_count++;
        tick();
      end
      valid_in = 0;
      // Drain: collect LATENCY more cycles for remaining pipeline outputs
      repeat(LATENCY) begin
        if (valid_out) valid_count++;
        tick();
      end
      if (valid_count >= 5) begin
        $display("  PASS [pipeline_flush    ] %0d valid outputs for 5 consecutive inputs", valid_count);
        pass_cnt++;
      end else begin
        $error("  FAIL [pipeline_flush    ] got %0d valid outputs, expected >=5", valid_count);
        fail_cnt++;
      end
    end

    // ─── Final summary ────────────────────────────────────────────────────────
    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: fp32_tanh_lut");
      $finish(0);
    end else begin
      $fatal(1, "FAIL: fp32_tanh_lut — %0d test(s) failed", fail_cnt);
    end
  end

endmodule
