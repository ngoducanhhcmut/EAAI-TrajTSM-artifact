//==============================================================================
// fp32_units.sv — don vi FP32 co duong ong cho BERT V2 (docs/KIEN_TRUC_BERT_V2.md)
//
// Chuan: sw/hwspec/fp.py — IEEE-754 single, RNE, ket qua |r| < 2^-126 -> 0 co dau
// (FTZ). Dau vao khong bao gio denormal. Khong co NaN/inf trong du lieu (inf duoc
// truyen qua cho an toan).
//
//   fp32_add_p  : LAT = 3   r = a + b   (+0 + -0 = +0, -0 + -0 = -0, x - x = +0)
//   fp32_mul_p  : LAT = 3   r = a * b
//   fp32_i2f_p  : LAT = 2   INT32 -> FP32 RNE
//   fp32_f2i_p  : LAT = 2   FP32 -> so nguyen RNE, bao hoa [LO, HI]
//
// Moi khoi la duong ong thuan (khong valid): ket qua cua dau vao o chu ky c xuat
// hien o chu ky c + LAT. Ben dieu khien tu mang co valid song song.
//==============================================================================
`timescale 1ns / 1ps

// LEGACY_ZERO = 1: hai toan hang deu bang 0 -> tra b (giong HET fp32_add_f trong planning_pkg,
// dung cho GRU da kiem chung). LEGACY_ZERO = 0: theo IEEE (+0 + -0 = +0).
module fp32_add_p #(
  parameter bit LEGACY_ZERO = 1'b0
) (
  input  logic        clk,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] r
);
  // ── Tang 1: dac biet, sap xep do lon, can chinh ──────────────────────────────
  logic        s1_spec;      // ket qua dac biet (inf / mot ve bang 0)
  logic [31:0] s1_spec_val;
  logic        s1_sr, s1_sub;
  logic [7:0]  s1_ea;
  logic [27:0] s1_wa, s1_wb;

  always_ff @(posedge clk) begin
    logic [31:0] big, sml;
    logic [7:0]  ed;
    logic [23:0] ma, mb;
    logic [26:0] mbx, shifted;
    logic        stk;
    s1_spec     <= 1'b0;
    s1_spec_val <= '0;
    if (a[30:23] == 8'hFF)          begin s1_spec <= 1'b1; s1_spec_val <= a; end
    else if (b[30:23] == 8'hFF)     begin s1_spec <= 1'b1; s1_spec_val <= b; end
    else if (a[30:0] == 31'd0 && b[30:0] == 31'd0)
                                    begin s1_spec <= 1'b1; s1_spec_val <= LEGACY_ZERO ? b : {a[31] & b[31], 31'd0}; end
    else if (a[30:0] == 31'd0)      begin s1_spec <= 1'b1; s1_spec_val <= b; end
    else if (b[30:0] == 31'd0)      begin s1_spec <= 1'b1; s1_spec_val <= a; end

    if (a[30:0] >= b[30:0]) begin big = a; sml = b; end
    else                    begin big = b; sml = a; end
    ma  = {1'b1, big[22:0]};
    mb  = {1'b1, sml[22:0]};
    ed  = big[30:23] - sml[30:23];
    mbx = {mb, 3'b000};
    if (ed >= 8'd27) begin
      shifted = 27'd0;
      stk     = 1'b1;                                  // mb != 0 luon dung
    end else begin
      shifted = mbx >> ed;
      stk     = |(mbx & ((27'd1 << ed) - 27'd1));
    end
    s1_sr  <= big[31];
    s1_sub <= big[31] ^ sml[31];
    s1_ea  <= big[30:23];
    s1_wa  <= {1'b0, ma, 3'b000};
    s1_wb  <= {1'b0, shifted[26:1], shifted[0] | stk};
  end

  // ── Tang 2: cong/tru, dem so 0 dau ──────────────────────────────────────────
  logic        s2_spec;
  logic [31:0] s2_spec_val;
  logic        s2_sr, s2_zero;
  logic signed [10:0] s2_er;
  logic [27:0] s2_sum;
  logic [4:0]  s2_lz;

  always_ff @(posedge clk) begin
    logic [27:0] sum;
    logic        st;
    logic [4:0]  lz;
    s2_spec     <= s1_spec;
    s2_spec_val <= s1_spec_val;
    s2_sr       <= s1_sr;
    s2_zero     <= 1'b0;
    if (!s1_sub) begin
      sum = s1_wa + s1_wb;
      if (sum[27]) begin
        st  = sum[0];
        sum = sum >> 1;
        sum[0] = sum[0] | st;
        s2_er <= $signed({3'b0, s1_ea}) + 11'sd1;
      end else begin
        s2_er <= $signed({3'b0, s1_ea});
      end
      lz = 5'd0;
    end else begin
      sum = s1_wa - s1_wb;
      if (sum[26:0] == 27'd0) s2_zero <= 1'b1;
      lz = 5'd0;
      for (int i = 0; i <= 26; i++)          // bit 1 cao nhat thang (ghi de sau cung)
        if (sum[i]) lz = 5'(26 - i);
      s2_er <= $signed({3'b0, s1_ea});
    end
    s2_sum <= sum;
    s2_lz  <= lz;
  end

  // ── Tang 3: chuan hoa, lam tron RNE, dong goi ─────────────────────────────────
  always_ff @(posedge clk) begin
    logic [27:0] sum;
    logic signed [10:0] er;
    logic [22:0] frac;
    logic        g, rb, s;
    logic [24:0] rnd;
    sum  = s2_sum << s2_lz;
    er   = s2_er - $signed({6'd0, s2_lz});
    frac = sum[25:3]; g = sum[2]; rb = sum[1]; s = sum[0];
    rnd  = {1'b0, 1'b1, frac} + 25'((g && (rb || s || frac[0])) ? 1 : 0);
    if (rnd[24]) er = er + 11'sd1;
    if (s2_spec)                 r <= s2_spec_val;
    else if (s2_zero)            r <= 32'd0;
    else if (er >= 11'sd255)     r <= {s2_sr, 8'hFF, 23'd0};
    else if (er <= 11'sd0)       r <= {s2_sr, 31'd0};
    else                         r <= {s2_sr, er[7:0], rnd[24] ? 23'd0 : rnd[22:0]};
  end
endmodule : fp32_add_p


module fp32_mul_p (
  input  logic        clk,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] r
);
  logic        s1_sr, s1_zero, s1_inf;
  logic signed [10:0] s1_er;
  logic [23:0] s1_ma, s1_mb;
  logic [47:0] s2_p;
  logic        s2_sr, s2_zero, s2_inf;
  logic signed [10:0] s2_er;

  always_ff @(posedge clk) begin
    s1_sr   <= a[31] ^ b[31];
    s1_inf  <= (a[30:23] == 8'hFF) || (b[30:23] == 8'hFF);
    s1_zero <= (a[30:23] == 8'd0)  || (b[30:23] == 8'd0);
    s1_er   <= $signed({3'b0, a[30:23]}) + $signed({3'b0, b[30:23]}) - 11'sd127;
    s1_ma   <= {1'b1, a[22:0]};
    s1_mb   <= {1'b1, b[22:0]};
  end

  always_ff @(posedge clk) begin
    s2_p    <= s1_ma * s1_mb;
    s2_sr   <= s1_sr;
    s2_zero <= s1_zero;
    s2_inf  <= s1_inf;
    s2_er   <= s1_er;
  end

  always_ff @(posedge clk) begin
    logic signed [10:0] er;
    logic [22:0] frac;
    logic        g, rb, s;
    logic [24:0] rnd;
    er = s2_er;
    if (s2_p[47]) begin
      frac = s2_p[46:24]; g = s2_p[23]; rb = s2_p[22]; s = |s2_p[21:0];
      er   = er + 11'sd1;
    end else begin
      frac = s2_p[45:23]; g = s2_p[22]; rb = s2_p[21]; s = |s2_p[20:0];
    end
    rnd = {1'b0, 1'b1, frac} + 25'((g && (rb || s || frac[0])) ? 1 : 0);
    if (rnd[24]) er = er + 11'sd1;
    if (s2_inf)                  r <= {s2_sr, 8'hFF, 23'd0};
    else if (s2_zero)            r <= {s2_sr, 31'd0};
    else if (er >= 11'sd255)     r <= {s2_sr, 8'hFF, 23'd0};
    else if (er <= 11'sd0)       r <= {s2_sr, 31'd0};
    else                         r <= {s2_sr, er[7:0], rnd[24] ? 23'd0 : rnd[22:0]};
  end
endmodule : fp32_mul_p


module fp32_i2f_p (
  input  logic               clk,
  input  logic signed [31:0] x,
  output logic        [31:0] r
);
  logic        s1_sign, s1_zero;
  logic [31:0] s1_mag;
  logic [4:0]  s1_msb;

  always_ff @(posedge clk) begin
    logic [31:0] mag;
    logic [4:0]  msb;
    mag = x[31] ? (~x + 32'd1) : x;       // -2^31 -> 2^31 (dung: khong dau 32 bit)
    msb = 5'd0;
    for (int i = 0; i < 32; i++) if (mag[i]) msb = 5'(i);
    s1_sign <= x[31];
    s1_zero <= (x == 32'sd0);
    s1_mag  <= mag;
    s1_msb  <= msb;
  end

  always_ff @(posedge clk) begin
    logic [55:0] w;        // mag dich trai de bit msb nam o vi tri 55
    logic [22:0] frac;
    logic        g, s;
    logic [24:0] rnd;
    logic [7:0]  e;
    w    = {24'd0, s1_mag} << (5'd31 - s1_msb) << 24;
    frac = w[54:32]; g = w[31]; s = |w[30:0];
    rnd  = {1'b0, 1'b1, frac} + 25'((g && (s || frac[0])) ? 1 : 0);
    e    = 8'd127 + {3'd0, s1_msb} + (rnd[24] ? 8'd1 : 8'd0);
    if (s1_zero) r <= 32'd0;
    else         r <= {s1_sign, e, rnd[24] ? 23'd0 : rnd[22:0]};
  end
endmodule : fp32_i2f_p


// FP32 -> so nguyen RNE, bao hoa [LO, HI]. Dau ra so co dau rong 16 bit.
module fp32_f2i_p #(
  parameter int LO = -128,
  parameter int HI = 127
) (
  input  logic               clk,
  input  logic        [31:0] x,
  output logic signed [15:0] r
);
  logic        s1_sign, s1_big, s1_small;
  logic [23:0] s1_int;       // phan nguyen cua |x| (khi |x| < 2^16)
  logic        s1_g, s1_s;

  always_ff @(posedge clk) begin
    logic [7:0]  e;
    logic [23:0] m;
    logic [47:0] w;
    int          sh;
    e = x[30:23];
    m = {1'b1, x[22:0]};
    s1_sign  <= x[31];
    s1_big   <= (e >= 8'd142);           // |x| >= 2^15 -> chac chan bao hoa
    s1_small <= (e < 8'd126);            // |x| < 0.5   -> 0
    // |x| = m * 2^(e-150). Dua ve {int[23:0], frac[23:0]}: w = m << (e-126), cat 24 bit thap la phan le
    sh = int'(e) - 126;                  // 0..15 khi khong big/small
    if (sh < 0) sh = 0;
    if (sh > 16) sh = 16;
    w = {24'd0, m} << sh;                // bit 23 cua m o vi tri 23+sh ; gia tri = w * 2^-24
    s1_int <= w[47:24];
    s1_g   <= w[23];
    s1_s   <= |w[22:0];
  end

  always_ff @(posedge clk) begin
    logic [24:0] q;
    logic signed [26:0] v;
    if (s1_small) q = 25'd0;
    else          q = {1'b0, s1_int} + 25'((s1_g && (s1_s || s1_int[0])) ? 1 : 0);
    v = s1_sign ? -$signed({2'b0, q}) : $signed({2'b0, q});
    if (s1_big)                r <= s1_sign ? 16'(LO) : 16'(HI);
    else if (v > HI)           r <= 16'(HI);
    else if (v < LO)           r <= 16'(LO);
    else                       r <= v[15:0];
  end
endmodule : fp32_f2i_p
