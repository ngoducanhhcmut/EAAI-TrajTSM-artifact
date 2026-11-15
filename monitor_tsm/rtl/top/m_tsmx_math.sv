/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.3
 * Description  : Golden reaction, world propagation, bridge and original-epoch replay helpers.
 *                v0.2: o_world/o_bridge are ungated (engine samples them only with
 *                o_rsp_valid in NPROPW/PROPW/BRIDGEW); saves one LUT per bit.
 *                v0.3: propagation rotates the 32 object slots instead of indexing them:
 *                the current object is always slot 0, each processed (or skipped) slot
 *                moves to slot 31, and ROT finishes the 32 rotations so slot order is
 *                restored at RESP. Removes the 32:1 object read mux and the per-slot write
 *                decode; the world returned is unchanged, propagation is <=32 clocks longer.
 *                The world register has its own load/rotate process: folding it into the
 *                FSM made synthesis build one full-width mux per writing state (+3.7k LUT).
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_math (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [2:0] i_op,
  input wire [255:0] i_ego,
  input wire [8199:0] i_world,
  input wire [31:0] i_delay,
  input wire [559:0] i_plan,
  input wire [31:0] i_rear,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic o_ok,
  output logic [8199:0] o_world,
  output logic [703:0] o_bridge,
  output logic [95:0] o_pose
);
  typedef enum logic [26:0] {
    ENUM_ST_BOOT = 27'h1,
    ENUM_ST_IDLE = 27'h2,
    ENUM_ST_START = 27'h4,
    ENUM_ST_REGO = 27'h8,
    ENUM_ST_REGOW = 27'h10,
    ENUM_ST_RLEAD = 27'h20,
    ENUM_ST_RLEADW = 27'h40,
    ENUM_ST_RGAP = 27'h80,
    ENUM_ST_RGAPW = 27'h100,
    ENUM_ST_RGAP2 = 27'h200,
    ENUM_ST_RGAP2W = 27'h400,
    ENUM_ST_OBJ = 27'h800,
    ENUM_ST_OADV = 27'h1000,
    ENUM_ST_OADVW = 27'h2000,
    ENUM_ST_OADV2 = 27'h4000,
    ENUM_ST_OADV2W = 27'h8000,
    ENUM_ST_BLOW = 27'h10000,
    ENUM_ST_BLOWW = 27'h20000,
    ENUM_ST_BHIGH = 27'h40000,
    ENUM_ST_BHIGHW = 27'h80000,
    ENUM_ST_PHASE = 27'h100000,
    ENUM_ST_PROF = 27'h200000,
    ENUM_ST_PROFW = 27'h400000,
    ENUM_ST_CONT = 27'h800000,
    ENUM_ST_CONTW = 27'h1000000,
    ENUM_ST_RESP = 27'h2000000,
    ENUM_ST_ROT = 27'h4000000
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [2:0] reg_op, w_op_nxt;
  logic [255:0] reg_ego, w_ego_nxt;
  logic [8199:0] reg_world;
  logic w_wload, w_wrot;
  logic [255:0] w_wlast;
  logic [31:0] reg_delay, w_delay_nxt;
  logic [559:0] reg_plan, w_plan_nxt;
  logic [31:0] reg_rear, w_rear_nxt;
  logic reg_ok, w_ok_nxt;
  logic [7:0] reg_idx, w_idx_nxt;
  logic [63:0] reg_x, w_x_nxt;
  logic [31:0] reg_v, w_v_nxt;
  logic [31:0] reg_a, w_a_nxt;
  logic [63:0] reg_xh, w_xh_nxt;
  logic [31:0] reg_vh, w_vh_nxt;
  logic [63:0] reg_lx, w_lx_nxt;
  logic [31:0] reg_lv, w_lv_nxt;
  logic [31:0] reg_first, w_first_nxt;
  logic reg_up, w_up_nxt;
  logic [31:0] reg_event, w_event_nxt;
  logic [703:0] reg_bridge, w_bridge_nxt;
  logic [31:0] reg_t, w_t_nxt;
  logic [31:0] reg_h, w_h_nxt;
  logic [31:0] reg_target, w_target_nxt;
  logic [31:0] reg_jerk, w_jerk_nxt;
  logic w_arith_req_valid, w_arith_req_ready, w_arith_resp_valid;
  logic [1927:0] w_arith_req_data;
  logic [640:0] w_arith_resp_data;
  logic [255:0] w_object;
  logic [31:0] w_pa,w_j;

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
  function automatic logic [31:0] f_diff(input logic [31:0] w_a,w_b);
    f_diff=32'(w_a-w_b);
  endfunction
  function automatic logic [63:0] f_abs(input logic [63:0] w_x);
    f_abs=w_x[63] ? 64'(~w_x+64'd1) : w_x;
  endfunction
  // The object being propagated is always rotated into slot 0.
  assign w_object=reg_world[8191:7936];
  // Separate pure decodes avoid transient default writes retriggering their consumers.
  assign w_pa=(reg_t>=32'd100000 && reg_jerk==32'd0) ? reg_target : reg_a;
  assign w_j=(reg_t>=32'd100000 && w_pa!=reg_target && reg_jerk!=32'd0)
    ? (((w_pa[31]!=reg_target[31]) ? w_pa[31] : w_pa<reg_target)
       ? reg_jerk : 32'(-reg_jerk)) : 32'd0;
  // State-only request decode isolates the primitive's ready from its request payload.
  always_comb begin : p_com_ar_req
    w_arith_req_valid=1'b0; w_arith_req_data='0;
    case(reg_fsm_ctrl_current_state)
      ENUM_ST_REGO: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd3,f_s64(reg_ego[223:160]),f_s32(reg_ego[159:128]),160'd0,160'd285000,160'd1,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_RLEAD: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd3,f_s64(reg_ego[95:32]),f_s32(reg_ego[31:0]),f_s32(32'(-32'd4000000)),160'd285000,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_RGAP: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd4,f_s64(64'(reg_ego[95:32]-reg_ego[223:160]-64'd4800000)),f_s32(reg_ego[31:0]),f_s32(32'(-32'd4000000)),f_s32(reg_ego[159:128]),160'd0,160'd285000,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_RGAP2: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd4,f_s64(64'(reg_lx-reg_xh-64'd4800000)),f_s32(reg_lv),f_s32(32'(-32'd4000000)),f_s32(reg_vh),f_s32(32'(-32'd8000000)),160'd3000000,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_OADV: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd3,f_s64(reg_x),f_s32(reg_v),f_s32(reg_a),{128'd0,reg_first},{159'd0,reg_up},160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_OADV2: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd3,f_s64(reg_x),f_s32(reg_v),f_s32(w_object[31:0]),{128'd0,32'(reg_delay-reg_first)},{159'd0,reg_up},160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_BLOW: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd3,f_s64(reg_ego[223:160]),f_s32(reg_ego[159:128]),f_s32(reg_ego[127:96]),{128'd0,reg_delay},160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_BHIGH: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd3,f_s64(reg_ego[223:160]),f_s32(reg_ego[159:128]),f_s32(reg_ego[127:96]),{128'd0,reg_delay},160'd1,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_PROF: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd5,{152'd0,reg_plan[79:72]},{128'd0,32'(reg_t-32'd100000)},f_s32(reg_plan[111:80]),160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      ENUM_ST_CONT: begin w_arith_req_valid=1'b1; w_arith_req_data={8'd7,f_s64(reg_x),f_s32(reg_v),f_s32(w_pa),f_s32(w_j),f_s32(reg_target),{128'd0,reg_h},160'd0,160'd0,160'd0,160'd0,160'd0,160'd0}; end
      default: begin end
    endcase
  end

  // Defaults retain state; unused FSM encodings recover through BOOT.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_op_nxt = reg_op;
    w_ego_nxt = reg_ego;
    w_wload = 1'b0;
    w_wrot = 1'b0;
    w_wlast = w_object;
    w_delay_nxt = reg_delay;
    w_plan_nxt = reg_plan;
    w_rear_nxt = reg_rear;
    w_ok_nxt = reg_ok;
    w_idx_nxt = reg_idx;
    w_x_nxt = reg_x;
    w_v_nxt = reg_v;
    w_a_nxt = reg_a;
    w_xh_nxt = reg_xh;
    w_vh_nxt = reg_vh;
    w_lx_nxt = reg_lx;
    w_lv_nxt = reg_lv;
    w_first_nxt = reg_first;
    w_up_nxt = reg_up;
    w_event_nxt = reg_event;
    w_bridge_nxt = reg_bridge;
    w_t_nxt = reg_t;
    w_h_nxt = reg_h;
    w_target_nxt = reg_target;
    w_jerk_nxt = reg_jerk;
    o_req_ready=i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
    o_rsp_valid=i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_RESP;
    o_ok=o_rsp_valid && reg_ok;
    // Wide payloads are ungated: the engine samples them only with o_rsp_valid.
    o_world=reg_world;
    o_bridge=reg_bridge;
    o_pose=o_rsp_valid ? {reg_x,reg_v} : 96'd0;

    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      ENUM_ST_IDLE: begin
        if(i_req_valid) begin
        w_op_nxt = i_op;        w_ego_nxt = i_ego;        w_wload = 1'b1;        w_delay_nxt = i_delay;        w_plan_nxt = i_plan;        w_rear_nxt = i_rear;        w_ok_nxt = 1'b1;        w_bridge_nxt = 704'd0;        w_idx_nxt = 8'd0;        w_fsm_ctrl_nxt_state = ENUM_ST_START;
        end
      end
      ENUM_ST_START: begin
        case(reg_op)
          2'd0: begin
            if(reg_rear<=32'd285000) begin w_ok_nxt=1'b0;
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
            else w_fsm_ctrl_nxt_state=ENUM_ST_REGO;
          end
          3'd1,3'd4: begin
            if(reg_world[8199:8192]>8'd32) begin w_ok_nxt=1'b0;
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
            else w_fsm_ctrl_nxt_state=ENUM_ST_OBJ;
          end
          2'd2: w_fsm_ctrl_nxt_state=ENUM_ST_BLOW;
          2'd3: begin
            w_x_nxt=reg_plan[207:144]; w_v_nxt=reg_plan[143:112];
            w_t_nxt=32'd0;
            w_target_nxt=32'(-32'd2000000*(32'(reg_plan[79:72] >> 2)+32'd1));
            case(reg_plan[73:72])
              2'd0: w_jerk_nxt=32'd2000000;
              2'd1: w_jerk_nxt=32'd4000000;
              2'd2: w_jerk_nxt=32'd8000000;
              default: w_jerk_nxt=32'd0;
            endcase
            if(reg_delay[31] || reg_delay==32'd0) w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
            else w_fsm_ctrl_nxt_state=ENUM_ST_PHASE;
          end
          default: begin w_ok_nxt=1'b0; w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
        endcase
      end
      ENUM_ST_REGO: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_REGOW;
      end
      ENUM_ST_REGOW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_xh_nxt = w_arith_resp_data[543:480];        w_vh_nxt = w_arith_resp_data[351:320];
        w_fsm_ctrl_nxt_state = ENUM_ST_RLEAD;
          end
        end
      end
      ENUM_ST_RLEAD: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_RLEADW;
      end
      ENUM_ST_RLEADW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_lx_nxt = w_arith_resp_data[543:480];        w_lv_nxt = w_arith_resp_data[351:320];
        w_fsm_ctrl_nxt_state = ENUM_ST_RGAP;
          end
        end
      end
      ENUM_ST_RGAP: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_RGAPW;
      end
      ENUM_ST_RGAPW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_ok_nxt = !f_lt(w_arith_resp_data[543:480],64'd500000);
        w_fsm_ctrl_nxt_state = ENUM_ST_RGAP2;
          end
        end
      end
      ENUM_ST_RGAP2: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_RGAP2W;
      end
      ENUM_ST_RGAP2W: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_ok_nxt = reg_ok && !f_lt(w_arith_resp_data[543:480],64'd500000);
        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end
        end
      end
      ENUM_ST_OBJ: begin
        if(reg_idx>=reg_world[8199:8192]) w_fsm_ctrl_nxt_state=ENUM_ST_ROT;
        else begin
          w_x_nxt=w_object[255:192]; w_v_nxt=w_object[191:160];
          w_a_nxt=w_object[159:128]; w_event_nxt=w_object[63:32];
          w_first_nxt=(reg_delay<w_object[63:32]) ? reg_delay : w_object[63:32];
          w_up_nxt=reg_op!=3'd4 && f_lt(w_object[255:192],reg_ego[223:160]);
          w_fsm_ctrl_nxt_state=ENUM_ST_OADV;
        end
      end
      ENUM_ST_OADV: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_OADVW;
      end
      ENUM_ST_OADVW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_ROT;
          end else begin
        w_x_nxt = w_arith_resp_data[543:480];        w_v_nxt = w_arith_resp_data[351:320];
        w_fsm_ctrl_nxt_state = ENUM_ST_OADV2;
          end
        end
      end
      ENUM_ST_OADV2: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_OADV2W;
      end
      ENUM_ST_OADV2W: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_ROT;
          end else begin
        w_wrot=1'b1;
        w_wlast={ w_arith_resp_data[543:480],w_arith_resp_data[351:320],
          w_object[159:64],reg_event>reg_delay ? 32'(reg_event-reg_delay):32'd0,
          w_object[31:0] };
        w_idx_nxt=8'(reg_idx+8'd1);
        w_fsm_ctrl_nxt_state = ENUM_ST_OBJ;
          end
        end
      end
      ENUM_ST_BLOW: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_BLOWW;
      end
      ENUM_ST_BLOWW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_x_nxt = w_arith_resp_data[543:480];        w_v_nxt = w_arith_resp_data[351:320];
        w_fsm_ctrl_nxt_state = ENUM_ST_BHIGH;
          end
        end
      end
      ENUM_ST_BHIGH: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_BHIGHW;
      end
      ENUM_ST_BHIGHW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_bridge_nxt={
          64'd0,32'd0,reg_ego[223:160],reg_ego[223:160],
          reg_ego[159:128],reg_ego[159:128],reg_ego[127:96],32'd0,
          64'd0,reg_delay,reg_x,w_arith_resp_data[543:480],reg_v,w_arith_resp_data[351:320],reg_ego[127:96],32'd0};
        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end
        end
      end
      ENUM_ST_PHASE: begin
        w_h_nxt=(reg_delay-reg_t>32'd20000) ? 32'd20000 : 32'(reg_delay-reg_t);
        if(reg_t>=reg_delay || reg_t>=32'd12800000) w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        else begin
          if(reg_t<32'd100000) begin w_a_nxt=reg_plan[111:80];
            w_fsm_ctrl_nxt_state=ENUM_ST_CONT; end
          else w_fsm_ctrl_nxt_state=ENUM_ST_PROF;
        end
      end
      ENUM_ST_PROF: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_PROFW;
      end
      ENUM_ST_PROFW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_a_nxt = w_arith_resp_data[511:480];
        w_fsm_ctrl_nxt_state = ENUM_ST_CONT;
          end
        end
      end
      ENUM_ST_CONT: begin
        if(w_arith_req_ready) w_fsm_ctrl_nxt_state=ENUM_ST_CONTW;
      end
      ENUM_ST_CONTW: begin
        if(w_arith_resp_valid) begin
          if(w_arith_resp_data[640]) begin
        w_ok_nxt = 1'b0;        w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          end else begin
        w_x_nxt = w_arith_resp_data[543:480];        w_v_nxt = w_arith_resp_data[351:320];        w_t_nxt = 32'(reg_t+reg_h);
        w_fsm_ctrl_nxt_state = ENUM_ST_PHASE;
          end
        end
      end
      // Unprocessed slots rotate unchanged until all 32 are back in order.
      ENUM_ST_ROT: begin
        if(reg_idx>=8'd32) w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        else begin
          w_wrot=1'b1;
          w_idx_nxt=8'(reg_idx+8'd1);
        end
      end
      ENUM_ST_RESP: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      default: w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
    endcase

  end
  // Asynchronous assertion; the enclosing reset synchronizer releases this domain.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_op <= '0;
      reg_ego <= '0;
      reg_delay <= '0;
      reg_plan <= '0;
      reg_rear <= '0;
      reg_ok <= '0;
      reg_idx <= '0;
      reg_x <= '0;
      reg_v <= '0;
      reg_a <= '0;
      reg_xh <= '0;
      reg_vh <= '0;
      reg_lx <= '0;
      reg_lv <= '0;
      reg_first <= '0;
      reg_up <= '0;
      reg_event <= '0;
      reg_bridge <= '0;
      reg_t <= '0;
      reg_h <= '0;
      reg_target <= '0;
      reg_jerk <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_op <= w_op_nxt;
      reg_ego <= w_ego_nxt;
      reg_delay <= w_delay_nxt;
      reg_plan <= w_plan_nxt;
      reg_rear <= w_rear_nxt;
      reg_ok <= w_ok_nxt;
      reg_idx <= w_idx_nxt;
      reg_x <= w_x_nxt;
      reg_v <= w_v_nxt;
      reg_a <= w_a_nxt;
      reg_xh <= w_xh_nxt;
      reg_vh <= w_vh_nxt;
      reg_lx <= w_lx_nxt;
      reg_lv <= w_lv_nxt;
      reg_first <= w_first_nxt;
      reg_up <= w_up_nxt;
      reg_event <= w_event_nxt;
      reg_bridge <= w_bridge_nxt;
      reg_t <= w_t_nxt;
      reg_h <= w_h_nxt;
      reg_target <= w_target_nxt;
      reg_jerk <= w_jerk_nxt;
    end
  end
  // World store: one load source and one rotate source per bit, so each bit is a
  // two-input mux behind a clock enable.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_world
    if (!i_rst_n_core) reg_world <= '0;
    else if (w_wload) reg_world <= i_world;
    else if (w_wrot) reg_world[8191:0] <= {reg_world[7935:0],w_wlast};
  end
  // Only the op codes this block issues are built.
  m_tsmx_arith #(.PARA_OPS(9'h0b8)) u_arith (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_arith_req_valid),
    .i_req_data(w_arith_req_data),
    .o_req_ready(w_arith_req_ready),
    .o_rsp_valid(w_arith_resp_valid),
    .o_rsp_data(w_arith_resp_data),
    .i_rsp_ready(1'b1)
  );

endmodule
`default_nettype wire
