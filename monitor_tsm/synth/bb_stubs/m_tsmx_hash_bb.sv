`default_nettype none
(* black_box *) module m_tsmx_hash (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [7:0] i_op,
  input wire [10:0] i_len,
  input wire [8415:0] i_data,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [288:0] o_rsp_data
);
endmodule
`default_nettype wire
