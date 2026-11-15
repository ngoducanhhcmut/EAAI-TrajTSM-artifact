// =============================================================================
// tb_gru_waypoint_decoder.sv — Unit Testbench for gru_waypoint_decoder
// Tests GRU decode sequence: gru_start → CLS read → URAM read → scratch →
//                            bias → wout → scale → waypoints_valid + gru_done
// Smoke test: all BRAMs modeled with zero data
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_gru_waypoint_decoder;
  import planning_pkg::*;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic          gru_start;

  // CLS buffer (FP32, 512-deep)
  logic  [8:0]   cls_buf_rd_addr;
  fp32_t         cls_buf_rd_data;
  logic          cls_buf_rd_en;

  // GRU URAM bank A (even beat-pairs)
  logic [16:0]   gru_uram_addr;
  logic [63:0]   gru_uram_rdata;
  logic          gru_uram_en;

  // GRU URAM bank B (odd beat-pairs) — N=32 dual-bank
  logic [16:0]   gru_uram_addr_b;
  logic [63:0]   gru_uram_rdata_b;
  logic          gru_uram_en_b;

  // GRU bias BRAM
  logic [10:0]   gru_bias_addr;
  logic [31:0]   gru_bias_rdata;

  // WOut BRAM
  logic [10:0]   wout_bram_addr;
  logic [31:0]   wout_bram_rdata;

  // GRU scale LUTRAM
  logic  [2:0]   gru_scale_sel;
  logic  [8:0]   gru_scale_addr;
  logic [15:0]   gru_scale_rdata;

  // WP-proj BRAM (FP32 projection weights)
  logic [10:0]   wp_proj_bram_addr;
  logic [31:0]   wp_proj_bram_rdata;
  logic          wp_proj_bram_en;

  // Outputs
  fp32_t         waypoint_x [NUM_WAYPOINTS-1:0];
  fp32_t         waypoint_y [NUM_WAYPOINTS-1:0];
  logic          waypoints_valid;
  logic          gru_done;

  gru_waypoint_decoder dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .gru_start        (gru_start),
    .cls_buf_rd_addr  (cls_buf_rd_addr),
    .cls_buf_rd_data  (cls_buf_rd_data),
    .cls_buf_rd_en    (cls_buf_rd_en),
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

  // ── Memory models (all return 0 for smoke test) ────────────────────────────
  // CLS buffer: FP32
  fp32_t cls_buf_mem [0:511];
  always_ff @(posedge clk) begin
    cls_buf_rd_data <= cls_buf_rd_en ? cls_buf_mem[cls_buf_rd_addr] : 32'h0;
  end

  // GRU URAM bank A: INT4 packed in 64-bit words
  logic [63:0] gru_uram_mem [0:131071];
  always_ff @(posedge clk) begin
    gru_uram_rdata   <= gru_uram_en   ? gru_uram_mem[gru_uram_addr[16:0]]   : 64'h0;
    gru_uram_rdata_b <= gru_uram_en_b ? gru_uram_mem[gru_uram_addr_b[16:0]] : 64'h0;
  end

  // WP-proj BRAM: FP32
  logic [31:0] wp_proj_bram_mem [0:2047];
  always_ff @(posedge clk) begin
    wp_proj_bram_rdata <= wp_proj_bram_en ? wp_proj_bram_mem[wp_proj_bram_addr] : 32'h0;
  end

  // Bias BRAM
  logic [31:0] gru_bias_mem [0:2047];
  always_ff @(posedge clk) begin
    gru_bias_rdata <= gru_bias_mem[gru_bias_addr];
  end

  // WOut BRAM
  logic [31:0] wout_bram_mem [0:2047];
  always_ff @(posedge clk) begin
    wout_bram_rdata <= wout_bram_mem[wout_bram_addr];
  end

  // GRU scale LUTRAM: {scale_q8[7:0], zp[7:0]}
  logic [15:0] gru_scale_mem [0:511];
  always_ff @(posedge clk) begin
    gru_scale_rdata <= gru_scale_mem[gru_scale_addr];
  end

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  function automatic logic [31:0] real_to_fp32(input real v);
    return $shortrealtobits(shortreal'(v));
  endfunction

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_gru_waypoint_decoder : gru_waypoint_decoder ===");

    gru_start = 0;

    // Initialize all memories to 0
    for (int i = 0; i < 512;    i++) cls_buf_mem[i]       = 32'h0;
    for (int i = 0; i < 131072; i++) gru_uram_mem[i]      = 64'h0;
    for (int i = 0; i < 2048;   i++) gru_bias_mem[i]      = 32'h0;
    for (int i = 0; i < 2048;   i++) wout_bram_mem[i]     = 32'h0;
    for (int i = 0; i < 512;    i++) gru_scale_mem[i]     = 16'h0;
    for (int i = 0; i < 2048;   i++) wp_proj_bram_mem[i]  = 32'h0;

    rst_n = 0;
    tick(3);
    rst_n = 1;
    tick(2);

    // T1: After reset, no done signals
    check_bit("after_reset_done",  gru_done,        1'b0);
    check_bit("after_reset_valid", waypoints_valid, 1'b0);

    // T2: gru_start pulse → should eventually produce gru_done and waypoints_valid
    @(posedge clk); #0.1;
    gru_start = 1'b1;
    @(posedge clk); #0.1;
    gru_start = 1'b0;

    // Wait for gru_done (all-zero inputs → output will be 0 FP32 waypoints)
    begin
      int timeout = 0;
      int wp_valid_seen = 0;
      int done_seen = 0;

      while (timeout < 7000000) begin
        @(posedge clk); #0.1;
        if (waypoints_valid) wp_valid_seen = 1;
        if (gru_done) begin
          done_seen = 1;
          break;
        end
        timeout++;
      end

      if (done_seen) begin
        $display("  PASS [%-30s] gru_done in %0d cycles", "gru_done_fires", timeout);
        pass_cnt++;
      end else begin
        $error("  FAIL [%-30s] timed out after %0d cycles", "gru_done_fires", timeout);
        fail_cnt++;
      end

      if (wp_valid_seen) begin
        $display("  PASS [%-30s] waypoints_valid seen", "wp_valid_fires");
        pass_cnt++;
        // With all-zero weights, waypoints should be 0 or very small FP32
        // Just check all outputs are not 'x' or 'z'
        for (int i = 0; i < NUM_WAYPOINTS; i++) begin
          if (waypoint_x[i] !== 32'bx && waypoint_y[i] !== 32'bx) begin
            $display("  PASS [%-30s] wp[%0d]: x=0x%08h y=0x%08h (no X/Z)",
                     "wp_defined", i, waypoint_x[i], waypoint_y[i]);
            pass_cnt++;
          end else begin
            $error("  FAIL [%-30s] wp[%0d] has X/Z values", "wp_defined", i);
            fail_cnt++;
          end
        end
      end else begin
        $error("  FAIL [%-30s] waypoints_valid never seen", "wp_valid_fires");
        fail_cnt++;
      end
    end

    tick(5);

    // T3: Second run — gru_start again, should complete without deadlock
    @(posedge clk); #0.1;
    gru_start = 1'b1;
    @(posedge clk); #0.1;
    gru_start = 1'b0;

    begin
      int timeout = 0;
      while (!gru_done && timeout < 7000000) begin
        @(posedge clk); #0.1;
        timeout++;
      end
      if (gru_done) begin
        $display("  PASS [%-30s] second run completes", "gru_run2_done");
        pass_cnt++;
      end else begin
        $error("  FAIL [%-30s] second run timed out", "gru_run2_done");
        fail_cnt++;
      end
    end

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: gru_waypoint_decoder");
      $finish(0);
    end else
      $fatal(1, "FAIL: gru_waypoint_decoder — %0d test(s) failed", fail_cnt);
  end

  initial begin
    #75000000;
    $fatal(1, "TIMEOUT: simulation exceeded 75 ms");
  end

endmodule
`default_nettype wire
