// =============================================================================
// tb_tsm_sysbd.sv — mo phong TSM muc he thong qua IP that cua BD (xem sim_sysbd/build_bd.tcl).
//
// Khac cac testbench cu: du lieu quy dao/world model nam trong AXI VIP slave 128 bit (dong vai
// DDR + cong HP1), di qua SmartConnect 256->128 that, nen lan du lieu cua burst hep la do IP
// Xilinx dat theo dung chuan AXI, khong phai do testbench tu dat. "R5" la AXI VIP master ghi/doc
// axi_gpio_0/axi_gpio_1 dung dia chi va trinh tu cua sw/board/tsm_onecase.c + tsm_demo.c.
//
//   `define TSM_NETLIST  -> dung netlist tong hop cua TSM (system_hmao_engine_0_2, dung ban trong bitstream)
//   caselist.txt (tuy chon, trong thu muc chay): dong 1 = so ms ranh truoc lan chay thu 2 (kiem tra
//   watchdog khi ranh), cac dong sau = chi so ca can chay. Khong co file -> 16 ca, ranh 10 ms.
// =============================================================================
`timescale 1ps/1ps
import axi_vip_pkg::*;
import tsm_ifc_axi_vip_mem_0_pkg::*;
import tsm_ifc_axi_vip_cpu_0_pkg::*;

module tb_tsm_sysbd;
  localparam int NC = 16;
  localparam longint TRAJ_BASE = 64'h7030_0000;
  localparam longint WM_BASE   = 64'h7040_0000;
  localparam bit [31:0] GPIO0 = 32'hA001_0000, GPIO1 = 32'hA002_0000;

  // pl_clk0 100 MHz (psu_init ZCU106), pl_clk2 187,5 MHz, pl_clk3 250 MHz
  logic clk0 = 0, clk2 = 0, clk3 = 0, ext_rst_n = 0;
  always #5000 clk0 = ~clk0;
  always #2667 clk2 = ~clk2;
  always #2000 clk3 = ~clk3;

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

`ifdef TSM_NETLIST
  system_hmao_engine_0_2 u_tsm (
`else
  hmao_engine_top_bd_ref u_tsm (
`endif
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

  // ---- theo doi bus doc cua TSM: dem burst hep va beat ----
  int n_ar_narrow, n_ar_wide, n_rbeat, n_rerr;
  always @(posedge clk2) begin
    if (arvalid && arready) begin
      if (arsize == 3'd2) n_ar_narrow++; else n_ar_wide++;
    end
    if (arvalid && arready && n_ar_narrow + n_ar_wide < 24)
      $display("    AR #%0d t=%0t addr=0x%08h len=%0d size=%0d (beat da nhan=%0d)",
               n_ar_narrow + n_ar_wide, $time, araddr, arlen, arsize, n_rbeat);
    if (rvalid && rready && rlast)
      $display("    RLAST t=%0t sau %0d beat", $time, n_rbeat + 1);
    if (rvalid && rready) begin
      n_rbeat++;
      if (rresp != 2'b00) n_rerr++;
    end
  end

  tsm_ifc_axi_vip_mem_0_slv_mem_t mem;
  tsm_ifc_axi_vip_cpu_0_mst_t     cpu;

  logic [31:0] traj_m [0:NC*512-1];
  logic [31:0] wm_m   [0:NC*2048-1];
  int    exp_g [NC];
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

  // ghi n word 32 bit vao bo nho VIP (128 bit/dong) tai dia chi base
  task automatic load_words(input longint base, input int first, input int n, input bit is_wm);
    bit [127:0] line;
    for (int i = 0; i < n; i += 4) begin
      for (int k = 0; k < 4; k++)
        line[32*k +: 32] = is_wm ? wm_m[first + i + k] : traj_m[first + i + k];
      mem.mem_model.backdoor_memory_write(base + 4 * i, line, '1);
    end
  endtask

  int npass, nfail, ncase, idle_ms;
  int clist [NC];
  initial begin
    int fd, g, f; string nm;
    bit [31:0] st, dt, pre;
    longint t0, t1;
    ncase = NC; idle_ms = 10;
    for (int i = 0; i < NC; i++) clist[i] = i;
    fd = $fopen("caselist.txt", "r");
    if (fd != 0) begin
      int v;
      void'($fscanf(fd, "%d", idle_ms));
      ncase = 0;
      while ($fscanf(fd, "%d", v) == 1) begin clist[ncase] = v; ncase++; end
      $fclose(fd);
    end
    $readmemh("traj.mem", traj_m);
    $readmemh("wm.mem", wm_m);
    fd = $fopen("expect.txt", "r");
    for (int i = 0; i < NC; i++) begin
      void'($fscanf(fd, "%d %h %s\n", g, f, nm));
      exp_g[i] = g; exp_f[i] = f; exp_n[i] = nm;
    end
    $fclose(fd);

    mem = new("mem", tb_tsm_sysbd.u_bd.tsm_ifc_i.axi_vip_mem.inst.IF);
    cpu = new("cpu", tb_tsm_sysbd.u_bd.tsm_ifc_i.axi_vip_cpu.inst.IF);
    mem.start_slave();
    cpu.start_master();

    repeat (20) @(posedge clk0);
    ext_rst_n = 1;
    wait (rst0_n === 1'b1 && rst2_n === 1'b1);
    repeat (50) @(posedge clk0);
`ifdef TSM_NETLIST
    $display("=== TSM SYSBD: NETLIST tong hop (system_hmao_engine_0_2), %0d ca", ncase);
`else
    $display("=== TSM SYSBD: RTL, %0d ca", ncase);
`endif

    for (int k = 0; k < ncase; k++) begin
      automatic int c = clist[k];
      // nhu firmware: chep quy dao + world model vao "DDR"
      load_words(TRAJ_BASE, c * 512, 352, 0);
      load_words(WM_BASE, c * 2048, 1600, 1);
      if (k == 1 && idle_ms > 0) begin
        $display("  ... ranh %0d ms truoc lan chay 2 (kiem tra watchdog khong dem khi ranh)", idle_ms);
        #(longint'(idle_ms) * 1_000_000_000);
      end
      rd32(GPIO1, pre);
      n_ar_narrow = 0; n_ar_wide = 0; n_rbeat = 0; n_rerr = 0;
      wr32(GPIO0, 1);
      wr32(GPIO0, 0);
      t0 = $time;
      do begin
        #1_000_000;  // poll moi 1 us
        rd32(GPIO1, st);
      end while (st[1] == 1'b0 && ($time - t0) < 64'd20_000_000_000);
      t1 = $time;
      rd32(GPIO1 + 8, dt);
      begin
        bit ok;
        ok = (pre == 0) && (st[1] == 1) && (st[0] == exp_g[c]) &&
             (st[14:8] == exp_f[c][6:0]) && (n_rerr == 0) && (n_ar_narrow == 8);
        // Fault-free cases must also keep the board's 8 ms completion time.
        // Allow clock rounding (5.334 ns) and the CPU's 1 us polling latency.
        if (exp_f[c] == 0)
          ok &= ((t1 - t0) >= 64'd7_999_000_000 &&
                 (t1 - t0) <= 64'd8_010_000_000);
        $display("[%2d] %-11s truoc start GPIO1=0x%08h | GPIO1=0x%08h -> %s fault=0x%02h step=%0d obs=%0d | %0.3f ms | AR hep=%0d rong=%0d beat=%0d rerr=%0d | mong doi %s fault=0x%02h  %s",
                 c, exp_n[c], pre, st, st[0] ? "GRANT" : "VETO ", st[14:8], dt[15:0], dt[31:16],
                 real'(t1 - t0) / 1.0e9, n_ar_narrow, n_ar_wide, n_rbeat, n_rerr,
                 exp_g[c] ? "GRANT" : "VETO ", exp_f[c], ok ? "PASS" : "FAIL");
        if (ok) npass++; else nfail++;
      end
      // xoa ngat nhu firmware
      wr32(GPIO0 + 8, 1);
      wr32(GPIO0 + 8, 0);
      #20_000_000;
    end
    $display("=== KET QUA: PASS %0d / FAIL %0d / %0d ca", npass, nfail, ncase);
    $finish;
  end
endmodule
