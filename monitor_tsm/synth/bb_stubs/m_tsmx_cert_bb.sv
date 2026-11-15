`default_nettype none
(* black_box *) module m_tsmx_cert #(
  // Parameter Description: locked Config1 contract version.
  // Parameter values: 1 only; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_VERSION = 32'd1,
  // Parameter Description: locked Config1 maximum lease.
  // Parameter values: 500000 only; default is 500000.
  // Parameter unit: microsecond
  parameter logic [31:0] PARA_LEASE_US = 32'd500000,
  // Parameter Description: locked Config1 ACK timeout.
  // Parameter values: 40000 only; default is 40000.
  // Parameter unit: microsecond
  parameter logic [31:0] PARA_ACK_US = 32'd40000,
  // Parameter Description: locked Config1 admission expiry margin.
  // Parameter values: 20000 only; default is 20000.
  // Parameter unit: microsecond
  parameter logic [31:0] PARA_MARGIN_US = 32'd20000,
  localparam logic [31:0] LPARA_OP_ELAPSED = 32'd8,
  localparam logic [31:0] LPARA_OK = 32'd0,
  localparam logic [31:0] LPARA_TIMEOUT = 32'd3,
  localparam logic [31:0] LPARA_BINDING = 32'd25,
  localparam logic [31:0] LPARA_REPLAY = 32'd26,
  localparam logic [31:0] LPARA_CONTEXT = 32'd27,
  localparam logic [31:0] LPARA_LEASE = 32'd28,
  localparam logic [31:0] LPARA_EXEC_EXPIRY = 32'd29,
  localparam logic [31:0] LPARA_ACK_TIMEOUT = 32'd30,
  localparam logic [31:0] LPARA_COMMITTED = 32'd31,
  localparam logic [31:0] LPARA_PENDING = 32'd32,
  localparam logic [31:0] LPARA_LATE_APPLY = 32'd33,
  localparam logic [31:0] LPARA_EXPIRY = 32'd34
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [2903:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [7:0] o_rsp_data
);
endmodule
`default_nettype wire
