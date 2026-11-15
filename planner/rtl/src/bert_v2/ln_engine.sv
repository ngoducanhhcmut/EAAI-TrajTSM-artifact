//==============================================================================
// ln_engine.sv — LayerNorm FP32 theo token (BERT V2). Chuan tung bit: hwspec_exact.layer_norm
//   s  = sum8(x) ; mu = fmul(s, 1/512)
//   d  = fsub(x, mu) ; v = fmul(sum8(fmul(d,d)), 1/512) ; r = rsqrt(fadd(v, eps))
//   y  = fadd(fmul(fmul(d, r), w), b)
// sum8: phan tu c cong vao tong rieng c mod 8 (bat dau +0) theo thu tu c tang, roi cay
//       ((p0+p1)+(p2+p3)) + ((p4+p5)+(p6+p7)).
// dst : 0 = COL A (RNE_sat(fmul(y, inv_s))) cot c byte t ; 1 = XR tai cho ; 2 = cls (FP32)
// ntok: so token (64, hoac 1 cho final LN — chi token 0).
//
// LICH CHU KY (moi phan tu phat o chu ky C0; "dang ky o E(k)" = gan <= o canh cuoi Ck-1):
//   Moi don vi FP co dau vao la thanh ghi: dang ky o E(k) -> ket qua hop le trong C(k+3).
//   RAM (XR, PARAM, dbuf) doc tre 2: dia chi o C0 -> du lieu hop le trong C2.
// Luot 1 : C2 dang ky fadd A (rf[c%8], x) -> C6 ket qua -> ghi rf o E7.
// Luot 2 : C2 dang ky fsub (x, -mu) -> C6 d: ghi dbuf, dang ky fmul A (d,d) -> C10
//          dang ky fadd A (rf[c%8], d*d) -> C14 ghi rf.
// Luot 3 : C2 dang ky fmul A (d, r) -> C6 dang ky fmul B (., w) -> C10 dang ky fadd B (., b)
//          -> C14 = y : ghi XR/cls ; dang ky fmul C (y, inv_s) -> C18 -> f2i -> C20 ghi COL.
// Hai phan tu cung tong rieng cach nhau 8 chu ky > do tre vong (luot 1: 5, luot 2: 5) -> khong xung dot.
//==============================================================================
`timescale 1ns / 1ps

module ln_engine (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  output logic        done,
  input  logic [1:0]  dst,
  input  logic [6:0]  ntok,
  input  logic [15:0] w_base,
  input  logic [15:0] b_base,
  input  logic [31:0] inv_s,
  output logic        xr_re,
  output logic [14:0] xr_raddr,
  input  logic [31:0] xr_rd,
  output logic        xr_we,
  output logic [14:0] xr_waddr,
  output logic [31:0] xr_wd,
  output logic        pa_re,
  output logic [15:0] pa_addr,
  input  logic [31:0] pa_rd,
  output logic        pb_re,
  output logic [15:0] pb_addr,
  input  logic [31:0] pb_rd,
  output logic        col_we,
  output logic [11:0] col_waddr,
  output logic [5:0]  col_wb,
  output logic [7:0]  col_wd,
  output logic        cls_we,
  output logic [8:0]  cls_waddr,
  output logic [31:0] cls_wd
);
  localparam logic [31:0] INV512 = 32'h3B000000;     // 2^-9
  localparam logic [31:0] EPS    = 32'h3727C5AC;     // F32(1e-5)
  localparam int NP = 21;                             // do dai ong phan tu (C0..C20)

  typedef enum logic [3:0] {S_IDLE, S_P1, S_P1W, S_TREE, S_MU, S_P2, S_P2W, S_VAR,
                            S_EPS, S_RSQ, S_P3, S_P3W, S_NEXT} st_t;
  st_t         st;
  logic        pass2;          // cay dang cho luot 2
  logic [5:0]  t;
  logic [9:0]  c;
  logic [5:0]  wcnt;
  logic [2:0]  tstep;
  logic [31:0] rf [15];        // p0..p7 = 0..7, q0..q3 = 8..11, r0,r1 = 12,13, tong = 14
  logic [31:0] mu, rstd;

  // ── don vi FP (dau vao thanh ghi) ───────────────────────────────────────────
  logic [31:0] aa_a, aa_b, aa_r, sb_a, sb_b, sb_r, ma_a, ma_b, ma_r;
  logic [31:0] mb_a, mb_b, mb_r, ab_a, ab_b, ab_r, mc_a, mc_r;
  logic signed [15:0] q_r;
  fp32_add_p u_aa (.clk, .a(aa_a), .b(aa_b), .r(aa_r));
  fp32_add_p u_sb (.clk, .a(sb_a), .b(sb_b), .r(sb_r));
  fp32_mul_p u_ma (.clk, .a(ma_a), .b(ma_b), .r(ma_r));
  fp32_mul_p u_mb (.clk, .a(mb_a), .b(mb_b), .r(mb_r));
  fp32_add_p u_ab (.clk, .a(ab_a), .b(ab_b), .r(ab_r));
  fp32_mul_p u_mc (.clk, .a(mc_a), .b(inv_s), .r(mc_r));
  fp32_f2i_p #(.LO(-128), .HI(127)) u_q (.clk, .x(mc_r), .r(q_r));

  logic        rs_start, rs_done;
  logic [31:0] rs_v, rs_r;
  fp32_nr_seq #(.MODE(1'b0)) u_rs (.clk, .rst_n, .start(rs_start), .v(rs_v), .done(rs_done), .r(rs_r));

  // ── ong phan tu: e_v[i] / e_c[i] = phan tu phat i chu ky truoc (i >= 1) ───
  logic       e_v [1:NP-1];
  logic [8:0] e_c [1:NP-1];
  logic [1:0] e_ps [1:NP-1];        // 1 = luot 1, 2 = luot 2, 3 = luot 3
  logic       iss;                   // phat phan tu o chu ky nay (C0)
  logic [1:0] iss_ps;
  assign iss    = (st == S_P1) || (st == S_P2) || (st == S_P3);
  assign iss_ps = (st == S_P1) ? 2'd1 : (st == S_P2) ? 2'd2 : 2'd3;

  // the cho ket qua fadd A -> rf: a_v[i] hop le trong C(dang ky + i), ghi o i = 3
  logic       a_v [4];
  logic [3:0] a_tg [4];
  logic       a_iss;  logic [3:0] a_itg;   // (combinational) dang ky fadd A o canh nay

  // dbuf: RAM doc tre 2
  (* ram_style = "block" *) logic [31:0] dbuf [512];
  logic [31:0] dq, d_rd;
  logic [31:0] w_d [4];          // w: C2 -> C6
  logic [31:0] b_d [8];          // b: C2 -> C10

  // ── dia chi doc (C0) ────────────────────────────────────────────────────────
  assign xr_re    = iss && (iss_ps != 2'd3);
  assign xr_raddr = {t, c[8:0]};
  assign pa_re    = iss && (iss_ps == 2'd3);
  assign pa_addr  = w_base + 16'(c[8:0]);
  assign pb_re    = pa_re;
  assign pb_addr  = b_base + 16'(c[8:0]);

  always_ff @(posedge clk) begin          // dbuf: RAM rieng (khong reset) -> BRAM/LUTRAM
    if (e_v[6] && e_ps[6] == 2'd2) dbuf[e_c[6]] <= sb_r;
    if (iss && iss_ps == 2'd3) dq <= dbuf[c[8:0]];
    d_rd <= dq;
    w_d[0] <= pa_rd; for (int i = 1; i < 4; i++) w_d[i] <= w_d[i-1];
    b_d[0] <= pb_rd; for (int i = 1; i < 8; i++) b_d[i] <= b_d[i-1];
  end
  // Chu y can chinh: w_d[k] hop le trong C(3+k) cho phan tu phat o C0 -> w_d[3] o C6.
  //                  b_d[k] hop le trong C(3+k)                    -> b_d[7] o C10.

  // ── dieu khien + moi dau vao FP (MOT khoi) ──────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE; done <= 1'b0; t <= '0; c <= '0; wcnt <= '0; tstep <= '0; pass2 <= 1'b0;
      rs_start <= 1'b0;
      for (int i = 1; i < NP; i++) e_v[i] <= 1'b0;
      for (int i = 0; i < 4; i++) a_v[i] <= 1'b0;
    end else begin
      done <= 1'b0;
      rs_start <= 1'b0;
      if (wcnt != 0) wcnt <= wcnt - 6'd1;

      // ong phan tu
      e_v[1] <= iss; e_c[1] <= c[8:0]; e_ps[1] <= iss_ps;
      for (int i = 2; i < NP; i++) begin e_v[i] <= e_v[i-1]; e_c[i] <= e_c[i-1]; e_ps[i] <= e_ps[i-1]; end

      // ong the fadd A
      a_v[0] <= 1'b0;
      for (int i = 1; i < 4; i++) begin a_v[i] <= a_v[i-1]; a_tg[i] <= a_tg[i-1]; end
      if (a_v[3]) rf[a_tg[3]] <= aa_r;

      // ── su kien theo phan tu ──
      // C2: luot 1 -> fadd A ; luot 2 -> fsub ; luot 3 -> fmul A (d, r)
      if (e_v[2] && e_ps[2] == 2'd1) begin
        aa_a <= rf[{1'b0, e_c[2][2:0]}]; aa_b <= xr_rd;
        a_v[0] <= 1'b1; a_tg[0] <= {1'b0, e_c[2][2:0]};
      end
      if (e_v[2] && e_ps[2] == 2'd2) begin sb_a <= xr_rd; sb_b <= {~mu[31], mu[30:0]}; end
      if (e_v[2] && e_ps[2] == 2'd3) begin ma_a <= d_rd; ma_b <= rstd; end
      // C6: luot 2 -> luu d, fmul A (d,d) ; luot 3 -> fmul B (., w)
      if (e_v[6] && e_ps[6] == 2'd2) begin ma_a <= sb_r; ma_b <= sb_r; end
      if (e_v[6] && e_ps[6] == 2'd3) begin mb_a <= ma_r; mb_b <= w_d[3]; end
      // C10: luot 2 -> fadd A (rf, d*d) ; luot 3 -> fadd B (., b)
      if (e_v[10] && e_ps[10] == 2'd2) begin
        aa_a <= rf[{1'b0, e_c[10][2:0]}]; aa_b <= ma_r;
        a_v[0] <= 1'b1; a_tg[0] <= {1'b0, e_c[10][2:0]};
      end
      if (e_v[10] && e_ps[10] == 2'd3) begin ab_a <= mb_r; ab_b <= b_d[7]; end
      // C14: luot 3 -> fmul C (y, inv_s)
      if (e_v[14] && e_ps[14] == 2'd3) mc_a <= ab_r;

      case (st)
        S_IDLE: if (start) begin
          t <= '0; c <= '0; st <= S_P1;
          for (int i = 0; i < 8; i++) rf[i] <= 32'd0;
        end
        S_P1: begin
          if (c == 10'd511) begin c <= '0; wcnt <= 6'd10; st <= S_P1W; end
          else c <= c + 10'd1;
        end
        S_P1W: if (wcnt == 0) begin tstep <= '0; pass2 <= 1'b0; st <= S_TREE; end
        S_TREE: if (wcnt == 0) begin
          case (tstep)
            3'd0, 3'd1, 3'd2, 3'd3: begin
              aa_a <= rf[{1'b0, tstep[1:0], 1'b0}]; aa_b <= rf[{1'b0, tstep[1:0], 1'b1}];
              a_v[0] <= 1'b1; a_tg[0] <= 4'(8 + tstep);
              if (tstep == 3'd3) wcnt <= 6'd5;
              tstep <= tstep + 3'd1;
            end
            3'd4, 3'd5: begin
              aa_a <= (tstep == 3'd4) ? rf[8] : rf[10];
              aa_b <= (tstep == 3'd4) ? rf[9] : rf[11];
              a_v[0] <= 1'b1; a_tg[0] <= (tstep == 3'd4) ? 4'd12 : 4'd13;
              if (tstep == 3'd5) wcnt <= 6'd5;
              tstep <= tstep + 3'd1;
            end
            3'd6: begin
              aa_a <= rf[12]; aa_b <= rf[13];
              a_v[0] <= 1'b1; a_tg[0] <= 4'd14;
              wcnt <= 6'd5; tstep <= 3'd7;
            end
            default: begin
              ma_a <= rf[14]; ma_b <= INV512; wcnt <= 6'd4;
              st <= pass2 ? S_VAR : S_MU;
            end
          endcase
        end
        S_MU: if (wcnt == 0) begin
          mu <= ma_r; c <= '0; st <= S_P2;
          for (int i = 0; i < 8; i++) rf[i] <= 32'd0;
        end
        S_P2: begin
          if (c == 10'd511) begin c <= '0; wcnt <= 6'd18; st <= S_P2W; end
          else c <= c + 10'd1;
        end
        S_P2W: if (wcnt == 0) begin tstep <= '0; pass2 <= 1'b1; st <= S_TREE; end
        S_VAR: if (wcnt == 0) begin aa_a <= ma_r; aa_b <= EPS; wcnt <= 6'd4; st <= S_EPS; end
        S_EPS: if (wcnt == 0) begin rs_v <= aa_r; rs_start <= 1'b1; st <= S_RSQ; end
        S_RSQ: if (rs_done) begin rstd <= rs_r; c <= '0; st <= S_P3; end
        S_P3: begin
          if (c == 10'd511) begin c <= '0; wcnt <= 6'd24; st <= S_P3W; end
          else c <= c + 10'd1;
        end
        S_P3W: if (wcnt == 0) st <= S_NEXT;
        S_NEXT: begin
          if (7'(t) + 7'd1 >= ntok) begin done <= 1'b1; st <= S_IDLE; end
          else begin
            t <= t + 6'd1; c <= '0; st <= S_P1;
            for (int i = 0; i < 8; i++) rf[i] <= 32'd0;
          end
        end
        default: st <= S_IDLE;
      endcase
    end
  end

  // ── ghi dau ra ──────────────────────────────────────────────────────────────
  assign xr_we     = e_v[14] && e_ps[14] == 2'd3 && dst == 2'd1;
  assign xr_waddr  = {t, e_c[14]};
  assign xr_wd     = ab_r;
  assign cls_we    = e_v[14] && e_ps[14] == 2'd3 && dst == 2'd2;
  assign cls_waddr = e_c[14];
  assign cls_wd    = ab_r;
  assign col_we    = e_v[20] && e_ps[20] == 2'd3 && dst == 2'd0;
  assign col_waddr = {3'd0, e_c[20]};
  assign col_wb    = t;
  assign col_wd    = q_r[7:0];
endmodule : ln_engine
