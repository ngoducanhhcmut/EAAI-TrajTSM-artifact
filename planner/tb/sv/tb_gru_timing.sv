// =============================================================================
// tb_gru_timing.sv — GRU N=32 Timing Verification Testbench
// Instantiates gru_waypoint_decoder with updated port list (no scratch BRAM,
// dual URAM bank, wp_proj BRAM).  All memories modeled with zero data.
// Measures: gru_start → gru_done cycle count vs. WCET budget.
// =============================================================================
`timescale 1ns/1ps
`define SIMULATION

module tb_gru_timing;
  import planning_pkg::*;

  // 185 MHz clock (period = 5.405 ns ≈ 5ns for sim convenience)
  logic clk = 1'b0;
  always #2.7027 clk = ~clk;

  logic rst_n;

  // ── DUT ports ───────────────────────────────────────────────────────────────
  logic         gru_start;

  // CLS buffer
  logic  [8:0]  cls_buf_rd_addr;
  fp32_t        cls_buf_rd_data;
  logic         cls_buf_rd_en;

  // URAM bank A (even beat-pairs)
  logic [16:0]  gru_uram_addr;
  logic [63:0]  gru_uram_rdata;
  logic         gru_uram_en;

  // URAM bank B (odd beat-pairs)
  logic [16:0]  gru_uram_addr_b;
  logic [63:0]  gru_uram_rdata_b;
  logic         gru_uram_en_b;

  // Bias BRAM
  logic [10:0]  gru_bias_addr;
  logic [31:0]  gru_bias_rdata;

  // WOut BRAM
  logic [10:0]  wout_bram_addr;
  logic [31:0]  wout_bram_rdata;

  // Scale LUTRAM
  logic  [2:0]  gru_scale_sel;
  logic  [8:0]  gru_scale_addr;
  logic [15:0]  gru_scale_rdata;

  // WP-proj BRAM
  logic [10:0]  wp_proj_bram_addr;
  logic [31:0]  wp_proj_bram_rdata;
  logic         wp_proj_bram_en;

  // Outputs
  fp32_t        waypoint_x [NUM_WAYPOINTS-1:0];
  fp32_t        waypoint_y [NUM_WAYPOINTS-1:0];
  logic         waypoints_valid;
  logic         gru_done;

  // ── DUT ─────────────────────────────────────────────────────────────────────
  gru_waypoint_decoder dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .gru_start        (gru_start),
    .cls_buf_rd_addr  (cls_buf_rd_addr),
    .cls_buf_rd_data  (cls_buf_rd_data),
    .cls_buf_rd_en    (cls_buf_rd_en),
    .gru_uram_addr    (gru_uram_addr),
    .gru_uram_rdata   (gru_uram_rdata),
    .gru_uram_en      (gru_uram_en),
    .gru_uram_addr_b  (gru_uram_addr_b),
    .gru_uram_rdata_b (gru_uram_rdata_b),
    .gru_uram_en_b    (gru_uram_en_b),
    .gru_bias_addr    (gru_bias_addr),
    .gru_bias_rdata   (gru_bias_rdata),
    .wout_bram_addr   (wout_bram_addr),
    .wout_bram_rdata  (wout_bram_rdata),
    .gru_scale_sel    (gru_scale_sel),
    .gru_scale_addr   (gru_scale_addr),
    .gru_scale_rdata  (gru_scale_rdata),
    .wp_proj_bram_addr(wp_proj_bram_addr),
    .wp_proj_bram_rdata(wp_proj_bram_rdata),
    .wp_proj_bram_en  (wp_proj_bram_en),
    .waypoint_x       (waypoint_x),
    .waypoint_y       (waypoint_y),
    .waypoints_valid  (waypoints_valid),
    .gru_done         (gru_done)
  );

  // ── Memory models (1-cycle registered reads, all-zero data) ─────────────────
  always_ff @(posedge clk) begin
    cls_buf_rd_data    <= '0;
    gru_uram_rdata     <= '0;
    gru_uram_rdata_b   <= '0;
    gru_bias_rdata     <= '0;
    wout_bram_rdata    <= '0;
    gru_scale_rdata    <= 16'h0100;  // scale_q8=1, zp=0  (non-zero to avoid degenerate path)
    wp_proj_bram_rdata <= '0;
  end

  // ── Cycle counter (hardware counter, 1 per posedge) ─────────────────────────
  longint hw_cycle = 0;
  always_ff @(posedge clk) hw_cycle <= hw_cycle + 1;

  longint start_cy, end_cy;
  longint total_cy;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  // ── Phase-level cycle accounting ─────────────────────────────────────────────
  // Count cycles spent in each major state category.
  longint cy_init=0, cy_mv_setup=0, cy_mv_col=0, cy_mv_drain=0;
  longint cy_tree=0, cy_post=0, cy_wout=0, cy_wp=0, cy_other=0;
  longint cy_step_done=0;

  always_ff @(posedge clk) begin
    if (rst_n) begin
      case (dut.state)
        5'd1:  cy_init      <= cy_init     + 1;   // S_INIT
        5'd2:  cy_mv_setup  <= cy_mv_setup + 1;   // S_MV_SETUP
        5'd3:  cy_mv_col    <= cy_mv_col   + 1;   // S_MV_COL
        5'd4:  cy_mv_drain  <= cy_mv_drain + 1;   // S_MV_DRAIN
        5'd5:  cy_tree      <= cy_tree     + 1;   // S_ADDER_TREE
        5'd6:  cy_post      <= cy_post     + 1;   // S_MV_POST
        5'd7:  cy_wout      <= cy_wout     + 1;   // S_WOUT_SETUP
        5'd8:  cy_wout      <= cy_wout     + 1;   // S_WOUT_COL
        5'd9:  cy_wout      <= cy_wout     + 1;   // S_WOUT_DRAIN
        5'd10: cy_wout      <= cy_wout     + 1;   // S_WOUT_BIAS
        5'd11: cy_wp        <= cy_wp       + 1;   // S_WP_APPLY
        5'd12: cy_step_done <= cy_step_done + 1;  // S_STEP_DONE
        default: cy_other   <= cy_other    + 1;
      endcase
    end
  end

  // ── Main test ────────────────────────────────────────────────────────────────
  initial begin
    gru_start = 1'b0;
    rst_n     = 1'b0;
    tick(10);
    rst_n = 1'b1;
    tick(5);

    $display("[tb_gru_timing] Issuing gru_start ...");

    @(posedge clk); #0.1;
    gru_start = 1'b1;
    start_cy = hw_cycle;
    @(posedge clk); #0.1;
    gru_start = 1'b0;

    // Wait for gru_done with timeout (allow up to 2M cycles)
    fork
      begin : wait_done
        @(posedge gru_done);
        end_cy = hw_cycle;
        total_cy = end_cy - start_cy;
        disable timeout_watchdog;
      end
      begin : timeout_watchdog
        tick(2_000_000);
        $display("[FAIL] gru_done not received within 2M cycles — GRU deadlock?");
        $finish;
      end
    join

    $display("");
    $display("=== GRU N=32 Phase Breakdown ===");
    $display("  S_INIT         : %0d cy", cy_init);
    $display("  S_MV_SETUP     : %0d cy", cy_mv_setup);
    $display("  S_MV_COL       : %0d cy", cy_mv_col);
    $display("  S_MV_DRAIN     : %0d cy", cy_mv_drain);
    $display("  S_ADDER_TREE   : %0d cy", cy_tree);
    $display("  S_MV_POST      : %0d cy", cy_post);
    $display("  S_WOUT_*       : %0d cy", cy_wout);
    $display("  S_WP_APPLY     : %0d cy", cy_wp);
    $display("  S_STEP_DONE    : %0d cy", cy_step_done);
    $display("  Other (IDLE+DONE): %0d cy", cy_other);
    $display("  TOTAL (counted): %0d cy",
             cy_init+cy_mv_setup+cy_mv_col+cy_mv_drain+cy_tree+cy_post+cy_wout+cy_wp+cy_step_done+cy_other);
    $display("");
    $display("=== GRU N=32 Timing Result ===");
    $display("  gru_start → gru_done : %0d cycles", total_cy);
    $display("  At 185 MHz           : %.3f ms", real'(total_cy) / 185000.0);
    $display("  WCET budget          : %0d cycles (%.3f ms)",
             GRU_LATENCY_CY, real'(GRU_LATENCY_CY) / 185000.0);

    if (total_cy <= GRU_LATENCY_CY) begin
      $display("  STATUS : PASS (margin = %0d cycles = %.3f ms)",
               GRU_LATENCY_CY - total_cy,
               real'(GRU_LATENCY_CY - total_cy) / 185000.0);
    end else begin
      $display("  STATUS : FAIL (over by %0d cycles = %.3f ms)",
               total_cy - GRU_LATENCY_CY,
               real'(total_cy - GRU_LATENCY_CY) / 185000.0);
    end
    $display("==============================");
    $display("");

    // Check waypoints valid
    if (waypoints_valid)
      $display("[PASS] waypoints_valid asserted");
    else
      $display("[WARN] waypoints_valid NOT seen (may be 1-cycle pulse, ok if gru_done fired)");

    $finish;
  end

  // ── Timeout guard ─────────────────────────────────────────────────────────
  initial begin
    #(2_100_000 * 5.41);
    $display("[FAIL] Global timeout reached.");
    $finish;
  end

endmodule
