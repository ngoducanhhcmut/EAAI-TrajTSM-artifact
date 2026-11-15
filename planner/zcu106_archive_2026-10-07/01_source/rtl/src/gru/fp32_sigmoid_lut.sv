// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// fp32_sigmoid_lut.sv — FP32 Sigmoid Lookup Table
// Spec v15.5 §7.6
// ================================================================================
// 256-entry LUTRAM for sigmoid activation in GRU cell (z_t, r_t gates).
// Input range: [-6.0, +6.0] FP32 (saturated outside).
// Output: σ(x) = 1/(1+exp(-x)) FP32.
// Latency: 7 cycles (saturate / IEEE-754 decode / barrel-shift / round-bias
//          + width-narrow / divide / clamp+LUTRAM read / output register).
//
// TIMING FIX (post-route 185MHz closure): the address-generation chain
// (IEEE-754 exponent/mantissa extract -> variable barrel shift -> divide-by-6
// round -> clamp -> LUTRAM read) used to be ONE fully combinational cloud
// landing in a single register (y_lut): 51 logic levels (23x CARRY8),
// WNS=-7.791ns at 185MHz/5.405ns. Four rounds of splitting were needed:
//   round 1: barrel-shift alone, then divide+clamp+read (2 stages) ->
//            real post-route re-synth only cut WNS to -3.751ns.
//   round 2: split "decode" (sign/exp/sig extract + shamt) from "shift"
//            (apply the registered shamt) -> post-place re-synth still
//            showed ~-3.87ns, worst path now isolated to the divide+clamp+
//            read stage specifically.
//   round 3: split the divide-by-6 itself into its own registered stage,
//            leaving only +128/clamp/LUTRAM-read for the next stage -> an
//            isolated post-synthesis check of the divide stage alone (no
//            real floorplan) showed WNS improve to -0.305ns, but the
//            32-bit-wide divide operand (a generic width carried from
//            fp32_shift's return type, even though x128 is provably
//            bounded to [-768,+768] by the Stage-1 clamp) meant Vivado
//            was synthesizing a full 32-bit divider for an 11-bit-range
//            value.
//   round 4 (this pass): narrow the divide operand to 16 bits (still far
//            wider than the true range, so no precision is lost) AND add
//            one more registered stage, so the round-bias+narrow step and
//            the divide-by-6 itself are on separate clock edges.
// This adds one more fixed, data-independent cycle (6 -> 7). No change to
// the sigmoid math itself -- same arithmetic, same round-half-away-from-zero
// bias, just narrower operand widths and one more pipeline register.
// ================================================================================

