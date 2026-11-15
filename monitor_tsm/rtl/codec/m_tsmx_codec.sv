/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Streaming packed-byte CRC32 and iterative SHA-256.
 * Assumptions  : Reset release is synchronized by the wrapper. See R3_DECISIONS.md.
 */
`timescale 1ns/1ps
`default_nettype none

module m_tsmx_codec #(
  // Parameter Description: maximum accepted bytes in one binding job, Config1 locked.
  // Parameter values: 32768 only; default is 32768.
  // Parameter unit: byte
  parameter logic [31:0] PARA_HASH_BYTES = 32'd32768
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [44:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [288:0] o_rsp_data
);
  // Structural wrapper preserves the common physical packed ABI (spec 5.3, 9.2).
  m_tsmx_codec_core #(.PARA_HASH_BYTES(PARA_HASH_BYTES)) u_codec_core (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(i_req_valid), .i_req_data(i_req_data), .i_rsp_ready(i_rsp_ready),
    .o_req_ready(o_req_ready), .o_rsp_valid(o_rsp_valid), .o_rsp_data(o_rsp_data)
  );
endmodule
`default_nettype wire
