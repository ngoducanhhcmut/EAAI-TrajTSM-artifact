// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// fp32_tanh_lut.sv — FP32 Hyperbolic Tangent Lookup Table
// Spec v15.5 §7.6
// ================================================================================
// 256-entry LUTRAM for tanh activation in GRU cell (n_t candidate hidden state).
// Input range: [-4.0, +4.0] FP32 (saturated outside).
// Output: tanh(x) = (exp(2x) - 1) / (exp(2x) + 1) ∈ [-1, +1].
// Latency: 5 cycles (saturate / IEEE-754 decode / barrel-shift / clamp+LUTRAM
//          read / output register).
//
// TIMING FIX (post-route 185MHz closure): mirrors the identical fix applied
// to fp32_sigmoid_lut.sv (see that file's header comment for the full
// root-cause writeup and iteration history -- same fp32_scale_pow2()-style
// barrel shifter, now split into a separate "decode" stage and "shift"
// stage). Kept latency-symmetric with fp32_sigmoid_lut.sv (5 cycles each) so
// the calling GRU FSM only needs one shared wait constant.
// ================================================================================

module fp32_tanh_lut
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,

  input  fp32_t         x_in,               // FP32 input
  input  logic          valid_in,

  output fp32_t         y_out,              // FP32 tanh(x_in)
  output logic          valid_out
);

  localparam fp32_t     X_MIN = 32'hC0800000;  // -4.0 IEEE 754
  localparam fp32_t     X_MAX = 32'h40800000;  // +4.0 IEEE 754

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // FP32 comparison helper (no NaN handling needed for bounded inputs)
  // Returns 1 if FP32 a < FP32 b
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  function automatic logic fp32_lt(input logic [31:0] a, input logic [31:0] b);
    if (a[31] != b[31]) return a[31]; // different signs: negative < positive
    else if (a[31]) return (a[30:0] > b[30:0]); // both negative: larger magnitude = smaller value
    else return (a[30:0] < b[30:0]); // both positive: smaller magnitude = smaller value
  endfunction

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 1: Saturate input to [-4.0, +4.0] range
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  fp32_t x_sat = '0;
  logic valid_s1 = '0;
  logic clamp_low = '0, clamp_high = '0, is_nan_in = '0;
  logic is_nan_s1 = '0;
  fp32_t x_sat_s1 = '0;

  always_comb begin
    // NaN: exp=0xFF and mantissa≠0. Must be checked BEFORE clamp comparisons
    // because fp32_lt treats NaN as a large positive number (clamp_high fires).
    is_nan_in  = (x_in[30:23] == 8'hFF) && (x_in[22:0] != 23'h0);
    clamp_low  = !is_nan_in && fp32_lt(x_in, X_MIN);
    clamp_high = !is_nan_in && fp32_lt(X_MAX, x_in);
    if (clamp_low)
      x_sat = X_MIN;
    else if (clamp_high)
      x_sat = X_MAX;
    else
      x_sat = x_in;
  end

  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n) begin
      valid_s1  <= '0;
      is_nan_s1 <= '0;
      x_sat_s1  <= '0;
    end else begin
      valid_s1  <= valid_in;
      is_nan_s1 <= is_nan_in;
      x_sat_s1  <= x_sat;
    end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 2 (NEW, split off the former shift stage): IEEE-754 decode only --
  // extract sign/significand and compute the (signed, can be negative)
  // shift amount. Pure bit-slicing + one subtraction: shallow.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // -------------------------------------------------------------------
  // BUG-FIX LUT-002: lut_idx was a sign-only placeholder (x_sat[31]?0:255)
  // that never varied with |x| -- on real silicon (SYNTHESIS path) this
  // made tanh_lut[] always read entry 0 or 255 regardless of magnitude.
  // Simulation never caught it because `ifndef SYNTHESIS uses a separate
  // behavioral $exp() path. Real index: idx = round(x*32) + 128, clamped
  // [0,255] -- matches the behavioral golden formula and the mapping
  // documented in tanh_lut_init.hex ("Array[I] = tanh((I-128)*4/128)").
  // -------------------------------------------------------------------
  function automatic void fp32_decode(input logic [31:0] f, input integer shift_bits,
                                       output logic sign, output logic [23:0] sig,
                                       output logic is_zero_exp, output integer shamt);
    logic [7:0] exp;
    begin
      sign = f[31];
      exp  = f[30:23];
      sig  = {1'b1, f[22:0]};
      is_zero_exp = (exp == 8'h00);
      shamt = (integer'(exp) - 127) - 23 + shift_bits;
    end
  endfunction

  logic sign_s2 = '0;
  logic [23:0] sig_s2 = '0;
  logic is_zero_exp_s2 = '0;
  integer      shamt_s2;
  logic valid_s2 = '0;
  logic is_nan_s2 = '0;
  fp32_t x_sat_s2 = '0;

  always_ff @(posedge clk) begin
    fp32_decode(x_sat_s1, 5, sign_s2, sig_s2, is_zero_exp_s2, shamt_s2);
    valid_s2  <= valid_s1;
    is_nan_s2 <= is_nan_s1;
    x_sat_s2  <= x_sat_s1;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 3 (was the shift half of the old combined stage): apply the
  // REGISTERED shamt/sig from Stage 2 to perform the actual variable
  // barrel shift, isolated on its own clock edge.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  (* RAM_STYLE = "distributed" *)
  logic [31:0]          tanh_lut [256];     // 256 entries, 32-bit FP32 each

`ifdef SYNTHESIS
  initial $readmemh("tanh_lut_init.hex", tanh_lut);
`endif

  function automatic logic signed [31:0] fp32_shift(input logic sign, input logic [23:0] sig,
                                                      input logic is_zero_exp, input integer shamt);
    logic [63:0] wide;
    begin
      if (is_zero_exp) begin
        fp32_shift = 32'sd0;
      end else begin
        if (shamt >= 0)
          wide = {40'b0, sig} << shamt;
        else
          wide = ({40'b0, sig} + (64'sd1 <<< (-shamt-1))) >> (-shamt);
        fp32_shift = sign ? -$signed(wide[31:0]) : $signed(wide[31:0]);
      end
    end
  endfunction

  logic signed [31:0] idx_signed_s3 = '0;
  logic valid_s3 = '0;
  logic is_nan_s3 = '0;
  fp32_t x_sat_s3 = '0;

  always_ff @(posedge clk) begin
    idx_signed_s3 <= fp32_shift(sign_s2, sig_s2, is_zero_exp_s2, shamt_s2) + 32'sd128;  // x*32 + 128
    valid_s3      <= valid_s2;
    is_nan_s3     <= is_nan_s2;
    x_sat_s3      <= x_sat_s2;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 4 (was Stage 2's second half): clamp to [0,255], then LUTRAM
  // lookup. Starts from Stage 3's REGISTERED idx_signed_s3.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic [7:0] lut_idx_s4 = '0;
  fp32_t y_lut_s4 = '0;
  logic valid_s4 = '0;
  logic is_nan_s4 = '0;
  fp32_t x_sat_s4 = '0;  // pipeline x for behavioral stage 5

  always_comb begin
    if (idx_signed_s3 < 0)        lut_idx_s4 = 8'd0;
    else if (idx_signed_s3 > 255) lut_idx_s4 = 8'd255;
    else                          lut_idx_s4 = idx_signed_s3[7:0];
  end

  always_ff @(posedge clk) begin
    y_lut_s4  <= tanh_lut[lut_idx_s4];
    valid_s4  <= valid_s3;
    is_nan_s4 <= is_nan_s3;
    x_sat_s4  <= x_sat_s3;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 5: Output register
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  fp32_t y_final = '0;
  logic valid_s5 = '0;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      y_final  <= '0;
      valid_s5 <= '0;
    end else begin
      if (is_nan_s4)
        y_final <= 32'h7FC00000;  // canonical quiet NaN
      else begin
`ifndef SYNTHESIS
        // LUT-quantized simulation: matches SW debug_gru_rtl.py tanh_lut()
        // idx = round(x * 32 + 128), clamped [0,255]; then compute tanh
        // at quantized x_lut = (idx-128)/32.0. x_sat_s4 already in [-4,+4].
        // Saturation handled naturally: x=+4→idx=256→255→tanh(3.96875)≈0.999329
        //                               x=-4→idx=0→tanh(-4)=-0.999329
        begin
          shortreal xv, xc, yv;
          real      lut_r, ex2;
          integer   lut_i;
          xv    = $bitstoshortreal(x_sat_s4);
          lut_r = real'(xv) * 32.0 + 128.0;
          lut_i = $rtoi(lut_r + 0.5);  // round-to-nearest (arg always >=0)
          if (lut_i < 0)   lut_i = 0;
          if (lut_i > 255) lut_i = 255;
          xc  = shortreal'((lut_i - 128) / 32.0);
          ex2 = $exp(2.0 * real'(xc));
          yv  = shortreal'((ex2 - 1.0) / (ex2 + 1.0));
          y_final <= $shortrealtobits(yv);
        end
`else
        y_final <= y_lut_s4;
`endif
      end
      valid_s5 <= valid_s4;
    end
  end

  assign y_out     = y_final;
  assign valid_out = valid_s5;

endmodule
// ================================================================================
