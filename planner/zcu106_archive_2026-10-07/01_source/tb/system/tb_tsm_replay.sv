// =============================================================================
// tb_tsm_replay.sv — phat lai DUNG 53 ca cua firmware demo (sw/board/tsm_demo.c: [A] 35 khung,
// [B] 15 ca, [C] CRC / NaN / xe chan) lien tiep, KHONG reset giua cac ca, qua IP that cua BD
// (sim_replay/build_bd.tcl = BD cua sim_sysbd: TSM -> SmartConnect -> VIP bo nho 128 bit; kiem giao thuc AXI tu viet).
//
// Them so voi tb_tsm_sysbd:
//   * replay_cfg.txt (tuy chon): dong 1 = 1 bat backpressure ngau nhien o bo nho (ARREADY + khe giua beat),
//     dong 2 = khoang nghi giua cac ca (us). Mac dinh: 1, 200.
//   * Kiem thu tu AR quy dao: dung 8 burst, dia chi 0x7030_0000 + k*176, khong phat AR khi con burst dang bay.
//   * Do so chu ky tu hmao_start toi luc FSM ra quyet dinh (chi RTL) va co chay tang 2 hay khong.
// Chay voi SIM_FAST_TSM + SIM_FAST_PREPROC: kiem quyet dinh / fault / giao thuc; KHONG kiem moc 8 ms.
// =============================================================================
`timescale 1ps/1ps
import axi_vip_pkg::*;
import tsm_ifc_axi_vip_mem_0_pkg::*;
import tsm_ifc_axi_vip_cpu_0_pkg::*;

module tb_tsm_replay;
  localparam int NC = 53;
  localparam longint TRAJ_BASE = 64'h7030_0000;
  localparam longint WM_BASE   = 64'h7040_0000;
  localparam bit [31:0] GPIO0 = 32'hA001_0000, GPIO1 = 32'hA002_0000;

  logic clk0 = 0, clk2 = 0, clk3 = 0, ext_rst_n = 0;
  always #5000 clk0 = ~clk0;   // pl_clk0 100 MHz (psu_init ZCU106)
  always #2667 clk2 = ~clk2;   // pl_clk2 187,5 MHz
  always #2000 clk3 = ~clk3;   // pl_clk3 250 MHz

  wire rst0_n, rst2_n, gpio_start, gpio_irqclr;
  wire [31:0] gpio_status, gpio_detail;
  wire hmao_start, irq_clear;
  wire [3:0]   arid;   wire [31:0] araddr; wire [7:0] arlen; wire [2:0] arsize; wire [1:0] arburst;
  wire         arvalid, arready, rready, rlast, rvalid;
  wire [3:0]   rid;    wire [255:0] rdata; wire [1:0] rresp;
  wire         hmao_complete, hmao_decision, fault_valid;
  wire [63:0]  hmao_violation;
  wire [6:0]   fault_bits;

  tsm_ifc_wrapper u_bd (
    .clk0(clk0), .clk2(clk2), .ext_rst_n(ext_rst_n), .rst0_n(rst0_n), .rst2_n(rst2_n),
    .gpio_start(gpio_start), .gpio_irqclr(gpio_irqclr), .gpio_status(gpio_status), .gpio_detail(gpio_detail),
    .S_AXI_HMAO_araddr(araddr), .S_AXI_HMAO_arburst(arburst), .S_AXI_HMAO_arid(arid),
    .S_AXI_HMAO_arlen(arlen), .S_AXI_HMAO_arready(arready), .S_AXI_HMAO_arsize(arsize),
    .S_AXI_HMAO_arvalid(arvalid), .S_AXI_HMAO_rdata(rdata), .S_AXI_HMAO_rid(rid),
    .S_AXI_HMAO_rlast(rlast), .S_AXI_HMAO_rready(rready), .S_AXI_HMAO_rresp(rresp),
    .S_AXI_HMAO_rvalid(rvalid),
    // TSM khong co cac chan nay; tren BD that SmartConnect tu gan mac dinh (ARCACHE=0011, con lai 0)
    .S_AXI_HMAO_arcache(4'b0011), .S_AXI_HMAO_arlock(1'b0), .S_AXI_HMAO_arprot(3'b000), .S_AXI_HMAO_arqos(4'b0000));

  hmao_gpio_cdc_bridge u_cdc (
    .src_clk(clk0), .src_rst_n(rst0_n), .gpio_start_level(gpio_start), .gpio_irqclr_level(gpio_irqclr),
    .dst_clk(clk2), .dst_rst_n(rst2_n), .hmao_start_pulse(hmao_start), .irq_clear_pulse(irq_clear));

  hmao_engine_top_bd_ref u_tsm (
    .clk(clk2), .rst_n(rst2_n), .wdt_clk(clk3), .hmao_start(hmao_start), .irq_clear(irq_clear),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready), .m_axi_rid(rid),
    .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
    .m_axi_rready(rready), .hmao_complete(hmao_complete), .hmao_decision_out(hmao_decision),
    .hmao_violation_out(hmao_violation), .hmao_status_out(), .hmao_latency_out(),
    .lateral_margin_out(), .long_margin_out(), .time_margin_out(),
    .fault_bits_out(fault_bits), .fault_valid_out(fault_valid));

  tsm_status_pack u_pack (
    .hmao_decision(hmao_decision), .hmao_complete(hmao_complete), .hmao_violation(hmao_violation),
    .fault_bits(fault_bits), .fault_valid(fault_valid), .gpio_status(gpio_status), .gpio_detail(gpio_detail));

  // ---- theo doi bus doc + FSM ----
  int n_ar_narrow, n_ar_wide, n_rbeat, n_rerr, n_overlap, n_badaddr, outstanding;
  int dec_cyc, cyc;
  bit seen_s2, decided;
  always @(posedge clk2) begin
    if (arvalid && arready) begin
      if (outstanding != 0) n_overlap++;
      if (arsize == 3'd2) begin
        if (araddr != 32'(TRAJ_BASE + n_ar_narrow * 176) ||
            arlen != ((n_ar_narrow == 7) ? 8'd42 : 8'd43)) n_badaddr++;
        n_ar_narrow++;
      end else n_ar_wide++;
    end
    if (rvalid && rready) begin
      n_rbeat++;
      if (rresp != 2'b00) n_rerr++;
    end
    outstanding <= outstanding + ((arvalid && arready) ? 1 : 0) - ((rvalid && rready && rlast) ? 1 : 0);
    if (hmao_start) begin cyc <= 0; decided <= 0; seen_s2 <= 0; end
    else begin
      cyc <= cyc + 1;
      if (u_tsm.u_hmao_bd.u_hmao.fsm_state == hmao_pkg::FSM_STAGE2_COMP) seen_s2 <= 1;
      if (!decided && (u_tsm.u_hmao_bd.u_hmao.output_grant || u_tsm.u_hmao_bd.u_hmao.output_veto)) begin
        decided <= 1; dec_cyc <= cyc;
      end
    end
  end

  // ---- kiem giao thuc AXI ngay cong TSM (thay VIP passthrough, vi passthrough lam SmartConnect hieu sai narrow) ----
  // (1) khi ARVALID=1 va chua ARREADY: ARADDR/ARLEN/ARSIZE/ARBURST phai giu nguyen; ARVALID khong duoc ha
  // (2) so beat moi burst = ARLEN+1, RLAST dung beat cuoi; (3) RID = ARID; (4) khong X tren AR khi ARVALID
  int n_proto;
  logic        p_arvalid; logic [31:0] p_araddr; logic [7:0] p_arlen; logic [2:0] p_arsize; logic [1:0] p_arburst;
  logic        p_pend;
  int          q_len [$]; int beat_in_burst;
  always @(posedge clk2) begin
    if (rst2_n) begin
      if (p_pend && !(arvalid && araddr == p_araddr && arlen == p_arlen && arsize == p_arsize && arburst == p_arburst)) begin
        n_proto++; $display("  !! AXI: AR thay doi/ha truoc khi ARREADY t=%0t", $time);
      end
      if (arvalid && ($isunknown(araddr) || $isunknown(arlen) || $isunknown(arsize))) begin
        n_proto++; $display("  !! AXI: X tren kenh AR t=%0t", $time);
      end
      p_pend <= arvalid && !arready;
      p_araddr <= araddr; p_arlen <= arlen; p_arsize <= arsize; p_arburst <= arburst;
      if (arvalid && arready) q_len.push_back(int'(arlen) + 1);
      if (rvalid && rready) begin
        if (q_len.size() == 0) begin n_proto++; $display("  !! AXI: beat R khong co AR t=%0t", $time); end
        else begin
          if (rid != arid && 0) n_proto++;
          beat_in_burst++;
          if (rlast != (beat_in_burst == q_len[0])) begin
            n_proto++; $display("  !! AXI: RLAST sai (beat %0d / %0d) t=%0t", beat_in_burst, q_len[0], $time);
          end
          if (rlast || beat_in_burst == q_len[0]) begin void'(q_len.pop_front()); beat_in_burst = 0; end
        end
      end
    end else begin p_pend <= 0; end
  end

  tsm_ifc_axi_vip_mem_0_slv_mem_t mem;
  tsm_ifc_axi_vip_cpu_0_mst_t     cpu;

  logic [31:0] traj_m [0:NC*512-1];
  logic [31:0] wm_m   [0:NC*2048-1];
  int    exp_g [NC];
  int    exp_mode [NC];
  int    exp_f [NC];
  string exp_n [NC];

  task automatic wr32(input bit [31:0] a, input bit [31:0] d);
    xil_axi_resp_t r;
    cpu.AXI4LITE_WRITE_BURST(a, 0, d, r);
    if (r != XIL_AXI_RESP_OKAY) $display("  !! AXI-Lite ghi 0x%08h resp=%0d", a, r);
  endtask
  task automatic rd32(input bit [31:0] a, output bit [31:0] d);
    xil_axi_resp_t r;
    cpu.AXI4LITE_READ_BURST(a, 0, d, r);
    if (r != XIL_AXI_RESP_OKAY) $display("  !! AXI-Lite doc 0x%08h resp=%0d", a, r);
  endtask
  task automatic load_words(input longint base, input int first, input int n, input bit is_wm);
    bit [127:0] line;
    for (int i = 0; i < n; i += 4) begin
      for (int k = 0; k < 4; k++)
        line[32*k +: 32] = is_wm ? wm_m[first + i + k] : traj_m[first + i + k];
      mem.mem_model.backdoor_memory_write(base + 4 * i, line, '1);
    end
  endtask

  int npass, nfail, bp, gap_us;
  initial begin
    int fd, g, md, f; string nm;
    bit [31:0] st, st2, dt, pre;
    longint t0, t1;
    axi_ready_gen arg;
    bp = 1; gap_us = 200;
    fd = $fopen("replay_cfg.txt", "r");
    if (fd != 0) begin void'($fscanf(fd, "%d %d", bp, gap_us)); $fclose(fd); end
    $readmemh("traj.mem", traj_m);
    $readmemh("wm.mem", wm_m);
    fd = $fopen("expect.txt", "r");
    for (int i = 0; i < NC; i++) begin
      void'($fscanf(fd, "%d %d %h %s\n", g, md, f, nm));
      exp_g[i] = g; exp_mode[i] = md; exp_f[i] = f; exp_n[i] = nm;
    end
    $fclose(fd);

    mem = new("mem", tb_tsm_replay.u_bd.tsm_ifc_i.axi_vip_mem.inst.IF);
    cpu = new("cpu", tb_tsm_replay.u_bd.tsm_ifc_i.axi_vip_cpu.inst.IF);
    mem.start_slave();
    cpu.start_master();
    $display("  [init] VIP da chay, bp=%0d", bp);
    if (bp) begin
      // Chi dung khe ngau nhien giua cac beat R cua mo hinh bo nho (send_arready tren mem agent lam treo mo phong).
      mem.mem_model.set_inter_beat_gap_delay_policy(XIL_AXI_MEMORY_DELAY_RANDOM);
      $display("  [init] da dat chinh sach khe ngau nhien");
      mem.mem_model.set_inter_beat_gap_range(0, 12);
      $display("  [init] da cai backpressure: khe 0..12 chu ky giua cac beat R");
    end

    repeat (20) @(posedge clk0);
    ext_rst_n = 1;
    $display("  [init] nha reset t=%0t", $time);
    wait (rst0_n === 1'b1 && rst2_n === 1'b1);
    repeat (50) @(posedge clk0);
    $display("=== TSM REPLAY 53 ca (thu tu firmware), backpressure=%0d, nghi %0d us", bp, gap_us);

    for (int c = 0; c < NC; c++) begin
      load_words(TRAJ_BASE, c * 512, 352, 0);
      load_words(WM_BASE, c * 2048, 1600, 1);
      rd32(GPIO1, pre);
      n_ar_narrow = 0; n_ar_wide = 0; n_rbeat = 0; n_rerr = 0; n_overlap = 0; n_badaddr = 0; n_proto = 0;
      wr32(GPIO0, 1);
      wr32(GPIO0, 0);
      t0 = $time;
      do begin
        #1_000_000;
        rd32(GPIO1, st);
      end while (st[1] == 1'b0 && ($time - t0) < 64'd100_000_000_000);   // firmware: 100 ms
      t1 = $time;
      rd32(GPIO1, st2);           // firmware doc lai GPIO1 sau khi thay complete
      rd32(GPIO1 + 8, dt);
      begin
        bit ok, fok;
        case (exp_mode[c])
          0: fok = (st2[14:8] == exp_f[c][6:0]);
          1: fok = (st2[14:8] & exp_f[c][6:0]) != 0;
          default: fok = 1;
        endcase
        ok = (pre == 0) && (st[1] == 1) && (st2 == st) && (st2[0] == exp_g[c]) && fok &&
             (n_rerr == 0) && (n_overlap == 0) && (exp_n[c] == "C1_CRC" || n_ar_narrow == 8) && (n_badaddr == 0) && (n_proto == 0);
        $display("[%2d] %-11s pre=0x%08h GPIO1=0x%08h -> %s fault=0x%02h step=%0d obs=%0d | quyet dinh @%0d chu ky%s | AR hep=%0d rong=%0d chong=%0d saidc=%0d rerr=%0d proto=%0d | mong doi %s  %s",
                 c, exp_n[c], pre, st2, st2[0] ? "GRANT" : "VETO ", st2[14:8], dt[15:0], dt[31:16],
                 dec_cyc, seen_s2 ? " (co tang 2)" : "", n_ar_narrow, n_ar_wide, n_overlap, n_badaddr, n_rerr, n_proto,
                 exp_g[c] ? "GRANT" : "VETO ", ok ? "PASS" : "FAIL");
        if (ok) npass++; else nfail++;
      end
      wr32(GPIO0 + 8, 1);
      wr32(GPIO0 + 8, 0);
      #(longint'(gap_us) * 1_000_000);
    end
    $display("=== KET QUA REPLAY: PASS %0d / FAIL %0d / %0d ca", npass, nfail, NC);
    $finish;
  end
endmodule
