// =============================================================================
// planning_top_bd_ref.v
// Pure-Verilog shim for Vivado Block Design module reference.
//
// Vivado 2023.2 restriction: BD module-reference top file must be type Verilog
// (.v), not SystemVerilog (.sv). This shim carries the X_INTERFACE attributes
// so BD SmartConnect auto-wires AXI interfaces, then instantiates
// planning_top_bd_wrapper (SystemVerilog) which contains the actual logic.
//
// fp32_t  = logic[31:0] (32 bits)
// NUM_WAYPOINTS = 4 → waypoint buses are 4×32 = 128 bits
// =============================================================================

`timescale 1ns/1ps

module planning_top_bd_ref (
  // ── Clocks & resets ────────────────────────────────────────────────────────
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, ASSOCIATED_BUSIF S_AXIL:M_AXI" *)
  input  wire        clk,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire        rst_n,

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 hmao_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET hmao_rst_n" *)
  input  wire        hmao_clk,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 hmao_rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire        hmao_rst_n,

  // ── AXI-Lite slave (PS → PL) ───────────────────────────────────────────────
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 12, DATA_WIDTH 32, READ_WRITE_MODE READ_WRITE" *)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWADDR" *)
  input  wire [11:0] s_axil_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWVALID" *)
  input  wire        s_axil_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL AWREADY" *)
  output wire        s_axil_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WDATA" *)
  input  wire [31:0] s_axil_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WSTRB" *)
  input  wire  [3:0] s_axil_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WVALID" *)
  input  wire        s_axil_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL WREADY" *)
  output wire        s_axil_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BRESP" *)
  output wire  [1:0] s_axil_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BVALID" *)
  output wire        s_axil_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL BREADY" *)
  input  wire        s_axil_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARADDR" *)
  input  wire [11:0] s_axil_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARVALID" *)
  input  wire        s_axil_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL ARREADY" *)
  output wire        s_axil_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RDATA" *)
  output wire [31:0] s_axil_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RRESP" *)
  output wire  [1:0] s_axil_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RVALID" *)
  output wire        s_axil_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXIL RREADY" *)
  input  wire        s_axil_rready,

  // ── AXI4 master (PL DMA → PS HP0) ─────────────────────────────────────────
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, ADDR_WIDTH 32, DATA_WIDTH 128, MAX_BURST_LENGTH 256, NUM_READ_OUTSTANDING 4, NUM_WRITE_OUTSTANDING 1, SUPPORTS_NARROW_BURST 0, READ_WRITE_MODE READ_ONLY" *)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
  output wire  [5:0] m_axi_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
  output wire [31:0] m_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
  output wire  [7:0] m_axi_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
  output wire  [2:0] m_axi_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
  output wire  [1:0] m_axi_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
  output wire  [1:0] m_axi_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
  output wire  [3:0] m_axi_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
  output wire  [2:0] m_axi_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
  output wire  [3:0] m_axi_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
  output wire        m_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
  input  wire        m_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
  input  wire  [5:0] m_axi_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
  input  wire [127:0] m_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
  input  wire  [1:0] m_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
  input  wire        m_axi_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
  input  wire        m_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
  output wire        m_axi_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWID" *)
  output wire  [5:0] m_axi_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
  output wire [31:0] m_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
  output wire  [7:0] m_axi_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
  output wire  [2:0] m_axi_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
  output wire  [1:0] m_axi_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
  output wire  [1:0] m_axi_awlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
  output wire  [3:0] m_axi_awcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
  output wire  [2:0] m_axi_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
  output wire  [3:0] m_axi_awqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
  output wire        m_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
  input  wire        m_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WID" *)
  output wire  [5:0] m_axi_wid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
  output wire [127:0] m_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
  output wire [15:0]  m_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
  output wire        m_axi_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
  output wire        m_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
  input  wire        m_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BID" *)
  input  wire  [5:0] m_axi_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
  input  wire  [1:0] m_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
  input  wire        m_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
  output wire        m_axi_bready,

  // ── HMAO outputs (not BD-connected; routed to HMAO system externally) ──────
  // waypoint_x/y: 4 × 32-bit fp32 values packed into 128-bit buses
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

  planning_top_bd_wrapper u_wrap (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .hmao_clk              (hmao_clk),
    .hmao_rst_n            (hmao_rst_n),
    // AXI-Lite
    .s_axil_awaddr         (s_axil_awaddr),
    .s_axil_awvalid        (s_axil_awvalid),
    .s_axil_awready        (s_axil_awready),
    .s_axil_wdata          (s_axil_wdata),
    .s_axil_wstrb          (s_axil_wstrb),
    .s_axil_wvalid         (s_axil_wvalid),
    .s_axil_wready         (s_axil_wready),
    .s_axil_bresp          (s_axil_bresp),
    .s_axil_bvalid         (s_axil_bvalid),
    .s_axil_bready         (s_axil_bready),
    .s_axil_araddr         (s_axil_araddr),
    .s_axil_arvalid        (s_axil_arvalid),
    .s_axil_arready        (s_axil_arready),
    .s_axil_rdata          (s_axil_rdata),
    .s_axil_rresp          (s_axil_rresp),
    .s_axil_rvalid         (s_axil_rvalid),
    .s_axil_rready         (s_axil_rready),
    // AXI4 DMA master
    .m_axi_arid            (m_axi_arid),
    .m_axi_araddr          (m_axi_araddr),
    .m_axi_arlen           (m_axi_arlen),
    .m_axi_arsize          (m_axi_arsize),
    .m_axi_arburst         (m_axi_arburst),
    .m_axi_arlock          (m_axi_arlock),
    .m_axi_arcache         (m_axi_arcache),
    .m_axi_arprot          (m_axi_arprot),
    .m_axi_arqos           (m_axi_arqos),
    .m_axi_arvalid         (m_axi_arvalid),
    .m_axi_arready         (m_axi_arready),
    .m_axi_rid             (m_axi_rid),
    .m_axi_rdata           (m_axi_rdata),
    .m_axi_rresp           (m_axi_rresp),
    .m_axi_rlast           (m_axi_rlast),
    .m_axi_rvalid          (m_axi_rvalid),
    .m_axi_rready          (m_axi_rready),
    .m_axi_awid            (m_axi_awid),
    .m_axi_awaddr          (m_axi_awaddr),
    .m_axi_awlen           (m_axi_awlen),
    .m_axi_awsize          (m_axi_awsize),
    .m_axi_awburst         (m_axi_awburst),
    .m_axi_awlock          (m_axi_awlock),
    .m_axi_awcache         (m_axi_awcache),
    .m_axi_awprot          (m_axi_awprot),
    .m_axi_awqos           (m_axi_awqos),
    .m_axi_awvalid         (m_axi_awvalid),
    .m_axi_awready         (m_axi_awready),
    .m_axi_wid             (m_axi_wid),
    .m_axi_wdata           (m_axi_wdata),
    .m_axi_wstrb           (m_axi_wstrb),
    .m_axi_wlast           (m_axi_wlast),
    .m_axi_wvalid          (m_axi_wvalid),
    .m_axi_wready          (m_axi_wready),
    .m_axi_bid             (m_axi_bid),
    .m_axi_bresp           (m_axi_bresp),
    .m_axi_bvalid          (m_axi_bvalid),
    .m_axi_bready          (m_axi_bready),
    // HMAO (4×32=128-bit packed buses connect to SV unpacked arrays)
    .waypoint_x            (waypoint_x),
    .waypoint_y            (waypoint_y),
    .waypoints_valid       (waypoints_valid),
    .waypoints_sanity_pass (waypoints_sanity_pass),
    // IRQ
    .done_irq              (done_irq),
    .wload_timeout_err     (wload_timeout_err)
  );

endmodule
