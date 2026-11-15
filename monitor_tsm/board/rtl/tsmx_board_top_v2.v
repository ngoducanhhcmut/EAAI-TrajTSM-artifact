// Claude 10/11/2026: tsmx_board_top_v2 = tsmx_board_top with tsmx_board_shim_v2 (board time base). Core unchanged.
// Claude 04/11/2026: block-design module reference for the ZCU106 TSM-X board test.
// m_tsmx_top (P=G=2, PARA_DIRECT=0) + tsmx_board_shim. Standard AXI names so IP integrator
// infers s_axi_csr (TSM-X CSR), s_axi_shim (board shim), s_axis_rx and m_axis_tx.
`timescale 1ns/1ps
`default_nettype none
module tsmx_board_top_v2 (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi_csr:s_axi_shim:s_axis_rx:m_axis_tx, ASSOCIATED_RESET resetn" *)
  input  wire        clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire        resetn,
  // TSM-X CSR (AXI4-Lite, 16-bit address)
  input  wire [15:0] s_axi_csr_awaddr,
  input  wire [2:0]  s_axi_csr_awprot,
  input  wire        s_axi_csr_awvalid,
  output wire        s_axi_csr_awready,
  input  wire [31:0] s_axi_csr_wdata,
  input  wire [3:0]  s_axi_csr_wstrb,
  input  wire        s_axi_csr_wvalid,
  output wire        s_axi_csr_wready,
  output wire [1:0]  s_axi_csr_bresp,
  output wire        s_axi_csr_bvalid,
  input  wire        s_axi_csr_bready,
  input  wire [15:0] s_axi_csr_araddr,
  input  wire [2:0]  s_axi_csr_arprot,
  input  wire        s_axi_csr_arvalid,
  output wire        s_axi_csr_arready,
  output wire [31:0] s_axi_csr_rdata,
  output wire [1:0]  s_axi_csr_rresp,
  output wire        s_axi_csr_rvalid,
  input  wire        s_axi_csr_rready,
  // Board shim (AXI4-Lite, 12-bit address)
  input  wire [11:0] s_axi_shim_awaddr,
  input  wire        s_axi_shim_awvalid,
  output wire        s_axi_shim_awready,
  input  wire [31:0] s_axi_shim_wdata,
  input  wire [3:0]  s_axi_shim_wstrb,
  input  wire        s_axi_shim_wvalid,
  output wire        s_axi_shim_wready,
  output wire [1:0]  s_axi_shim_bresp,
  output wire        s_axi_shim_bvalid,
  input  wire        s_axi_shim_bready,
  input  wire [11:0] s_axi_shim_araddr,
  input  wire        s_axi_shim_arvalid,
  output wire        s_axi_shim_arready,
  output wire [31:0] s_axi_shim_rdata,
  output wire [1:0]  s_axi_shim_rresp,
  output wire        s_axi_shim_rvalid,
  input  wire        s_axi_shim_rready,
  // Request stream from the AXI-Stream FIFO
  input  wire [31:0] s_axis_rx_tdata,
  input  wire [3:0]  s_axis_rx_tkeep,
  input  wire        s_axis_rx_tlast,
  input  wire        s_axis_rx_tvalid,
  output wire        s_axis_rx_tready,
  // Command stream to the AXI-Stream FIFO
  output wire [31:0] m_axis_tx_tdata,
  output wire [3:0]  m_axis_tx_tkeep,
  output wire        m_axis_tx_tlast,
  output wire        m_axis_tx_tvalid,
  input  wire        m_axis_tx_tready,
  output wire        brake,
  output wire        heartbeat
);
  wire        core_rst_n, ack_valid, rsp_valid, rsp_ready, irq;
  wire [31:0] time_us, ack_seq;
  wire [37:0] rsp_data;
  wire [9:0]  log_idx;
  wire        log_valid, log_ready, log_ready_out, log_valid_out;
  wire [1055:0] log_data;

  m_tsmx_top #(.PARA_DIRECT(32'd0), .PARA_G(32'd2), .PARA_P(32'd2)) u_tsmx (
    .i_clk_core(clk), .i_rst_n_core(core_rst_n),
    .i_req_valid(1'b0), .i_req_data({44673{1'b0}}), .o_req_ready(),
    .i_rsp_ready(rsp_ready), .o_rsp_valid(rsp_valid), .o_rsp_data(rsp_data),
    .i_time_us(time_us), .i_ack_valid(ack_valid), .i_ack_seq(ack_seq),
    .o_brake(brake), .o_heartbeat(heartbeat),
    .i_axi_awaddr(s_axi_csr_awaddr), .i_axi_awprot(s_axi_csr_awprot), .i_axi_awvalid(s_axi_csr_awvalid),
    .i_axi_wdata(s_axi_csr_wdata), .i_axi_wstrb(s_axi_csr_wstrb), .i_axi_wvalid(s_axi_csr_wvalid),
    .i_axi_bready(s_axi_csr_bready), .i_axi_araddr(s_axi_csr_araddr), .i_axi_arprot(s_axi_csr_arprot),
    .i_axi_arvalid(s_axi_csr_arvalid), .i_axi_rready(s_axi_csr_rready),
    .o_axi_awready(s_axi_csr_awready), .o_axi_wready(s_axi_csr_wready), .o_axi_bvalid(s_axi_csr_bvalid),
    .o_axi_bresp(s_axi_csr_bresp), .o_axi_arready(s_axi_csr_arready), .o_axi_rvalid(s_axi_csr_rvalid),
    .o_axi_rresp(s_axi_csr_rresp), .o_axi_rdata(s_axi_csr_rdata), .o_int_irq(irq),
    .i_log_idx(log_idx), .i_log_valid(log_valid), .i_log_ready(log_ready),
    .o_log_ready(log_ready_out), .o_log_data(log_data), .o_log_valid(log_valid_out),
    .i_rx_valid(s_axis_rx_tvalid), .i_rx_data(s_axis_rx_tdata), .i_rx_keep(s_axis_rx_tkeep),
    .i_rx_last(s_axis_rx_tlast), .o_rx_ready(s_axis_rx_tready),
    .o_tx_valid(m_axis_tx_tvalid), .o_tx_data(m_axis_tx_tdata), .o_tx_keep(m_axis_tx_tkeep),
    .o_tx_last(m_axis_tx_tlast), .i_tx_ready(m_axis_tx_tready)
  );

  tsmx_board_shim_v2 u_shim (
    .clk(clk), .rst_n(resetn),
    .s_axi_awaddr(s_axi_shim_awaddr), .s_axi_awvalid(s_axi_shim_awvalid), .s_axi_awready(s_axi_shim_awready),
    .s_axi_wdata(s_axi_shim_wdata), .s_axi_wstrb(s_axi_shim_wstrb), .s_axi_wvalid(s_axi_shim_wvalid),
    .s_axi_wready(s_axi_shim_wready), .s_axi_bresp(s_axi_shim_bresp), .s_axi_bvalid(s_axi_shim_bvalid),
    .s_axi_bready(s_axi_shim_bready), .s_axi_araddr(s_axi_shim_araddr), .s_axi_arvalid(s_axi_shim_arvalid),
    .s_axi_arready(s_axi_shim_arready), .s_axi_rdata(s_axi_shim_rdata), .s_axi_rresp(s_axi_shim_rresp),
    .s_axi_rvalid(s_axi_shim_rvalid), .s_axi_rready(s_axi_shim_rready),
    .core_rst_n(core_rst_n), .time_us(time_us), .ack_seq(ack_seq), .ack_valid(ack_valid),
    .rsp_valid(rsp_valid), .rsp_data(rsp_data), .rsp_ready(rsp_ready),
    .brake(brake), .heartbeat(heartbeat), .int_irq(irq),
    .log_idx(log_idx), .log_valid(log_valid), .log_ready(log_ready),
    .log_ready_in(log_ready_out), .log_data(log_data), .log_valid_in(log_valid_out),
    .rx_valid(s_axis_rx_tvalid), .rx_ready(s_axis_rx_tready), .rx_last(s_axis_rx_tlast)
  );
endmodule
`default_nettype wire
