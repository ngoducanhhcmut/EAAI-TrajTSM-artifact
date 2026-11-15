// =============================================================================
// FILE        : uram_arbiter.sv
// PROJECT     : VLA-HMAO Planning Accelerator
// SPEC        : VLA_HMAO_SPEC_v15_5 §15.5 (v13.2 — unchanged)
// DESCRIPTION : URAM 72-block arbitrator.
//               Port A (read-only)  → BERT encoder or GRU decoder
//               Port B (write-only) → weight_loader DMA
//
//   URAM layout (§8.3):
//     Blocks  0..47: BERT INT4 weights  (bert_encoder_layer reads via Port A)
//     Blocks 48..71: GRU  INT4 weights  (gru_waypoint_decoder reads via Port A)
//     Blocks 72..95: unused / spare
//
//   Mutual-exclusivity guaranteed by planning_top FSM (§4):
//     - bert_active  asserted during BERT_PHASE
//     - gru_active   asserted during GRU_PHASE
//     - uram_copy_active asserted during weight_loader DMA (boot + per-layer)
//     These three phases never overlap (validated by SVA assertions below).
//
//   Port A : one 64-bit read per cycle (BERT or GRU, muxed).
//   Port B : one 64-bit write per cycle (weight_loader only).
//
//   Latency: Port A read data available 1 cycle after uram_porta_en/addr driven
//            (URAM288 default 1-cycle latency in 64-bit mode).
//            bert_uram_rdata / gru_uram_rdata registered 1 cycle after enable.
//
//   Resource estimate: LUT ~50, FF ~200, BRAM 0, URAM 0
//                      (URAM288 primitives instantiated by planning_top / synth)
// =============================================================================

// Note: `default_nettype none removed — all ports and signals are explicitly
// typed as logic, so the directive is redundant and triggers Synth 8-6735
// in Vivado 2023.2 when combined with a package import inside the module body.

