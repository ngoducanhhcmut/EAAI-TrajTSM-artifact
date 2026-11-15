// ================================================================================
// Testbench: tb_cdc_pulse_sync.sv
// DUT: cdc_pulse_sync — Pulse-to-level CDC synchronizer (3-stage default)
// Spec: §15.3
// ================================================================================
`timescale 1ns/1ps

module tb_cdc_pulse_sync;

  // ── Clock & reset ─────────────────────────────────────────────────────────────
  // src_clk  = 200 MHz (5 ns period)
  // dest_clk = 133 MHz (7.5 ns period) — intentionally different domain
  localparam real SRC_PERIOD  = 5.0;
  localparam real DEST_PERIOD = 7.5;

  logic src_clk  = 0;
  logic dest_clk = 0;
  logic rst_n    = 0;

  always #(SRC_PERIOD/2.0)  src_clk  = ~src_clk;
  always #(DEST_PERIOD/2.0) dest_clk = ~dest_clk;

  // ── DUT I/O ───────────────────────────────────────────────────────────────────
  logic src_pulse  = 0;
  logic dest_level;

  cdc_pulse_sync #(.STAGES(3)) dut (
    .src_clk    (src_clk),
    .rst_n      (rst_n),
    .src_pulse  (src_pulse),
    .dest_clk   (dest_clk),
    .dest_level (dest_level)
  );

  // ── Watchdog ──────────────────────────────────────────────────────────────────
  initial begin
    #50_000;  // 50 µs
    $fatal(1, "WATCHDOG: simulation exceeded 50 µs without finishing.");
  end

  // ── Helpers ───────────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  // Issue a 1-cycle pulse on src domain
  task automatic send_pulse();
    @(posedge src_clk);
    #1;
    src_pulse = 1'b1;
    @(posedge src_clk);
    #1;
    src_pulse = 1'b0;
  endtask

  // Wait for dest_level to rise (at most max_dest_cycles)
  task automatic wait_dest_edge(input int max_cycles, output logic got_it);
    int cnt;
    got_it = 1'b0;
    for (cnt = 0; cnt < max_cycles; cnt++) begin
      @(posedge dest_clk);
      if (dest_level) begin
        got_it = 1'b1;
        return;
      end
    end
  endtask

  // Check: dest_level must be exactly 1 cycle wide (edge detect output)
  task automatic check_pulse_width(output logic ok);
    // Caller has already seen dest_level==1 on current dest_clk edge.
    // Verify it goes low on the next dest_clk edge.
    ok = 1'b0;
    @(posedge dest_clk);
    if (dest_level === 1'b0)
      ok = 1'b1;
  endtask

  function void chk(string desc, logic cond);
    if (cond) begin
      $display("  PASS: %s", desc);
      pass_cnt++;
    end else begin
      $display("  FAIL: %s  (dest_level=%0b)", desc, dest_level);
      fail_cnt++;
    end
  endfunction

  // ── Test stimulus ─────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_cdc_pulse_sync ===");

    // ── TC1: Reset — dest_level must be 0 after rst_n deasserted ─────────────
    rst_n = 0;
    repeat(5) @(posedge dest_clk);
    chk("TC1 reset: dest_level == 0", dest_level === 1'b0);

    // ── TC2: Release reset, still no pulse ──────────────────────────────────
    @(posedge src_clk); #1;
    rst_n = 1;
    repeat(10) @(posedge dest_clk);
    chk("TC2 post-reset idle: dest_level == 0", dest_level === 1'b0);

    // ── TC3: Single pulse → expect exactly one dest_level pulse ─────────────
    begin
      logic got;
      logic width_ok;
      send_pulse();
      wait_dest_edge(20, got);
      chk("TC3 single pulse: dest_level observed", got === 1'b1);
      if (got) begin
        check_pulse_width(width_ok);
        chk("TC3 single pulse: dest_level is 1-cycle wide", width_ok);
      end else begin
        fail_cnt++;
        $display("  FAIL: TC3 pulse width check skipped (no edge seen)");
      end
    end

    // Drain
    repeat(15) @(posedge dest_clk);

    // ── TC4: Two back-to-back pulses (one src cycle apart) ──────────────────
    begin
      logic got1, got2;
      // Send pulse 1
      send_pulse();
      wait_dest_edge(20, got1);
      chk("TC4a first of two pulses: dest_level observed", got1);
      if (got1) begin
        // Consume the 1-cycle pulse
        @(posedge dest_clk);
      end
      // Send pulse 2 shortly after
      repeat(3) @(posedge src_clk);
      send_pulse();
      wait_dest_edge(20, got2);
      chk("TC4b second of two pulses: dest_level observed", got2);
    end

    repeat(15) @(posedge dest_clk);

    // ── TC5: 5 consecutive pulses, each separated by 3 src cycles ───────────
    begin
      int obs;
      obs = 0;
      for (int i = 0; i < 5; i++) begin
        logic got;
        repeat(3) @(posedge src_clk);
        send_pulse();
        wait_dest_edge(25, got);
        if (got) obs++;
      end
      chk("TC5 5 spaced pulses: all 5 observed in dest domain", obs === 5);
    end

    repeat(15) @(posedge dest_clk);

    // ── TC6: Assert rst_n low, toggle should reset, no spurious edge ─────────
    begin
      // send a pulse first
      send_pulse();
      @(posedge src_clk); #1;
      // Assert reset immediately
      rst_n = 0;
      repeat(6) @(posedge dest_clk);
      chk("TC6 mid-flight reset: dest_level cleared to 0", dest_level === 1'b0);
      rst_n = 1;
      repeat(5) @(posedge dest_clk);
      chk("TC6 post-reset: dest_level stays 0", dest_level === 1'b0);
    end

    repeat(10) @(posedge dest_clk);

    // ── TC7: Reset then immediate pulse ─────────────────────────────────────
    begin
      logic got;
      rst_n = 0;
      repeat(3) @(posedge src_clk);
      rst_n = 1;
      @(posedge src_clk); #1;
      send_pulse();
      wait_dest_edge(20, got);
      chk("TC7 pulse immediately after reset release: dest_level observed", got);
    end

    repeat(15) @(posedge dest_clk);

    // ── TC8: No spurious edge when no pulse sent (long idle) ─────────────────
    begin
      int spurious;
      spurious = 0;
      for (int i = 0; i < 50; i++) begin
        @(posedge dest_clk);
        if (dest_level) spurious++;
      end
      chk("TC8 long idle: no spurious dest_level pulses", spurious === 0);
    end

    // ── TC9: Rapid pulses — at least STAGES+1 src cycles apart ──────────────
    begin
      int obs;
      obs = 0;
      for (int j = 0; j < 4; j++) begin
        logic got;
        // Min spacing: STAGES+1 = 4 src cycles between leading edges
        repeat(5) @(posedge src_clk);
        send_pulse();
        wait_dest_edge(25, got);
        if (got) obs++;
      end
      chk("TC9 minimum-spacing pulses: all 4 observed", obs === 4);
    end

    repeat(15) @(posedge dest_clk);

    // ── TC10: src_pulse held high for 2 cycles (should count as 2 toggles → 0 net) ─
    begin
      // Toggle FF toggles on each src_clk where src_pulse=1.
      // 2 src cycles of high → 2 toggles → net zero change.
      // So dest should see 0 net edges (or 2 edges if spacing allows propagation).
      // Behavioral expectation: toggle happens twice → even count → dest_level
      // should NOT fire (or fire twice and cancel).
      logic t_before;
      int obs;
      obs = 0;
      // Drain any outstanding
      repeat(20) @(posedge dest_clk);
      @(posedge src_clk); #1;
      src_pulse = 1'b1;
      repeat(2) @(posedge src_clk);
      src_pulse = 1'b0;
      // Monitor for 30 dest cycles
      for (int k = 0; k < 30; k++) begin
        @(posedge dest_clk);
        if (dest_level) obs++;
      end
      // 2 toggles may produce 0, 1, or 2 dest pulses depending on CDC timing.
      // Accept any count 0..2 (no spurious amplification).
      chk("TC10 double-high src: edge count <= 2", obs <= 2);
    end

    repeat(10) @(posedge dest_clk);

    // ── TC11: STAGES=3 → minimum propagation ≥ 3 dest cycles ────────────────
    begin
      int lat;
      logic found;
      lat   = 0;
      found = 0;
      send_pulse();
      for (int i = 0; i < 20 && !found; i++) begin
        @(posedge dest_clk);
        lat++;
        if (dest_level) found = 1;
      end
      chk("TC11 latency >= 3 dest cycles", found && lat >= 3);
    end

    repeat(10) @(posedge dest_clk);

    // ── TC12: Back-to-back reset-release-pulse stress ────────────────────────
    begin
      int obs;
      obs = 0;
      for (int r = 0; r < 3; r++) begin
        logic got;
        rst_n = 0;
        repeat(4) @(posedge src_clk);
        rst_n = 1;
        @(posedge src_clk); #1;
        send_pulse();
        wait_dest_edge(25, got);
        if (got) obs++;
      end
      chk("TC12 3× reset-release-pulse cycles: all 3 observed", obs === 3);
    end

    repeat(10) @(posedge dest_clk);

    // ── Summary ──────────────────────────────────────────────────────────────
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
      $finish(0);
    else
      $fatal(1, "tb_cdc_pulse_sync: %0d test(s) FAILED.", fail_cnt);
  end

endmodule
// ================================================================================
