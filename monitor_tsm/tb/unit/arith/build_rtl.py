"""Generate the repetitive width-specific instances; all executable RTL is emitted."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'rtl/arith/m_tsmx_arith.sv'
header='''/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Shared checked integer and rational motion primitive controller.
 * Assumptions  : Wrapper synchronizes reset release. See R2_DECISIONS.md.
 * Deviations   : HIE-02: functional leaf; the system top is structural.
 *                PAR-03: literal SI quadratic coefficients follow golden exactly.
 *                A grouped combinational process avoids Icarus function sensitivity.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_arith (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1927:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [640:0] o_rsp_data
);
  typedef enum logic [3:0] {
    ENUM_ST_BOOT=4'd0, ENUM_ST_IDLE=4'd1, ENUM_ST_SETUP=4'd2,
    ENUM_ST_ROOT=4'd3, ENUM_ST_ISSUE=4'd4, ENUM_ST_WAIT=4'd5,
    ENUM_ST_RESP=4'd6
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [7:0] reg_op, w_op_nxt;
  logic [159:0] reg_q [0:11];
  logic [159:0] w_q_nxt [0:11];
  logic [640:0] reg_resp, w_resp_nxt;
  logic [31:0] reg_lo, reg_hi, w_lo_nxt, w_hi_nxt, w_mid;
  logic reg_stop, w_stop_nxt;
  logic [3:0] reg_issue, reg_recv, w_issue_nxt, w_recv_nxt;
  logic [159:0] reg_min, w_min_nxt;
  logic w_guard, w_unused, w_issue_valid, w_done, w_fault;
  logic [1:0] w_width;
  logic [159:0] w_num [0:1];
  logic [159:0] w_den [0:1];
  logic w_up [0:1];
  logic [159:0] w_quot [0:1];
  logic [639:0] w_ramp, w_root_ramp;
  logic [255:0] w_disp_0, w_disp_1;
  logic [191:0] w_disp_int;
  logic [159:0] w_time, w_vel_num, w_pose, w_vel, w_candidate;
  logic [159:0] w_pt_n [0:6];
  logic [159:0] w_pt_d [0:6];
  logic [6:0] w_pt_valid;
  logic [159:0] w_ea, w_eb, w_ua, w_ub, w_tn, w_td;
  logic w_active_a, w_active_b;
'''
funcs='''
  // Explicit two's-complement helpers; no signed language types or casts.
  function automatic logic f_lt(input logic [159:0] w_a, w_b);
    f_lt = (w_a[159] != w_b[159]) ? w_a[159] : (w_a < w_b);
  endfunction
  function automatic logic [159:0] f_abs(input logic [159:0] w_a);
    f_abs = w_a[159] ? 160'(~w_a + 1'b1) : w_a;
  endfunction
  function automatic logic f_fit(input logic [159:0] w_a, input logic [31:0] w_bits);
    logic [159:0] w_limit;
    begin
      w_limit = 160'd1 << (w_bits-1'b1);
      f_fit = (w_bits >= 32'd1) && (w_bits <= 32'd160) && (f_abs(w_a) < w_limit);
    end
  endfunction
  function automatic logic f_range(input logic [159:0] w_a, w_lo, w_hi);
    f_range = !f_lt(w_a,w_lo) && !f_lt(w_hi,w_a);
  endfunction

  // Rational displacement uses s128 products; stop clips before the quadratic.
  function automatic logic [255:0] f_disp(input logic [159:0] w_v,w_a,w_n,w_d);
    logic [127:0] w_num, w_den, w_am;
    begin
      w_am = 128'(f_abs(w_a));
      w_num = 128'(128'd2*128'(w_v)*128'(w_n)*128'd1000000*128'(w_d)
        +128'(w_a)*128'(w_n)*128'(w_n));
      w_den = 128'(128'd2000000000000*128'(w_d)*128'(w_d));
      if (w_a[159] && (128'(w_n)*w_am >= 128'(w_v)*128'd1000000*128'(w_d))) begin
        w_num = 128'(128'(w_v)*128'(w_v));
        w_den = 128'(128'd2*w_am);
      end
      f_disp = {w_num,w_den};
    end
  endfunction
  // Integer-time displacement has its own s96 expression and divider pipeline.
  function automatic logic [191:0] f_disp_int(input logic [159:0] w_v,w_a,w_h);
    logic [95:0] w_num, w_den, w_am;
    begin
      w_am = 96'(f_abs(w_a));
      w_num = 96'(96'd2000000*96'(w_v)*96'(w_h)+96'(w_a)*96'(w_h)*96'(w_h));
      w_den = 96'd2000000000000;
      if (w_a[159] && (96'(w_h)*w_am >= 96'(w_v)*96'd1000000)) begin
        w_num = 96'(96'(w_v)*96'(w_v));
        w_den = 96'(96'd2*w_am);
      end
      f_disp_int = {w_num,w_den};
    end
  endfunction
  // Bound-proven capped ramp: xn s160, xd u136, vn s112, vd u88.
  function automatic logic [639:0] f_ramp(input logic [159:0] w_v,w_a,w_j,w_target,w_h);
    logic [159:0] w_d,w_n,w_xn,w_xd,w_hd,w_tail;
    logic [111:0] w_vn;
    logic [87:0] w_vd;
    begin
      w_d = f_abs(w_j);
      if (w_d == '0) w_d = 160'd1;
      w_n = 160'(w_h*w_d);
      if (w_n > 160'(f_abs(160'(w_target-w_a))*160'd1000000))
        w_n = 160'(f_abs(160'(w_target-w_a))*160'd1000000);
      if (w_j == '0) w_n = '0;
      w_vd = 88'(88'd2000000000000*88'(w_d)*88'(w_d));
      w_vn = 112'(112'(w_v)*112'(w_vd)+112'd2000000*112'(w_a)*112'(w_h)
        *112'(w_d)*112'(w_d)+112'(w_j)*(112'd2*112'(w_n)*112'(w_h)*112'(w_d)
        -112'(w_n)*112'(w_n)));
      w_xd = 160'(160'd6000000000000000000*w_d*w_d*w_d);
      w_hd = 160'(w_h*w_d);
      w_tail = 160'(w_hd-w_n);
      w_xn = 160'(160'd6000000000000*w_v*w_h*w_d*w_d*w_d
        +160'd3000000*w_a*w_h*w_h*w_d*w_d*w_d
        +w_j*(w_hd*w_hd*w_hd-w_tail*w_tail*w_tail));
      f_ramp = {w_xn,w_xd,{{48{w_vn[111]}},w_vn},72'd0,w_vd};
    end
  endfunction
  // Library ordering is b2,b4,b6,b8, each with j2,j4,j8,instant.
  function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
    logic [159:0] w_b,w_j,w_change,w_result;
    logic [63:0] w_product;
    begin
      w_b = 160'((160'd2+(w_id>>2'd2)*160'd2)*160'd1000000);
      w_j = '0;
      case (w_id[1:0])
        2'd0: w_j=160'd2000000;
        2'd1: w_j=160'd4000000;
        2'd2: w_j=160'd8000000;
        default: w_j='0;
      endcase
      // j/T is the exact integer 2,4,8: no general division is needed.
      w_product='0;
      case (w_id[1:0])
        2'd0: w_product=64'(64'(w_t)*64'd2);
        2'd1: w_product=64'(64'(w_t)*64'd4);
        2'd2: w_product=64'(64'(w_t)*64'd8);
        default: w_product='0;
      endcase
      w_change={96'd0,w_product};
      if (w_t[159]) w_change='0;
      w_result=160'(w_initial+w_change);
      if (f_lt(160'(~w_b+1'b1),w_result)) w_result=160'(~w_b+1'b1);
      if (f_lt(w_result,160'(w_initial-w_change))) w_result=160'(w_initial-w_change);
      if (f_lt(160'd0,w_result)) w_result='0;
      if (w_j=='0) w_result=160'(~w_b+1'b1);
      f_profile=w_result;
    end
  endfunction
'''
body='''
  // Guard every consumed slot before arithmetic; padding is canonical zero.
  always_comb begin : p_com_guard
    w_guard=1'b0;
    w_unused=1'b0;
    for (int idx=0; idx<12; idx++) begin
      case (reg_op)
        8'd0,8'd1,8'd8: if (idx>=2 && reg_q[idx]!='0) w_unused=1'b1;
        8'd2,8'd3: if (idx>=5 && reg_q[idx]!='0) w_unused=1'b1;
        8'd4: if (idx>=6 && reg_q[idx]!='0) w_unused=1'b1;
        8'd5: if (idx>=3 && reg_q[idx]!='0) w_unused=1'b1;
        8'd6: if (idx>=5 && reg_q[idx]!='0) w_unused=1'b1;
        8'd7: if (idx>=7 && reg_q[idx]!='0) w_unused=1'b1;
        default: w_unused=1'b1;
      endcase
    end
    case (reg_op)
      8'd0: w_guard=(reg_q[1]>=160'd1 && reg_q[1]<=160'd160)
        && f_fit(reg_q[0],32'(reg_q[1]));
      8'd1: w_guard=f_fit(reg_q[0],32'd160) && !reg_q[1][159] && reg_q[1]!='0;
      8'd2: w_guard=f_range(reg_q[0],160'd0,160'd20000000)
        && f_range(reg_q[1],160'(-160'd8000000),160'd2000000)
        && reg_q[2]<160'd70368744177664 && reg_q[3]>0 && reg_q[3]<160'd16777216
        && reg_q[4]<=160'd1;
      8'd3: w_guard=f_fit(reg_q[0],32'd64)
        && f_range(reg_q[1],160'd0,160'd20000000)
        && f_range(reg_q[2],160'(-160'd8000000),160'd2000000)
        && reg_q[3]<=160'd12800000 && reg_q[4]<=160'd1;
      8'd4: w_guard=f_fit(reg_q[0],32'd64)
        && f_range(reg_q[1],160'd0,160'd20000000)
        && f_range(reg_q[2],160'(-160'd8000000),160'd2000000)
        && f_range(reg_q[3],160'd0,160'd20000000)
        && f_range(reg_q[4],160'(-160'd8000000),160'd2000000)
        && reg_q[5]<=160'd12800000;
      8'd5: w_guard=reg_q[0]<160'd16 && f_fit(reg_q[1],32'd32)
        && f_range(reg_q[2],160'(-160'd8000000),160'd0);
      8'd6: w_guard=f_range(reg_q[0],160'd0,160'd20000000)
        && f_range(reg_q[1],160'(-160'd8000000),160'd2000000)
        && f_range(reg_q[2],160'(-160'd8000000),160'd8000000)
        && f_range(reg_q[3],160'(-160'd8000000),160'd2000000)
        && reg_q[4]<=160'd100000;
      8'd7: w_guard=f_fit(reg_q[0],32'd64)
        && f_range(reg_q[1],160'd0,160'd20000000)
        && f_range(reg_q[2],160'(-160'd8000000),160'd2000000)
        && f_range(reg_q[3],160'(-160'd8000000),160'd8000000)
        && f_range(reg_q[4],160'(-160'd8000000),160'd2000000)
        && reg_q[5]<=160'd100000 && reg_q[6]<=160'd1;
      8'd8: w_guard=reg_q[0]<=160'd4294967295 && reg_q[1]<=160'd4294967295;
      default: w_guard=1'b0;
    endcase
    if (w_unused) w_guard=1'b0;
  end

  // Enumerate all possible stop phases without sorting: endpoints, stops, three roots.
  // A root is used only when its assumed active accelerations hold at that time.
  always_comb begin : p_com_points
    w_pt_valid=7'b0000011;
    w_ea='0; w_eb='0; w_ua='0; w_ub='0; w_tn='0; w_td='0;
    w_active_a=1'b0; w_active_b=1'b0;
    w_pt_n[0]='0; w_pt_d[0]=160'd1;
    w_pt_n[1]='0; w_pt_d[1]=160'd1;
    w_pt_n[2]='0; w_pt_d[2]=160'd1;
    w_pt_n[3]='0; w_pt_d[3]=160'd1;
    w_pt_n[4]='0; w_pt_d[4]=160'd1;
    w_pt_n[5]='0; w_pt_d[5]=160'd1;
    w_pt_n[6]='0; w_pt_d[6]=160'd1;
    if (reg_op==8'd4) begin
    w_pt_n[1]=reg_q[5];
    w_pt_n[2]=160'(reg_q[1]*160'd1000000);
    w_pt_d[2]=f_abs(reg_q[2]);
    w_pt_valid[2]=reg_q[2][159] && w_pt_n[2]>0
      && w_pt_n[2]<160'(reg_q[5]*w_pt_d[2]);
    w_pt_n[3]=160'(reg_q[3]*160'd1000000);
    w_pt_d[3]=f_abs(reg_q[4]);
    w_pt_valid[3]=reg_q[4][159] && w_pt_n[3]>0
      && w_pt_n[3]<160'(reg_q[5]*w_pt_d[3]);
    for (int idx=4; idx<7; idx++) begin
      w_ea=reg_q[2]; w_eb=reg_q[4]; w_ua=reg_q[1]; w_ub=reg_q[3];
      if (idx==5) begin w_eb='0; if (reg_q[4][159]) w_ub='0; end
      if (idx==6) begin w_ea='0; if (reg_q[2][159]) w_ua='0; end
      w_td=160'(w_ea-w_eb);
      w_tn=160'((w_ub-w_ua)*160'd1000000);
      if (w_td[159]) begin w_td=160'(~w_td+1'b1); w_tn=160'(~w_tn+1'b1); end
      w_active_a=!(reg_q[2][159] && 160'(reg_q[1]*160'd1000000*w_td)
        <=160'(w_tn*f_abs(reg_q[2])));
      w_active_b=!(reg_q[4][159] && 160'(reg_q[3]*160'd1000000*w_td)
        <=160'(w_tn*f_abs(reg_q[4])));
      w_pt_n[idx]=w_tn; w_pt_d[idx]=w_td;
      w_pt_valid[idx]=(w_td!='0) && !w_tn[159] && w_tn>0
        && w_tn<160'(reg_q[5]*w_td)
        && ((idx==6) ? !w_active_a : w_active_a)
        && ((idx==5) ? !w_active_b : w_active_b);
    end
    end
  end

  // Form two independent directed quotient jobs. Unselected pipelines receive bubbles.
  always_comb begin : p_com_jobs
    w_width=2'd2;
    w_mid=32'(({1'b0,reg_lo}+{1'b0,reg_hi})>>1'b1);
    w_time=reg_q[5];
    if (reg_stop) w_time={128'd0,reg_lo};
    w_ramp='0;
    if (reg_op==8'd7) w_ramp=f_ramp(reg_q[1],reg_q[2],reg_q[3],reg_q[4],w_time);
    if (reg_op==8'd6) w_ramp=f_ramp(reg_q[0],reg_q[1],reg_q[2],reg_q[3],reg_q[4]);
    w_root_ramp='0;
    if (reg_op==8'd7 && reg_fsm_ctrl_current_state==ENUM_ST_ROOT)
      w_root_ramp=f_ramp(reg_q[1],reg_q[2],reg_q[3],reg_q[4],{128'd0,w_mid});
    w_disp_0='0;
    w_disp_1='0;
    w_disp_int='0;
    w_vel_num='0;
    w_num[0]='0; w_num[1]='0;
    w_den[0]=160'd1; w_den[1]=160'd1;
    w_up[0]=1'b0; w_up[1]=1'b0;
    case (reg_op)
      8'd1: begin w_num[0]=reg_q[0]; w_den[0]=reg_q[1]; w_up[0]=1'b1; end
      8'd2: begin
        w_disp_0=f_disp(reg_q[0],reg_q[1],reg_q[2],reg_q[3]);
        w_width=2'd1;
        w_num[0]={{32{w_disp_0[255]}},w_disp_0[255:128]};
        w_den[0]={32'd0,w_disp_0[127:0]}; w_up[0]=reg_q[4][0];
      end
      8'd3: begin
        w_disp_int=f_disp_int(reg_q[1],reg_q[2],reg_q[3]);
        w_vel_num=160'(reg_q[1]*160'd1000000+reg_q[2]*reg_q[3]);
        w_width=2'd0;
        w_num[0]={{64{w_disp_int[191]}},w_disp_int[191:96]};
        w_den[0]={64'd0,w_disp_int[95:0]}; w_up[0]=reg_q[4][0];
        w_num[1]=w_vel_num; w_den[1]=160'd1000000; w_up[1]=reg_q[4][0];
      end
      8'd4: begin
        w_width=2'd1;
        if (reg_issue<4'd7 && w_pt_valid[reg_issue]) begin
          w_disp_0=f_disp(reg_q[1],reg_q[2],w_pt_n[reg_issue],w_pt_d[reg_issue]);
          w_disp_1=f_disp(reg_q[3],reg_q[4],w_pt_n[reg_issue],w_pt_d[reg_issue]);
          w_num[0]={{32{w_disp_0[255]}},w_disp_0[255:128]};
          w_den[0]={32'd0,w_disp_0[127:0]};
          w_num[1]={{32{w_disp_1[255]}},w_disp_1[255:128]};
          w_den[1]={32'd0,w_disp_1[127:0]};
        end
        w_up[1]=1'b1;
      end
      8'd7: begin
        w_num[0]=w_ramp[639:480]; w_den[0]=w_ramp[479:320]; w_up[0]=reg_q[6][0];
        w_num[1]=w_ramp[319:160]; w_den[1]=w_ramp[159:0]; w_up[1]=reg_q[6][0];
        if (reg_stop) begin
          w_num[1]=reg_q[1]; w_den[1]=160'd1000000; w_up[1]=1'b1;
        end
      end
      default: begin end
    endcase
    w_issue_valid=(reg_fsm_ctrl_current_state==ENUM_ST_ISSUE);
  end

  // Combine completed quotients independently of the request coefficient process.
  always_comb begin : p_com_result
    w_pose=160'(reg_q[0]+w_quot[0]);
    w_vel=w_quot[1];
    if (w_vel[159]) w_vel='0;
    if (reg_op==8'd7 && reg_stop) begin
      w_vel='0;
      if (reg_q[6][0]) w_pose=160'(w_pose+w_quot[1]);
    end
    w_candidate=160'(reg_q[0]+w_quot[0]-w_quot[1]);
  end

  // State-only public outputs; response payload is canonical zero while invalid.
  always_comb begin : p_com_output
    o_req_ready=1'b0; o_rsp_valid=1'b0; o_rsp_data='0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready=i_rst_n_core;
      ENUM_ST_RESP: begin
        o_rsp_valid=i_rst_n_core;
        if (i_rst_n_core) o_rsp_data=reg_resp;
      end
      default: begin end
    endcase
  end

  // One request context is retained until consumption. Faults erase every pose slot.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state=reg_fsm_ctrl_current_state;
    w_op_nxt=reg_op; w_resp_nxt=reg_resp;
    w_lo_nxt=reg_lo; w_hi_nxt=reg_hi; w_stop_nxt=reg_stop;
    w_issue_nxt=reg_issue; w_recv_nxt=reg_recv; w_min_nxt=reg_min;
    w_q_nxt[0]=reg_q[0];
    w_q_nxt[1]=reg_q[1];
    w_q_nxt[2]=reg_q[2];
    w_q_nxt[3]=reg_q[3];
    w_q_nxt[4]=reg_q[4];
    w_q_nxt[5]=reg_q[5];
    w_q_nxt[6]=reg_q[6];
    w_q_nxt[7]=reg_q[7];
    w_q_nxt[8]=reg_q[8];
    w_q_nxt[9]=reg_q[9];
    w_q_nxt[10]=reg_q[10];
    w_q_nxt[11]=reg_q[11];
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      ENUM_ST_IDLE: if (i_req_valid) begin
        w_op_nxt=i_req_data[1927:1920];
        for (int idx=0; idx<12; idx++) w_q_nxt[idx]=i_req_data[1919-idx*160 -:160];
        w_resp_nxt='0; w_lo_nxt='0; w_stop_nxt=1'b0;
        w_issue_nxt='0; w_recv_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_SETUP;
      end
      ENUM_ST_SETUP: begin
        w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
        w_min_nxt=reg_q[0];
        if (!w_guard) begin
          w_resp_nxt={1'b1,640'd0}; w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end else begin
          case (reg_op)
            8'd0: begin
              w_resp_nxt={1'b0,reg_q[0],480'd0}; w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
            end
            8'd5: begin
              w_resp_nxt={1'b0,f_profile(reg_q[0],reg_q[1],reg_q[2]),480'd0};
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
            end
            8'd6: begin w_resp_nxt={1'b0,w_ramp}; w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
            8'd7: if (w_ramp[319]) begin
              w_stop_nxt=1'b1; w_hi_nxt=32'(reg_q[5]);
              w_fsm_ctrl_nxt_state=ENUM_ST_ROOT;
            end
            8'd8: begin
              w_resp_nxt={1'b0,128'd0,32'(reg_q[0]-reg_q[1]),480'd0};
              w_resp_nxt[639:512]={128{w_resp_nxt[511]}};
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
            end
            default: begin end
          endcase
        end
      end
      ENUM_ST_ROOT: begin
        if (reg_hi-reg_lo<=32'd1) w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
        else if (w_root_ramp[319]) w_hi_nxt=w_mid;
        else w_lo_nxt=w_mid;
      end
      ENUM_ST_ISSUE: begin
        w_issue_nxt=4'(reg_issue+1'b1);
        if (reg_op!=8'd4 || reg_issue==4'd6) w_fsm_ctrl_nxt_state=ENUM_ST_WAIT;
      end
      ENUM_ST_WAIT: begin end
      ENUM_ST_RESP: if (i_rsp_ready) begin
        w_resp_nxt='0; w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      end
      default: begin w_resp_nxt='0; w_fsm_ctrl_nxt_state=ENUM_ST_BOOT; end
    endcase
    if (w_done && (reg_fsm_ctrl_current_state==ENUM_ST_WAIT
      || reg_fsm_ctrl_current_state==ENUM_ST_ISSUE)) begin
      w_recv_nxt=4'(reg_recv+1'b1);
      case (reg_op)
        8'd3,8'd7: begin
          w_resp_nxt={1'b0,w_pose,w_vel,320'd0};
          if (w_fault || !f_fit(w_pose,32'd64) || !f_fit(w_vel,32'd32))
            w_resp_nxt={1'b1,640'd0};
          w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end
        8'd4: begin
          if (w_pt_valid[reg_recv] && f_lt(w_candidate,reg_min)) w_min_nxt=w_candidate;
          if (w_fault || (w_pt_valid[reg_recv] && !f_fit(w_candidate,32'd64))) begin
            w_resp_nxt={1'b1,640'd0};
          end
          if (reg_recv==4'd6) begin
            if (!w_resp_nxt[640]) w_resp_nxt={1'b0,w_min_nxt,480'd0};
            w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
          end
        end
        default: begin
          w_resp_nxt={1'b0,w_quot[0],480'd0};
          if (w_fault || (reg_op==8'd2 && !f_fit(w_quot[0],32'd64)))
            w_resp_nxt={1'b1,640'd0};
          w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end
      endcase
    end
  end

  // Asynchronous assertion clears all context and pipeline validity; wrapper releases reset.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT; reg_op<='0; reg_resp<='0;
      reg_lo<='0; reg_hi<='0; reg_stop<=1'b0; reg_issue<='0; reg_recv<='0; reg_min<='0;
      for (int idx=0; idx<12; idx++) reg_q[idx]<='0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state; reg_op<=w_op_nxt;
      reg_resp<=w_resp_nxt; reg_lo<=w_lo_nxt; reg_hi<=w_hi_nxt; reg_stop<=w_stop_nxt;
      reg_issue<=w_issue_nxt; reg_recv<=w_recv_nxt; reg_min<=w_min_nxt;
      for (int idx=0; idx<12; idx++) reg_q[idx]<=w_q_nxt[idx];
    end
  end
'''
decls=''
inst=''
for k,w in enumerate((96,128,160)):
    for lane in range(2):
        name=f'{k}_{lane}'
        decls+=f'  logic w_valid_{name}, w_fault_{name};\n  logic [{w-1}:0] w_data_{name};\n'
        inst+=f'''  m_tsmx_arith_div #(.PARA_W(32'd{w})) u_div_{k*2+lane} (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_valid(w_issue_valid && w_width==2'd{k}),
    .i_num(w_num[{lane}][{w-1}:0]), .i_den(w_den[{lane}][{w-1}:0]), .i_up(w_up[{lane}]),
    .o_valid(w_valid_{name}), .o_fault(w_fault_{name}), .o_data(w_data_{name})
  );
'''
mux='''
  // Fixed width classes prevent an integer-time operation from paying for s160 arithmetic.
  always_comb begin : p_com_div_mux
    w_done=1'b0; w_fault=1'b0; w_quot[0]='0; w_quot[1]='0;
    case (w_width)
'''
for k,w in enumerate((96,128,160)):
    mux+=f'''      2'd{k}: begin
        w_done=w_valid_{k}_0 && w_valid_{k}_1;
        w_fault=w_fault_{k}_0 || w_fault_{k}_1;
'''
    for lane in range(2):
        mux+=f'        w_quot[{lane}]={{{{{160-w}{{w_data_{k}_{lane}[{w-1}]}}}},w_data_{k}_{lane}}};\n' if w<160 else f'        w_quot[{lane}]=w_data_{k}_{lane};\n'
    mux+='      end\n'
mux+='''      default: begin end
    endcase
  end
'''
OUT.parent.mkdir(parents=True,exist_ok=True)
import re
combined=body+mux
blocks={}
def take(m):
    blocks[m[1]]=m[2]
    return ''
combined=re.sub(r'  always_comb begin : (\w+)\n(.*?)\n  end\n',take,combined,flags=re.S)
order=('p_com_guard','p_com_points','p_com_jobs','p_com_div_mux','p_com_result','p_com_output','p_com_ctrl')
math='  // One arithmetic process avoids cross-process automatic-function sensitivity.\n  always_comb begin : p_com_math\n'
for name in order:
    math+='    // '+name+': grouped arithmetic and controller equations.\n'+blocks[name]+'\n'
math+='  end\n'
OUT.write_text(header+decls+funcs+math+combined+'\n  // Private width-class pipelines, paired for displacement and velocity.\n'+inst+'endmodule\n`default_nettype wire\n',encoding='ascii')
print(OUT)