module uram_arbiter (
  input  logic        clk,
  input  logic        rst_n,

  // ── Activity qualifiers (from planning_top FSM) ──────────────────────────
  input  logic        bert_active,       // BERT_PHASE in progress
  input  logic        gru_active,        // GRU_PHASE  in progress
  input  logic        uram_copy_active,  // weight_loader DMA writing to URAM

  // ── BERT read port (blocks 0..47) ────────────────────────────────────────
  //    uram_addr_t = {block[6:0], within[11:0]}  (§2.1)
  input  logic [18:0] bert_uram_addr,    // valid when bert_uram_en
  input  logic        bert_uram_en,
  output logic [63:0] bert_uram_rdata,   // registered, 1-cycle latency

  // ── GRU read port A (bank A, blocks 48..59, even beat-pairs) ────────────
  //    Relative address {rel_block[4:0]=0..11, within[11:0]}
  //    Absolute: {7'd48 + {2'b00, gru_uram_addr[16:12]}, gru_uram_addr[11:0]}
  input  logic [16:0] gru_uram_addr,     // [16:12]=rel_block 0..11, [11:0]=within
  input  logic        gru_uram_en,
  output logic [63:0] gru_uram_rdata,    // registered, 1-cycle latency

  // ── GRU read port B (bank B, blocks 60..71, odd beat-pairs) ─────────────
  //    Relative address {rel_block[4:0]=12..23, within[11:0]}
  //    Absolute: {7'd48 + {2'b00, gru_uram_addr_b[16:12]}, gru_uram_addr_b[11:0]}
  input  logic [16:0] gru_uram_addr_b,
  input  logic        gru_uram_en_b,
  output logic [63:0] gru_uram_rdata_b,  // registered, 1-cycle latency

  // ── weight_loader write port (Port B during uram_copy_active) ────────────
  input  logic [18:0] wl_uram_addr,      // {absolute_block[6:0], within[11:0]}
  input  logic [63:0] wl_uram_wdata,
  input  logic        wl_uram_we,

  // ── Physical URAM Port A (read) ───────────────────────────────────────────
  output logic [18:0] uram_porta_addr,
  input  logic [63:0] uram_porta_rdata,  // driven FROM uram primitive
  output logic        uram_porta_en,

  // ── Physical URAM Port B (dual-mode: GRU read or WL write) ───────────────
  output logic [18:0] uram_portb_addr,
  output logic [63:0] uram_portb_wdata,
  output logic        uram_portb_we,
  input  logic [63:0] uram_portb_rdata   // read data (used during gru_active)
);
  import planning_pkg::*;

  // ---------------------------------------------------------------------------
  // 1. GRU relative → absolute address translation
  //    Port A (bank A): gru_uram_addr[16:12] = rel_block (0..11), abs 48..59
  //    Port B (bank B): gru_uram_addr_b[16:12] = rel_block (12..23), abs 60..71
  // ---------------------------------------------------------------------------
  logic [6:0]  gru_abs_block,   gru_abs_block_b;
  logic [18:0] gru_abs_addr,    gru_abs_addr_b;

  assign gru_abs_block   = 7'd48 + {2'b00, gru_uram_addr[16:12]};
  assign gru_abs_addr    = {gru_abs_block,   gru_uram_addr[11:0]};
  assign gru_abs_block_b = 7'd48 + {2'b00, gru_uram_addr_b[16:12]};
  assign gru_abs_addr_b  = {gru_abs_block_b, gru_uram_addr_b[11:0]};

  // ---------------------------------------------------------------------------
  // 2. Port A mux: BERT has priority; GRU next; idle otherwise.
  //    Mutual exclusion is architecturally guaranteed (see SVA below), so
  //    simple priority is safe — it serves as a belt-and-suspenders guard.
  // ---------------------------------------------------------------------------
  always_comb begin
    if (bert_active && bert_uram_en) begin
      uram_porta_addr = bert_uram_addr;
      uram_porta_en   = 1'b1;
    end else if (gru_active && gru_uram_en) begin
      uram_porta_addr = gru_abs_addr;
      uram_porta_en   = 1'b1;
    end else begin
      uram_porta_addr = '0;
      uram_porta_en   = 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // 3. Port B: GRU bank-B read during gru_active; WL write during uram_copy_active.
  //    These phases are mutually exclusive (enforced by planning_top FSM).
  // ---------------------------------------------------------------------------
  always_comb begin
    if (gru_active && gru_uram_en_b) begin
      uram_portb_addr  = gru_abs_addr_b;
      uram_portb_wdata = '0;
      uram_portb_we    = 1'b0;
    end else begin
      uram_portb_addr  = wl_uram_addr;
      uram_portb_wdata = wl_uram_wdata;
      uram_portb_we    = wl_uram_we & uram_copy_active;
    end
  end

  // ---------------------------------------------------------------------------
  // 4. Read-data pipeline: register rdata by 1 cycle, demux to consumers.
  //    Port A → bert/gru_uram_rdata;  Port B → gru_uram_rdata_b (during gru_active).
  // ---------------------------------------------------------------------------
  // [IMPL 150 MHz, 04/10] URAM XPM READ_LATENCY = 2 -> chot du lieu khi enable da tre 2 chu ky
  // (truoc: tre 1 voi READ_LATENCY 1). Tong do tre dia chi -> *_rdata = 3.
  logic bert_en_d0, gru_en_d0, gru_en_b_d0;
  logic bert_en_d1, gru_en_d1, gru_en_b_d1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bert_en_d0 <= 1'b0; gru_en_d0 <= 1'b0; gru_en_b_d0 <= 1'b0;
      bert_en_d1 <= 1'b0; gru_en_d1 <= 1'b0; gru_en_b_d1 <= 1'b0;
    end else begin
      bert_en_d0  <= bert_active & bert_uram_en;
      gru_en_d0   <= gru_active  & gru_uram_en;
      gru_en_b_d0 <= gru_active  & gru_uram_en_b;
      bert_en_d1  <= bert_en_d0;
      gru_en_d1   <= gru_en_d0;
      gru_en_b_d1 <= gru_en_b_d0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bert_uram_rdata  <= '0;
      gru_uram_rdata   <= '0;
      gru_uram_rdata_b <= '0;
    end else begin
      if (bert_en_d1)  bert_uram_rdata  <= uram_porta_rdata;
      if (gru_en_d1)   gru_uram_rdata   <= uram_porta_rdata;
      if (gru_en_b_d1) gru_uram_rdata_b <= uram_portb_rdata;
    end
  end

  // ---------------------------------------------------------------------------
  // 5. SVA Assertions (§15.5)
  //    Synthesised-off in implementation; active in simulation / formal.
  // ---------------------------------------------------------------------------
