// =============================================================================
// planning_top_bd_wrapper.sv
// Vivado Block Design wrapper for planning_top.
//
// Bundles flat AXI-Lite and AXI4 ports into Xilinx interface groups using
// (* X_INTERFACE_INFO *) attributes so that Vivado BD SmartConnect can
// auto-connect them to the Zynq UltraScale+ PS.
//
// AXI-Lite slave:  S_AXIL  — connects to PS M_AXI_HPM0_FPD
// AXI4 master:     M_AXI   — connects to PS S_AXI_HP0_FPD (weight DMA)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module planning_top_bd_wrapper (
  // ── Clocks & resets ────────────────────────────────────────────────────────
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, ASSOCIATED_BUSIF S_AXIL:M_AXI" *)
  input  wire         clk,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire         rst_n,

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 hmao_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 50000000, ASSOCIATED_RESET hmao_rst_n" *)
  input  wire         hmao_clk,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 hmao_rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire         hmao_rst_n,

  // ── AXI-Lite slave (PS → PL) — 12-bit addr, 32-bit data ──────────────────
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 12, DATA_WIDTH 32, READ_WRITE_MODE READ_WRITE" *)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWADDR" *)
  input  wire [11:0]  s_axil_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWVALID" *)
  input  wire         s_axil_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWREADY" *)
  output wire         s_axil_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WDATA" *)
  input  wire [31:0]  s_axil_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WSTRB" *)
  input  wire [3:0]   s_axil_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WVALID" *)
  input  wire         s_axil_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WREADY" *)
  output wire         s_axil_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BRESP" *)
  output wire [1:0]   s_axil_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BVALID" *)
  output wire         s_axil_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BREADY" *)
  input  wire         s_axil_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARADDR" *)
  input  wire [11:0]  s_axil_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARVALID" *)
  input  wire         s_axil_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARREADY" *)
  output wire         s_axil_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RDATA" *)
  output wire [31:0]  s_axil_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RRESP" *)
  output wire [1:0]   s_axil_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RVALID" *)
  output wire         s_axil_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RREADY" *)
  input  wire         s_axil_rready,

  // ── AXI4 master (PL DMA → PS HP0) — 128-bit read-only ────────────────────
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, ADDR_WIDTH 32, DATA_WIDTH 128, MAX_BURST_LENGTH 256, NUM_READ_OUTSTANDING 4, NUM_WRITE_OUTSTANDING 1, SUPPORTS_NARROW_BURST 0, READ_WRITE_MODE READ_ONLY" *)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
  output wire [5:0]   m_axi_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
  output wire [31:0]  m_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
  output wire [7:0]   m_axi_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
  output wire [2:0]   m_axi_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
  output wire [1:0]   m_axi_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
  output wire [1:0]   m_axi_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
  output wire [3:0]   m_axi_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
  output wire [2:0]   m_axi_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
  output wire [3:0]   m_axi_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
  output wire         m_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
  input  wire         m_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
  input  wire [5:0]   m_axi_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
  input  wire [127:0] m_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
  input  wire [1:0]   m_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
  input  wire         m_axi_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
  input  wire         m_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
  output wire         m_axi_rready,

  // ── AXI4 master write channel tie-offs (DMA is read-only) ────────────────
  // These ports exist only to complete the AXI4 interface for Vivado BD.
  // SmartConnect will see them as permanently idle (AWVALID=0, WVALID=0).
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWID" *)
  output wire [5:0]   m_axi_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
  output wire [31:0]  m_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
  output wire [7:0]   m_axi_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
  output wire [2:0]   m_axi_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
  output wire [1:0]   m_axi_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
  output wire [1:0]   m_axi_awlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
  output wire [3:0]   m_axi_awcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
  output wire [2:0]   m_axi_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
  output wire [3:0]   m_axi_awqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
  output wire         m_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
  input  wire         m_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WID" *)
  output wire [5:0]   m_axi_wid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
  output wire [127:0] m_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
  output wire [15:0]  m_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
  output wire         m_axi_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
  output wire         m_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
  input  wire         m_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BID" *)
  input  wire [5:0]   m_axi_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
  input  wire [1:0]   m_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
  input  wire         m_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
  output wire         m_axi_bready,

  // ── HMAO outputs ──────────────────────────────────────────────────────────
  output wire [127:0] waypoint_x,
  output wire [127:0] waypoint_y,
  output wire         waypoints_valid,
  output wire         waypoints_sanity_pass,

  // ── Interrupt to PS ────────────────────────────────────────────────────────
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 done_irq INTERRUPT" *)
  (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH, PortWidth 1" *)
  output wire         done_irq,
  output wire         wload_timeout_err
);

  wire [31:0] waypoint_x_arr [3:0];
  wire [31:0] waypoint_y_arr [3:0];

  assign waypoint_x = {waypoint_x_arr[3], waypoint_x_arr[2], waypoint_x_arr[1], waypoint_x_arr[0]};
  assign waypoint_y = {waypoint_y_arr[3], waypoint_y_arr[2], waypoint_y_arr[1], waypoint_y_arr[0]};

  planning_top u_planning_top (
    .clk              (clk),
    .rst_n            (rst_n),
    // AXI-Lite
    .axil_awaddr      (s_axil_awaddr),
    .axil_awvalid     (s_axil_awvalid),
    .axil_awready     (s_axil_awready),
    .axil_wdata       (s_axil_wdata),
    .axil_wstrb       (s_axil_wstrb),
    .axil_wvalid      (s_axil_wvalid),
    .axil_wready      (s_axil_wready),
    .axil_bresp       (s_axil_bresp),
    .axil_bvalid      (s_axil_bvalid),
    .axil_bready      (s_axil_bready),
    .axil_araddr      (s_axil_araddr),
    .axil_arvalid     (s_axil_arvalid),
    .axil_arready     (s_axil_arready),
    .axil_rdata       (s_axil_rdata),
    .axil_rresp       (s_axil_rresp),
    .axil_rvalid      (s_axil_rvalid),
    .axil_rready      (s_axil_rready),
    // AXI4 DMA master
    .m_axi_arid       (m_axi_arid),
    .m_axi_araddr     (m_axi_araddr),
    .m_axi_arlen      (m_axi_arlen),
    .m_axi_arsize     (m_axi_arsize),
    .m_axi_arburst    (m_axi_arburst),
    .m_axi_arlock     (m_axi_arlock),
    .m_axi_arcache    (m_axi_arcache),
    .m_axi_arprot     (m_axi_arprot),
    .m_axi_arqos      (m_axi_arqos),
    .m_axi_arvalid    (m_axi_arvalid),
    .m_axi_arready    (m_axi_arready),
    .m_axi_rid        (m_axi_rid),
    .m_axi_rdata      (m_axi_rdata),
    .m_axi_rresp      (m_axi_rresp),
    .m_axi_rlast      (m_axi_rlast),
    .m_axi_rvalid     (m_axi_rvalid),
    .m_axi_rready     (m_axi_rready),
    // HMAO
    .waypoint_x           (waypoint_x_arr),
    .waypoint_y           (waypoint_y_arr),
    .waypoints_valid      (waypoints_valid),
    .waypoints_sanity_pass(waypoints_sanity_pass),
    .hmao_clk             (hmao_clk),
    .hmao_rst_n           (hmao_rst_n),
    // IRQ
    .done_irq         (done_irq),
    .wload_timeout_err(wload_timeout_err)
  );

  // ── Write-channel tie-offs (DMA read-only — write channels never asserted) ─
  assign m_axi_awid    = '0;
  assign m_axi_awaddr  = '0;
  assign m_axi_awlen   = '0;
  assign m_axi_awsize  = 3'b100;   // 16 bytes (128-bit) — harmless default
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = '0;
  assign m_axi_awcache = '0;
  assign m_axi_awprot  = '0;
  assign m_axi_awqos   = '0;
  assign m_axi_awvalid = 1'b0;     // never initiate a write
  assign m_axi_wid     = '0;
  assign m_axi_wdata   = '0;
  assign m_axi_wstrb   = '0;
  assign m_axi_wlast   = 1'b0;
  assign m_axi_wvalid  = 1'b0;
  assign m_axi_bready  = 1'b1;     // accept (ignore) any stray B responses

endmodule

`default_nettype wire
