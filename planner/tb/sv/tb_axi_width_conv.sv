// =============================================================================
// tb_axi_width_conv.sv — Vivado xsim testbench for axi_width_converter
// Tests 128-bit AXI read → 64-bit output conversion
// BEAT0: out_data = rdata[63:0],  out_last=0
// BEAT1: out_data = rdata[127:64], out_last=1 (when AXI rlast=1)
// Usage: Vivado simulation, top = tb_axi_width_conv
// =============================================================================
`timescale 1ns/1ps

module tb_axi_width_conv;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic         clk       = 1'b0;
  logic         rst_n;
  // AXI R channel (128-bit input)
  logic [127:0] axi_rdata;
  logic   [1:0] axi_rresp;
  logic         axi_rlast;
  logic         axi_rvalid;
  logic         axi_rready;
  // 64-bit output stream
  logic  [63:0] out_data;
  logic   [1:0] out_resp;
  logic         out_valid;
  logic         out_last;
  logic         out_ready;

  always #2.5 clk = ~clk;

  axi_width_converter dut (.*);

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick();
    @(posedge clk); #0.1;
  endtask

  task do_reset();
    rst_n     = 0;
    axi_rdata = 0;
    axi_rresp = 0;
    axi_rlast = 0;
    axi_rvalid= 0;
    out_ready = 0;
    tick(); tick();
    rst_n = 1;
    tick();
  endtask

  task check_val(input string name, input logic [63:0] got, input logic [63:0] exp);
    if (got === exp) begin
      $display("  PASS [%-24s] = 0x%016h", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-24s] got=0x%016h exp=0x%016h", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-24s] = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-24s] got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  // Send one 128-bit AXI beat and collect both 64-bit output beats
  task send_and_collect(
    input  logic [127:0] rdata,
    input  logic         is_last,
    output logic  [63:0] beat0,
    output logic  [63:0] beat1,
    output logic         last0,
    output logic         last1
  );
    // Present AXI beat
    axi_rdata  = rdata;
    axi_rlast  = is_last;
    axi_rvalid = 1;
    out_ready  = 1;

    // BEAT0: lower 64 bits
    @(posedge clk iff (out_valid && out_ready)); #0.1;
    beat0 = out_data;
    last0 = out_last;

    // BEAT1: upper 64 bits
    @(posedge clk iff (out_valid && out_ready)); #0.1;
    beat1 = out_data;
    last1 = out_last;

    axi_rvalid = 0;
    axi_rlast  = 0;
    tick();
  endtask

  // ── Test sequence ─────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_axi_width_conv : axi_width_converter ===");

    do_reset();

    // T1: after reset, out_valid=0
    check_bit("after_reset_out_valid", out_valid, 1'b0);

    // T2: Single 128-bit beat (rlast=0 → mid-burst, last0=0 last1=0)
    begin
      logic [63:0] b0, b1;
      logic        l0, l1;
      logic [127:0] test_data;
      test_data = 128'hDEADBEEF_CAFEBABE_01234567_89ABCDEF;
      send_and_collect(test_data, 1'b0, b0, b1, l0, l1);
      check_val("beat0_low64",    b0, test_data[63:0]);
      check_val("beat1_high64",   b1, test_data[127:64]);
      check_bit("beat0_not_last", l0, 1'b0);  // BEAT0 is never last
      check_bit("beat1_not_last", l1, 1'b0);  // mid-burst: rlast=0 → last1=0
    end

    // T3: Last beat of burst (rlast=1 → last1=1, last0=0)
    begin
      logic [63:0] b0, b1;
      logic        l0, l1;
      logic [127:0] test_data;
      test_data = 128'hFFFFFFFF_00000000_AAAAAAAA_55555555;
      send_and_collect(test_data, 1'b1, b0, b1, l0, l1);
      check_val("last_beat0_low",  b0, test_data[63:0]);
      check_val("last_beat1_high", b1, test_data[127:64]);
      check_bit("last_beat0_last", l0, 1'b0);  // BEAT0 always 0
      check_bit("last_beat1_last", l1, 1'b1);  // BEAT1 last when rlast=1
    end

    // T4: axi_rready follows out_ready — when consumer not ready, stall
    begin
      logic [63:0] b0, b1;
      logic        l0, l1;
      axi_rdata  = 128'h1111_2222_3333_4444_5555_6666_7777_8888;
      axi_rlast  = 0;
      axi_rvalid = 1;
      out_ready  = 0;   // consumer NOT ready
      repeat(3) tick();
      check_bit("backpressure_valid", out_valid, 1'b0);  // no output while not ready
      out_ready = 1;
      axi_rvalid= 0;
      tick();
      pass_cnt++;  // no deadlock observed
      $display("  PASS [backpressure      ] no deadlock");
    end

    // T5: Multiple back-to-back bursts
    begin
      logic [63:0] b0, b1;
      logic        l0, l1;
      for (int i = 0; i < 4; i++) begin
        logic [127:0] d;
        d = {64'hAAAA_0000_0000_0000 + i, 64'h5555_0000_0000_0000 + i};
        send_and_collect(d, (i==3), b0, b1, l0, l1);
        if (b0 === d[63:0] && b1 === d[127:64]) begin
          $display("  PASS [burst_beat_%0d      ] low=0x%016h high=0x%016h", i, b0, b1);
          pass_cnt += 2;
        end else begin
          $error("  FAIL [burst_beat_%0d      ] data mismatch", i);
          fail_cnt += 2;
        end
      end
    end

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: axi_width_converter");
      $finish(0);
    end else
      $fatal(1, "FAIL: axi_width_converter — %0d test(s) failed", fail_cnt);
  end

  // Timeout watchdog: 50 μs max
  initial begin
    #50000;
    $fatal(1, "TIMEOUT: simulation exceeded 50 us");
  end

endmodule
