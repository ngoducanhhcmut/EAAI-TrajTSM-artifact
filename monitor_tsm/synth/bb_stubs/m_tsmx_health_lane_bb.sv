`default_nettype none
(* black_box *) module m_tsmx_health_lane #( 
  // Parameter Description: Protected word capacity; ABI remains fixed at 1024 slots.
  // Parameter values: 1 through 1024; default 1024.
  // Parameter unit: count
  parameter logic [31:0] PARA_HEALTH_WORDS=32'd1024
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [33823:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic o_rsp_data
);
endmodule
`default_nettype wire
