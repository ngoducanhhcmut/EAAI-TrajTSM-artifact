/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-30
 * Version      : 0.2
 * Description  : All sixteen candidates, paired streaming contexts with terminal validation.
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_sweep #(
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_G = 32'd8,
  // Parameter Description: replicated private candidate resources.
  // Parameter values: 1,2,4,8; default 8.
  // Parameter unit: count
  parameter logic [31:0] PARA_P = 32'd8,
  localparam logic [31:0] LPARA_PAIR_NUM = (PARA_G<PARA_P) ? PARA_G : PARA_P
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [127:0] i_pose,
  input wire [31:0] i_epoch,
  input wire [8199:0] i_world,
  input wire [383:0] i_lane,
  input wire [1:0] i_kind,
  input wire [703:0] i_bridge,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [15:0] o_rsp_data
);
  typedef enum logic [3:0] {
    ENUM_ST_BOOT = 4'h1,
    ENUM_ST_IDLE = 4'h2,
    ENUM_ST_RUN = 4'h4,
    ENUM_ST_RESP = 4'h8
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [127:0] reg_pose, w_pose_nxt;
  logic [31:0] reg_epoch, w_epoch_nxt;
  logic [8199:0] reg_world, w_world_nxt;
  logic [383:0] reg_lane, w_lane_nxt;
  logic [1:0] reg_kind, w_kind_nxt;
  logic [703:0] reg_bridge, w_bridge_nxt;
  logic [7:0] reg_base, w_base_nxt;
  logic [15:0] reg_mask, w_mask_nxt;
  logic [7:0] reg_mrm_sent, w_mrm_sent_nxt;
  logic [7:0] reg_geom_sent, w_geom_sent_nxt;
  logic [7:0] reg_done, w_done_nxt;
  logic [1:0] reg_row, w_row_nxt;
  logic [PARA_G-1:0] w_mrm_req_valid,w_mrm_req_ready,w_mrm_row_valid,w_mrm_row_ready,w_mrm_resp_valid,w_mrm_resp_ready;
  logic [PARA_G*176-1:0] w_mrm_req_data;
  logic [PARA_G*401-1:0] w_mrm_row_data;
  logic [PARA_G*50-1:0] w_mrm_resp_data;
  logic [PARA_P-1:0] w_geom_req_valid,w_geom_req_ready,w_geom_row_valid,w_geom_row_ready,w_geom_terminal_valid,w_geom_terminal_ready,w_geom_resp_valid;
  logic [PARA_P*8624-1:0] w_geom_req_data;
  logic [PARA_P*401-1:0] w_geom_row_data;
  logic [PARA_P*50-1:0] w_geom_terminal_data;
  logic [PARA_P*81-1:0] w_geom_resp_data;
  logic [7:0] w_active;


  // v0.2: geom request payload is ungated; B3 samples it only with i_req_valid,
  // and the registered world is stable for the whole RUN state.
  for(genvar gen_idx=0;gen_idx<PARA_P;gen_idx++) begin : gen_greq
    assign w_geom_req_data[8624*gen_idx +:8624]={8'(reg_base+8'(gen_idx)),reg_epoch,reg_world,reg_lane};
  end

  // Defaults retain state; unused FSM encodings recover through BOOT.
  always @* begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_pose_nxt = reg_pose;
    w_epoch_nxt = reg_epoch;
    w_world_nxt = reg_world;
    w_lane_nxt = reg_lane;
    w_kind_nxt = reg_kind;
    w_bridge_nxt = reg_bridge;
    w_base_nxt = reg_base;
    w_mask_nxt = reg_mask;
    w_mrm_sent_nxt = reg_mrm_sent;
    w_geom_sent_nxt = reg_geom_sent;
    w_done_nxt = reg_done;
    w_row_nxt = reg_row;
    o_req_ready = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
    o_rsp_valid = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_RESP;
    o_rsp_data = o_rsp_valid ? reg_mask : 16'd0;
    w_mrm_req_valid='0; w_mrm_req_data='0; w_mrm_row_ready='0; w_mrm_resp_ready='0;
    w_geom_req_valid='0; w_geom_row_valid='0; w_geom_row_data='0; w_geom_terminal_valid='0; w_geom_terminal_data='0;
    w_active='0;
    for (int idx=0;idx<LPARA_PAIR_NUM;idx++) begin
      w_active[idx] = (reg_kind==2'd0) || idx==0;
    end
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
      end
      ENUM_ST_IDLE: begin
        if(i_req_valid) begin
        w_pose_nxt = i_pose;        w_epoch_nxt = i_epoch;        w_world_nxt = i_world;        w_lane_nxt = i_lane;        w_kind_nxt = i_kind;        w_bridge_nxt = i_bridge;        w_base_nxt = i_kind==2'd1 ? 8'd15 : 8'd0;        w_mask_nxt = 16'd0;        w_mrm_sent_nxt = 8'd0;        w_geom_sent_nxt = 8'd0;        w_done_nxt = 8'd0;        w_row_nxt = 2'd0;        w_fsm_ctrl_nxt_state = ENUM_ST_RUN;
        end
      end
      ENUM_ST_RUN: begin
        for(int idx=0;idx<LPARA_PAIR_NUM;idx++) begin
          if(w_active[idx]) begin
            w_geom_req_valid[idx]=!reg_geom_sent[idx];
            if(w_geom_req_valid[idx] && w_geom_req_ready[idx]) w_geom_sent_nxt[idx]=1'b1;
            if(reg_kind!=2'd2) begin
              w_mrm_req_valid[idx]=reg_geom_sent[idx] && !reg_mrm_sent[idx];
              w_mrm_req_data[176*idx +:176]={reg_pose,8'(reg_base+8'(idx)),reg_epoch,8'd128};
              if(w_mrm_req_valid[idx] && w_mrm_req_ready[idx]) w_mrm_sent_nxt[idx]=1'b1;
              w_geom_row_valid[idx]=w_mrm_row_valid[idx]; w_geom_row_data[401*idx +:401]=w_mrm_row_data[401*idx +:401];
              w_mrm_row_ready[idx]=w_geom_row_ready[idx];
              w_geom_terminal_valid[idx]=w_mrm_resp_valid[idx]; w_geom_terminal_data[50*idx +:50]=w_mrm_resp_data[50*idx +:50];
              w_mrm_resp_ready[idx]=w_geom_terminal_ready[idx];
            end
            if(w_geom_resp_valid[idx] && !reg_done[idx]) begin
              w_done_nxt[idx]=1'b1;
              w_mask_nxt[reg_base+8'(idx)]=w_geom_resp_data[81*idx+80];
            end
          end
        end
        if(reg_kind==2'd2 && reg_geom_sent[0]) begin
          w_geom_row_valid[0]=reg_row<2'd2;
          w_geom_row_data[0 +:401]={8'd0,reg_epoch,8'(reg_row),
            reg_bridge[703-352*32'(reg_row[0]) -:352],reg_row==2'd1};
          if(w_geom_row_valid[0] && w_geom_row_ready[0]) w_row_nxt=2'(reg_row+2'd1);
          w_geom_terminal_valid[0]=reg_row==2'd2;
          w_geom_terminal_data[0 +:50]={1'b1,8'd0,1'b0,32'd0,8'd2};
        end
        if((reg_done & w_active)==w_active) begin
          if(reg_kind==2'd0 && reg_base+8'(LPARA_PAIR_NUM)<8'd16) begin
            w_base_nxt=8'(reg_base+8'(LPARA_PAIR_NUM));
            w_mrm_sent_nxt='0; w_geom_sent_nxt='0; w_done_nxt='0;
          end else w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
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
      reg_pose <= '0;
      reg_epoch <= '0;
      reg_world <= '0;
      reg_lane <= '0;
      reg_kind <= '0;
      reg_bridge <= '0;
      reg_base <= '0;
      reg_mask <= '0;
      reg_mrm_sent <= '0;
      reg_geom_sent <= '0;
      reg_done <= '0;
      reg_row <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_pose <= w_pose_nxt;
      reg_epoch <= w_epoch_nxt;
      reg_world <= w_world_nxt;
      reg_lane <= w_lane_nxt;
      reg_kind <= w_kind_nxt;
      reg_bridge <= w_bridge_nxt;
      reg_base <= w_base_nxt;
      reg_mask <= w_mask_nxt;
      reg_mrm_sent <= w_mrm_sent_nxt;
      reg_geom_sent <= w_geom_sent_nxt;
      reg_done <= w_done_nxt;
      reg_row <= w_row_nxt;
    end
  end
  // B3 stores up to 129 endpoints while consuming cells, exceeding the 35-slot bound.
  for(genvar gen_idx=0;gen_idx<PARA_G;gen_idx++) begin : gen_mrm
  m_tsmx_mrmgen u_tsmx_mrmgen (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_mrm_req_valid[gen_idx]),
    .i_req_data(w_mrm_req_data[176*gen_idx +:176]),
    .o_req_ready(w_mrm_req_ready[gen_idx]),
    .i_row_ready(w_mrm_row_ready[gen_idx]),
    .o_row_valid(w_mrm_row_valid[gen_idx]),
    .o_row_data(w_mrm_row_data[401*gen_idx +:401]),
    .i_rsp_ready(w_mrm_resp_ready[gen_idx]),
    .o_rsp_valid(w_mrm_resp_valid[gen_idx]),
    .o_rsp_data(w_mrm_resp_data[50*gen_idx +:50])
  );
  end
  for(genvar gen_idx=0;gen_idx<PARA_P;gen_idx++) begin : gen_geom
  m_tsmx_geom u_tsmx_geom (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_geom_req_valid[gen_idx]),
    .i_req_data(w_geom_req_data[8624*gen_idx +:8624]),
    .o_req_ready(w_geom_req_ready[gen_idx]),
    .i_row_valid(w_geom_row_valid[gen_idx]),
    .i_row_data(w_geom_row_data[401*gen_idx +:401]),
    .o_row_ready(w_geom_row_ready[gen_idx]),
    .i_terminal_valid(w_geom_terminal_valid[gen_idx]),
    .i_terminal_data(w_geom_terminal_data[50*gen_idx +:50]),
    .o_terminal_ready(w_geom_terminal_ready[gen_idx]),
    .i_rsp_ready(1'b1),
    .o_rsp_valid(w_geom_resp_valid[gen_idx]),
    .o_rsp_data(w_geom_resp_data[81*gen_idx +:81])
  );
  end

endmodule
`default_nettype wire
