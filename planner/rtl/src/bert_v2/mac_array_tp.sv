//==============================================================================
// mac_array_tp.sv — mang MAC song song theo token (BERT V2, docs/KIEN_TRUC_BERT_V2.md §3)
//
// 512 lan = 64 token (t) x 8 cot ra (j). Moi chu ky co in_v:
//   acc[t][j] = (in_first ? 0 : acc[t][j]) + act[t] * w[j]
// act[t] : byte t cua in_act (INT8 co dau, hoac UINT8 khi in_act_u8 = 1)
// w[j]   : 9 bit co dau.
// Duong ong: A (thanh ghi vao lan) -> M (nhan) -> P (tich luy) — anh xa DSP48E2.
//
// Thoat: chu ky sau khi tong cua phan tu in_last da vao P, 512 tong duoc chup vao ngan
// hang `cap`, roi doc ra 1 phan tu/chu ky qua bo chon 2 tang: thu tu e = t*8 + j.
//   d_v / d_acc / d_t / d_j
// RANG BUOC dieu khien: chi dua in_last khi `can_last` = 1 (chuoi thoat rong va khong co
// lan chup nao dang treo) — khong thi tong nhom truoc chua thoat xong se bi ghi de.
// Co assert mo phong cho rang buoc nay.
//==============================================================================
`timescale 1ns / 1ps

module mac_array_tp (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               in_v,
  input  logic               in_first,
  input  logic               in_last,
  input  logic               in_act_u8,
  input  logic [511:0]       in_act,
  input  logic [7:0][8:0]    in_w,
  output logic               can_last,
  output logic               d_v,
  output logic signed [31:0] d_acc,
  output logic [5:0]         d_t,
  output logic [2:0]         d_j
);
  localparam int NT = 64, NJ = 8, NL = NT * NJ;

  // ── tin hieu dieu khien qua duong ong ────────────────────────────────────────
  logic v1, f1, l1, v2, f2, l2, l3;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      {v1, f1, l1, v2, f2, l2, l3} <= '0;
    end else begin
      v1 <= in_v;  f1 <= in_first & in_v;  l1 <= in_last & in_v;
      v2 <= v1;    f2 <= f1;               l2 <= l1;
      l3 <= l2;
    end
  end

  // ── 512 lan ──────────────────────────────────────────────────────────────────
  logic signed [31:0] acc [NL];

  for (genvar t = 0; t < NT; t++) begin : g_t
    // tang A: 1 thanh ghi act cho moi token (dung chung 8 lan)
    logic signed [8:0] a_r;
    always_ff @(posedge clk)
      a_r <= in_act_u8 ? $signed({1'b0, in_act[t*8 +: 8]}) : $signed({in_act[t*8 + 7], in_act[t*8 +: 8]});
    for (genvar j = 0; j < NJ; j++) begin : g_j
      (* use_dsp = "yes" *) logic signed [17:0] m_r;
      logic signed [8:0] w_r;
      always_ff @(posedge clk) begin
        w_r <= in_w[j];
        m_r <= a_r * w_r;                       // tang M (a_r, w_r la thanh ghi A)
      end
      always_ff @(posedge clk)                  // tang P
        if (v2) acc[t*NJ + j] <= (f2 ? 32'sd0 : acc[t*NJ + j]) + 32'(m_r);
    end
  end
  // Chu y can chinh: a_r va w_r cung o tang A (ghi tai canh c+1), m_r tai c+2, acc tai c+3
  // dung v2/f2 (ghi tai c+2). OK.

  // ── thoat: ngan hang chup + bo chon 512:1 duong ong 2 tang ─────────────────
  // l3 (canh c+4): cap <= acc ; dcnt = 512. Moi chu ky co dcnt != 0 phat 1 chi so
  // doc e = 512 - dcnt. Tang A: chon trong 8 khoi 64 (theo e[5:0]); tang B: chon khoi
  // theo e[8:6]. d_* ra sau 2 chu ky ke tu khi phat chi so.
  logic signed [31:0] cap [NL];
  logic [9:0]         dcnt;
  logic [8:0]         ridx;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) dcnt <= '0;
    else if (l3) dcnt <= 10'(NL);
    else if (dcnt != 0) dcnt <= dcnt - 10'd1;
  end
  always_ff @(posedge clk) if (l3) for (int i = 0; i < NL; i++) cap[i] <= acc[i];
  assign ridx = 9'(NL - dcnt);

  logic               ra_v, rb_v;
  logic [8:0]         ra_i, rb_i;
  logic signed [31:0] ra_m [8];
  logic signed [31:0] rb_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ra_v <= 1'b0; rb_v <= 1'b0; end
    else begin ra_v <= (dcnt != 0) && !l3; rb_v <= ra_v; end
  end
  always_ff @(posedge clk) begin
    ra_i <= ridx;
    for (int q = 0; q < 8; q++) ra_m[q] <= cap[q*64 + ridx[5:0]];
    rb_i <= ra_i;
    rb_d <= ra_m[ra_i[8:6]];
  end

  assign d_v   = rb_v;
  assign d_acc = rb_d;
  assign d_t   = rb_i[8:3];
  assign d_j   = rb_i[2:0];

  // ra_v: con phan tu dang doc (d_v se len o chu ky sau) -> chua ranh
  assign can_last = (dcnt == 0) && !l1 && !l2 && !l3 && !ra_v;

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n && l3 && dcnt != 0)
    $error("[mac_array_tp] chup tong moi khi chuoi thoat con %0d phan tu", dcnt);
`endif
endmodule : mac_array_tp
