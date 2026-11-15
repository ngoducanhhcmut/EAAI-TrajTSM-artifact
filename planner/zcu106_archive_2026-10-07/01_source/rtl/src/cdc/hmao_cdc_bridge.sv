// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// hmao_cdc_bridge.sv — HMAO Output Clock Domain Crossing Bridge
// Spec: §1, §15 (output interface to HMAO with CDC)
// ================================================================================
// Synchronizes trajectory waypoints from PL clock to HMAO clock domain.
// [C11 FIXED]: Toggle-based CDC handshake for multi-bit FP32 data safety.
//              3-stage synchronizers. wp_valid_out is a 1-cycle pulse.
//              rst_n connected to all hsync_chain instances.
// ================================================================================

module hmao_cdc_bridge
  import planning_pkg::*;
(
  // PL clock domain (200 MHz)
  input  logic          pl_clk,
  input  logic          pl_rst_n,
  input  fp32_t         pl_waypoint_x [NUM_WAYPOINTS-1:0],
  input  fp32_t         pl_waypoint_y [NUM_WAYPOINTS-1:0],
  input  logic          pl_waypoints_valid,
  input  logic          pl_sanity_pass,

  // HMAO clock domain (async)
  input  logic          hmao_clk,
  input  logic          hmao_rst_n,
  output fp32_t         hmao_waypoint_x [NUM_WAYPOINTS-1:0],
  output fp32_t         hmao_waypoint_y [NUM_WAYPOINTS-1:0],
  output logic          hmao_waypoints_valid,
  output logic          hmao_sanity_pass
);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Step 1 (src/pl_clk domain):
  //   When pl_waypoints_valid asserts, capture all waypoint data and
  //   toggle the req_toggle flag. Data remains stable until next capture.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  fp32_t  wp_x_cap [NUM_WAYPOINTS-1:0];
  fp32_t  wp_y_cap [NUM_WAYPOINTS-1:0];
  logic   sanity_cap;
  logic   req_toggle;   // level toggle in pl_clk domain

  always_ff @(posedge pl_clk, negedge pl_rst_n)
    if (!pl_rst_n) begin
      req_toggle <= 1'b0;
      sanity_cap <= 1'b0;
      for (int w = 0; w < NUM_WAYPOINTS; w++) begin
        wp_x_cap[w] <= '0;
        wp_y_cap[w] <= '0;
      end
    end else if (pl_waypoints_valid) begin
      // Capture data BEFORE toggling req — data must be stable when req is seen
      for (int w = 0; w < NUM_WAYPOINTS; w++) begin
        wp_x_cap[w] <= pl_waypoint_x[w];
        wp_y_cap[w] <= pl_waypoint_y[w];
      end
      sanity_cap <= pl_sanity_pass;
      req_toggle <= ~req_toggle;
    end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Step 2 (dst/hmao_clk domain):
  //   Sync req_toggle through 3-stage hsync_chain → req_sync
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic req_sync;

  hsync_chain #(.WIDTH(1), .STAGES(3)) u_req_sync (
    .clk   (hmao_clk),
    .rst_n (hmao_rst_n),
    .d_in  (req_toggle),
    .d_out (req_sync)
  );

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Step 3 (dst/hmao_clk domain):
  //   Edge-detect req_sync → data_valid_pulse (1-cycle pulse)
  //   On this pulse, read the captured waypoint data.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic req_sync_prev;
  logic data_valid_pulse;

  always_ff @(posedge hmao_clk, negedge hmao_rst_n)
    if (!hmao_rst_n)
      req_sync_prev <= 1'b0;
    else
      req_sync_prev <= req_sync;

  assign data_valid_pulse = req_sync ^ req_sync_prev;  // any edge → pulse

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Step 4 (dst/hmao_clk domain):
  //   Register waypoint data on data_valid_pulse.
  //   The captured registers (wp_x_cap, wp_y_cap) are stable at this point
  //   because the toggle was set AFTER data was captured.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  fp32_t hmao_wp_x_r [NUM_WAYPOINTS-1:0];
  fp32_t hmao_wp_y_r [NUM_WAYPOINTS-1:0];
  logic  hmao_sanity_r;
  logic  hmao_valid_r;

  always_ff @(posedge hmao_clk, negedge hmao_rst_n)
    if (!hmao_rst_n) begin
      hmao_sanity_r <= 1'b0;
      hmao_valid_r  <= 1'b0;
      for (int w = 0; w < NUM_WAYPOINTS; w++) begin
        hmao_wp_x_r[w] <= '0;
        hmao_wp_y_r[w] <= '0;
      end
    end else begin
      hmao_valid_r <= data_valid_pulse;
      if (data_valid_pulse) begin
        for (int w = 0; w < NUM_WAYPOINTS; w++) begin
          hmao_wp_x_r[w] <= wp_x_cap[w];
          hmao_wp_y_r[w] <= wp_y_cap[w];
        end
        hmao_sanity_r <= sanity_cap;
      end
    end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Step 5: Drive outputs
  //   wp_valid_out is a 1-cycle pulse (= data_valid_pulse)
  //   sanity_pass is level (registered)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  genvar w;
  generate
    for (w = 0; w < NUM_WAYPOINTS; w++) begin : gen_wp_out
      assign hmao_waypoint_x[w] = hmao_wp_x_r[w];
      assign hmao_waypoint_y[w] = hmao_wp_y_r[w];
    end
  endgenerate

  // wp_valid_out: 1-cycle pulse in hmao_clk domain
  assign hmao_waypoints_valid = hmao_valid_r;
  assign hmao_sanity_pass     = hmao_sanity_r;

endmodule
// ================================================================================
