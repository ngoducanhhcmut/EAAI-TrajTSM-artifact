// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// pp_mux.sv — Ping-Pong Memory Multiplexer & Write Controller
// Spec: §1.2 (ping-pong buffer pool), §4.2b (PROJ_PHASE write)
// ================================================================================
// Manages read/write arbitration between:
//   - Read: bert_encoder_layer (active layer reader)
//   - Write: feature_projector (PROJ_PHASE), bert_encoder_layer (layer output)
// Maintains two 64×512 INT8 buffers (pp_A, pp_B).

module pp_mux
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,

  // ── Control (from planning_top FSM) ───────────────────────────────────
  input  logic  [3:0]   phase,              // current execution phase
  input  logic          proj_phase_en,      // Phase 2: PROJ_PHASE active
  input  logic          bert_phase_en,      // Phase 3: BERT_PHASE active

  // ── Feature projector write port (PROJ_PHASE) ────────────────────────
  input  logic [14:0]   proj_wr_addr,
  input  logic  [7:0]   proj_wr_data,
  input  logic          proj_wr_en,
  output logic          proj_wr_ready,

  // ── BERT encoder read port ────────────────────────────────────────────
  input  logic          bert_rd_sel,        // 0=pp_A, 1=pp_B
  input  logic [14:0]   bert_rd_addr,
  input  logic          bert_rd_en,
  output logic  [7:0]   bert_rd_data,

  // ── BERT encoder write port (layer output) ────────────────────────────
  input  logic          bert_wr_sel,        // 0=pp_A, 1=pp_B
  input  logic [14:0]   bert_wr_addr,
  input  logic  [7:0]   bert_wr_data,
  input  logic          bert_wr_en,
  output logic          bert_wr_ready,

  // ── BRAM ports (internal dual-buffer) ─────────────────────────────────
  // pp_A: 8 blocks (4K×8b SDP each)
  output logic [14:0]   pp_a_wr_addr,
  output logic  [7:0]   pp_a_wr_data,
  output logic          pp_a_wr_en,
  output logic [14:0]   pp_a_rd_addr,
  input  logic  [7:0]   pp_a_rd_data,
  output logic          pp_a_rd_en,

  // pp_B: 8 blocks (4K×8b SDP each)
  output logic [14:0]   pp_b_wr_addr,
  output logic  [7:0]   pp_b_wr_data,
  output logic          pp_b_wr_en,
  output logic [14:0]   pp_b_rd_addr,
  input  logic  [7:0]   pp_b_rd_data,
  output logic          pp_b_rd_en
);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Port Arbitration During PROJ_PHASE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic proj_owns_pp_a;  // feature_projector has exclusive access to pp_A during PROJ

  assign proj_owns_pp_a = proj_phase_en;  // During PROJ_PHASE, projector writes pp_A

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PATH 1: Feature Projector → pp_A (write during PROJ_PHASE)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  assign proj_wr_ready  = proj_owns_pp_a;  // Ready during PROJ_PHASE

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PATH 2 & 3: BERT Encoder access (read/write to selected pp buffer)
  //             - Read: bert_layer reads current pp_A or pp_B (pp_rd_sel)
  //             - Write: bert_layer writes computed layer output to pp (pp_wr_sel)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  assign bert_wr_ready = ~proj_owns_pp_a || !bert_phase_en;  // Available when proj not blocking

  // ── Read path multiplexer ──────────────────────────────────────────────
  always_comb begin
    if (bert_rd_sel == 1'b0) begin
      // Read from pp_A
      pp_a_rd_addr = bert_rd_addr;
      pp_a_rd_en   = bert_rd_en;
      pp_b_rd_addr = '0;
      pp_b_rd_en   = 1'b0;
      bert_rd_data = pp_a_rd_data;
    end else begin
      // Read from pp_B
      pp_a_rd_addr = '0;
      pp_a_rd_en   = 1'b0;
      pp_b_rd_addr = bert_rd_addr;
      pp_b_rd_en   = bert_rd_en;
      bert_rd_data = pp_b_rd_data;
    end
  end

  // ── Write path multiplexer ─────────────────────────────────────────────
  always_comb begin
    if (bert_wr_sel == 1'b0) begin
      // Write to pp_A (if projector not using it)
      if (!proj_owns_pp_a) begin
        pp_a_wr_addr = bert_wr_addr;
        pp_a_wr_data = bert_wr_data;
        pp_a_wr_en   = bert_wr_en;
      end else begin
        pp_a_wr_addr = proj_wr_addr;  // Keep projector write if active
        pp_a_wr_data = proj_wr_data;
        pp_a_wr_en   = proj_wr_en && proj_owns_pp_a;
      end
      pp_b_wr_addr = '0;
      pp_b_wr_data = '0;
      pp_b_wr_en   = 1'b0;
    end else begin
      // Write to pp_B
      pp_a_wr_addr = proj_owns_pp_a ? proj_wr_addr : '0;
      pp_a_wr_data = proj_owns_pp_a ? proj_wr_data : '0;
      pp_a_wr_en   = proj_owns_pp_a ? proj_wr_en : 1'b0;

      pp_b_wr_addr = bert_wr_addr;
      pp_b_wr_data = bert_wr_data;
      pp_b_wr_en   = bert_wr_en;
    end
  end

endmodule
// ================================================================================
