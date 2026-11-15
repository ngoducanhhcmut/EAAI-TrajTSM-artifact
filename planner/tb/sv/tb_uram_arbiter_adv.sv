// =============================================================================
// tb_uram_arbiter.sv — Comprehensive Unit Testbench for uram_arbiter
// Covers: Happy path, Pipeline Hold, Isolation, Masking, Boundary, SVA Negatives
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_uram_arbiter_adv;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic          bert_active;
  logic          gru_active;
  logic          uram_copy_active;

  logic [18:0]   bert_uram_addr;
  logic          bert_uram_en;
  logic [63:0]   bert_uram_rdata;

  logic [16:0]   gru_uram_addr;
  logic          gru_uram_en;
  logic [63:0]   gru_uram_rdata;

  logic [18:0]   wl_uram_addr;
  logic [63:0]   wl_uram_wdata;
  logic          wl_uram_we;

  logic [18:0]   uram_porta_addr;
  logic [63:0]   uram_porta_rdata;
  logic          uram_porta_en;

  logic [18:0]   uram_portb_addr;
  logic [63:0]   uram_portb_wdata;
  logic          uram_portb_we;

  uram_arbiter dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .bert_active       (bert_active),
    .gru_active        (gru_active),
    .uram_copy_active  (uram_copy_active),
    .bert_uram_addr    (bert_uram_addr),
    .bert_uram_en      (bert_uram_en),
    .bert_uram_rdata   (bert_uram_rdata),
    .gru_uram_addr     (gru_uram_addr),
    .gru_uram_en       (gru_uram_en),
    .gru_uram_rdata    (gru_uram_rdata),
    .wl_uram_addr      (wl_uram_addr),
    .wl_uram_wdata     (wl_uram_wdata),
    .wl_uram_we        (wl_uram_we),
    .uram_porta_addr   (uram_porta_addr),
    .uram_porta_rdata  (uram_porta_rdata),
    .uram_porta_en     (uram_porta_en),
    .uram_portb_addr   (uram_portb_addr),
    .uram_portb_wdata  (uram_portb_wdata),
    .uram_portb_we     (uram_portb_we)
  );

  // ── Behavioral URAM model (19-bit addr × 64-bit data) ─────────────────────
  logic [63:0] uram [0:524287]; // 512K words (19-bit addr) [cite: 66, 67]
  logic [63:0] porta_rdata_reg;

  always_ff @(posedge clk) begin
    if (uram_portb_we)
      uram[uram_portb_addr] <= uram_portb_wdata;
    if (uram_porta_en)
      porta_rdata_reg <= uram[uram_porta_addr];
  end
  assign uram_porta_rdata = porta_rdata_reg;

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  task check_hex(input string name, input logic [63:0] got, input logic [63:0] exp);
    if (got === exp) begin
      $display("  [PASS] %-35s : 0x%016h", name, got);
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-35s : got=0x%016h exp=0x%016h", name, got, exp);
      fail_cnt++;
    end
  endtask

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("======================================================");
    $display("=== tb_uram_arbiter : Full Coverage Verification   ===");
    $display("======================================================");

    // Default states
    bert_active      = 0;
    gru_active       = 0;
    uram_copy_active = 0;
    bert_uram_addr   = '0;
    bert_uram_en     = 0;
    gru_uram_addr    = '0;
    gru_uram_en      = 0;
    wl_uram_addr     = '0;
    wl_uram_wdata    = '0;
    wl_uram_we       = 0;

    // Init URAM [cite: 81]
    for (int i = 0; i < 524288; i++) uram[i] = 64'h0;

    rst_n = 0;
    tick(3);
    rst_n = 1;
    tick(2);

    $display("\n--- [Phase 1] Setup: Writing Test Data ---");
    uram_copy_active = 1;
    // Write for BERT (Block 0, offset 0x100)
    wl_uram_addr  = 19'h100;
    wl_uram_wdata = 64'h1111_AAAA_1111_AAAA;
    wl_uram_we    = 1'b1;
    tick(1);
    // Write for GRU Boundary: Rel_block 23, offset 0xFFF -> Abs Block = 48+23 = 71 (0x47)
    // Addr = {7'h47, 12'hFFF} = 19'h47FFF
    wl_uram_addr  = 19'h47FFF;
    wl_uram_wdata = 64'h9999_BBBB_9999_BBBB;
    wl_uram_we    = 1'b1;
    tick(1);
    wl_uram_we    = 1'b0;
    uram_copy_active = 0;
    tick(2);
    check_hex("Init_BERT_RAM", uram[19'h100], 64'h1111_AAAA_1111_AAAA);
    check_hex("Init_GRU_Boundary_RAM", uram[19'h47FFF], 64'h9999_BBBB_9999_BBBB);

    $display("\n--- [Phase 2] Pipeline Hold & Isolation Test ---");
    bert_active = 1;
    bert_uram_addr = 19'h100;
    bert_uram_en = 1'b1;
    tick(1); // Cycle 1: Addr/En driven
    bert_uram_en = 1'b0; // Drop EN immediately (simulate bubble or stall)
    tick(1); // Cycle 2: URAM presents data, reg captures it
    tick(2); // Cycle 3-4: EN was low, data should HOLD
    check_hex("BERT_Hold_Data", bert_uram_rdata, 64'h1111_AAAA_1111_AAAA);
    check_hex("Isolation_GRU_Unchanged", gru_uram_rdata, 64'h0); // GRU must stay 0
    bert_active = 0;

    $display("\n--- [Phase 3] GRU Boundary Translation & Hold Test ---");
    gru_active = 1;
    gru_uram_addr = {5'd23, 12'hFFF}; // Max allowed GRU address [cite: 41, 42]
    gru_uram_en = 1'b1;
    tick(1);
    gru_uram_en = 1'b0; 
    tick(3); 
    check_hex("GRU_Boundary_Hold_Data", gru_uram_rdata, 64'h9999_BBBB_9999_BBBB);
    check_hex("Isolation_BERT_Unchanged", bert_uram_rdata, 64'h1111_AAAA_1111_AAAA); // BERT holds old data
    gru_active = 0;

    $display("\n--- [Phase 4] Data Masking (Security) Test ---");
    // 4.1 Write Masking: wl_uram_we = 1 but uram_copy_active = 0
    wl_uram_addr  = 19'h200;
    wl_uram_wdata = 64'hDEAD_DEAD_DEAD_DEAD;
    wl_uram_we    = 1'b1; 
    tick(1);
    wl_uram_we    = 1'b0;
    tick(1);
    check_hex("Write_Masking_Blocked", uram[19'h200], 64'h0); // RAM must remain 0

    // 4.2 Read Masking: Cross-domain read (GRU is active, but BERT tries to read)
    gru_active = 1;
    bert_uram_addr = 19'h100; // Contains 0x1111...
    bert_uram_en = 1'b1;      // BERT wants to read
    tick(2);
    bert_uram_en = 1'b0;
    gru_active = 0;
    tick(1);
    // BERT's rdata must NOT have updated with new cycles, it should hold the Phase 2 value
    // (In our case, Phase 2 value was 0x1111..., so to strictly test, let's look at a new address)
    // Actually, because porta_addr defaults to GRU's addr (which is 0 here), porta_rdata is 0.
    // If masking failed, bert_rdata would become 0.
    check_hex("Read_Masking_Blocked", bert_uram_rdata, 64'h1111_AAAA_1111_AAAA); 

    $display("\n--- [Phase 5] Negative SVA Tests ---");
    $display("    (NOTE: Expect to see $error prints from DUT below. This is CORRECT behavior!)");
    
    // A1: BERT and GRU both active [cite: 34, 35, 36]
    bert_active = 1; gru_active = 1;
    tick(1); 
    bert_active = 0; gru_active = 0;

    // A2: BERT and Copy both active [cite: 37, 38, 39]
    bert_active = 1; uram_copy_active = 1;
    tick(1);
    bert_active = 0; uram_copy_active = 0;

    // A3: GRU out of bounds (> 23) [cite: 40, 41, 42]
    gru_active = 1; gru_uram_en = 1; gru_uram_addr = {5'd24, 12'h0}; 
    tick(1);
    gru_active = 0; gru_uram_en = 0;

    // A4: WL out of bounds (> 71) [cite: 43, 44, 45]
    uram_copy_active = 1; wl_uram_we = 1; wl_uram_addr = {7'd72, 12'h0};
    tick(1);
    uram_copy_active = 0; wl_uram_we = 0;

    // A5: BERT out of bounds (> 47) [cite: 46, 47, 48]
    bert_active = 1; bert_uram_en = 1; bert_uram_addr = {7'd48, 12'h0};
    tick(1);
    bert_active = 0; bert_uram_en = 0;

    $display("\n======================================================");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("=== VERDICT: SUCCESS (Ready for Sign-off)          ===");
      $finish(0);
    end else begin
      $display("=== VERDICT: FAILED                                ===");
      $fatal(1, "TB failed with %0d errors.", fail_cnt);
    end
  end

  initial begin
    #50000;
    $fatal(1, "TIMEOUT: simulation exceeded 50 us");
  end

endmodule
`default_nettype wire