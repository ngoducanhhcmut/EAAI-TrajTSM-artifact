/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Streaming B3 geometry, deferred validation and private arithmetic.
 * Assumptions  : Reset release is synchronized by the enclosing core wrapper.
 *                Row storage is resetless and guarded by the reset row count.
 * Deviations   : HIE-02: functional leaf; the enclosing system top is structural.
 *                PAR-03: SI coefficients and ABI bit positions follow golden exactly.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_geom #(
  // Parameter Description: allocated actors; ABI remains thirty-two slots.
  // Parameter values: 1..32; default is 32.
  // Parameter unit: count
  parameter logic [31:0] PARA_MAX_OBJ = 32'd32,
  // Parameter Description: allocated cells; stream count is checked against this limit.
  // Parameter values: 1..128; default is 128.
  // Parameter unit: count
  parameter logic [31:0] PARA_MAX_CELLS = 32'd128
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [8623:0] i_req_data,
  input wire i_row_valid,
  input wire [400:0] i_row_data,
  input wire i_terminal_valid,
  input wire [49:0] i_terminal_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_row_ready,
  output logic o_terminal_ready,
  output logic o_rsp_valid,
  output logic [80:0] o_rsp_data
);
  typedef enum logic [3:0] {
    ENUM_ST_BOOT = 4'd0,
    ENUM_ST_IDLE = 4'd1,
    ENUM_ST_ROW = 4'd2,
    ENUM_ST_INFL = 4'd3,
    ENUM_ST_IWAIT = 4'd4,
    ENUM_ST_ACT = 4'd5,
    ENUM_ST_ISSUE = 4'd6,
    ENUM_ST_AWAIT = 4'd7,
    ENUM_ST_STEP = 4'd8,
    ENUM_ST_FIN = 4'd9,
    ENUM_ST_RESP = 4'd10
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [39:0] reg_tag, w_tag_nxt;
  logic [8199:0] reg_world, w_world_nxt;
  logic [383:0] reg_lane, w_lane_nxt;
  logic [7:0] reg_count, w_count_nxt;
  logic [49:0] reg_term, w_term_nxt;
  logic [0:0] reg_term_valid, w_term_valid_nxt;
  logic [0:0] reg_bad_row, w_bad_row_nxt;
  logic [0:0] reg_bad_tag, w_bad_tag_nxt;
  logic [7:0] reg_cell, w_cell_nxt;
  logic [7:0] reg_actor, w_actor_nxt;
  logic [7:0] reg_fail, w_fail_nxt;
  logic [7:0] reg_steps, w_steps_nxt;
  logic [63:0] reg_margin, w_margin_nxt;
  logic [80:0] reg_resp, w_resp_nxt;
  logic [63:0] reg_inflate, w_inflate_nxt;
  logic [31:0] reg_part, w_part_nxt;
  logic [31:0] reg_remain, w_remain_nxt;
  logic [0:0] reg_ahead, w_ahead_nxt;
  logic [255:0] reg_pose, w_pose_nxt;
  logic [127:0] reg_vel, w_vel_nxt;
  logic [31:0] reg_oa, w_oa_nxt;
  logic [351:0] reg_rows [0:PARA_MAX_CELLS+1-1];
  logic [351:0] w_rows_nxt [0:PARA_MAX_CELLS+1-1];
  logic [255:0] reg_obj [0:PARA_MAX_OBJ-1];
  logic [255:0] w_obj_nxt [0:PARA_MAX_OBJ-1];
  logic [191:0] reg_motion [0:PARA_MAX_OBJ-1];
  logic [191:0] w_motion_nxt [0:PARA_MAX_OBJ-1];
  logic [351:0] w_row, w_nxt;
  logic [31:0] w_h, w_event, w_elapsed, w_accel;
  logic [63:0] w_gap, w_piece_margin;
  logic [255:0] w_object;
  logic [95:0] w_inum_0, w_inum_1, w_iq_0, w_iq_1;
  logic w_iv_0, w_iv_1, w_if_0, w_if_1;
  logic [4:0] w_ready, w_valid;
  logic w_adv_ready, w_adv_valid, w_adv_fault;
  logic [255:0] w_adv_pose;
  logic [127:0] w_adv_vel;
  logic [1927:0] w_req [0:4];
  logic [640:0] w_rsp [0:4];
  logic w_issue, w_consume, w_all, w_row_ok, w_lane_ok, w_lane_fit;
  logic w_obj_ok, w_speed_ok;
  logic [7:0] w_pre_reason;
  logic [63:0] w_lo, w_hi, w_y, w_half, w_err, w_reserve;
  logic [63:0] w_positive, w_speed_product, w_speed_limit;

  // Unsigned bit patterns implement explicit two's-complement comparisons.
  function automatic logic f_lt(input logic [63:0] w_a, w_b);
    f_lt = (w_a[63] != w_b[63]) ? w_a[63] : w_a < w_b;
  endfunction
  function automatic logic f_range(input logic [63:0] w_a, w_l, w_u);
    f_range = !f_lt(w_a,w_l) && !f_lt(w_u,w_a);
  endfunction
  function automatic logic [159:0] f_s64(input logic [63:0] w_a);
    f_s64 = {{96{w_a[63]}},w_a};
  endfunction
  function automatic logic [159:0] f_s32(input logic [31:0] w_a);
    f_s32 = {{128{w_a[31]}},w_a};
  endfunction
  function automatic logic f_row(input logic [351:0] w_r);
    f_row = w_r[351:288] == '0 && w_r[287:256] <= 32'd25600000
      && f_range(w_r[255:192],64'(-64'd10070000000),64'd10070000000)
      && f_range(w_r[191:128],w_r[255:192],64'd10070000000)
      && w_r[127:96] <= w_r[95:64] && w_r[95:64] <= 32'd20000000
      && f_range({{32{w_r[63]}},w_r[63:32]},64'(-64'd8000000),64'd0)
      && w_r[31:0] <= 32'd8000000;
  endfunction

  // Stable row reads keep operand data independent of ready/valid evaluation.
  assign w_row = (reg_cell < PARA_MAX_CELLS
    && {1'b0,reg_cell}+9'd1 < {1'b0,reg_count}) ? reg_rows[reg_cell] : 352'd0;
  // The following endpoint supplies cell duration without changing the current row.
  assign w_nxt = (reg_cell < PARA_MAX_CELLS
    && {1'b0,reg_cell}+9'd1 < {1'b0,reg_count}) ? reg_rows[reg_cell+8'd1] : 352'd0;

  // Decode only initialized slots; counts bound every variable array index.
  always_comb begin : p_com_decode
    w_object = '0;
    if (reg_actor < PARA_MAX_OBJ) w_object = reg_obj[reg_actor];
    w_h = 32'(w_nxt[287:256]-w_row[287:256]);
    w_elapsed = 32'(w_row[287:256]-reg_rows[0][287:256]);
    w_event = 32'(w_object[63:32]-w_elapsed);
    w_accel = w_object[127:96];
    if (w_elapsed >= w_object[63:32]) w_accel = w_object[31:0];
    {w_lo,w_hi,w_y,w_half,w_err,w_reserve} = reg_lane;
    w_lane_ok = f_range(w_lo,64'(-64'd10000000000),64'd10000000000)
      && f_range(w_hi,w_lo,64'd10000000000)
      && f_range(w_y,64'(-64'd10000000000),64'd10000000000)
      && w_half > 64'd0 && w_half <= 64'd10000000
      && w_err <= 64'd1000000 && w_reserve <= 64'd10000000;
    w_lane_fit = !f_lt(64'(w_y-w_half-w_err),w_lo)
      && !f_lt(w_hi,64'(w_y+w_half+w_err));
    w_obj_ok = 1'b1;
    w_speed_ok = 1'b1;
    w_positive = '0;
    w_speed_product = '0;
    w_speed_limit = '0;
    for (int idx=0; idx<PARA_MAX_OBJ; idx++) begin
      if (idx < reg_world[8199:8192]) begin
        if (!(f_range(reg_obj[idx][255:192],64'(-64'd10000000000),64'd10000000000)
          && reg_obj[idx][191:160] <= 32'd20000000
          && f_range({{32{reg_obj[idx][159]}},reg_obj[idx][159:128]},
            64'(-64'd8000000),64'd2000000)
          && f_range({{32{reg_obj[idx][31]}},reg_obj[idx][31:0]},
            64'(-64'd8000000),64'd2000000)
          && reg_obj[idx][63:32] <= 32'd12800000
          && reg_obj[idx][127:64] > 64'd0 && reg_obj[idx][127:64] <= 64'd20000000))
          w_obj_ok = 1'b0;
        w_positive = '0;
        if (!reg_obj[idx][159]) w_positive = {32'd0,reg_obj[idx][159:128]};
        if (!reg_obj[idx][31] && {32'd0,reg_obj[idx][31:0]} > w_positive)
          w_positive = {32'd0,reg_obj[idx][31:0]};
        if (reg_count > 8'd0 && reg_count <= 8'(PARA_MAX_CELLS+1)) begin
          w_speed_product = 64'(w_positive * 64'(reg_rows[reg_count-8'd1][287:256]
            -reg_rows[0][287:256]));
          w_speed_limit = 64'((64'd20000000-{32'd0,reg_obj[idx][191:160]})*64'd1000000);
          if (w_speed_product > w_speed_limit) w_speed_ok = 1'b0;
        end
      end
    end
    w_pre_reason = 8'd0;
    casez ({!reg_term[49] || reg_count<8'd2 || reg_term[7:0]!=reg_count || reg_bad_tag,
      reg_bad_row,!w_lane_ok,reg_world[8199:8192]>8'(PARA_MAX_OBJ),!w_lane_fit,
      !w_obj_ok,reg_count<8'd2 || reg_rows[reg_count-8'd1][287:256]<=reg_rows[0][287:256]
      || 32'(reg_rows[reg_count-8'd1][287:256]-reg_rows[0][287:256])>32'd12800000,
      !w_speed_ok})
      8'b1???????: w_pre_reason=8'd17;
      8'b01??????: w_pre_reason=8'd4;
      8'b001?????: w_pre_reason=8'd18;
      8'b0001????: w_pre_reason=8'd19;
      8'b00001???: w_pre_reason=8'd20;
      8'b000001??: w_pre_reason=8'd21;
      8'b0000001?: w_pre_reason=8'd16;
      8'b00000001: w_pre_reason=8'd22;
      default: w_pre_reason=8'd0;
    endcase
    w_inum_0 = 96'(96'(w_row[31:0])*96'(w_h)*96'(w_h)*96'(w_h));
    w_inum_1 = 96'(96'(w_h)*96'(w_h));
    w_gap = reg_ahead ? 64'(reg_pose[255:192]-reg_pose[63:0]-w_object[127:64])
      : 64'(reg_pose[127:64]-reg_pose[191:128]-w_object[127:64]);
    w_piece_margin = 64'(w_rsp[0][543:480]-w_reserve);
    w_all = &w_valid;
    w_issue = reg_fsm_ctrl_current_state==ENUM_ST_ISSUE && (&w_ready);
    w_consume = reg_fsm_ctrl_current_state==ENUM_ST_AWAIT && w_all;
    w_row_ok = f_row(i_row_data[352:1]);
    // Public channel mapping.
    o_req_ready = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
    o_row_ready = i_rst_n_core && reg_fsm_ctrl_current_state!=ENUM_ST_IDLE
      && reg_fsm_ctrl_current_state!=ENUM_ST_BOOT
      && reg_fsm_ctrl_current_state!=ENUM_ST_RESP && reg_count<8'(PARA_MAX_CELLS+1);
    o_terminal_ready = i_rst_n_core && !reg_term_valid
      && reg_fsm_ctrl_current_state!=ENUM_ST_IDLE
      && reg_fsm_ctrl_current_state!=ENUM_ST_BOOT
      && reg_fsm_ctrl_current_state!=ENUM_ST_RESP;
    o_rsp_valid = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_RESP;
    o_rsp_data = o_rsp_valid ? reg_resp : 81'd0;
    // Provisional next-state computation.
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_tag_nxt = reg_tag;
    w_world_nxt = reg_world;
    w_lane_nxt = reg_lane;
    w_count_nxt = reg_count;
    w_term_nxt = reg_term;
    w_term_valid_nxt = reg_term_valid;
    w_bad_row_nxt = reg_bad_row;
    w_bad_tag_nxt = reg_bad_tag;
    w_cell_nxt = reg_cell;
    w_actor_nxt = reg_actor;
    w_fail_nxt = reg_fail;
    w_steps_nxt = reg_steps;
    w_margin_nxt = reg_margin;
    w_resp_nxt = reg_resp;
    w_inflate_nxt = reg_inflate;
    w_part_nxt = reg_part;
    w_remain_nxt = reg_remain;
    w_ahead_nxt = reg_ahead;
    w_pose_nxt = reg_pose;
    w_vel_nxt = reg_vel;
    w_oa_nxt = reg_oa;
    w_rows_nxt[0]=reg_rows[0];
    for (int idx=1; idx<PARA_MAX_CELLS+1; idx++) w_rows_nxt[idx]=reg_rows[idx];
    w_obj_nxt[0]=reg_obj[0];
    for (int idx=1; idx<PARA_MAX_OBJ; idx++) w_obj_nxt[idx]=reg_obj[idx];
    w_motion_nxt[0]=reg_motion[0];
    for (int idx=1; idx<PARA_MAX_OBJ; idx++) w_motion_nxt[idx]=reg_motion[idx];
    if (i_row_valid && o_row_ready) begin
      w_rows_nxt[reg_count] = i_row_data[352:1];
      w_count_nxt = 8'(reg_count+8'd1);
      w_bad_row_nxt = reg_bad_row || !w_row_ok;
      w_bad_tag_nxt = reg_bad_tag || i_row_data[400:361]!=reg_tag
        || i_row_data[360:353]!=reg_count;
    end
    if (i_terminal_valid && o_terminal_ready) begin
      w_term_nxt=i_terminal_data;
      w_term_valid_nxt=1'b1;
    end
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      ENUM_ST_IDLE: if (i_req_valid) begin
        w_tag_nxt=i_req_data[8623:8584];
        w_world_nxt=i_req_data[8583:384];
        w_lane_nxt=i_req_data[383:0];
        w_count_nxt='0; w_term_valid_nxt=1'b0; w_bad_row_nxt=1'b0;
        w_bad_tag_nxt=1'b0; w_cell_nxt='0; w_actor_nxt='0; w_fail_nxt='0;
        w_steps_nxt='0; w_margin_nxt=64'd10000000000; w_resp_nxt='0;
        for (int idx=0; idx<PARA_MAX_OBJ; idx++) begin
          w_obj_nxt[idx]=i_req_data[8575-idx*256 -:256];
          w_motion_nxt[idx]={i_req_data[8575-idx*256 -:64],
            i_req_data[8575-idx*256 -:64],i_req_data[8511-idx*256 -:32],
            i_req_data[8511-idx*256 -:32]};
        end
        w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
      end
      ENUM_ST_ROW: begin
        if (reg_term_valid && reg_count==reg_term[7:0]
          && (reg_fail!=8'd0 || reg_bad_row || w_pre_reason!=8'd0
            || {1'b0,reg_cell}+9'd1>={1'b0,reg_count}))
          w_fsm_ctrl_nxt_state=ENUM_ST_FIN;
        else if (reg_fail==8'd0 && !reg_bad_row
          && {1'b0,reg_cell}+9'd1<{1'b0,reg_count}) begin
          casez ({w_h==32'd0 || w_h>32'd100000,
            reg_world[8199:8192]==8'd0 || reg_world[8199:8192]>8'(PARA_MAX_OBJ),
            !w_obj_ok})
            3'b1??: begin
              w_fail_nxt=8'd23; w_steps_nxt=reg_cell;
            end
            3'b01?,3'b001: begin
              w_cell_nxt=8'(reg_cell+8'd1);
            end
            default: w_fsm_ctrl_nxt_state=ENUM_ST_INFL;
          endcase
        end
      end
      ENUM_ST_INFL: w_fsm_ctrl_nxt_state=ENUM_ST_IWAIT;
      ENUM_ST_IWAIT: if (w_iv_0 && w_iv_1) begin
        w_inflate_nxt=64'd0;
        w_actor_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_ACT;
      end
      ENUM_ST_ACT: begin
        w_pose_nxt={reg_motion[reg_actor][191:64],
          64'(w_row[255:192]-reg_inflate),64'(w_row[191:128]+reg_inflate)};
        w_vel_nxt={reg_motion[reg_actor][63:0],w_row[127:64]};
        w_ahead_nxt=!f_lt(reg_motion[reg_actor][191:128],w_row[191:128]);
        w_part_nxt=w_h;
        w_remain_nxt='0;
        if (w_event>32'd0 && w_event<w_h && w_object[63:32]>w_elapsed) begin
          w_part_nxt=w_event; w_remain_nxt=32'(w_h-w_event);
        end
        w_oa_nxt=w_object[159:128];
        if (w_elapsed>=w_object[63:32]) w_oa_nxt=w_object[31:0];
        w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
      end
      ENUM_ST_ISSUE: if (&w_ready) w_fsm_ctrl_nxt_state=ENUM_ST_AWAIT;
      ENUM_ST_AWAIT: if (w_all) begin
        if (f_lt(w_piece_margin,reg_margin)) w_margin_nxt=w_piece_margin;
        casez ({w_rsp[0][640] || w_rsp[1][640] || w_rsp[2][640]
          || w_rsp[3][640] || w_rsp[4][640],w_piece_margin[63]})
          2'b1?: begin
            w_fail_nxt=8'd4; w_steps_nxt=reg_cell;
            w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
          end
          2'b01: begin
            w_fail_nxt=8'd24; w_margin_nxt=w_piece_margin;
            w_steps_nxt=8'(reg_cell+8'd1); w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
          end
          default: begin
            for (int idx=1; idx<5; idx++) begin
              w_pose_nxt[255-(idx-1)*64 -:64]=w_rsp[idx][543:480];
              w_vel_nxt[127-(idx-1)*32 -:32]=w_rsp[idx][351:320];
            end
            if (w_rsp[2][351:320]>32'd20000000) w_vel_nxt[95:64]=32'd20000000;
            if (reg_remain!=32'd0) begin
              w_part_nxt=reg_remain; w_remain_nxt='0; w_oa_nxt=w_object[31:0];
              w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
            end else w_fsm_ctrl_nxt_state=ENUM_ST_STEP;
          end
        endcase
      end
      ENUM_ST_STEP: begin
        w_motion_nxt[reg_actor]={reg_pose[255:128],reg_vel[127:64]};
        if ({1'b0,reg_actor}+9'd1<{1'b0,reg_world[8199:8192]}) begin
          w_actor_nxt=8'(reg_actor+8'd1); w_fsm_ctrl_nxt_state=ENUM_ST_ACT;
        end else begin
          w_cell_nxt=8'(reg_cell+8'd1); w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
        end
      end
      ENUM_ST_FIN: begin
        casez ({w_pre_reason!=8'd0,reg_fail!=8'd0})
          2'b1?: w_resp_nxt={1'b0,64'hffffffffffffffff,w_pre_reason,8'd0};
          2'b01: w_resp_nxt={1'b0,reg_fail==8'd24 ? reg_margin : 64'hffffffffffffffff,
            reg_fail,reg_steps};
          default: w_resp_nxt={1'b1,reg_margin,8'd0,8'(reg_count-8'd1)};
        endcase
        w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
      end
      ENUM_ST_RESP: if (i_rsp_ready) w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      default: w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
    endcase
  end

  // Stable operand decode does not depend on primitive ready.
  always_comb begin : p_com_arith
    // Private arithmetic requests.
    w_req[0]='0;
    for (int idx=1; idx<5; idx++) w_req[idx]='0;
    w_req[0][1927:1920]=8'd4;
    w_req[0][1919:1760]=f_s64(w_gap);
    w_req[0][1759:1600]=f_s32(reg_ahead ? reg_vel[127:96] : reg_vel[63:32]);
    w_req[0][1599:1440]=f_s32(reg_ahead ? reg_oa : w_row[63:32]);
    w_req[0][1439:1280]=f_s32(reg_ahead ? reg_vel[31:0] : reg_vel[95:64]);
    w_req[0][1279:1120]=f_s32(reg_ahead ? w_row[63:32] : reg_oa);
    w_req[0][1119:960]={128'd0,reg_part};
    for (int idx=1; idx<5; idx++) begin
      w_req[idx][1927:1920]=8'd3;
      w_req[idx][1919:1760]=f_s64(reg_pose[255-(idx-1)*64 -:64]);
      w_req[idx][1759:1600]=f_s32(reg_vel[127-(idx-1)*32 -:32]);
      w_req[idx][1599:1440]=f_s32(idx<3 ? reg_oa : w_row[63:32]);
      w_req[idx][1439:1280]={128'd0,reg_part};
      w_req[idx][1279:1120]=160'((idx==2)||(idx==4));
    end
  end

  // Control is asynchronously invalidated; payload RAM is guarded by count and job state.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT;
      reg_tag<='0;
      reg_world<='0;
      reg_lane<='0;
      reg_count<='0;
      reg_term<='0;
      reg_term_valid<='0;
      reg_bad_row<='0;
      reg_bad_tag<='0;
      reg_cell<='0;
      reg_actor<='0;
      reg_fail<='0;
      reg_steps<='0;
      reg_margin<='0;
      reg_resp<='0;
      reg_inflate<='0;
      reg_part<='0;
      reg_remain<='0;
      reg_ahead<='0;
      reg_pose<='0;
      reg_vel<='0;
      reg_oa<='0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_tag<=w_tag_nxt;
      reg_world<=w_world_nxt;
      reg_lane<=w_lane_nxt;
      reg_count<=w_count_nxt;
      reg_term<=w_term_nxt;
      reg_term_valid<=w_term_valid_nxt;
      reg_bad_row<=w_bad_row_nxt;
      reg_bad_tag<=w_bad_tag_nxt;
      reg_cell<=w_cell_nxt;
      reg_actor<=w_actor_nxt;
      reg_fail<=w_fail_nxt;
      reg_steps<=w_steps_nxt;
      reg_margin<=w_margin_nxt;
      reg_resp<=w_resp_nxt;
      reg_inflate<=w_inflate_nxt;
      reg_part<=w_part_nxt;
      reg_remain<=w_remain_nxt;
      reg_ahead<=w_ahead_nxt;
      reg_pose<=w_pose_nxt;
      reg_vel<=w_vel_nxt;
      reg_oa<=w_oa_nxt;
    end
  end

  // Valid counts suppress all reads before the owning request initializes each slot.
  always_ff @(posedge i_clk_core) begin : p_ff_payload
    for (int idx=0; idx<PARA_MAX_CELLS+1; idx++) reg_rows[idx]<=w_rows_nxt[idx];
    for (int idx=0; idx<PARA_MAX_OBJ; idx++) reg_obj[idx]<=w_obj_nxt[idx];
    for (int idx=0; idx<PARA_MAX_OBJ; idx++) reg_motion[idx]<=w_motion_nxt[idx];
  end

  // Independent divider pipelines preserve outward rounding without behavioral division.
  m_tsmx_arith_div #(.PARA_W(32'd96)) u_arith_div_0 (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_valid(reg_fsm_ctrl_current_state==ENUM_ST_INFL),
    .i_num(w_inum_0), .i_den(96'd8000000000000000000), .i_up(1'b1),
    .o_valid(w_iv_0), .o_fault(w_if_0), .o_data(w_iq_0)
  );
  m_tsmx_arith_div #(.PARA_W(32'd96)) u_arith_div_1 (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_valid(reg_fsm_ctrl_current_state==ENUM_ST_INFL),
    .i_num(w_inum_1), .i_den(96'd2000000000000), .i_up(1'b1),
    .o_valid(w_iv_1), .o_fault(w_if_1), .o_data(w_iq_1)
  );
  // Swept uses the accepted implementation without modifying its sources.
    m_tsmx_geom_swept u_geom_swept (
      .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
      .i_req_valid(w_issue), .i_req_data(w_req[0]), .i_rsp_ready(w_consume),
      .o_req_ready(w_ready[0]), .o_rsp_valid(w_valid[0]), .o_rsp_data(w_rsp[0])
    );
  // Four interval advances share two II1 pipelines and complete before the swept result.
  m_tsmx_geom_adv u_geom_adv (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_valid(w_issue), .i_ready(w_consume), .i_pose(reg_pose), .i_vel(reg_vel),
    .i_oa(reg_oa), .i_ea(w_row[63:32]), .i_h(reg_part),
    .o_ready(w_adv_ready), .o_valid(w_adv_valid), .o_fault(w_adv_fault),
    .o_pose(w_adv_pose), .o_vel(w_adv_vel)
  );
  // Preserve the shared primitive's slot ABI at the local join.
  for (genvar gen_idx=1; gen_idx<5; gen_idx++) begin : gen_join
    // Local results retain the accepted arithmetic slot layout at the join.
    assign w_ready[gen_idx]=w_adv_ready;
    assign w_valid[gen_idx]=w_adv_valid;
    assign w_rsp[gen_idx]={w_adv_fault,
      {{96{w_adv_pose[255-(gen_idx-1)*64]}},w_adv_pose[255-(gen_idx-1)*64 -:64]},
      {{128{w_adv_vel[127-(gen_idx-1)*32]}},w_adv_vel[127-(gen_idx-1)*32 -:32]},320'd0};
  end
endmodule
`default_nettype wire