module fp32_sigmoid_lut
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,

  input  fp32_t         x_in,               // FP32 input
  input  logic          valid_in,

  output fp32_t         y_out,              // FP32 sigmoid(x_in)
  output logic          valid_out
);

  localparam fp32_t     X_MIN = 32'hC0C00000;  // -6.0 IEEE 754
  localparam fp32_t     X_MAX = 32'h40C00000;  // +6.0 IEEE 754

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
  // Stage 1: Saturate input to [-6.0, +6.0] range
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
  // Stage 2 (NEW, split off Stage 2's own former shift stage): IEEE-754
  // decode only -- extract sign/significand and compute the (signed, can be
  // negative) shift amount. Pure bit-slicing + one subtraction: shallow.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // -------------------------------------------------------------------
  // BUG-FIX LUT-002: lut_idx was a raw bit-extraction placeholder
  // ({x_sat[30:24],1'b0}) that does NOT correspond to the true magnitude
  // scaling of x -- on real silicon (SYNTHESIS path) this reads the wrong
  // sigmoid_lut[] entry. Simulation never caught it because `ifndef
  // SYNTHESIS uses a separate behavioral $exp() path. Real index:
  // idx = round(x*128/6) + 128, clamped [0,255] -- matches the behavioral
  // golden formula and sigmoid_lut_init.hex's documented mapping
  // ("Array[I] = sigmoid((I-128)*6/128)").
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
    // [Fix N] 7 -> 13: giu x*8192 thay vi x*128 de CHI lam tron MOT lan.
    // Truoc day lam tron x*128 thanh so nguyen roi moi chia 6 -> lam tron HAI lan,
    // lech 1 bac chi so LUT o ~7,5% so ca (do 10/133 bang tb don vi).
    fp32_decode(x_sat_s1, 16, sign_s2, sig_s2, is_zero_exp_s2, shamt_s2);
    valid_s2  <= valid_s1;
    is_nan_s2 <= is_nan_s1;
    x_sat_s2  <= x_sat_s1;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 3 (was Stage 2's shift half): apply the REGISTERED shamt/sig from
  // Stage 2 to perform the actual variable barrel shift. Isolated on its
  // own so it doesn't share a cycle with the IEEE-754 decode anymore.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  (* RAM_STYLE = "distributed" *)
  logic [31:0]          sigmoid_lut [256];   // 256 entries, 32-bit FP32 each

`ifdef SYNTHESIS
  initial $readmemh("sigmoid_lut_init.hex", sigmoid_lut);
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

  logic signed [31:0] x128_s3 = '0;
  logic valid_s3 = '0;
  logic is_nan_s3 = '0;
  fp32_t x_sat_s3 = '0;

  always_ff @(posedge clk) begin
    x128_s3   <= fp32_shift(sign_s2, sig_s2, is_zero_exp_s2, shamt_s2);  // x*128 (exact, power-of-2 scale)
    valid_s3  <= valid_s2;
    is_nan_s3 <= is_nan_s2;
    x_sat_s3  <= x_sat_s2;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 4 (NEW pipeline split): round-bias ONLY, plus a width-narrowing
  // truncation. x_sat is clamped to [-6.0,+6.0] (Stage 1), so x128 = x*128
  // is provably bounded to [-768,+768] -- yet x128_s3 is carried as a
  // 32-bit signed value (a generic width from fp32_shift's return type),
  // which forces Vivado to synthesize a full 32-bit divider in Stage 5
  // even though the upper 21 bits are always sign-extension. Truncating to
  // 16 bits here (still far wider than the true ±771 range after biasing,
  // so no precision is lost) lets Stage 5's divider be built far narrower.
  // This is a width optimization only -- the numeric value and the
  // round-half-away-from-zero bias math are unchanged.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic [20:0] x128_biased_s4 = '0;   // [Fix N3] KHONG DAU, da cong offset 393216
  logic valid_s4 = '0;
  logic is_nan_s4 = '0;
  fp32_t x_sat_s4 = '0;

  // Round x128/6 to nearest (signed '/' truncates toward zero in SV, so
  // bias by +-3 before dividing to get round-half-away-from-zero). The
  // actual divide-by-6 is deferred to Stage 5, on this narrowed value.
  always_ff @(posedge clk) begin
    // [Fix N2] Cong offset 128 bac (=49152) TRUOC khi chia, dung nhu tham chieu
    //   idx = floor((x*8192 + 49152 + 192) / 384)
    // x thuoc [-6,6] -> x*8192 thuoc [-49152,49152] -> tong luon >= 0, nen phep
    // chia cat-ve-0 cua SV trung voi floor, va +192 cho lam tron nua-len.
    // Nho vay khong con khac biet quy tac lam tron o gia tri am.
    x128_biased_s4 <= 21'($signed(x128_s3) + 32'sd394752);  // 393216 + 1536
    valid_s4       <= valid_s3;
    is_nan_s4      <= is_nan_s3;
    x_sat_s4       <= x_sat_s3;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 5 (NEW pipeline split): divide-by-6 ONLY, on the narrowed
  // 16-bit biased value from Stage 4. Isolating this into its own
  // registered stage (rather than sharing a cycle with +128/clamp/LUT-read)
  // is the next incremental cut after Stage 4/5's earlier decode/shift
  // split: real post-route timing showed the combined divide+clamp+read
  // stage was still the worst path (WNS -7.791ns -> -3.751ns -> ~-3.87ns
  // post-place). Combined with the width narrowing above, an isolated
  // post-synthesis check of this stage alone showed WNS improve to
  // -0.305ns; this further split adds one more fixed cycle of margin.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic signed [15:0] idx_raw_s5 = '0;
  logic valid_s5 = '0;
  logic is_nan_s5 = '0;
  fp32_t x_sat_s5 = '0;

  always_ff @(posedge clk) begin
    idx_raw_s5 <= 16'(x128_biased_s4 / 21'd3072);  // [Fix N3] 65536/3072 == 128/6
    valid_s5   <= valid_s4;
    is_nan_s5  <= is_nan_s4;
    x_sat_s5   <= x_sat_s4;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 6 (was Stage 5's role after the divide split): +128 offset,
  // clamp to [0,255], then LUTRAM lookup. Starts from Stage 5's
  // REGISTERED idx_raw_s5.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic signed [15:0] idx_signed_s6;
  logic [7:0] lut_idx_s6 = '0;
  fp32_t y_lut_s6 = '0;
  logic valid_s6 = '0;
  logic is_nan_s6 = '0;
  fp32_t x_sat_s6 = '0;  // pipeline x for behavioral stage 7

  assign idx_signed_s6 = idx_raw_s5;   // [Fix N2] offset 128 da cong o Stage 4

  always_comb begin
    if (idx_signed_s6 < 0)        lut_idx_s6 = 8'd0;
    else if (idx_signed_s6 > 255) lut_idx_s6 = 8'd255;
    else                          lut_idx_s6 = idx_signed_s6[7:0];
  end

  always_ff @(posedge clk) begin
    y_lut_s6  <= sigmoid_lut[lut_idx_s6];
    valid_s6  <= valid_s5;
    is_nan_s6 <= is_nan_s5;
    x_sat_s6  <= x_sat_s5;
  end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Stage 7: Output register
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  fp32_t y_final = '0;
  logic valid_s7 = '0;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      y_final  <= '0;
      valid_s7 <= '0;
    end else begin
      if (is_nan_s6)
        y_final <= 32'h7FC00000;  // canonical quiet NaN
      else begin
`ifndef SYNTHESIS
        // LUT-quantized simulation: matches SW debug_gru_rtl.py sigmoid_lut()
        // idx = round(x * 128/6 + 128), clamped [0,255]; then compute sigmoid
        // at the quantized x_lut = (idx-128)*6/128. x_sat_s6 already in [-6,+6].
        // Saturation (clamp_low/high) handled naturally: x=+6→idx=256→255→0.997413
        //                                                  x=-6→idx=0→sigmoid(-6)=0.002473
        begin
          shortreal xv, xc, yv;
          real      lut_r;
          integer   lut_i;
          xv    = $bitstoshortreal(x_sat_s6);
          lut_r = real'(xv) * (128.0 / 6.0) + 128.0;
          lut_i = $rtoi(lut_r + 0.5);  // round-to-nearest (arg always >=0)
          if (lut_i < 0)   lut_i = 0;
          if (lut_i > 255) lut_i = 255;
          xc = shortreal'((lut_i - 128) * 6.0 / 128.0);
          yv = 1.0 / (1.0 + shortreal'($exp(real'(-xc))));
          y_final <= $shortrealtobits(yv);
        end
`else
        y_final <= y_lut_s6;
`endif
      end
      valid_s7 <= valid_s6;
    end
  end

  assign y_out     = y_final;
  assign valid_out = valid_s7;

endmodule
// ================================================================================
