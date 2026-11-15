/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-30
 * Version      : 0.2
 * Description  : Dedicated accepted B4/B3 pair; endpoints stay in a local row RAM.
 *                v0.2 returns {terminal,last row} to B13 and replays rows from the RAM
 *                (v0.1 copied the 45458-bit trajectory through three register sets).
 * Assumptions  : Wrapper synchronizes reset release and owns DFT reset override.
 *                Only m_tsmx_health issues B4 requests, so rows are stable during replay.
 * Deviations   : Functional leaves implement logic (HIE-02); enclosing lane is structural.
 *                Fixed SI constants and record widths implement spec 9.2 (PAR-03).
 *                Row RAM has no reset; per-row valid bits reproduce the v0.1 clear.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_health_bist #(
  localparam logic [31:0] LPARA_MAX_ROWS = 32'd129
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire [175:0] i_b4_data,
  input wire i_b4_valid,
  input wire i_b4_ready,
  input wire [8583:0] i_b3_data,
  input wire i_b3_valid,
  input wire i_b3_ready,
  output logic o_b4_ready,
  output logic [401:0] o_b4_data,
  output logic o_b4_valid,
  output logic o_b3_ready,
  output logic [80:0] o_b3_data,
  output logic o_b3_valid
);
  typedef enum logic [2:0] {
    ENUM_ST_BOOT=3'd0, ENUM_ST_IDLE=3'd1, ENUM_ST_ROWS=3'd2,
    ENUM_ST_TERM=3'd3, ENUM_ST_WAIT=3'd4
  } ctrl_state_type_def;
  typedef enum logic [1:0] {
    ENUM_RS_IDLE=2'd0, ENUM_RS_READ=2'd1, ENUM_RS_HOLD=2'd2
  } rsp_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  rsp_state_type_def reg_fsm_rsp_current_state, w_fsm_rsp_nxt_state;
  (* ram_style = "distributed" *) logic [351:0] reg_row_mem [0:128];
  logic [128:0] reg_row_ok;
  logic [49:0] reg_term;
  logic [351:0] reg_last;
  logic [7:0] reg_idx, w_idx_nxt;
  logic w_grow_valid, w_gvalid, w_gready;
  logic [400:0] w_grow;
  logic [49:0] w_gterm;
  logic w_row_ready, w_term_ready, w_req_ready;
  logic w_req_valid, w_row_valid, w_term_valid;
  logic [400:0] w_row;
  logic [8623:0] w_req;
  logic [7:0] w_cnt;
  logic [351:0] w_rd_last, w_rd_row;

  // B13 sees the terminal record and the endpoint it qualifies, after the rows settle.
  assign w_cnt=reg_term[7:0];
  assign o_b4_valid=reg_fsm_rsp_current_state==ENUM_RS_HOLD;
  assign o_b4_data=o_b4_valid ? {reg_term,reg_last} : 402'd0;
  assign w_gready=reg_fsm_rsp_current_state==ENUM_RS_IDLE;
  assign w_rd_last=(w_cnt>=8'd1 && w_cnt<=8'(LPARA_MAX_ROWS) && reg_row_ok[w_cnt-8'd1])
    ? reg_row_mem[w_cnt-8'd1] : 352'd0;
  assign w_req={40'd0,i_b3_data};
  assign w_req_valid=i_b3_valid && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
  assign o_b3_ready=w_req_ready && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
  // Replay qualifies each initialized endpoint and sends terminal metadata only after all rows.
  assign w_row_valid=reg_fsm_ctrl_current_state==ENUM_ST_ROWS && reg_idx<w_cnt;
  // Terminal handshake follows the final accepted endpoint.
  assign w_term_valid=reg_fsm_ctrl_current_state==ENUM_ST_TERM;
  assign w_rd_row=(reg_idx<8'(LPARA_MAX_ROWS) && reg_row_ok[reg_idx]) ? reg_row_mem[reg_idx] : 352'd0;
  assign w_row=(reg_idx<8'(LPARA_MAX_ROWS)) ? {40'd0,reg_idx,w_rd_row,reg_idx+8'd1==w_cnt} : 401'd0;

  // Response capture: terminal first, then one RAM read of the qualified endpoint.
  always_comb begin : p_com_rsp
    w_fsm_rsp_nxt_state=reg_fsm_rsp_current_state;
    case(reg_fsm_rsp_current_state)
      ENUM_RS_IDLE: if(w_gvalid) w_fsm_rsp_nxt_state=ENUM_RS_READ;
      ENUM_RS_READ: w_fsm_rsp_nxt_state=ENUM_RS_HOLD;
      ENUM_RS_HOLD: if(i_b4_ready) w_fsm_rsp_nxt_state=ENUM_RS_IDLE;
      default: w_fsm_rsp_nxt_state=ENUM_RS_IDLE;
    endcase
  end

  // Independent B4 capture and B3 replay permit dedicated resources without global contention.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state=reg_fsm_ctrl_current_state;
    w_idx_nxt=reg_idx;
    case(reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      ENUM_ST_IDLE: if(i_b3_valid && w_req_ready) begin
        w_idx_nxt='0; w_fsm_ctrl_nxt_state=ENUM_ST_ROWS;
      end
      ENUM_ST_ROWS: begin
        if(reg_idx>=w_cnt) w_fsm_ctrl_nxt_state=ENUM_ST_TERM;
        else if(w_row_ready) w_idx_nxt=8'(reg_idx+8'd1);
      end
      ENUM_ST_TERM: if(w_term_ready) w_fsm_ctrl_nxt_state=ENUM_ST_WAIT;
      ENUM_ST_WAIT: if(o_b3_valid && i_b3_ready) w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      default: w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
    endcase
  end

  // Reset invalidates buffered endpoints and aborts both accepted dependencies.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if(!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT;
      reg_fsm_rsp_current_state<=ENUM_RS_IDLE;
      reg_row_ok<='0; reg_term<='0; reg_last<='0; reg_idx<='0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_fsm_rsp_current_state<=w_fsm_rsp_nxt_state;
      reg_idx<=w_idx_nxt;
      if(i_b4_valid && o_b4_ready) reg_row_ok<='0;
      if(w_grow_valid && w_grow[360:353]<8'(LPARA_MAX_ROWS)) reg_row_ok[w_grow[360:353]]<=1'b1;
      if(reg_fsm_rsp_current_state==ENUM_RS_IDLE && w_gvalid) reg_term<=w_gterm;
      if(reg_fsm_rsp_current_state==ENUM_RS_READ) reg_last<=w_rd_last;
    end
  end

  // Endpoint storage: one write port from B4, asynchronous reads for capture and replay.
  always_ff @(posedge i_clk_core) begin : p_ff_rows
    if(w_grow_valid && w_grow[360:353]<8'(LPARA_MAX_ROWS))
      reg_row_mem[w_grow[360:353]]<=w_grow[352:1];
  end

  // Accepted dependencies own all arithmetic; each has private per-lane pipelines.
  m_tsmx_mrmgen u_tsmx_mrmgen (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(i_b4_valid), .i_req_data(i_b4_data), .o_req_ready(o_b4_ready),
    .i_row_ready(1'b1), .o_row_valid(w_grow_valid), .o_row_data(w_grow),
    .i_rsp_ready(w_gready), .o_rsp_valid(w_gvalid), .o_rsp_data(w_gterm)
  );
  m_tsmx_geom u_tsmx_geom (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(w_req_valid), .i_req_data(w_req), .o_req_ready(w_req_ready),
    .i_row_valid(w_row_valid), .i_row_data(w_row), .o_row_ready(w_row_ready),
    .i_terminal_valid(w_term_valid), .i_terminal_data(reg_term),
    .o_terminal_ready(w_term_ready), .i_rsp_ready(i_b3_ready),
    .o_rsp_valid(o_b3_valid), .o_rsp_data(o_b3_data)
  );
endmodule

`default_nettype wire
