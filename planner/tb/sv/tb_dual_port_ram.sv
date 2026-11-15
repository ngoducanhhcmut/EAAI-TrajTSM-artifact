// ================================================================================
// Testbench: tb_dual_port_ram.sv
// DUT: dual_port_ram — Parameterized True Dual-Port BRAM
// ================================================================================
`timescale 1ns/1ps

module tb_dual_port_ram;

  // ── Parameters ────────────────────────────────────────────────────────────────
  localparam int DW   = 32;
  localparam int DEPTH = 64;
  localparam int AW   = $clog2(DEPTH);  // 6

  // ── Clocks & resets ───────────────────────────────────────────────────────────
  localparam real CLK_PERIOD = 5.0;  // 200 MHz
  logic clk_a = 0, clk_b = 0;
  logic rst_a_n = 0, rst_b_n = 0;

  always #(CLK_PERIOD/2.0) clk_a = ~clk_a;
  always #(CLK_PERIOD/2.0) clk_b = ~clk_b;  // same freq, slight skew possible

  // ── DUT I/O ───────────────────────────────────────────────────────────────────
  logic              ena, wea;
  logic [AW-1:0]    addra;
  logic [DW-1:0]    dina, douta;

  logic              enb, web;
  logic [AW-1:0]    addrb;
  logic [DW-1:0]    dinb, doutb;

  dual_port_ram #(
    .DATA_WIDTH       (DW),
    .DEPTH            (DEPTH),
    .REGISTERED_OUTPUT(1),
    .COLLISION_MODE   ("WRITE_FIRST")
  ) dut (
    .clk_a  (clk_a),  .rst_a_n (rst_a_n),
    .ena    (ena),    .wea     (wea),
    .addra  (addra),  .dina    (dina),    .douta (douta),
    .clk_b  (clk_b),  .rst_b_n (rst_b_n),
    .enb    (enb),    .web     (web),
    .addrb  (addrb),  .dinb    (dinb),    .doutb (doutb)
  );

  // ── Watchdog ──────────────────────────────────────────────────────────────────
  initial begin
    #50_000;
    $fatal(1, "WATCHDOG: simulation exceeded 50 µs.");
  end

  // ── Scoreboard ────────────────────────────────────────────────────────────────
  logic [DW-1:0] ref_mem [DEPTH];
  int pass_cnt = 0;
  int fail_cnt = 0;

  function void chk(string desc, logic cond);
    if (cond) begin $display("  PASS: %s", desc); pass_cnt++; end
    else      begin $display("  FAIL: %s", desc); fail_cnt++; end
  endfunction

  // ── Write via port A helper ───────────────────────────────────────────────────
  task automatic port_a_write(input logic [AW-1:0] addr, input logic [DW-1:0] data);
    @(posedge clk_a); #1;
    ena = 1; wea = 1; addra = addr; dina = data;
    @(posedge clk_a); #1;
    ena = 0; wea = 0;
    ref_mem[addr] = data;
  endtask

  // ── Read via port A helper (latency=2 with OREG) ─────────────────────────────
  task automatic port_a_read(input logic [AW-1:0] addr, output logic [DW-1:0] data);
    @(posedge clk_a); #1;
    ena = 1; wea = 0; addra = addr;
    @(posedge clk_a); #1;  // RAM stage
    @(posedge clk_a); #1;  // OREG stage
    data = douta;
    ena = 0;
  endtask

  // ── Write via port B helper ───────────────────────────────────────────────────
  task automatic port_b_write(input logic [AW-1:0] addr, input logic [DW-1:0] data);
    @(posedge clk_b); #1;
    enb = 1; web = 1; addrb = addr; dinb = data;
    @(posedge clk_b); #1;
    enb = 0; web = 0;
    ref_mem[addr] = data;
  endtask

  // ── Read via port B helper ────────────────────────────────────────────────────
  task automatic port_b_read(input logic [AW-1:0] addr, output logic [DW-1:0] data);
    @(posedge clk_b); #1;
    enb = 1; web = 0; addrb = addr;
    @(posedge clk_b); #1;
    @(posedge clk_b); #1;
    data = doutb;
    enb = 0;
  endtask

  // ── Test ─────────────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_dual_port_ram ===");
    // Init
    ena=0; wea=0; addra='0; dina='0;
    enb=0; web=0; addrb='0; dinb='0;
    for (int i=0; i<DEPTH; i++) ref_mem[i] = '0;

    // TC1: Release reset — BRAM output registers have no reset, outputs are
    // unpredictable until first read. Just verify DUT is alive (no assertion).
    @(posedge clk_a); #1; rst_a_n = 1; rst_b_n = 1;
    @(posedge clk_a); #1;
    // No output check here: BRAM output registers are not reset by rst_a_n/rst_b_n

    // TC2: Port A write, Port A read-back (WRITE_FIRST)
    begin
      logic [DW-1:0] rdat;
      port_a_write(6'd0, 32'hDEAD_BEEF);
      port_a_read (6'd0, rdat);
      chk("TC2 port-A wr/rd addr0: read matches write", rdat === 32'hDEAD_BEEF);
    end

    // TC3: Port B write, Port B read-back
    begin
      logic [DW-1:0] rdat;
      port_b_write(6'd1, 32'hCAFE_BABE);
      port_b_read (6'd1, rdat);
      chk("TC3 port-B wr/rd addr1: read matches write", rdat === 32'hCAFE_BABE);
    end

    // TC4: Port A write, Port B read (cross-port)
    begin
      logic [DW-1:0] rdat;
      port_a_write(6'd5, 32'h1234_5678);
      repeat(3) @(posedge clk_b); // allow propagation
      port_b_read(6'd5, rdat);
      chk("TC4 cross-port A-wr/B-rd addr5", rdat === 32'h1234_5678);
    end

    // TC5: Port B write, Port A read (cross-port)
    begin
      logic [DW-1:0] rdat;
      port_b_write(6'd10, 32'hABCD_EF01);
      repeat(3) @(posedge clk_a);
      port_a_read(6'd10, rdat);
      chk("TC5 cross-port B-wr/A-rd addr10", rdat === 32'hABCD_EF01);
    end

    // TC6: Sequential writes to multiple addresses via port A, then verify via B
    begin
      logic [DW-1:0] rdat;
      int ok;
      ok = 1;
      for (int i = 0; i < 8; i++) begin
        port_a_write(AW'(i+16), DW'(32'hA000_0000 | i));
      end
      repeat(4) @(posedge clk_b);
      for (int i = 0; i < 8; i++) begin
        port_b_read(AW'(i+16), rdat);
        if (rdat !== DW'(32'hA000_0000 | i)) ok = 0;
      end
      chk("TC6 burst wr portA, verify portB (8 locations)", ok);
    end

    // TC7: Overwrite — last write wins
    begin
      logic [DW-1:0] rdat;
      port_a_write(6'd20, 32'h1111_1111);
      port_a_write(6'd20, 32'h2222_2222);
      port_a_read (6'd20, rdat);
      chk("TC7 overwrite: last value retained", rdat === 32'h2222_2222);
    end

    // TC8: Boundary address (addr=0) write and read
    begin
      logic [DW-1:0] rdat;
      port_b_write(6'd0, 32'hFFFF_FFFF);
      repeat(3) @(posedge clk_a);
      port_a_read(6'd0, rdat);
      chk("TC8 boundary addr=0: read after B-write", rdat === 32'hFFFF_FFFF);
    end

    // TC9: Boundary address (addr=DEPTH-1) write and read
    begin
      logic [DW-1:0] rdat;
      port_a_write(AW'(DEPTH-1), 32'h0000_0001);
      repeat(3) @(posedge clk_b);
      port_b_read(AW'(DEPTH-1), rdat);
      chk("TC9 boundary addr=DEPTH-1: read correct", rdat === 32'h0000_0001);
    end

    // TC10: ena=0 — read should NOT update output
    begin
      logic [DW-1:0] rdat_before, rdat_after;
      // Write known value
      port_a_write(6'd30, 32'hBEEF_CAFE);
      // Read it once to prime OREG
      port_a_read(6'd30, rdat_before);
      // Now assert ena=0 and try to read a different address
      @(posedge clk_a); #1;
      ena = 0; wea = 0; addra = 6'd0;  // different addr, but ena=0
      repeat(4) @(posedge clk_a);
      rdat_after = douta;
      // Output should not change (or be 0 from OREG reset) — it must NOT show addr0
      // With ena=0 the RAM does not update douta_int; OREG holds last value
      // The test: rdat_after must still be rdat_before (no new read issued)
      chk("TC10 ena=0: output not updated on disabled port",
          rdat_after === rdat_before || rdat_after === '0);
    end

    // TC11: All-zeros data write and read
    begin
      logic [DW-1:0] rdat;
      port_a_write(6'd40, 32'h0000_0000);
      port_a_read (6'd40, rdat);
      chk("TC11 all-zeros data: read back correct", rdat === 32'h0);
    end

    // TC12: All-ones data write and read
    begin
      logic [DW-1:0] rdat;
      port_b_write(6'd41, 32'hFFFF_FFFF);
      repeat(3) @(posedge clk_b);
      port_b_read(6'd41, rdat);
      chk("TC12 all-ones data: read back correct", rdat === 32'hFFFF_FFFF);
    end

    // ── Summary ──────────────────────────────────────────────────────────────
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
      $finish(0);
    else
      $fatal(1, "tb_dual_port_ram: %0d test(s) FAILED.", fail_cnt);
  end

endmodule
// ================================================================================
