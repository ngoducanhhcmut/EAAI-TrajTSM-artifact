/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : B7 finite-jerk priority reduction.
 * Assumptions  : See R1_DECISIONS.md; reset release is synchronized by the wrapper.
 */
`timescale 1ns/1ps
`default_nettype none

module m_tsmx_sel #(
  // Parameter Description: fixed library size; overrides other than 16 are unsupported.
  // Parameter values: 16 only; default is 16.
  // Parameter unit: count
  parameter logic [31:0] PARA_PROFILES = 32'd16,
  localparam logic [31:0] LPARA_LABEL_COND = 32'd1,
  localparam logic [31:0] LPARA_LABEL_MIT = 32'd2,
  localparam logic [31:0] LPARA_CAND_MIT = 32'd15,
  localparam logic [31:0] LPARA_ACCEPT_MASK = 32'h7777,
  localparam logic [31:0] LPARA_CAND_0 = 32'd1,
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
  // BOOT inhibits ready during reset; IDLE accepts once; RESP holds until consumed.
  typedef enum logic [1:0] {
    ENUM_ST_BOOT = 2'b00,
    ENUM_ST_IDLE = 2'b01,
    ENUM_ST_RESP = 2'b10
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state;
  ctrl_state_type_def w_fsm_ctrl_nxt_state;
  logic [15:0] reg_resp;
  logic [15:0] w_result;
  logic [15:0] w_resp_nxt;

  // State-only outputs avoid a request/response ready combinational loop.
  always_comb begin : p_com_outputs
    o_req_ready = 1'b0;
    o_rsp_valid = 1'b0;
    o_rsp_data = '0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready = i_rst_n_core;
      ENUM_ST_RESP: begin
        o_rsp_valid = i_rst_n_core;
        if (i_rst_n_core) o_rsp_data = reg_resp;
      end
      default: begin
        o_req_ready = 1'b0;
      end
    endcase
  end

  // Acceptance captures the proposal; consumption clears validity and payload.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_resp_nxt = reg_resp;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
        w_resp_nxt = '0;
      end
      ENUM_ST_IDLE: begin
        if (i_req_valid) begin
          w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          w_resp_nxt = w_result;
        end
      end
      ENUM_ST_RESP: begin
        if (i_rsp_ready) begin
          w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
          w_resp_nxt = '0;
        end
      end
      default: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
        w_resp_nxt = '0;
      end
    endcase
  end

  // Instantaneous profiles are masked; lowest remaining ID wins (spec 5.5.7, 9.2).
  always_comb begin : p_com_sel
    w_result = {8'(LPARA_CAND_MIT), 8'(LPARA_LABEL_MIT)};
    casez (i_req_data & 16'(LPARA_ACCEPT_MASK))
      16'b???????????????1: w_result = {8'(LPARA_CAND_0), 8'(LPARA_LABEL_COND)};
      16'b??????????????10: w_result = {8'(LPARA_CAND_1), 8'(LPARA_LABEL_COND)};
      16'b?????????????100: w_result = {8'(LPARA_CAND_2), 8'(LPARA_LABEL_COND)};
      16'b???????????10000: w_result = {8'(LPARA_CAND_4), 8'(LPARA_LABEL_COND)};
      16'b??????????100000: w_result = {8'(LPARA_CAND_5), 8'(LPARA_LABEL_COND)};
      16'b?????????1000000: w_result = {8'(LPARA_CAND_6), 8'(LPARA_LABEL_COND)};
      16'b???????100000000: w_result = {8'(LPARA_CAND_8), 8'(LPARA_LABEL_COND)};
      16'b??????1000000000: w_result = {8'(LPARA_CAND_9), 8'(LPARA_LABEL_COND)};
      16'b?????10000000000: w_result = {8'(LPARA_CAND_10), 8'(LPARA_LABEL_COND)};
      16'b???1000000000000: w_result = {8'(LPARA_CAND_12), 8'(LPARA_LABEL_COND)};
      16'b??10000000000000: w_result = {8'(LPARA_CAND_13), 8'(LPARA_LABEL_COND)};
      16'b?100000000000000: w_result = {8'(LPARA_CAND_14), 8'(LPARA_LABEL_COND)};
      default: w_result = {8'(LPARA_CAND_MIT), 8'(LPARA_LABEL_MIT)};
    endcase
  end


  // Control and response are invalidated asynchronously; release comes from the wrapper.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_resp <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_resp <= w_resp_nxt;
    end
  end

endmodule
`default_nettype wire