// [Fix AG2] Bat khi ASSERT_ON HOAC dieu kien cu (!SYNTHESIS). Dieu kien viet
// NGAY TAI CHO: macro dinh nghia o tep khac KHONG thay duoc khi xvlog
// bien dich tung tep rieng (da thu thuc nghiem 30/09/2026).
`ifdef ASSERT_ON
  `define _AG_EN_URAM
`elsif SYNTHESIS
`else
  `define _AG_EN_URAM
`endif
`ifdef _AG_EN_URAM
  initial $display("[AG] assertion BAT: uram_arbiter.sv %m");

  // A1: BERT and GRU phases never overlap
  property p_bert_gru_mutex;
    @(posedge clk) disable iff (!rst_n)
    !(bert_active && gru_active);
  endproperty
  assert property (p_bert_gru_mutex)
    else $error("[uram_arbiter] ASSERTION FAIL A1: bert_active && gru_active both high!");

  // A2: BERT phase and URAM copy (weight_loader DMA) never overlap
  property p_bert_copy_mutex;
    @(posedge clk) disable iff (!rst_n)
    !(bert_active && uram_copy_active);
  endproperty
  assert property (p_bert_copy_mutex)
    else $error("[uram_arbiter] ASSERTION FAIL A2: bert_active && uram_copy_active both high!");

  // A3: GRU bank-A relative block index in range 0..11
  property p_gru_addr_range;
    @(posedge clk) disable iff (!rst_n)
    gru_uram_en |-> (gru_uram_addr[16:12] <= 5'd11);
  endproperty
  assert property (p_gru_addr_range)
    else $error("[uram_arbiter] ASSERTION FAIL A3: gru_uram_addr[16:12]=%0d > 11",
                gru_uram_addr[16:12]);

  // A3b: GRU bank-B relative block index in range 12..23
  property p_gru_addrb_range;
    @(posedge clk) disable iff (!rst_n)
    gru_uram_en_b |-> ((gru_uram_addr_b[16:12] >= 5'd12) &&
                       (gru_uram_addr_b[16:12] <= 5'd23));
  endproperty
  assert property (p_gru_addrb_range)
    else $error("[uram_arbiter] ASSERTION FAIL A3b: gru_uram_addr_b[16:12]=%0d out of 12..23",
                gru_uram_addr_b[16:12]);

  // A4: weight_loader write address absolute block in range 0..71
  property p_wl_addr_range;
    @(posedge clk) disable iff (!rst_n)
    wl_uram_we |-> (wl_uram_addr[18:12] <= 7'd71);
  endproperty
  assert property (p_wl_addr_range)
    else $error("[uram_arbiter] ASSERTION FAIL A4: wl_uram_addr[18:12]=%0d > 71",
                wl_uram_addr[18:12]);

  // A5: BERT read address absolute block in range 0..47
  property p_bert_addr_range;
    @(posedge clk) disable iff (!rst_n)
    bert_uram_en |-> (bert_uram_addr[18:12] <= 7'd47);
  endproperty
  assert property (p_bert_addr_range)
    else $error("[uram_arbiter] ASSERTION FAIL A5: bert_uram_addr[18:12]=%0d > 47",
                bert_uram_addr[18:12]);

  // Coverage: all three port-A user types should be exercised
  cover property (@(posedge clk) disable iff (!rst_n) bert_active && bert_uram_en);
  cover property (@(posedge clk) disable iff (!rst_n) gru_active  && gru_uram_en);
  cover property (@(posedge clk) disable iff (!rst_n) uram_copy_active && wl_uram_we);

`endif // SYNTHESIS

endmodule : uram_arbiter

`default_nettype wire
