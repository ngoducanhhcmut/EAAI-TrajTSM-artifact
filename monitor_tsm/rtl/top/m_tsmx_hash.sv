/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Top-owned canonical byte serializer and accepted codec.
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_hash (
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
  typedef enum logic [3:0] {
    ENUM_ST_BOOT = 4'h1,
    ENUM_ST_IDLE = 4'h2,
    ENUM_ST_SEND = 4'h4,
    ENUM_ST_WAIT = 4'h8
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [7:0] reg_op, w_op_nxt;
  logic [10:0] reg_len, w_len_nxt;
  logic [8415:0] reg_data, w_data_nxt;
  logic [10:0] reg_idx, w_idx_nxt;
  logic w_codec_req_valid, w_codec_req_ready, w_codec_resp_valid;
  logic [44:0] w_codec_req_data;
  logic [288:0] w_codec_resp_data;


  // Defaults retain state; unused FSM encodings recover through BOOT.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_op_nxt = reg_op;
    w_len_nxt = reg_len;
    w_data_nxt = reg_data;
    w_idx_nxt = reg_idx;
    o_req_ready = i_rst_n_core && reg_fsm_ctrl_current_state == ENUM_ST_IDLE;
    o_rsp_valid = i_rst_n_core && w_codec_resp_valid;
    o_rsp_data = o_rsp_valid ? w_codec_resp_data : 289'd0;
    w_codec_req_valid = 1'b0; w_codec_req_data = '0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      ENUM_ST_IDLE: begin
        if (i_req_valid) begin
        w_op_nxt = i_op;        w_len_nxt = i_len;        w_data_nxt = i_data;        w_idx_nxt = 11'd0;        w_fsm_ctrl_nxt_state = ENUM_ST_SEND;
        end
      end
      ENUM_ST_SEND: begin
        w_codec_req_valid = 1'b1;
        w_codec_req_data = {reg_op, reg_idx==11'd0, reg_idx+11'd4>=reg_len,
          3'((reg_len-reg_idx>=11'd4) ? 11'd4 : reg_len-reg_idx),
          reg_data[8415-32'(reg_idx)*8 -:32]};
        if (w_codec_req_ready) begin
          if (reg_idx+11'd4>=reg_len) w_fsm_ctrl_nxt_state = ENUM_ST_WAIT;
          else w_idx_nxt = 11'(reg_idx+11'd4);
        end
      end
      ENUM_ST_WAIT: begin
        if (w_codec_resp_valid) w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      default: w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
    endcase

  end
  // Asynchronous assertion; the enclosing reset synchronizer releases this domain.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_op <= '0;
      reg_len <= '0;
      reg_data <= '0;
      reg_idx <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_op <= w_op_nxt;
      reg_len <= w_len_nxt;
      reg_data <= w_data_nxt;
      reg_idx <= w_idx_nxt;
    end
  end
  m_tsmx_codec u_codec (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_codec_req_valid),
    .i_req_data(w_codec_req_data),
    .o_req_ready(w_codec_req_ready),
    .o_rsp_valid(w_codec_resp_valid),
    .o_rsp_data(w_codec_resp_data),
    .i_rsp_ready(1'b1)
  );

endmodule
`default_nettype wire
