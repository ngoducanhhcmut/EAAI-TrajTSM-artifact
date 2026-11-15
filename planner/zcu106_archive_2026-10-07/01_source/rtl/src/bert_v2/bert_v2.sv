//==============================================================================
// bert_v2.sv — BERT V2 cua Traj: bo nho + projector + LN + mm_engine + softmax + dieu khien
// docs/KIEN_TRUC_BERT_V2.md. Chuan tung bit: sw/hwspec/hwspec_exact.forward.
//
// Lenh (xung 1 chu ky, khi !busy):
//   cmd_proj        : projector -> XR ; proj LN (XR tai cho)
//   cmd_layer + lyr : 1 lop BERT (trong so lop `lyr` PHAI da nam o URAM 0..196607)
//   cmd_final       : final LN token 0 -> cls (cls_we/cls_waddr/cls_wd)
// done: xung 1 chu ky khi lenh xong.
// PARAM: ghi tu DMA static boot (pm_we) khi khong co lenh nao chay.
// URAM / pos_emb: doc tre 2 chu ky (planning_top dam bao).
//==============================================================================
`timescale 1ns / 1ps

module bert_v2
  import planning_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cmd_proj,
  input  logic        cmd_layer,
  input  logic [1:0]  lyr,
  input  logic        cmd_final,
  output logic        busy,
  output logic        done,
  // token + mat na
  input  bbox6_t      tok [MAX_SEQ_LEN-1:0],   // CUNG dai voi input_adapter.bbox_out (noi mang theo VI TRI)
  input  logic [7:0]  nvalid,
  input  logic [63:0] key_valid,
  // PARAM (DMA)
  input  logic        pm_we,
  input  logic [15:0] pm_waddr,
  input  logic [31:0] pm_wd,
  // pos_emb
  output logic        pe_re,
  output logic [13:0] pe_addr,
  input  logic [63:0] pe_rd,
  // URAM
  output logic        u_en,
  output logic [17:0] u_addr,
  input  logic [63:0] u_rd,
  // CLS
  output logic        cls_we,
  output logic [8:0]  cls_waddr,
  output logic [31:0] cls_wd
);
  localparam int LN_BASE = 36864, GLN_BASE = 45056, SCAL_BASE = 50688, GELU_BASE = 50752;

  // ── bo nho ──────────────────────────────────────────────────────────────────
  logic        xa_en, xa_we, xb_en, xb_we;  logic [14:0] xa_addr, xb_addr;
  logic [31:0] xa_wd, xa_rd, xb_wd;
  bv2_ram_tdp #(.W(32), .D(32768)) u_xr (.clk, .a_en(xa_en), .a_we(1'b0), .a_addr(xa_addr), .a_wd('0), .a_rd(xa_rd),
                                         .b_en(xb_en), .b_we(xb_we), .b_addr(xb_addr), .b_wd(xb_wd), .b_rd());
  logic        pma_en, pma_we, pmb_en;  logic [15:0] pma_addr, pmb_addr;
  logic [31:0] pma_wd, pma_rd, pmb_rd;
  bv2_ram_tdp #(.W(32), .D(65536)) u_pm (.clk, .a_en(pma_en), .a_we(pma_we), .a_addr(pma_addr), .a_wd(pma_wd), .a_rd(pma_rd),
                                         .b_en(pmb_en), .b_we(1'b0), .b_addr(pmb_addr), .b_wd('0), .b_rd(pmb_rd));
  logic        col_re, col_we;  logic [11:0] col_raddr, col_waddr;  logic [5:0] col_wb;
  logic [7:0]  col_wd;  logic [511:0] col_rd;
  bv2_ram_bytew #(.NB(64), .D(2560)) u_col (.clk, .we(col_we), .waddr(col_waddr), .wb(col_wb), .wd(col_wd),
                                            .re(col_re), .raddr(col_raddr), .rd(col_rd));
  logic        k8_re, k8_we, v8_re, v8_we;  logic [11:0] k8_raddr, k8_waddr, v8_raddr, v8_waddr;
  logic [63:0] k8_rd, v8_rd;  logic [2:0] k8_wb, v8_wb;  logic [7:0] k8_wd, v8_wd;
  bv2_ram_bytew #(.NB(8), .D(4096)) u_k8 (.clk, .we(k8_we), .waddr(k8_waddr), .wb(k8_wb), .wd(k8_wd),
                                          .re(k8_re), .raddr(k8_raddr), .rd(k8_rd));
  bv2_ram_bytew #(.NB(8), .D(4096)) u_v8 (.clk, .we(v8_we), .waddr(v8_waddr), .wb(v8_wb), .wd(v8_wd),
                                          .re(v8_re), .raddr(v8_raddr), .rd(v8_rd));
  logic        sc_we, sc_re;  logic [11:0] sc_waddr, sc_raddr;  logic [31:0] sc_wd, sc_rd;
  bv2_ram_tdp #(.W(32), .D(4096)) u_sc (.clk, .a_en(sc_re), .a_we(1'b0), .a_addr(sc_raddr), .a_wd('0), .a_rd(sc_rd),
                                        .b_en(sc_we), .b_we(sc_we), .b_addr(sc_waddr), .b_wd(sc_wd), .b_rd());

  // ── engine ──────────────────────────────────────────────────────────────────
  // projector
  logic pj_start, pj_done, pj_pa_re, pj_pb_re, pj_xr_we;
  logic [15:0] pj_pa_addr, pj_pb_addr;  logic [14:0] pj_xr_waddr;  logic [31:0] pj_xr_wd;
  projector_v2 u_pj (.clk, .rst_n, .start(pj_start), .done(pj_done), .nvalid, .tok,
                     .pa_re(pj_pa_re), .pa_addr(pj_pa_addr), .pa_rd(pma_rd),
                     .pb_re(pj_pb_re), .pb_addr(pj_pb_addr), .pb_rd(pmb_rd),
                     .pe_re, .pe_addr, .pe_rd,
                     .xr_we(pj_xr_we), .xr_waddr(pj_xr_waddr), .xr_wd(pj_xr_wd));
  // LN
  logic ln_start, ln_done;  logic [1:0] ln_dst;  logic [6:0] ln_ntok;
  logic [15:0] ln_wb, ln_bb;  logic [31:0] ln_inv;
  logic ln_xr_re, ln_xr_we, ln_pa_re, ln_pb_re, ln_col_we;
  logic [14:0] ln_xr_raddr, ln_xr_waddr;  logic [31:0] ln_xr_wd;
  logic [15:0] ln_pa_addr, ln_pb_addr;  logic [11:0] ln_col_waddr;  logic [5:0] ln_col_wb;  logic [7:0] ln_col_wd;
  ln_engine u_ln (.clk, .rst_n, .start(ln_start), .done(ln_done), .dst(ln_dst), .ntok(ln_ntok),
                  .w_base(ln_wb), .b_base(ln_bb), .inv_s(ln_inv),
                  .xr_re(ln_xr_re), .xr_raddr(ln_xr_raddr), .xr_rd(xa_rd),
                  .xr_we(ln_xr_we), .xr_waddr(ln_xr_waddr), .xr_wd(ln_xr_wd),
                  .pa_re(ln_pa_re), .pa_addr(ln_pa_addr), .pa_rd(pma_rd),
                  .pb_re(ln_pb_re), .pb_addr(ln_pb_addr), .pb_rd(pmb_rd),
                  .col_we(ln_col_we), .col_waddr(ln_col_waddr), .col_wb(ln_col_wb), .col_wd(ln_col_wd),
                  .cls_we, .cls_waddr, .cls_wd);
  // mm
  logic mm_start, mm_done;  logic [2:0] mm_mode, mm_head;
  logic [15:0] mm_csb, mm_bb;  logic [17:0] mm_ub;  logic [31:0] mm_mul3, s_cctx;
  logic gl_we;  logic [7:0] gl_addr, gl_wd;
  logic mm_col_we, mm_xr_re, mm_xr_we, mm_pa_re, mm_pb_re;
  logic [11:0] mm_col_waddr;  logic [5:0] mm_col_wb;  logic [7:0] mm_col_wd;
  logic [14:0] mm_xr_raddr, mm_xr_waddr;  logic [31:0] mm_xr_wd;
  logic [15:0] mm_pa_addr, mm_pb_addr;
  logic signed [31:0] rowmax [64];
  mm_engine u_mm (.clk, .rst_n, .start(mm_start), .done(mm_done), .mode(mm_mode), .head(mm_head),
                  .key_valid, .cs_base(mm_csb), .b_base(mm_bb), .uram_base(mm_ub), .mul3(mm_mul3), .c_ctx(s_cctx),
                  .gl_we, .gl_addr, .gl_wd,
                  .col_re, .col_raddr, .col_rd,
                  .col_we(mm_col_we), .col_waddr(mm_col_waddr), .col_wb(mm_col_wb), .col_wd(mm_col_wd),
                  .u_en, .u_addr, .u_rd,
                  .k8_re, .k8_raddr, .k8_rd, .k8_we, .k8_waddr, .k8_wb, .k8_wd,
                  .v8_re, .v8_raddr, .v8_rd, .v8_we, .v8_waddr, .v8_wb, .v8_wd,
                  .sc_we, .sc_waddr, .sc_wd, .rowmax,
                  .xr_re(mm_xr_re), .xr_raddr(mm_xr_raddr), .xr_rd(xa_rd),
                  .xr_we(mm_xr_we), .xr_waddr(mm_xr_waddr), .xr_wd(mm_xr_wd),
                  .pa_re(mm_pa_re), .pa_addr(mm_pa_addr), .pa_rd(pma_rd),
                  .pb_re(mm_pb_re), .pb_addr(mm_pb_addr), .pb_rd(pmb_rd));
  // softmax
  logic sm_start, sm_done;  logic [31:0] s_cqk;
  logic sm_col_we;  logic [11:0] sm_col_waddr;  logic [5:0] sm_col_wb;  logic [7:0] sm_col_wd;
  softmax_u8 #(.P8_BASE(1024)) u_sm (.clk, .rst_n, .start(sm_start), .done(sm_done), .c_qk(s_cqk), .key_valid,
                  .rowmax, .sc_re, .sc_raddr, .sc_rd,
                  .col_we(sm_col_we), .col_waddr(sm_col_waddr), .col_wb(sm_col_wb), .col_wd(sm_col_wd));

  // ── dieu khien ──────────────────────────────────────────────────────────────
  typedef enum logic [2:0] {E_NONE, E_PJ, E_LN, E_MM, E_SM, E_LD} eng_t;
  typedef enum logic [4:0] {
    C_IDLE, C_PJ, C_PLN, C_LD, C_LN1, C_Q, C_K, C_V, C_QK, C_SM, C_PV, C_WO, C_LN2, C_W1, C_W2,
    C_FIN, C_END
  } cst_t;
  cst_t        cs;
  eng_t        eng;
  logic        wait_done;     // dang cho engine xong
  logic [1:0]  L;
  logic [2:0]  h;
  logic [31:0] s_insin, s_isq, s_isk, s_isv, s_is1;
  // nap vo huong + GELU: doc PARAM cong A, du lieu ve sau 2 chu ky
  logic [6:0]  ld_i;          // 0..6 vo huong, 7..70 GELU (64 tu)
  logic        ld_v [1:2];  logic [6:0] ld_ii [1:2];
  logic        gl_busy;
  logic        ld_issue;

  logic eng_done;
  always_comb begin
    case (eng)
      E_PJ: eng_done = pj_done;
      E_LN: eng_done = ln_done;
      E_MM: eng_done = mm_done;
      E_SM: eng_done = sm_done;
      default: eng_done = 1'b0;
    endcase
  end

  assign busy = (cs != C_IDLE);

  // khoi dong 1 engine (to hop tu trang thai + co "vua vao")
  logic entered;    // 1 o chu ky dau tien cua trang thai
  always_comb begin
    pj_start = 1'b0; ln_start = 1'b0; mm_start = 1'b0; sm_start = 1'b0;
    ln_dst = 2'd0; ln_ntok = 7'd64; ln_wb = '0; ln_bb = '0; ln_inv = 32'h3F800000;
    mm_mode = 3'd0; mm_head = h; mm_csb = '0; mm_bb = '0; mm_ub = '0; mm_mul3 = '0;
    case (cs)
      C_PJ:  pj_start = entered;
      C_PLN: begin ln_start = entered; ln_dst = 2'd1; ln_wb = 16'(GLN_BASE); ln_bb = 16'(GLN_BASE + 512); end
      C_LN1: begin ln_start = entered; ln_wb = 16'(LN_BASE + L*2048); ln_bb = 16'(LN_BASE + L*2048 + 512); ln_inv = s_insin; end
      C_LN2: begin ln_start = entered; ln_wb = 16'(LN_BASE + L*2048 + 1024); ln_bb = 16'(LN_BASE + L*2048 + 1536); ln_inv = s_insin; end
      C_FIN: begin ln_start = entered; ln_dst = 2'd2; ln_ntok = 7'd1; ln_wb = 16'(GLN_BASE + 1024); ln_bb = 16'(GLN_BASE + 1536); end
      C_Q:  begin mm_start = entered; mm_mode = 3'd0; mm_csb = 16'(L*9216 + 0);    mm_ub = 18'd0;      mm_mul3 = s_isq; end
      C_K:  begin mm_start = entered; mm_mode = 3'd1; mm_csb = 16'(L*9216 + 512);  mm_ub = 18'd16384;  mm_mul3 = s_isk; end
      C_V:  begin mm_start = entered; mm_mode = 3'd2; mm_csb = 16'(L*9216 + 1024); mm_ub = 18'd32768;  mm_mul3 = s_isv; end
      C_WO: begin mm_start = entered; mm_mode = 3'd3; mm_csb = 16'(L*9216 + 1536); mm_ub = 18'd49152; end
      C_W1: begin mm_start = entered; mm_mode = 3'd4; mm_csb = 16'(L*9216 + 2048); mm_ub = 18'd65536;  mm_mul3 = s_is1; end
      C_W2: begin mm_start = entered; mm_mode = 3'd5; mm_csb = 16'(L*9216 + 4096); mm_ub = 18'd131072; end
      C_QK: begin mm_start = entered; mm_mode = 3'd6; end
      C_PV: begin mm_start = entered; mm_mode = 3'd7; end
      C_SM: sm_start = entered;
      default: ;
    endcase
    mm_bb = mm_csb + 16'd4608;
    // giu mode on dinh khi engine dang chay (cs khong doi trong luc cho)
  end

  assign ld_issue = (cs == C_LD) && (ld_i < 7'd71);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cs <= C_IDLE; eng <= E_NONE; done <= 1'b0; entered <= 1'b0; L <= '0; h <= '0; ld_i <= '0;
      ld_v[1] <= 1'b0; ld_v[2] <= 1'b0;
      s_insin <= '0; s_isq <= '0; s_isk <= '0; s_isv <= '0; s_cqk <= '0; s_cctx <= '0; s_is1 <= '0;
    end else begin
      done <= 1'b0;
      entered <= 1'b0;
      // ong nap vo huong / GELU
      ld_v[1] <= ld_issue; ld_ii[1] <= ld_i;
      ld_v[2] <= ld_v[1];  ld_ii[2] <= ld_ii[1];
      if (ld_v[2]) begin
        case (ld_ii[2])
          7'd0: s_insin <= pma_rd;  7'd1: s_isq <= pma_rd;  7'd2: s_isk <= pma_rd;
          7'd3: s_isv <= pma_rd;    7'd4: s_cqk <= pma_rd;  7'd5: s_cctx <= pma_rd;
          7'd6: s_is1 <= pma_rd;
          default: ;
        endcase
      end

      case (cs)
        C_IDLE: begin
          if (cmd_proj)       begin cs <= C_PJ;  eng <= E_PJ; entered <= 1'b1; end
          else if (cmd_layer) begin L <= lyr; ld_i <= '0; cs <= C_LD; eng <= E_LD; end
          else if (cmd_final) begin cs <= C_FIN; eng <= E_LN; entered <= 1'b1; end
        end
        C_PJ:  if (eng_done) begin cs <= C_PLN; eng <= E_LN; entered <= 1'b1; end
        C_PLN: if (eng_done) cs <= C_END;
        C_LD: begin
          if (ld_i < 7'd71) ld_i <= ld_i + 7'd1;
          else if (!ld_v[1] && !ld_v[2] && !gl_busy) begin cs <= C_LN1; eng <= E_LN; entered <= 1'b1; end
        end
        C_LN1: if (eng_done) begin cs <= C_Q;  eng <= E_MM; entered <= 1'b1; end
        C_Q:   if (eng_done) begin cs <= C_K;  entered <= 1'b1; end
        C_K:   if (eng_done) begin cs <= C_V;  entered <= 1'b1; end
        C_V:   if (eng_done) begin cs <= C_QK; h <= '0; entered <= 1'b1; end
        C_QK:  if (eng_done) begin cs <= C_SM; eng <= E_SM; entered <= 1'b1; end
        C_SM:  if (eng_done) begin cs <= C_PV; eng <= E_MM; entered <= 1'b1; end
        C_PV:  if (eng_done) begin
                 if (h == 3'd7) begin cs <= C_WO; entered <= 1'b1; end
                 else begin h <= h + 3'd1; cs <= C_QK; entered <= 1'b1; end
               end
        C_WO:  if (eng_done) begin cs <= C_LN2; eng <= E_LN; entered <= 1'b1; end
        C_LN2: if (eng_done) begin cs <= C_W1; eng <= E_MM; entered <= 1'b1; end
        C_W1:  if (eng_done) begin cs <= C_W2; entered <= 1'b1; end
        C_W2:  if (eng_done) cs <= C_END;
        C_FIN: if (eng_done) cs <= C_END;
        C_END: begin done <= 1'b1; eng <= E_NONE; cs <= C_IDLE; end
        default: cs <= C_IDLE;
      endcase
    end
  end
  // Chu y: mm_start = entered trong trang thai moi; `h` cap nhat cung canh voi entered nen
  // mm_head (= h) da dung khi engine lay mau start. Cac cau hinh mm/ln giu on dinh suot trang thai.

  // GELU: moi tu 32 bit -> 4 byte ghi LUT (4 chu ky). Tu den moi 1 chu ky trong luc nap ->
  // can bo dem: luu toi da 64 tu vao mang roi day ra.
  logic [31:0] gw [64];
  logic [7:0]  gl_cnt;     // 0..255 byte da ghi
  logic        gl_go;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin gl_cnt <= '0; gl_go <= 1'b0; end
    else begin
      if (ld_v[2] && ld_ii[2] >= 7'd7) gw[ld_ii[2] - 7'd7] <= pma_rd;
      if (cs == C_LD && ld_i == 7'd0) begin gl_cnt <= '0; gl_go <= 1'b0; end
      else if (ld_v[2] && ld_ii[2] == 7'd70) gl_go <= 1'b1;
      else if (gl_go) begin
        gl_cnt <= gl_cnt + 8'd1;
        if (gl_cnt == 8'd255) gl_go <= 1'b0;
      end
    end
  end
  assign gl_busy = gl_go;
  assign gl_we   = gl_go;
  assign gl_addr = gl_cnt;
  assign gl_wd   = gw[gl_cnt[7:2]][gl_cnt[1:0]*8 +: 8];

  // ── ghep cong bo nho ────────────────────────────────────────────────────────
  always_comb begin
    // XR cong A (doc)
    xa_en = 1'b0; xa_addr = '0;
    if (eng == E_LN)      begin xa_en = ln_xr_re; xa_addr = ln_xr_raddr; end
    else if (eng == E_MM) begin xa_en = mm_xr_re; xa_addr = mm_xr_raddr; end
    // XR cong B (ghi)
    xb_en = 1'b0; xb_we = 1'b0; xb_addr = '0; xb_wd = '0;
    case (eng)
      E_PJ: begin xb_en = pj_xr_we; xb_we = pj_xr_we; xb_addr = pj_xr_waddr; xb_wd = pj_xr_wd; end
      E_LN: begin xb_en = ln_xr_we; xb_we = ln_xr_we; xb_addr = ln_xr_waddr; xb_wd = ln_xr_wd; end
      E_MM: begin xb_en = mm_xr_we; xb_we = mm_xr_we; xb_addr = mm_xr_waddr; xb_wd = mm_xr_wd; end
      default: ;
    endcase
    // PARAM cong A: DMA ghi (khi ranh) / engine doc
    pma_en = 1'b0; pma_we = 1'b0; pma_addr = '0; pma_wd = pm_wd;
    pmb_en = 1'b0; pmb_addr = '0;
    if (cs == C_IDLE && pm_we) begin pma_en = 1'b1; pma_we = 1'b1; pma_addr = pm_waddr; end
    else case (eng)
      E_PJ: begin pma_en = pj_pa_re; pma_addr = pj_pa_addr; pmb_en = pj_pb_re; pmb_addr = pj_pb_addr; end
      E_LN: begin pma_en = ln_pa_re; pma_addr = ln_pa_addr; pmb_en = ln_pb_re; pmb_addr = ln_pb_addr; end
      E_MM: begin pma_en = mm_pa_re; pma_addr = mm_pa_addr; pmb_en = mm_pb_re; pmb_addr = mm_pb_addr; end
      E_LD: begin pma_en = ld_issue;
                  pma_addr = (ld_i < 7'd7) ? 16'(SCAL_BASE + L*16) + 16'(ld_i)
                                           : 16'(GELU_BASE + L*64) + 16'(ld_i - 7'd7); end
      default: ;
    endcase
    // COL ghi
    col_we = 1'b0; col_waddr = '0; col_wb = '0; col_wd = '0;
    case (eng)
      E_LN: begin col_we = ln_col_we; col_waddr = ln_col_waddr; col_wb = ln_col_wb; col_wd = ln_col_wd; end
      E_MM: begin col_we = mm_col_we; col_waddr = mm_col_waddr; col_wb = mm_col_wb; col_wd = mm_col_wd; end
      E_SM: begin col_we = sm_col_we; col_waddr = sm_col_waddr; col_wb = sm_col_wb; col_wd = sm_col_wd; end
      default: ;
    endcase
  end
endmodule : bert_v2
