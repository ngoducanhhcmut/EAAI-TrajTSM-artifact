//==============================================================================
// tb_planning_top_e2e — kiem TOAN KHOI TRAJ tu DDR toi waypoint, KHONG tiem du lieu.
//   DDR mo hinh (AXI4 doc, burst) nap payload V2 (sw/payloads/v2) + world model mau.
//   CSR AXI-lite nhu firmware: cho boot -> WM_SEL -> START -> cho ngat -> doc WP.
//   Nhieu khung hinh lien tiep (khong reset): +S0=<mau dau> +NS=<so mau>.
//   So: CLS (cls_buf) TUNG BIT voi hwspec ; waypoint voi GRU tuong duong RTL (dung sai
//   1 mm, bao lech lon nhat) va voi GT (ADE). Bao so chu ky tung pha.
//==============================================================================
`timescale 1ns / 1ps
module tb_planning_top_e2e;
  import planning_pkg::*;
  localparam real TCK = 5.405;      // 185 MHz
  logic clk = 0, rst_n = 0;
  always #(TCK/2) clk = ~clk;

  // ── DUT ─────────────────────────────────────────────────────────────────────
  logic [11:0] axil_awaddr = 0, axil_araddr = 0;
  logic axil_awvalid = 0, axil_wvalid = 0, axil_bready = 1, axil_arvalid = 0, axil_rready = 1;
  logic [31:0] axil_wdata = 0; logic [3:0] axil_wstrb = 4'hF;
  logic axil_awready, axil_wready, axil_bvalid, axil_arready, axil_rvalid;
  logic [1:0] axil_bresp, axil_rresp; logic [31:0] axil_rdata;
  logic [5:0] m_axi_arid, m_axi_rid; logic [31:0] m_axi_araddr; logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize, m_axi_arprot; logic [1:0] m_axi_arburst, m_axi_arlock, m_axi_rresp;
  logic [3:0] m_axi_arcache, m_axi_arqos; logic m_axi_arvalid, m_axi_arready, m_axi_rlast, m_axi_rvalid, m_axi_rready;
  logic [127:0] m_axi_rdata;
  fp32_t waypoint_x [NUM_WAYPOINTS-1:0], waypoint_y [NUM_WAYPOINTS-1:0];
  logic waypoints_valid, waypoints_sanity_pass, done_irq, wload_timeout_err;

  planning_top dut (.*, .hmao_clk(clk), .hmao_rst_n(rst_n));

  // ── DDR ─────────────────────────────────────────────────────────────────────
  localparam string V = "tb/e2e/vec/";
  logic [127:0] r_bw [393216], r_pe [8192], r_pa [4096], r_pb [8192], r_pc [2048];
  logic [127:0] r_gb [512], r_gw [49152], r_go [512], r_gs [384], r_gp [384], r_wm [1024];
  int n_bad_addr = 0;

  function automatic logic [127:0] ddr_rd(input logic [31:0] a);
    logic [31:0] o;
    if (a < 32'h0060_0000)                                  return r_bw[(a - 32'h0)       >> 4];
    if (a >= 32'h0060_0000 && a < 32'h0062_0000)            return r_pe[(a - 32'h0060_0000) >> 4];
    if (a >= 32'h0064_0000 && a < 32'h0064_4000)            return r_wm[(a - 32'h0064_0000) >> 4];
    if (a >= 32'h0064_4000 && a < 32'h00E4_0000)            return 128'd0;     // phan con lai buffer WM
    if (a >= 32'h017D_2000 && a < 32'h017D_4000)            return r_gb[(a - 32'h017D_2000) >> 4];
    if (a >= 32'h017D_4000 && a < 32'h0189_4000)            return r_gw[(a - 32'h017D_4000) >> 4];
    if (a >= 32'h0189_4000 && a < 32'h0189_6000)            return r_go[(a - 32'h0189_4000) >> 4];
    if (a >= 32'h018A_0000 && a < 32'h018A_1800)            return r_gs[(a - 32'h018A_0000) >> 4];
    if (a >= 32'h018A_8000 && a < 32'h018A_9800)            return r_gp[(a - 32'h018A_8000) >> 4];
    if (a >= 32'h0190_0000 && a < 32'h0191_0000)            return r_pa[(a - 32'h0190_0000) >> 4];
    if (a >= 32'h0191_0000 && a < 32'h0193_0000)            return r_pb[(a - 32'h0191_0000) >> 4];
    if (a >= 32'h0193_0000 && a < 32'h0193_8000)            return r_pc[(a - 32'h0193_0000) >> 4];
    n_bad_addr++;
    if (n_bad_addr < 10) $display("  [DDR] doc dia chi ngoai vung: %08h", a);
    return 128'd0;
  endfunction

  // AXI4 doc: 1 giao dich treo, tre 6 chu ky, burst INCR
  logic        rd_busy = 0;
  logic [31:0] rd_addr;
  logic [8:0]  rd_left;
  logic [3:0]  rd_lat;
  assign m_axi_arready = !rd_busy;
  assign m_axi_rid = 6'd0; assign m_axi_rresp = 2'b00;
  always_ff @(posedge clk) begin
    if (!rst_n) begin rd_busy <= 0; m_axi_rvalid <= 0; m_axi_rlast <= 0; end
    else begin
      if (!rd_busy && m_axi_arvalid) begin
        rd_busy <= 1; rd_addr <= m_axi_araddr; rd_left <= {1'b0, m_axi_arlen} + 9'd1; rd_lat <= 4'd6;
        m_axi_rvalid <= 0;
      end else if (rd_busy) begin
        if (rd_lat != 0) rd_lat <= rd_lat - 4'd1;
        else if (!m_axi_rvalid || m_axi_rready) begin
          if (rd_left != 0) begin
            m_axi_rvalid <= 1; m_axi_rdata <= ddr_rd(rd_addr); m_axi_rlast <= (rd_left == 9'd1);
            rd_addr <= rd_addr + 32'd16; rd_left <= rd_left - 9'd1;
          end else begin
            m_axi_rvalid <= 0; m_axi_rlast <= 0; rd_busy <= 0;
          end
        end
      end
    end
  end

  // ── AXI-lite (task tinh — tranh loi xsim voi task automatic co output) ───────
  logic [31:0] rd_val;
  task axil_write(input logic [11:0] a, input logic [31:0] d);
    @(posedge clk);
    axil_awaddr <= a; axil_awvalid <= 1; axil_wdata <= d; axil_wvalid <= 1;
    @(posedge clk);
    while (!(axil_awready && axil_wready)) @(posedge clk);
    @(posedge clk); axil_awvalid <= 0; axil_wvalid <= 0;
    while (!axil_bvalid) @(posedge clk);
    @(posedge clk);
  endtask
  task axil_read(input logic [11:0] a);
    @(posedge clk);
    axil_araddr <= a; axil_arvalid <= 1;
    @(posedge clk);
    while (!axil_arready) @(posedge clk);
    @(posedge clk); axil_arvalid <= 0;
    while (!axil_rvalid) @(posedge clk);
    rd_val = axil_rdata;
    @(posedge clk);
  endtask

  // ── dem chu ky theo pha ──────────────────────────────────────────────────────
  longint ph_cyc [16];
  always @(posedge clk) if (rst_n) ph_cyc[dut.phase] += 1;


  // ── bo kiem tich hop (+CHK, chi dung khi mau co vector hwspec o tb/unit/bert_v2/vec/sXX) ──
  bit chk_on;
  string UV;
  logic [31:0] c_prm [65536], c_tok [384], c_pln [32768];
  logic [63:0] c_pe [16384], c_ur [196608];
  logic [0:0]  c_pad [64];
  int c_nv, c_fd, c_e, c_i, c_l;
  always @(posedge clk) if (chk_on && rst_n) begin
    // roi PH_PROJ -> PH_BERT: so PARAM, pos_emb, token, nvalid, mat na, XR (proj LN)
    if (dut.phase_prev == 2 && dut.phase == 3) begin
      c_e = 0; for (c_i = 0; c_i < 57344; c_i++) if (dut.u_bv2.u_pm.mem[c_i] !== c_prm[c_i]) begin if (c_e < 4) $display("   [CHK] PARAM[%0d] got %08h mong %08h", c_i, dut.u_bv2.u_pm.mem[c_i], c_prm[c_i]); c_e++; end
      $display("   [CHK] PARAM: %0d sai", c_e);
      c_e = 0; for (c_i = 0; c_i < 16384; c_i++) if (dut.u_posemb_bram.mem[c_i] !== c_pe[c_i]) begin if (c_e < 4) $display("   [CHK] POSEMB[%0d] got %016h mong %016h", c_i, dut.u_posemb_bram.mem[c_i], c_pe[c_i]); c_e++; end
      $display("   [CHK] POSEMB: %0d sai", c_e);
      $display("   [CHK] nvalid=%0d (mong %0d)  key_valid=%016h", dut.ia_num_valid_tokens, c_nv, dut.wmp_attn_mask);
      c_e = 0; for (c_i = 0; c_i < c_nv; c_i++) if (dut.ia_bbox_out[c_i] !== {c_tok[c_i*6], c_tok[c_i*6+1], c_tok[c_i*6+2], c_tok[c_i*6+3], c_tok[c_i*6+4], c_tok[c_i*6+5]}) begin
        if (c_e < 4) $display("   [CHK] TOK[%0d] got %048h", c_i, dut.ia_bbox_out[c_i]); c_e++; end
      $display("   [CHK] TOKEN: %0d sai", c_e);
      c_e = 0; for (c_i = 0; c_i < 32768; c_i++) if (dut.u_bv2.u_xr.mem[c_i] !== c_pln[c_i]) begin if (c_e < 4) $display("   [CHK] XR(projLN)[%0d] got %08h mong %08h", c_i, dut.u_bv2.u_xr.mem[c_i], c_pln[c_i]); c_e++; end
      $display("   [CHK] XR sau proj LN: %0d sai", c_e);
    end
    // vua vao BERT_SUB_COMPUTE: so URAM lop hien tai
    if (dut.bert_layer_start) begin
      c_l = dut.bert_layer_idx;
      $readmemh({UV, $sformatf("uram_%0d.hex", c_l)}, c_ur);
      c_e = 0; for (c_i = 0; c_i < 196608; c_i++) if (dut.u_uram_xpm.xpm_memory_base_inst.mem[c_i] !== c_ur[c_i]) begin
        if (c_e < 4) $display("   [CHK] URAM L%0d[%0d] got %016h mong %016h", c_l, c_i, dut.u_uram_xpm.xpm_memory_base_inst.mem[c_i], c_ur[c_i]); c_e++; end
      $display("   [CHK] URAM lop %0d: %0d sai", c_l, c_e);
    end
  end


  // ── CHE DO CHAN DOAN +GRU2: chay GRU 2 lan lien tiep tren CUNG CLS (s00), so ket qua ──
  // Ghi acc_row moi khi chot (S_ADDER_TREE -> S_MV_POST) cua tung lan; bao hang dau tien khac.
  localparam int NACC = 20000;
  logic [31:0] g2_acc [2][NACC];
  logic [7:0]  g2_tag_s [2][NACC]; logic [3:0] g2_tag_m [2][NACC]; logic [9:0] g2_tag_r [2][NACC];
  int g2_n [2]; int g2_run = -1;
  always @(posedge clk) if (g2_run >= 0 && dut.u_gru.state == 5 /* S_ADDER_TREE */
                           && dut.u_gru.at_cnt == 30 /* AT_LAT */ && g2_n[g2_run] < NACC) begin
    g2_acc[g2_run][g2_n[g2_run]]   = dut.u_gru.acc_tree;
    g2_tag_s[g2_run][g2_n[g2_run]] = dut.u_gru.step_cnt;
    g2_tag_m[g2_run][g2_n[g2_run]] = dut.u_gru.mat_idx;
    g2_tag_r[g2_run][g2_n[g2_run]] = dut.u_gru.row_cnt;
    g2_n[g2_run]++;
  end

  // snapshot vao hang dau (S_MV_SETUP, step0 mat0 row0): x_t (SCR_X_T, baddr 80..95), cls_local,
  // thang hang 0, 16 cap toan hang FMAC lan 0 dau tien
  logic [31:0] g2_x [2][512], g2_cls [2][512], g2_sc [2], g2_fa [2][16], g2_fb [2][16];
  int g2_snap [2], g2_nf [2];
  always @(posedge clk) if (g2_run >= 0) begin
    if (dut.u_gru.state == 2 && dut.u_gru.step_cnt == 0 && dut.u_gru.mat_idx == 0 && dut.u_gru.row_cnt == 0
        && g2_snap[g2_run] == 0) begin
      g2_snap[g2_run] = 1;
      for (int e = 0; e < 512; e++) begin
        g2_x[g2_run][e]   = dut.u_gru.scr_dbg(e % 32, 80 + e / 32);
        g2_cls[g2_run][e] = dut.u_gru.cls_local[e % 32][e / 32];
      end
      g2_sc[g2_run] = dut.u_gru.gru_scale_rdata;
    end
    if (g2_snap[g2_run] == 1 && dut.u_gru.par_fmac_en[0] && g2_nf[g2_run] < 16) begin
      g2_fa[g2_run][g2_nf[g2_run]] = dut.u_gru.par_fmac_a[0];
      g2_fb[g2_run][g2_nf[g2_run]] = dut.u_gru.par_fmac_b[0];
      g2_nf[g2_run]++;
    end
  end
  task g2_report();
    int ex = 0, ec = 0, ea = 0, eb = 0, fx = -1;
    for (int e = 0; e < 512; e++) begin
      if (g2_x[0][e] !== g2_x[1][e]) begin ex++; if (fx < 0) fx = e; end
      if (g2_cls[0][e] !== g2_cls[1][e]) ec++;
    end
    for (int i = 0; i < 16; i++) begin if (g2_fa[0][i] !== g2_fa[1][i]) ea++; if (g2_fb[0][i] !== g2_fb[1][i]) eb++; end
    $display("[GRU2] x_t khac %0d/512 (dau tien e=%0d: %08h vs %08h) | cls_local khac %0d | scale %04h vs %04h | FMAC0 a khac %0d/16, b khac %0d/16",
             ex, fx, fx >= 0 ? g2_x[0][fx] : 0, fx >= 0 ? g2_x[1][fx] : 0, ec, g2_sc[0], g2_sc[1], ea, eb);
    for (int i = 0; i < 4; i++) $display("[GRU2]  FMAC0 #%0d a %08h/%08h b %08h/%08h", i, g2_fa[0][i], g2_fa[1][i], g2_fb[0][i], g2_fb[1][i]);
  endtask

  task gru2_run();
    logic [31:0] cls [512];
    logic [31:0] wx [2][4], wy [2][4];
    int r, i, first;
    $readmemh({V, "s00_cls.hex"}, cls);
    for (i = 0; i < 512; i++) dut.u_cls_buf.mem[i] = cls[i];
    force dut.gru_active = 1'b1;
    for (r = 0; r < 2; r++) begin
      g2_run = r; g2_n[r] = 0; g2_snap[r] = 0; g2_nf[r] = 0;
      @(posedge clk); force dut.u_gru.gru_start = 1'b1; @(posedge clk); release dut.u_gru.gru_start;
      while (!dut.u_gru.gru_done) @(posedge clk);
      repeat (3) @(posedge clk);
      for (i = 0; i < 4; i++) begin wx[r][i] = dut.u_gru.waypoint_x[i]; wy[r][i] = dut.u_gru.waypoint_y[i]; end
      $display("[GRU2] lan %0d: %0d acc_row, WP3=(%f,%f)", r, g2_n[r], f2r(wx[r][3]), f2r(wy[r][3]));
    end
    g2_run = -1;
    release dut.gru_active;
    g2_report();
    first = -1;
    for (i = 0; i < g2_n[0] && i < g2_n[1]; i++) if (g2_acc[0][i] !== g2_acc[1][i]) begin first = i; break; end
    if (first < 0) $display("[GRU2] moi acc_row TRUNG giua 2 lan");
    else $display("[GRU2] KHAC DAU TIEN o acc_row #%0d: step=%0d mat=%0d row=%0d  lan0=%08h lan1=%08h",
                  first, g2_tag_s[0][first], g2_tag_m[0][first], g2_tag_r[0][first], g2_acc[0][first], g2_acc[1][first]);
    for (i = 0; i < 4; i++) if (wx[0][i] !== wx[1][i] || wy[0][i] !== wy[1][i])
      $display("[GRU2] WP%0d khac: lan0 (%08h,%08h) lan1 (%08h,%08h)", i, wx[0][i], wy[0][i], wx[1][i], wy[1][i]);
    $display("==== GRU2 xong ====");
    $finish;
  endtask

  // ── chay ────────────────────────────────────────────────────────────────────
  string sn;
  int S0, NS, si, k, n_cls_err, tot_fail = 0, to, wp_fd;
  logic [31:0] cls_exp [512], wp_exp [8], gt [8];
  real wpx, wpy, ex, ey, gx, gy, dmax, err_gt, sum_ade = 0.0, maxdiff_all = 0.0;
  longint c0;

  function automatic real f2r(input logic [31:0] b); return real'($bitstoshortreal(b)); endfunction

  initial begin
    if (!$value$plusargs("S0=%d", S0)) S0 = 0;
    if (!$value$plusargs("NS=%d", NS)) NS = 1;
    $readmemh({V, "ddr_bert_weights.hex"}, r_bw);
    $readmemh({V, "ddr_pos_emb.hex"}, r_pe);
    $readmemh({V, "ddr_param_a.hex"}, r_pa); $readmemh({V, "ddr_param_b.hex"}, r_pb); $readmemh({V, "ddr_param_c.hex"}, r_pc);
    $readmemh({V, "ddr_gru_bias.hex"}, r_gb); $readmemh({V, "ddr_gru_weights.hex"}, r_gw);
    $readmemh({V, "ddr_gru_wout_staging.hex"}, r_go); $readmemh({V, "ddr_gru_scale_zp.hex"}, r_gs);
    $readmemh({V, "ddr_gru_wp_proj.hex"}, r_gp);
    for (k = 0; k < 1024; k++) r_wm[k] = '0;
    repeat (20) @(posedge clk); rst_n = 1;

    // cho static boot + nap GRU
    to = 0;
    do begin repeat (2000) @(posedge clk); axil_read(12'h004); to++; end
    while (!(rd_val[8] && rd_val[10]) && to < 2000);
    $display("[%0t] boot xong: STATUS=%08h, chu ky=%0d", $time, rd_val, $time / TCK);
    if (!(rd_val[8] && rd_val[10])) begin $display("==== E2E: BOOT HET GIO ===="); $finish; end
    if ($test$plusargs("GRU2")) gru2_run();
    axil_write(12'h034, 32'h1);           // IRQ_ENABLE done
    axil_write(12'h008, 32'h0);           // WM_SEL = A

    for (si = S0; si < S0 + NS; si++) begin
      sn = $sformatf("s%02d", si);
      for (k = 0; k < 1024; k++) r_wm[k] = '0;
      $readmemh({V, sn, "_wm.hex"}, r_wm);
      $readmemh({V, sn, "_cls.hex"}, cls_exp);
      $readmemh({V, sn, "_wp.hex"}, wp_exp);
      $readmemh({V, sn, "_gt.hex"}, gt);
      chk_on = $test$plusargs("CHK");
      if (chk_on) begin
        UV = {"tb/unit/bert_v2/vec/", sn, "/"};
        $readmemh({UV, "param.hex"}, c_prm); $readmemh({UV, "tok.hex"}, c_tok); $readmemh({UV, "proj_ln.hex"}, c_pln);
        $readmemh({UV, "posemb.hex"}, c_pe); $readmemh({UV, "pad.hex"}, c_pad);
        c_fd = $fopen({UV, "meta.txt"}, "r"); void'($fscanf(c_fd, "%d", c_nv)); $fclose(c_fd);
      end
      for (k = 0; k < 16; k++) ph_cyc[k] = 0;
      c0 = $time / TCK;
      axil_write(12'h000, 32'h1);         // START
      to = 0;
      while (!done_irq && to < 30_000_000) begin @(posedge clk); to++; end
      if (!done_irq) begin $display("==== E2E %s: HET GIO (pha %0d) ====", sn, dut.phase); $finish; end
      repeat (5) @(posedge clk);
      axil_write(12'h000, 32'h100);       // xoa IRQ
      // CLS tung bit
      n_cls_err = 0;
      for (k = 0; k < 512; k++) if (dut.u_cls_buf.mem[k] !== cls_exp[k]) begin
        if (n_cls_err < 5) $display("  %s CLS[%0d]: got %08h mong %08h", sn, k, dut.u_cls_buf.mem[k], cls_exp[k]);
        n_cls_err++;
      end
      // waypoint qua CSR
      dmax = 0.0; err_gt = 0.0;
      wp_fd = $fopen({"tb/e2e/results/wp_rtl_", sn, ".txt"}, "w");
      for (k = 0; k < 4; k++) begin
        axil_read(12'h010 + 12'(k*8)); wpx = f2r(rd_val); $fwrite(wp_fd, "%08h ", rd_val);
        axil_read(12'h014 + 12'(k*8)); wpy = f2r(rd_val); $fwrite(wp_fd, "%08h ", rd_val);
        ex = f2r(wp_exp[2*k]); ey = f2r(wp_exp[2*k+1]); gx = f2r(gt[2*k]); gy = f2r(gt[2*k+1]);
        if ((wpx-ex < 0 ? ex-wpx : wpx-ex) > dmax) dmax = (wpx-ex < 0 ? ex-wpx : wpx-ex);
        if ((wpy-ey < 0 ? ey-wpy : wpy-ey) > dmax) dmax = (wpy-ey < 0 ? ey-wpy : wpy-ey);
        err_gt += $sqrt((wpx-gx)*(wpx-gx) + (wpy-gy)*(wpy-gy)) / 4.0;
        if (k == 3) $display("  %s WP3 = (%8.3f, %8.3f)  mong (%8.3f, %8.3f)  GT (%8.3f, %8.3f)", sn, wpx, wpy, ex, ey, gx, gy);
      end
      $fwrite(wp_fd, "%0d\n", n_cls_err); $fclose(wp_fd);
      sum_ade += err_gt;
      if (dmax > maxdiff_all) maxdiff_all = dmax;
      $display("  %s: CLS %0d loi | lech WP vs GRU-RTL-equiv max %.6f m | ADE vs GT %.3f m | %0d chu ky (%.3f ms @185MHz)",
               sn, n_cls_err, dmax, err_gt, $time / TCK - c0, ($time / TCK - c0) * TCK * 1e-6);
      $display("     pha: WM %0d | PROJ %0d | BERT %0d | CLS %0d | GRU %0d | OUT %0d",
               ph_cyc[1], ph_cyc[2], ph_cyc[3], ph_cyc[4], ph_cyc[5], ph_cyc[6]);
      if (n_cls_err != 0 || dmax > 1e-3) tot_fail++;
    end
    $display("TONG KET: %0d/%0d mau DAT | ADE TB %.3f m | lech WP lon nhat %.6f m | dia chi DDR la %0d",
             NS - tot_fail, NS, sum_ade / NS, maxdiff_all, n_bad_addr);
    if (tot_fail == 0 && n_bad_addr == 0) $display("==== E2E TRAJ: DAT ====");
    else $display("==== E2E TRAJ: %0d MAU LOI ====", tot_fail);
    $finish;
  end
endmodule
