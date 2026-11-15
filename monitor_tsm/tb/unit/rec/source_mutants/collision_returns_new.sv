/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : B10 bounded chronological event recorder.
 * Assumptions  : See R1_DECISIONS.md; reset release is synchronized by the wrapper.
 */
`timescale 1ns/1ps
`default_nettype none

module m_tsmx_rec #(
  // Parameter Description: ring capacity fixed at elaboration; index port remains 10 bits.
  // Parameter values: 1 through 1024; default is 64.
  // Parameter unit: count
  parameter logic [31:0] PARA_LOG_DEPTH = 32'd64,
  localparam logic [31:0] LPARA_FIELD_W = 32'd263,
  localparam logic [31:0] LPARA_FIELDS = 32'd4,
  localparam logic [31:0] LPARA_LEN_W = 32'd6,
  localparam logic [31:0] LPARA_BYTE_W = 32'd8,
  localparam logic [31:0] LPARA_INT_PAD_W = 32'd192,
  localparam logic [31:0] LPARA_INT_W = 32'd64,
  localparam logic [31:0] LPARA_STRING_MAX = 32'd32,
  localparam logic [31:0] LPARA_LOST_MAX = 32'hffffffff
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1055:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [31:0] o_rsp_data,
  input wire [9:0] i_log_idx,
  input wire i_log_valid,
  input wire i_log_ready,
  output logic o_log_ready,
  output logic [1055:0] o_log_data,
  output logic o_log_valid
);
  // BOOT inhibits ready during reset; IDLE accepts once; RESP holds until consumed.
  typedef enum logic [1:0] {
    ENUM_ST_BOOT = 2'b00,
    ENUM_ST_IDLE = 2'b01,
    ENUM_ST_RESP = 2'b10
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state;
  ctrl_state_type_def w_fsm_ctrl_nxt_state;
  logic [31:0] reg_resp;
  logic [31:0] w_result;
  logic [31:0] w_resp_nxt;
  logic [1055:0] reg_events [0:PARA_LOG_DEPTH-1];
  logic [10:0] reg_count;
  logic [9:0] reg_head;
  logic [31:0] reg_lost;
  logic [10:0] w_count_nxt;
  logic [9:0] w_head_nxt;
  logic [31:0] w_lost_nxt;
  logic [10:0] w_wr_sum;
  logic [9:0] w_wr_addr;
  logic [10:0] w_rd_sum;
  logic [9:0] w_rd_addr;
  logic w_event_ok;
  logic w_wr_en;
  logic reg_log_valid;
  logic reg_log_armed;
  logic [1055:0] reg_log_data;
  logic w_log_valid_nxt;
  logic [1055:0] w_log_data_nxt;

  // State-only outputs avoid a request/response ready combinational loop.
  always_comb begin : p_com_outputs
    o_req_ready = 1'b0;
    o_rsp_valid = 1'b0;
    o_rsp_data = '0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready = i_rst_n_core;
      ENUM_ST_RESP: begin
        o_rsp_valid = i_rst_n_core;
        if (i_rst_n_core) o_rsp_data = reg_resp;
      end
      default: begin
        o_req_ready = 1'b0;
      end
    endcase
  end

  // Acceptance captures the proposal; consumption clears validity and payload.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_resp_nxt = reg_resp;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
        w_resp_nxt = '0;
      end
      ENUM_ST_IDLE: begin
        if (i_req_valid) begin
          w_fsm_ctrl_nxt_state = ENUM_ST_RESP;
          w_resp_nxt = w_result;
        end
      end
      ENUM_ST_RESP: begin
        if (i_rsp_ready) begin
          w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;
          w_resp_nxt = '0;
        end
      end
      default: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
        w_resp_nxt = '0;
      end
    endcase
  end

  // Canonical Event ABI validation (spec 9.2); unused fields and padding must be zero.
  // Integers preserve golden's strict lower bound: -2^63 itself is invalid.
  always_comb begin : p_com_schema
    w_event_ok = i_req_data[1055] & (i_req_data[1054:1052] <= 3'(LPARA_FIELDS));
    for (int idx = 0; idx < LPARA_FIELDS; idx++) begin
      if (32'(idx) < {29'd0, i_req_data[1054:1052]}) begin
        if (i_req_data[1051-idx*LPARA_FIELD_W]) begin
          if (i_req_data[1050-idx*LPARA_FIELD_W -: LPARA_LEN_W] > 6'(LPARA_STRING_MAX)) w_event_ok = 1'b0;
          for (int pos = 0; pos < 32; pos++) begin
            if ((32'(pos) >= {26'd0, i_req_data[1050-idx*LPARA_FIELD_W -: LPARA_LEN_W]}) &
                (i_req_data[1044-idx*LPARA_FIELD_W-pos*LPARA_BYTE_W -: LPARA_BYTE_W] != 8'd0)) w_event_ok = 1'b0;
          end
        end else begin
          if ((i_req_data[1050-idx*LPARA_FIELD_W -: LPARA_LEN_W] != 6'd0) |
              (i_req_data[1044-idx*LPARA_FIELD_W -: LPARA_INT_PAD_W] != 192'd0) |
              (i_req_data[852-idx*LPARA_FIELD_W -: LPARA_INT_W] == 64'h8000000000000000))
            w_event_ok = 1'b0;
        end
      end else begin
        if (i_req_data[1051-idx*LPARA_FIELD_W -: LPARA_FIELD_W] != {LPARA_FIELD_W{1'b0}}) w_event_ok = 1'b0;
      end
    end
  end

  // Modulo addressing supports non-power-of-two capacities; full writes replace the oldest.
  // Count/head/lost change only on request acceptance, independent of log backpressure.
  always_comb begin : p_com_ring
    w_count_nxt = reg_count;
    w_head_nxt = reg_head;
    w_lost_nxt = reg_lost;
    w_wr_sum = $bits(w_wr_sum)'({1'b0, reg_head} + reg_count);
    if ({21'd0, w_wr_sum} >= PARA_LOG_DEPTH)
      w_wr_sum = $bits(w_wr_sum)'({21'd0, w_wr_sum} - PARA_LOG_DEPTH);
    w_wr_addr = w_wr_sum[9:0];
    w_wr_en = 1'b0;
    if (i_req_valid & o_req_ready) begin
      if (!w_event_ok | ({21'd0, reg_count} == PARA_LOG_DEPTH)) begin
        if (reg_lost != LPARA_LOST_MAX) w_lost_nxt = $bits(w_lost_nxt)'(reg_lost + 32'd1);
      end
      if (w_event_ok) begin
        w_wr_en = 1'b1;
        if ({21'd0, reg_count} == PARA_LOG_DEPTH) begin
          w_head_nxt = $bits(w_head_nxt)'(reg_head + 10'd1);
          if ({22'd0, reg_head} == (PARA_LOG_DEPTH - 32'd1)) w_head_nxt = 10'd0;
        end else w_count_nxt = $bits(w_count_nxt)'(reg_count + 11'd1);
      end
    end
    w_result = w_lost_nxt;
  end


  // Indexed read is a pre-write snapshot; consumption never deletes a ring entry.
  // Out-of-range queries complete with zero. A stalled snapshot remains immutable.
  always_comb begin : p_com_log
    o_log_ready = i_rst_n_core & reg_log_armed & !reg_log_valid;
    o_log_valid = i_rst_n_core & reg_log_valid;
    o_log_data = '0;
    if (o_log_valid) o_log_data = reg_log_data;
    w_log_valid_nxt = reg_log_valid;
    w_log_data_nxt = reg_log_data;
    w_rd_sum = $bits(w_rd_sum)'({1'b0, reg_head} + {1'b0, i_log_idx});
    if ({21'd0, w_rd_sum} >= PARA_LOG_DEPTH)
      w_rd_sum = $bits(w_rd_sum)'({21'd0, w_rd_sum} - PARA_LOG_DEPTH);
    w_rd_addr = w_rd_sum[9:0];
    if (o_log_valid & i_log_ready) begin
      w_log_valid_nxt = 1'b0;
      w_log_data_nxt = '0;
    end
    if (i_log_valid & o_log_ready) begin
      w_log_valid_nxt = 1'b1;
      w_log_data_nxt = '0;
      if ({1'b0, i_log_idx} < reg_count) w_log_data_nxt = (w_wr_en && w_wr_addr == w_rd_addr) ? i_req_data : reg_events[w_rd_addr];
    end
  end

  // Control and response are invalidated asynchronously; release comes from the wrapper.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_resp <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_resp <= w_resp_nxt;
    end
  end

  // RAM payload needs no reset: count invalidates every entry until a valid append.
  // Nonblocking writes preserve the pre-write read snapshot on same-address collision.
  always_ff @(posedge i_clk_core) begin : p_ff_events
    if (w_wr_en) reg_events[w_wr_addr] <= i_req_data;
  end

  // Ring metadata and read-channel validity are reset; no data is consumed while invalid.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ring
    if (!i_rst_n_core) begin
      reg_count <= 11'd0;
      reg_head <= 10'd0;
      reg_lost <= 32'd0;
      reg_log_valid <= 1'b0;
      reg_log_armed <= 1'b0;
      reg_log_data <= '0;
    end else begin
      reg_count <= w_count_nxt;
      reg_head <= w_head_nxt;
      reg_lost <= w_lost_nxt;
      reg_log_valid <= w_log_valid_nxt;
      reg_log_armed <= 1'b1;
      reg_log_data <= w_log_data_nxt;
    end
  end

endmodule
`default_nettype wire
