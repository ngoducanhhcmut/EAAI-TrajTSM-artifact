/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Asynchronous assertion and two-flop synchronous core reset release.
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_rst (
  input wire i_clk_core,
  input wire i_rst_n_core,
  output logic o_rst_n_core
);
  logic [1:0] reg_release;
  // Both stages assert asynchronously; only stage two releases functional state.
  assign o_rst_n_core=reg_release[1];
  // The core domain samples release on two successive rising edges.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_release
    if(!i_rst_n_core) reg_release<=2'b00;
    else reg_release<={reg_release[0],1'b1};
  end
endmodule
`default_nettype wire
