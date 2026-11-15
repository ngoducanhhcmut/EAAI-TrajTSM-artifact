/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : B9 immutable certificate checker.
 * Assumptions  : See R9_DECISIONS.md; wrapper synchronizes reset release.
 * Deviations   : HIE-02: functional leaf; system top is structural.
 */
`timescale 1ns/1ps
`default_nettype none

module m_tsmx_cert #(
  // Parameter Description: locked Config1 contract version.
  // Parameter values: 1 only; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_VERSION = 32'd1,
  // Parameter Description: locked Config1 maximum lease.
  // Parameter values: 500000 only; default is 500000.
  // Parameter unit: microsecond
  parameter logic [31:0] PARA_LEASE_US = 32'd500000,
  // Parameter Description: locked Config1 ACK timeout.
  // Parameter values: 40000 only; default is 40000.
  // Parameter unit: microsecond
  parameter logic [31:0] PARA_ACK_US = 32'd40000,
  // Parameter Description: locked Config1 admission expiry margin.
  // Parameter values: 20000 only; default is 20000.
  // Parameter unit: microsecond
  parameter logic [31:0] PARA_MARGIN_US = 32'd20000,
  localparam logic [31:0] LPARA_OP_ELAPSED = 32'd8,
  localparam logic [31:0] LPARA_OK = 32'd0,
  localparam logic [31:0] LPARA_TIMEOUT = 32'd3,
  localparam logic [31:0] LPARA_BINDING = 32'd25,
  localparam logic [31:0] LPARA_REPLAY = 32'd26,
  localparam logic [31:0] LPARA_CONTEXT = 32'd27,
  localparam logic [31:0] LPARA_LEASE = 32'd28,
  localparam logic [31:0] LPARA_EXEC_EXPIRY = 32'd29,
  localparam logic [31:0] LPARA_ACK_TIMEOUT = 32'd30,
  localparam logic [31:0] LPARA_COMMITTED = 32'd31,
  localparam logic [31:0] LPARA_PENDING = 32'd32,
  localparam logic [31:0] LPARA_LATE_APPLY = 32'd33,
  localparam logic [31:0] LPARA_EXPIRY = 32'd34
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [2903:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [7:0] o_rsp_data
);
  typedef enum logic [1:0] {
    ENUM_ST_BOOT=2'd0, ENUM_ST_IDLE=2'd1,
    ENUM_ST_WAIT=2'd2, ENUM_ST_RESP=2'd3
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [2903:0] reg_req, w_req_nxt;
  logic [7:0] reg_resp, w_resp_nxt, w_result;
  logic w_ar_ready, w_ar_valid, w_ar_req;
  logic [1927:0] w_ar_data;
  logic [640:0] w_ar_resp;
  logic w_plan_present;
  logic [559:0] w_plan;
  logic [1216:0] w_cert;
  logic [31:0] w_now;
  logic w_executor;
  logic w_issued_valid;
  logic [31:0] w_issued;
  logic w_ack;
  logic w_seq_valid;
  logic [31:0] w_seq;
  logic w_context_valid;
  logic [255:0] w_context;
  logic w_reuse;
  logic [255:0] w_snapshot;
  logic [255:0] w_trajectory;
  logic [255:0] w_seal;
  logic [31:0] w_remain, w_apply, w_since, w_tail, w_phase;
  logic w_missing, w_binding, w_replay, w_ctx_bad, w_lease_bad;
  logic w_expired, w_ack_late, w_commit, w_late, w_margin;

  // Immutable request decode follows spec9, first field at the most significant bit.
  assign {w_plan_present, w_plan, w_cert, w_now, w_executor, w_issued_valid, w_issued, w_ack, w_seq_valid, w_seq, w_context_valid, w_context, w_reuse, w_snapshot, w_trajectory, w_seal} = reg_req;

  // Lease subtraction uses the accepted private arithmetic opcode8 (elapsed).
  // Live input is sampled by both modules on the same valid/ready acceptance edge.
  assign w_ar_data = {8'(LPARA_OP_ELAPSED), 128'd0, i_req_data[1797:1766],
                      128'd0, i_req_data[2614:2583], 1600'd0};
  // One helper job is issued only with public acceptance.
  assign w_ar_req = i_req_valid && i_rst_n_core
    && (reg_fsm_ctrl_current_state == ENUM_ST_IDLE);

  // Serial differences retain the full u32 domain; bit31 is the elapsed sign.
  always_comb begin : p_com_checks
    w_remain = 32'(w_cert[671:640] - w_now);
    w_apply = 32'(w_plan[239:208] - w_now);
    w_phase = 32'(w_now - w_plan[239:208]);
    w_since = 32'(w_now - w_issued);
    w_tail = 32'(w_cert[671:640] - w_plan[239:208]);
    w_missing = !w_plan_present || !w_cert[1216];
    w_binding = (w_cert[1215:960] != w_snapshot)
      || (w_cert[959:704] != w_trajectory) || (w_cert[255:0] != w_seal)
      || (w_cert[703:672] != w_plan[239:208])
      || (w_cert[639:608] != PARA_VERSION) || (w_cert[607:576] != PARA_VERSION)
      || (w_cert[575:544] != PARA_VERSION) || (w_cert[543:512] != PARA_VERSION);
    w_replay = w_seq_valid && (w_plan[559:528] != w_seq);
    w_ctx_bad = w_context_valid && (w_cert[511:256] != w_context);
    w_lease_bad = w_ar_resp[640] || w_ar_resp[639]
      || (w_ar_resp[639:480] == 160'd0)
      || (w_ar_resp[639:480] > 160'(PARA_LEASE_US));
    w_expired = w_remain[31] || (w_remain == 32'd0);
    w_ack_late = w_issued_valid && !w_since[31]
      && (w_since >= PARA_ACK_US) && !w_ack;
    // Separate subtraction preserves the exact ambiguous half-wrap encoding.
    w_commit = w_ack && !w_phase[31];
    w_late = !w_reuse && w_apply[31];
    w_margin = w_remain[31] || (w_remain < PARA_MARGIN_US)
      || w_tail[31] || (w_tail <= PARA_MARGIN_US);
    w_result = 8'(LPARA_OK);
    casez ({w_missing,w_binding,w_replay,w_ctx_bad,w_lease_bad})
      5'b1????: w_result = 8'(LPARA_TIMEOUT);
      5'b01???: w_result = 8'(LPARA_BINDING);
      5'b001??: w_result = 8'(LPARA_REPLAY);
      5'b0001?: w_result = 8'(LPARA_CONTEXT);
      5'b00001: w_result = 8'(LPARA_LEASE);
      default: begin
        if (w_executor) begin
          casez ({w_expired,w_ack_late,w_commit})
            3'b1??: w_result = 8'(LPARA_EXEC_EXPIRY);
            3'b01?: w_result = 8'(LPARA_ACK_TIMEOUT);
            3'b001: w_result = 8'(LPARA_COMMITTED);
            default: w_result = 8'(LPARA_PENDING);
          endcase
        end else begin
          casez ({w_late,w_margin})
            2'b1?: w_result = 8'(LPARA_LATE_APPLY);
            2'b01: w_result = 8'(LPARA_EXPIRY);
            default: w_result = 8'(LPARA_OK);
          endcase
        end
      end
    endcase
  end

  // Handshake is state-gated; response stays immutable until consumed.
  always_comb begin : p_com_outputs
    o_req_ready = 1'b0;
    o_rsp_valid = 1'b0;
    o_rsp_data = '0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready = i_rst_n_core && w_ar_ready;
      ENUM_ST_RESP: begin
        o_rsp_valid = i_rst_n_core;
        if (i_rst_n_core) o_rsp_data = reg_resp;
      end
      default: o_req_ready = 1'b0;
    endcase
  end

  // Capture once, drain the private arithmetic result, then publish ordered status.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_req_nxt = reg_req;
    w_resp_nxt = reg_resp;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      ENUM_ST_IDLE: begin
        if (i_req_valid && o_req_ready) begin
          w_req_nxt = i_req_data;
          w_fsm_ctrl_nxt_state = ENUM_ST_WAIT;
        end
      end
      ENUM_ST_WAIT: begin
        if (w_ar_valid) begin
          w_resp_nxt = w_result;
          w_req_nxt = '0;
          w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
        end
      end
      ENUM_ST_RESP: begin
        if (i_rsp_ready) begin
          w_resp_nxt = '0;
          w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
        end
      end
      default: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
        w_req_nxt = '0;
        w_resp_nxt = '0;
      end
    endcase
  end

  // Reset revokes the local context and the private primitive together.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_req <= '0;
      reg_resp <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_req <= w_req_nxt;
      reg_resp <= w_resp_nxt;
    end
  end

  // Private helper: no shared-resource arbitration or codec ownership in this leaf.
  m_tsmx_arith u_arith (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_ar_req), .i_req_data(w_ar_data), .i_rsp_ready(1'b1),
    .o_req_ready(w_ar_ready), .o_rsp_valid(w_ar_valid), .o_rsp_data(w_ar_resp)
  );
endmodule
`default_nettype wire
