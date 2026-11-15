/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : One continuous MRM context with ordered endpoint streaming.
 * Assumptions  : Wrapper synchronizes reset release; tags retained until terminal drain.
 * Deviations   : HIE-02 functional leaf. SI constants and ABI widths are fixed by golden.
 *                Grouped Moore next-state/datapath avoids Icarus function sensitivity.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_mrmgen #(
  // Parameter Description: Maximum cells per candidate; bounded by eight-bit row count.
  // Parameter values: 1 through 128; default 128.
  // Parameter unit: count
  parameter logic [31:0] PARA_MAX_CELLS = 32'd128
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [175:0] i_req_data,
  input wire i_row_ready,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_row_valid,
  output logic [400:0] o_row_data,
  output logic o_rsp_valid,
  output logic [49:0] o_rsp_data
);
  typedef enum logic [3:0] {
    ENUM_ST_BOOT=4'd0, ENUM_ST_IDLE=4'd1, ENUM_ST_GUARD=4'd2,
    ENUM_ST_PREP=4'd3, ENUM_ST_ISSUE=4'd4, ENUM_ST_WAIT=4'd5,
    ENUM_ST_ROW=4'd6, ENUM_ST_STEP=4'd7, ENUM_ST_CHECK=4'd8,
    ENUM_ST_END=4'd9, ENUM_ST_RESP=4'd10
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [175:0] reg_req, w_req_nxt;
  logic [31:0] reg_t, w_t_nxt;
  logic [63:0] reg_xl, w_xl_nxt;
  logic [63:0] reg_xh, w_xh_nxt;
  logic [31:0] reg_vl, w_vl_nxt;
  logic [31:0] reg_vh, w_vh_nxt;
  logic [31:0] reg_a, w_a_nxt;
  logic [7:0] reg_cid, w_cid_nxt;
  logic [31:0] reg_epoch, w_epoch_nxt;
  logic [7:0] reg_limit, w_limit_nxt;
  logic [7:0] reg_cnt, w_cnt_nxt;
  logic [31:0] reg_stop, w_stop_nxt;
  logic [0:0] reg_stop_valid, w_stop_valid_nxt;
  logic [31:0] reg_start, w_start_nxt;
  logic [31:0] reg_cmd, w_cmd_nxt;
  logic [31:0] reg_jerk, w_jerk_nxt;
  logic [49:0] reg_resp, w_resp_nxt;
  logic [400:0] reg_row, w_row_nxt;
  logic [1:0] reg_op, w_op_nxt;
  logic [0:0] reg_final, w_final_nxt;
  logic w_ar_ready, w_ar_valid, w_ar_req;
  logic [1927:0] w_ar_data;
  logic [640:0] w_ar_resp;
  logic [31:0] w_b, w_j, w_target, w_signed;
  logic [31:0] w_stop_time;
  logic w_grid, w_range, w_held;

  // Sign extension keeps every arithmetic operand valid in the shared s160 ABI.
  function automatic logic [159:0] f_ext32(input logic [31:0] w_x);
    f_ext32={{128{w_x[31]}},w_x};
  endfunction
  function automatic logic [159:0] f_ext64(input logic [63:0] w_x);
    f_ext64={{96{w_x[63]}},w_x};
  endfunction
  function automatic logic f_lt32(input logic [31:0] w_x,w_y);
    f_lt32=(w_x[31]!=w_y[31]) ? w_x[31] : w_x<w_y;
  endfunction

  // Outputs depend on registered state and payload; invalid channels drive zero.
  always_comb begin : p_com_outputs
    o_req_ready=1'b0; o_row_valid=1'b0; o_row_data='0;
    o_rsp_valid=1'b0; o_rsp_data='0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready=i_rst_n_core;
      ENUM_ST_ROW: begin o_row_valid=i_rst_n_core; if(i_rst_n_core) o_row_data=reg_row; end
      ENUM_ST_RESP: begin o_rsp_valid=i_rst_n_core; if(i_rst_n_core) o_rsp_data=reg_resp; end
      default: begin end
    endcase
  end

  // Profile lookup uses fixed library order, with explicit signed comparison.
  // Grid admission is a bounded equality decoder, not a synthesized remainder.
  always_comb begin : p_com_profile
    w_b=32'(32'd2000000*(32'(reg_cid[3:2])+32'd1));
    w_j='0;
    case(reg_cid[1:0])
      2'd0: w_j=32'd2000000;
      2'd1: w_j=32'd4000000;
      2'd2: w_j=32'd8000000;
      default: w_j='0;
    endcase
    w_target=32'(~w_b+32'd1);
    w_signed='0;
    if(reg_t>=32'd100000 && reg_vh!='0 && reg_start!=w_target)
      w_signed=f_lt32(w_target,reg_start) ? 32'(~w_j+32'd1) : w_j;
    w_grid=1'b0;
    for(int idx=0;idx<129;idx++) begin
      if(reg_epoch==32'(idx)*32'd100000) w_grid=1'b1;
    end
    w_range=(reg_req[47:40]<8'd16) && w_grid
      && reg_req[7:0]>=8'd1 && 32'(reg_req[7:0])<=PARA_MAX_CELLS
      && reg_req[7:0]<=8'd128 && reg_req[111:80]<=32'd10000000
      && (reg_req[79:48]=='0 || (reg_req[79] && reg_req[79:48]>=32'hff85ee00))
      && ((reg_req[175] && reg_req[175:112]>=64'hfffffffdabf41c00)
          || (!reg_req[175] && reg_req[175:112]<=64'd10000000000));
    w_stop_time=reg_stop_valid ? reg_stop : 32'(reg_t+32'd100000);
    w_held=(reg_vh=='0) && (reg_t+32'd100000>=w_stop_time+32'd2000000);
  end

  // One private arithmetic engine serves profile start/midpoint and both interval sides.
  // op0/1 are profile queries; op2/3 integrate lower/upper with directed rounding.
  always_comb begin : p_com_arith
    w_ar_req=1'b0; w_ar_data='0;
    if(reg_fsm_ctrl_current_state==ENUM_ST_ISSUE) begin
      w_ar_req=1'b1;
      case(reg_op)
        2'd0,2'd1: begin
          w_ar_data[1927:1920]=8'd5;
          w_ar_data[1919:1760]=160'(reg_cid);
          w_ar_data[1759:1600]=160'(reg_t-32'd100000);
          if(reg_op==2'd1) w_ar_data[1759:1600]=160'(reg_t-32'd50000);
          w_ar_data[1599:1440]=f_ext32(reg_a);
        end
        default: begin
          w_ar_data[1927:1920]=8'd7;
          w_ar_data[1919:1760]=(reg_op==2'd2) ? f_ext64(reg_xl) : f_ext64(reg_xh);
          w_ar_data[1759:1600]=(reg_op==2'd2) ? 160'(reg_vl) : 160'(reg_vh);
          w_ar_data[1599:1440]=f_ext32(reg_start);
          w_ar_data[1439:1280]=f_ext32(reg_jerk);
          w_ar_data[1279:1120]=f_ext32(w_target);
          w_ar_data[1119:960]=160'd100000;
          w_ar_data[959:800]=160'(reg_op==2'd3);
        end
      endcase
    end
  end

  // Stream each cell before computing the next. Terminal status follows all row handshakes.
  // Partial horizon rows remain provisional until the consumer sees terminal accept.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state=reg_fsm_ctrl_current_state;
    w_req_nxt=reg_req;
    w_t_nxt=reg_t;
    w_xl_nxt=reg_xl;
    w_xh_nxt=reg_xh;
    w_vl_nxt=reg_vl;
    w_vh_nxt=reg_vh;
    w_a_nxt=reg_a;
    w_cid_nxt=reg_cid;
    w_epoch_nxt=reg_epoch;
    w_limit_nxt=reg_limit;
    w_cnt_nxt=reg_cnt;
    w_stop_nxt=reg_stop;
    w_stop_valid_nxt=reg_stop_valid;
    w_start_nxt=reg_start;
    w_cmd_nxt=reg_cmd;
    w_jerk_nxt=reg_jerk;
    w_resp_nxt=reg_resp;
    w_row_nxt=reg_row;
    w_op_nxt=reg_op;
    w_final_nxt=reg_final;
    case(reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      ENUM_ST_IDLE: if(i_req_valid) begin
        w_req_nxt=i_req_data;
        w_xl_nxt=i_req_data[175:112]; w_xh_nxt=i_req_data[175:112];
        w_vl_nxt=i_req_data[111:80]; w_vh_nxt=i_req_data[111:80];
        w_a_nxt=i_req_data[79:48]; w_cid_nxt=i_req_data[47:40];
        w_epoch_nxt=i_req_data[39:8]; w_t_nxt=i_req_data[39:8];
        w_limit_nxt=i_req_data[7:0]; w_cnt_nxt='0;
        w_stop_nxt='0; w_stop_valid_nxt='0; w_final_nxt='0;
        w_resp_nxt='0; w_row_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_GUARD;
      end
      ENUM_ST_GUARD: begin
        if(w_range) w_fsm_ctrl_nxt_state=ENUM_ST_PREP;
        else begin
          w_resp_nxt={1'b0,8'd14,1'b0,32'd0,8'd0};
          w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end
      end
      ENUM_ST_PREP: begin
        w_start_nxt='0; w_cmd_nxt='0; w_jerk_nxt='0; w_op_nxt=2'd0;
        casez({reg_vh=='0,reg_t<32'd100000})
          2'b1?: w_fsm_ctrl_nxt_state=ENUM_ST_STEP;
          2'b01: begin
            w_start_nxt=reg_a; w_cmd_nxt=reg_a;
            w_fsm_ctrl_nxt_state=ENUM_ST_STEP;
          end
          default: w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
        endcase
      end
      ENUM_ST_ISSUE: if(w_ar_ready) w_fsm_ctrl_nxt_state=ENUM_ST_WAIT;
      ENUM_ST_WAIT: if(w_ar_valid) begin
        if(w_ar_resp[640]) begin
          w_resp_nxt={1'b0,8'd4,reg_stop_valid,reg_stop,reg_cnt};
          w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end else begin
          case(reg_op)
            2'd0: begin
              w_start_nxt=w_ar_resp[511:480]; w_op_nxt=2'd1;
              w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
            end
            2'd1: begin
              w_cmd_nxt=w_ar_resp[511:480];
              if(w_j==32'd0) w_start_nxt=w_ar_resp[511:480];
              w_jerk_nxt=w_signed;
              w_fsm_ctrl_nxt_state=ENUM_ST_STEP;
            end
            2'd2: begin
              w_xl_nxt=w_ar_resp[543:480]; w_vl_nxt=w_ar_resp[351:320];
              w_op_nxt=2'd3; w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
            end
            default: begin
              w_xh_nxt=w_ar_resp[543:480]; w_vh_nxt=w_ar_resp[351:320];
              w_fsm_ctrl_nxt_state=ENUM_ST_CHECK;
            end
          endcase
        end
      end
      ENUM_ST_STEP: begin
        // Row352 is the zero-extended golden Row288, matching pack_trajectory.
        w_row_nxt={reg_cid,reg_epoch,reg_cnt,64'd0,
          reg_t,reg_xl,reg_xh,reg_vl,reg_vh,reg_cmd,
          (reg_jerk[31] ? 32'(~reg_jerk+32'd1) : reg_jerk),
          1'b0};
        w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
      end
      ENUM_ST_ROW: if(1'b1) begin
        w_cnt_nxt=8'(reg_cnt+8'd1);
        if(reg_final) begin
          w_resp_nxt={1'b1,8'd0,reg_stop_valid,reg_stop,8'(reg_cnt+8'd1)};
          w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end else begin
          w_op_nxt=2'd2; w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
        end
      end
      ENUM_ST_CHECK: begin
        if(reg_vh=='0 && !reg_stop_valid) begin
          w_stop_nxt=32'(reg_t+32'd100000); w_stop_valid_nxt=1'b1;
        end
        w_t_nxt=32'(reg_t+32'd100000);
        casez({w_held,reg_cnt==reg_limit})
          2'b1?: begin w_final_nxt=1'b1; w_fsm_ctrl_nxt_state=ENUM_ST_END; end
          2'b01: begin
            w_resp_nxt={1'b0,8'd16,w_stop_valid_nxt,w_stop_nxt,reg_cnt};
            w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
          end
          default: w_fsm_ctrl_nxt_state=ENUM_ST_PREP;
        endcase
      end
      ENUM_ST_END: begin
        w_row_nxt={reg_cid,reg_epoch,reg_cnt,64'd0,
          reg_t,reg_xl,reg_xh,reg_vl,reg_vh,32'd0,32'd0,1'b1};
        w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
      end
      ENUM_ST_RESP: if(i_rsp_ready) w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      default: w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
    endcase
  end

  // Asynchronous assertion aborts the context and every private primitive tag.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if(!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT;
      reg_req<='0;
      reg_t<='0;
      reg_xl<='0;
      reg_xh<='0;
      reg_vl<='0;
      reg_vh<='0;
      reg_a<='0;
      reg_cid<='0;
      reg_epoch<='0;
      reg_limit<='0;
      reg_cnt<='0;
      reg_stop<='0;
      reg_stop_valid<='0;
      reg_start<='0;
      reg_cmd<='0;
      reg_jerk<='0;
      reg_resp<='0;
      reg_row<='0;
      reg_op<='0;
      reg_final<='0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_req<=w_req_nxt;
      reg_t<=w_t_nxt;
      reg_xl<=w_xl_nxt;
      reg_xh<=w_xh_nxt;
      reg_vl<=w_vl_nxt;
      reg_vh<=w_vh_nxt;
      reg_a<=w_a_nxt;
      reg_cid<=w_cid_nxt;
      reg_epoch<=w_epoch_nxt;
      reg_limit<=w_limit_nxt;
      reg_cnt<=w_cnt_nxt;
      reg_stop<=w_stop_nxt;
      reg_stop_valid<=w_stop_valid_nxt;
      reg_start<=w_start_nxt;
      reg_cmd<=w_cmd_nxt;
      reg_jerk<=w_jerk_nxt;
      reg_resp<=w_resp_nxt;
      reg_row<=w_row_nxt;
      reg_op<=w_op_nxt;
      reg_final<=w_final_nxt;
    end
  end

  // Public arithmetic protocol is fully drained before the next command can issue.
  m_tsmx_arith u_tsmx_arith (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_ar_req), .i_req_data(w_ar_data), .i_rsp_ready(1'b1),
    .o_req_ready(w_ar_ready), .o_rsp_valid(w_ar_valid), .o_rsp_data(w_ar_resp)
  );
endmodule
`default_nettype wire
