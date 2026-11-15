`timescale 1ns/1ps
// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// hsync_chain.sv — Multi-stage CDC Synchronizer
// Generic clock domain crossing synchronizer (2-3 stages)
// [C11/FIX4 FIXED]: added rst_n port; default STAGES changed to 3
// ================================================================================

module hsync_chain
  #(parameter WIDTH = 1, STAGES = 3)
(
  input  logic                clk,
  input  logic                rst_n,
  input  logic [WIDTH-1:0]    d_in,
  output logic [WIDTH-1:0]    d_out
);

  logic [WIDTH-1:0] sync_r [STAGES];

  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n)
      for (int i = 0; i < STAGES; i++)
        sync_r[i] <= '0;
    else
      for (int i = 0; i < STAGES; i++)
        sync_r[i] <= (i == 0) ? d_in : sync_r[i-1];

  assign d_out = sync_r[STAGES-1];

endmodule
// ================================================================================
