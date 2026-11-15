`default_nettype none
(* black_box *) module m_tsmx_supervisor #(
  localparam logic [31:0] LPARA_MODE_L0 = 32'd0,
  localparam logic [31:0] LPARA_MODE_L1 = 32'd1,
  localparam logic [31:0] LPARA_MODE_L2 = 32'd2,
  localparam logic [31:0] LPARA_MODE_L3 = 32'd3,
  localparam logic [31:0] LPARA_MODE_HOLD = 32'd4,
  localparam logic [31:0] LPARA_MODE_RECOVERY = 32'd5,
  localparam logic [31:0] LPARA_RECOVERY_GOOD = 32'd3
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [43:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [7:0] o_rsp_data
);
endmodule
`default_nettype wire
