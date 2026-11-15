// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// gru_scale_lutram.sv — Per-Row GRU Weight Scale/ZP LUTRAM
// Spec v15.5 §15.17
// ================================================================================
// 512-entry LUTRAM storing per-row scale and zero-point for GRU dequantization.
// One instance per GRU weight matrix (6 total: W_iz, W_hz, W_ir, W_hr, W_in, W_hn).
//
// Each entry: {scale_q8[7:0], zp[7:0]} = 16-bit per 512 rows.
// Initialized from DDR4_GRU_SCALE at boot (weight_loader Step G).
// Read registered (1-cycle latency). [v15.3-A03]

module gru_scale_lutram
  import planning_pkg::*;
  #(parameter DEPTH = 512)
(
  input  logic          clk,
  input  logic          rst_n,

  // ── Read port (rd_addr → rd_data, 1-cycle registered) ────────────────
  input  logic [8:0]    rd_addr,            // 0..511
  output logic [15:0]   rd_data,            // {scale_q8[7:0], zp[7:0]} — REGISTERED

  // ── Programming port (boot loading) ──────────────────────────────────
  input  logic          wr_en,              // write strobe
  input  logic [8:0]    wr_addr,            // programming address
  input  logic [15:0]   wr_data             // {scale_q8, zp}
);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 512-entry LUTRAM (16-bit × 512 = 1024B ≈ 256 LUT6)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  (* RAM_STYLE = "distributed" *)
  logic [15:0]          scale_zp_table [512];

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WRITE PORT (Programming at boot via weight_loader)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  always_ff @(posedge clk)
    if (wr_en)
      scale_zp_table[wr_addr] <= wr_data;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // READ PORT — Registered (1-cycle latency, OREG=1 behavior)
  // [v15.3-A03]: rd_data output register cleared to 0 on rst_n=0
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rd_data <= '0;
    else
      rd_data <= scale_zp_table[rd_addr];
  end

endmodule
// ================================================================================
