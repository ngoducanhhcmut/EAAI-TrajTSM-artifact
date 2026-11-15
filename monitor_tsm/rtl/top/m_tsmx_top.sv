/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Structural top, synchronized reset, transport and all accepted block composition.
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_top #(
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_G = 32'd8,
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_P = 32'd8,
  // Parameter Description: direct semantic port selection.
  // Parameter values: 0,1; default 0.
  // Parameter unit: count
  parameter logic [31:0] PARA_DIRECT = 32'd0
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [44672:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [37:0] o_rsp_data,
  input wire [31:0] i_time_us,
  input wire i_ack_valid,
  input wire [31:0] i_ack_seq,
  output logic o_brake,
  output logic o_heartbeat,
  input wire [15:0] i_axi_awaddr,
  input wire [2:0] i_axi_awprot,
  input wire i_axi_awvalid,
  input wire [31:0] i_axi_wdata,
  input wire [3:0] i_axi_wstrb,
  input wire i_axi_wvalid,
  input wire i_axi_bready,
  input wire [15:0] i_axi_araddr,
  input wire [2:0] i_axi_arprot,
  input wire i_axi_arvalid,
  input wire i_axi_rready,
  output logic o_axi_awready,
  output logic o_axi_wready,
  output logic o_axi_bvalid,
  output logic [1:0] o_axi_bresp,
  output logic o_axi_arready,
  output logic o_axi_rvalid,
  output logic [1:0] o_axi_rresp,
  output logic [31:0] o_axi_rdata,
  output logic o_int_irq,
  input wire [9:0] i_log_idx,
  input wire i_log_valid,
  input wire i_log_ready,
  output logic o_log_ready,
  output logic [1055:0] o_log_data,
  output logic o_log_valid,
  input wire i_rx_valid,
  input wire [31:0] i_rx_data,
  input wire [3:0] i_rx_keep,
  input wire i_rx_last,
  output logic o_rx_ready,
  output logic o_tx_valid,
  output logic [31:0] o_tx_data,
  output logic [3:0] o_tx_keep,
  output logic o_tx_last,
  input wire i_tx_ready
);
  logic w_rst_n;
  logic w_req_valid,w_req_ready,w_cmd_valid,w_cmd_ready;
  logic [44672:0] w_req_data;
  logic [1896:0] w_cmd_data;
  logic [7:0] w_parse_reason;
  // Reset release is synchronized once for the entire core domain.
  m_tsmx_rst u_tsmx_rst (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .o_rst_n_core(w_rst_n)
  );
  // Engine owns all persistent semantic state and all accepted leaf transactions.
  m_tsmx_engine #(.PARA_G(PARA_G),.PARA_P(PARA_P),.PARA_DIRECT(PARA_DIRECT)) u_tsmx_engine (
    .i_req_valid(w_req_valid),
    .i_req_data(w_req_data),
    .i_rsp_ready(i_rsp_ready),
    .o_req_ready(w_req_ready),
    .o_rsp_valid(o_rsp_valid),
    .o_rsp_data(o_rsp_data),
    .i_time_us(i_time_us),
    .i_ack_valid(i_ack_valid),
    .i_ack_seq(i_ack_seq),
    .o_brake(o_brake),
    .o_heartbeat(o_heartbeat),
    .i_axi_awaddr(i_axi_awaddr),
    .i_axi_awprot(i_axi_awprot),
    .i_axi_awvalid(i_axi_awvalid),
    .i_axi_wdata(i_axi_wdata),
    .i_axi_wstrb(i_axi_wstrb),
    .i_axi_wvalid(i_axi_wvalid),
    .i_axi_bready(i_axi_bready),
    .i_axi_araddr(i_axi_araddr),
    .i_axi_arprot(i_axi_arprot),
    .i_axi_arvalid(i_axi_arvalid),
    .i_axi_rready(i_axi_rready),
    .o_axi_awready(o_axi_awready),
    .o_axi_wready(o_axi_wready),
    .o_axi_bvalid(o_axi_bvalid),
    .o_axi_bresp(o_axi_bresp),
    .o_axi_arready(o_axi_arready),
    .o_axi_rvalid(o_axi_rvalid),
    .o_axi_rresp(o_axi_rresp),
    .o_axi_rdata(o_axi_rdata),
    .o_int_irq(o_int_irq),
    .i_log_idx(i_log_idx),
    .i_log_valid(i_log_valid),
    .i_log_ready(i_log_ready),
    .o_log_ready(o_log_ready),
    .o_log_data(o_log_data),
    .o_log_valid(o_log_valid),
    .i_clk_core(i_clk_core),
    .i_rst_n_core(w_rst_n),
    .i_parse_reason(w_parse_reason),
    .o_cmd_valid(w_cmd_valid),
    .o_cmd_data(w_cmd_data),
    .i_cmd_ready(w_cmd_ready)
  );
  // Parameter selection changes only the request source, never decision arithmetic.
  m_tsmx_io #(.PARA_DIRECT(PARA_DIRECT)) u_tsmx_io (
    .i_rx_valid(i_rx_valid),
    .i_rx_data(i_rx_data),
    .i_rx_keep(i_rx_keep),
    .i_rx_last(i_rx_last),
    .o_rx_ready(o_rx_ready),
    .o_tx_valid(o_tx_valid),
    .o_tx_data(o_tx_data),
    .o_tx_keep(o_tx_keep),
    .o_tx_last(o_tx_last),
    .i_tx_ready(i_tx_ready),
    .i_clk_core(i_clk_core),
    .i_rst_n_core(w_rst_n),
    .i_req_valid(i_req_valid),
    .i_req_data(i_req_data),
    .o_req_ready(o_req_ready),
    .o_core_valid(w_req_valid),
    .o_core_data(w_req_data),
    .o_core_reason(w_parse_reason),
    .i_time_us(i_time_us),
    .i_core_ready(w_req_ready),
    .i_cmd_valid(w_cmd_valid),
    .i_cmd_data(w_cmd_data),
    .o_cmd_ready(w_cmd_ready)
  );
endmodule
`default_nettype wire
