/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.2
 * Description  : Two-slot custom frame transport; immutable commands survive brake override.
 *                v0.2 stores the rx frame as per-word registers (v0.1 bit scatter broke synthesis).
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_io #(
  // Parameter Description: direct semantic port selection.
  // Parameter values: 0,1; default 0.
  // Parameter unit: count
  parameter logic [31:0] PARA_DIRECT = 32'd0
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [44672:0] i_req_data,
  output logic o_req_ready,
  output logic o_core_valid,
  output logic [44672:0] o_core_data,
  output logic [7:0] o_core_reason,
  input wire i_core_ready,
  input wire [31:0] i_time_us,
  input wire i_cmd_valid,
  input wire [1896:0] i_cmd_data,
  output logic o_cmd_ready,
  input wire i_rx_valid,
  input wire [31:0] i_rx_data,
  input wire [3:0] i_rx_keep,
  input wire i_rx_last,
  output logic o_rx_ready,
  output logic o_tx_valid,
  output logic [31:0] o_tx_data,
  output logic [3:0] o_tx_keep,
  output logic o_tx_last,
  input wire i_tx_ready
);
  typedef enum logic [1:0] {
    ENUM_ST_BOOT = 2'h1,
    ENUM_ST_RUN = 2'h2
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic [31:0] reg_pw [0:1395];
  logic [31:0] reg_s0w [0:1395];
  logic [31:0] reg_s1w [0:1395];
  logic reg_pb, reg_s0b, reg_s1b;
  logic [44672:0] w_rx_data_0, w_rx_data_1;
  logic w_pw_clr, w_pw_we, w_commit_0, w_commit_1, w_tmo;
  logic [31:0] w_swap;
  logic [7:0] reg_rx_err_0, w_rx_err_0_nxt;
  logic [7:0] reg_rx_err_1, w_rx_err_1_nxt;
  logic [1:0] reg_rx_count, w_rx_count_nxt;
  logic reg_rx_head, w_rx_head_nxt;
  logic reg_rx_tail, w_rx_tail_nxt;
  logic [10:0] reg_rx_word_idx, w_rx_word_idx_nxt;
  logic reg_bad, w_bad_nxt;
  logic [14:0] reg_age, w_age_nxt;
  logic [1896:0] reg_tx_data_0, w_tx_data_0_nxt;
  logic [1896:0] reg_tx_data_1, w_tx_data_1_nxt;
  logic [1:0] reg_tx_count, w_tx_count_nxt;
  logic reg_tx_head, w_tx_head_nxt;
  logic reg_tx_tail, w_tx_tail_nxt;
  logic [6:0] reg_tx_word_idx, w_tx_word_idx_nxt;
  logic [31:0] w_rxword;
  logic [1903:0] w_txbytes;

  // The exact semantic record is outer-padded at its LSB to a whole byte.
  assign w_txbytes={(reg_tx_head ? reg_tx_data_1:reg_tx_data_0),7'd0};

  // Defaults retain state; unused FSM encodings recover through BOOT.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
    w_pw_clr = 1'b0; w_pw_we = 1'b0; w_commit_0 = 1'b0; w_commit_1 = 1'b0; w_tmo = 1'b0;
    w_rx_err_0_nxt = reg_rx_err_0;
    w_rx_err_1_nxt = reg_rx_err_1;
    w_rx_count_nxt = reg_rx_count;
    w_rx_head_nxt = reg_rx_head;
    w_rx_tail_nxt = reg_rx_tail;
    w_rx_word_idx_nxt = reg_rx_word_idx;
    w_bad_nxt = reg_bad;
    w_age_nxt = reg_age;
    w_tx_data_0_nxt = reg_tx_data_0;
    w_tx_data_1_nxt = reg_tx_data_1;
    w_tx_count_nxt = reg_tx_count;
    w_tx_head_nxt = reg_tx_head;
    w_tx_tail_nxt = reg_tx_tail;
    w_tx_word_idx_nxt = reg_tx_word_idx;
    o_req_ready=1'b0; o_core_valid=1'b0; o_core_data='0; o_core_reason='0;
    o_rx_ready=i_rst_n_core && reg_rx_count<2'd2 && PARA_DIRECT==32'd0;
    if(PARA_DIRECT!=32'd0) begin
      o_core_valid=i_rst_n_core && i_req_valid;
      o_core_data=o_core_valid ? i_req_data:44673'd0;
      o_req_ready=i_rst_n_core && i_core_ready;
    end else begin
      o_core_valid=i_rst_n_core && reg_rx_count!=2'd0;
      if(o_core_valid) begin
        o_core_data=reg_rx_head ? w_rx_data_1:w_rx_data_0;
        o_core_reason=reg_rx_head ? reg_rx_err_1:reg_rx_err_0;
      end
    end
    o_cmd_ready=i_rst_n_core && reg_tx_count<2'd2;
    o_tx_valid=i_rst_n_core && reg_tx_count!=2'd0;
    o_tx_data='0; o_tx_keep='0; o_tx_last=1'b0;
    w_rxword=i_rx_data;
    if(o_tx_valid) begin
      o_tx_keep=4'hf;
      case(reg_tx_word_idx)
        7'd0: o_tx_data=32'd2;
        7'd1: o_tx_data=32'd238;
        default: begin
          // Byte zero is the first canonical big-endian payload byte, in bus bits 7:0.
          for(int idx=0;idx<4;idx++) begin
            if(4*(32'(reg_tx_word_idx)-2)+idx<238)
              o_tx_data[8*idx +:8]=w_txbytes[1903-8*(4*(32'(reg_tx_word_idx)-2)+idx) -:8];
          end
          if(reg_tx_word_idx==7'd61) begin o_tx_keep=4'b0011; o_tx_last=1'b1; end
        end
      endcase
    end
    if(PARA_DIRECT==32'd0 && o_core_valid && i_core_ready) begin
      w_rx_count_nxt=2'(reg_rx_count-2'd1); w_rx_head_nxt=!reg_rx_head;
    end
    if(i_cmd_valid && o_cmd_ready) begin
      if(reg_tx_tail) w_tx_data_1_nxt=i_cmd_data; else w_tx_data_0_nxt=i_cmd_data;
      w_tx_tail_nxt=!reg_tx_tail; w_tx_count_nxt=2'(reg_tx_count+2'd1);
    end
    if(o_tx_valid && i_tx_ready) begin
      if(o_tx_last) begin
        w_tx_word_idx_nxt='0; w_tx_head_nxt=!reg_tx_head;
        w_tx_count_nxt=2'(w_tx_count_nxt-2'd1);
      end else w_tx_word_idx_nxt=7'(reg_tx_word_idx+7'd1);
    end
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state = ENUM_ST_RUN;
      end
      ENUM_ST_RUN: begin
        if(reg_rx_word_idx!=11'd0) begin
          w_age_nxt=15'(reg_age+15'd1);
          if(reg_age==15'd16383) begin
            // Timeout commits the partial frame with word 0 replaced by the current time.
            w_tmo=1'b1;
            if(reg_rx_tail) begin w_commit_1=1'b1; w_rx_err_1_nxt=8'd3; end
            else begin w_commit_0=1'b1; w_rx_err_0_nxt=8'd3; end
            w_rx_tail_nxt=!reg_rx_tail; w_rx_count_nxt=2'(w_rx_count_nxt+2'd1);
            w_rx_word_idx_nxt='0; w_pw_clr=1'b1; w_bad_nxt=1'b0; w_age_nxt='0;
          end
        end
        if(i_rx_valid && o_rx_ready && reg_age!=15'd16383) begin
          if(reg_rx_word_idx==11'd0) w_age_nxt='0;
          case(reg_rx_word_idx)
            11'd0: begin w_bad_nxt=i_rx_data!=32'd1 || i_rx_keep!=4'hf || i_rx_last;
              w_pw_clr=1'b1; w_rx_word_idx_nxt=11'd1; end
            11'd1: begin w_bad_nxt=reg_bad || i_rx_data!=32'd5585
                || i_rx_keep!=4'hf || i_rx_last; w_rx_word_idx_nxt=11'd2; end
            default: begin
              w_pw_we=1'b1;
              w_bad_nxt=reg_bad || i_rx_last!=(reg_rx_word_idx==11'd1398)
                || i_rx_keep!=(reg_rx_word_idx==11'd1398 ? 4'b0001:4'hf)
                || (reg_rx_word_idx==11'd1398 && i_rx_data[6:0]!=7'd0);
              if(i_rx_last || reg_rx_word_idx==11'd1398) begin
                // Parser provenance is carried separately; no malformed value can authorize motion.
                if(reg_rx_tail) begin w_commit_1=1'b1; w_rx_err_1_nxt=w_bad_nxt ? 8'd4:8'd0; end
                else begin w_commit_0=1'b1; w_rx_err_0_nxt=w_bad_nxt ? 8'd4:8'd0; end
                w_rx_tail_nxt=!reg_rx_tail; w_rx_count_nxt=2'(w_rx_count_nxt+2'd1);
                w_rx_word_idx_nxt='0; w_pw_clr=1'b1; w_bad_nxt=1'b0; w_age_nxt='0;
              end else w_rx_word_idx_nxt=11'(reg_rx_word_idx+11'd1);
            end
          endcase
        end
      end
      default: w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;
    endcase

  end
  // Asynchronous assertion; the enclosing reset synchronizer releases this domain.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;
      reg_rx_err_0 <= '0;
      reg_rx_err_1 <= '0;
      reg_rx_count <= '0;
      reg_rx_head <= '0;
      reg_rx_tail <= '0;
      reg_rx_word_idx <= '0;
      reg_bad <= '0;
      reg_age <= '0;
      reg_tx_data_0 <= '0;
      reg_tx_data_1 <= '0;
      reg_tx_count <= '0;
      reg_tx_head <= '0;
      reg_tx_tail <= '0;
      reg_tx_word_idx <= '0;
    end else begin
      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;
      reg_rx_err_0 <= w_rx_err_0_nxt;
      reg_rx_err_1 <= w_rx_err_1_nxt;
      reg_rx_count <= w_rx_count_nxt;
      reg_rx_head <= w_rx_head_nxt;
      reg_rx_tail <= w_rx_tail_nxt;
      reg_rx_word_idx <= w_rx_word_idx_nxt;
      reg_bad <= w_bad_nxt;
      reg_age <= w_age_nxt;
      reg_tx_data_0 <= w_tx_data_0_nxt;
      reg_tx_data_1 <= w_tx_data_1_nxt;
      reg_tx_count <= w_tx_count_nxt;
      reg_tx_head <= w_tx_head_nxt;
      reg_tx_tail <= w_tx_tail_nxt;
      reg_tx_word_idx <= w_tx_word_idx_nxt;
    end
  end

  // Bus byte 7:0 is the first canonical payload byte of each 32-bit word.
  assign w_swap={i_rx_data[7:0],i_rx_data[15:8],i_rx_data[23:16],i_rx_data[31:24]};

  // Payload word k (rx word index k+2) occupies frame bits 44672-32k down to 44641-32k.
  for(genvar gidx=0;gidx<1396;gidx++) begin : gen_rx_word
    logic w_hit;
    logic [31:0] w_merged;
    assign w_hit=w_pw_we && reg_rx_word_idx==11'(gidx+2);
    assign w_merged=w_hit ? w_swap:((w_tmo && gidx==0) ? i_time_us:reg_pw[gidx]);
    assign w_rx_data_0[44672-32*gidx -:32]=reg_s0w[gidx];
    assign w_rx_data_1[44672-32*gidx -:32]=reg_s1w[gidx];
    always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_word
      if (!i_rst_n_core) begin
        reg_pw[gidx] <= '0; reg_s0w[gidx] <= '0; reg_s1w[gidx] <= '0;
      end else begin
        if(w_pw_clr) reg_pw[gidx] <= '0;
        else if(w_hit) reg_pw[gidx] <= w_swap;
        if(w_commit_0) reg_s0w[gidx] <= w_merged;
        if(w_commit_1) reg_s1w[gidx] <= w_merged;
      end
    end
  end

  // The final rx word carries only frame bit 0, in bus bit 7.
  logic w_hitb, w_mergedb;
  assign w_hitb=w_pw_we && reg_rx_word_idx==11'd1398;
  assign w_mergedb=w_hitb ? i_rx_data[7]:reg_pb;
  assign w_rx_data_0[0]=reg_s0b;
  assign w_rx_data_1[0]=reg_s1b;
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_bit0
    if (!i_rst_n_core) begin
      reg_pb <= 1'b0; reg_s0b <= 1'b0; reg_s1b <= 1'b0;
    end else begin
      if(w_pw_clr) reg_pb <= 1'b0;
      else if(w_hitb) reg_pb <= i_rx_data[7];
      if(w_commit_0) reg_s0b <= w_mergedb;
      if(w_commit_1) reg_s1b <= w_mergedb;
    end
  end

endmodule
`default_nettype wire
