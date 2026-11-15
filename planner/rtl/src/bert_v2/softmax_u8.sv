//==============================================================================
// softmax_u8.sv — softmax 1 dau (64 hang x 64 khoa) ra xac suat u8 (BERT V2)
// Chuan tung bit: hwspec_exact.softmax_u8
//   s = fmul(i2f(acc), c_qk) ; m = fmul(i2f(rowmax), c_qk)   (don dieu => = max s)
//   e = hop le ? exp_neg(fsub(s, m)) : 0
//   S = sum8(e) (khoa j -> tong rieng j mod 8, roi cay) ; g = fmul(recip(S), 255)
//   p = RNE_sat(fmul(e, g), 0, 255) -> COL cot (P8_BASE + j) byte i
// Lich luot A (khoa j phat o C0): SC hop le C2 -> i2f C4 -> fmul C7 -> fsub C10 -> exp C16
//   -> ghi ebuf + fadd tong rieng (dau vao to hop) -> C19 ghi rf o E20.
// Tuan tu theo hang (chua chong lap hang).
//==============================================================================
`timescale 1ns / 1ps

module softmax_u8 #(
  parameter int P8_BASE = 1024
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               start,
  output logic               done,
  input  logic [31:0]        c_qk,
  input  logic [63:0]        key_valid,
  input  logic signed [31:0] rowmax [64],
  output logic               sc_re,
  output logic [11:0]        sc_raddr,
  input  logic [31:0]        sc_rd,
  output logic               col_we,
  output logic [11:0]        col_waddr,
  output logic [5:0]         col_wb,
  output logic [7:0]         col_wd
);
  localparam logic [31:0] C255 = 32'h437F0000;

  typedef enum logic [3:0] {S_IDLE, S_M, S_A, S_AW, S_TREE, S_RC, S_G, S_B, S_BW, S_NEXT} st_t;
  st_t st;
  logic [5:0]  i;           // hang
  logic [6:0]  j;           // bo dem khoa
  logic [5:0]  wcnt;
  logic [2:0]  tstep;
  logic [31:0] rf [15];
  logic [31:0] m_r, g_r;
  logic [31:0] ebuf [64];

  // ── chuoi luot A (to hop giua cac don vi) ───────────────────────────────────
  logic [31:0] f_a, s_a, d_a, e_a;
  fp32_i2f_p     u_i2f (.clk, .x(sc_rd), .r(f_a));
  fp32_mul_p     u_ms  (.clk, .a(f_a), .b(c_qk), .r(s_a));
  fp32_add_p     u_sub (.clk, .a(s_a), .b({~m_r[31], m_r[30:0]}), .r(d_a));
  fp32_exp_neg_p u_exp (.clk, .x(d_a), .r(e_a));

  // ong phan tu luot A: a_v[k] = khoa phat k chu ky truoc
  logic       a_v [1:16];
  logic [5:0] a_j [1:16];
  logic [31:0] e_fin;
  assign e_fin = key_valid[a_j[16]] ? e_a : 32'd0;

  // fadd tich luy / cay (dau vao to hop)
  logic [31:0] ac_a, ac_b, ac_r;
  logic        ac_iss;
  logic [3:0]  ac_tg;
  fp32_add_p u_acc (.clk, .a(ac_a), .b(ac_b), .r(ac_r));
  logic       t_v [1:3];
  logic [3:0] t_tg [1:3];

  // m: i2f(rowmax[i]) * c_qk
  logic [31:0] fm, mm_r;
  fp32_i2f_p u_i2fm (.clk, .x(rowmax[i]), .r(fm));
  fp32_mul_p u_mm   (.clk, .a(fm), .b(c_qk), .r(mm_r));

  // recip + g
  logic rc_start, rc_done; logic [31:0] rc_r, g_out;
  fp32_nr_seq #(.MODE(1'b1)) u_rc (.clk, .rst_n, .start(rc_start), .v(rf[14]), .done(rc_done), .r(rc_r));
  fp32_mul_p u_g (.clk, .a(rc_r), .b(C255), .r(g_out));

  // luot B: p = f2i_u8(fmul(e, g))
  logic [31:0] eb_q, pb_m;
  logic signed [15:0] pb_q;
  fp32_mul_p u_mp (.clk, .a(eb_q), .b(g_r), .r(pb_m));
  fp32_f2i_p #(.LO(0), .HI(255)) u_p (.clk, .x(pb_m), .r(pb_q));
  logic       b_v [1:6];
  logic [5:0] b_j [1:6];

  // to hop cho fadd tich luy
  always_comb begin
    ac_iss = 1'b0; ac_tg = '0; ac_a = '0; ac_b = '0;
    if (a_v[16]) begin
      ac_iss = 1'b1; ac_tg = {1'b0, a_j[16][2:0]}; ac_a = rf[{1'b0, a_j[16][2:0]}]; ac_b = e_fin;
    end else if (st == S_TREE && wcnt == 0) begin
      case (tstep)
        3'd0, 3'd1, 3'd2, 3'd3: begin
          ac_iss = 1'b1; ac_tg = 4'(8 + tstep);
          ac_a = rf[{1'b0, tstep[1:0], 1'b0}]; ac_b = rf[{1'b0, tstep[1:0], 1'b1}];
        end
        3'd4: begin ac_iss = 1'b1; ac_tg = 4'd12; ac_a = rf[8];  ac_b = rf[9];  end
        3'd5: begin ac_iss = 1'b1; ac_tg = 4'd13; ac_a = rf[10]; ac_b = rf[11]; end
        3'd6: begin ac_iss = 1'b1; ac_tg = 4'd14; ac_a = rf[12]; ac_b = rf[13]; end
        default: ;
      endcase
    end
  end

  assign sc_re    = (st == S_A);
  assign sc_raddr = {i, j[5:0]};

  always_ff @(posedge clk) begin
    eb_q <= ebuf[j[5:0]];      // luot B: doc ebuf (tre 1) -> fmul to hop
    if (a_v[16]) ebuf[a_j[16]] <= e_fin;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE; done <= 1'b0; i <= '0; j <= '0; wcnt <= '0; tstep <= '0; rc_start <= 1'b0;
      for (int k = 1; k <= 16; k++) a_v[k] <= 1'b0;
      for (int k = 1; k <= 3; k++) t_v[k] <= 1'b0;
      for (int k = 1; k <= 6; k++) b_v[k] <= 1'b0;
    end else begin
      done <= 1'b0;
      rc_start <= 1'b0;
      if (wcnt != 0) wcnt <= wcnt - 6'd1;
      a_v[1] <= (st == S_A); a_j[1] <= j[5:0];
      for (int k = 2; k <= 16; k++) begin a_v[k] <= a_v[k-1]; a_j[k] <= a_j[k-1]; end
      t_v[1] <= ac_iss; t_tg[1] <= ac_tg;
      for (int k = 2; k <= 3; k++) begin t_v[k] <= t_v[k-1]; t_tg[k] <= t_tg[k-1]; end
      if (t_v[3]) rf[t_tg[3]] <= ac_r;
      b_v[1] <= (st == S_B); b_j[1] <= j[5:0];
      for (int k = 2; k <= 6; k++) begin b_v[k] <= b_v[k-1]; b_j[k] <= b_j[k-1]; end

      case (st)
        S_IDLE: if (start) begin i <= '0; st <= S_M; wcnt <= 6'd6; end
        S_M: if (wcnt == 0) begin                    // m san sang (i2f 2 + fmul 3)
          m_r <= mm_r; j <= '0; st <= S_A;
          for (int k = 0; k < 8; k++) rf[k] <= 32'd0;
        end
        S_A: begin
          if (j == 7'd63) begin j <= '0; wcnt <= 6'd22; st <= S_AW; end
          else j <= j + 7'd1;
        end
        S_AW: if (wcnt == 0) begin tstep <= '0; st <= S_TREE; end
        S_TREE: if (wcnt == 0) begin
          case (tstep)
            3'd3, 3'd5: begin wcnt <= 6'd4; tstep <= tstep + 3'd1; end
            3'd6: begin wcnt <= 6'd4; tstep <= 3'd7; end
            3'd7: begin rc_start <= 1'b1; st <= S_RC; end
            default: tstep <= tstep + 3'd1;
          endcase
        end
        S_RC: if (rc_done) begin wcnt <= 6'd4; st <= S_G; end
        S_G: if (wcnt == 0) begin g_r <= g_out; j <= '0; st <= S_B; end
        S_B: begin
          if (j == 7'd63) begin j <= '0; wcnt <= 6'd8; st <= S_BW; end
          else j <= j + 7'd1;
        end
        S_BW: if (wcnt == 0) st <= S_NEXT;
        S_NEXT: begin
          if (i == 6'd63) begin done <= 1'b1; st <= S_IDLE; end
          else begin i <= i + 6'd1; wcnt <= 6'd6; st <= S_M; end
        end
        default: st <= S_IDLE;
      endcase
    end
  end

  // luot B: j phat C0 -> eb_q C1 -> fmul C4 -> f2i C6 -> ghi
  assign col_we    = b_v[6];
  assign col_waddr = 12'(P8_BASE) + {6'd0, b_j[6]};
  assign col_wb    = i;
  assign col_wd    = pb_q[7:0];
endmodule : softmax_u8
