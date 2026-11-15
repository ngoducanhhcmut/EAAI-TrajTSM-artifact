/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-02
 * Version      : 0.2
 * Description  : B1 integrity, serial freshness and explicit freeze history proposal.
 * Assumptions  : Config1 only; parser and local CRC belong to top (spec 5.3/9.2).
 * Deviation    : Functional leaf has logic (HIE-02); system top remains structural.
 * Deviation    : ABI field widths and SI bounds are fixed constants, not tunable.
 * A8 (02/11)   : ODD acceleration widened to [-8,+2] m/s^2 for Ego, snapshot and plan
 *                (golden check_apos.py); legacy/m_tsmx_ingress_pre_A8.sv.txt.
 * Reset        : Wrapper supplies synchronized release and test reset override.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_ingress #(
  // Parameter Description: transport limit enforced by top before parse_ok is asserted.
  // Parameter values: 65536 only; default is 65536.
  // Parameter unit: byte
  parameter logic [31:0] PARA_PACKET_LIMIT = 32'd65536,
  localparam logic [31:0] LPARA_AGE = 32'd150000,
  localparam logic [31:0] LPARA_FREEZE = 32'd300000,
  localparam logic [31:0] LPARA_MOVE = 32'd200000,
  localparam logic [31:0] LPARA_SPEED = 32'd10000000,
  localparam logic [31:0] LPARA_ACCEL = 32'd8000000,
  localparam logic [31:0] LPARA_ACCEL_POS = 32'd2000000,
  localparam logic [31:0] LPARA_SCALE = 32'd1000000,
  localparam logic [31:0] LPARA_POS_METERS = 32'd10000,
  localparam logic [31:0] LPARA_OP_ELAPSED = 32'd8,
  localparam logic [31:0] LPARA_TAILS = 32'd16,
  localparam logic [31:0] LPARA_COUNT_MIN = 32'd2,
  localparam logic [31:0] LPARA_COUNT_MAX = 32'd32,
  localparam logic [31:0] LPARA_COMPUTE = 32'd10000
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1373:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [339:0] o_rsp_data
);
  // Reason enum follows the shared section9.2 encoding exactly.
  typedef enum logic [7:0] {
    ENUM_RSN_OK=8'd0,
    ENUM_RSN_CLK=8'd1,
    ENUM_RSN_NO_SAMPLE=8'd2,
    ENUM_RSN_TIMEOUT=8'd3,
    ENUM_RSN_NUMERIC=8'd4,
    ENUM_RSN_RANGE=8'd5,
    ENUM_RSN_OVERFLOW=8'd6,
    ENUM_RSN_DEADLINE=8'd7,
    ENUM_RSN_SNAPSHOT=8'd8,
    ENUM_RSN_CRC=8'd9,
    ENUM_RSN_SEQUENCE=8'd10,
    ENUM_RSN_EGO_AGE=8'd11,
    ENUM_RSN_FRESHNESS=8'd12,
    ENUM_RSN_FREEZE=8'd13
  } reason_type_def;
  // BOOT releases reset; ISSUE/WAIT reserve the private arithmetic response.
  typedef enum logic [2:0] {
    ENUM_ST_BOOT=3'd0, ENUM_ST_IDLE=3'd1, ENUM_ST_ISSUE=3'd2,
    ENUM_ST_WAIT=3'd3, ENUM_ST_RESP=3'd4
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [1373:0] reg_req, w_req_nxt;
  logic [339:0] reg_resp, w_resp_nxt, w_result;
  logic [331:0] w_state, w_new_state;
  logic [255:0] w_ego, w_snap;
  logic [559:0] w_plan;
  logic [720:0] w_pkt;
  logic [31:0] w_now, w_crc, w_local_crc, w_pkt_schema;
  logic [31:0] w_seq, w_generated, w_apply, w_v, w_a, w_compute, w_schema;
  logic [63:0] w_x;
  logic [7:0] w_tail, w_count, w_reason;
  logic [95:0] w_ids;
  logic w_parse, w_present, w_seq_valid, w_time_valid, w_sample_valid, w_sig_valid;
  logic [31:0] w_old_seq, w_last_time, w_last_sample, w_freeze_since;
  logic [63:0] w_freeze_x, w_ego_x;
  logic [135:0] w_signature, w_new_sig;
  logic [31:0] w_ego_t, w_snap_t;
  logic [223:0] w_ego_rest, w_snap_rest;
  logic [31:0] w_seq_age, w_ego_age, w_snap_age, w_gen_age, w_gen_snap;
  logic [31:0] w_sample_age, w_freeze_age;
  logic [64:0] w_delta, w_distance;
  logic [13:0] w_reject;
  logic w_same;
  logic [1927:0] w_arith_req;
  logic [640:0] w_arith_rsp;
  logic w_arith_valid, w_arith_ready, w_arith_rsp_valid, w_arith_rsp_ready;

  // Two's-complement position comparison has no signed SV data dependency.
  function automatic logic f_pos(input logic [63:0] w_value);
    logic [63:0] w_mag;
    begin
      w_mag = w_value[63] ? 64'(~w_value + 1'b1) : w_value;
      f_pos = w_mag <= (64'(LPARA_POS_METERS)*64'(LPARA_SCALE));
    end
  endfunction

  // Numeric sentinels use the golden checked(...,64) guard before range checks.
  function automatic logic f_numeric(input logic [255:0] w_motion);
    logic [31:0] w_t, w_speed, w_accel, w_lead_v;
    logic [63:0] w_pos, w_lead_x;
    begin
      {w_t,w_pos,w_speed,w_accel,w_lead_x,w_lead_v}=w_motion;
      f_numeric = (w_pos==64'h8000000000000000) ||
        (w_lead_x==64'h8000000000000000);
    end
  endfunction

  // The Ego/snapshot range envelope is Config1, including the complete lead fields.
  function automatic logic f_range(input logic [255:0] w_motion);
    logic [31:0] w_t, w_speed, w_accel, w_lead_v, w_mag;
    logic [63:0] w_pos, w_lead_x;
    begin
      {w_t,w_pos,w_speed,w_accel,w_lead_x,w_lead_v}=w_motion;
      w_mag = 32'(~w_accel + 1'b1);
      f_range = f_pos(w_pos) && f_pos(w_lead_x) && w_speed<=LPARA_SPEED &&
        w_lead_v<=LPARA_SPEED &&
        (w_accel[31] ? w_mag<=LPARA_ACCEL : w_accel<=LPARA_ACCEL_POS);
    end
  endfunction

  // Decode immutable request and serial differences; only clock age uses shared ARITH.
  assign {w_state,w_now,w_ego,w_pkt,w_local_crc,w_parse}=reg_req;
  assign {w_present,w_plan,w_crc,w_ids,w_pkt_schema}=w_pkt;
  assign {w_seq,w_snap,w_generated,w_apply,w_x,w_v,w_a,w_tail,
    w_compute,w_count,w_schema}=w_plan;
  // State fields carry separate validity, preserving full u32 serial values.
  assign {w_seq_valid,w_old_seq,w_time_valid,w_last_time,w_sample_valid,
    w_last_sample,w_sig_valid,w_signature,w_freeze_since,w_freeze_x}=w_state;
  // Timestamp/position extracts retain unpadded nested record widths.
  assign {w_ego_t,w_ego_rest}=w_ego;
  assign {w_snap_t,w_snap_rest}=w_snap;
  assign w_ego_x=w_ego_rest[223:160];
  assign w_new_sig={w_x,w_v,w_a,w_tail};
  assign w_same=w_sig_valid && w_signature==w_new_sig;
  assign w_seq_age=32'(w_seq-w_old_seq);
  assign w_ego_age=32'(w_now-w_ego_t);
  assign w_snap_age=32'(w_now-w_snap_t);
  assign w_gen_age=32'(w_now-w_generated);
  assign w_gen_snap=32'(w_generated-w_snap_t);
  assign w_sample_age=32'(w_now-w_last_sample);
  assign w_freeze_age=32'(w_now-w_freeze_since);
  assign w_delta=65'({w_ego_x[63],w_ego_x}-{w_freeze_x[63],w_freeze_x});
  assign w_distance=w_delta[64] ? 65'(~w_delta+1'b1) : w_delta;
  assign w_arith_req={8'(LPARA_OP_ELAPSED),128'd0,w_now,128'd0,w_last_time,1600'd0};
  assign w_arith_valid=(reg_fsm_ctrl_current_state==ENUM_ST_ISSUE);
  assign w_arith_rsp_ready=(reg_fsm_ctrl_current_state==ENUM_ST_WAIT);

  // Ordered golden guards: bit zero has highest priority. No reject updates state.
  always_comb begin : p_com_admit
    w_reject='0;
    w_reject[0]=w_time_valid && w_arith_rsp[511];
    w_reject[1]=!w_present && w_sample_valid && !w_sample_age[31] &&
      w_sample_age>=LPARA_FREEZE;
    w_reject[2]=!w_present;
    w_reject[3]=!w_parse || f_numeric(w_ego);
    w_reject[4]=!f_range(w_ego);
    w_reject[5]=f_numeric(w_snap);
    w_reject[6]=!f_range(w_snap);
    w_reject[7]=(w_x==64'h8000000000000000);
    w_reject[8]=!f_pos(w_x) || w_v>LPARA_SPEED ||
      !(w_a[31] ? 32'(~w_a+1'b1)<=LPARA_ACCEL : w_a<=LPARA_ACCEL_POS) ||
      w_tail>=8'(LPARA_TAILS) || w_schema!=32'd1 || w_pkt_schema!=32'd1;
    w_reject[9]=(w_count<8'(LPARA_COUNT_MIN) || w_count>8'(LPARA_COUNT_MAX));
    w_reject[10]=(w_compute>LPARA_COMPUTE);
    w_reject[11]=(w_ids[95:64]!=w_ids[63:32] || w_ids[95:64]!=w_ids[31:0]);
    w_reject[12]=1'b0;
    w_reject[13]=w_seq_valid && (w_seq_age[31] || w_seq_age=='0);
    w_reason=ENUM_RSN_OK;
    casez (w_reject)
      14'b?????????????1: w_reason=ENUM_RSN_CLK;
      14'b????????????10: w_reason=ENUM_RSN_NO_SAMPLE;
      14'b???????????100: w_reason=ENUM_RSN_TIMEOUT;
      14'b??????????1000: w_reason=ENUM_RSN_NUMERIC;
      14'b?????????10000: w_reason=ENUM_RSN_RANGE;
      14'b????????100000: w_reason=ENUM_RSN_NUMERIC;
      14'b???????1000000: w_reason=ENUM_RSN_RANGE;
      14'b??????10000000: w_reason=ENUM_RSN_NUMERIC;
      14'b?????100000000: w_reason=ENUM_RSN_RANGE;
      14'b????1000000000: w_reason=ENUM_RSN_OVERFLOW;
      14'b???10000000000: w_reason=ENUM_RSN_DEADLINE;
      14'b??100000000000: w_reason=ENUM_RSN_SNAPSHOT;
      14'b?1000000000000: w_reason=ENUM_RSN_CRC;
      14'b10000000000000: w_reason=ENUM_RSN_SEQUENCE;
      default: begin
        casez ({w_ego_age[31] || w_ego_age>LPARA_AGE,
          w_snap_age[31] || w_snap_age>LPARA_AGE || w_gen_age[31] || w_gen_snap[31],
          w_same && !w_freeze_age[31] && w_freeze_age>=LPARA_FREEZE &&
          w_distance>{33'd0,LPARA_MOVE}})
          3'b1??: w_reason=ENUM_RSN_EGO_AGE;
          3'b01?: w_reason=ENUM_RSN_FRESHNESS;
          3'b001: w_reason=ENUM_RSN_FREEZE;
          default: w_reason=ENUM_RSN_OK;
        endcase
      end
    endcase
    w_new_state=w_state;
    if (w_reason==ENUM_RSN_OK) begin
      w_new_state={1'b1,w_seq,1'b1,w_now,1'b1,w_snap_t,1'b1,w_new_sig,
        w_same ? w_freeze_since : w_now,w_same ? w_freeze_x : w_ego_x};
    end
    w_result={w_new_state,w_reason};
  end

  // State-only ready/valid; invalid data is always zero, including asynchronous reset.
  always_comb begin : p_com_outputs
    o_req_ready=1'b0;
    o_rsp_valid=1'b0;
    o_rsp_data='0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready=i_rst_n_core;
      ENUM_ST_RESP: begin
        o_rsp_valid=i_rst_n_core;
        if (i_rst_n_core) o_rsp_data=reg_resp;
      end
      default: begin end
    endcase
  end

  // Capture once, drain private arithmetic, hold response until consumption.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state=reg_fsm_ctrl_current_state;
    w_req_nxt=reg_req;
    w_resp_nxt=reg_resp;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      ENUM_ST_IDLE: if (i_req_valid) begin
        w_req_nxt=i_req_data;
        w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
      end
      ENUM_ST_ISSUE: if (w_arith_ready) w_fsm_ctrl_nxt_state=ENUM_ST_WAIT;
      ENUM_ST_WAIT: if (w_arith_rsp_valid) begin
        w_resp_nxt=w_result;
        w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
      end
      ENUM_ST_RESP: if (i_rsp_ready) begin
        w_resp_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      end
      default: begin
        w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
        w_req_nxt='0;
        w_resp_nxt='0;
      end
    endcase
  end

  // Local validity and payload clear together; wrapper owns persistent Ingress state.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT;
      reg_req<='0;
      reg_resp<='0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_req<=w_req_nxt;
      reg_resp<=w_resp_nxt;
    end
  end

  // Private accepted primitive; op8 computes serial clock regression without contention.
  // Only the op codes this block issues are built.
  m_tsmx_arith #(.PARA_OPS(9'h100)) u_tsmx_arith (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_arith_valid), .i_req_data(w_arith_req),
    .i_rsp_ready(w_arith_rsp_ready), .o_req_ready(w_arith_ready),
    .o_rsp_valid(w_arith_rsp_valid), .o_rsp_data(w_arith_rsp)
  );
endmodule
`default_nettype wire
