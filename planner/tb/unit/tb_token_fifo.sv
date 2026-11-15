// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// tb_token_fifo.sv — Unit Test for 64-entry Token FIFO
// Test: Handshake protocol, write/read, occupancy, capacity
// Spec v15.5 §3.1, §15.15
// ================================================================================

`timescale 1ns / 1ps
`default_nettype none

import planning_pkg::*;

module tb_token_fifo ();

  logic clk, rst_n;
  
  // Write side (from world_model_parser)
  bbox6_t x_token_data;
  token_type_t x_token_type;
  logic x_token_valid;
  logic x_token_ready;
  
  // Read side (to input_adapter)
  bbox6_t token_o;
  token_type_t token_type_o;
  logic token_valid_o;
  logic token_ready_i;
  
  // Status
  logic [7:0] fifo_occupancy;
  
  integer errors = 0, tests = 0;

  // DUT: 64-entry Token FIFO
  token_fifo dut (
    .clk(clk), .rst_n(rst_n),
    .x_token_data(x_token_data),
    .x_token_type(x_token_type),
    .x_token_valid(x_token_valid),
    .x_token_ready(x_token_ready),
    .token_o(token_o),
    .token_type_o(token_type_o),
    .token_valid_o(token_valid_o),
    .token_ready_i(token_ready_i),
    .fifo_occupancy(fifo_occupancy)
  );

  // Clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset
  initial begin
    rst_n = 0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
  end

  // Test stimulus
  initial begin
    x_token_valid = 0;
    token_ready_i = 0;
    x_token_data = '0;
    x_token_type = TT_CLS;

    @(posedge rst_n);
    @(posedge clk);
    $display("[FIFO_TEST] Starting token_fifo unit test (64-entry handshake)...");

    // Test 1: FIFO empty on reset
    $display("[TEST 1] Verify FIFO empty on reset");
    tests = tests + 1;
    if (fifo_occupancy == 8'd0 && !token_valid_o) begin
      $display("  ✓ PASS: occupancy=0, token_valid_o=0");
    end else begin
      $display("  ✗ FAIL: occupancy=%d, token_valid_o=%d", fifo_occupancy, token_valid_o);
      errors = errors + 1;
    end

    // Test 2: Write single token with handshake
    $display("[TEST 2] Write single token (x_token_valid/ready handshake)");
    tests = tests + 1;
    x_token_data = 24'hCAFEBA;
    x_token_type = TT_EGO;
    x_token_valid = 1;
    @(posedge clk);
    x_token_valid = 0;
    @(posedge clk);  // Occupancy updated
    @(posedge clk);  // Account for output pipeline delay
    if (token_valid_o && fifo_occupancy == 8'd1) begin
      $display("  ✓ PASS: token available, occupancy=1");
    end else begin
      $display("  ✗ FAIL: token_valid_o=%d, occupancy=%d", token_valid_o, fifo_occupancy);
      errors = errors + 1;
    end

    // Test 3: Read token with handshake
    $display("[TEST 3] Read token (token_valid_o/ready_i handshake)");
    tests = tests + 1;
    token_ready_i = 1;
    @(posedge clk);
    token_ready_i = 0;
    @(posedge clk);  // Occupancy updated
    @(posedge clk);  // Account for output pipeline delay to clear token_valid_o
    if (fifo_occupancy == 8'd0 && !token_valid_o) begin
      $display("  ✓ PASS: token drained, occupancy=0");
    end else begin
      $display("  ✗ FAIL: occupancy=%d, token_valid_o=%d", fifo_occupancy, token_valid_o);
      errors = errors + 1;
    end

    // Test 4: Fill FIFO to capacity (64 entries per spec §15.15)
    $display("[TEST 4] Fill FIFO to 64 entries (capacity test)");
    tests = tests + 1;
    for (int i = 0; i < 64; i = i + 1) begin
      x_token_data = 24'(i);
      x_token_type = TT_OBJECT;
      x_token_valid = 1;
      if (!x_token_ready) begin
        $display("  ⚠ INFO: x_token_ready=0 at entry %0d (full)", i);
        break;
      end
      @(posedge clk);
    end
    x_token_valid = 0;
    @(posedge clk);
    if (fifo_occupancy == 8'd64) begin
      $display("  ✓ PASS: FIFO capacity 64 verified (occupancy=%d)", fifo_occupancy);
    end else begin
      $display("  ✗ FAIL: occupancy=%d (expected 64)", fifo_occupancy);
      errors = errors + 1;
    end

    // Test 5: Verify x_token_ready=0 when full
    $display("[TEST 5] Verify x_token_ready low when FIFO full");
    tests = tests + 1;
    if (!x_token_ready) begin
      $display("  ✓ PASS: x_token_ready=0 (FIFO full, backpressure active)");
    end else begin
      $display("  ✗ FAIL: x_token_ready=%d (expected 0)", x_token_ready);
      errors = errors + 1;
    end

    // Test 6: Drain FIFO
    $display("[TEST 6] Drain FIFO (read all 64 tokens)");
    tests = tests + 1;
    token_ready_i = 1;
    
    // Drain until FIFO is empty (occupancy=0 AND token_valid_o=0)
    integer drain_count = 0;
    while (fifo_occupancy > 0 || token_valid_o) begin
      @(posedge clk);
      #1;  // Check on settled values
      if (token_valid_o && token_ready_i) begin
        drain_count = drain_count + 1;
      end
      if (drain_count > 65) break;  // Safety: stop after 65 transfers
    end
    
    token_ready_i = 0;
    @(posedge clk);
    
    if (fifo_occupancy == 8'd0 && !token_valid_o && drain_count == 64) begin
      $display("  ✓ PASS: FIFO drained all 64 tokens, occupancy=0");
    end else begin
      $display("  ✗ FAIL: occupancy=%d, token_valid_o=%d, drained=%0d/64", 
               fifo_occupancy, token_valid_o, drain_count);
      errors = errors + 1;
    end

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
    
    // Allow extra time for waveform capture
    repeat(100) @(posedge clk);
    $finish;
  end

endmodule
