`default_nettype none
(* black_box *) module m_tsmx_ingress #(
  // Parameter Description: transport limit enforced by top before parse_ok is asserted.
  // Parameter values: 65536 only; default is 65536.
  // Parameter unit: byte
  parameter logic [31:0] PARA_PACKET_LIMIT = 32'd65536,
  localparam logic [31:0] LPARA_AGE = 32'd150000,
  localparam logic [31:0] LPARA_FREEZE = 32'd300000,
  localparam logic [31:0] LPARA_MOVE = 32'd200000,
  localparam logic [31:0] LPARA_SPEED = 32'd10000000,
  localparam logic [31:0] LPARA_ACCEL = 32'd8000000,
  localparam logic [31:0] LPARA_SCALE = 32'd1000000,
  localparam logic [31:0] LPARA_POS_METERS = 32'd10000,
  localparam logic [31:0] LPARA_OP_ELAPSED = 32'd8,
  localparam logic [31:0] LPARA_TAILS = 32'd16,
  localparam logic [31:0] LPARA_COUNT_MIN = 32'd2,
  localparam logic [31:0] LPARA_COUNT_MAX = 32'd32,
  localparam logic [31:0] LPARA_COMPUTE = 32'd10000
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1373:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [339:0] o_rsp_data
);
endmodule
`default_nettype wire
