`default_nettype none
(* black_box *) module m_tsmx_splice #(
  localparam logic [31:0] LPARA_DX = 32'd50000,
  localparam logic [31:0] LPARA_DV = 32'd50000,
  localparam logic [31:0] LPARA_DA = 32'd100000,
  localparam logic [31:0] LPARA_TUBE_X = 32'd160000,
  localparam logic [31:0] LPARA_TUBE_V = 32'd200000,
  localparam logic [31:0] LPARA_MAX_DELAY = 32'd100000,
  localparam logic [31:0] LPARA_MAX_V = 32'd10000000,
  localparam logic [31:0] LPARA_MAX_A = 32'd8000000,
  localparam logic [31:0] LPARA_POS_UNIT = 32'd1000000000,
  localparam logic [31:0] LPARA_OP_ADVANCE = 32'd3
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [815:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic o_rsp_data
);
endmodule
`default_nettype wire
