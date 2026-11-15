`default_nettype none
(* black_box *) module m_tsmx_math (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [2:0] i_op,
  input wire [255:0] i_ego,
  input wire [8199:0] i_world,
  input wire [31:0] i_delay,
  input wire [559:0] i_plan,
  input wire [31:0] i_rear,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic o_ok,
  output logic [8199:0] o_world,
  output logic [703:0] o_bridge,
  output logic [95:0] o_pose
);
endmodule
`default_nettype wire
