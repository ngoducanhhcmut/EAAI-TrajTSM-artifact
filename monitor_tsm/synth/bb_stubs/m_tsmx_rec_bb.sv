`default_nettype none
(* black_box *) module m_tsmx_rec #(
  // Parameter Description: ring capacity fixed at elaboration; index port remains 10 bits.
  // Parameter values: 1 through 1024; default is 64.
  // Parameter unit: count
  parameter logic [31:0] PARA_LOG_DEPTH = 32'd64,
  localparam logic [31:0] LPARA_FIELD_W = 32'd263,
  localparam logic [31:0] LPARA_FIELDS = 32'd4,
  localparam logic [31:0] LPARA_LEN_W = 32'd6,
  localparam logic [31:0] LPARA_BYTE_W = 32'd8,
  localparam logic [31:0] LPARA_INT_PAD_W = 32'd192,
  localparam logic [31:0] LPARA_INT_W = 32'd64,
  localparam logic [31:0] LPARA_STRING_MAX = 32'd32,
  localparam logic [31:0] LPARA_LOST_MAX = 32'hffffffff
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1055:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [31:0] o_rsp_data,
  input wire [9:0] i_log_idx,
  input wire i_log_valid,
  input wire i_log_ready,
  output logic o_log_ready,
  output logic [1055:0] o_log_data,
  output logic o_log_valid
);
endmodule
`default_nettype wire
