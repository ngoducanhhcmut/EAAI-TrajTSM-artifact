//==============================================================================
// projector_v2.sv — projector FP32 (BERT V2). Chuan tung bit: hwspec_exact.projector
//   a = fmul(tok0, W0); a = fadd(a, fmul(tok_k, W_k)) k=1..5; a = fadd(a, b); x = fadd(a, pos)
//   -> XR[t*512 + o]. Token t >= nvalid duoc ep = 0 (golden: token dem = 0).
// Pha 1: nap W (PARAM 47104 + o*6 + k) va b (PARAM 50176 + o) vao 7 bank noi bo.
// Pha 2: t ngoai, o trong, 1 phan tu/chu ky. Lich (phat C0):
//   C2  : W_k, b, pos hop le -> 6 fmul -> C5
//   C5  : fadd(p0,p1) -> C8 ; +p2 -> C11 ; +p3 -> C14 ; +p4 -> C17 ; +p5 -> C20
//   C20 : +b -> C23 ; +pos -> C26 -> ghi XR
// pos_emb: RAM 64 bit, dia chi {t, o[8:1]}, [31:0] kenh chan / [63:32] kenh le, doc tre 2.
//==============================================================================
`timescale 1ns / 1ps

module projector_v2
  import planning_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  output logic        done,
  input  logic [7:0]  nvalid,
  input  bbox6_t      tok [MAX_SEQ_LEN-1:0],   // CUNG dai voi input_adapter.bbox_out (noi mang theo VI TRI)
  output logic        pa_re,
  output logic [15:0] pa_addr,
  input  logic [31:0] pa_rd,
  output logic        pb_re,
  output logic [15:0] pb_addr,
  input  logic [31:0] pb_rd,
  output logic        pe_re,
  output logic [13:0] pe_addr,
  input  logic [63:0] pe_rd,
  output logic        xr_we,
  output logic [14:0] xr_waddr,
  output logic [31:0] xr_wd
);
  localparam int PW_BASE = 47104, PB_BASE = 50176;

  typedef enum logic [2:0] {S_IDLE, S_LOAD, S_LOADW, S_RUN, S_DRAIN} st_t;
  st_t st;

  // ── bank trong so (doc tre 2) ───────────────────────────────────────────────
  // 6 bank W + 1 bank b, moi bank 1 RAM rieng (de suy ra BRAM/LUTRAM, khong phai FF)
  logic [11:0] li;            // chi so nap 0..3071
  logic [2:0]  lk;  logic [8:0] lo;      // (k, o) cua li phat
  logic        l_v [1:2]; logic [2:0] l_k [1:2]; logic [8:0] l_o [1:2]; logic l_b [1:2];

  // ── pha chay ────────────────────────────────────────────────────────────────
  logic [5:0]  t;
  logic [8:0]  o;
  logic        iss;
  logic [31:0] tr [6], tr_d1 [6], tr_d2 [6];
  logic [31:0] wq [6], wr [6], bq, br;
  logic [5:0]  wcnt;

  assign iss = (st == S_RUN);

  // truong k cua token theo thu tu hwspec: 0 x_min, 1 y_min, 2 x_max, 3 y_max, 4 vx, 5 vy
  function automatic logic [31:0] fld(input bbox6_t b, input int k);
    case (k)
      0: return b.x_min;  1: return b.y_min;  2: return b.x_max;
      3: return b.y_max;  4: return b.vx;     default: return b.vy;
    endcase
  endfunction
  logic [8:0] li_b1, li_b2;

  // doc bank (tre 2)
  for (genvar gk = 0; gk < 6; gk++) begin : g_wb
    (* ram_style = "block" *) logic [31:0] wb_m [512];
    always_ff @(posedge clk) begin
      if (l_v[2] && l_k[2] == 3'(gk)) wb_m[l_o[2]] <= pa_rd;
      wq[gk] <= wb_m[o];
      wr[gk] <= wq[gk];
    end
  end
  (* ram_style = "block" *) logic [31:0] bb_m [512];
  always_ff @(posedge clk) begin
    if (l_v[2] && l_b[2]) bb_m[li_b2] <= pb_rd;
    bq <= bb_m[o]; br <= bq;
  end
  always_ff @(posedge clk) begin
    for (int k = 0; k < 6; k++) begin tr_d1[k] <= tr[k]; tr_d2[k] <= tr_d1[k]; end
  end
  assign pe_re   = iss;
  assign pe_addr = {t, o[8:1]};

  // ── tinh ────────────────────────────────────────────────────────────────────
  logic [31:0] p [6];
  for (genvar k = 0; k < 6; k++) begin : g_mul
    fp32_mul_p u_m (.clk, .a(tr_d2[k]), .b(wr[k]), .r(p[k]));
  end
  logic [31:0] d2 [3], d3 [6], d4 [9], d5 [12];     // p2..p5 tu C5
  logic [31:0] bd [18];                              // b tu C2 -> C20
  logic [31:0] pd [21];                              // pos tu C2 -> C23
  logic [31:0] a8, a11, a14, a17, a20, a23, a26;
  logic        o_odd_d [1:2];
  logic [31:0] pos_c2;
  assign pos_c2 = o_odd_d[2] ? pe_rd[63:32] : pe_rd[31:0];
  always_ff @(posedge clk) begin
    o_odd_d[1] <= o[0]; o_odd_d[2] <= o_odd_d[1];
    d2[0] <= p[2]; for (int i = 1; i < 3;  i++) d2[i] <= d2[i-1];
    d3[0] <= p[3]; for (int i = 1; i < 6;  i++) d3[i] <= d3[i-1];
    d4[0] <= p[4]; for (int i = 1; i < 9;  i++) d4[i] <= d4[i-1];
    d5[0] <= p[5]; for (int i = 1; i < 12; i++) d5[i] <= d5[i-1];
    bd[0] <= br;   for (int i = 1; i < 18; i++) bd[i] <= bd[i-1];
    pd[0] <= pos_c2; for (int i = 1; i < 21; i++) pd[i] <= pd[i-1];
  end
  fp32_add_p u_a1 (.clk, .a(p[0]), .b(p[1]),   .r(a8));
  fp32_add_p u_a2 (.clk, .a(a8),   .b(d2[2]),  .r(a11));
  fp32_add_p u_a3 (.clk, .a(a11),  .b(d3[5]),  .r(a14));
  fp32_add_p u_a4 (.clk, .a(a14),  .b(d4[8]),  .r(a17));
  fp32_add_p u_a5 (.clk, .a(a17),  .b(d5[11]), .r(a20));
  fp32_add_p u_a6 (.clk, .a(a20),  .b(bd[17]), .r(a23));
  fp32_add_p u_a7 (.clk, .a(a23),  .b(pd[20]), .r(a26));
  // Kiem lich: p[k] hop le C5 ; d2[2] o C8 ; d3[5] o C11 ; d4[8] o C14 ; d5[11] o C17 ;
  //            br hop le C2 -> bd[17] o C20 ; pos_c2 o C2 -> pd[20] o C23. Dung.

  // ong (v, t, o) toi C26
  logic        e_v [1:26];
  logic [14:0] e_a [1:26];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE; done <= 1'b0; li <= '0; lk <= '0; lo <= '0; t <= '0; o <= '0; wcnt <= '0;
      for (int i = 1; i <= 2; i++) l_v[i] <= 1'b0;
      for (int i = 1; i <= 26; i++) e_v[i] <= 1'b0;
    end else begin
      done <= 1'b0;
      if (wcnt != 0) wcnt <= wcnt - 6'd1;
      // ong nap
      l_v[1] <= (st == S_LOAD); l_k[1] <= lk; l_o[1] <= lo; l_b[1] <= (li < 12'd512);
      l_v[2] <= l_v[1]; l_k[2] <= l_k[1]; l_o[2] <= l_o[1]; l_b[2] <= l_b[1];
      // ong tinh
      e_v[1] <= iss; e_a[1] <= {t, o};
      for (int i = 2; i <= 26; i++) begin e_v[i] <= e_v[i-1]; e_a[i] <= e_a[i-1]; end

      case (st)
        S_IDLE: if (start) begin li <= '0; lk <= '0; lo <= '0; st <= S_LOAD; end
        S_LOAD: begin
          li <= li + 12'd1;
          if (lk == 3'd5) begin lk <= '0; lo <= lo + 9'd1; end else lk <= lk + 3'd1;
          if (li == 12'd3071) begin wcnt <= 6'd4; st <= S_LOADW; end
        end
        S_LOADW: if (wcnt == 0) begin
          t <= '0; o <= '0; st <= S_RUN;
          for (int k = 0; k < 6; k++) tr[k] <= (8'd0 < nvalid) ? fld(tok[0], k) : 32'd0;
        end
        S_RUN: begin
          if (o == 9'd511) begin
            o <= '0;
            if (t == 6'd63) begin wcnt <= 6'd30; st <= S_DRAIN; end
            else begin
              t <= t + 6'd1;
              for (int k = 0; k < 6; k++)
                tr[k] <= ({2'b0, t} + 8'd1 < nvalid) ? fld(tok[t + 6'd1], k) : 32'd0;
            end
          end else o <= o + 9'd1;
        end
        S_DRAIN: if (wcnt == 0) begin done <= 1'b1; st <= S_IDLE; end
        default: st <= S_IDLE;
      endcase
    end
  end
  always_ff @(posedge clk) begin li_b1 <= li[8:0]; li_b2 <= li_b1; end

  assign pa_re   = (st == S_LOAD);
  assign pa_addr = 16'(PW_BASE) + 16'(li);
  assign pb_re   = (st == S_LOAD) && (li < 12'd512);
  assign pb_addr = 16'(PB_BASE) + 16'(li[8:0]);

  assign xr_we    = e_v[26];
  assign xr_waddr = e_a[26];
  assign xr_wd    = a26;
endmodule : projector_v2
