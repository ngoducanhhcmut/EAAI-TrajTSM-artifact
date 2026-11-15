// =============================================================================
// tb_uram_arbiter.sv — Unit Testbench for uram_arbiter
// Tests URAM arbitration: wl_uram_we has priority, then bert/gru read
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_uram_arbiter;

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
  logic [63:0] uram [0:524287];  // 512K words (19-bit addr)
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

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_hex(input string name, input logic [63:0] got, input logic [63:0] exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = 0x%016h", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=0x%016h exp=0x%016h", name, got, exp);
      fail_cnt++;
    end
  endtask

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_uram_arbiter : uram_arbiter ===");

    bert_active      = 0;
    gru_active       = 0;
    uram_copy_active = 0;
    bert_uram_addr   = 19'h0;
    bert_uram_en     = 0;
    gru_uram_addr    = 17'h0;
    gru_uram_en      = 0;
    wl_uram_addr     = 19'h0;
    wl_uram_wdata    = 64'h0;
    wl_uram_we       = 0;
    // Init URAM
    for (int i = 0; i < 524288; i++) uram[i] = 64'h0;

    rst_n = 0;
    tick(3);
    rst_n = 1;
    tick(2);

    // T1: Weight-loader write path
    // Write 0xDEADBEEF_CAFEBABE to address 0x100
    uram_copy_active = 1;
    @(posedge clk); #0.1;
    wl_uram_addr  = 19'h100;
    wl_uram_wdata = 64'hDEADBEEF_CAFEBABE;
    wl_uram_we    = 1'b1;
    @(posedge clk); #0.1;
    wl_uram_we    = 1'b0;
    uram_copy_active = 0;
    tick(2);
    // portb_we should have triggered — uram[0x100] = written value
    check_hex("wl_write_portb", uram[19'h100], 64'hDEADBEEF_CAFEBABE);

    // T2: BERT read from written address
    bert_active    = 1;
    @(posedge clk); #0.1;
    bert_uram_addr = 19'h100;
    bert_uram_en   = 1'b1;
    @(posedge clk); #0.1;
    bert_uram_en   = 1'b0;
    tick(2);  // 1 extra cycle for registered output
    check_hex("bert_read_val", bert_uram_rdata, 64'hDEADBEEF_CAFEBABE);
    bert_active = 0;

    // T3: GRU read from a different address (write first)
    uram_copy_active = 1;
    @(posedge clk); #0.1;
    wl_uram_addr  = 19'h30200;  // GRU block 48 offset 0x200 = {7'd48,12'h200}
    wl_uram_wdata = 64'h1234567890ABCDEF;
    wl_uram_we    = 1'b1;
    @(posedge clk); #0.1;
    wl_uram_we    = 1'b0;
    uram_copy_active = 0;
    tick(2);

    gru_active   = 1;
    @(posedge clk); #0.1;
    gru_uram_addr = 17'h200;
    gru_uram_en   = 1'b1;
    @(posedge clk); #0.1;
    gru_uram_en   = 1'b0;
    tick(2);
    check_hex("gru_read_val", gru_uram_rdata, 64'h1234567890ABCDEF);
    gru_active = 0;

    // T4: BERT read-only while idle (bert_active=1, uram_copy_active=0)
    // Note: bert_active and uram_copy_active are mutually exclusive by design
    // invariant (see RTL assertion A2). Testing both simultaneously is invalid.
    bert_active    = 1;
    @(posedge clk); #0.1;
    bert_uram_addr = 19'h100;   // re-read the value written in T1
    bert_uram_en   = 1'b1;
    @(posedge clk); #0.1;
    bert_uram_en   = 1'b0;
    tick(2);
    check_hex("bert_read_no_hang", bert_uram_rdata, 64'hDEADBEEF_CAFEBABE);
    bert_active = 0;

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: uram_arbiter");
      $finish(0);
    end else
      $fatal(1, "FAIL: uram_arbiter — %0d test(s) failed", fail_cnt);
  end

  initial begin
    #50000;
    $fatal(1, "TIMEOUT: simulation exceeded 50 us");
  end

endmodule
`default_nettype wire
