// ================================================================================
// Testbench: tb_pp_mux.sv (Upgraded Version)
// DUT: pp_mux — Ping-Pong Memory Multiplexer & Write Controller
// ================================================================================
`timescale 1ns/1ps

module tb_pp_mux_adv;
  import planning_pkg::*;

  // ── Clock & reset ─────────────────────────────────────────────────────────────
  localparam real CLK_PERIOD = 5.0; // 200 MHz
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

  pp_mux dut (.*); // Auto-connect matching port names

  // ── Simple memory models for pp_A and pp_B ───────────────────────────────────
  logic [7:0] mem_a [0:32767];
  logic [7:0] mem_b [0:32767];

  assign pp_a_rd_data = mem_a[pp_a_rd_addr];
  assign pp_b_rd_data = mem_b[pp_b_rd_addr];

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
    if (cond) begin 
        $display("  [PASS] %s", desc); 
        pass_cnt++;
    end else begin 
        $error("  [FAIL] %s", desc); 
        fail_cnt++;
    end
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

  // ── Test Sequence ─────────────────────────────────────────────────────────────
  initial begin
    $display("=================================================");
    $display("=== tb_pp_mux: STARTING COMPREHENSIVE TESTS ===");
    $display("=================================================");
    
    idle_all();
    for (int i=0; i<32768; i++) begin mem_a[i]='0; mem_b[i]='0; end

    // ----------------------------------------------------------------
    // GROUP 1: RESET & BASIC IDLE
    // ----------------------------------------------------------------
    repeat(4) @(posedge clk);
    chk("TC01 reset: All Write Enables == 0", (pp_a_wr_en == 0) && (pp_b_wr_en == 0));
    chk("TC01 reset: All Read Enables == 0",  (pp_a_rd_en == 0) && (pp_b_rd_en == 0));
    
    @(posedge clk); #1; rst_n = 1;
    repeat(2) @(posedge clk);

    // ----------------------------------------------------------------
    // GROUP 2: BASIC PROJ_PHASE & BERT_PHASE (Existing logic check)
    // ----------------------------------------------------------------
    @(posedge clk); #1;
    proj_phase_en = 1'b1; bert_phase_en = 1'b0; phase = 4'd2;
    #1;
    chk("TC02 PROJ_PHASE: proj_wr_ready == 1", proj_wr_ready === 1'b1);

    @(posedge clk); #1;
    proj_wr_addr = 15'h0005; proj_wr_data = 8'hAB; proj_wr_en = 1'b1;
    #1;
    chk("TC03 PROJ write -> pp_A correct", (pp_a_wr_en == 1) && (pp_a_wr_addr == 15'h0005) && (pp_a_wr_data == 8'hAB));
    chk("TC03 PROJ write -> pp_B isolated", pp_b_wr_en == 0);
    
    @(posedge clk); #1; proj_wr_en = 0; idle_all();

    // ----------------------------------------------------------------
    // GROUP 3: CONCURRENCY & COLLISION RESOLUTION (The Core Upgrade)
    // ----------------------------------------------------------------
    $display("--- Group 3: Concurrency & Collision ---");
    
    // TC04: Simultaneous Independent Writes (PROJ writes A, BERT writes B)
    @(posedge clk); #1;
    proj_phase_en = 1'b1; bert_phase_en = 1'b1; // Both phases active internally
    
    proj_wr_en = 1'b1; proj_wr_addr = 15'h1111; proj_wr_data = 8'hAA;
    bert_wr_en = 1'b1; bert_wr_sel  = 1'b1; bert_wr_addr = 15'h2222; bert_wr_data = 8'hBB;
    #1;
    chk("TC04 Sync Write: PROJ -> pp_A Success", (pp_a_wr_en == 1) && (pp_a_wr_data == 8'hAA));
    chk("TC04 Sync Write: BERT -> pp_B Success", (pp_b_wr_en == 1) && (pp_b_wr_data == 8'hBB));

    // TC05: Write Collision on pp_A (PROJ vs BERT -> PROJ MUST WIN)
    @(posedge clk); #1;
    proj_wr_en = 1'b1; proj_wr_addr = 15'h3333; proj_wr_data = 8'hCC;
    bert_wr_en = 1'b1; bert_wr_sel  = 1'b0; bert_wr_addr = 15'h4444; bert_wr_data = 8'hDD; // BERT tries to write A
    #1;
    chk("TC05 Collision: PROJ wins pp_A wr_en", pp_a_wr_en === 1'b1);
    chk("TC05 Collision: PROJ wins pp_A data",  pp_a_wr_data === 8'hCC);
    chk("TC05 Collision: BERT data rejected",   pp_a_wr_data !== 8'hDD);
    chk("TC05 Collision: pp_B remains untouched", pp_b_wr_en === 1'b0);

    // TC06: Ping-Pong True Operation (PROJ Writes A, BERT Reads B simultaneously)
    @(posedge clk); #1;
    mem_b[15'h5555] = 8'hEE; // Pre-load B
    proj_wr_en = 1'b1; proj_wr_addr = 15'h6666; proj_wr_data = 8'hFF; // PROJ writes A
    bert_wr_en = 1'b0; // Turn off BERT write
    bert_rd_en = 1'b1; bert_rd_sel = 1'b1; bert_rd_addr = 15'h5555;   // BERT reads B
    #1;
    chk("TC06 Ping-Pong: PROJ writes A successfully", (pp_a_wr_en == 1) && (pp_a_wr_data == 8'hFF));
    chk("TC06 Ping-Pong: BERT reads B successfully",  (pp_b_rd_en == 1) && (bert_rd_data == 8'hEE));
    chk("TC06 Ping-Pong: Cross-talk prevention",      (pp_a_rd_en == 0) && (pp_b_wr_en == 0));

    // TC07: Ping-Pong True Operation (BERT Writes B, BERT Reads A simultaneously)
    @(posedge clk); #1;
    proj_phase_en = 1'b0; // Proj phase over
    proj_wr_en    = 1'b0;
    mem_a[15'h7777] = 8'h42; // Pre-load A
    
    bert_wr_en = 1'b1; bert_wr_sel = 1'b1; bert_wr_addr = 15'h8888; bert_wr_data = 8'h99; // BERT writes B
    bert_rd_en = 1'b1; bert_rd_sel = 1'b0; bert_rd_addr = 15'h7777;                       // BERT reads A
    #1;
    chk("TC07 BERT Internal Ping-Pong: Writes B", (pp_b_wr_en == 1) && (pp_b_wr_data == 8'h99));
    chk("TC07 BERT Internal Ping-Pong: Reads A",  (pp_a_rd_en == 1) && (bert_rd_data == 8'h42));

    @(posedge clk); #1; idle_all();

    // ----------------------------------------------------------------
    // GROUP 4: BOUNDARY & EDGE CASES
    // ----------------------------------------------------------------
    $display("--- Group 4: Boundary & Edge Cases ---");
    
    // TC08: Maximum Address boundaries (15-bit -> 0x7FFF)
    @(posedge clk); #1;
    bert_phase_en = 1'b1;
    mem_a[15'h7FFF] = 8'hDE;
    bert_rd_sel  = 1'b0; bert_rd_addr = 15'h7FFF; bert_rd_en = 1'b1;
    #1;
    chk("TC08 Max Addr 0x7FFF Read", bert_rd_data === 8'hDE);

    // TC09: Ready Flag Stall Logic Check
    @(posedge clk); #1;
    proj_phase_en = 1'b1; bert_phase_en = 1'b1;
    #1;
    // NOTE: According to current RTL: bert_wr_ready = ~proj_owns_pp_a || !bert_phase_en;
    // This implies if PROJ is active, BERT is told NOT READY, even if BERT just wants to write to B.
    chk("TC09 Ready Flag: BERT is stalled when PROJ is active", bert_wr_ready === 1'b0);

    // ── Summary ──────────────────────────────────────────────────────────────
    $display("=================================================");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    $display("=================================================");
    
    if (fail_cnt == 0) begin
      $display("=> ALL TESTS PASSED. Ready for Synthesis.");
      $finish(0);
    end else begin
      $fatal(1, "=> tb_pp_mux: %0d test(s) FAILED. Please check waveforms.", fail_cnt);
    end
  end

endmodule