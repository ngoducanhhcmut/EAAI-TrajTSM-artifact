// ================================================================================
// Testbench: tb_pp_mux.sv
// DUT: pp_mux — Ping-Pong Memory Multiplexer & Write Controller
// Spec: §1.2, §4.2b
// ================================================================================
`timescale 1ns/1ps

module tb_pp_mux;

  import planning_pkg::*;

  // ── Clock & reset ─────────────────────────────────────────────────────────────
  localparam real CLK_PERIOD = 5.0;  // 200 MHz
  logic clk   = 0;
  logic rst_n = 0;

  always #(CLK_PERIOD/2.0) clk = ~clk;

  // ── DUT I/O ───────────────────────────────────────────────────────────────────
  logic  [3:0] phase;
  logic        proj_phase_en;
  logic        bert_phase_en;

  logic [14:0] proj_wr_addr;
  logic  [7:0] proj_wr_data;
  logic        proj_wr_en;
  logic        proj_wr_ready;

  logic        bert_rd_sel;
  logic [14:0] bert_rd_addr;
  logic        bert_rd_en;
  logic  [7:0] bert_rd_data;

  logic        bert_wr_sel;
  logic [14:0] bert_wr_addr;
  logic  [7:0] bert_wr_data;
  logic        bert_wr_en;
  logic        bert_wr_ready;

  logic [14:0] pp_a_wr_addr, pp_a_rd_addr;
  logic  [7:0] pp_a_wr_data, pp_a_rd_data;
  logic        pp_a_wr_en,   pp_a_rd_en;

  logic [14:0] pp_b_wr_addr, pp_b_rd_addr;
  logic  [7:0] pp_b_wr_data, pp_b_rd_data;
  logic        pp_b_wr_en,   pp_b_rd_en;

  pp_mux dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .phase         (phase),
    .proj_phase_en (proj_phase_en),
    .bert_phase_en (bert_phase_en),
    .proj_wr_addr  (proj_wr_addr),
    .proj_wr_data  (proj_wr_data),
    .proj_wr_en    (proj_wr_en),
    .proj_wr_ready (proj_wr_ready),
    .bert_rd_sel   (bert_rd_sel),
    .bert_rd_addr  (bert_rd_addr),
    .bert_rd_en    (bert_rd_en),
    .bert_rd_data  (bert_rd_data),
    .bert_wr_sel   (bert_wr_sel),
    .bert_wr_addr  (bert_wr_addr),
    .bert_wr_data  (bert_wr_data),
    .bert_wr_en    (bert_wr_en),
    .bert_wr_ready (bert_wr_ready),
    .pp_a_wr_addr  (pp_a_wr_addr),
    .pp_a_wr_data  (pp_a_wr_data),
    .pp_a_wr_en    (pp_a_wr_en),
    .pp_a_rd_addr  (pp_a_rd_addr),
    .pp_a_rd_data  (pp_a_rd_data),
    .pp_a_rd_en    (pp_a_rd_en),
    .pp_b_wr_addr  (pp_b_wr_addr),
    .pp_b_wr_data  (pp_b_wr_data),
    .pp_b_wr_en    (pp_b_wr_en),
    .pp_b_rd_addr  (pp_b_rd_addr),
    .pp_b_rd_data  (pp_b_rd_data),
    .pp_b_rd_en    (pp_b_rd_en)
  );

  // ── Simple memory models for pp_A and pp_B ───────────────────────────────────
  logic [7:0] mem_a [0:32767];
  logic [7:0] mem_b [0:32767];

  // Drive read-data from models (combinational for simplicity)
  assign pp_a_rd_data = mem_a[pp_a_rd_addr];
  assign pp_b_rd_data = mem_b[pp_b_rd_addr];

  // Capture writes to models
  always_comb begin
    if (pp_a_wr_en) mem_a[pp_a_wr_addr] = pp_a_wr_data;
    if (pp_b_wr_en) mem_b[pp_b_wr_addr] = pp_b_wr_data;
  end

  // ── Watchdog ──────────────────────────────────────────────────────────────────
  initial begin
    #50_000;
    $fatal(1, "WATCHDOG: simulation exceeded 50 µs.");
  end

  // ── Scoreboard ────────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  function void chk(string desc, logic cond);
    if (cond) begin $display("  PASS: %s", desc); pass_cnt++; end
    else      begin $display("  FAIL: %s", desc); fail_cnt++; end
  endfunction

  // ── Default drive ─────────────────────────────────────────────────────────────
  task automatic idle_all();
    phase         = 4'd0;
    proj_phase_en = 1'b0;
    bert_phase_en = 1'b0;
    proj_wr_addr  = '0;
    proj_wr_data  = '0;
    proj_wr_en    = 1'b0;
    bert_rd_sel   = 1'b0;
    bert_rd_addr  = '0;
    bert_rd_en    = 1'b0;
    bert_wr_sel   = 1'b0;
    bert_wr_addr  = '0;
    bert_wr_data  = '0;
    bert_wr_en    = 1'b0;
  endtask

  // ── Test ─────────────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_pp_mux ===");
    idle_all();
    for (int i=0; i<32768; i++) begin mem_a[i]='0; mem_b[i]='0; end

    // TC1: Reset — all enables de-asserted, ready signals defined
    repeat(4) @(posedge clk);
    chk("TC1 reset: pp_a_wr_en==0", pp_a_wr_en === 1'b0);
    chk("TC1 reset: pp_b_wr_en==0", pp_b_wr_en === 1'b0);
    chk("TC1 reset: pp_a_rd_en==0", pp_a_rd_en === 1'b0);
    chk("TC1 reset: pp_b_rd_en==0", pp_b_rd_en === 1'b0);
    @(posedge clk); #1; rst_n = 1;
    repeat(2) @(posedge clk);

    // ─── PROJ_PHASE tests ────────────────────────────────────────────────────
    // TC2: PROJ_PHASE — proj_wr_ready asserted
    begin
      @(posedge clk); #1;
      proj_phase_en = 1'b1;
      bert_phase_en = 1'b0;
      phase         = 4'd2;
      #1;  // combinational settle
      chk("TC2 PROJ_PHASE: proj_wr_ready==1", proj_wr_ready === 1'b1);
    end

    // TC3: PROJ_PHASE — projector write forwarded to pp_A
    begin
      @(posedge clk); #1;
      proj_wr_addr = 15'h0005;
      proj_wr_data = 8'hAB;
      proj_wr_en   = 1'b1;
      #1;
      chk("TC3 PROJ write→pp_A wr_en",    pp_a_wr_en   === 1'b1);
      chk("TC3 PROJ write→pp_A wr_addr",  pp_a_wr_addr === 15'h0005);
      chk("TC3 PROJ write→pp_A wr_data",  pp_a_wr_data === 8'hAB);
      chk("TC3 PROJ write: pp_B untouched", pp_b_wr_en === 1'b0);
      @(posedge clk); #1;
      proj_wr_en = 1'b0;
    end

    // TC4: PROJ_PHASE — bert_wr_ready is 0 or 1 depending on spec
    //      (spec: bert_wr_ready = ~proj_owns_pp_a || !bert_phase_en)
    //      With proj_phase_en=1, bert_phase_en=0 → bert_wr_ready = !0 || !0 = 1
    begin
      #1;
      chk("TC4 PROJ_PHASE+no-BERT: bert_wr_ready==1",
          bert_wr_ready === 1'b1);
    end

    // TC5: PROJ_PHASE + BERT_PHASE simultaneously — bert_wr_ready must be 0
    begin
      @(posedge clk); #1;
      bert_phase_en = 1'b1;
      #1;
      chk("TC5 PROJ+BERT phase: bert_wr_ready==0", bert_wr_ready === 1'b0);
      bert_phase_en = 1'b0;
    end

    // TC6: PROJ_PHASE — pp_B write enable NOT asserted (projector owns pp_A)
    begin
      @(posedge clk); #1;
      proj_wr_en = 1'b1; proj_wr_addr = 15'h0010; proj_wr_data = 8'hCD;
      #1;
      chk("TC6 PROJ_PHASE: pp_b_wr_en==0", pp_b_wr_en === 1'b0);
      @(posedge clk); #1; proj_wr_en = 1'b0;
    end

    // Switch to BERT_PHASE
    @(posedge clk); #1;
    proj_phase_en = 1'b0;
    bert_phase_en = 1'b1;
    phase         = 4'd3;

    // TC7: BERT_PHASE — BERT reads from pp_A (bert_rd_sel=0)
    begin
      @(posedge clk); #1;
      // Preset mem_a with known value
      mem_a[15'h0020] = 8'h77;
      bert_rd_sel  = 1'b0;
      bert_rd_addr = 15'h0020;
      bert_rd_en   = 1'b1;
      #1;
      chk("TC7 BERT read pp_A: pp_a_rd_en==1",   pp_a_rd_en   === 1'b1);
      chk("TC7 BERT read pp_A: pp_b_rd_en==0",   pp_b_rd_en   === 1'b0);
      chk("TC7 BERT read pp_A: addr forwarded",  pp_a_rd_addr === 15'h0020);
      chk("TC7 BERT read pp_A: data returned",   bert_rd_data === 8'h77);
      @(posedge clk); #1; bert_rd_en = 1'b0;
    end

    // TC8: BERT_PHASE — BERT reads from pp_B (bert_rd_sel=1)
    begin
      mem_b[15'h0030] = 8'h55;
      @(posedge clk); #1;
      bert_rd_sel  = 1'b1;
      bert_rd_addr = 15'h0030;
      bert_rd_en   = 1'b1;
      #1;
      chk("TC8 BERT read pp_B: pp_b_rd_en==1",   pp_b_rd_en   === 1'b1);
      chk("TC8 BERT read pp_B: pp_a_rd_en==0",   pp_a_rd_en   === 1'b0);
      chk("TC8 BERT read pp_B: data returned",   bert_rd_data === 8'h55);
      @(posedge clk); #1; bert_rd_en = 1'b0;
    end

    // TC9: BERT_PHASE — BERT writes to pp_B (bert_wr_sel=1)
    begin
      @(posedge clk); #1;
      bert_wr_sel  = 1'b1;
      bert_wr_addr = 15'h0040;
      bert_wr_data = 8'hEE;
      bert_wr_en   = 1'b1;
      #1;
      chk("TC9 BERT write pp_B: pp_b_wr_en==1",  pp_b_wr_en   === 1'b1);
      chk("TC9 BERT write pp_B: pp_b_wr_addr",   pp_b_wr_addr === 15'h0040);
      chk("TC9 BERT write pp_B: pp_b_wr_data",   pp_b_wr_data === 8'hEE);
      chk("TC9 BERT write pp_B: pp_a not driven", pp_a_wr_en  === 1'b0);
      @(posedge clk); #1; bert_wr_en = 1'b0;
    end

    // TC10: BERT_PHASE — BERT writes to pp_A (bert_wr_sel=0, proj inactive)
    begin
      @(posedge clk); #1;
      proj_phase_en = 1'b0;
      bert_wr_sel   = 1'b0;
      bert_wr_addr  = 15'h0050;
      bert_wr_data  = 8'h33;
      bert_wr_en    = 1'b1;
      #1;
      chk("TC10 BERT write pp_A: pp_a_wr_en==1",  pp_a_wr_en   === 1'b1);
      chk("TC10 BERT write pp_A: pp_a_wr_addr",   pp_a_wr_addr === 15'h0050);
      chk("TC10 BERT write pp_A: pp_a_wr_data",   pp_a_wr_data === 8'h33);
      @(posedge clk); #1; bert_wr_en = 1'b0;
    end

    // TC11: Idle — no enables asserted anywhere
    begin
      idle_all();
      @(posedge clk); #1;
      #1;
      chk("TC11 idle: pp_a_wr_en==0", pp_a_wr_en === 1'b0);
      chk("TC11 idle: pp_b_wr_en==0", pp_b_wr_en === 1'b0);
      chk("TC11 idle: pp_a_rd_en==0", pp_a_rd_en === 1'b0);
      chk("TC11 idle: pp_b_rd_en==0", pp_b_rd_en === 1'b0);
    end

    // TC12: PROJ_PHASE: proj_wr_en=0 → pp_a_wr_en must remain 0
    begin
      @(posedge clk); #1;
      proj_phase_en = 1'b1;
      proj_wr_en    = 1'b0;  // not writing
      #1;
      chk("TC12 PROJ_PHASE no-write: pp_a_wr_en==0", pp_a_wr_en === 1'b0);
      proj_phase_en = 1'b0;
    end

    // TC13: BERT reads pp_A — bert_rd_en=0 → pp_a_rd_en=0
    begin
      @(posedge clk); #1;
      bert_phase_en = 1'b1;
      bert_rd_sel   = 1'b0;
      bert_rd_en    = 1'b0;  // disabled
      bert_rd_addr  = 15'h0100;
      #1;
      chk("TC13 BERT rd disabled: pp_a_rd_en==0", pp_a_rd_en === 1'b0);
      bert_rd_en = 1'b0;
    end

    // TC14: Boundary addresses propagated correctly (max 15-bit addr = 0x7FFF)
    begin
      mem_a[15'h7FFF] = 8'hFF;
      @(posedge clk); #1;
      bert_phase_en = 1'b1; proj_phase_en = 1'b0;
      bert_rd_sel   = 1'b0;
      bert_rd_addr  = 15'h7FFF;
      bert_rd_en    = 1'b1;
      #1;
      chk("TC14 boundary addr 0x7FFF: data=0xFF", bert_rd_data === 8'hFF);
      @(posedge clk); #1; bert_rd_en = 1'b0;
    end

    // ── Summary ──────────────────────────────────────────────────────────────
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
      $finish(0);
    else
      $fatal(1, "tb_pp_mux: %0d test(s) FAILED.", fail_cnt);
  end

endmodule
// ================================================================================
