/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Exact swept quadratic minimum using private accepted II1 dividers.
 * Assumptions  : Reset release is synchronized by the enclosing core wrapper.
 *                Row storage is resetless and guarded by the reset row count.
 * Deviations   : HIE-02: functional leaf; the enclosing system top is structural.
 *                PAR-03: SI coefficients and ABI bit positions follow golden exactly.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_geom_swept (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1927:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [640:0] o_rsp_data
);
  logic [0:0] reg_busy, w_busy_nxt;
  logic [0:0] reg_done, w_done_nxt;
  logic [0:0] reg_fault, w_fault_nxt;
  logic [2:0] reg_issue, w_issue_nxt;
  logic [2:0] reg_recv, w_recv_nxt;
  logic [383:0] reg_q, w_q_nxt;
  logic [63:0] reg_min, w_min_nxt;
  logic [63:0] w_gap,w_va,w_aa,w_vb,w_ab,w_h,w_ea,w_eb,w_ua,w_ub,w_tn,w_td;
  logic [127:0] w_num_0,w_num_1,w_den_0,w_den_1,w_q_0,w_q_1;
  logic [255:0] w_disp_0,w_disp_1;
  logic [63:0] w_result;
  logic w_en,w_point,w_active_a,w_active_b,w_valid_0,w_valid_1,w_fault_0,w_fault_1;

  // Seven candidate slots cover endpoints, both stops and three active-acceleration phases.
  function automatic logic [63:0] f_abs(input logic [63:0] w_a);
    f_abs=w_a[63] ? 64'(~w_a+64'd1) : w_a;
  endfunction
  function automatic logic f_lt(input logic [63:0] w_a,w_b);
    f_lt=w_a[63]!=w_b[63] ? w_a[63] : w_a<w_b;
  endfunction
  function automatic logic [255:0] f_disp(input logic [63:0] w_v,w_a,w_n,w_d);
    logic [127:0] w_num,w_den,w_acc;
    begin
      w_acc={{64{w_a[63]}},w_a};
      w_num=128'(128'd2000000*128'(w_v)*128'(w_n)*128'(w_d)
        +w_acc*128'(w_n)*128'(w_n));
      w_den=128'(128'd2000000000000*128'(w_d)*128'(w_d));
      if (w_a[63] && 128'(w_n)*128'(f_abs(w_a))
        >=128'(w_v)*128'd1000000*128'(w_d)) begin
        w_num=128'(128'(w_v)*128'(w_v));
        w_den=128'(128'd2*128'(f_abs(w_a)));
      end
      f_disp={w_num,w_den};
    end
  endfunction

  // Rational-time candidates are issued consecutively; invalid slots issue harmless zero work.
  always_comb begin : p_com_math
    {w_gap,w_va,w_aa,w_vb,w_ab,w_h}=reg_q;
    o_req_ready=i_rst_n_core && !reg_busy;
    o_rsp_valid=i_rst_n_core && reg_done;
    o_rsp_data='0;
    if (o_rsp_valid) o_rsp_data={reg_fault,{{96{reg_min[63]}},reg_min},480'd0};
    w_en=reg_busy && reg_issue<3'd7;
    w_point=1'b0;w_tn='0;w_td=64'd1;
    w_ea=w_aa;w_eb=w_ab;w_ua=w_va;w_ub=w_vb;
    w_active_a=1'b0;w_active_b=1'b0;
    case (reg_issue)
      3'd0: w_point=1'b1;
      3'd1: begin w_tn=w_h;w_point=1'b1;end
      3'd2: begin
        w_tn=64'(w_va*64'd1000000);w_td=f_abs(w_aa);
        w_point=w_aa[63] && w_tn>64'd0 && 128'(w_tn)<128'(w_h)*128'(w_td);
      end
      3'd3: begin
        w_tn=64'(w_vb*64'd1000000);w_td=f_abs(w_ab);
        w_point=w_ab[63] && w_tn>64'd0 && 128'(w_tn)<128'(w_h)*128'(w_td);
      end
      3'd4,3'd5,3'd6: begin
        if (reg_issue==3'd5)begin w_eb='0;if(w_ab[63])w_ub='0;end
        if (reg_issue==3'd6)begin w_ea='0;if(w_aa[63])w_ua='0;end
        w_td=64'(w_ea-w_eb);w_tn=64'((w_ub-w_ua)*64'd1000000);
        if(w_td[63])begin w_td=64'(~w_td+64'd1);w_tn=64'(~w_tn+64'd1);end
        w_active_a=!(w_aa[63] && 128'(w_va)*128'd1000000*128'(w_td)
          <=128'(w_tn)*128'(f_abs(w_aa)));
        w_active_b=!(w_ab[63] && 128'(w_vb)*128'd1000000*128'(w_td)
          <=128'(w_tn)*128'(f_abs(w_ab)));
        w_point=1'b0 && w_td!=64'd0 && !w_tn[63] && w_tn>64'd0
          && 128'(w_tn)<128'(w_h)*128'(w_td)
          && (reg_issue==3'd6 ? !w_active_a : w_active_a)
          && (reg_issue==3'd5 ? !w_active_b : w_active_b);
      end
      default: w_point=1'b0;
    endcase
    w_disp_0={128'd0,128'd1};w_disp_1={128'd0,128'd1};
    if (w_en && w_point) begin
      w_disp_0=f_disp(w_va,w_aa,w_tn,w_td);
      w_disp_1=f_disp(w_vb,w_ab,w_tn,w_td);
    end
    {w_num_0,w_den_0}=w_disp_0;{w_num_1,w_den_1}=w_disp_1;
    w_result=64'(w_gap+w_q_0[63:0]-w_q_1[63:0]);
    w_busy_nxt=reg_busy;w_done_nxt=reg_done;w_fault_nxt=reg_fault;
    w_issue_nxt=reg_issue;w_recv_nxt=reg_recv;w_q_nxt=reg_q;w_min_nxt=reg_min;
    if (i_req_valid && o_req_ready)begin
      w_busy_nxt=1'b1;w_done_nxt=1'b0;w_fault_nxt=1'b0;w_issue_nxt='0;w_recv_nxt='0;
      w_q_nxt={i_req_data[1823:1760],i_req_data[1663:1600],i_req_data[1503:1440],
        i_req_data[1343:1280],i_req_data[1183:1120],i_req_data[1023:960]};
      w_min_nxt=64'h7fffffffffffffff;
    end
    if(w_en)w_issue_nxt=3'(reg_issue+3'd1);
    if(w_valid_0 && w_valid_1 && reg_recv<3'd7)begin
      w_fault_nxt=reg_fault || w_fault_0 || w_fault_1;
      if(f_lt(w_result,reg_min))w_min_nxt=w_result;
      w_recv_nxt=3'(reg_recv+3'd1);
      if(reg_recv==3'd6)w_done_nxt=1'b1;
    end
    if(reg_done && i_rsp_ready)begin w_busy_nxt=1'b0;w_done_nxt=1'b0;end
  end

  // Asynchronous reset clears all outstanding work and response ownership.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_state
    if(!i_rst_n_core)begin
      reg_busy<='0;
      reg_done<='0;
      reg_fault<='0;
      reg_issue<='0;
      reg_recv<='0;
      reg_q<='0;
      reg_min<='0;
    end else begin
      reg_busy<=w_busy_nxt;
      reg_done<=w_done_nxt;
      reg_fault<=w_fault_nxt;
      reg_issue<=w_issue_nxt;
      reg_recv<=w_recv_nxt;
      reg_q<=w_q_nxt;
      reg_min<=w_min_nxt;
    end
  end

  // Front floors and rear ceils each use a private fully pipelined rational divider.
  m_tsmx_arith_div #(.PARA_W(32'd128)) u_arith_div_0 (
    .i_clk_core(i_clk_core),.i_rst_n_core(i_rst_n_core),.i_valid(w_en),
    .i_num(w_num_0),.i_den(w_den_0),.i_up(1'b0),
    .o_valid(w_valid_0),.o_fault(w_fault_0),.o_data(w_q_0)
  );
  m_tsmx_arith_div #(.PARA_W(32'd128)) u_arith_div_1 (
    .i_clk_core(i_clk_core),.i_rst_n_core(i_rst_n_core),.i_valid(w_en),
    .i_num(w_num_1),.i_den(w_den_1),.i_up(1'b1),
    .o_valid(w_valid_1),.o_fault(w_fault_1),.o_data(w_q_1)
  );
endmodule
`default_nettype wire
