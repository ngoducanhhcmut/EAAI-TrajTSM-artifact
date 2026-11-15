/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Immutable command source mux with independent sticky brake override.
 * Assumptions  : Top supplies B9-authorized flags and owns time/expiry monitoring.
 *                Reset release is synchronized in the wrapper. See R10_DECISIONS.md.
 * Deviations   : HIE-02: functional leaf; system top remains structural.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_arb #(
  // Parameter Description: fixed profile library size; no other configuration is supported.
  // Parameter values: 16 only; default is 16.
  // Parameter unit: count
  parameter logic [31:0] PARA_PROFILES = 32'd16,
  // Parameter Description: locked brake8 instant mitigation profile identifier.
  // Parameter values: 15 only; default is 15.
  // Parameter unit: none
  parameter logic [31:0] PARA_MIT_ID = 32'd15,
  localparam logic [31:0] LPARA_PROFILES = 32'd16,
  localparam logic [31:0] LPARA_MIT_ID = 32'd15,
  localparam logic [31:0] LPARA_STEP = 32'd100000,
  localparam logic [31:0] LPARA_FINITE = 32'h7777
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [3862:0] i_req_data,
  input wire i_rsp_ready,
  input wire i_override,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [1996:0] o_rsp_data,
  output logic o_brake
);
  typedef enum logic [2:0] {
    ENUM_MODE_L0 = 3'd0, ENUM_MODE_L1 = 3'd1, ENUM_MODE_L2 = 3'd2,
    ENUM_MODE_L3 = 3'd3, ENUM_MODE_HOLD = 3'd4, ENUM_MODE_RECOVERY = 3'd5
  } mode_type_def;
  typedef enum logic [2:0] {
    ENUM_SRC_NOMINAL = 3'd0, ENUM_SRC_BACKUP = 3'd1, ENUM_SRC_FALLBACK = 3'd2,
    ENUM_SRC_MIT = 3'd3, ENUM_SRC_PARKING = 3'd4
  } src_type_def;
  typedef enum logic [7:0] {
    ENUM_LABEL_COND = 8'd1, ENUM_LABEL_MIT = 8'd2
  } label_type_def;
  typedef enum logic [1:0] {
    ENUM_ST_BOOT = 2'd0,
    ENUM_ST_IDLE = 2'd1,
    ENUM_ST_RESP = 2'd2
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state;
  ctrl_state_type_def w_fsm_ctrl_nxt_state;
  logic [1996:0] reg_resp, w_resp_nxt, w_result;
  logic reg_brake, w_brake_nxt;
  logic [2:0] w_mode, w_cmd_mode, w_src;
  logic [7:0] w_cand, w_label, w_cmd_cand, w_cmd_label;
  logic [31:0] w_now, w_seq, w_apply, w_expiry;
  logic w_pending_valid, w_backup_valid, w_parking, w_cmd_override;
  logic [559:0] w_pending_plan, w_backup_plan, w_plan;
  logic [1216:0] w_pending_cert, w_backup_cert, w_cert;
  logic [255:0] w_ego;

  // Command has100 spare MSB bits: listed fields total1897; see SPEC-ISSUE.
  // Field order is exactly spec 9.2, MSB first; no fixture summary offsets are used.
  assign {w_mode, w_cand, w_label, w_now, w_pending_valid, w_pending_plan,
          w_pending_cert, w_backup_valid, w_backup_plan, w_backup_cert, w_ego} = i_req_data;

  // Brake assertion bypasses both the clock and command backpressure.
  assign o_brake = !i_rst_n_core || i_override || reg_brake;

  // The held frame is independent of override; invalid payload is always zero.
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
      default: o_req_ready = 1'b0;
    endcase
  end

  // Select only preauthorized records; a missing record fails closed to L3/id15.
  // Source codes and local fallback metadata are delegated ABI choices, decisions 4..7.
  always_comb begin : p_com_cmd
    w_src = ENUM_SRC_MIT;
    w_cmd_mode = ENUM_MODE_L3;
    w_cmd_label = ENUM_LABEL_MIT;
    w_cmd_cand = 8'(LPARA_MIT_ID);
    w_seq = '0;
    w_apply = w_now;
    w_expiry = 32'(w_now + LPARA_STEP);
    w_plan = '0;
    w_cert = '0;
    w_parking = 1'b0;
    w_cmd_override = 1'b1;
    w_result = '0;
    if (!i_override && PARA_PROFILES == LPARA_PROFILES && PARA_MIT_ID == LPARA_MIT_ID) begin
      case (w_mode)
        ENUM_MODE_L0, ENUM_MODE_RECOVERY: begin
          if (w_pending_valid && w_pending_cert[1216]) begin
            w_src = ENUM_SRC_NOMINAL;
            w_cmd_mode = w_mode;
            w_cmd_label = ENUM_LABEL_COND;
            w_cmd_cand = w_pending_plan[79:72];
            w_plan = w_pending_plan;
            w_cert = w_pending_cert;
            w_cmd_override = 1'b0;
          end
        end
        ENUM_MODE_L1: begin
          if (w_backup_valid && w_backup_cert[1216]) begin
            w_src = ENUM_SRC_BACKUP;
            w_cmd_mode = w_mode;
            w_cmd_label = ENUM_LABEL_COND;
            w_cmd_cand = w_backup_plan[79:72];
            w_plan = w_backup_plan;
            w_cert = w_backup_cert;
            w_cmd_override = 1'b0;
          end
        end
        ENUM_MODE_L2: begin
          if (w_cand < 8'(LPARA_PROFILES) && LPARA_FINITE[w_cand[3:0]] && w_label == ENUM_LABEL_COND) begin
            w_src = ENUM_SRC_FALLBACK;
            w_cmd_mode = w_mode;
            w_cmd_label = w_label;
            w_cmd_cand = w_cand;
            w_cmd_override = 1'b0;
          end
        end
        ENUM_MODE_HOLD: begin
          w_src = ENUM_SRC_PARKING;
          w_cmd_mode = w_mode;
          w_parking = 1'b1;
          w_cmd_override = 1'b0;
        end
        default: begin
          w_src = ENUM_SRC_MIT;
        end
      endcase
    end
    case (w_src)
      ENUM_SRC_NOMINAL, ENUM_SRC_BACKUP: begin
        w_seq = w_plan[559:528];
        w_apply = w_now;
        w_expiry = w_cert[671:640];
      end
      default: begin
        // Local commands carry the current state, not a fabricated nominal certificate.
        // Epoch stays now; local lifetime is one decision step, with serial u32 wrap.
        w_plan = {32'd0, w_ego, w_now, w_now, w_ego[223:160], w_ego[159:128],
                  w_ego[127:96], w_cmd_cand, 32'd0, 8'd0, 32'd1};
      end
    endcase
    w_result = {100'd0, w_src, w_cmd_mode, w_cmd_label, w_cmd_cand, w_seq, w_apply,
                w_expiry, w_plan, w_cert, w_parking, w_cmd_override};
  end

  // Override is sticky until a new safe command is accepted with override low.
  // Consumption clears only transport validity; it does not withdraw brake protection.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_resp_nxt = reg_resp;
    w_brake_nxt = reg_brake;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
        w_resp_nxt = '0;
      end
      ENUM_ST_IDLE: begin
        if (i_req_valid) begin
          w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          w_resp_nxt = w_result;
          w_brake_nxt = w_result[0];
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
        w_brake_nxt = 1'b1;
      end
    endcase
    if (i_override) w_brake_nxt = 1'b1;
  end

  // Reset invalidates the frame and asserts brake. Wrapper owns synchronized reset release.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_resp <= '0;
      reg_brake <= 1'b1;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_resp <= w_resp_nxt;
      reg_brake <= w_brake_nxt;
    end
  end
endmodule
`default_nettype wire
