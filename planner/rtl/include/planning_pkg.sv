//==============================================================================
// File: planning_pkg.sv
// Description: System-level parameter package for VLA-HMAO Planning Accelerator
//              W4A8 quantization — INT4 weights, INT8 activations, INT32 accum
//              Based on PlanTSMALL (4 layers, 512 hidden, Pre-LN, GELU)
//
// Spec: VLA_HMAO_SPEC_v15_5.txt §2.1
// Target: Xilinx ZCU106 XCZU7EV-2FFVC1156 @ 200 MHz
// Author: VLA-HMAO Team
// Date:   2026-03-25
// Status: RTL-READY (v15.5 — 256 issues resolved)
//==============================================================================

// [Fix AG2] Khoi macro VLA_ASSERT tung dat o day DA BO: da thu thuc nghiem,
// macro dinh nghia trong tep nay KHONG thay duoc o tep khac khi xvlog bien
// dich tung tep rieng. Dieu kien bat assertion nay viet tai tung cho.

/* verilator lint_off TIMESCALEMOD */
package planning_pkg;

  // ── Model dimensions ────────────────────────────────────────────────────────
  localparam int  NUM_LAYERS      = 4;
  localparam int  HIDDEN_DIM      = 512;
  localparam int  NUM_HEADS       = 8;
  localparam int  HEAD_DIM        = 64;    // HIDDEN_DIM / NUM_HEADS
  localparam int  FFN_DIM         = 2048;  // 4 × HIDDEN_DIM
  localparam int  MAX_SEQ_LEN     = 64;
  localparam int  NUM_WAYPOINTS   = 4;
  localparam int  GRU_HIDDEN      = 512;
  localparam int  GRU_INPUT_DIM   = 512;

  // ── Quantization ────────────────────────────────────────────────────────────
  localparam int  WEIGHT_BITS     = 4;     // INT4 weights (DDR4 / URAM)
  localparam int  ACT_BITS        = 8;     // INT8 activations
  localparam int  ACCUM_BITS      = 32;    // INT32 accumulator
  localparam int  FP32_BITS       = 32;

  // ── World model limits ──────────────────────────────────────────────────────
  localparam int  MAX_OBJECTS     = 200;
  localparam int  MAX_LANES       = 20;
  localparam int  MAX_WP_PER_LANE = 10;

  // ── BRAM layout — LN BRAM (8× RAMB36E2) ────────────────────────────────────
  // addr = (layer × LN_BRAM_LAYER_STRIDE) + (norm_sel × LN_BRAM_NORM_STRIDE)
  //      + (param_sel × LN_BRAM_PARAM_STRIDE) + channel_idx
  // norm_sel:  0 = LN1 (pre-Attention), 1 = LN2 (pre-FFN)
  // param_sel: 0 = gamma, 1 = beta; channel_idx: 0..511
  // Max addr: 3×2048 + 1×1024 + 1×512 + 511 = 8191 → [12:0] ✓
  localparam int  LN_BRAM_LAYER_STRIDE  = 2048;
  localparam int  LN_BRAM_NORM_STRIDE   = 1024;
  localparam int  LN_BRAM_PARAM_STRIDE  = 512;

  // ── BRAM layout — Scale/ZP BRAM (9× RAMB36E2) ──────────────────────────────
  // Data [31:0]: {zp_odd[7:0], scale_odd[7:0], zp_even[7:0], scale_even[7:0]}
  // packed_addr = (layer × SCALE_LAYER_STRIDE + SCALE_M_xx + ch) >> 1
  // Max packed addr = (4×4608-1)/2 = 9215 → [13:0] (14-bit) ✓
  localparam int  SCALE_LAYER_STRIDE    = 4608;
  localparam int  SCALE_M_WQ            = 0;     // 512 ch (WQ output)
  localparam int  SCALE_M_WK            = 512;   // 512 ch (WK output)
  localparam int  SCALE_M_WV            = 1024;  // 512 ch (WV output)
  localparam int  SCALE_M_WO            = 1536;  // 512 ch (WO output)
  localparam int  SCALE_M_W1            = 2048;  // 2048 ch (W1 output)
  localparam int  SCALE_M_W2            = 4096;  // 512 ch (W2 output)
  // Verify: 512+512+512+512+2048+512 = 4608 = SCALE_LAYER_STRIDE ✓

  // ── BRAM layout — Bias BRAM (18× RAMB36E2) [v15.4-C03 FIXED] ───────────────
  // 18 blocks × 1024 entries = 18,432 entries ≥ 18,432 needed ✓
  // Max addr: 3×4608+4096+511 = 18,431 → [14:0] ✓
  // [v15.4-C03]: Was 16 blocks → L3 W1[ch512..2047] and L3 W2 silently corrupt
  localparam int  BIAS_LAYER_STRIDE     = 4608;
  localparam int  BIAS_M_WQ             = 0;
  localparam int  BIAS_M_WK             = 512;
  localparam int  BIAS_M_WV             = 1024;
  localparam int  BIAS_M_WO             = 1536;
  localparam int  BIAS_M_W1             = 2048;
  localparam int  BIAS_M_W2             = 4096;

  // ── Ping-pong / LN1_q scratch address ──────────────────────────────────────
  // addr[14:0] = {token[5:0], channel[8:0]}
  localparam int  PP_ADDR_BITS          = 15;

  // ── K/V scratch address ─────────────────────────────────────────────────────
  // addr[14:0] = {head[2:0], k_tok[5:0], local_d[5:0]}  [v15.3-N03]
  // block_select = addr[14:12] = head[2:0] → 1 block per head ✓

  // ── QK^T scratch address ────────────────────────────────────────────────────
  // addr[14:0] = {head[2:0], q_tok[5:0], k_tok[5:0]}
  localparam int  QKT_ADDR_BITS         = 15;

  // ── Attention scale ─────────────────────────────────────────────────────────
  // QK^T INT32 scores >> ATTN_SCALE_SHIFT before softmax (divide by sqrt(64)=8)
  localparam int  ATTN_SCALE_SHIFT      = 3;   // >>3 = ÷8

  // ── GRU parallelism ─────────────────────────────────────────────────────────
  localparam int  GRU_MAC_PARALLEL      = 32;   // parallel INT4 MACs per cycle

  // ── Timing constants (cycles @ 200 MHz) ────────────────────────────────────
  // Per-layer BERT breakdown (see §2.1 for detailed annotation):
  //   Weight load:          98,000 cy
  //   LN1 (×8 units):        8,192 cy
  //   Q/K/V projections:    98,304 cy  (3×32,768)
  //   QK^T accumulation:   262,144 cy  (64 q_toks × 4,096, 8 heads parallel)
  //   Softmax (×8):         16,384 cy
  //   Attn × V:            262,144 cy
  //   ctx_quant:               512 cy
  //   WO projection:        32,768 cy
  //   WO requant:              512 cy
  //   Residual #1:             512 cy
  //   LN2 (×8 units):        8,192 cy
  //   W1 (4 sub-passes):   131,072 cy
  //   GELU (streaming):      2,048 cy
  //   W2 (4 sub-passes):   131,072 cy
  //   W2 requant:              512 cy
  //   Residual #2:             512 cy
  //   Pipeline/BRAM ovhd:    8,064 cy
  //   Per layer total: ~1,060,944 cy
  localparam int  BERT_LATENCY_CY       = 4_300_000;   // 4 layers conservative [v15.3-R01]
  localparam int  GRU_LATENCY_CY        = 800_000;     // N=32 parallel: ~4ms @ 185MHz
  localparam int  TOTAL_LATENCY_CY      = 10_800_000;  // 54.0ms @ 200MHz [v15.4-N01]
  localparam int  WLOAD_TIMEOUT_CY      = 500_000;

  // ── DDR4 address map ────────────────────────────────────────────────────────
  //   Layer offsets for BERT weights:
  //   L0=0x0000_0000, L1=0x0018_0000, L2=0x0030_0000, L3=0x0048_0000
  localparam logic [31:0] DDR4_BERT_WEIGHT    = 32'h0000_0000; // 6MB   BERT INT4
  localparam logic [31:0] DDR4_POS_EMB        = 32'h0060_0000; // 128KB pos embed FP32
  localparam logic [31:0] DDR4_SCALE          = 32'h0062_0000; // 36KB  scale+zp
  localparam logic [31:0] DDR4_BERT_LN        = 32'h0062_9000; // 32KB  LN γ,β params
  localparam logic [31:0] DDR4_WM_A           = 32'h0064_0000; // 8MB   WM buffer A
  localparam logic [31:0] DDR4_WM_B           = 32'h00E4_0000; // 8MB   WM buffer B
  // Gap 0x0164_0000→0x017C_0000 reserved [v15.4-M06: DDR4_BERT_STAGING removed]
  localparam logic [31:0] DDR4_BERT_BIAS      = 32'h017C_0000; // 72KB  BERT bias INT32
  localparam logic [31:0] DDR4_GRU_BIAS       = 32'h017D_2000; // 8KB   GRU bias FP32
  localparam logic [31:0] DDR4_GRU_WEIGHT     = 32'h017D_4000; // 768KB GRU INT4
  localparam logic [31:0] DDR4_GRU_WOUT_STAG  = 32'h0189_4000; // 8KB   GRU W_out FP32
  localparam logic [31:0] DDR4_GRU_SCALE      = 32'h018A_0000; // 6KB   GRU scale/ZP
  localparam logic [31:0] DDR4_GRU_WP_PROJ    = 32'h018A_8000; // 6KB   wp_proj FP32 (autoregressive)
  // BERT V2 (docs/KIEN_TRUC_BERT_V2.md §4): anh PARAM 57344 tu nap o static boot, 3 doan lien tiep
  localparam logic [31:0] DDR4_PARAM_A        = 32'h0190_0000; // 64KB  PARAM[0..16383]
  localparam logic [31:0] DDR4_PARAM_B        = 32'h0191_0000; // 128KB PARAM[16384..49151]
  localparam logic [31:0] DDR4_PARAM_C        = 32'h0193_0000; // 32KB  PARAM[49152..57343]

  // ── BERT weight layer strides ────────────────────────────────────────────────
  localparam logic [31:0] BERT_LAYER_STRIDE   = 32'h0018_0000; // 1.5MB per layer

  // ── Type aliases ────────────────────────────────────────────────────────────
  typedef logic [31:0] fp32_t;
  typedef logic  [7:0] int8_t;
  typedef logic [31:0] int32_t;
  typedef logic  [3:0] int4_t;

  // ── World-model token types ──────────────────────────────────────────────────
  typedef struct packed {
    fp32_t x_min, y_min, x_max, y_max, vx, vy;
  } bbox6_t;   // 24 bytes

  typedef bbox6_t token_t;  // token payload = bbox6_t for projector input

  typedef enum logic [3:0] {
    TT_CLS    = 4'd0,
    TT_EGO    = 4'd1,
    TT_OBJECT = 4'd2,
    TT_LANE   = 4'd3,
    TT_TARGET = 4'd4
  } token_type_t;

  typedef logic [MAX_SEQ_LEN-1:0] attn_mask_t;  // bit k=1 → token k is valid

  // ── BRAM / URAM address types ────────────────────────────────────────────────
  typedef logic [12:0] ln_bram_addr_t;    // LN BRAM, max 8191
  typedef logic [13:0] scale_bram_addr_t; // Scale BRAM, max 9215
  typedef logic [14:0] bias_bram_addr_t;  // Bias BRAM, max 18431
  typedef logic [14:0] pp_addr_t;         // Ping-pong / LN1_q, {tok[5:0],ch[8:0]}
  typedef logic [14:0] kv_addr_t;         // K/V scratch, {head[2:0],tok[5:0],d[5:0]}
  typedef logic [14:0] qkt_addr_t;        // QK^T scratch, {head[2:0],q[5:0],k[5:0]}
  typedef logic [18:0] uram_addr_t;       // {block[6:0], within[11:0]}

  // ── Shared_int8_macs op_sel encoding ────────────────────────────────────────
  localparam logic [2:0] OP_PROJ = 3'd0;  // feature_projector W_proj
  localparam logic [2:0] OP_WQ   = 3'd1;  // Query projection
  localparam logic [2:0] OP_WK   = 3'd2;  // Key projection
  localparam logic [2:0] OP_WV   = 3'd3;  // Value projection
  localparam logic [2:0] OP_W1   = 3'd4;  // FFN first layer (512→2048)
  localparam logic [2:0] OP_W2   = 3'd5;  // FFN second layer (2048→512)
  localparam logic [2:0] OP_WO   = 3'd6;  // Output projection

  // ── URAM base_block per op_sel ───────────────────────────────────────────────
  // W1: base = 16 + subpass×4; W2: base = 32 + subpass×4 [v15.4-S03]
  localparam int  URAM_BASE_WQ   = 0;
  localparam int  URAM_BASE_WK   = 4;
  localparam int  URAM_BASE_WV   = 8;
  localparam int  URAM_BASE_WO   = 12;
  localparam int  URAM_BASE_W1   = 16;  // + subpass_idx×4
  localparam int  URAM_BASE_W2   = 32;  // + subpass_idx×4

  // ── AXI HP0 parameters ───────────────────────────────────────────────────────
  localparam int  HP0_DATA_WIDTH  = 128;  // 128-bit AXI HP0
  localparam int  HP0_ADDR_WIDTH  = 32;
  localparam int  HP0_ID_WIDTH    = 6;

  // ── Ping-pong buffer address helper ─────────────────────────────────────────
  // pp_addr[14:0] = {token[5:0], channel[8:0]}
  function automatic pp_addr_t pp_addr(input logic [5:0] tok, input logic [8:0] ch);
    return {tok, ch};
  endfunction

  // ── K/V scratch address helper ───────────────────────────────────────────────
  function automatic kv_addr_t kv_addr(input logic [2:0] head, input logic [5:0] tok,
                                        input logic [5:0] d);
    return {head, tok, d};
  endfunction

  // ── QK^T scratch address helper ─────────────────────────────────────────────
  function automatic qkt_addr_t qkt_addr(input logic [2:0] head, input logic [5:0] q_tok,
                                          input logic [5:0] k_tok);
    return {head, q_tok, k_tok};
  endfunction

  // ── URAM BERT address helper ─────────────────────────────────────────────────
  // uram_addr[18:0] = {block[6:0], row[4:0], col[6:0]}
  function automatic uram_addr_t uram_bert_addr(
    input int          block,
    input logic  [4:0] row,
    input logic  [8:0] col   // word index within row (col >> 4 gives 64-bit word)
  );
    return {7'(block), row, col[6:0]};
  endfunction

  // ── Bias BRAM address helper ─────────────────────────────────────────────────
  function automatic bias_bram_addr_t bias_bram_addr(
    input logic  [1:0] layer,
    input int          mat_base,
    input logic  [8:0] ch
  );
    return 15'(layer) * 15'(BIAS_LAYER_STRIDE) + 15'(mat_base) + 15'(ch);
  endfunction

  // ── Scale BRAM packed address helper ─────────────────────────────────────────
  function automatic scale_bram_addr_t scale_bram_packed_addr(
    input logic  [1:0] layer,
    input int          mat_base,
    input logic  [8:0] ch
  );
    logic [14:0] raw;
    raw = 15'(layer) * 15'(SCALE_LAYER_STRIDE) + 15'(mat_base) + 15'(ch);
    return raw[14:1];  // >> 1: two channels packed per word
  endfunction

  // ── URAM WO base block ────────────────────────────────────────────────────────
  localparam int  URAM_WO_BASE_BLOCK  = URAM_BASE_WO;  // = 12


  //============================================================================
  // [Fix G] Thu vien FP32 IEEE-754 tong hop duoc — thay cho ma tam cua GRU.
  // Da kiem chung bit-exact voi numpy float32 tren 6000 vector (0 sai).
  // Luu y: shortreal cua xsim KHONG dung chuan IEEE nen tham chieu la numpy.
  //============================================================================
// ============================================================================
// FP32 (IEEE-754 single) tong hop duoc. Lam tron round-to-nearest-even.
// Denormal duoc xu ly nhu 0 (flush-to-zero) — du cho duong du lieu GRU.
// ============================================================================

function automatic logic [31:0] fp32_mul_f(input logic [31:0] a, input logic [31:0] b);
  logic        sr;
  logic [7:0]  ea, eb;
  logic [23:0] ma, mb;
  logic [47:0] p;
  logic signed [10:0] er;
  logic [22:0] frac;
  logic        g, r, s;
  logic [24:0] rnd;      // {carry, 1.frac}
  begin
    ea = a[30:23]; eb = b[30:23];
    sr = a[31] ^ b[31];
    if (ea == 8'hFF || eb == 8'hFF) return {sr, 8'hFF, 23'd0};
    if (ea == 8'd0  || eb == 8'd0)  return {sr, 31'd0};
    ma = {1'b1, a[22:0]};
    mb = {1'b1, b[22:0]};
    p  = ma * mb;                       // [2^46, 2^48)
    er = $signed({3'b0, ea}) + $signed({3'b0, eb}) - 11'sd127;
    if (p[47]) begin
      frac = p[46:24]; g = p[23]; r = p[22]; s = |p[21:0];
      er   = er + 11'sd1;
    end else begin
      frac = p[45:23]; g = p[22]; r = p[21]; s = |p[20:0];
    end
    rnd = {1'b0, 1'b1, frac} + 25'((g && (r || s || frac[0])) ? 1 : 0);
    if (rnd[24]) er = er + 11'sd1;      // 1.111..1 -> 10.0 : dinh tri lai thanh 1.0
    if (er >= 11'sd255) return {sr, 8'hFF, 23'd0};
    if (er <= 11'sd0)   return {sr, 31'd0};
    return {sr, er[7:0], rnd[24] ? 23'd0 : rnd[22:0]};
  end
endfunction

function automatic logic [31:0] fp32_add_f(input logic [31:0] a, input logic [31:0] b);
  logic [31:0] big, sml;
  logic        sa, sb, sr;
  logic [7:0]  ea, eb;
  logic [23:0] ma, mb;
  logic [7:0]  ed;
  logic [27:0] wa, wb, sum;
  logic [26:0] shifted;
  logic signed [10:0] er;
  logic [22:0] frac;
  logic        g, r, s;
  logic [24:0] rnd;
  int          lz;
  begin
    if (a[30:23] == 8'hFF) return a;
    if (b[30:23] == 8'hFF) return b;
    if (a[30:0]  == 31'd0) return b;
    if (b[30:0]  == 31'd0) return a;
    if (a[30:0] >= b[30:0]) begin big = a; sml = b; end
    else                    begin big = b; sml = a; end
    sa = big[31]; ea = big[30:23]; ma = {1'b1, big[22:0]};
    sb = sml[31]; eb = sml[30:23]; mb = {1'b1, sml[22:0]};
    sr = sa;
    ed = ea - eb;
    wa = {1'b0, ma, 3'b000};                       // bit 26 = an 1
    if (ed >= 8'd27) begin
      wb = 28'd0;
      if (mb != 24'd0) wb[0] = 1'b1;               // sticky
    end else begin
      shifted = {ma[23] ? mb : mb, 3'b000} >> ed;  // {mb,3'b0} >> ed
      wb = {1'b0, shifted};
      if (|(({mb, 3'b000}) & ((27'd1 << ed) - 27'd1))) wb[0] = 1'b1;
    end

    if (sa == sb) begin
      sum = wa + wb;
      er  = $signed({3'b0, ea});
      if (sum[27]) begin
        s   = sum[0];
        sum = sum >> 1;
        sum[0] = sum[0] | s;                        // giu sticky
        er  = er + 11'sd1;
      end
    end else begin
      sum = wa - wb;
      if (sum[26:0] == 27'd0) return 32'd0;
      lz = 0;
      while (!sum[26] && lz < 27) begin sum = sum << 1; lz++; end
      er = $signed({3'b0, ea}) - $signed(11'(lz));
    end

    frac = sum[25:3]; g = sum[2]; r = sum[1]; s = sum[0];
    rnd  = {1'b0, 1'b1, frac} + 25'((g && (r || s || frac[0])) ? 1 : 0);
    if (rnd[24]) er = er + 11'sd1;
    if (er >= 11'sd255) return {sr, 8'hFF, 23'd0};
    if (er <= 11'sd0)   return {sr, 31'd0};
    return {sr, er[7:0], rnd[24] ? 23'd0 : rnd[22:0]};
  end
endfunction

function automatic logic [31:0] fp32_sub_f(input logic [31:0] a, input logic [31:0] b);
  return fp32_add_f(a, {~b[31], b[30:0]});
endfunction


  // (int4 - zp) * scale_q8 * 2^-8  ->  FP32 chinh xac tuyet doi.
  // |prod| < 2^18 < 2^24 nen bieu dien duoc dung, khong can lam tron.
  function automatic logic [31:0] fp32_from_dequant(
      input logic [3:0] w_int4, input logic [7:0] w_zp, input logic [7:0] w_scale_q8);
    logic signed [4:0]  se;
    logic signed [9:0]  d;
    logic signed [18:0] prod;
    logic [18:0]        mag;
    logic               sgn;
    int                 msb;
    logic signed [10:0] er;
    logic [22:0]        frac;
    begin
      se   = {w_int4[3], w_int4};
      d    = $signed({{5{se[4]}}, se}) - $signed({2'b0, w_zp});
      prod = $signed(d) * $signed({11'b0, w_scale_q8});
      if (prod == 19'sd0) return 32'd0;
      sgn = prod[18];
      mag = sgn ? (~prod + 19'd1) : prod[18:0];
      msb = 0;
      for (int i = 18; i >= 0; i--) if (mag[i] && msb == 0) msb = i;
      er   = 11'sd127 + 11'(msb) - 11'sd8;
      frac = 23'(mag << (23 - msb));
      if (er <= 11'sd0) return {sgn, 31'd0};
      return {sgn, er[7:0], frac};
    end
  endfunction


  // [Fix S] FP32 -> so nguyen co dau, lam tron NUA-RA-XA-0 (khop nhanh golden:
  // $rtoi(r >= 0 ? r+0.5 : r-0.5)). Bao hoa +-1023 (du cho INT9 truoc khi kep).
  function automatic logic signed [10:0] fp32_to_int_round(input logic [31:0] v);
    logic        sg;
    logic [7:0]  ex;
    logic [23:0] mn;
    logic signed [10:0] sh;
    logic [40:0] w;
    logic [10:0] r;
    begin
      sg = v[31]; ex = v[30:23]; mn = {1'b1, v[22:0]};
      if (ex == 8'd0)   return 11'sd0;                    // 0 / denormal
      if (ex == 8'hFF)  return sg ? -11'sd1023 : 11'sd1023;
      sh = $signed({3'b0, ex}) - 11'sd127 - 11'sd23;      // gia tri = mn * 2^sh
      if (sh >= 0) begin
        if (sh > 11'sd10) return sg ? -11'sd1023 : 11'sd1023;
        w = 41'(mn) << sh[3:0];
      end else begin
        if (-sh > 11'sd25) return 11'sd0;                 // qua nho -> 0
        // lam tron nua-ra-xa-0: cong 2^(-sh-1) roi dich phai
        w = (41'(mn) + (41'd1 << (6'(-sh) - 6'd1))) >> 6'(-sh);
      end
      r = (w > 41'd1023) ? 11'd1023 : 11'(w);
      return sg ? -$signed(r) : $signed(r);
    end
  endfunction


  // [Fix T] So nguyen co dau (Q8) -> FP32 chinh xac tuyet doi: gia tri = prod * 2^-8.
  // |prod| < 2^18 < 2^24 nen bieu dien duoc dung, khong can lam tron.
  function automatic logic [31:0] fp32_from_q8(input logic signed [17:0] prod);
    logic [17:0] mag;
    logic        sgn;
    int          msb;
    logic signed [10:0] er;
    logic [22:0] frac;
    begin
      if (prod == 18'sd0) return 32'd0;
      sgn = prod[17];
      mag = sgn ? (~prod + 18'd1) : prod[17:0];
      msb = 0;
      for (int i = 17; i >= 0; i--) if (mag[i] && msb == 0) msb = i;
      er   = 11'sd127 + 11'(msb) - 11'sd8;
      frac = 23'(mag << (23 - msb));
      if (er <= 11'sd0) return {sgn, 31'd0};
      return {sgn, er[7:0], frac};
    end
  endfunction


  // [Fix U] Nghich dao FP32: 1/d. Dung cho cac thang do la HANG SO bien dich
  // (goi trong localparam) nen duoc gap thanh hang so luc elaborate, KHONG sinh
  // phan cung. Thuat toan: Q = floor(2^47 / mant24), Q thuoc (2^23, 2^24].
  function automatic logic [31:0] fp32_recip_f(input logic [31:0] d);
    logic [7:0]  ed;
    logic [24:0] den, rem, quo;
    logic [25:0] rem2;
    logic [8:0]  ef;
    begin
      ed = d[30:23];
      if (ed == 8'd0)   return 32'h7F800000;              // 1/0 -> +Inf
      if (ed == 8'hFF)  return 32'd0;                     // 1/Inf -> 0
      den = {2'b01, d[22:0]};                             // mant24
      rem = 25'd0;
      quo = 25'd0;
      for (int i = 47; i >= 0; i--) begin
        rem = (rem << 1) | 25'((i == 47) ? 1 : 0);
        if (rem >= den) begin
          rem = rem - den;
          quo = (quo << 1) | 25'd1;
        end else begin
          quo = (quo << 1);
        end
      end
      // [Fix U2] Lam tron toi gan nhat (truoc day cat -> lech 1 ULP o 250/511 ca).
      if ({1'b0, rem} << 1 >= {1'b0, den}) quo = quo + 25'd1;
      if (quo[24]) begin
        ef = 9'd254 - {1'b0, ed};
        if (ef[8] || ef == 9'd0) return {d[31], 31'd0};
        return {d[31], ef[7:0], 23'd0};
      end else begin
        ef = 9'd253 - {1'b0, ed};
        if (ef[8] || ef == 9'd0) return {d[31], 31'd0};
        return {d[31], ef[7:0], quo[22:0]};
      end
    end
  endfunction


  // [Fix W] FP32 -> Q1.14 co dau, lam tron toi gan nhat, bao hoa +-16383.
  // Ban cu trong attn_context_mac gan {1'b1, fp[22:8]} (16 bit) vao bien 15 bit
  // -> MAT BIT DAN DAU. Do duoc 600/600 sai.
  function automatic logic signed [15:0] fp32_to_q14(input logic [31:0] fp);
    logic [7:0]  ex;
    logic [23:0] mn;
    logic signed [10:0] sh;
    logic [40:0] w;
    begin
      ex = fp[30:23];
      if (ex == 8'd0) return 16'sd0;
      mn = {1'b1, fp[22:0]};
      // gia tri*2^14 = mn * 2^(ex-127+14-23) = mn * 2^(ex-136)
      sh = $signed({3'b0, ex}) - 11'sd136;
      if (sh >= 11'sd1) return fp[31] ? -16'sd16383 : 16'sd16383;   // bao hoa
      if (sh == 11'sd0) w = 41'(mn);
      else begin
        if (-sh > 11'sd25) return 16'sd0;
        w = (41'(mn) + (41'd1 << (6'(-sh) - 6'd1))) >> 6'(-sh);     // lam tron
      end
      if (w > 41'd16383) w = 41'd16383;
      return fp[31] ? -$signed(16'(w)) : $signed(16'(w));
    end
  endfunction

  // [Fix W] Bo tich luy Q14 32-bit -> FP32 (gia tri = acc * 2^-14), lam tron gan nhat.
  // Ban cu dich (24 - msb) -> AM khi msb > 24 -> dinh tri luon 0 -> dau ra luon la
  // luy thua cua 2. Do duoc 600/600 sai.
  function automatic logic [31:0] fp32_from_q14_32(input logic signed [31:0] acc);
    logic [31:0] mag;
    logic        sgn;
    int          msb;
    logic signed [10:0] er;
    logic [55:0] w;
    logic [24:0] rnd;
    begin
      if (acc == 32'sd0) return 32'd0;
      sgn = acc[31];
      mag = sgn ? (~acc + 32'd1) : acc;
      msb = 0;
      for (int i = 31; i >= 0; i--) if (mag[i] && msb == 0) msb = i;
      er = 11'sd127 + 11'(msb) - 11'sd14;
      if (msb <= 23) begin
        w   = 56'(mag) << (23 - msb);
        rnd = {1'b0, 24'(w)};
      end else begin
        // [Fix W2] Lam tron NUA-VE-CHAN (chuan IEEE-754), khong phai nua-len.
        // Truoc day nua-len -> lech 1 ULP o 78/600 ca, tat ca deu la diem hoa.
        automatic logic        g, st, ls;
        automatic logic [24:0] top;
        top = 25'(mag >> (msb - 23));              // 24 bit giu lai
        g   = mag[msb - 24];                        // bit canh
        st  = |(mag & ((32'd1 << (msb - 24)) - 32'd1));
        ls  = top[0];
        rnd = top + 25'((g && (st || ls)) ? 1 : 0);
        if (rnd[24]) begin rnd = rnd >> 1; er = er + 11'sd1; end
      end
      if (er >= 11'sd255) return {sgn, 8'hFF, 23'd0};
      if (er <= 11'sd0)   return {sgn, 31'd0};
      return {sgn, er[7:0], rnd[22:0]};
    end
  endfunction

endpackage : planning_pkg

//==============================================================================
// End of File
//==============================================================================
