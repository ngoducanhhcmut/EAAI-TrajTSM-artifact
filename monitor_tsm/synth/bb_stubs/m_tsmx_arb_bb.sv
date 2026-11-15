`default_nettype none
(* black_box *) module m_tsmx_arb #(
  // Parameter Description: fixed profile library size; no other configuration is supported.
  // Parameter values: 16 only; default is 16.
  // Parameter unit: count
  parameter logic [31:0] PARA_PROFILES = 32'd16,
  // Parameter Description: locked brake8 instant mitigation profile identifier.
  // Parameter values: 15 only; default is 15.
  // Parameter unit: none
  parameter logic [31:0] PARA_MIT_ID = 32'd15,
  localparam logic [31:0] LPARA_PROFILES = 32'd16,
  localparam logic [31:0] LPARA_MIT_ID = 32'd15,
  localparam logic [31:0] LPARA_STEP = 32'd100000,
  localparam logic [31:0] LPARA_FINITE = 32'h7777
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [3862:0] i_req_data,
  input wire i_rsp_ready,
  input wire i_override,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [1996:0] o_rsp_data,
  output logic o_brake
);
endmodule
`default_nettype wire
