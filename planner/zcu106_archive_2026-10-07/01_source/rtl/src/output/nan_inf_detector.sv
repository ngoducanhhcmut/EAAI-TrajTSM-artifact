// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// nan_inf_detector.sv — NaN/Inf Detection for Debugging
// Spec v15.5 §15.14 (V15-S04)
// ================================================================================
// Detects FP32 NaN and Infinity values in data streams for runtime debugging
// and signal integrity monitoring. Raises error flags to CSR STATUS register.

module nan_inf_detector
  import planning_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // ── Scalar FP32 input (spec §15.14 scalar interface) ────────────────
  input  logic [31:0] fp32_in,
  input  logic        valid_in,

  // ── Detection outputs (registered, 1-cycle latency) ─────────────────
  output logic        nan_detected,   // exp=0xFF AND mantissa != 0
  output logic        inf_detected,   // exp=0xFF AND mantissa == 0
  output logic        fault_out,      // nan_detected | inf_detected (registered)
  output logic        valid_out       // valid_in delayed 1 cycle
);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // IEEE 754 FP32 combinational detection
  // exp_field  = fp32_in[30:23]; mantissa = fp32_in[22:0]
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic nan_comb, inf_comb;

  assign nan_comb = (fp32_in[30:23] == 8'hFF) && (fp32_in[22:0] != '0);
  assign inf_comb = (fp32_in[30:23] == 8'hFF) && (fp32_in[22:0] == '0);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Registered outputs — 1-cycle pipeline latency
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      nan_detected <= 1'b0;
      inf_detected <= 1'b0;
      fault_out    <= 1'b0;
      valid_out    <= 1'b0;
    end else begin
      valid_out    <= valid_in;
      nan_detected <= nan_comb;
      inf_detected <= inf_comb;
      fault_out    <= nan_comb | inf_comb;
    end
  end

endmodule
// ================================================================================
