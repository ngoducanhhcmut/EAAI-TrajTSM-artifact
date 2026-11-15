`default_nettype none
(* black_box *) module m_tsmx_sweep #(
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_G = 32'd8,
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_P = 32'd8,
  localparam logic [31:0] LPARA_PAIR_NUM = (PARA_G<PARA_P) ? PARA_G : PARA_P
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [127:0] i_pose,
  input wire [31:0] i_epoch,
  input wire [8199:0] i_world,
  input wire [383:0] i_lane,
  input wire [1:0] i_kind,
  input wire [703:0] i_bridge,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [15:0] o_rsp_data
);
endmodule
`default_nettype wire
