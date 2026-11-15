// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// cdc_pulse_sync.sv — Pulse to Level CDC Synchronizer
// Spec: §15.3 (CDC synchronization to HMAO)
// ================================================================================
// Converts a pulse signal (source clock) to a level signal (dest clock).
// Suitable for single-cycle synchronization events.
// [FIX4 FIXED]: added rst_n; added 3-stage synchronizer; changed default STAGES to 3

module cdc_pulse_sync
  #(parameter STAGES = 3)
(
  input  logic   src_clk,
  input  logic   rst_n,
  input  logic   src_pulse,      // 1-cycle pulse in source domain

  input  logic   dest_clk,
  output logic   dest_level      // level signal in dest domain (sticky, cleared externally)
);

  // Toggle FF in source domain: converts pulse to level toggle
  logic toggle_r;
  always_ff @(posedge src_clk, negedge rst_n)
    if (!rst_n)
      toggle_r <= 1'b0;
    else if (src_pulse)
      toggle_r <= ~toggle_r;

  // Multi-stage synchronizer chain in dest domain
  logic [STAGES-1:0] sync_r;
  always_ff @(posedge dest_clk, negedge rst_n)
    if (!rst_n)
      sync_r <= '0;
    else begin
      sync_r[0] <= toggle_r;
      for (int i = 1; i < STAGES; i++)
        sync_r[i] <= sync_r[i-1];
    end

  // Detect edge in dest domain → 1-cycle pulse
  logic sync_prev;
  always_ff @(posedge dest_clk, negedge rst_n)
    if (!rst_n)
      sync_prev <= 1'b0;
    else
      sync_prev <= sync_r[STAGES-1];

  assign dest_level = sync_r[STAGES-1] ^ sync_prev;

endmodule
// ================================================================================
