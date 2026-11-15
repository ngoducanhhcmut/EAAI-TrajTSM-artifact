//==============================================================================
// mm_engine.sv — bo nap + mang MAC + hau xu ly (BERT V2, docs/KIEN_TRUC_BERT_V2.md §3)
// Chuan tung bit: sw/hwspec/hwspec_exact.py (proj, softmax-max, ctx, residual, GELU).
//
// mode : 0 Q, 1 K, 2 V, 3 WO, 4 W1, 5 W2, 6 QK, 7 PV
//   K / so nhom / nguon act / nguon w / dich:
//   Q,K,V,WO : 512 / 64  / COL A        / URAM / Q8->COL B+o ; K8 ; V8 ; XR+=
//   W1       : 512 / 256 / COL A        / URAM / COL B+o (GELU8)
//   W2       : 2048/ 64  / COL B        / URAM / XR+=
//   QK       : 64  / 8   / COL B+h*64+k / K8   / SC[t*64+kk], rowmax
//   PV       : 64  / 8   / COL B+512+k (u8) / V8 / COL A col h*64+dd
// Moi RAM doc tre 2 chu ky (URAM cung phai = 2 — planning_top boc cho dung).
//==============================================================================
`timescale 1ns / 1ps

module mm_engine (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               start,
  output logic               done,
  input  logic [2:0]         mode,
  input  logic [2:0]         head,
  input  logic [63:0]        key_valid,
  input  logic [15:0]        cs_base,
  input  logic [15:0]        b_base,
  input  logic [17:0]        uram_base,
  input  logic [31:0]        mul3,        // inv_sq / inv_sk / inv_sv / inv_s1
  input  logic [31:0]        c_ctx,
  // GELU LUT (nap truoc W1)
  input  logic               gl_we,
  input  logic [7:0]         gl_addr,
  input  logic [7:0]         gl_wd,
  // COL
  output logic               col_re,
  output logic [11:0]        col_raddr,
  input  logic [511:0]       col_rd,
  output logic               col_we,
  output logic [11:0]        col_waddr,
  output logic [5:0]         col_wb,
  output logic [7:0]         col_wd,
  // URAM
  output logic               u_en,
  output logic [17:0]        u_addr,
  input  logic [63:0]        u_rd,
  // K8 / V8
  output logic               k8_re,
  output logic [11:0]        k8_raddr,
  input  logic [63:0]        k8_rd,
  output logic               k8_we,
  output logic [11:0]        k8_waddr,
  output logic [2:0]         k8_wb,
  output logic [7:0]         k8_wd,
  output logic               v8_re,
  output logic [11:0]        v8_raddr,
  input  logic [63:0]        v8_rd,
  output logic               v8_we,
  output logic [11:0]        v8_waddr,
  output logic [2:0]         v8_wb,
  output logic [7:0]         v8_wd,
  // SC + max hang
  output logic               sc_we,
  output logic [11:0]        sc_waddr,
  output logic [31:0]        sc_wd,
  output logic signed [31:0] rowmax [64],
  // XR
  output logic               xr_re,
  output logic [14:0]        xr_raddr,
  input  logic [31:0]        xr_rd,
  output logic               xr_we,
  output logic [14:0]        xr_waddr,
  output logic [31:0]        xr_wd,
  // PARAM (2 cong doc)
  output logic               pa_re,
  output logic [15:0]        pa_addr,
  input  logic [31:0]        pa_rd,
  output logic               pb_re,
  output logic [15:0]        pb_addr,
  input  logic [31:0]        pb_rd
);
  localparam logic [2:0] MD_Q = 0, MD_K = 1, MD_V = 2, MD_WO = 3, MD_W1 = 4, MD_W2 = 5,
                         MD_QK = 6, MD_PV = 7;
  localparam int COL_B = 512;
  localparam int RD_LAT = 3;   // [IMPL 04/10] URAM 3 (XPM tre 2 + arbiter); COL/K8/V8 (tre 2) duoc tre them 1

  // ── tham so theo mode ─────────────────────────────────────────────────────────
  logic [11:0] K_m1;          // K-1
  logic [8:0]  NG_m1;         // so nhom - 1
  logic [11:0] act_base;
  logic        act_u8;
  logic [1:0]  wsrc;          // 0 URAM, 1 K8, 2 V8
  always_comb begin
    K_m1 = 12'd511; NG_m1 = 9'd63; act_base = 12'd0; act_u8 = 1'b0; wsrc = 2'd0;
    case (mode)
      MD_W1: NG_m1 = 9'd255;
      MD_W2: begin K_m1 = 12'd2047; act_base = 12'(COL_B); end
      MD_QK: begin K_m1 = 12'd63; NG_m1 = 9'd7; act_base = 12'(COL_B) + {3'd0, head, 6'd0}; wsrc = 2'd1; end
      MD_PV: begin K_m1 = 12'd63; NG_m1 = 9'd7; act_base = 12'(COL_B + 512); act_u8 = 1'b1; wsrc = 2'd2; end
      default: ;
    endcase
  end

  // [IMPL 150 MHz, 04/10] tham so theo mode CHOT vao thanh ghi o start (mode khong doi trong
  // suot phep) -> cat duong to hop cs(bert_v2) -> giai ma -> URAM addr / 512 lan MAC (-1,016 /
  // -0,885 ns sau route). Dia chi URAM tinh TANG DAN theo nhom (gbase), bo phep nhan g*(K/2).
  logic [11:0] K_m1_r;  logic [8:0] NG_m1_r;  logic [11:0] act_base_r;  logic [1:0] wsrc_r;
  (* max_fanout = 16 *) logic act_u8_r;
  logic [17:0] gbase;

  // du lieu COL/K8/V8 (RAM tre 2) tre them 1 -> thang hang URAM (tre 3)
  logic [511:0] col_rd_d;  logic [63:0] k8_rd_d, v8_rd_d;
  always_ff @(posedge clk) begin col_rd_d <= col_rd; k8_rd_d <= k8_rd; v8_rd_d <= v8_rd; end

  // ── mang MAC ─────────────────────────────────────────────────────────────────
  logic               m_v, m_first, m_last, can_last;
  logic [7:0][8:0]    m_w;
  logic               d_v;
  logic signed [31:0] d_acc;
  logic [5:0]         d_t;
  logic [2:0]         d_j;
  mac_array_tp u_mac (.clk, .rst_n, .in_v(m_v), .in_first(m_first), .in_last(m_last),
                      .in_act_u8(act_u8_r), .in_act(col_rd_d), .in_w(m_w), .can_last,
                      .d_v, .d_acc, .d_t, .d_j);

  // ── bo nap ───────────────────────────────────────────────────────────────────
  logic        running, issuing;
  logic [11:0] k;
  logic [8:0]  g;
  logic [RD_LAT-1:0] p_v, p_f, p_l, p_e;     // ong co (tang 0 = vua phat)
  logic        last_in_pipe;
  logic        busy_any, done_cond;
  logic        iss, iss_last;
  logic [8:0]  drain_g;

  assign last_in_pipe = |(p_l & p_v);
  assign iss_last = (k == K_m1_r);
  assign iss = issuing && (!iss_last || (can_last && !last_in_pipe));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      running <= 1'b0; issuing <= 1'b0; k <= '0; g <= '0; drain_g <= '0;
      // [IMPL 04/10] gia tri reset cho thanh ghi cau hinh (khong reset -> Vivado suy FDCP:
      // CRITICAL WARNING Netlist 29-358 'cannot be timed accurately'). Luon nap lai o start.
      K_m1_r <= '0; NG_m1_r <= '0; act_base_r <= '0; wsrc_r <= '0; act_u8_r <= 1'b0; gbase <= '0;
      p_v <= '0; p_f <= '0; p_l <= '0; p_e <= '0;
    end else begin
      p_v <= {p_v[RD_LAT-2:0], iss};
      p_f <= {p_f[RD_LAT-2:0], iss && (k == 12'd0)};
      p_l <= {p_l[RD_LAT-2:0], iss && iss_last};
      p_e <= {p_e[RD_LAT-2:0], k[0]};
      if (done_cond) running <= 1'b0;
      if (start) begin
        running <= 1'b1; issuing <= 1'b1; k <= '0; g <= '0;
        K_m1_r <= K_m1; NG_m1_r <= NG_m1; act_base_r <= act_base; wsrc_r <= wsrc; act_u8_r <= act_u8;
        gbase <= uram_base;
      end else if (iss) begin
        if (iss_last) begin
          drain_g <= g;
          k <= '0;
          if (g == NG_m1_r) issuing <= 1'b0;
          else begin
            g <= g + 9'd1;
            gbase <= gbase + 18'({1'b0, K_m1_r[11:1]} + 12'd1);
          end
        end else begin
          k <= k + 12'd1;
        end
      end
    end
  end

  // dia chi doc
  always_comb begin
    col_re    = iss;
    col_raddr = act_base_r + k;
    u_en      = iss && (wsrc_r == 2'd0) && !k[0];
    u_addr    = gbase + 18'(k[11:1]);
    k8_re     = iss && (wsrc_r == 2'd1);
    k8_raddr  = {head, k[5:0], 3'b000} + 12'(g[2:0]);
    v8_re     = iss && (wsrc_r == 2'd2);
    v8_raddr  = {k[5:0], 6'd0} + {3'd0, head, g[2:0]};
  end

  // du lieu ve sau RD_LAT -> dau vao MAC
  logic [63:0] u_lat;
  always_ff @(posedge clk) if (p_v[RD_LAT-1] && !p_e[RD_LAT-1]) u_lat <= u_rd;
  always_comb begin
    logic [63:0] uw;
    uw = p_e[RD_LAT-1] ? u_lat : u_rd;
    m_v = p_v[RD_LAT-1];
    m_first = p_f[RD_LAT-1];
    m_last = p_l[RD_LAT-1];
    for (int j = 0; j < 8; j++) begin
      logic [3:0] nb;
      nb = uw[(2*j + (p_e[RD_LAT-1] ? 1 : 0))*4 +: 4];
      case (wsrc_r)
        2'd1:    m_w[j] = {k8_rd_d[j*8 + 7], k8_rd_d[j*8 +: 8]};
        2'd2:    m_w[j] = {v8_rd_d[j*8 + 7], v8_rd_d[j*8 +: 8]};
        default: m_w[j] = {{5{nb[3]}}, nb};
      endcase
    end
  end

  // ── hau xu ly: duong ong co dinh 14 tang ───────────────────────────────────
  localparam int PL = 14;
  // tang i (1..PL): phan tu da vao tu i chu ky truoc (tang 0 = d_v/d_t/d_o hien tai)
  logic        s_v [1:PL];
  logic [5:0]  s_t [1:PL];
  logic [10:0] s_o [1:PL];
  logic [10:0] d_o;
  assign d_o = (mode == MD_W1) ? {drain_g[7:0], d_j} : {2'd0, drain_g[5:0], d_j};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 1; i <= PL; i++) s_v[i] <= 1'b0;
    end else begin
      s_v[1] <= d_v && (mode != MD_QK);
      for (int i = 2; i <= PL; i++) s_v[i] <= s_v[i-1];
    end
  end
  always_ff @(posedge clk) begin
    s_t[1] <= d_t; s_o[1] <= d_o;
    for (int i = 2; i <= PL; i++) begin s_t[i] <= s_t[i-1]; s_o[i] <= s_o[i-1]; end
  end
  logic pp_busy;
  always_comb begin
    pp_busy = 1'b0;
    for (int i = 1; i <= PL; i++) pp_busy |= s_v[i];
  end

  // c0: doc PARAM, XR ; i2f
  assign pa_re   = d_v; assign pa_addr = cs_base + 16'(d_o);
  assign pb_re   = d_v; assign pb_addr = b_base + 16'(d_o);
  assign xr_re   = d_v && (mode == MD_WO || mode == MD_W2);
  assign xr_raddr = {d_t, d_o[8:0]};

  logic [31:0] f_c2, y1_c5, y_c8, z_c11, r_c11;
  fp32_i2f_p u_i2f (.clk, .x(d_acc), .r(f_c2));
  fp32_mul_p u_mul2 (.clk, .a(f_c2), .b((mode == MD_PV) ? c_ctx : pa_rd), .r(y1_c5));

  logic [31:0] b_d [3];       // b tu c2 -> c5
  logic [31:0] xr_d [6];      // xr tu c2 -> c8
  logic [31:0] y1_d [6];      // y1 tu c5 -> c11 (PV)
  always_ff @(posedge clk) begin
    b_d[0] <= pb_rd; b_d[1] <= b_d[0]; b_d[2] <= b_d[1];
    xr_d[0] <= xr_rd; for (int i = 1; i < 6; i++) xr_d[i] <= xr_d[i-1];
    y1_d[0] <= y1_c5; for (int i = 1; i < 6; i++) y1_d[i] <= y1_d[i-1];
  end
  fp32_add_p u_addb (.clk, .a(y1_c5), .b(b_d[2]), .r(y_c8));
  fp32_mul_p u_mul3 (.clk, .a(y_c8), .b(mul3), .r(z_c11));
  fp32_add_p u_res  (.clk, .a(xr_d[5]), .b(y_c8), .r(r_c11));

  logic signed [15:0] q_c13;
  fp32_f2i_p #(.LO(-128), .HI(127)) u_q (.clk, .x((mode == MD_PV) ? y1_d[5] : z_c11), .r(q_c13));

  logic [7:0] glut [256];
  always_ff @(posedge clk) if (gl_we) glut[gl_addr] <= gl_wd;
  logic [7:0]  q_c14;
  logic [31:0] r_d [3];
  always_ff @(posedge clk) begin
    q_c14 <= (mode == MD_W1) ? glut[8'(q_c13[7:0] + 8'd128)] : q_c13[7:0];
    r_d[0] <= r_c11; r_d[1] <= r_d[0]; r_d[2] <= r_d[1];
  end

  // c14: ghi
  logic        w_v;
  logic [5:0]  w_t;
  logic [10:0] w_o;
  assign w_v = s_v[PL];
  assign w_t = s_t[PL];
  assign w_o = s_o[PL];
  always_comb begin
    col_we = 1'b0; col_waddr = '0; col_wb = w_t; col_wd = q_c14;
    k8_we = 1'b0; k8_waddr = {w_o[8:0], w_t[5:3]}; k8_wb = w_t[2:0]; k8_wd = q_c14;
    v8_we = 1'b0; v8_waddr = {w_t, w_o[8:3]}; v8_wb = w_o[2:0]; v8_wd = q_c14;
    xr_we = 1'b0; xr_waddr = {w_t, w_o[8:0]}; xr_wd = r_d[2];
    case (mode)
      MD_Q:  begin col_we = w_v; col_waddr = 12'(COL_B) + {3'd0, w_o[8:0]}; end
      MD_K:  k8_we = w_v;
      MD_V:  v8_we = w_v;
      MD_W1: begin col_we = w_v; col_waddr = 12'(COL_B) + {1'b0, w_o}; end
      MD_PV: begin col_we = w_v; col_waddr = {3'd0, head, w_o[5:0]}; end
      MD_WO, MD_W2: xr_we = w_v;
      default: ;
    endcase
  end

  // ── QK: ghi SC + max hang (o c0) ────────────────────────────────────────────
  logic [5:0] kk;
  assign kk = {drain_g[2:0], d_j};
  always_ff @(posedge clk) begin
    sc_we    <= d_v && (mode == MD_QK);
    sc_waddr <= {d_t, kk};
    sc_wd    <= d_acc;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 64; i++) rowmax[i] <= 32'sh80000000;
    end else if (start) begin
      for (int i = 0; i < 64; i++) rowmax[i] <= 32'sh80000000;
    end else if (d_v && mode == MD_QK && key_valid[kk] && d_acc > rowmax[d_t]) begin
      rowmax[d_t] <= d_acc;
    end
  end

  // ── xong ────────────────────────────────────────────────────────────────────
  assign busy_any  = issuing || (|p_v) || !can_last || d_v || pp_busy || sc_we;
  assign done_cond = running && !start && !busy_any;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) done <= 1'b0;
    else        done <= done_cond;
  end
endmodule : mm_engine
