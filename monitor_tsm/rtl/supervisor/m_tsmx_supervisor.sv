/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : B8 atomic next-state proposal.
 * Assumptions  : See R1_DECISIONS.md; reset release is synchronized by the wrapper.
 */
`timescale 1ns/1ps
`default_nettype none

module m_tsmx_supervisor #(
  localparam logic [31:0] LPARA_MODE_L0 = 32'd0,
  localparam logic [31:0] LPARA_MODE_L1 = 32'd1,
  localparam logic [31:0] LPARA_MODE_L2 = 32'd2,
  localparam logic [31:0] LPARA_MODE_L3 = 32'd3,
  localparam logic [31:0] LPARA_MODE_HOLD = 32'd4,
  localparam logic [31:0] LPARA_MODE_RECOVERY = 32'd5,
  localparam logic [31:0] LPARA_RECOVERY_GOOD = 32'd3
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [43:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [7:0] o_rsp_data
);
  // BOOT inhibits ready during reset; IDLE accepts once; RESP holds until consumed.
  typedef enum logic [1:0] {
    ENUM_ST_BOOT = 2'b00,
    ENUM_ST_IDLE = 2'b01,
    ENUM_ST_RESP = 2'b10
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state;
  ctrl_state_type_def w_fsm_ctrl_nxt_state;
  logic [7:0] reg_resp;
  logic [7:0] w_result;
  logic [7:0] w_resp_nxt;
  logic [1:0] w_good;
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

  // Ordered B8 precedence from spec 5.5.8; malformed modes use the unhealthy path.
  // Request: mode[43:41], good[40:39], fault[38], accept[37], v[36:5], flags[4:0].
  // Response: mode[7:5], good[4:3], fault[2], clear_pending[1], clear_backup[0].
  always_comb begin : p_com_proposal
    w_result = {3'(LPARA_MODE_L3), 2'd0, 1'b1, 1'b1, 1'b0};
    w_good = i_req_data[40:39];
    if (w_good != 2'(LPARA_RECOVERY_GOOD)) w_good = $bits(w_good)'(w_good + 2'd1);
    casez ({i_req_data[1] | !i_req_data[0] | (i_req_data[43:41] > 3'(LPARA_MODE_RECOVERY)),
            i_req_data[37], i_req_data[36:5] == 32'd0,
            i_req_data[4] & i_req_data[2], i_req_data[3] & i_req_data[2]})
      5'b1????: begin
        w_result = {3'(LPARA_MODE_L3), 2'd0, 1'b1, 1'b1, 1'b1};
        if (i_req_data[36:5] == 32'd0) w_result[7:5] = 3'(LPARA_MODE_HOLD);
      end
      5'b01???: begin
        w_result = {3'(LPARA_MODE_RECOVERY), w_good, 1'b0, 1'b0, 1'b0};
        if (w_good == 2'(LPARA_RECOVERY_GOOD)) w_result[7:5] = 3'(LPARA_MODE_L0);
      end
      5'b001??: w_result = {3'(LPARA_MODE_HOLD), 2'd0, 1'b1, 1'b1, 1'b0};
      5'b0001?: w_result = {3'(LPARA_MODE_L1), 2'd0, 1'b1, 1'b1, 1'b0};
      5'b00001: w_result = {3'(LPARA_MODE_L2), 2'd0, 1'b1, 1'b1, 1'b0};
      default: w_result = {3'(LPARA_MODE_L3), 2'd0, 1'b1, 1'b1, 1'b0};
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
