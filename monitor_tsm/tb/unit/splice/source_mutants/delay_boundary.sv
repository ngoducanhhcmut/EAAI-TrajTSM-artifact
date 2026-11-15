/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-02
 * Version      : 0.2
 * Description  : B2 eight-corner delayed reachability containment.
 * Assumptions  : Config1 constants locked; wrapper synchronizes reset release.
 * Deviations   : HIE-02 functional leaf; the enclosing system top is structural.
 *                PAR-03 literal field slices are the fixed section 9.2 wire ABI.
 * A8 (02/11)   : ego/plan acceleration range [-8,+2] m/s^2 and corner a clamped to
 *                [-8,+2] (golden b2_splice); legacy/m_tsmx_splice_pre_A8.sv.txt.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_splice #(
  localparam logic [31:0] LPARA_DX = 32'd50000,
  localparam logic [31:0] LPARA_DV = 32'd50000,
  localparam logic [31:0] LPARA_DA = 32'd100000,
  localparam logic [31:0] LPARA_TUBE_X = 32'd160000,
  localparam logic [31:0] LPARA_TUBE_V = 32'd200000,
  localparam logic [31:0] LPARA_MAX_DELAY = 32'd100000,
  localparam logic [31:0] LPARA_MAX_V = 32'd10000000,
  localparam logic [31:0] LPARA_MAX_A = 32'd8000000,
  localparam logic [31:0] LPARA_MAX_A_POS = 32'd2000000,
  localparam logic [31:0] LPARA_POS_UNIT = 32'd1000000000,
  localparam logic [31:0] LPARA_OP_ADVANCE = 32'd3
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [815:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic o_rsp_data
);
  typedef enum logic [2:0] {
    ENUM_ST_BOOT=3'd0, ENUM_ST_IDLE=3'd1, ENUM_ST_GUARD=3'd2,
    ENUM_ST_ISSUE=3'd3, ENUM_ST_WAIT=3'd4, ENUM_ST_RESP=3'd5
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [815:0] reg_req, w_req_nxt;
  logic [3:0] reg_corner, w_corner_nxt;
  logic reg_accept, w_accept_nxt;
  logic [63:0] w_x, w_v, w_a, w_px, w_pv, w_pa;
  logic [63:0] w_cx, w_cv, w_ca, w_rx, w_rv, w_pos_limit;
  logic [31:0] w_delay;
  logic w_guard, w_contained;
  logic [1927:0] w_arith_req;
  logic [640:0] w_arith_resp;
  logic w_arith_valid, w_arith_ready, w_arith_done, w_arith_take;

  // Unsigned containers preserve two's-complement ordering without language signedness.
  function automatic logic f_lt(input logic [63:0] w_l, w_r);
    f_lt = (w_l[63] != w_r[63]) ? w_l[63] : (w_l < w_r);
  endfunction
  function automatic logic f_range(input logic [63:0] w_value, w_lo, w_hi);
    f_range = !f_lt(w_value,w_lo) && !f_lt(w_hi,w_value);
  endfunction

  // Decode only fields consumed by golden B2; other fields remain in the snapshot.
  // All arithmetic below fits s64 after the ingress guard (position <=10000*S).
  always_comb begin : p_com_motion
    w_x = reg_req[783:720];
    w_v = {{32{reg_req[719]}},reg_req[719:688]};
    w_a = {{32{reg_req[687]}},reg_req[687:656]};
    w_px = reg_req[207:144];
    w_pv = {{32{reg_req[143]}},reg_req[143:112]};
    w_pa = {{32{reg_req[111]}},reg_req[111:80]};
    w_delay = 32'(reg_req[239:208]-reg_req[815:784]);
    w_pos_limit = 64'(64'd10 * 64'(LPARA_POS_UNIT));
    w_guard = f_range(w_x,64'(-w_pos_limit),w_pos_limit)
      && f_range(w_px,64'(-w_pos_limit),w_pos_limit)
      && f_range(w_v,64'd0,64'(LPARA_MAX_V))
      && f_range(w_pv,64'd0,64'(LPARA_MAX_V))
      && f_range(w_a,64'(-64'(LPARA_MAX_A)),64'(LPARA_MAX_A_POS))
      && f_range(w_pa,64'(-64'(LPARA_MAX_A)),64'(LPARA_MAX_A_POS))
      && (w_delay < LPARA_MAX_DELAY);
    w_cx = reg_corner[3] ? 64'(w_x+64'(LPARA_DX)) : 64'(w_x-64'(LPARA_DX));
    w_cv = reg_corner[2] ? 64'(w_v+64'(LPARA_DV)) : 64'(w_v-64'(LPARA_DV));
    if (w_cv[63]) w_cv = '0;
    w_ca = reg_corner[1] ? 64'(w_a+64'(LPARA_DA)) : 64'(w_a-64'(LPARA_DA));
    if (f_lt(64'(LPARA_MAX_A_POS),w_ca)) w_ca = 64'(LPARA_MAX_A_POS);
    if (f_lt(w_ca,64'(-64'(LPARA_MAX_A)))) w_ca = 64'(-64'(LPARA_MAX_A));
    w_rx = w_arith_resp[543:480];
    w_rv = w_arith_resp[383:320];
    w_contained = !w_arith_resp[640]
      && f_range(w_rx,64'(w_px-64'(LPARA_TUBE_X)),64'(w_px+64'(LPARA_TUBE_X)))
      && f_range(w_rv,64'(w_pv-64'(LPARA_TUBE_V)),64'(w_pv+64'(LPARA_TUBE_V)));
    w_arith_req = {8'(LPARA_OP_ADVANCE),{96{w_cx[63]}},w_cx,
      {96{w_cv[63]}},w_cv,{96{w_ca[63]}},w_ca,128'd0,w_delay,
      159'd0,reg_corner[0],1120'd0};
  end

  // Moore outputs hold a single response until consumption, with zero invalid payload.
  always_comb begin : p_com_outputs
    o_req_ready = 1'b0;
    o_rsp_valid = 1'b0;
    o_rsp_data = 1'b0;
    w_arith_valid = 1'b0;
    w_arith_take = 1'b0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready = i_rst_n_core;
      ENUM_ST_ISSUE: w_arith_valid = i_rst_n_core;
      ENUM_ST_WAIT: w_arith_take = i_rst_n_core;
      ENUM_ST_RESP: begin
        o_rsp_valid = i_rst_n_core;
        o_rsp_data = reg_accept && i_rst_n_core;
      end
      default: begin end
    endcase
  end

  // Sixteen serial outward jobs cover dx/dv/da and floor/ceil. Never short-circuit
  // an issued job: drain its response before advancing or returning to the caller.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_req_nxt = reg_req;
    w_corner_nxt = reg_corner;
    w_accept_nxt = reg_accept;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      ENUM_ST_IDLE: if (i_req_valid) begin
        w_req_nxt = i_req_data;
        w_corner_nxt = '0;
        w_accept_nxt = 1'b1;
        w_fsm_ctrl_nxt_state = ENUM_ST_GUARD;
      end
      ENUM_ST_GUARD: begin
        if (w_guard) w_fsm_ctrl_nxt_state = ENUM_ST_ISSUE;
        else begin
          w_accept_nxt = 1'b0;
          w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
        end
      end
      ENUM_ST_ISSUE: if (w_arith_ready) w_fsm_ctrl_nxt_state = ENUM_ST_WAIT;
      ENUM_ST_WAIT: if (w_arith_done) begin
        w_accept_nxt = reg_accept && w_contained;
        if (&reg_corner) w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
        else begin
          w_corner_nxt = 4'(reg_corner+1'b1);
          w_fsm_ctrl_nxt_state = ENUM_ST_ISSUE;
        end
      end
      ENUM_ST_RESP: if (i_rsp_ready) begin
        w_accept_nxt = 1'b0;
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      default: begin
        w_accept_nxt = 1'b0;
        w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
      end
    endcase
  end

  // Core reset aborts both the public context and private arithmetic pipeline.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_req <= '0;
      reg_corner <= '0;
      reg_accept <= 1'b0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_req <= w_req_nxt;
      reg_corner <= w_corner_nxt;
      reg_accept <= w_accept_nxt;
    end
  end

  // One private accepted arithmetic engine; no contention with any other block.
  // Only the op codes this block issues are built.
  m_tsmx_arith #(.PARA_OPS(9'h008)) u_tsmx_arith (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_arith_valid), .i_req_data(w_arith_req), .i_rsp_ready(w_arith_take),
    .o_req_ready(w_arith_ready), .o_rsp_valid(w_arith_done), .o_rsp_data(w_arith_resp)
  );
endmodule
`default_nettype wire
