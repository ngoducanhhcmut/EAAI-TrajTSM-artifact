/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-02
 * Version      : 0.5
 * Description  : Golden-ordered state ownership, admission, helpers, reseal and independent timers.
 *                CLAUDE-OPT (31/10): the CSR status record is registered once (reg_sts_*);
 *                the combinational FSM/timer status chained into the CSR AXI write
 *                decision (20 LUT levels). CSR status becomes visible one clock later.
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_engine #(
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_G = 32'd8,
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_P = 32'd8,
  // Parameter Description: direct semantic port selection.
  // Parameter values: 0,1; default 0.
  // Parameter unit: count
  parameter logic [31:0] PARA_DIRECT = 32'd0
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [44672:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [37:0] o_rsp_data,
  input wire [31:0] i_time_us,
  input wire i_ack_valid,
  input wire [31:0] i_ack_seq,
  output logic o_brake,
  output logic o_heartbeat,
  input wire [7:0] i_parse_reason,
  output logic o_cmd_valid,
  output logic [1896:0] o_cmd_data,
  input wire i_cmd_ready,
  input wire [15:0] i_axi_awaddr,
  input wire [2:0] i_axi_awprot,
  input wire i_axi_awvalid,
  input wire [31:0] i_axi_wdata,
  input wire [3:0] i_axi_wstrb,
  input wire i_axi_wvalid,
  input wire i_axi_bready,
  input wire [15:0] i_axi_araddr,
  input wire [2:0] i_axi_arprot,
  input wire i_axi_arvalid,
  input wire i_axi_rready,
  output logic o_axi_awready,
  output logic o_axi_wready,
  output logic o_axi_bvalid,
  output logic [1:0] o_axi_bresp,
  output logic o_axi_arready,
  output logic o_axi_rvalid,
  output logic [1:0] o_axi_rresp,
  output logic [31:0] o_axi_rdata,
  output logic o_int_irq,
  input wire [9:0] i_log_idx,
  input wire i_log_valid,
  input wire i_log_ready,
  output logic o_log_ready,
  output logic [1055:0] o_log_data,
  output logic o_log_valid
);
  typedef enum logic [75:0] {
    ENUM_ST_BOOT = 76'h1,
    ENUM_ST_IDLE = 76'h2,
    ENUM_ST_START = 76'h4,
    ENUM_ST_TLOG = 76'h8,
    ENUM_ST_TLOGW = 76'h10,
    ENUM_ST_BIST = 76'h20,
    ENUM_ST_BISTW = 76'h40,
    ENUM_ST_HEALTH = 76'h80,
    ENUM_ST_HEALTHW = 76'h100,
    ENUM_ST_PENDING = 76'h200,
    ENUM_ST_OLDCHK = 76'h400,
    ENUM_ST_OLDCHKW = 76'h800,
    ENUM_ST_CRC = 76'h1000,
    ENUM_ST_CRCW = 76'h2000,
    ENUM_ST_INGRESS = 76'h4000,
    ENUM_ST_INGRESSW = 76'h8000,
    ENUM_ST_ADMIT = 76'h10000,
    ENUM_ST_CONTEXT = 76'h20000,
    ENUM_ST_CONTEXTW = 76'h40000,
    ENUM_ST_SNAP = 76'h80000,
    ENUM_ST_SNAPW = 76'h100000,
    ENUM_ST_TRAJ = 76'h200000,
    ENUM_ST_TRAJW = 76'h400000,
    ENUM_ST_SEAL = 76'h800000,
    ENUM_ST_SEALW = 76'h1000000,
    ENUM_ST_NEWCHK = 76'h2000000,
    ENUM_ST_NEWCHKW = 76'h4000000,
    ENUM_ST_SPLICE0 = 76'h8000000,
    ENUM_ST_SPLICE = 76'h10000000,
    ENUM_ST_SPLICEW = 76'h20000000,
    ENUM_ST_REACT0 = 76'h40000000,
    ENUM_ST_REACT = 76'h80000000,
    ENUM_ST_REACTW = 76'h100000000,
    ENUM_ST_NOM0 = 76'h200000000,
    ENUM_ST_NPROP = 76'h400000000,
    ENUM_ST_NPROPW = 76'h800000000,
    ENUM_ST_NOM = 76'h1000000000,
    ENUM_ST_NOMW = 76'h2000000000,
    ENUM_ST_OVERRIDE = 76'h4000000000,
    ENUM_ST_FALLBACK = 76'h8000000000,
    ENUM_ST_FALLBACKW = 76'h10000000000,
    ENUM_ST_SEL = 76'h20000000000,
    ENUM_ST_SELW = 76'h40000000000,
    ENUM_ST_TAIL0 = 76'h80000000000,
    ENUM_ST_BRIDGE = 76'h100000000000,
    ENUM_ST_BRIDGEW = 76'h200000000000,
    ENUM_ST_BRIDGE0 = 76'h400000000000,
    ENUM_ST_BGEOM = 76'h800000000000,
    ENUM_ST_BGEOMW = 76'h1000000000000,
    ENUM_ST_PROP = 76'h2000000000000,
    ENUM_ST_PROPW = 76'h4000000000000,
    ENUM_ST_TAIL = 76'h8000000000000,
    ENUM_ST_TAILW = 76'h10000000000000,
    ENUM_ST_TSEL = 76'h20000000000000,
    ENUM_ST_TSELW = 76'h40000000000000,
    ENUM_ST_REUSE0 = 76'h80000000000000,
    ENUM_ST_RECHK = 76'h100000000000000,
    ENUM_ST_RECHKW = 76'h200000000000000,
    ENUM_ST_REPLAY0 = 76'h400000000000000,
    ENUM_ST_REPLAY = 76'h800000000000000,
    ENUM_ST_REPLAYW = 76'h1000000000000000,
    ENUM_ST_SUPER = 76'h2000000000000000,
    ENUM_ST_SUPERW = 76'h4000000000000000,
    ENUM_ST_COMMIT0 = 76'h8000000000000000,
    ENUM_ST_NEWHASH = 76'h10000000000000000,
    ENUM_ST_NEWHASHW = 76'h20000000000000000,
    ENUM_ST_NEWCERT = 76'h40000000000000000,
    ENUM_ST_RESEAL = 76'h80000000000000000,
    ENUM_ST_RESEALW = 76'h100000000000000000,
    ENUM_ST_RECORD = 76'h200000000000000000,
    ENUM_ST_RECORDW = 76'h400000000000000000,
    ENUM_ST_ARB0 = 76'h800000000000000000,
    ENUM_ST_ARB = 76'h1000000000000000000,
    ENUM_ST_ARBW = 76'h2000000000000000000,
    ENUM_ST_DELIVER = 76'h4000000000000000000,
    ENUM_ST_DRAIN = 76'h8000000000000000000
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [44672:0] reg_req, w_req_nxt;
  logic [7:0] reg_parse_reason, w_parse_reason_nxt;
  logic reg_active, w_active_nxt;
  logic [331:0] reg_ing, w_ing_nxt;
  logic [331:0] reg_proposal, w_proposal_nxt;
  logic [2:0] reg_mode, w_mode_nxt;
  logic [1:0] reg_good, w_good_nxt;
  logic reg_fault, w_fault_nxt;
  logic reg_pending_valid, w_pending_valid_nxt;
  logic [559:0] reg_pending_plan, w_pending_plan_nxt;
  logic [1216:0] reg_pending_cert, w_pending_cert_nxt;
  logic [31:0] reg_issued, w_issued_nxt;
  logic reg_backup_valid, w_backup_valid_nxt;
  logic [559:0] reg_backup_plan, w_backup_plan_nxt;
  logic [1216:0] reg_backup_cert, w_backup_cert_nxt;
  logic [7:0] reg_reason, w_reason_nxt;
  logic [7:0] reg_commit, w_commit_nxt;
  logic [7:0] reg_cid, w_cid_nxt;
  logic [7:0] reg_label, w_label_nxt;
  logic [7:0] reg_tail, w_tail_nxt;
  logic reg_healthy, w_healthy_nxt;
  logic reg_reuse, w_reuse_nxt;
  logic [8199:0] reg_world, w_world_nxt;
  logic [383:0] reg_lane, w_lane_nxt;
  logic [8199:0] reg_lead, w_lead_nxt;
  logic [703:0] reg_bridge, w_bridge_nxt;
  logic [255:0] reg_context, w_context_nxt;
  logic [255:0] reg_snapshot, w_snapshot_nxt;
  logic [255:0] reg_trajectory, w_trajectory_nxt;
  logic [255:0] reg_seal, w_seal_nxt;
  logic [559:0] reg_new_plan, w_new_plan_nxt;
  logic [1216:0] reg_new_cert, w_new_cert_nxt;
  logic [37:0] reg_resp_data, w_resp_data_nxt;
  logic [37:0] reg_final_rsp, w_final_rsp_nxt;
  logic reg_resp_valid, w_resp_valid_nxt;
  logic [1896:0] reg_cmd, w_cmd_nxt;
  logic reg_cmd_valid, w_cmd_valid_nxt;
  logic [31:0] reg_count, w_count_nxt;
  logic [31:0] reg_lost, w_lost_nxt;
  logic reg_deadline, w_deadline_nxt;
  logic reg_override, w_override_nxt;
  logic reg_live_bad, w_live_bad_nxt;
  logic [31:0] reg_tick, w_tick_nxt;
  logic reg_tick_valid, w_tick_valid_nxt;
  logic [31:0] reg_heartbeat_time, w_heartbeat_time_nxt;
  logic reg_heartbeat, w_heartbeat_nxt;
  logic reg_heartbeat_en, w_heartbeat_en_nxt;
  logic [7:0] reg_timer_code, w_timer_code_nxt;
  logic reg_timer_valid, w_timer_valid_nxt;
  logic reg_ing_par, w_ing_par_nxt;
  logic reg_pending_plan_par, w_pending_plan_par_nxt;
  logic reg_pending_cert_par, w_pending_cert_par_nxt;
  logic reg_backup_plan_par, w_backup_plan_par_nxt;
  logic reg_backup_cert_par, w_backup_cert_par_nxt;
  logic reg_ctrl_par, w_ctrl_par_nxt;
  logic reg_bist_wait, w_bist_wait_nxt;
  logic reg_csr_rst, w_csr_rst_nxt;
  logic reg_dup_sent, w_dup_sent_nxt;
  logic reg_main_sent, w_main_sent_nxt;
  logic reg_dup_done, w_dup_done_nxt;
  logic reg_main_done, w_main_done_nxt;
  logic reg_dup_result, w_dup_result_nxt;
  logic reg_lane_good, w_lane_good_nxt;
  logic reg_replay_full, w_replay_full_nxt;
  logic [1055:0] reg_replay_event, w_replay_event_nxt;
  logic [31:0] reg_log_drops, w_log_drops_nxt;
  logic w_b1_req_valid, w_b1_req_ready, w_b1_resp_valid;
  logic [1373:0] w_b1_req_data;
  logic [339:0] w_b1_resp_data;
  logic w_b2_req_valid, w_b2_req_ready, w_b2_resp_valid;
  logic [815:0] w_b2_req_data;
  logic [0:0] w_b2_resp_data;
  logic w_b9_req_valid, w_b9_req_ready, w_b9_resp_valid;
  logic [2903:0] w_b9_req_data;
  logic [7:0] w_b9_resp_data;
  logic w_b7_req_valid, w_b7_req_ready, w_b7_resp_valid;
  logic [15:0] w_b7_req_data;
  logic [15:0] w_b7_resp_data;
  logic w_b8_req_valid, w_b8_req_ready, w_b8_resp_valid;
  logic [43:0] w_b8_req_data;
  logic [7:0] w_b8_resp_data;
  logic w_arb_req_valid, w_arb_req_ready, w_arb_resp_valid;
  logic [3862:0] w_arb_req_data;
  logic [1996:0] w_arb_resp_data;
  logic w_rec_req_valid, w_rec_req_ready, w_rec_resp_valid;
  logic [1055:0] w_rec_req_data;
  logic [31:0] w_rec_resp_data;
  logic w_health_req_valid, w_health_req_ready, w_health_resp_valid;
  logic [33823:0] w_health_req_data;
  logic [0:0] w_health_resp_data;
  logic w_arb_brake;
  logic [3:0] w_config;
  logic w_sts_valid, reg_sts_valid;
  logic [114:0] w_sts_data, reg_sts_data;
  logic [31:0] w_now,w_delay,w_phase,w_xerr;
  logic [31:0] reg_xph,reg_xn,reg_xm,reg_xerr;
  logic [64:0] reg_xprod,reg_xmprod;
  logic reg_hs_crc,reg_hs_ctx,reg_hs_snap,reg_hs_traj,reg_hs_seal,reg_hs_newh,reg_hs_reseal;
  logic reg_ss_nom,reg_ss_tail,reg_ms_nprop;
  logic [255:0] w_ego;
  logic [720:0] w_packet;
  logic [559:0] w_plan;
  logic [1216:0] w_cert;
  logic [31:0] w_tickdiff,w_remaining,w_ackage,w_applydiff;
  logic w_explicit,w_cap,w_rst,w_live,w_clockbad,w_tick,w_timer;
  logic [7:0] w_timer_code;
  logic w_ack;
  logic w_replay;
  logic w_fsm_valid;
  logic w_hash_req_valid,w_hash_req_ready,w_hash_resp_valid;
  logic [7:0] w_hash_op;
  logic [10:0] w_hash_len;
  logic [8415:0] w_hash_data;
  logic [288:0] w_hash_resp_data;
  logic w_math_req_valid,w_math_req_ready,w_math_resp_valid,w_math_ok;
  logic [2:0] w_math_op;
  logic [8199:0] w_math_world,w_math_out;
  logic [31:0] w_math_delay;
  logic [559:0] w_math_plan;
  logic [703:0] w_math_bridge;
  logic [95:0] w_math_pose;
  logic w_sweep_req_valid,w_sweep_req_ready,w_sweep_resp_valid;
  logic [127:0] w_sweep_pose;
  logic [8199:0] w_sweep_world;
  logic [383:0] w_sweep_lane;
  logic [1:0] w_sweep_kind;
  logic [15:0] w_sweep_mask;
  logic w_dup_req_valid,w_dup_req_ready,w_dup_resp_valid;
  logic [15:0] w_dup_mask;
  logic [255:0] w_event_reason,w_event_mode;
  logic [5:0] w_reason_len,w_mode_len;

  // Explicit unsigned-vector sign extension and serial comparison.
  function automatic logic [159:0] f_s32(input logic [31:0] w_x);
    f_s32={{128{w_x[31]}},w_x};
  endfunction
  function automatic logic [159:0] f_s64(input logic [63:0] w_x);
    f_s64={{96{w_x[63]}},w_x};
  endfunction
  function automatic logic f_lt(input logic [63:0] w_a,w_b);
    f_lt=(w_a[63]!=w_b[63]) ? w_a[63] : w_a<w_b;
  endfunction
  // CLAUDE-FIX-004: v%20000 = 32*((v>>5)%625) + v[4:0]; (v>>5)%625 from three 9-bit
  // residue tables, so the tick update is a shallow ROM-add instead of a 32-bit divider.
  function automatic logic [31:0] f_mod20k(input logic [31:0] w_v);
    f_mod20k = w_v % 32'd20000;
  endfunction
  function automatic logic [31:0] f_diff(input logic [31:0] w_a,w_b);
    f_diff=32'(w_a-w_b);
  endfunction
  function automatic logic [63:0] f_abs(input logic [63:0] w_x);
    f_abs=w_x[63] ? 64'(~w_x+64'd1) : w_x;
  endfunction
  // Immutable direct request field offsets follow spec 9.2 exactly.
  assign {w_now,w_ego,w_packet,w_cert} = reg_req[44672:42447];
  assign w_plan=w_packet[719:160];
  assign w_explicit=reg_req[33862] || reg_req[33861];
  assign w_cap=reg_req[33859];
  assign w_rst=reg_req[33857] || w_config[1] || reg_csr_rst;
  assign w_delay=f_diff(w_plan[239:208],w_ego[255:224]);
  assign w_phase=f_diff(w_now,reg_backup_plan[239:208]);
  // n=ceil(phase/20000); xerr=max(640, n+ceil((n*(n-1))/100)+11) in 32-bit wrap arithmetic.
  assign w_xerr=32'(reg_xn+32'(reg_xmprod[64:39])+32'd11)>32'd640
    ? 32'(reg_xn+32'(reg_xmprod[64:39])+32'd11) : 32'd640;
  // Live state is admitted before codec, motion or candidate work.
  assign w_live=w_ego[255:224]==w_now
    && f_abs(w_ego[223:160])<=64'd10000000000
    && f_abs(w_ego[95:32])<=64'd10000000000
    && w_ego[159:128]<=32'd10000000 && w_ego[31:0]<=32'd10000000
    && !f_lt({{32{w_ego[127]}},w_ego[127:96]},64'(-64'd8000000))
    // A8 (02/11): live acceleration in [-8,+2] m/s^2 (golden live_ego_valid)
    && !f_lt(64'd2000000,{{32{w_ego[127]}},w_ego[127:96]});
  // Rollback uses only the last committed decision epoch.
  assign w_clockbad=reg_ing[298] && f_diff(w_now,reg_ing[297:266])>=32'h80000000;
  // Tick arithmetic uses serial half-wrap ordering; no unsigned epoch ordering is substituted.
  assign w_tickdiff=f_diff(i_time_us,reg_tick);
  assign w_tick=reg_tick_valid && !w_tickdiff[31] && w_tickdiff>=32'd20000;
  assign w_remaining=f_diff(reg_pending_cert[671:640],i_time_us);
  assign w_ackage=f_diff(i_time_us,reg_issued);
  assign w_applydiff=f_diff(i_time_us,reg_pending_plan[239:208]);
  assign w_ack=i_ack_valid && i_ack_seq==reg_pending_plan[559:528];
  assign w_replay=reg_pending_valid && i_ack_valid && !w_ack;
  // Regular subcycle service is supplemented at exact safety boundaries (spec6.2).
  assign w_timer=reg_pending_valid && (w_tick || w_ack || w_timer_code==8'd29 || w_timer_code==8'd30);
  // Cached immutable records were hashed at admission; timer service has no codec dependency.
  always_comb begin : p_com_timer
    w_timer_code=8'd32;
    casez({w_remaining[31] || w_remaining==32'd0,
           !w_ack && !w_ackage[31] && w_ackage>=32'd40000,
           w_ack && !w_applydiff[31]})
      3'b1??: w_timer_code=8'd29;
      3'b01?: w_timer_code=8'd30;
      3'b001: w_timer_code=8'd31;
      default: w_timer_code=8'd32;
    endcase
  end
  // Golden Event string payloads, zero padded on the right.
  always_comb begin : p_com_event
    w_event_reason='0; w_reason_len='0; w_event_mode='0; w_mode_len='0;
    case(reg_reason)
      8'd0: begin w_reason_len=6'd2; w_event_reason=256'h6f6b000000000000000000000000000000000000000000000000000000000000; end
      8'd1: begin w_reason_len=6'd11; w_event_reason=256'h636c6f636b5f7265736574000000000000000000000000000000000000000000; end
      8'd2: begin w_reason_len=6'd16; w_event_reason=256'h667265657a655f6e6f5f73616d706c6500000000000000000000000000000000; end
      8'd3: begin w_reason_len=6'd7; w_event_reason=256'h74696d656f757400000000000000000000000000000000000000000000000000; end
      8'd4: begin w_reason_len=6'd7; w_event_reason=256'h6e756d6572696300000000000000000000000000000000000000000000000000; end
      8'd5: begin w_reason_len=6'd12; w_event_reason=256'h72616e67655f736368656d610000000000000000000000000000000000000000; end
      8'd6: begin w_reason_len=6'd8; w_event_reason=256'h6f766572666c6f77000000000000000000000000000000000000000000000000; end
      8'd7: begin w_reason_len=6'd8; w_event_reason=256'h646561646c696e65000000000000000000000000000000000000000000000000; end
      8'd8: begin w_reason_len=6'd8; w_event_reason=256'h736e617073686f74000000000000000000000000000000000000000000000000; end
      8'd9: begin w_reason_len=6'd3; w_event_reason=256'h6372630000000000000000000000000000000000000000000000000000000000; end
      8'd10: begin w_reason_len=6'd8; w_event_reason=256'h73657175656e6365000000000000000000000000000000000000000000000000; end
      8'd11: begin w_reason_len=6'd13; w_event_reason=256'h65676f5f66726573686e65737300000000000000000000000000000000000000; end
      8'd12: begin w_reason_len=6'd9; w_event_reason=256'h66726573686e6573730000000000000000000000000000000000000000000000; end
      8'd13: begin w_reason_len=6'd6; w_event_reason=256'h667265657a650000000000000000000000000000000000000000000000000000; end
      8'd14: begin w_reason_len=6'd5; w_event_reason=256'h72616e6765000000000000000000000000000000000000000000000000000000; end
      8'd15: begin w_reason_len=6'd15; w_event_reason=256'h70686173655f616c69676e6d656e740000000000000000000000000000000000; end
      8'd16: begin w_reason_len=6'd7; w_event_reason=256'h686f72697a6f6e00000000000000000000000000000000000000000000000000; end
      8'd17: begin w_reason_len=6'd10; w_event_reason=256'h7472616a6563746f727900000000000000000000000000000000000000000000; end
      8'd18: begin w_reason_len=6'd10; w_event_reason=256'h6c616e655f72616e676500000000000000000000000000000000000000000000; end
      8'd19: begin w_reason_len=6'd15; w_event_reason=256'h6f626a6563745f6f766572666c6f770000000000000000000000000000000000; end
      8'd20: begin w_reason_len=6'd4; w_event_reason=256'h6c616e6500000000000000000000000000000000000000000000000000000000; end
      8'd21: begin w_reason_len=6'd12; w_event_reason=256'h6f626a6563745f72616e67650000000000000000000000000000000000000000; end
      8'd22: begin w_reason_len=6'd18; w_event_reason=256'h6f626a6563745f73706565645f626f756e640000000000000000000000000000; end
      8'd23: begin w_reason_len=6'd4; w_event_reason=256'h74696d6500000000000000000000000000000000000000000000000000000000; end
      8'd24: begin w_reason_len=6'd10; w_event_reason=256'h73657061726174696f6e00000000000000000000000000000000000000000000; end
      8'd25: begin w_reason_len=6'd7; w_event_reason=256'h62696e64696e6700000000000000000000000000000000000000000000000000; end
      8'd26: begin w_reason_len=6'd6; w_event_reason=256'h7265706c61790000000000000000000000000000000000000000000000000000; end
      8'd27: begin w_reason_len=6'd15; w_event_reason=256'h636f6e746578745f62696e64696e670000000000000000000000000000000000; end
      8'd28: begin w_reason_len=6'd11; w_event_reason=256'h6c656173655f626f756e64000000000000000000000000000000000000000000; end
      8'd29: begin w_reason_len=6'd18; w_event_reason=256'h6578706972795f61745f6578656375746f720000000000000000000000000000; end
      8'd30: begin w_reason_len=6'd11; w_event_reason=256'h61636b5f74696d656f7574000000000000000000000000000000000000000000; end
      8'd31: begin w_reason_len=6'd9; w_event_reason=256'h636f6d6d69747465640000000000000000000000000000000000000000000000; end
      8'd32: begin w_reason_len=6'd7; w_event_reason=256'h70656e64696e6700000000000000000000000000000000000000000000000000; end
      8'd33: begin w_reason_len=6'd10; w_event_reason=256'h6c6174655f6170706c7900000000000000000000000000000000000000000000; end
      8'd34: begin w_reason_len=6'd6; w_event_reason=256'h6578706972790000000000000000000000000000000000000000000000000000; end
      8'd35: begin w_reason_len=6'd10; w_event_reason=256'h6e6f5f70656e64696e6700000000000000000000000000000000000000000000; end
      8'd36: begin w_reason_len=6'd6; w_event_reason=256'h73706c6963650000000000000000000000000000000000000000000000000000; end
      8'd37: begin w_reason_len=6'd11; w_event_reason=256'h667474695f627564676574000000000000000000000000000000000000000000; end
      8'd38: begin w_reason_len=6'd8; w_event_reason=256'h67656f6d65747279000000000000000000000000000000000000000000000000; end
      8'd39: begin w_reason_len=6'd10; w_event_reason=256'h6361706162696c69747900000000000000000000000000000000000000000000; end
      8'd40: begin w_reason_len=6'd6; w_event_reason=256'h6865616c74680000000000000000000000000000000000000000000000000000; end
      8'd41: begin w_reason_len=6'd5; w_event_reason=256'h7265736574000000000000000000000000000000000000000000000000000000; end
      8'd42: begin w_reason_len=6'd9; w_event_reason=256'h6e6f5f6261636b75700000000000000000000000000000000000000000000000; end
      8'd43: begin w_reason_len=6'd8; w_event_reason=256'h65676f5f6c697665000000000000000000000000000000000000000000000000; end
      8'd44: begin w_reason_len=6'd6; w_event_reason=256'h6272696467650000000000000000000000000000000000000000000000000000; end
      default: begin w_reason_len=6'd7; w_event_reason={56'h6e756d65726963,200'd0}; end
    endcase
    case(reg_mode)
      3'd0: begin w_mode_len=6'd2; w_event_mode=256'h4c30000000000000000000000000000000000000000000000000000000000000; end
      3'd1: begin w_mode_len=6'd2; w_event_mode=256'h4c31000000000000000000000000000000000000000000000000000000000000; end
      3'd2: begin w_mode_len=6'd2; w_event_mode=256'h4c32000000000000000000000000000000000000000000000000000000000000; end
      3'd3: begin w_mode_len=6'd2; w_event_mode=256'h4c33000000000000000000000000000000000000000000000000000000000000; end
      3'd4: begin w_mode_len=6'd4; w_event_mode=256'h484f4c4400000000000000000000000000000000000000000000000000000000; end
      3'd5: begin w_mode_len=6'd8; w_event_mode=256'h5245434f56455259000000000000000000000000000000000000000000000000; end
      default: begin w_mode_len=6'd2; w_event_mode={16'h4c33,240'd0}; end
    endcase
  end
  // Only declared one-hot controller encodings can retain transaction authority.
  always_comb begin : p_com_fsm_guard
    w_fsm_valid=1'b0;
    case(reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT,
      ENUM_ST_IDLE,
      ENUM_ST_START,
      ENUM_ST_TLOG,
      ENUM_ST_TLOGW,
      ENUM_ST_BIST,
      ENUM_ST_BISTW,
      ENUM_ST_HEALTH,
      ENUM_ST_HEALTHW,
      ENUM_ST_PENDING,
      ENUM_ST_OLDCHK,
      ENUM_ST_OLDCHKW,
      ENUM_ST_CRC,
      ENUM_ST_CRCW,
      ENUM_ST_INGRESS,
      ENUM_ST_INGRESSW,
      ENUM_ST_ADMIT,
      ENUM_ST_CONTEXT,
      ENUM_ST_CONTEXTW,
      ENUM_ST_SNAP,
      ENUM_ST_SNAPW,
      ENUM_ST_TRAJ,
      ENUM_ST_TRAJW,
      ENUM_ST_SEAL,
      ENUM_ST_SEALW,
      ENUM_ST_NEWCHK,
      ENUM_ST_NEWCHKW,
      ENUM_ST_SPLICE0,
      ENUM_ST_SPLICE,
      ENUM_ST_SPLICEW,
      ENUM_ST_REACT0,
      ENUM_ST_REACT,
      ENUM_ST_REACTW,
      ENUM_ST_NOM0,
      ENUM_ST_NPROP,
      ENUM_ST_NPROPW,
      ENUM_ST_NOM,
      ENUM_ST_NOMW,
      ENUM_ST_OVERRIDE,
      ENUM_ST_FALLBACK,
      ENUM_ST_FALLBACKW,
      ENUM_ST_SEL,
      ENUM_ST_SELW,
      ENUM_ST_TAIL0,
      ENUM_ST_BRIDGE,
      ENUM_ST_BRIDGEW,
      ENUM_ST_BRIDGE0,
      ENUM_ST_BGEOM,
      ENUM_ST_BGEOMW,
      ENUM_ST_PROP,
      ENUM_ST_PROPW,
      ENUM_ST_TAIL,
      ENUM_ST_TAILW,
      ENUM_ST_TSEL,
      ENUM_ST_TSELW,
      ENUM_ST_REUSE0,
      ENUM_ST_RECHK,
      ENUM_ST_RECHKW,
      ENUM_ST_REPLAY0,
      ENUM_ST_REPLAY,
      ENUM_ST_REPLAYW,
      ENUM_ST_SUPER,
      ENUM_ST_SUPERW,
      ENUM_ST_COMMIT0,
      ENUM_ST_NEWHASH,
      ENUM_ST_NEWHASHW,
      ENUM_ST_NEWCERT,
      ENUM_ST_RESEAL,
      ENUM_ST_RESEALW,
      ENUM_ST_RECORD,
      ENUM_ST_RECORDW,
      ENUM_ST_ARB0,
      ENUM_ST_ARB,
      ENUM_ST_ARBW,
      ENUM_ST_DELIVER,
      ENUM_ST_DRAIN: w_fsm_valid=1'b1;
      default: w_fsm_valid=1'b0;
    endcase
  end

  // Defaults retain state; unused FSM encodings recover through BOOT.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_req_nxt = reg_req;
    w_parse_reason_nxt = reg_parse_reason;
    w_active_nxt = reg_active;
    w_ing_nxt = reg_ing;
    w_proposal_nxt = reg_proposal;
    w_mode_nxt = reg_mode;
    w_good_nxt = reg_good;
    w_fault_nxt = reg_fault;
    w_pending_valid_nxt = reg_pending_valid;
    w_pending_plan_nxt = reg_pending_plan;
    w_pending_cert_nxt = reg_pending_cert;
    w_issued_nxt = reg_issued;
    w_backup_valid_nxt = reg_backup_valid;
    w_backup_plan_nxt = reg_backup_plan;
    w_backup_cert_nxt = reg_backup_cert;
    w_reason_nxt = reg_reason;
    w_commit_nxt = reg_commit;
    w_cid_nxt = reg_cid;
    w_label_nxt = reg_label;
    w_tail_nxt = reg_tail;
    w_healthy_nxt = reg_healthy;
    w_reuse_nxt = reg_reuse;
    w_world_nxt = reg_world;
    w_lane_nxt = reg_lane;
    w_lead_nxt = reg_lead;
    w_bridge_nxt = reg_bridge;
    w_context_nxt = reg_context;
    w_snapshot_nxt = reg_snapshot;
    w_trajectory_nxt = reg_trajectory;
    w_seal_nxt = reg_seal;
    w_new_plan_nxt = reg_new_plan;
    w_new_cert_nxt = reg_new_cert;
    w_resp_data_nxt = reg_resp_data;
    w_final_rsp_nxt = reg_final_rsp;
    w_resp_valid_nxt = reg_resp_valid;
    w_cmd_nxt = reg_cmd;
    w_cmd_valid_nxt = reg_cmd_valid;
    w_count_nxt = reg_count;
    w_lost_nxt = reg_lost;
    w_deadline_nxt = reg_deadline;
    w_override_nxt = reg_override;
    w_live_bad_nxt = reg_live_bad;
    w_tick_nxt = reg_tick;
    w_tick_valid_nxt = reg_tick_valid;
    w_heartbeat_time_nxt = reg_heartbeat_time;
    w_heartbeat_nxt = reg_heartbeat;
    w_heartbeat_en_nxt = reg_heartbeat_en;
    w_timer_code_nxt = reg_timer_code;
    w_timer_valid_nxt = reg_timer_valid;
    w_ing_par_nxt = reg_ing_par;
    w_pending_plan_par_nxt = reg_pending_plan_par;
    w_pending_cert_par_nxt = reg_pending_cert_par;
    w_backup_plan_par_nxt = reg_backup_plan_par;
    w_backup_cert_par_nxt = reg_backup_cert_par;
    w_ctrl_par_nxt = reg_ctrl_par;
    w_bist_wait_nxt = reg_bist_wait;
    w_csr_rst_nxt = reg_csr_rst;
    w_dup_sent_nxt = reg_dup_sent;
    w_main_sent_nxt = reg_main_sent;
    w_dup_done_nxt = reg_dup_done;
    w_main_done_nxt = reg_main_done;
    w_dup_result_nxt = reg_dup_result;
    w_lane_good_nxt = reg_lane_good;
    w_replay_full_nxt = reg_replay_full;
    w_replay_event_nxt = reg_replay_event;
    w_log_drops_nxt = reg_log_drops;
    o_req_ready=i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE
      && !reg_resp_valid && !reg_cmd_valid && !reg_bist_wait && (PARA_DIRECT!=32'd0 || !w_config[0])
      && !reg_replay_full && reg_log_drops==32'd0 && !w_replay
      && (PARA_DIRECT!=32'd0 || (w_config[3] && w_config[2]));
    o_rsp_valid=i_rst_n_core && reg_resp_valid;
    o_rsp_data=o_rsp_valid ? reg_resp_data : 38'd0;
    o_cmd_valid=i_rst_n_core && reg_cmd_valid;
    // CLAUDE-OPT (31/10): ungated; m_tsmx_io loads it only on i_cmd_valid && o_cmd_ready.
    o_cmd_data=reg_cmd;
    o_brake=!i_rst_n_core || reg_override || w_arb_brake || reg_final_rsp[9];
    o_heartbeat=i_rst_n_core && reg_heartbeat_en && reg_heartbeat;
    w_hash_req_valid=1'b0; w_hash_op='0; w_hash_len='0;
    w_math_req_valid=1'b0; w_math_op='0;
    w_math_delay='0; w_math_plan=reg_backup_plan;
    w_sweep_req_valid=1'b0;
    w_dup_req_valid=1'b0;
    w_sweep_kind=2'd0;
    w_b1_req_valid=1'b0; w_b1_req_data='0; w_b2_req_valid=1'b0; w_b2_req_data='0;
    w_b9_req_valid=1'b0; w_b9_req_data='0; w_b7_req_valid=1'b0; w_b7_req_data='0;
    w_b8_req_valid=1'b0; w_b8_req_data='0; w_arb_req_valid=1'b0; w_arb_req_data='0;
    w_rec_req_valid=1'b0; w_rec_req_data='0; w_health_req_valid=1'b0; w_health_req_data='0;
    w_sts_valid=1'b0; w_sts_data='0;
    if(w_config[0]) w_bist_wait_nxt=1'b1;
    if(w_replay) begin
      if(!reg_replay_full) begin
        w_replay_full_nxt=1'b1;
        w_replay_event_nxt={1'b1,3'd4,1'b0,6'd0,224'd0,i_time_us,
          1'b1,6'd6,48'h7265706c6179,208'd0,1'b1,w_mode_len,w_event_mode,
          1'b0,6'd0,248'd0,reg_cid};
      end else if(reg_log_drops!=32'hffffffff) w_log_drops_nxt=32'(reg_log_drops+32'd1);
    end
    if(reg_resp_valid && i_rsp_ready) begin w_resp_valid_nxt=1'b0; w_resp_data_nxt='0; end
    if(reg_cmd_valid && i_cmd_ready) begin w_cmd_valid_nxt=1'b0; w_cmd_nxt='0; end
    if(w_tick) w_tick_nxt=32'(i_time_us-f_mod20k(w_tickdiff));
    if((reg_mode==3'd1 || (!reg_pending_valid && (reg_mode==3'd0 || reg_mode==3'd5)))
      && reg_backup_valid && (f_diff(reg_backup_cert[671:640],i_time_us)==32'd0
      || f_diff(reg_backup_cert[671:640],i_time_us)>=32'h80000000)) w_override_nxt=1'b1;
    if(reg_heartbeat_en && f_diff(i_time_us,reg_heartbeat_time)<32'h80000000
       && f_diff(i_time_us,reg_heartbeat_time)>=32'd1000) begin
      w_heartbeat_nxt=!reg_heartbeat; w_heartbeat_time_nxt=i_time_us;
    end
    if(w_timer && w_timer_code!=8'd32) begin
      w_timer_valid_nxt=1'b1; w_timer_code_nxt=w_timer_code;
      w_pending_valid_nxt=1'b0;
      if(w_timer_code==8'd31) begin w_backup_valid_nxt=1'b1; w_backup_plan_nxt=reg_pending_plan; w_backup_cert_nxt=reg_pending_cert; end
      else w_override_nxt=1'b1;
      w_sts_valid=1'b1;
      w_sts_data={{reg_final_rsp[37:10],w_timer_code!=8'd31,w_timer_code,reg_heartbeat_en},
        reg_active,1'b0,w_timer_code==8'd31 || reg_backup_valid,reg_healthy,reg_healthy,
        reg_count,reg_lost,8'h04};
    end
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      ENUM_ST_IDLE: begin
        if(i_req_valid && o_req_ready) begin
        w_req_nxt = i_req_data;        w_parse_reason_nxt = i_parse_reason;        w_active_nxt = 1'b1;        w_count_nxt = 32'd1;        w_deadline_nxt = 1'b0;        w_live_bad_nxt = 1'b0;        w_reason_nxt = 8'd0;        w_commit_nxt = 8'd35;        w_reuse_nxt = 1'b0;        w_cid_nxt = 8'd15;        w_label_nxt = 8'd2;        w_tail_nxt = 8'd15;        if(!reg_tick_valid) begin
          w_tick_valid_nxt=1'b1;
          w_tick_nxt=32'(i_time_us-f_mod20k(i_time_us));
          w_heartbeat_time_nxt=i_time_us;
        end
        w_sts_valid=1'b1;
        w_sts_data={{reg_final_rsp[37:29],reg_mode,reg_cid,reg_label,reg_override,8'd35,reg_heartbeat_en},
          1'b1,reg_pending_valid,reg_backup_valid,reg_healthy,reg_healthy,32'd0,reg_lost,8'd0};
        w_fsm_ctrl_nxt_state = ENUM_ST_START;
        end
        if(reg_bist_wait && !reg_cmd_valid && !reg_resp_valid) w_fsm_ctrl_nxt_state=ENUM_ST_BIST;
        if((reg_replay_full || reg_log_drops!=32'd0) && !reg_cmd_valid && !reg_resp_valid) w_fsm_ctrl_nxt_state=ENUM_ST_TLOG;
      end
      ENUM_ST_START: begin
        if(!w_live || w_clockbad || reg_parse_reason!=8'd0) begin
          w_reason_nxt=reg_parse_reason!=8'd0 ? reg_parse_reason : (w_clockbad ? 8'd1 : 8'd43);
          w_commit_nxt=w_reason_nxt;
          if(w_clockbad) begin
            w_tick_valid_nxt=1'b1;
            w_tick_nxt=32'(i_time_us-f_mod20k(i_time_us));
            w_heartbeat_time_nxt=i_time_us;
          end
          w_healthy_nxt=1'b0; w_live_bad_nxt=1'b1;
          w_override_nxt=1'b1; w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0;
          w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;
        end else begin
          w_world_nxt='0;
          w_world_nxt[8199:8192]=8'd1;
          w_world_nxt[8191:7936]={w_ego[95:32],w_ego[31:0],32'd0,64'd4800000,
            w_ego[255:224]<32'd500000 ? 32'(32'd500000-w_ego[255:224]):32'd0,
            reg_req[33860] ? 32'(-32'd4000000):32'd0};
          w_lead_nxt=w_world_nxt;
          if(reg_req[33862]) w_world_nxt=reg_req[42446:34247];
          w_lane_nxt={64'hffffffffffe488c0,64'd1800000,64'd0,
            64'd950000,64'd50000,64'd500000};
          if(reg_req[33861]) w_lane_nxt=reg_req[34246:33863];
          if(!reg_req[33858]) begin
            w_healthy_nxt=1'b0; w_override_nxt=1'b1;
            w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0;
            w_fsm_ctrl_nxt_state=ENUM_ST_PENDING;
          end else w_fsm_ctrl_nxt_state=ENUM_ST_HEALTH;
        end
      end
      ENUM_ST_TLOG: begin
        w_rec_req_valid=1'b1;
        w_rec_req_data=reg_replay_full ? reg_replay_event : 1056'd0;
        if(w_rec_req_ready) begin
          if(reg_replay_full) w_replay_full_nxt=1'b0;
          else w_log_drops_nxt=32'(reg_log_drops-32'd1);
          w_fsm_ctrl_nxt_state=ENUM_ST_TLOGW;
        end
      end
      ENUM_ST_TLOGW: begin
        if(w_rec_resp_valid) begin
          w_lost_nxt=w_rec_resp_data;
          w_sts_valid=1'b1;
          w_sts_data={{reg_final_rsp[37:29],reg_mode,reg_cid,reg_label,reg_override,
            8'd26,reg_heartbeat_en},1'b0,reg_pending_valid,reg_backup_valid,reg_healthy,reg_healthy,reg_count,w_rec_resp_data,8'h08};
          w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        end
      end
      ENUM_ST_BIST: begin
        w_health_req_valid=1'b1; w_health_req_data={1'b1,11'd6,11'd6,31'd0,(^reg_ing),31'd0,(^reg_pending_plan),31'd0,(^reg_pending_cert),31'd0,(^reg_backup_plan),31'd0,(^reg_backup_cert),31'd0,(^{reg_mode,reg_good,reg_fault}),32576'd0,reg_ing_par,reg_pending_plan_par,reg_pending_cert_par,reg_backup_plan_par,reg_backup_cert_par,reg_ctrl_par,1018'd0,reg_lane_good,1'b1,(6'b000001 << reg_mode),1'b1};
        if(w_health_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_BISTW;
      end
      ENUM_ST_BISTW: begin
        if(w_health_resp_valid) begin
          w_bist_wait_nxt=1'b0; w_healthy_nxt=w_health_resp_data[0];
          w_sts_valid=1'b1;
          w_sts_data={{1'b0,8'd0,reg_mode,8'd15,8'd2,!w_health_resp_data[0],8'd35,w_health_resp_data[0]},
            1'b0,reg_pending_valid,reg_backup_valid,w_health_resp_data[0],1'b1,32'd0,reg_lost,8'h10};
          if(!w_health_resp_data[0]) begin
            w_override_nxt=1'b1; w_pending_valid_nxt=1'b0; w_backup_valid_nxt=1'b0;
            w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1;
            w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0;
          end
          w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        end
      end
      ENUM_ST_HEALTH: begin
        w_health_req_valid=1'b1; w_health_req_data=PARA_DIRECT!=32'd0 ? reg_req[33823:0] : {1'b1,11'd6,11'd6,31'd0,(^reg_ing),31'd0,(^reg_pending_plan),31'd0,(^reg_pending_cert),31'd0,(^reg_backup_plan),31'd0,(^reg_backup_cert),31'd0,(^{reg_mode,reg_good,reg_fault}),32576'd0,reg_ing_par,reg_pending_plan_par,reg_pending_cert_par,reg_backup_plan_par,reg_backup_cert_par,reg_ctrl_par,1018'd0,reg_lane_good,1'b1,(6'b000001 << reg_mode),1'b1};
        if(w_health_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_HEALTHW;
      end
      ENUM_ST_HEALTHW: begin
        if(w_health_resp_valid) begin
        w_healthy_nxt = w_health_resp_data[0] && reg_req[33858];
        w_fsm_ctrl_nxt_state = ENUM_ST_PENDING;
        end
      end
      ENUM_ST_PENDING: begin
        if(reg_timer_valid) begin w_commit_nxt=reg_timer_code;
          w_timer_valid_nxt=1'b0; end
        if(reg_pending_valid) w_fsm_ctrl_nxt_state=ENUM_ST_OLDCHK;
        else w_fsm_ctrl_nxt_state=ENUM_ST_CRC;
        if(reg_healthy==1'b0) begin w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0;
          w_override_nxt=1'b1; end
      end
      ENUM_ST_OLDCHK: begin
        w_b9_req_valid=1'b1; w_b9_req_data={1'b1,reg_pending_plan,reg_pending_cert,w_now,1'b1,1'b1,reg_issued,reg_req[33856],1'b1,reg_pending_plan[559:528],1'b0,256'd0,1'b0,reg_pending_cert[1215:960],reg_pending_cert[959:704],reg_pending_cert[255:0]};
        if(w_b9_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_OLDCHKW;
      end
      ENUM_ST_OLDCHKW: begin
        if(w_b9_resp_valid) begin
        w_commit_nxt=w_b9_resp_data;
        if(w_b9_resp_data==8'd31) begin w_backup_valid_nxt=1'b1; w_backup_plan_nxt=reg_pending_plan; w_backup_cert_nxt=reg_pending_cert; end
        if(w_b9_resp_data!=8'd32) w_pending_valid_nxt=1'b0;
        w_fsm_ctrl_nxt_state = ENUM_ST_CRC;
        end
      end
      ENUM_ST_CRC: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd0; w_hash_len=11'd86;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_CRCW;
      end
      ENUM_ST_CRCW: begin
        if(w_hash_resp_valid) begin
        w_seal_nxt = {224'd0,w_hash_resp_data[287:256]};
        w_fsm_ctrl_nxt_state = ENUM_ST_INGRESS;

        end
      end
      ENUM_ST_INGRESS: begin
        w_b1_req_valid=1'b1; w_b1_req_data={reg_ing,w_now,w_ego,w_packet,reg_seal[31:0],1'b1};
        if(w_b1_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_INGRESSW;
      end
      ENUM_ST_INGRESSW: begin
        if(w_b1_resp_valid) begin
        w_proposal_nxt = w_b1_resp_data[339:8];        w_reason_nxt = w_b1_resp_data[7:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_ADMIT;
        end
      end
      ENUM_ST_ADMIT: begin
        if(reg_reason==8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_CONTEXT;
        else w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;
      end
      ENUM_ST_CONTEXT: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd3; w_hash_len=11'd1049;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_CONTEXTW;
      end
      ENUM_ST_CONTEXTW: begin
        if(w_hash_resp_valid) begin
        w_context_nxt = w_hash_resp_data[255:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_SNAP;
          if(w_hash_resp_data[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
        end
      end
      ENUM_ST_SNAP: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd1; w_hash_len=11'd32;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_SNAPW;
      end
      ENUM_ST_SNAPW: begin
        if(w_hash_resp_valid) begin
        w_snapshot_nxt = w_hash_resp_data[255:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_TRAJ;
          if(w_hash_resp_data[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
        end
      end
      ENUM_ST_TRAJ: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd2; w_hash_len=11'd70;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_TRAJW;
      end
      ENUM_ST_TRAJW: begin
        if(w_hash_resp_valid) begin
        w_trajectory_nxt = w_hash_resp_data[255:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_SEAL;
          if(w_hash_resp_data[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
        end
      end
      ENUM_ST_SEAL: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd4; w_hash_len=11'd120;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_SEALW;
      end
      ENUM_ST_SEALW: begin
        if(w_hash_resp_valid) begin
        w_seal_nxt = w_hash_resp_data[255:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_NEWCHK;
          if(w_hash_resp_data[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
        end
      end
      ENUM_ST_NEWCHK: begin
        w_b9_req_valid=1'b1; w_b9_req_data={w_packet[720],w_plan,w_cert,w_now,1'b0,1'b0,32'd0,1'b0,1'b0,32'd0,1'b1,reg_context,1'b0,reg_snapshot,reg_trajectory,reg_seal};
        if(w_b9_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_NEWCHKW;
      end
      ENUM_ST_NEWCHKW: begin
        if(w_b9_resp_valid) begin
        w_reason_nxt = w_b9_resp_data;
        w_fsm_ctrl_nxt_state = ENUM_ST_SPLICE0;
        end
      end
      ENUM_ST_SPLICE0: begin
        if(reg_reason==8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_SPLICE;
        else w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;
      end
      ENUM_ST_SPLICE: begin
        w_b2_req_valid=1'b1; w_b2_req_data={w_ego,w_plan};
        if(w_b2_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_SPLICEW;
      end
      ENUM_ST_SPLICEW: begin
        if(w_b2_resp_valid) begin
        if(!w_b2_resp_data[0]) w_reason_nxt=8'd36;
        w_fsm_ctrl_nxt_state = ENUM_ST_REACT0;
        end
      end
      ENUM_ST_REACT0: begin
        if(reg_reason==8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_REACT;
        else w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;
      end
      ENUM_ST_REACT: begin
        w_math_req_valid=1'b1; w_math_op=3'd0;

        if(w_math_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_REACTW;
      end
      ENUM_ST_REACTW: begin
        if(w_math_resp_valid) begin
        if(!w_math_ok) w_reason_nxt=8'd37;
        w_fsm_ctrl_nxt_state = ENUM_ST_NOM0;
        end
      end
      ENUM_ST_NOM0: begin
        if(reg_reason!=8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;
        else begin
          w_math_delay='0;
          if(f_diff(w_plan[239:208],w_plan[527:496])<32'h80000000
             && f_diff(w_plan[239:208],w_plan[527:496])>32'd500000) begin
            w_reason_nxt=8'd38; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
          else w_fsm_ctrl_nxt_state=ENUM_ST_NPROP;
        end
      end
      ENUM_ST_NPROP: begin
        w_math_req_valid=1'b1; w_math_op=3'd4;
        w_math_delay=f_diff(w_plan[239:208],w_plan[527:496]);
        if(w_math_delay[31]) w_math_delay=32'd0;
        if(w_math_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_NPROPW;
      end
      ENUM_ST_NPROPW: begin
        if(w_math_resp_valid) begin
        w_fsm_ctrl_nxt_state = ENUM_ST_NOM;
        end
      end
      ENUM_ST_NOM: begin
        w_sweep_req_valid=1'b1;
        w_sweep_kind=2'd1;
        if(w_sweep_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_NOMW;
      end
      ENUM_ST_NOMW: begin
        if(w_sweep_resp_valid) begin
        if(!w_sweep_mask[15]) w_reason_nxt=8'd38;
        w_fsm_ctrl_nxt_state = ENUM_ST_OVERRIDE;
        end
      end
      ENUM_ST_OVERRIDE: begin
        if(!w_cap) w_reason_nxt=8'd39;
        if(!reg_healthy) w_reason_nxt=8'd40;
        if(w_rst) w_reason_nxt=8'd41;
        w_dup_sent_nxt=1'b0; w_main_sent_nxt=1'b0;
        w_dup_done_nxt=1'b0; w_main_done_nxt=1'b0;
        w_fsm_ctrl_nxt_state=ENUM_ST_FALLBACK;
      end
      ENUM_ST_FALLBACK: begin
        w_sweep_req_valid=!reg_main_sent;
        w_dup_req_valid=!reg_dup_sent;
        if(w_sweep_req_valid && w_sweep_req_ready) w_main_sent_nxt=1'b1;
        if(w_dup_req_valid && w_dup_req_ready) w_dup_sent_nxt=1'b1;
        if((reg_main_sent || w_sweep_req_ready) && (reg_dup_sent || w_dup_req_ready))
          w_fsm_ctrl_nxt_state=ENUM_ST_FALLBACKW;
      end
      ENUM_ST_FALLBACKW: begin
        if(w_sweep_resp_valid) begin
          w_context_nxt={240'd0,w_sweep_mask}; w_main_done_nxt=1'b1;
        end
        if(w_dup_resp_valid) begin w_dup_result_nxt=w_dup_mask[0]; w_dup_done_nxt=1'b1; end
        if((reg_main_done || w_sweep_resp_valid) && (reg_dup_done || w_dup_resp_valid)) begin
          w_lane_good_nxt=w_context_nxt[0]==w_dup_result_nxt;
          if(!w_lane_good_nxt && PARA_DIRECT==32'd0) begin
            w_healthy_nxt=1'b0; w_reason_nxt=w_rst ? 8'd41:8'd40;
            w_override_nxt=1'b1; w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0;
          end
          w_fsm_ctrl_nxt_state=ENUM_ST_SEL;
        end
      end
      ENUM_ST_SEL: begin
        w_b7_req_valid=1'b1; w_b7_req_data=reg_context[15:0];
        if(w_b7_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_SELW;
      end
      ENUM_ST_SELW: begin
        if(w_b7_resp_valid) begin
        w_cid_nxt = w_b7_resp_data[15:8];        w_label_nxt = w_b7_resp_data[7:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_TAIL0;
        end
      end
      ENUM_ST_TAIL0: begin
        if(reg_reason!=8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_REUSE0;
        else begin
          if(!w_explicit && (f_diff(w_plan[239:208],w_plan[527:496])>=32'h80000000
             || f_diff(w_plan[239:208],w_plan[527:496])>32'd100000)) begin
            w_reason_nxt=8'd42; w_fsm_ctrl_nxt_state=ENUM_ST_REUSE0; end
          else begin
            if(w_explicit) w_fsm_ctrl_nxt_state=ENUM_ST_BRIDGE;
            else w_fsm_ctrl_nxt_state=ENUM_ST_TAIL;
          end
        end
      end
      ENUM_ST_BRIDGE: begin
        w_math_req_valid=1'b1; w_math_op=3'd2;
        w_math_delay=w_delay[31] ? 32'd0 : w_delay;
        if(w_math_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_BRIDGEW;
      end
      ENUM_ST_BRIDGEW: begin
        if(w_math_resp_valid) begin
        w_bridge_nxt = w_math_bridge;
        w_fsm_ctrl_nxt_state = ENUM_ST_BRIDGE0;
        end
      end
      ENUM_ST_BRIDGE0: begin
        if(w_delay==32'd0 || w_delay[31]) w_fsm_ctrl_nxt_state=ENUM_ST_PROP;
        else w_fsm_ctrl_nxt_state=ENUM_ST_BGEOM;
      end
      ENUM_ST_BGEOM: begin
        w_sweep_req_valid=1'b1;
        w_sweep_kind=2'd2;
        if(w_sweep_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_BGEOMW;
      end
      ENUM_ST_BGEOMW: begin
        if(w_sweep_resp_valid) begin
        if(!w_sweep_mask[0]) w_reason_nxt=8'd42;
        w_fsm_ctrl_nxt_state = ENUM_ST_PROP;
        end
      end
      ENUM_ST_PROP: begin
        w_math_req_valid=1'b1; w_math_op=3'd1;
        w_math_delay=w_delay[31] ? 32'd0 : w_delay;
        if(w_math_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_PROPW;
      end
      ENUM_ST_PROPW: begin
        if(w_math_resp_valid) begin
        w_fsm_ctrl_nxt_state = ENUM_ST_TAIL;
        end
      end
      ENUM_ST_TAIL: begin
        w_sweep_req_valid=1'b1;
        if(w_sweep_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_TAILW;
      end
      ENUM_ST_TAILW: begin
        if(w_sweep_resp_valid) begin
        w_context_nxt = {240'd0,w_sweep_mask};
        w_fsm_ctrl_nxt_state = ENUM_ST_TSEL;
        end
      end
      ENUM_ST_TSEL: begin
        w_b7_req_valid=1'b1; w_b7_req_data=reg_context[15:0];
        if(w_b7_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_TSELW;
      end
      ENUM_ST_TSELW: begin
        if(w_b7_resp_valid) begin
        w_tail_nxt = w_b7_resp_data[15:8];        if(w_b7_resp_data[15:8]==8'd15) w_reason_nxt=8'd42;
        w_fsm_ctrl_nxt_state = ENUM_ST_REUSE0;
        end
      end
      ENUM_ST_REUSE0: begin
        w_reuse_nxt=1'b0;
        if(reg_backup_valid && !w_phase[31] && w_cap && reg_healthy)
          w_fsm_ctrl_nxt_state=ENUM_ST_RECHK;
        else w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;
      end
      ENUM_ST_RECHK: begin
        w_b9_req_valid=1'b1; w_b9_req_data={1'b1,reg_backup_plan,reg_backup_cert,w_now,1'b0,1'b0,32'd0,1'b0,1'b0,32'd0,1'b0,256'd0,1'b1,reg_backup_cert[1215:960],reg_backup_cert[959:704],reg_backup_cert[255:0]};
        if(w_b9_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_RECHKW;
      end
      ENUM_ST_RECHKW: begin
        if(w_b9_resp_valid) begin
        w_reuse_nxt = w_b9_resp_data==8'd0 && f_diff(reg_backup_cert[671:640],w_now)<32'h80000000 && f_diff(reg_backup_cert[671:640],w_now)>32'd120000;
        w_fsm_ctrl_nxt_state = ENUM_ST_REPLAY0;
        end
      end
      ENUM_ST_REPLAY0: begin
        if(reg_reuse) w_fsm_ctrl_nxt_state=ENUM_ST_REPLAY;
        else w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;
      end
      ENUM_ST_REPLAY: begin
        w_math_req_valid=1'b1; w_math_op=3'd3;
        w_math_delay=w_phase;
        if(w_math_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_REPLAYW;
      end
      ENUM_ST_REPLAYW: begin
        if(w_math_resp_valid) begin
        w_reuse_nxt=w_math_ok
          && f_abs(64'(w_ego[223:160]-w_math_pose[95:32]))+64'd50000+64'(reg_xerr)<=64'd160000
          && f_abs(64'({32'd0,w_ego[159:128]}-{32'd0,w_math_pose[31:0]}))+64'd50640<=64'd200000;
        w_fsm_ctrl_nxt_state = ENUM_ST_SUPER;
        end
      end
      ENUM_ST_SUPER: begin
        w_b8_req_valid=1'b1; w_b8_req_data={reg_mode,reg_good,reg_fault,reg_reason==8'd0,(reg_live_bad || reg_deadline) ? 32'd1000000 : w_ego[159:128],reg_reuse,reg_cid!=8'd15,w_cap,w_rst || reg_deadline,reg_healthy && !reg_live_bad};
        if(w_b8_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_SUPERW;
      end
      ENUM_ST_SUPERW: begin
        if(w_b8_resp_valid) begin
        w_mode_nxt=w_b8_resp_data[7:5]; w_good_nxt=w_b8_resp_data[4:3]; w_fault_nxt=w_b8_resp_data[2];
        w_csr_rst_nxt=1'b0;
        if(w_b8_resp_data[1]) w_pending_valid_nxt=1'b0;
        if(w_b8_resp_data[0]) w_backup_valid_nxt=1'b0;
        w_fsm_ctrl_nxt_state = ENUM_ST_COMMIT0;
        end
      end
      ENUM_ST_COMMIT0: begin
        w_ing_nxt[298]=1'b1; w_ing_nxt[297:266]=w_now;
        if(reg_reason==8'd0) begin
          w_new_plan_nxt=w_plan; w_new_plan_nxt[79:72]=reg_tail;
          w_ing_nxt=reg_proposal;
          w_fsm_ctrl_nxt_state=ENUM_ST_NEWHASH;
        end else w_fsm_ctrl_nxt_state=ENUM_ST_RECORD;
      end
      ENUM_ST_NEWHASH: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd2; w_hash_len=11'd70;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_NEWHASHW;
      end
      ENUM_ST_NEWHASHW: begin
        if(w_hash_resp_valid) begin
        w_trajectory_nxt = w_hash_resp_data[255:0];
        w_fsm_ctrl_nxt_state = ENUM_ST_NEWCERT;
          if(w_hash_resp_data[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
        end
      end
      ENUM_ST_NEWCERT: begin
        w_new_cert_nxt = {1'b1,reg_snapshot,reg_trajectory,reg_new_plan[239:208],w_cert[671:640],32'd1,32'd1,32'd1,32'd1,w_cert[511:256],256'd0};        w_fsm_ctrl_nxt_state = ENUM_ST_RESEAL;
      end
      ENUM_ST_RESEAL: begin
        w_hash_req_valid=1'b1; w_hash_op=8'd4; w_hash_len=11'd120;
        if(w_hash_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_RESEALW;
      end
      ENUM_ST_RESEALW: begin
        if(w_hash_resp_valid) begin
        w_new_cert_nxt = {reg_new_cert[1216:256],w_hash_resp_data[255:0]};        w_pending_cert_nxt = {reg_new_cert[1216:256],w_hash_resp_data[255:0]};        w_pending_plan_nxt = reg_new_plan;        w_pending_valid_nxt = 1'b1;        w_issued_nxt = w_now;
        w_fsm_ctrl_nxt_state = ENUM_ST_RECORD;
          if(w_hash_resp_data[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
        end
      end
      ENUM_ST_RECORD: begin
        w_rec_req_valid=1'b1; w_rec_req_data={1'b1,3'd4,1'b0,6'd0,224'd0,w_now,1'b1,w_reason_len,w_event_reason,1'b1,w_mode_len,w_event_mode,1'b0,6'd0,248'd0,reg_cid};
        if(w_rec_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_RECORDW;
      end
      ENUM_ST_RECORDW: begin
        if(w_rec_resp_valid) begin
        w_lost_nxt = w_rec_resp_data;
        w_fsm_ctrl_nxt_state = ENUM_ST_ARB0;
        end
      end
      ENUM_ST_ARB0: begin
        w_override_nxt=reg_live_bad || reg_deadline || !reg_healthy || reg_mode==3'd3;
        if((reg_mode==3'd0 || reg_mode==3'd5) && reg_pending_valid
          && (f_diff(reg_pending_cert[671:640],i_time_us)==32'd0
            || f_diff(reg_pending_cert[671:640],i_time_us)>=32'h80000000)) w_override_nxt=1'b1;
        if(reg_mode==3'd1 && reg_backup_valid
          && (f_diff(reg_backup_cert[671:640],i_time_us)==32'd0
            || f_diff(reg_backup_cert[671:640],i_time_us)>=32'h80000000)) w_override_nxt=1'b1;
        w_heartbeat_en_nxt=reg_healthy && !reg_live_bad;
        if(!reg_heartbeat_en && reg_healthy && !reg_live_bad) begin
          w_heartbeat_time_nxt=i_time_us; w_heartbeat_nxt=1'b0;
        end
        if(!reg_healthy || reg_live_bad) w_heartbeat_nxt=1'b0;
        w_fsm_ctrl_nxt_state=ENUM_ST_ARB;
      end
      ENUM_ST_ARB: begin
        w_arb_req_valid=1'b1; w_arb_req_data={reg_mode,reg_cid,reg_label,w_now,reg_pending_valid,reg_pending_plan,reg_pending_cert,reg_backup_valid,reg_backup_plan,reg_backup_cert,w_ego};
        if(w_arb_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_ARBW;
      end
      ENUM_ST_ARBW: begin
        if(w_arb_resp_valid) begin
        w_cmd_nxt = w_arb_resp_data[1896:0];        w_cmd_valid_nxt = !reg_deadline;
        w_fsm_ctrl_nxt_state = ENUM_ST_DELIVER;
        end
      end
      ENUM_ST_DELIVER: begin
        if(!reg_cmd_valid || i_cmd_ready) begin
          w_active_nxt=1'b0;
          if(!reg_deadline) begin
            w_resp_data_nxt={reg_reason==8'd0,reg_reason,reg_mode,reg_cid,reg_label,
              reg_reason!=8'd0,reg_commit,reg_healthy && !reg_live_bad};
            w_final_rsp_nxt=w_resp_data_nxt;
            w_resp_valid_nxt=1'b1;
          end
          w_sts_valid=1'b1;
          w_sts_data={reg_deadline ? reg_final_rsp : w_resp_data_nxt,1'b0,reg_pending_valid,reg_backup_valid,
            reg_healthy && !reg_live_bad,reg_healthy,
            reg_deadline ? 32'd1875000:32'(reg_count+32'd1),reg_lost,8'h81};
          w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        end
      end
      ENUM_ST_DRAIN: begin
        if(w_sweep_req_ready && w_dup_req_ready && w_math_req_ready && w_hash_req_ready && w_health_req_ready
          && w_b1_req_ready && w_b2_req_ready && w_b9_req_ready && w_b7_req_ready && w_b8_req_ready && w_arb_req_ready && w_rec_req_ready)
          w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;
      end
      default: w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
    endcase
    // Timers and deadline never depend on host, executor or recorder backpressure.
    if(reg_active && !reg_deadline) begin
      w_count_nxt=32'(reg_count+32'd1);
      if(reg_count==32'd1874999 && !w_resp_valid_nxt) begin
        w_deadline_nxt=1'b1; w_reason_nxt=8'd7; w_commit_nxt=8'd35;
        w_active_nxt=1'b0;
        w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1;
        w_pending_valid_nxt=1'b0; w_backup_valid_nxt=1'b0; w_override_nxt=1'b1;
        w_cmd_valid_nxt=1'b0; w_cmd_nxt='0;
        w_resp_data_nxt={1'b0,8'd7,3'd3,8'd15,8'd2,1'b1,8'd35,reg_healthy};
        w_final_rsp_nxt=w_resp_data_nxt;
        w_resp_valid_nxt=1'b1; w_fsm_ctrl_nxt_state=ENUM_ST_DRAIN;
        w_sts_valid=1'b1; w_sts_data={w_resp_data_nxt,1'b0,1'b0,1'b0,
          reg_healthy,reg_healthy,32'd1875000,reg_lost,8'h81};
      end
    end
    // CSR reset revokes authority immediately and drains accepted work before reuse.
    if(w_config[1] && !w_deadline_nxt) begin
      w_override_nxt=1'b1; w_pending_valid_nxt=1'b0; w_backup_valid_nxt=1'b0;
      w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0;
      w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1;
      if(reg_fsm_ctrl_current_state==ENUM_ST_IDLE) w_ing_nxt='0;
      else if(reg_fsm_ctrl_current_state!=ENUM_ST_BOOT
        && reg_fsm_ctrl_current_state!=ENUM_ST_BIST
        && reg_fsm_ctrl_current_state!=ENUM_ST_BISTW
        && reg_fsm_ctrl_current_state!=ENUM_ST_TLOG
        && reg_fsm_ctrl_current_state!=ENUM_ST_TLOGW) begin
        w_csr_rst_nxt=1'b1; w_reason_nxt=8'd41; w_commit_nxt=8'd35;
        w_live_bad_nxt=1'b1; w_cmd_valid_nxt=1'b0; w_cmd_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_DRAIN;
      end
    end
    // An invalid controller encoding revokes authority before safe drain/recovery.
    if(!w_fsm_valid) begin
      w_override_nxt=1'b1; w_pending_valid_nxt=1'b0; w_backup_valid_nxt=1'b0;
      w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1; w_healthy_nxt=1'b0;
      w_heartbeat_en_nxt=1'b0; w_heartbeat_nxt=1'b0; w_cmd_valid_nxt=1'b0; w_cmd_nxt='0;
      if(!reg_deadline) begin w_reason_nxt=8'd40; w_commit_nxt=8'd35; w_live_bad_nxt=1'b1; end
      if(reg_active || reg_deadline) w_fsm_ctrl_nxt_state=ENUM_ST_DRAIN;
      else w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
    end
    // Stored parity follows intentional writes after all fault/reset priorities resolve.
    if(w_ing_nxt!=reg_ing) w_ing_par_nxt=^w_ing_nxt;
    if(w_pending_plan_nxt!=reg_pending_plan) w_pending_plan_par_nxt=^w_pending_plan_nxt;
    if(w_pending_cert_nxt!=reg_pending_cert) w_pending_cert_par_nxt=^w_pending_cert_nxt;
    if(w_backup_plan_nxt!=reg_backup_plan) w_backup_plan_par_nxt=^w_backup_plan_nxt;
    if(w_backup_cert_nxt!=reg_backup_cert) w_backup_cert_par_nxt=^w_backup_cert_nxt;
    if({w_mode_nxt,w_good_nxt,w_fault_nxt}!={reg_mode,reg_good,reg_fault})
      w_ctrl_par_nxt=^{w_mode_nxt,w_good_nxt,w_fault_nxt};

  end
  // Asynchronous assertion; the enclosing reset synchronizer releases this domain.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_req <= '0;
      reg_parse_reason <= '0;
      reg_active <= '0;
      reg_ing <= '0;
      reg_proposal <= '0;
      reg_mode <= 3'd3;
      reg_good <= '0;
      reg_fault <= '0;
      reg_pending_valid <= '0;
      reg_pending_plan <= '0;
      reg_pending_cert <= '0;
      reg_issued <= '0;
      reg_backup_valid <= '0;
      reg_backup_plan <= '0;
      reg_backup_cert <= '0;
      reg_reason <= '0;
      reg_commit <= '0;
      reg_cid <= '0;
      reg_label <= '0;
      reg_tail <= '0;
      reg_healthy <= '0;
      reg_reuse <= '0;
      reg_world <= '0;
      reg_lane <= '0;
      reg_lead <= '0;
      reg_bridge <= '0;
      reg_context <= '0;
      reg_snapshot <= '0;
      reg_trajectory <= '0;
      reg_seal <= '0;
      reg_new_plan <= '0;
      reg_new_cert <= '0;
      reg_resp_data <= '0;
      reg_final_rsp <= '0;
      reg_resp_valid <= '0;
      reg_cmd <= '0;
      reg_cmd_valid <= '0;
      reg_count <= '0;
      reg_lost <= '0;
      reg_deadline <= '0;
      reg_override <= 1'b1;
      reg_live_bad <= '0;
      reg_tick <= '0;
      reg_tick_valid <= '0;
      reg_heartbeat_time <= '0;
      reg_heartbeat <= '0;
      reg_heartbeat_en <= '0;
      reg_timer_code <= '0;
      reg_timer_valid <= '0;
      reg_ing_par <= '0;
      reg_pending_plan_par <= '0;
      reg_pending_cert_par <= '0;
      reg_backup_plan_par <= '0;
      reg_backup_cert_par <= '0;
      reg_ctrl_par <= '0;
      reg_bist_wait <= '0;
      reg_csr_rst <= '0;
      reg_dup_sent <= '0;
      reg_main_sent <= '0;
      reg_dup_done <= '0;
      reg_main_done <= '0;
      reg_dup_result <= '0;
      reg_lane_good <= 1'b1;
      reg_replay_full <= '0;
      reg_replay_event <= '0;
      reg_log_drops <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_req <= w_req_nxt;
      reg_parse_reason <= w_parse_reason_nxt;
      reg_active <= w_active_nxt;
      reg_ing <= w_ing_nxt;
      reg_proposal <= w_proposal_nxt;
      reg_mode <= w_mode_nxt;
      reg_good <= w_good_nxt;
      reg_fault <= w_fault_nxt;
      reg_pending_valid <= w_pending_valid_nxt;
      reg_pending_plan <= w_pending_plan_nxt;
      reg_pending_cert <= w_pending_cert_nxt;
      reg_issued <= w_issued_nxt;
      reg_backup_valid <= w_backup_valid_nxt;
      reg_backup_plan <= w_backup_plan_nxt;
      reg_backup_cert <= w_backup_cert_nxt;
      reg_reason <= w_reason_nxt;
      reg_commit <= w_commit_nxt;
      reg_cid <= w_cid_nxt;
      reg_label <= w_label_nxt;
      reg_tail <= w_tail_nxt;
      reg_healthy <= w_healthy_nxt;
      reg_reuse <= w_reuse_nxt;
      reg_world <= w_world_nxt;
      reg_lane <= w_lane_nxt;
      reg_lead <= w_lead_nxt;
      reg_bridge <= w_bridge_nxt;
      reg_context <= w_context_nxt;
      reg_snapshot <= w_snapshot_nxt;
      reg_trajectory <= w_trajectory_nxt;
      reg_seal <= w_seal_nxt;
      reg_new_plan <= w_new_plan_nxt;
      reg_new_cert <= w_new_cert_nxt;
      reg_resp_data <= w_resp_data_nxt;
      reg_final_rsp <= w_final_rsp_nxt;
      reg_resp_valid <= w_resp_valid_nxt;
      reg_cmd <= w_cmd_nxt;
      reg_cmd_valid <= w_cmd_valid_nxt;
      reg_count <= w_count_nxt;
      reg_lost <= w_lost_nxt;
      reg_deadline <= w_deadline_nxt;
      reg_override <= w_override_nxt;
      reg_live_bad <= w_live_bad_nxt;
      reg_tick <= w_tick_nxt;
      reg_tick_valid <= w_tick_valid_nxt;
      reg_heartbeat_time <= w_heartbeat_time_nxt;
      reg_heartbeat <= w_heartbeat_nxt;
      reg_heartbeat_en <= w_heartbeat_en_nxt;
      reg_timer_code <= w_timer_code_nxt;
      reg_timer_valid <= w_timer_valid_nxt;
      reg_ing_par <= w_ing_par_nxt;
      reg_pending_plan_par <= w_pending_plan_par_nxt;
      reg_pending_cert_par <= w_pending_cert_par_nxt;
      reg_backup_plan_par <= w_backup_plan_par_nxt;
      reg_backup_cert_par <= w_backup_cert_par_nxt;
      reg_ctrl_par <= w_ctrl_par_nxt;
      reg_bist_wait <= w_bist_wait_nxt;
      reg_csr_rst <= w_csr_rst_nxt;
      reg_dup_sent <= w_dup_sent_nxt;
      reg_main_sent <= w_main_sent_nxt;
      reg_dup_done <= w_dup_done_nxt;
      reg_main_done <= w_main_done_nxt;
      reg_dup_result <= w_dup_result_nxt;
      reg_lane_good <= w_lane_good_nxt;
      reg_replay_full <= w_replay_full_nxt;
      reg_replay_event <= w_replay_event_nxt;
      reg_log_drops <= w_log_drops_nxt;
    end
  end

  // CLAUDE-FIX-003: wide sub-block operands select on state flags registered from the
  // next state, so each bit is a small mux instead of a private 76-bit state decode.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_opsel
    if (!i_rst_n_core) begin
      reg_hs_crc <= 1'b0; reg_hs_ctx <= 1'b0; reg_hs_snap <= 1'b0; reg_hs_traj <= 1'b0;
      reg_hs_seal <= 1'b0; reg_hs_newh <= 1'b0; reg_hs_reseal <= 1'b0;
      reg_ss_nom <= 1'b0; reg_ss_tail <= 1'b0; reg_ms_nprop <= 1'b0;
    end else begin
      reg_hs_crc <= w_fsm_ctrl_nxt_state==ENUM_ST_CRC;
      reg_hs_ctx <= w_fsm_ctrl_nxt_state==ENUM_ST_CONTEXT;
      reg_hs_snap <= w_fsm_ctrl_nxt_state==ENUM_ST_SNAP;
      reg_hs_traj <= w_fsm_ctrl_nxt_state==ENUM_ST_TRAJ;
      reg_hs_seal <= w_fsm_ctrl_nxt_state==ENUM_ST_SEAL;
      reg_hs_newh <= w_fsm_ctrl_nxt_state==ENUM_ST_NEWHASH;
      reg_hs_reseal <= w_fsm_ctrl_nxt_state==ENUM_ST_RESEAL;
      reg_ss_nom <= w_fsm_ctrl_nxt_state==ENUM_ST_NOM;
      reg_ss_tail <= w_fsm_ctrl_nxt_state==ENUM_ST_TAIL;
      reg_ms_nprop <= w_fsm_ctrl_nxt_state==ENUM_ST_NPROP;
    end
  end
  // Flags equal the decoded current state (same reset, same next-state source).
  assign w_hash_data=({8416{reg_hs_crc}} & {w_plan,w_packet[127:0],7728'd0})
    | ({8416{reg_hs_ctx}} & {(reg_req[33862] ? reg_req[42446:34247] : 8200'd0),
                             reg_lane[383:256],32'd1,32'd1,24'd0})
    | ({8416{reg_hs_snap}} & {w_plan[527:272],8160'd0})
    | ({8416{reg_hs_traj}} & {w_plan,7856'd0})
    | ({8416{reg_hs_seal}} & {w_cert[1215:256],7456'd0})
    | ({8416{reg_hs_newh}} & {reg_new_plan,7856'd0})
    | ({8416{reg_hs_reseal}} & {reg_new_cert[1215:256],7456'd0});
  assign w_math_world=reg_ms_nprop ? {8'd1,w_plan[367:304],w_plan[303:272],32'd0,64'd4800000,
      (w_plan[527:496]<32'd500000 ? 32'(32'd500000-w_plan[527:496]):32'd0),
      (reg_req[33860] ? 32'(-32'd4000000):32'd0),7936'd0} : reg_world;
  // CLAUDE-OPT (31/10): the nominal lead (NPROP) and the future world (PROP, or the
  // nominal lead when not explicit) are read from u_tsmx_math's held reg_world: math is
  // idle between NPROPW..TAIL0 and between PROPW..TAIL, and holds reg_world while idle.
  // Removes the 2x8200-bit reg_nominal_lead/reg_future copies.
  assign w_sweep_world=(reg_ss_nom || reg_ss_tail) ? w_math_out : reg_world;
  assign w_sweep_lane=reg_ss_nom ? {64'hffffffffffe488c0,64'd1800000,64'd0,64'd950000,64'd50000,
                                    64'd500000} : reg_lane;
  assign w_sweep_pose=(reg_ss_nom || reg_ss_tail) ? w_plan[207:80]
                                                   : {w_ego[223:160],w_ego[159:128],w_ego[127:96]};

  // CLAUDE-FIX-002: the replay error bound is pipelined from the phase latched with the
  // REPLAY math request (math answers 7+ clocks later); constant divides use reciprocals.
  // Status record pipeline into the CSR block.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_sts
    if (!i_rst_n_core) begin
      reg_sts_valid <= 1'b0; reg_sts_data <= '0;
    end else begin
      reg_sts_valid <= w_sts_valid; reg_sts_data <= w_sts_data;
    end
  end
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_xerr
    if (!i_rst_n_core) begin
      reg_xph <= '0; reg_xprod <= '0; reg_xn <= '0; reg_xm <= '0; reg_xmprod <= '0;
      reg_xerr <= '0;
    end else begin
      if(reg_fsm_ctrl_current_state==ENUM_ST_REPLAY && w_math_req_ready)
        reg_xph <= 32'(w_phase+32'd19999);
      reg_xprod <= 65'(reg_xph)*65'd7036874418;
      reg_xn <= 32'(reg_xprod[64:47]);
      reg_xm <= 32'(reg_xn*32'(reg_xn-32'd1)+32'd99);
      reg_xmprod <= 65'(reg_xm)*65'd5497558139;
      reg_xerr <= w_xerr;
    end
  end
  m_tsmx_ingress u_b1 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_b1_req_valid),
    .i_req_data(w_b1_req_data),
    .o_req_ready(w_b1_req_ready),
    .o_rsp_valid(w_b1_resp_valid),
    .o_rsp_data(w_b1_resp_data),
    .i_rsp_ready(1'b1)
  );
  m_tsmx_splice u_b2 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_b2_req_valid),
    .i_req_data(w_b2_req_data),
    .o_req_ready(w_b2_req_ready),
    .o_rsp_valid(w_b2_resp_valid),
    .o_rsp_data(w_b2_resp_data),
    .i_rsp_ready(1'b1)
  );
  m_tsmx_cert u_b9 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_b9_req_valid),
    .i_req_data(w_b9_req_data),
    .o_req_ready(w_b9_req_ready),
    .o_rsp_valid(w_b9_resp_valid),
    .o_rsp_data(w_b9_resp_data),
    .i_rsp_ready(1'b1)
  );
  m_tsmx_sel u_b7 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_b7_req_valid),
    .i_req_data(w_b7_req_data),
    .o_req_ready(w_b7_req_ready),
    .o_rsp_valid(w_b7_resp_valid),
    .o_rsp_data(w_b7_resp_data),
    .i_rsp_ready(1'b1)
  );
  m_tsmx_supervisor u_b8 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_b8_req_valid),
    .i_req_data(w_b8_req_data),
    .o_req_ready(w_b8_req_ready),
    .o_rsp_valid(w_b8_resp_valid),
    .o_rsp_data(w_b8_resp_data),
    .i_rsp_ready(1'b1)
  );
  m_tsmx_arb u_arb (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_arb_req_valid),
    .i_req_data(w_arb_req_data),
    .o_req_ready(w_arb_req_ready),
    .o_rsp_valid(w_arb_resp_valid),
    .o_rsp_data(w_arb_resp_data),
    .i_rsp_ready(1'b1),
    .i_override(reg_override && reg_mode!=3'd4),
    .o_brake(w_arb_brake)
  );
  m_tsmx_rec u_rec (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_rec_req_valid),
    .i_req_data(w_rec_req_data),
    .o_req_ready(w_rec_req_ready),
    .o_rsp_valid(w_rec_resp_valid),
    .o_rsp_data(w_rec_resp_data),
    .i_rsp_ready(1'b1),
    .i_log_idx(i_log_idx),
    .i_log_valid(i_log_valid),
    .i_log_ready(i_log_ready),
    .o_log_ready(o_log_ready),
    .o_log_data(o_log_data),
    .o_log_valid(o_log_valid)
  );
  m_tsmx_health_lane u_health (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_health_req_valid),
    .i_req_data(w_health_req_data),
    .o_req_ready(w_health_req_ready),
    .o_rsp_valid(w_health_resp_valid),
    .o_rsp_data(w_health_resp_data),
    .i_rsp_ready(1'b1)
  );
  m_tsmx_hash u_tsmx_hash (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_hash_req_valid),
    .i_op(w_hash_op),
    .i_len(w_hash_len),
    .i_data(w_hash_data),
    .o_req_ready(w_hash_req_ready),
    .o_rsp_valid(w_hash_resp_valid),
    .o_rsp_data(w_hash_resp_data)
  );
  m_tsmx_math u_tsmx_math (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_math_req_valid),
    .i_op(w_math_op),
    .i_ego(w_ego),
    .i_world(w_math_world),
    .i_delay(w_math_delay),
    .i_plan(w_math_plan),
    .i_rear(reg_req[33855:33824]),
    .o_req_ready(w_math_req_ready),
    .o_rsp_valid(w_math_resp_valid),
    .o_ok(w_math_ok),
    .o_world(w_math_out),
    .o_bridge(w_math_bridge),
    .o_pose(w_math_pose)
  );
  m_tsmx_sweep #(.PARA_G(PARA_G),.PARA_P(PARA_P)) u_tsmx_sweep_0 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_sweep_req_valid),
    .i_pose(w_sweep_pose),
    // CLAUDE-FIX-001 (30/10): golden select/select_world/plan_tail use b4 phase 0;
    // mrmgen phase and B3 row tag share this field; absolute now skipped the ramp.
    .i_epoch(32'd0),
    .i_world(w_sweep_world),
    .i_lane(w_sweep_lane),
    .i_kind(w_sweep_kind),
    .i_bridge(reg_bridge),
    .o_req_ready(w_sweep_req_ready),
    .o_rsp_valid(w_sweep_resp_valid),
    .o_rsp_data(w_sweep_mask)
  );
  m_tsmx_sweep #(.PARA_G(32'd1),.PARA_P(32'd1)) u_tsmx_sweep_1 (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_dup_req_valid),
    .i_pose({w_ego[223:160],w_ego[159:128],w_ego[127:96]}),
    // CLAUDE-FIX-001 (30/10): golden select/select_world/plan_tail use b4 phase 0;
    // mrmgen phase and B3 row tag share this field; absolute now skipped the ramp.
    .i_epoch(32'd0),
    .i_world(reg_world),
    .i_lane(reg_lane),
    .i_kind(2'd3),
    .i_bridge(704'd0),
    .o_req_ready(w_dup_req_ready),
    .o_rsp_valid(w_dup_resp_valid),
    .o_rsp_data(w_dup_mask)
  );
  m_tsmx_csr u_tsmx_csr (
    .i_axi_awaddr(i_axi_awaddr),
    .i_axi_awprot(i_axi_awprot),
    .i_axi_awvalid(i_axi_awvalid),
    .i_axi_wdata(i_axi_wdata),
    .i_axi_wstrb(i_axi_wstrb),
    .i_axi_wvalid(i_axi_wvalid),
    .i_axi_bready(i_axi_bready),
    .i_axi_araddr(i_axi_araddr),
    .i_axi_arprot(i_axi_arprot),
    .i_axi_arvalid(i_axi_arvalid),
    .i_axi_rready(i_axi_rready),
    .o_axi_awready(o_axi_awready),
    .o_axi_wready(o_axi_wready),
    .o_axi_bvalid(o_axi_bvalid),
    .o_axi_bresp(o_axi_bresp),
    .o_axi_arready(o_axi_arready),
    .o_axi_rvalid(o_axi_rvalid),
    .o_axi_rresp(o_axi_rresp),
    .o_axi_rdata(o_axi_rdata),
    .o_int_irq(o_int_irq),
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_sts_valid(reg_sts_valid),
    .i_sts_data(reg_sts_data),
    .o_config_data(w_config)
  );

`ifdef FORMAL
  // ---- Claude 05/11/2026: deadline (watchdog) properties, proven by k-induction ----
  // Assumption: one reset at time 0, then reset stays released and the clock runs (no glitch / no clock loss).
  // All submodule outputs (incl. CSR config / CSR reset) are unconstrained: see gen.py.
  reg f_init = 1'b1;
  reg f_prev_active = 1'b0;
  reg [31:0] f_prev_count = 32'd0;
  always @(posedge i_clk_core) begin
    f_init <= 1'b0;
    f_prev_active <= reg_active;
    f_prev_count <= reg_count;
  end
  always @(*) begin
    if (f_init) assume(!i_rst_n_core);
    else assume(i_rst_n_core);
  end
  always @(posedge i_clk_core) if (!f_init) begin
    // W1: while a request is active its cycle counter stays in [1, 1874999]
    W1: assert(!reg_active || (reg_count >= 32'd1 && reg_count <= 32'd1874998));
    // W2: an active request cannot be overwritten by a new admission (FSM not in IDLE/BOOT)
    //     (idle-side service states TLOG/TLOGW/BIST/BISTW are entered from IDLE only without an admission)
    W2: assert(!reg_active || (reg_fsm_ctrl_current_state != ENUM_ST_IDLE
                               && reg_fsm_ctrl_current_state != ENUM_ST_BOOT
                               && reg_fsm_ctrl_current_state != ENUM_ST_TLOG
                               && reg_fsm_ctrl_current_state != ENUM_ST_TLOGW
                               && reg_fsm_ctrl_current_state != ENUM_ST_BIST
                               && reg_fsm_ctrl_current_state != ENUM_ST_BISTW));
    // W3: no stale response is pending while a request is active
    W3: assert(!reg_active || !reg_resp_valid);
    // W5: after a deadline the brake output stays asserted
    W5: assert(!reg_deadline || o_brake);
    // W9: the latched deadline response is a REJECT with the deadline reason and brake bit (keeps o_brake high)
    W9: assert(!reg_deadline || (reg_final_rsp[9] && !reg_final_rsp[37] && reg_final_rsp[36:29] == 8'd7));
    // W6: deadline and active are exclusive
    W6: assert(!(reg_deadline && reg_active));
    if (f_prev_active) begin
      // W4: the counter advances by exactly one per active cycle (no stall by host/executor/recorder)
      if (reg_active) W4: assert(reg_count == f_prev_count + 32'd1);
      // W7: whenever activity ends, a response is presented (normal result or deadline REJECT)
      else W7: assert(reg_resp_valid);
    end
    // W8: a deadline response is a REJECT (accept bit 0) with reason 7
    if (reg_deadline && reg_resp_valid) W8: assert(reg_resp_data[37] == 1'b0 && reg_resp_data[36:29] == 8'd7);
  end
`endif

endmodule
`default_nettype wire
