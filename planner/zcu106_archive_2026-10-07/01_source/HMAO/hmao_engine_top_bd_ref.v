// =============================================================================
// hmao_engine_top_bd_ref.v
// Pure-Verilog shim for Vivado Block Design module reference.
//
// Vivado 2023.2 restriction: BD module-reference top file must be .v, not .sv.
// This shim carries X_INTERFACE attributes so BD auto-wires M_AXI to a
// SmartConnect, then instantiates hmao_engine_top_bd_wrapper (SystemVerilog).
// =============================================================================
`timescale 1ns/1ps

module hmao_engine_top_bd_ref (
  // ── Clock / Reset ──────────────────────────────────────────────────────────
  // NOTE 2026-10-04: FREQ_HZ 250000000 -> 187500000 (PL2 187,5 MHz: TSM 250 MHz vi pham -1,05 ns
  //   sau route; do tre co dinh 1,5M chu ky = 8,0 ms < han 10 ms). VERIFICATION_HISTORY AK.7.
  // NOTE 2026-08-04: FREQ_HZ dropped from 300000000 to 250000000 to match the
  // real clk_pl_2 PS PLL configuration after relaxing HMAO's clock to buy
  // back timing margin (see scripts/fix_hmao_gpio_cdc.tcl / rtl/src/cdc/
  // hmao_gpio_cdc_bridge.sv for the full story). No RTL functional change
  // needed elsewhere: hmao_pkg.sv's timing budgets are all cycle-counted, not
  // wall-clock-timed.
  (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET rst_n, FREQ_HZ 187500000" *)
  input  wire         clk,
  (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire         rst_n,
  (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 wdt_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 250000000" *)   // wdt_clk = PL3, giu 250 MHz
  input  wire         wdt_clk,

  // ── Control ────────────────────────────────────────────────────────────────
  input  wire         hmao_start,
  input  wire         irq_clear,

  // ── AXI4 Read-Only Master (256-bit) ───────────────────────────────────────
  (* X_INTERFACE_INFO      = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, DATA_WIDTH 256, ADDR_WIDTH 32, ID_WIDTH 4, \
     HAS_BURST 1, HAS_LOCK 0, HAS_CACHE 0, HAS_PROT 0, HAS_QOS 0, HAS_REGION 0, \
     HAS_SIZE 1, READ_WRITE_MODE READ_ONLY, MAX_BURST_LENGTH 64" *)
  output wire [3:0]   m_axi_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
  output wire [31:0]  m_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
  output wire [7:0]   m_axi_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
  output wire [2:0]   m_axi_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
  output wire [1:0]   m_axi_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
  output wire         m_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
  input  wire         m_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
  input  wire [3:0]   m_axi_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
  input  wire [255:0] m_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
  input  wire [1:0]   m_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
  input  wire         m_axi_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
  input  wire         m_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
  output wire         m_axi_rready,

  // ── Outputs ────────────────────────────────────────────────────────────────
  output wire         hmao_complete,
  output wire         hmao_decision_out,
  output wire [63:0]  hmao_violation_out,
  output wire [31:0]  hmao_status_out,
  output wire [31:0]  hmao_latency_out,
  output wire [15:0]  lateral_margin_out,
  output wire [15:0]  long_margin_out,
  output wire [15:0]  time_margin_out,
  output wire [6:0]   fault_bits_out,
  output wire         fault_valid_out
);

  hmao_engine_top_bd_wrapper u_hmao_bd (
    .clk                (clk),
    .rst_n              (rst_n),
    .wdt_clk            (wdt_clk),
    .hmao_start         (hmao_start),
    .irq_clear          (irq_clear),
    .m_axi_arid         (m_axi_arid),
    .m_axi_araddr       (m_axi_araddr),
    .m_axi_arlen        (m_axi_arlen),
    .m_axi_arsize       (m_axi_arsize),
    .m_axi_arburst      (m_axi_arburst),
    .m_axi_arvalid      (m_axi_arvalid),
    .m_axi_arready      (m_axi_arready),
    .m_axi_rid          (m_axi_rid),
    .m_axi_rdata        (m_axi_rdata),
    .m_axi_rresp        (m_axi_rresp),
    .m_axi_rlast        (m_axi_rlast),
    .m_axi_rvalid       (m_axi_rvalid),
    .m_axi_rready       (m_axi_rready),
    .hmao_complete      (hmao_complete),
    .hmao_decision_out  (hmao_decision_out),
    .hmao_violation_out (hmao_violation_out),
    .hmao_status_out    (hmao_status_out),
    .hmao_latency_out   (hmao_latency_out),
    .lateral_margin_out (lateral_margin_out),
    .long_margin_out    (long_margin_out),
    .time_margin_out    (time_margin_out),
    .fault_bits_out     (fault_bits_out),
    .fault_valid_out    (fault_valid_out)
  );

endmodule
