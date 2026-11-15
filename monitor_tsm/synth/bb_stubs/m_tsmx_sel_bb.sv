`default_nettype none
(* black_box *) module m_tsmx_sel #(
  // Parameter Description: fixed library size; overrides other than 16 are unsupported.
  // Parameter values: 16 only; default is 16.
  // Parameter unit: count
  parameter logic [31:0] PARA_PROFILES = 32'd16,
  localparam logic [31:0] LPARA_LABEL_COND = 32'd1,
  localparam logic [31:0] LPARA_LABEL_MIT = 32'd2,
  localparam logic [31:0] LPARA_CAND_MIT = 32'd15,
  localparam logic [31:0] LPARA_ACCEPT_MASK = 32'h7777,
  localparam logic [31:0] LPARA_CAND_0 = 32'd0,
  localparam logic [31:0] LPARA_CAND_1 = 32'd1,
  localparam logic [31:0] LPARA_CAND_2 = 32'd2,
  localparam logic [31:0] LPARA_CAND_4 = 32'd4,
  localparam logic [31:0] LPARA_CAND_5 = 32'd5,
  localparam logic [31:0] LPARA_CAND_6 = 32'd6,
  localparam logic [31:0] LPARA_CAND_8 = 32'd8,
  localparam logic [31:0] LPARA_CAND_9 = 32'd9,
  localparam logic [31:0] LPARA_CAND_10 = 32'd10,
  localparam logic [31:0] LPARA_CAND_12 = 32'd12,
  localparam logic [31:0] LPARA_CAND_13 = 32'd13,
  localparam logic [31:0] LPARA_CAND_14 = 32'd14
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [15:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [15:0] o_rsp_data
);
endmodule
`default_nettype wire
