"""R3 source recipe. Only writes the codec-owned RTL directory."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'rtl/codec'
OUT.mkdir(parents=True,exist_ok=True)
header='''/*
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
'''
params='''  // Parameter Description: maximum accepted bytes in one binding job, Config1 locked.
  // Parameter values: 32768 only; default is 32768.
  // Parameter unit: byte
  parameter logic [31:0] PARA_HASH_BYTES = 32'd32768
'''
ports='''  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [44:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [288:0] o_rsp_data
'''
(OUT/'m_tsmx_codec.sv').write_text(header+'\nmodule m_tsmx_codec #(\n'+params+') (\n'+ports+''');
  // Structural wrapper preserves the common physical packed ABI (spec 5.3, 9.2).
  m_tsmx_codec_core #(.PARA_HASH_BYTES(PARA_HASH_BYTES)) u_codec_core (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_req_valid(i_req_valid), .i_req_data(i_req_data), .i_rsp_ready(i_rsp_ready),
    .o_req_ready(o_req_ready), .o_rsp_valid(o_rsp_valid), .o_rsp_data(o_rsp_data)
  );
endmodule
`default_nettype wire
''')
regs=[('op',8,"'0"),('len',32,"'0"),('crc',32,"32'hffffffff"),('resp',289,"'0"),
      ('buf',1024,"'0"),('full',2,"'0"),('final',2,"'0"),('bank',1,"'0"),('rd_bank',1,"'0"),
      ('idx',4,"'0"),('mark',1,"'0"),('room',1,"'0"),('hash',256,"LPARA_IV"),
      ('work',256,"LPARA_IV"),('sched',512,"'0"),('round',6,"'0"),('last',1,"'0"),('objects',8,"'0")]
k='428a2f98 71374491 b5c0fbcf e9b5dba5 3956c25b 59f111f1 923f82a4 ab1c5ed5 d807aa98 12835b01 243185be 550c7dc3 72be5d74 80deb1fe 9bdc06a7 c19bf174 e49b69c1 efbe4786 0fc19dc6 240ca1cc 2de92c6f 4a7484aa 5cb0a9dc 76f988da 983e5152 a831c66d b00327c8 bf597fc7 c6e00bf3 d5a79147 06ca6351 14292967 27b70a85 2e1b2138 4d2c6dfc 53380d13 650a7354 766a0abb 81c2c92e 92722c85 a2bfe8a1 a81a664b c24b8b70 c76c51a3 d192e819 d6990624 f40e3585 106aa070 19a4c116 1e376c08 2748774c 34b0bcb5 391c0cb3 4ed8aa4a 5b9cca4f 682e6ff3 748f82ee 78a5636f 84c87814 8cc70208 90befffa a4506ceb bef9a3f7 c67178f2'.split()
s=header+'\nmodule m_tsmx_codec_core #(\n'+params+''',
  localparam logic [255:0] LPARA_IV =
    256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19,
  localparam logic [2047:0] LPARA_K = 2048'h'''+''.join(k)+'''
) (
'''+ports+''');
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
'''
for name,width,reset in regs:
    s+=f'  logic [{width-1}:0] reg_{name}, w_{name}_nxt;\n'
s+='''  logic [7:0] w_op, w_byte;
  logic [2:0] w_count;
  logic [31:0] w_len, w_limit, w_crc, w_word, w_pos;
  logic w_start, w_end, w_take, w_bad, w_push, w_finish, w_raw;
  logic [31:0] w_a, w_b, w_c, w_d, w_e, w_f, w_g, w_h;
  logic [31:0] w_t1, w_t2, w_schedule;
  logic [255:0] w_sum;

  // SHA-256 fixed rotations; arguments and return values are unsigned protocol words.
  function automatic [31:0] rotr(input logic [31:0] w_x, input logic [4:0] w_n);
    rotr = (w_x >> w_n) | (w_x << (6'd32-{1'b0,w_n}));
  endfunction
  function automatic [31:0] crc_byte(input logic [31:0] w_x, input logic [7:0] w_y);
    logic [31:0] w_v;
    begin
      w_v=w_x^{24'd0,w_y};
      for (int idx=0; idx<8; idx++) begin
        if (w_v[0]) w_v=(w_v>>1)^32'hedb88320;
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
            && w_pos>=(32'd1+({24'd0,reg_objects}<<5))) w_bad=w_bad | (w_byte!=8'd0);
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
      +((w_e&w_f)^(~w_e&w_g))+LPARA_K[2047-32'(reg_round)*32 -: 32]
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
'''
for name,width,reset in regs: s+=f'    w_{name}_nxt=reg_{name};\n'
s+='''    w_word='0;
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
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
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
'''
for name,width,reset in regs: s+=f'          w_{name}_nxt={reset};\n'
s+='''          w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
        end
      end
      default: begin
        w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
        w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
        w_full_nxt='0;
      end
    endcase
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
'''
for name,width,reset in regs:s+=f'      reg_{name}<={reset};\n'
s+='''    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_fsm_sha_current_state<=w_fsm_sha_nxt_state;
'''
for name,width,reset in regs:s+=f'      reg_{name}<=w_{name}_nxt;\n'
s+='''    end
  end
endmodule
`default_nettype wire
'''
iv='6a09e667 bb67ae85 3c6ef372 a54ff53a 510e527f 9b05688c 1f83d9ab 5be0cd19'.split()
wide=s[s.index('  localparam logic [255:0]'):s.index('\n) (')]
constants=[f"  localparam logic [31:0] LPARA_IV_{i} = 32'h{v}" for i,v in enumerate(iv)]
constants += [f"  localparam logic [31:0] LPARA_K_{i} = 32'h{v}" for i,v in enumerate(k)]
s=s.replace(wide,',\n'.join(constants))
s=s.replace('LPARA_IV;', 'sha_iv();').replace('LPARA_IV\n','sha_iv()\n')
s=s.replace("LPARA_K[2047-32'(reg_round)*32 -: 32]",'sha_k(reg_round)')
func='  // FIPS180-4 initialization vector and round constants, independent of payload.\n'
func+='  function automatic [255:0] sha_iv();\n    sha_iv={'+','.join(f'LPARA_IV_{i}' for i in range(8))+'};\n  endfunction\n'
func+='  function automatic [31:0] sha_k(input logic [5:0] w_idx);\n    case (w_idx)\n'
func+=''.join(f"      6'd{i}: sha_k=LPARA_K_{i};\n" for i in range(64))
func+="      default: sha_k=32'd0;\n    endcase\n  endfunction\n\n"
s=s.replace('  // SHA-256 fixed rotations',func+'  // SHA-256 fixed rotations')
s=s.replace('w_op, w_byte;', 'w_op, w_byte, w_objects;')
s=s.replace('{24\'d0,reg_objects}',"{24'd0,w_objects}")
# BOOT is also an illegal-state recovery barrier, so it reinitializes all job state.
boot="      ENUM_ST_BOOT: begin\n        w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;\n        w_fsm_sha_nxt_state=ENUM_ST_EMPTY;\n"
for name,width,reset in regs:
    boot+=f'        w_{name}_nxt={reset.replace("LPARA_IV","sha_iv()")};\n'
boot+='      end'
s=s.replace('      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;',boot)
s=s.replace('    if (w_push) begin', '''    if (reg_fsm_sha_current_state==2'd3) begin
      w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
      w_fsm_sha_nxt_state=ENUM_ST_EMPTY;
      w_full_nxt='0;
      w_push=1'b0;
    end
    if (w_push) begin''')
(OUT/'m_tsmx_codec_core.sv').write_text(s)
