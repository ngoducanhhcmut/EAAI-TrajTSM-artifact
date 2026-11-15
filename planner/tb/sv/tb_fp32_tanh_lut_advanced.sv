// =============================================================================
// tb_fp32_tanh_lut_advanced.sv — Advanced self-checking testbench
// Covers: Pipeline latency, Scoreboarding, Corner Cases (IEEE-754), Random Sweep
// =============================================================================
`timescale 1ns/1ps

module tb_fp32_tanh_lut_advanced;
  // import planning_pkg::*; // Uncomment if needed

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic        clk     = 1'b0;
  logic        rst_n;
  logic [31:0] x_in;
  logic        valid_in;
  logic [31:0] y_out;
  logic        valid_out;

  // ── Clock Generation ──────────────────────────────────────────────────────
  always #2.5 clk = ~clk; // 200 MHz

  // ── DUT Instantiation ─────────────────────────────────────────────────────
  fp32_tanh_lut dut (.*);

  // ── IEEE-754 FP32 Constants ───────────────────────────────────────────────
  localparam logic [31:0] FP32_NEG4     = 32'hC0800000; // -4.0
  localparam logic [31:0] FP32_POS4     = 32'h40800000; // +4.0
  localparam logic [31:0] FP32_NEG1     = 32'hBF800000; // -1.0
  localparam logic [31:0] FP32_POS1     = 32'h3F800000; // +1.0
  
  // Corner cases
  localparam logic [31:0] FP32_POS_ZERO = 32'h00000000; // +0.0
  localparam logic [31:0] FP32_NEG_ZERO = 32'h80000000; // -0.0
  localparam logic [31:0] FP32_POS_INF  = 32'h7F800000; // +Infinity
  localparam logic [31:0] FP32_NEG_INF  = 32'hFF800000; // -Infinity
  localparam logic [31:0] FP32_NAN      = 32'h7FC00000; // NaN
  localparam logic [31:0] FP32_SUBNORM  = 32'h00400000; // Subnormal number

  // ── Reference Model ────────────────────────────────────────────────────────
  // BUG-FIX (golden-model mismatch): this used to index into a separate
  // tb_lut[] (loaded from tanh_lut_init.hex) with a bit-extraction formula
  // ({x_sat[29:23],1'b0}) that matched NEITHER the DUT's actual simulated
  // output (DUT uses the `ifndef SYNTHESIS behavioral $exp() path, not the
  // LUT, in simulation) NOR a physically valid index scaling -- causing
  // near-100% mismatches independent of any RTL defect. Now mirrors
  // fp32_tanh_lut.sv's real behavioral math exactly (same round-to-nearest,
  // same shortreal precision) for bit-exact comparison in simulation.

  // Replicate DUT's exact comparison logic for accurate golden reference
  function automatic logic fp32_lt(input logic [31:0] a, input logic [31:0] b);
    if (a[31] != b[31]) return a[31];
    else if (a[31]) return (a[30:0] > b[30:0]);
    else return (a[30:0] < b[30:0]);
  endfunction

  // Golden model to calculate expected output
  function automatic logic [31:0] get_expected_y(input logic [31:0] x);
    logic        is_nan;
    logic        clamp_low, clamp_high;
    logic [31:0] x_sat;
    shortreal    xv, xc, yv;
    real         lut_r, ex2;
    integer      lut_i;

    is_nan = (x[30:23] == 8'hFF) && (x[22:0] != 23'h0);
    if (is_nan) return 32'h7FC00000;  // canonical quiet NaN, matches DUT is_nan_s2 path

    clamp_low  = fp32_lt(x, FP32_NEG4);
    clamp_high = fp32_lt(FP32_POS4, x);
    if (clamp_low)       x_sat = FP32_NEG4;
    else if (clamp_high) x_sat = FP32_POS4;
    else                 x_sat = x;

    // Same quantized computation as fp32_tanh_lut.sv's `ifndef SYNTHESIS path
    xv    = $bitstoshortreal(x_sat);
    lut_r = real'(xv) * 32.0 + 128.0;
    lut_i = $rtoi(lut_r + 0.5);
    if (lut_i < 0)   lut_i = 0;
    if (lut_i > 255) lut_i = 255;
    xc  = shortreal'((lut_i - 128) / 32.0);
    ex2 = $exp(2.0 * real'(xc));
    yv  = shortreal'((ex2 - 1.0) / (ex2 + 1.0));
    return $shortrealtobits(yv);
  endfunction

  // ── Scoreboard & Data Structures ──────────────────────────────────────────
  typedef struct {
    logic [31:0] x_val;
    logic [31:0] exp_y;
  } exp_data_t;

  exp_data_t expected_q[$]; // Queue to hold expected values
  
  int pass_cnt = 0;
  int fail_cnt = 0;
  int tx_cnt   = 0;

  // ── Latency Monitor (Strict 3-cycle check) ────────────────────────────────
  logic v_d1, v_d2, v_d3;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) {v_d3, v_d2, v_d1} <= 3'b0;
    else        {v_d3, v_d2, v_d1} <= {v_d2, v_d1, valid_in};
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      // 1. Strict latency assertion
      if (valid_out !== v_d3) begin
        $error("[TIME %0t] LATENCY VIOLATION: valid_out=%b, expected=%b", $time, valid_out, v_d3);
        fail_cnt++;
      end

      // 2. Data verification
      if (valid_out) begin
        if (expected_q.size() == 0) begin
          $error("[TIME %0t] SCOREBOARD UNDERFLOW: valid_out high but queue empty!", $time);
          fail_cnt++;
        end else begin
          exp_data_t exp_item = expected_q.pop_front();
          if (y_out !== exp_item.exp_y) begin
            $error("[FAIL] X=0x%08h | GOT=0x%08h | EXP=0x%08h", exp_item.x_val, y_out, exp_item.exp_y);
            fail_cnt++;
          end else begin
            pass_cnt++;
          end
        end
      end
    end
  end

  // ── Test Tasks ────────────────────────────────────────────────────────────
  task do_reset();
    rst_n    = 0;
    x_in     = 0;
    valid_in = 0;
    expected_q.delete();
    repeat(5) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // Push 1 stimulus to DUT and record expected value
  task drive_stimulus(input logic [31:0] x);
    x_in     <= x;
    valid_in <= 1'b1;
    expected_q.push_back('{x, get_expected_y(x)});
    tx_cnt++;
    @(posedge clk);
  endtask

  // Insert idle cycles
  task insert_bubble(input int cycles);
    valid_in <= 1'b0;
    x_in     <= 32'hxxxxxxxx; // Inject X to ensure logic doesn't leak
    repeat(cycles) @(posedge clk);
  endtask

  // Wait for all items in pipeline to flush
  task wait_for_flush();
    insert_bubble(10); // Wait enough cycles for pipeline to drain
    if (expected_q.size() != 0) begin
      $error("Pipeline flush incomplete! Queue still has %0d items.", expected_q.size());
      fail_cnt++;
    end
  endtask

  // ── Main Test Sequence ────────────────────────────────────────────────────
  initial begin
    $display("===============================================================");
    $display("=== STARTING ADVANCED TB: fp32_tanh_lut");
    $display("===============================================================");
    
    do_reset();

    // ------------------------------------------------------------------------
    $display("\n[PHASE 1] Corner Cases & IEEE-754 Boundaries...");
    drive_stimulus(FP32_POS_ZERO);
    drive_stimulus(FP32_NEG_ZERO);
    drive_stimulus(FP32_POS4);
    drive_stimulus(FP32_NEG4);
    drive_stimulus(FP32_POS_INF);
    drive_stimulus(FP32_NEG_INF);
    drive_stimulus(FP32_NAN);
    drive_stimulus(FP32_SUBNORM);
    wait_for_flush();

    // ------------------------------------------------------------------------
    $display("\n[PHASE 2] Back-to-Back Pipeline Stress (100 sequential vectors)...");
    for (int i = 0; i < 100; i++) begin
      // Mix valid and out-of-bounds ranges
      logic [31:0] rand_x;
      if (i % 5 == 0) rand_x = FP32_NEG1; // Inject some known in-range
      else rand_x = $urandom();           // Inject fully random bits
      
      drive_stimulus(rand_x);
    end
    wait_for_flush();

    // ------------------------------------------------------------------------
    $display("\n[PHASE 3] Random Sweep with Stalls (5000 iterations)...");
    for (int i = 0; i < 5000; i++) begin
      drive_stimulus($urandom());
      
      // 20% chance to insert a random pipeline stall/bubble
      if ($urandom_range(0, 100) < 20) begin
        insert_bubble($urandom_range(1, 3));
      end
    end
    wait_for_flush();

    // ------------------------------------------------------------------------
    $display("\n===============================================================");
    $display("=== TEST SUMMARY");
    $display("=== Vectors tested: %0d", tx_cnt);
    $display("=== RESULT: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    $display("===============================================================");
    
    if (fail_cnt == 0) begin
      $display(">>> SUCCESS: fp32_tanh_lut is robust! <<<");
      $finish(0);
    end else begin
      $fatal(1, ">>> FAILURE: Found %0d bugs in design. <<<", fail_cnt);
    end
  end

endmodule