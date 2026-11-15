// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// tb_hsync_chain.sv — Unit Test for CDC Synchronizer
// Test: Cross-domain synchronization reliability
// ================================================================================

`timescale 1ns / 1ps
`default_nettype none

import planning_pkg::*;

module tb_hsync_chain ();

  logic clk_src, clk_dst, rst_n;
  logic data_in, data_out;
  
  integer errors = 0, tests = 0;

  // DUT: 2-stage synchronizer
  hsync_chain #(.WIDTH(1), .STAGES(2)) dut (
    .clk_src(clk_src),
    .clk_dst(clk_dst),
    .rst_n(rst_n),
    .data_in(data_in),
    .data_out(data_out)
  );

  // Source clock: 5ns (200MHz)
  initial begin
    clk_src = 0;
    forever #5 clk_src = ~clk_src;
  end

  // Destination clock: 10ns (100MHz) — asynchronous
  initial begin
    clk_dst = 0;
    forever #10 clk_dst = ~clk_dst;
  end

  // Reset
  initial begin
    rst_n = 0;
    @(posedge clk_dst);
    @(posedge clk_dst);
    rst_n = 1;
  end

  // Test stimulus
  initial begin
    data_in = 0;

    @(posedge clk_dst);
    $display("[CDC_TEST] Starting hsync_chain unit test...");

    // Test 1: Low → High transition
    $display("[TEST 1] Rising edge synchronization");
    tests = tests + 1;
    data_in = 0;
    repeat(3) @(posedge clk_src);
    data_in = 1;
    @(posedge clk_src);
    // Wait for CDC latency (2+ dst clock cycles)
    repeat(5) @(posedge clk_dst);
    if (data_out == 1) begin
      $display("  ✓ PASS: Input high synchronized to output");
    end else begin
      $display("  ✗ FAIL: data_out=%d (expected 1)", data_out);
      errors = errors + 1;
    end

    // Test 2: High → Low transition
    $display("[TEST 2] Falling edge synchronization");
    tests = tests + 1;
    data_in = 0;
    repeat(3) @(posedge clk_src);
    // CDC latency again
    repeat(5) @(posedge clk_dst);
    if (data_out == 0) begin
      $display("  ✓ PASS: Input low synchronized to output");
    end else begin
      $display("  ✗ FAIL: data_out=%d (expected 0)", data_out);
      errors = errors + 1;
    end

    // Test 3: Stability check (long stable periods)
    $display("[TEST 3] Stable value held for duration");
    tests = tests + 1;
    data_in = 1;
    repeat(6) @(posedge clk_dst);
    if (data_out == 1) begin
      $display("  ✓ PASS: Stable high value maintained");
    end else begin
      $display("  ✗ FAIL: Value changed unexpectedly");
      errors = errors + 1;
    end

    // Test 4: Reset behavior
    $display("[TEST 4] Reset clears output");
    tests = tests + 1;
    data_in = 1;
    rst_n = 0;
    @(posedge clk_dst);
    if (data_out == 0) begin
      $display("  ✓ PASS: Output cleared on reset");
    end else begin
      $display("  ✗ FAIL: data_out=%d after reset (expected 0)", data_out);
      errors = errors + 1;
    end

    @(posedge clk_dst);
    rst_n = 1;

    // Summary
    $display("");
    $display("========================================");
    $display("  Tests run: %0d", tests);
    $display("  Errors:    %0d", errors);
    if (errors == 0) begin
      $display("  Status: ✓ ALL TESTS PASSED");
    end else begin
      $display("  Status: ✗ FAILURES DETECTED");
    end
    $display("========================================");
    
    $finish;
  end

endmodule
