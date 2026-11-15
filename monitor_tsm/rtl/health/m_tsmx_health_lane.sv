/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-30
 * Version      : 0.2
 * Description  : Structural B13 lane with dedicated accepted B4/B3 resources.
 * Assumptions  : Wrapper synchronizes reset release and owns DFT reset override.
 * Deviations   : Functional leaves implement logic (HIE-02); enclosing lane is structural.
 *                Fixed SI constants and record widths implement spec 9.2 (PAR-03).
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_health_lane #( 
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
  logic [175:0] w_b4_req;
  logic [401:0] w_b4_rsp;
  logic [8583:0] w_b3_req;
  logic [80:0] w_b3_rsp;
  logic w_b4_qv,w_b4_qr,w_b4_sv,w_b4_sr;
  logic w_b3_qv,w_b3_qr,w_b3_sv,w_b3_sr;
  // Dedicated pair has no contention with functional candidate sweeps.
  m_tsmx_health #(.PARA_HEALTH_WORDS(PARA_HEALTH_WORDS)) u_tsmx_health (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(i_req_valid), .i_req_data(i_req_data), .i_rsp_ready(i_rsp_ready),
    .o_req_ready(o_req_ready), .o_rsp_valid(o_rsp_valid), .o_rsp_data(o_rsp_data),
    .o_b4_data(w_b4_req), .o_b4_valid(w_b4_qv), .i_b4_ready(w_b4_qr),
    .i_b4_data(w_b4_rsp), .i_b4_valid(w_b4_sv), .o_b4_ready(w_b4_sr),
    .o_b3_data(w_b3_req), .o_b3_valid(w_b3_qv), .i_b3_ready(w_b3_qr),
    .i_b3_data(w_b3_rsp), .i_b3_valid(w_b3_sv), .o_b3_ready(w_b3_sr)
  );
  m_tsmx_health_bist u_tsmx_health_bist (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_b4_data(w_b4_req), .i_b4_valid(w_b4_qv), .o_b4_ready(w_b4_qr),
    .o_b4_data(w_b4_rsp), .o_b4_valid(w_b4_sv), .i_b4_ready(w_b4_sr),
    .i_b3_data(w_b3_req), .i_b3_valid(w_b3_qv), .o_b3_ready(w_b3_qr),
    .o_b3_data(w_b3_rsp), .o_b3_valid(w_b3_sv), .i_b3_ready(w_b3_sr)
  );
endmodule

`default_nettype wire
