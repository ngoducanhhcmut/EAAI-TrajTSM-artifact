/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Streaming packed-byte CRC32 and iterative SHA-256.
 * Assumptions  : Reset release is synchronized by the wrapper. See R3_DECISIONS.md.
 */
`timescale 1ns/1ps
`default_nettype none

module m_tsmx_codec_core #(
  // Parameter Description: maximum accepted bytes in one binding job, Config1 locked.
  // Parameter values: 32768 only; default is 32768.
  // Parameter unit: byte
  parameter logic [31:0] PARA_HASH_BYTES = 32'd32768
,
  localparam logic [31:0] LPARA_IV_0 = 32'h6a09e667,
  localparam logic [31:0] LPARA_IV_1 = 32'hbb67ae85,
  localparam logic [31:0] LPARA_IV_2 = 32'h3c6ef372,
  localparam logic [31:0] LPARA_IV_3 = 32'ha54ff53a,
  localparam logic [31:0] LPARA_IV_4 = 32'h510e527f,
  localparam logic [31:0] LPARA_IV_5 = 32'h9b05688c,
  localparam logic [31:0] LPARA_IV_6 = 32'h1f83d9ab,
  localparam logic [31:0] LPARA_IV_7 = 32'h5be0cd19,
  localparam logic [31:0] LPARA_K_0 = 32'h428a2f98,
  localparam logic [31:0] LPARA_K_1 = 32'h71374491,
  localparam logic [31:0] LPARA_K_2 = 32'hb5c0fbcf,
  localparam logic [31:0] LPARA_K_3 = 32'he9b5dba5,
  localparam logic [31:0] LPARA_K_4 = 32'h3956c25b,
  localparam logic [31:0] LPARA_K_5 = 32'h59f111f1,
  localparam logic [31:0] LPARA_K_6 = 32'h923f82a4,
  localparam logic [31:0] LPARA_K_7 = 32'hab1c5ed5,
  localparam logic [31:0] LPARA_K_8 = 32'hd807aa98,
  localparam logic [31:0] LPARA_K_9 = 32'h12835b01,
  localparam logic [31:0] LPARA_K_10 = 32'h243185be,
  localparam logic [31:0] LPARA_K_11 = 32'h550c7dc3,
  localparam logic [31:0] LPARA_K_12 = 32'h72be5d74,
  localparam logic [31:0] LPARA_K_13 = 32'h80deb1fe,
  localparam logic [31:0] LPARA_K_14 = 32'h9bdc06a7,
  localparam logic [31:0] LPARA_K_15 = 32'hc19bf174,
  localparam logic [31:0] LPARA_K_16 = 32'he49b69c1,
  localparam logic [31:0] LPARA_K_17 = 32'hefbe4786,
  localparam logic [31:0] LPARA_K_18 = 32'h0fc19dc6,
  localparam logic [31:0] LPARA_K_19 = 32'h240ca1cc,
  localparam logic [31:0] LPARA_K_20 = 32'h2de92c6f,
  localparam logic [31:0] LPARA_K_21 = 32'h4a7484aa,
  localparam logic [31:0] LPARA_K_22 = 32'h5cb0a9dc,
  localparam logic [31:0] LPARA_K_23 = 32'h76f988da,
  localparam logic [31:0] LPARA_K_24 = 32'h983e5152,
  localparam logic [31:0] LPARA_K_25 = 32'ha831c66d,
  localparam logic [31:0] LPARA_K_26 = 32'hb00327c8,
  localparam logic [31:0] LPARA_K_27 = 32'hbf597fc7,
  localparam logic [31:0] LPARA_K_28 = 32'hc6e00bf3,
  localparam logic [31:0] LPARA_K_29 = 32'hd5a79147,
  localparam logic [31:0] LPARA_K_30 = 32'h06ca6351,
  localparam logic [31:0] LPARA_K_31 = 32'h14292967,
  localparam logic [31:0] LPARA_K_32 = 32'h27b70a85,
  localparam logic [31:0] LPARA_K_33 = 32'h2e1b2138,
  localparam logic [31:0] LPARA_K_34 = 32'h4d2c6dfc,
  localparam logic [31:0] LPARA_K_35 = 32'h53380d13,
  localparam logic [31:0] LPARA_K_36 = 32'h650a7354,
  localparam logic [31:0] LPARA_K_37 = 32'h766a0abb,
  localparam logic [31:0] LPARA_K_38 = 32'h81c2c92e,
  localparam logic [31:0] LPARA_K_39 = 32'h92722c85,
  localparam logic [31:0] LPARA_K_40 = 32'ha2bfe8a1,
  localparam logic [31:0] LPARA_K_41 = 32'ha81a664b,
  localparam logic [31:0] LPARA_K_42 = 32'hc24b8b70,
  localparam logic [31:0] LPARA_K_43 = 32'hc76c51a3,
  localparam logic [31:0] LPARA_K_44 = 32'hd192e819,
  localparam logic [31:0] LPARA_K_45 = 32'hd6990624,
  localparam logic [31:0] LPARA_K_46 = 32'hf40e3585,
  localparam logic [31:0] LPARA_K_47 = 32'h106aa070,
  localparam logic [31:0] LPARA_K_48 = 32'h19a4c116,
  localparam logic [31:0] LPARA_K_49 = 32'h1e376c08,
  localparam logic [31:0] LPARA_K_50 = 32'h2748774c,
  localparam logic [31:0] LPARA_K_51 = 32'h34b0bcb5,
  localparam logic [31:0] LPARA_K_52 = 32'h391c0cb3,
  localparam logic [31:0] LPARA_K_53 = 32'h4ed8aa4a,
  localparam logic [31:0] LPARA_K_54 = 32'h5b9cca4f,
  localparam logic [31:0] LPARA_K_55 = 32'h682e6ff3,
  localparam logic [31:0] LPARA_K_56 = 32'h748f82ee,
  localparam logic [31:0] LPARA_K_57 = 32'h78a5636f,
  localparam logic [31:0] LPARA_K_58 = 32'h84c87814,
  localparam logic [31:0] LPARA_K_59 = 32'h8cc70208,
  localparam logic [31:0] LPARA_K_60 = 32'h90befffa,
  localparam logic [31:0] LPARA_K_61 = 32'ha4506ceb,
  localparam logic [31:0] LPARA_K_62 = 32'hbef9a3f7,
  localparam logic [31:0] LPARA_K_63 = 32'hc67178f2
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [44:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [288:0] o_rsp_data
);
  // BOOT suppresses ready during reset. Invalid encodings recover through BOOT.
  typedef enum logic [2:0] {
    ENUM_ST_BOOT=3'd0, ENUM_ST_IDLE=3'd1, ENUM_ST_FEED=3'd2,
    ENUM_ST_PAD=3'd3, ENUM_ST_WAIT=3'd4, ENUM_ST_RESP=3'd5
  } ctrl_type_def;
  typedef enum logic [1:0] {
    ENUM_ST_EMPTY=2'd0, ENUM_ST_RUN=2'd1, ENUM_ST_ADD=2'd2
  } sha_type_def;
  ctrl_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  sha_type_def reg_fsm_sha_current_state, w_fsm_sha_nxt_state;
  logic [7:0] reg_op, w_op_nxt;
  logic [31:0] reg_len, w_len_nxt;
  logic [31:0] reg_crc, w_crc_nxt;
  logic [288:0] reg_resp, w_resp_nxt;
  logic [1023:0] reg_buf, w_buf_nxt;
  logic [1:0] reg_full, w_full_nxt;
  logic [1:0] reg_final, w_final_nxt;
  logic [0:0] reg_bank, w_bank_nxt;
  logic [0:0] reg_rd_bank, w_rd_bank_nxt;
  logic [3:0] reg_idx, w_idx_nxt;
  logic [0:0] reg_mark, w_mark_nxt;
  logic [0:0] reg_room, w_room_nxt;
  logic [255:0] reg_hash, w_hash_nxt;
  logic [255:0] reg_work, w_work_nxt;
  logic [511:0] reg_sched, w_sched_nxt;
  logic [5:0] reg_round, w_round_nxt;
  logic [0:0] reg_last, w_last_nxt;
  logic [7:0] reg_objects, w_objects_nxt;
  logic [7:0] w_op, w_byte, w_objects;
  logic [2:0] w_count;
  logic [31:0] w_len, w_limit, w_crc, w_word, w_pos;
  logic w_start, w_end, w_take, w_bad, w_push, w_finish, w_raw;
  logic [31:0] w_a, w_b, w_c, w_d, w_e, w_f, w_g, w_h;
  logic [31:0] w_t1, w_t2, w_schedule;
  logic [255:0] w_sum;

  // FIPS180-4 initialization vector and round constants, independent of payload.
  function automatic [255:0] sha_iv();
    sha_iv={LPARA_IV_0,LPARA_IV_1,LPARA_IV_2,LPARA_IV_3,LPARA_IV_4,LPARA_IV_5,LPARA_IV_6,LPARA_IV_7};
  endfunction
  function automatic [31:0] sha_k(input logic [5:0] w_idx);
    case (w_idx)
      6'd0: sha_k=LPARA_K_0;
      6'd1: sha_k=LPARA_K_1;
      6'd2: sha_k=LPARA_K_2;
      6'd3: sha_k=LPARA_K_3;
      6'd4: sha_k=LPARA_K_4;
      6'd5: sha_k=LPARA_K_5;
      6'd6: sha_k=LPARA_K_6;
      6'd7: sha_k=LPARA_K_7;
      6'd8: sha_k=LPARA_K_8;
      6'd9: sha_k=LPARA_K_9;
      6'd10: sha_k=LPARA_K_10;
      6'd11: sha_k=LPARA_K_11;
      6'd12: sha_k=LPARA_K_12;
      6'd13: sha_k=LPARA_K_13;
      6'd14: sha_k=LPARA_K_14;
      6'd15: sha_k=LPARA_K_15;
      6'd16: sha_k=LPARA_K_16;
      6'd17: sha_k=LPARA_K_17;
      6'd18: sha_k=LPARA_K_18;
      6'd19: sha_k=LPARA_K_19;
      6'd20: sha_k=LPARA_K_20;
      6'd21: sha_k=LPARA_K_21;
      6'd22: sha_k=LPARA_K_22;
      6'd23: sha_k=LPARA_K_23;
      6'd24: sha_k=LPARA_K_24;
      6'd25: sha_k=LPARA_K_25;
      6'd26: sha_k=LPARA_K_26;
      6'd27: sha_k=LPARA_K_27;
      6'd28: sha_k=LPARA_K_28;
      6'd29: sha_k=LPARA_K_29;
      6'd30: sha_k=LPARA_K_30;
      6'd31: sha_k=LPARA_K_31;
      6'd32: sha_k=LPARA_K_32;
      6'd33: sha_k=LPARA_K_33;
      6'd34: sha_k=LPARA_K_34;
      6'd35: sha_k=LPARA_K_35;
      6'd36: sha_k=LPARA_K_36;
      6'd37: sha_k=LPARA_K_37;
      6'd38: sha_k=LPARA_K_38;
      6'd39: sha_k=LPARA_K_39;
      6'd40: sha_k=LPARA_K_40;
      6'd41: sha_k=LPARA_K_41;
      6'd42: sha_k=LPARA_K_42;
      6'd43: sha_k=LPARA_K_43;
      6'd44: sha_k=LPARA_K_44;
      6'd45: sha_k=LPARA_K_45;
      6'd46: sha_k=LPARA_K_46;
      6'd47: sha_k=LPARA_K_47;
      6'd48: sha_k=LPARA_K_48;
      6'd49: sha_k=LPARA_K_49;
      6'd50: sha_k=LPARA_K_50;
      6'd51: sha_k=LPARA_K_51;
      6'd52: sha_k=LPARA_K_52;
      6'd53: sha_k=LPARA_K_53;
      6'd54: sha_k=LPARA_K_54;
      6'd55: sha_k=LPARA_K_55;
      6'd56: sha_k=LPARA_K_56;
      6'd57: sha_k=LPARA_K_57;
      6'd58: sha_k=LPARA_K_58;
      6'd59: sha_k=LPARA_K_59;
      6'd60: sha_k=LPARA_K_60;
      6'd61: sha_k=LPARA_K_61;
      6'd62: sha_k=LPARA_K_62;
      6'd63: sha_k=LPARA_K_63;
      default: sha_k=32'd0;
    endcase
  endfunction

  // SHA-256 fixed rotations; arguments and return values are unsigned protocol words.
  function automatic [31:0] rotr(input logic [31:0] w_x, input logic [4:0] w_n);
    rotr = (w_x >> w_n) | (w_x << (6'd32-{1'b0,w_n}));
  endfunction
  function automatic [31:0] crc_byte(input logic [31:0] w_x, input logic [7:0] w_y);
    logic [31:0] w_v;
    begin
      w_v=w_x^{24'd0,w_y};
      for (int idx=0; idx<8; idx++) begin
        if (w_v[0]) w_v=(w_v>>1)^32'hedb88321;
        else w_v=w_v>>1;
      end
      crc_byte=w_v;
    end
  endfunction

  // No combinational ready feedback: bank occupancy and registered job state gate input.
  always_comb begin : p_com_ports
    o_req_ready=1'b0;
    o_rsp_valid=1'b0;
    o_rsp_data='0;
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: o_req_ready=i_rst_n_core;
      ENUM_ST_FEED: o_req_ready=i_rst_n_core & ~reg_full[reg_bank];
      ENUM_ST_RESP: begin
        o_rsp_valid=i_rst_n_core;
        if (i_rst_n_core) o_rsp_data=reg_resp;
      end
      default: o_req_ready=1'b0;
    endcase
  end

  // Validate transport, operation length and observable packed schema bytes (spec 9.2).
  always_comb begin : p_com_check
    w_start=i_req_data[36];
    w_end=i_req_data[35];
    w_count=i_req_data[34:32];
    w_op=reg_op;
    if (reg_fsm_ctrl_current_state==ENUM_ST_IDLE) w_op=i_req_data[44:37];
    w_len=32'(reg_len+{29'd0,w_count});
    w_limit=PARA_HASH_BYTES;
    w_raw=1'b0;
    case (w_op)
      8'd0: w_limit=32'd86;
      8'd1: w_limit=32'd32;
      8'd2: w_limit=32'd70;
      8'd3: w_limit=32'd1049;
      8'd4: w_limit=32'd120;
      8'd5,8'd6: w_raw=1'b1;
      default: w_limit=32'd0;
    endcase
    w_take=i_req_valid & o_req_ready;
    w_bad=(w_op>8'd6) | (w_count>3'd4) | (w_len>w_limit);
    w_bad=w_bad | (w_start!=(reg_fsm_ctrl_current_state==ENUM_ST_IDLE));
    w_bad=w_bad | (i_req_data[44:37]!=w_op);
    if (!w_end) w_bad=w_bad | (w_count!=3'd4);
    if (w_end && !w_raw) w_bad=w_bad | (w_len!=w_limit);
    if (w_count==3'd0) w_bad=w_bad | !(w_start && w_end && w_raw);
    w_crc=reg_crc;
    w_byte='0;
    w_pos='0;
    w_objects=reg_objects;
    if (reg_len==32'd0) w_objects=i_req_data[31:24];
    for (int idx=0; idx<4; idx++) begin
      w_byte=i_req_data[31-idx*8 -: 8];
      w_pos=32'(reg_len+32'(idx));
      if (32'(idx)<{29'd0,w_count}) begin
        w_crc=crc_byte(w_crc,w_byte);
        // Plan schema bytes66..69; packet schema82..85. Schema is u32=1.
        if (((w_op==8'd0 || w_op==8'd2) && w_pos>=32'd66 && w_pos<=32'd69)
          || (w_op==8'd0 && w_pos>=32'd82)) begin
          if (w_pos==32'd69 || w_pos==32'd85) w_bad=w_bad | (w_byte!=8'd1);
          else w_bad=w_bad | (w_byte!=8'd0);
        end
        if (w_op==8'd3) begin
          if (w_pos==32'd0) w_bad=w_bad | (w_byte>8'd32);
          if (w_pos>32'd0 && w_pos<32'd1025
            && w_pos>=(32'd1+({24'd0,w_objects}<<5))) w_bad=w_bad | (w_byte!=8'd0);
          if (w_pos>=32'd1041) begin
            if (w_pos==32'd1044 || w_pos==32'd1048) w_bad=w_bad | (w_byte!=8'd1);
            else w_bad=w_bad | (w_byte!=8'd0);
          end
        end
      end else w_bad=w_bad | (w_byte!=8'd0);
    end
  end

  // SHA round datapath: sixteen-word shift schedule and eight working words, modulo2^32.
  always_comb begin : p_com_sha
    {w_a,w_b,w_c,w_d,w_e,w_f,w_g,w_h}=reg_work;
    w_t1=32'(w_h+(rotr(w_e,5'd6)^rotr(w_e,5'd11)^rotr(w_e,5'd25))
      +((w_e&w_f)^(~w_e&w_g))+sha_k(reg_round)
      +reg_sched[511:480]);
    w_t2=32'((rotr(w_a,5'd2)^rotr(w_a,5'd13)^rotr(w_a,5'd22))
      +((w_a&w_b)^(w_a&w_c)^(w_b&w_c)));
    w_schedule=32'(reg_sched[511:480]
      +(rotr(reg_sched[479:448],5'd7)^rotr(reg_sched[479:448],5'd18)
        ^(reg_sched[479:448]>>3)) +reg_sched[223:192]
      +(rotr(reg_sched[63:32],5'd17)^rotr(reg_sched[63:32],5'd19)
        ^(reg_sched[63:32]>>10)));
    w_sum='0;
    for (int idx=0; idx<8; idx++) begin
      w_sum[255-idx*32 -: 32]=32'(reg_hash[255-idx*32 -: 32]
        +reg_work[255-idx*32 -: 32]);
    end
  end

  // Double-buffer producer and compression consumer update disjoint occupied/free banks.
  // Padding is generated locally at one word/cycle; input last is never hashed as text.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state=reg_fsm_ctrl_current_state;
    w_fsm_sha_nxt_state=reg_fsm_sha_current_state;
    w_op_nxt=reg_op;
    w_len_nxt=reg_len;
    w_crc_nxt=reg_crc;
    w_resp_nxt=reg_resp;
    w_buf_nxt=reg_buf;
    w_full_nxt=reg_full;
    w_final_nxt=reg_final;
    w_bank_nxt=reg_bank;
    w_rd_bank_nxt=reg_rd_bank;
    w_idx_nxt=reg_idx;
    w_mark_nxt=reg_mark;
    w_room_nxt=reg_room;
    w_hash_nxt=reg_hash;
    w_work_nxt=reg_work;
    w_sched_nxt=reg_sched;
    w_round_nxt=reg_round;
    w_last_nxt=reg_last;
    w_objects_nxt=reg_objects;
    w_word='0;
    w_push=1'b0;
    w_finish=1'b0;
    case (reg_fsm_sha_current_state)
      ENUM_ST_EMPTY: begin
        if (reg_full[reg_rd_bank]) begin
          w_sched_nxt=reg_buf[1023-32'(reg_rd_bank)*512 -: 512];
          w_work_nxt=reg_hash;
          w_round_nxt='0;
          w_last_nxt=reg_final[reg_rd_bank];
          w_full_nxt[reg_rd_bank]=1'b0;
          w_rd_bank_nxt=~reg_rd_bank;
          w_fsm_sha_nxt_state=ENUM_ST_RUN;
        end
      end
      ENUM_ST_RUN: begin
        w_work_nxt={32'(w_t1+w_t2),w_a,w_b,w_c,32'(w_d+w_t1),w_e,w_f,w_g};
        w_sched_nxt={reg_sched[479:0],w_schedule};
        w_round_nxt=6'(reg_round+6'd1);
        if (reg_round==6'd63) w_fsm_sha_nxt_state=ENUM_ST_ADD;
      end
      ENUM_ST_ADD: begin
        w_hash_nxt=w_sum;
        w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
        if (reg_last) begin
          w_resp_nxt={1'b0,32'd0,w_sum};
          w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end
      end
      default: w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
    endcase
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: begin
        w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
        w_op_nxt='0;
        w_len_nxt='0;
        w_crc_nxt=32'hffffffff;
        w_resp_nxt='0;
        w_buf_nxt='0;
        w_full_nxt='0;
        w_final_nxt='0;
        w_bank_nxt='0;
        w_rd_bank_nxt='0;
        w_idx_nxt='0;
        w_mark_nxt='0;
        w_room_nxt='0;
        w_hash_nxt=sha_iv();
        w_work_nxt=sha_iv();
        w_sched_nxt='0;
        w_round_nxt='0;
        w_last_nxt='0;
        w_objects_nxt='0;
      end
      ENUM_ST_IDLE,ENUM_ST_FEED: begin
        if (w_take) begin
          w_op_nxt=w_op;
          w_len_nxt=w_len;
          if (reg_len==32'd0) w_objects_nxt=i_req_data[31:24];
          if (w_op==8'd0 || w_op==8'd5) begin
            w_crc_nxt=w_crc;
            w_fsm_ctrl_nxt_state=ENUM_ST_FEED;
            if (w_end) begin
              w_resp_nxt={1'b0,~w_crc,256'd0};
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
            end
          end else begin
            w_push=1'b1;
            w_word=i_req_data[31:0];
            w_fsm_ctrl_nxt_state=ENUM_ST_FEED;
            if (w_end) begin
              w_mark_nxt=(w_count<3'd4);
              w_room_nxt=(reg_idx<4'd14);
              if (w_count<3'd4) w_word=w_word | (32'h80000000 >> ({29'd0,w_count}<<3));
              w_fsm_ctrl_nxt_state=ENUM_ST_PAD;
            end
          end
          if (w_bad) begin
            w_push=1'b0;
            w_resp_nxt={1'b1,288'd0};
            w_full_nxt='0;
            w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
            w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
          end
        end
      end
      ENUM_ST_PAD: begin
        if (!reg_full[reg_bank]) begin
          w_push=1'b1;
          casez ({reg_mark,reg_room,reg_idx})
            6'b0?????: begin
              w_word=32'h80000000;
              w_mark_nxt=1'b1;
              w_room_nxt=(reg_idx<4'd14);
            end
            6'b111111: begin
              w_word=32'(reg_len<<3);
              w_finish=1'b1;
              w_fsm_ctrl_nxt_state=ENUM_ST_WAIT;
            end
            default: w_word='0;
          endcase
        end
      end
      ENUM_ST_WAIT: begin end
      ENUM_ST_RESP: begin
        if (i_rsp_ready) begin
          w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
          w_op_nxt='0;
          w_len_nxt='0;
          w_crc_nxt=32'hffffffff;
          w_resp_nxt='0;
          w_buf_nxt='0;
          w_full_nxt='0;
          w_final_nxt='0;
          w_bank_nxt='0;
          w_rd_bank_nxt='0;
          w_idx_nxt='0;
          w_mark_nxt='0;
          w_room_nxt='0;
          w_hash_nxt=sha_iv();
          w_work_nxt=sha_iv();
          w_sched_nxt='0;
          w_round_nxt='0;
          w_last_nxt='0;
          w_objects_nxt='0;
          w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
        end
      end
      default: begin
        w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
        w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
        w_full_nxt='0;
      end
    endcase
    if (reg_fsm_sha_current_state==2'd3) begin
      w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
      w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
      w_full_nxt='0;
      w_push=1'b0;
    end
    if (w_push) begin
      w_buf_nxt[1023-32'(reg_bank)*512-32'(reg_idx)*32 -: 32]=w_word;
      w_idx_nxt=4'(reg_idx+4'd1);
      if (reg_idx==4'd15) begin
        w_full_nxt[reg_bank]=1'b1;
        w_final_nxt[reg_bank]=w_finish;
        w_bank_nxt=~reg_bank;
        w_room_nxt=1'b1;
      end
    end
  end

  // Asynchronous reset clears partial jobs; wrapper synchronizes release (spec 7).
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_state
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT;
      reg_fsm_sha_current_state<=ENUM_ST_EMPTY;
      reg_op<='0;
      reg_len<='0;
      reg_crc<=32'hffffffff;
      reg_resp<='0;
      reg_buf<='0;
      reg_full<='0;
      reg_final<='0;
      reg_bank<='0;
      reg_rd_bank<='0;
      reg_idx<='0;
      reg_mark<='0;
      reg_room<='0;
      reg_hash<=sha_iv();
      reg_work<=sha_iv();
      reg_sched<='0;
      reg_round<='0;
      reg_last<='0;
      reg_objects<='0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_fsm_sha_current_state<=w_fsm_sha_nxt_state;
      reg_op<=w_op_nxt;
      reg_len<=w_len_nxt;
      reg_crc<=w_crc_nxt;
      reg_resp<=w_resp_nxt;
      reg_buf<=w_buf_nxt;
      reg_full<=w_full_nxt;
      reg_final<=w_final_nxt;
      reg_bank<=w_bank_nxt;
      reg_rd_bank<=w_rd_bank_nxt;
      reg_idx<=w_idx_nxt;
      reg_mark<=w_mark_nxt;
      reg_room<=w_room_nxt;
      reg_hash<=w_hash_nxt;
      reg_work<=w_work_nxt;
      reg_sched<=w_sched_nxt;
      reg_round<=w_round_nxt;
      reg_last<=w_last_nxt;
      reg_objects<=w_objects_nxt;
    end
  end
endmodule
`default_nettype wire
