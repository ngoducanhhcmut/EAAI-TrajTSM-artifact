// =============================================================================
// tb_traj_sysbd.sv — VLA-Traj (planning_top) muc he thong qua IP that (sim_traj/build_bd.tcl).
//   * DDR = AXI VIP slave 128 bit sau SmartConnect that, khe ngau nhien 0..8 chu ky giua cac beat R.
//     Noi dung nap tu tb/e2e/vec/ddr_*.hex (trung tung byte voi payload board sw/payloads/v2).
//   * AXI-Lite: ghi theo 3 kieu (AW truoc W, W truoc AW, cung luc) roi doc lai — kiem ban sua AXI-Lite.
//   * Trinh tu nhu firmware: cho nap trong so (STATUS bit 8,10), IRQ_EN, WM_SEL, START, doc 4 waypoint.
//   * So waypoint voi tb/e2e/results/final_35/wp_rtl_s00.txt (E2E 35/35) — phai trung TUNG BIT.
//   Bien dich voi -d SYNTHESIS -d ASSERT_ON (nhu E2E).
// =============================================================================
`timescale 1ps/1ps
import axi_vip_pkg::*;
import traj_ifc_axi_vip_mem_0_pkg::*;

module tb_traj_sysbd;
  logic clk = 0, hclk = 0, ext_rst_n = 0;
  always #3333 clk = ~clk;      // 150 MHz (clk_pl_0)
  always #2667 hclk = ~hclk;    // 187,5 MHz (hmao_clk, chi cau CDC sang TSM)
  wire rst_n;

  logic [11:0] awaddr = 0, araddr = 0; logic awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  logic [31:0] wdata = 0;
  wire awready, wready, bvalid, arready, rvalid; wire [1:0] bresp, rresp; wire [31:0] rdata;
  wire [5:0] arid, rid; wire [31:0] m_araddr; wire [7:0] arlen; wire [2:0] arsize, arprot; wire [1:0] arburst, arlock;
  wire [3:0] arcache, arqos; wire m_arvalid, m_arready, m_rready, m_rlast, m_rvalid; wire [127:0] m_rdata; wire [1:0] m_rresp;
  wire done_irq, wload_timeout_err, m_awvalid;

  traj_ifc_wrapper u_bd (
    .clk0(clk), .ext_rst_n(ext_rst_n), .rst0_n(rst_n),
    .S_AXI_TRAJ_araddr(m_araddr), .S_AXI_TRAJ_arburst(arburst), .S_AXI_TRAJ_arcache(arcache), .S_AXI_TRAJ_arid(arid),
    .S_AXI_TRAJ_arlen(arlen), .S_AXI_TRAJ_arlock(arlock[0]), .S_AXI_TRAJ_arprot(arprot), .S_AXI_TRAJ_arqos(arqos),
    .S_AXI_TRAJ_arready(m_arready), .S_AXI_TRAJ_arsize(arsize), .S_AXI_TRAJ_arvalid(m_arvalid),
    .S_AXI_TRAJ_rdata(m_rdata), .S_AXI_TRAJ_rid(rid), .S_AXI_TRAJ_rlast(m_rlast), .S_AXI_TRAJ_rready(m_rready),
    .S_AXI_TRAJ_rresp(m_rresp), .S_AXI_TRAJ_rvalid(m_rvalid));

  planning_top_bd_ref u_dut (
    .clk(clk), .rst_n(rst_n), .hmao_clk(hclk), .hmao_rst_n(rst_n),
    .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(4'hF), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
    .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
    .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
    .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
    .m_axi_arid(arid), .m_axi_araddr(m_araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize), .m_axi_arburst(arburst),
    .m_axi_arlock(arlock), .m_axi_arcache(arcache), .m_axi_arprot(arprot), .m_axi_arqos(arqos),
    .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready), .m_axi_rid(rid), .m_axi_rdata(m_rdata),
    .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
    .m_axi_awid(), .m_axi_awaddr(), .m_axi_awlen(), .m_axi_awsize(), .m_axi_awburst(), .m_axi_awlock(),
    .m_axi_awcache(), .m_axi_awprot(), .m_axi_awqos(), .m_axi_awvalid(m_awvalid), .m_axi_awready(1'b0),
    .m_axi_wid(), .m_axi_wdata(), .m_axi_wstrb(), .m_axi_wlast(), .m_axi_wvalid(), .m_axi_wready(1'b0),
    .m_axi_bid(6'd0), .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0), .m_axi_bready(),
    .waypoint_x(), .waypoint_y(), .waypoints_valid(), .waypoints_sanity_pass(),
    .done_irq(done_irq), .wload_timeout_err(wload_timeout_err));

  // ---- kiem giao thuc phia master DMA: RLAST dung beat cuoi, khong beat thua, RRESP ----
  int q_len [$]; int beat_in = 0, n_proto = 0, n_rerr = 0, n_ar = 0;
  logic p_pend = 0; logic [31:0] p_addr; logic [7:0] p_len;
  always @(posedge clk) if (rst_n) begin
    if (p_pend && !(m_arvalid && m_araddr == p_addr && arlen == p_len)) begin
      n_proto++; if (n_proto < 5) $display("  !! AXI: AR doi/ha truoc ARREADY t=%0t", $time); end
    p_pend <= m_arvalid && !m_arready; p_addr <= m_araddr; p_len <= arlen;
    if (m_arvalid && m_arready) begin q_len.push_back(int'(arlen) + 1); n_ar++; end
    if (m_rvalid && m_rready) begin
      if (m_rresp != 2'b00) n_rerr++;
      if (q_len.size() == 0) begin n_proto++; if (n_proto < 5) $display("  !! AXI: beat R khong co AR t=%0t", $time); end
      else begin
        beat_in++;
        if (m_rlast != (beat_in == q_len[0])) begin n_proto++; if (n_proto < 5) $display("  !! AXI: RLAST sai %0d/%0d t=%0t", beat_in, q_len[0], $time); end
        if (m_rlast || beat_in == q_len[0]) begin void'(q_len.pop_front()); beat_in = 0; end
      end
    end
    if (m_awvalid) begin n_proto++; if (n_proto < 5) $display("  !! Traj phat lenh GHI DDR (khong mong doi)"); end
  end

  // ---- AXI-Lite: mode 0 = AW va W cung luc, 1 = AW truoc W (lech 3 chu ky), 2 = W truoc AW ----
  logic [31:0] rd_val; int n_csr_bad = 0;
  task automatic axil_write(input logic [11:0] a, input logic [31:0] d, input int mode);
    int to = 0;
    @(posedge clk);
    if (mode != 2) begin awaddr <= a; awvalid <= 1; end
    if (mode != 1) begin wdata <= d; wvalid <= 1; end
    if (mode != 0) begin
      repeat (3) @(posedge clk);
      if (mode == 1) begin wdata <= d; wvalid <= 1; end else begin awaddr <= a; awvalid <= 1; end
    end
    bready <= 1;
    // giu valid cho toi khi duoc nhan (moi kenh rieng, dung chuan AXI)
    fork
      begin do @(posedge clk); while (!(awvalid && awready)); awvalid <= 0; end
      begin do @(posedge clk); while (!(wvalid && wready)); wvalid <= 0; end
    join
    while (!bvalid && to < 1000) begin @(posedge clk); to++; end
    if (!bvalid) begin $display("  !! AXI-Lite: GHI 0x%03h (kieu %0d) KHONG CO PHAN HOI B (CPU se treo)", a, mode); n_csr_bad++; end
    @(posedge clk); bready <= 0;
  endtask
  task automatic axil_read(input logic [11:0] a);
    @(posedge clk); araddr <= a; arvalid <= 1; rready <= 1;
    do @(posedge clk); while (!(arvalid && arready)); arvalid <= 0;
    while (!rvalid) @(posedge clk);
    rd_val = rdata; @(posedge clk); rready <= 0;
  endtask

  traj_ifc_axi_vip_mem_0_slv_mem_t mem;
  localparam string V = "C:/Users/TransformerDA/Downloads/vla_new_arch/tb/e2e/vec/";
  task automatic load_region(input string f, input longint base, input int n);
    logic [127:0] buf_[];
    buf_ = new[n];
    $readmemh({V, f}, buf_);
    for (int i = 0; i < n; i++) mem.mem_model.backdoor_memory_write(base + 16 * i, buf_[i], '1);
    $display("  nap %s -> 0x%08h (%0d dong 128 bit)", f, base, n);
  endtask

  logic [31:0] gold [9];
  initial begin
    int fd, to, ok_csr, n_wp_bad; longint t0;
    mem = new("mem", tb_traj_sysbd.u_bd.traj_ifc_i.axi_vip_mem.inst.IF);
    mem.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_FIXED);
    mem.mem_model.set_default_memory_value(0);
    mem.start_slave();
    mem.mem_model.set_inter_beat_gap_delay_policy(XIL_AXI_MEMORY_DELAY_RANDOM);
    mem.mem_model.set_inter_beat_gap_range(0, 8);
    $display("=== TRAJ SYSBD: nap DDR ===");
    load_region("ddr_bert_weights.hex", 64'h0000_0000, 393216);
    load_region("ddr_pos_emb.hex",      64'h0060_0000, 8192);
    load_region("ddr_param_a.hex",      64'h0190_0000, 4096);
    load_region("ddr_param_b.hex",      64'h0191_0000, 8192);
    load_region("ddr_param_c.hex",      64'h0193_0000, 2048);
    load_region("ddr_gru_bias.hex",     64'h017D_2000, 512);
    load_region("ddr_gru_weights.hex",  64'h017D_4000, 49152);
    load_region("ddr_gru_wout_staging.hex", 64'h0189_4000, 512);
    load_region("ddr_gru_scale_zp.hex", 64'h018A_0000, 384);
    load_region("ddr_gru_wp_proj.hex",  64'h018A_8000, 384);
    load_region("s00_wm.hex",           64'h0064_0000, 1024);
    fd = $fopen("C:/Users/TransformerDA/Downloads/vla_new_arch/tb/e2e/results/final_35/wp_rtl_s00.txt", "r");
    for (int i = 0; i < 9; i++) void'($fscanf(fd, "%h", gold[i]));
    $fclose(fd);

    repeat (20) @(posedge clk); ext_rst_n = 1;
    wait (rst_n === 1'b1);
    $display("[%0t] nha reset PL -> Traj tu nap trong so tu DDR", $time);

    // --- kiem AXI-Lite: ghi TARGET_X/Y (0x060/0x064) theo 3 kieu, doc lai, tra ve 0 ---
    ok_csr = 0;
    axil_write(12'h060, 32'h1234_5678, 1); axil_read(12'h060); ok_csr += (rd_val == 32'h1234_5678);
    $display("  AXI-Lite AW truoc W : doc lai 0x%08h %s", rd_val, rd_val == 32'h1234_5678 ? "DAT" : "SAI");
    axil_write(12'h064, 32'h9ABC_DEF0, 2); axil_read(12'h064); ok_csr += (rd_val == 32'h9ABC_DEF0);
    $display("  AXI-Lite W truoc AW : doc lai 0x%08h %s", rd_val, rd_val == 32'h9ABC_DEF0 ? "DAT" : "SAI");
    axil_write(12'h060, 32'h0BAD_F00D, 0); axil_read(12'h060); ok_csr += (rd_val == 32'h0BAD_F00D);
    $display("  AXI-Lite cung luc   : doc lai 0x%08h %s", rd_val, rd_val == 32'h0BAD_F00D ? "DAT" : "SAI");
    axil_write(12'h060, 32'h0, 1); axil_write(12'h064, 32'h0, 2);
    axil_read(12'h060); ok_csr += (rd_val == 0); axil_read(12'h064); ok_csr += (rd_val == 0);

    // --- cho nap trong so (nhu script board: STATUS bit 8 va 10) ---
    to = 0;
    do begin repeat (2000) @(posedge clk); axil_read(12'h004); to++; end
    while (!(rd_val[8] && rd_val[10]) && to < 3000);
    $display("[%0t] STATUS=0x%08h sau khi nap trong so (%0d AR, rerr=%0d, proto=%0d)", $time, rd_val, n_ar, n_rerr, n_proto);
    if (!(rd_val[8] && rd_val[10])) begin $display("==== TRAJ SYSBD: NAP TRONG SO HET GIO ===="); $finish; end

    axil_write(12'h034, 32'h1, 1);   // IRQ_ENABLE (AW truoc W)
    axil_write(12'h008, 32'h0, 2);   // WM_SEL = A (W truoc AW)
    t0 = $time;
    axil_write(12'h000, 32'h1, 1);   // START
    to = 0;
    while (!done_irq && to < 30_000_000) begin @(posedge clk); to++; end
    if (!done_irq) begin $display("==== TRAJ SYSBD: SUY LUAN HET GIO ===="); $finish; end
    $display("[%0t] xong suy luan sau %0d chu ky (%.2f ms @150 MHz)", $time, (($time - t0) / 6666), real'($time - t0) / 1.0e9);
    repeat (5) @(posedge clk);
    axil_write(12'h000, 32'h100, 2);  // xoa IRQ
    n_wp_bad = 0;
    for (int k = 0; k < 8; k++) begin
      axil_read(12'h010 + 12'(k * 4));
      if (rd_val !== gold[k]) n_wp_bad++;
      $display("  WP word %0d: FPGA-RTL 0x%08h  E2E-35/35 0x%08h  %s", k, rd_val, gold[k], rd_val === gold[k] ? "trung" : "KHAC");
    end
    $display("=== KET QUA: AXI-Lite %0d/5 | CSR khong phan hoi %0d | waypoint khac %0d/8 | AXI proto %0d | RRESP loi %0d | %0d AR",
             ok_csr, n_csr_bad, n_wp_bad, n_proto, n_rerr, n_ar);
    if (ok_csr == 5 && n_csr_bad == 0 && n_wp_bad == 0 && n_proto == 0 && n_rerr == 0)
      $display("==== TRAJ SYSBD: DAT ====");
    else $display("==== TRAJ SYSBD: SAI ====");
    $finish;
  end
endmodule
