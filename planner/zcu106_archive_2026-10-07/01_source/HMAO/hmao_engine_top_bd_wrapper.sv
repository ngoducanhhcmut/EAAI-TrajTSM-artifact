// =============================================================================
// hmao_engine_top_bd_wrapper.sv
// Vivado Block Design wrapper for hmao_engine_top (400 MHz ASIL-D safety engine).
//
// Flattens the internal axi4_ro_if and hmao_pipe_if SV interfaces into plain
// logic ports with X_INTERFACE_INFO attributes so the IP Integrator can
// auto-connect M_AXI to a SmartConnect.
//
// Sensor quality inputs are tied to maximum quality (0xFF / 0x00 for severity)
// for initial board bring-up.  The smpu_decerr sideband is grounded (no SMPU
// on FPGA prototype).  Debug outputs are left open.
// =============================================================================
`timescale 1ns/1ps

import hmao_pkg::*;

module hmao_engine_top_bd_wrapper (
  // ── Clock / Reset ─────────────────────────────────────────────────────────
  (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET rst_n, FREQ_HZ 300000000" *)
  input  logic        clk,

  (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  logic        rst_n,

  // Independent watchdog clock (async to clk, ASIL-D ring-osc analog)
  (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 wdt_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 250000000" *)   // wdt_clk = PL3, giu 250 MHz
  input  logic        wdt_clk,

  // ── Control ───────────────────────────────────────────────────────────────
  input  logic        hmao_start,    // Pulse from PS GPIO
  input  logic        irq_clear,     // Written by PS after reading decision

  // ── AXI4 Read-Only Master (256-bit) — trajectory + world model fetch ──────
  (* X_INTERFACE_INFO      = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
  (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, DATA_WIDTH 256, ADDR_WIDTH 32, ID_WIDTH 4, \
     HAS_BURST 1, HAS_LOCK 0, HAS_CACHE 0, HAS_PROT 0, HAS_QOS 0, HAS_REGION 0, \
     HAS_SIZE 1, READ_WRITE_MODE READ_ONLY, MAX_BURST_LENGTH 64" *)
  output logic [3:0]   m_axi_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
  output logic [31:0]  m_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
  output logic [7:0]   m_axi_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
  output logic [2:0]   m_axi_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
  output logic [1:0]   m_axi_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
  output logic         m_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
  input  logic         m_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
  input  logic [3:0]   m_axi_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
  input  logic [255:0] m_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
  input  logic [1:0]   m_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
  input  logic         m_axi_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
  input  logic         m_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
  output logic         m_axi_rready,

  // ── Outputs ───────────────────────────────────────────────────────────────
  output logic         hmao_complete,
  output logic         hmao_decision_out,
  output logic [63:0]  hmao_violation_out,
  output logic [31:0]  hmao_status_out,
  output logic [31:0]  hmao_latency_out,
  output logic [15:0]  lateral_margin_out,
  output logic [15:0]  long_margin_out,
  output logic [15:0]  time_margin_out,
  output logic [6:0]   fault_bits_out,    // hmao_fault_t packed [6:0]
  output logic         fault_valid_out
);

  // ── Internal interfaces ────────────────────────────────────────────────────
  axi4_ro_if #(.ADDR_W(32), .DATA_W(256), .ID_W(4)) u_axi_if (
    .aclk(clk), .aresetn(rst_n)
  );

  hmao_pipe_if u_pipe (.clk(clk), .rst_n(rst_n));

  // ── Bridge: flat output ports ← axi4_ro_if (HMAO drives these) ────────────
  assign m_axi_arid    = u_axi_if.arid;
  assign m_axi_araddr  = u_axi_if.araddr;
  assign m_axi_arlen   = u_axi_if.arlen;
  assign m_axi_arsize  = u_axi_if.arsize;
  assign m_axi_arburst = u_axi_if.arburst;
  assign m_axi_arvalid = u_axi_if.arvalid;
  assign m_axi_rready  = u_axi_if.rready;

  // Bridge: axi4_ro_if ← flat input ports (SmartConnect drives these) ────────
  assign u_axi_if.arready    = m_axi_arready;
  assign u_axi_if.rid        = m_axi_rid;
  assign u_axi_if.rdata      = m_axi_rdata;
  assign u_axi_if.rresp      = m_axi_rresp;
  assign u_axi_if.rlast      = m_axi_rlast;
  assign u_axi_if.rvalid     = m_axi_rvalid;
  // No SMPU on FPGA prototype — tie sideband to 0
  assign u_axi_if.smpu_decerr = 1'b0;

  // ── fault_out (packed struct) → flat bits ─────────────────────────────────
  hmao_fault_t fault_int;
  assign fault_bits_out = fault_int;

  // ── hmao_engine_top ───────────────────────────────────────────────────────
  hmao_engine_top u_hmao (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .hmao_start               (hmao_start),
    // Sensor quality: tie to "good" for initial bring-up
    .gps_quality              (8'hFF),
    .camera_quality           (8'hFF),
    .road_friction            (8'hFF),
    .actuator_health          (8'hFF),
    .weather_severity         (8'h00),
    .axi_ro                   (u_axi_if.master),
    .pipe                     (u_pipe),
    .wdt_clk                  (wdt_clk),
    .hmao_complete            (hmao_complete),
    .hmao_decision_out        (hmao_decision_out),
    .hmao_violation_out       (hmao_violation_out),
    .hmao_status_out          (hmao_status_out),
    .hmao_latency_out         (hmao_latency_out),
    .lateral_margin_out       (lateral_margin_out),
    .long_margin_out          (long_margin_out),
    .time_margin_out          (time_margin_out),
    .irq_clear                (irq_clear),
    .debug_start_preproc      (),
    .debug_fsm_state_encoded  (),
    .debug_hmao_start_received(),
    .debug_preproc_valid      (),
    .debug_preproc_error      (),
    .fault_out                (fault_int),
    .fault_valid_out          (fault_valid_out)
  );

endmodule
