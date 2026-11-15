$ /home/ngoducanh/oss-cad-suite/bin/verilator_bin --lint-only -Wall --top-module m_tsmx_top arb/m_tsmx_arb.sv arith/m_tsmx_arith.sv cert/m_tsmx_cert.sv csr/m_tsmx_csr.sv codec/m_tsmx_codec_core.sv codec/m_tsmx_codec.sv top/m_tsmx_hash.sv health/m_tsmx_health.sv geom/m_tsmx_geom_su.sv geom/m_tsmx_geom.sv mrmgen/m_tsmx_mrmgen.sv health/m_tsmx_health_bist.sv health/m_tsmx_health_lane.sv ingress/m_tsmx_ingress.sv top/m_tsmx_math.sv rec/m_tsmx_rec.sv sel/m_tsmx_sel.sv splice/m_tsmx_splice.sv supervisor/m_tsmx_supervisor.sv top/m_tsmx_sweep.sv top/m_tsmx_engine.sv top/m_tsmx_io.sv top/m_tsmx_rst.sv top/m_tsmx_top.sv
(cwd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/rtl)

%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:130:28: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_cell' generates 8 bits.
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  130 |   assign w_row = (reg_cell < PARA_MAX_CELLS
      |                            ^
                      ... For warning description see https://verilator.org/warn/WIDTHEXPAND?v=5.053
                      ... Use "/* verilator lint_off WIDTHEXPAND */" and lint_on around source to disable this message.
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:133:28: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_cell' generates 8 bits.
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  133 |   assign w_nxt = (reg_cell < PARA_MAX_CELLS
      |                            ^
%Warning-WIDTHTRUNC: geom/m_tsmx_geom.sv:139:53: Bit extraction of array[31:0] requires 5 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  139 |     if (reg_actor < PARA_MAX_OBJ) w_object = reg_obj[reg_actor];
      |                                                     ^
                     ... For warning description see https://verilator.org/warn/WIDTHTRUNC?v=5.053
                     ... Use "/* verilator lint_off WIDTHTRUNC */" and lint_on around source to disable this message.
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:139:19: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_actor' generates 8 bits.
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  139 |     if (reg_actor < PARA_MAX_OBJ) w_object = reg_obj[reg_actor];
      |                   ^
%Warning-WIDTHTRUNC: geom/m_tsmx_geom.sv:309:31: Bit extraction of array[31:0] requires 5 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  309 |         w_pose_nxt={reg_motion[reg_actor][191:64],
      |                               ^
%Warning-WIDTHTRUNC: geom/m_tsmx_geom.sv:311:30: Bit extraction of array[31:0] requires 5 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  311 |         w_vel_nxt={reg_motion[reg_actor][63:0],w_row[127:64]};
      |                              ^
%Warning-WIDTHTRUNC: geom/m_tsmx_geom.sv:312:37: Bit extraction of array[31:0] requires 5 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  312 |         w_ahead_nxt=!f_lt(reg_motion[reg_actor][191:128],w_row[191:128]);
      |                                     ^
%Warning-WIDTHTRUNC: geom/m_tsmx_geom.sv:348:21: Bit extraction of array[31:0] requires 5 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  348 |         w_motion_nxt[reg_actor]={reg_pose[255:128],reg_vel[127:64]};
      |                     ^
%Warning-WIDTHCONCAT: geom/m_tsmx_geom.sv:388:18: Replication of more that --replication-limit 8192 is suspect: 8200
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  388 |       reg_world<='0;
      |                  ^~
                      ... For warning description see https://verilator.org/warn/WIDTHCONCAT?v=5.053
                      ... Use "/* verilator lint_off WIDTHCONCAT */" and lint_on around source to disable this message.
%Warning-WIDTHCONCAT: health/m_tsmx_health_bist.sv:71:45: Replication of more that --replication-limit 8192 is suspect: 45408
                                                        : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist'
   71 |     if(i_b4_valid && o_b4_ready) w_rows_nxt='0;
      |                                             ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health_bist.sv:94:17: Replication of more that --replication-limit 8192 is suspect: 45408
                                                        : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist'
   94 |       reg_rows<='0; reg_traj<='0; reg_idx<='0;
      |                 ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health_bist.sv:94:31: Replication of more that --replication-limit 8192 is suspect: 45458
                                                        : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist'
   94 |       reg_rows<='0; reg_traj<='0; reg_idx<='0;
      |                               ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:91:15: Replication of more that --replication-limit 8192 is suspect: 54042
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   91 |     o_b3_data='0; o_b3_valid=1'b0; o_b3_ready=1'b0;
      |               ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:92:13: Replication of more that --replication-limit 8192 is suspect: 8200
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   92 |     w_world='0; w_lane={64'hffffffffffe488c0,64'd1800000,64'd0,
      |             ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:169:16: Replication of more that --replication-limit 8192 is suspect: 33824
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
  169 |       reg_req<='0; reg_traj<='0; reg_idx<='0; reg_good<=1'b0;
      |                ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:169:30: Replication of more that --replication-limit 8192 is suspect: 45458
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
  169 |       reg_req<='0; reg_traj<='0; reg_idx<='0; reg_good<=1'b0;
      |                              ^~
%Warning-WIDTHCONCAT: top/m_tsmx_sweep.sv:89:42: Replication of more that --replication-limit 8192 is suspect: 8624
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_1'
   89 |     w_geom_req_valid='0; w_geom_req_data='0; w_geom_row_valid='0; w_geom_row_data='0; w_geom_terminal_valid='0; w_geom_terminal_data='0;
      |                                          ^~
%Warning-WIDTHTRUNC: top/m_tsmx_sweep.sv:120:25: Bit extraction of var[15:0] requires 4 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_1'
  120 |               w_mask_nxt[reg_base+8'(idx)]=w_geom_resp_data[81*idx+80];
      |                         ^
%Warning-WIDTHCONCAT: top/m_tsmx_sweep.sv:152:20: Replication of more that --replication-limit 8192 is suspect: 8200
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_1'
  152 |       reg_world <= '0;
      |                    ^~
%Warning-WIDTHCONCAT: top/m_tsmx_sweep.sv:89:42: Replication of more that --replication-limit 8192 is suspect: 68992
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_1'
   89 |     w_geom_req_valid='0; w_geom_req_data='0; w_geom_row_valid='0; w_geom_row_data='0; w_geom_terminal_valid='0; w_geom_terminal_data='0;
      |                                          ^~
%Warning-WIDTHTRUNC: rec/m_tsmx_rec.sv:189:69: Bit extraction of array[63:0] requires 6 bit index, not 10 bits.
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_rec'
  189 |       if ({1'b0, i_log_idx} < reg_count) w_log_data_nxt = reg_events[w_rd_addr];
      |                                                                     ^
%Warning-WIDTHTRUNC: rec/m_tsmx_rec.sv:207:28: Bit extraction of array[63:0] requires 6 bit index, not 10 bits.
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_rec'
  207 |     if (w_wr_en) reg_events[w_wr_addr] <= i_req_data;
      |                            ^
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:174:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h0' generates 2 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  174 |         case(reg_op)
      |         ^~~~
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:174:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h2' generates 2 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  174 |         case(reg_op)
      |         ^~~~
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:174:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h3' generates 2 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  174 |         case(reg_op)
      |         ^~~~
%Warning-WIDTHCONCAT: top/m_tsmx_math.sv:370:20: Replication of more that --replication-limit 8192 is suspect: 8200
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  370 |       reg_world <= '0;
      |                    ^~
%Warning-WIDTHCONCAT: top/m_tsmx_hash.sv:85:19: Replication of more that --replication-limit 8192 is suspect: 8416
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_hash'
   85 |       reg_data <= '0;
      |                   ^~
%Warning-WIDTHEXPAND: arb/m_tsmx_arb.sv:131:58: Bit extraction of var[31:0] requires 5 bit index, not 4 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_arb'
  131 |           if (w_cand < 8'(LPARA_PROFILES) && LPARA_FINITE[w_cand[3:0]] && w_label == ENUM_LABEL_COND) begin
      |                                                          ^
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:93:54: Replication of more that --replication-limit 8192 is suspect: 44673
                                            : ... note: In instance 'm_tsmx_top.u_tsmx_io'
   93 |     o_req_ready=1'b0; o_core_valid=1'b0; o_core_data='0; o_core_reason='0;
      |                                                      ^~
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:150:49: Replication of more that --replication-limit 8192 is suspect: 44673
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
  150 |             w_rx_word_idx_nxt='0; w_partial_nxt='0; w_bad_nxt=1'b0; w_age_nxt='0;
      |                                                 ^~
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:157:29: Replication of more that --replication-limit 8192 is suspect: 44673
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
  157 |               w_partial_nxt='0; w_rx_word_idx_nxt=11'd1; end
      |                             ^~
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:176:53: Replication of more that --replication-limit 8192 is suspect: 44673
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
  176 |                 w_rx_word_idx_nxt='0; w_partial_nxt='0; w_bad_nxt=1'b0; w_age_nxt='0;
      |                                                     ^~
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:190:24: Replication of more that --replication-limit 8192 is suspect: 44673
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
  190 |       reg_rx_data_0 <= '0;
      |                        ^~
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:191:24: Replication of more that --replication-limit 8192 is suspect: 44673
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
  191 |       reg_rx_data_1 <= '0;
      |                        ^~
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:198:22: Replication of more that --replication-limit 8192 is suspect: 44673
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
  198 |       reg_partial <= '0;
      |                      ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:566:69: Replication of more that --replication-limit 8192 is suspect: 8416
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  566 |     w_hash_req_valid=1'b0; w_hash_op='0; w_hash_len='0; w_hash_data='0;
      |                                                                     ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:575:89: Replication of more that --replication-limit 8192 is suspect: 33824
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  575 |     w_rec_req_valid=1'b0; w_rec_req_data='0; w_health_req_valid=1'b0; w_health_req_data='0;
      |                                                                                         ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:638:23: Replication of more that --replication-limit 8192 is suspect: 8200
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  638 |           w_world_nxt='0;
      |                       ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:846:22: Replication of more that --replication-limit 8192 is suspect: 8200
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  846 |         w_math_world='0; w_math_world[8199:8192]=8'd1;
      |                      ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1176:18: Replication of more that --replication-limit 8192 is suspect: 44673
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1176 |       reg_req <= '0;
      |                  ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1198:20: Replication of more that --replication-limit 8192 is suspect: 8200
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1198 |       reg_world <= '0;
      |                    ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1199:21: Replication of more that --replication-limit 8192 is suspect: 8200
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1199 |       reg_future <= '0;
      |                     ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1201:19: Replication of more that --replication-limit 8192 is suspect: 8200
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1201 |       reg_lead <= '0;
      |                   ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1202:27: Replication of more that --replication-limit 8192 is suspect: 8200
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1202 |       reg_nominal_lead <= '0;
      |                           ^~
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:237:18: Bits of signal are not used: 'w_arb_resp_data'[1996:1897]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  237 |   logic [1996:0] w_arb_resp_data;
      |                  ^~~~~~~~~~~~~~~
                       ... For warning description see https://verilator.org/warn/UNUSEDSIGNAL?v=5.053
                       ... Use "/* verilator lint_off UNUSEDSIGNAL */" and lint_on around source to disable this message.
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:253:48: Bits of signal are not used: 'w_applydiff'[30:0]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  253 |   logic [31:0] w_tickdiff,w_remaining,w_ackage,w_applydiff;
      |                                                ^~~~~~~~~~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:278:16: Bits of signal are not used: 'w_dup_mask'[15:1]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  278 |   logic [15:0] w_dup_mask;
      |                ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_io.sv:67:16: Signal is not used: 'w_rxword'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
   67 |   logic [31:0] w_rxword;
      |                ^~~~~~~~
%Warning-UNUSEDSIGNAL: cert/m_tsmx_cert.sv:64:17: Bits of signal are not used: 'w_ar_resp'[479:0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9'
   64 |   logic [640:0] w_ar_resp;
      |                 ^~~~~~~~~
%Warning-UNUSEDSIGNAL: cert/m_tsmx_cert.sv:66:17: Bits of signal are not used: 'w_plan'[527:240,207:0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9'
   66 |   logic [559:0] w_plan;
      |                 ^~~~~~
%Warning-UNUSEDSIGNAL: cert/m_tsmx_cert.sv:81:26: Bits of signal are not used: 'w_apply'[30:0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9'
   81 |   logic [31:0] w_remain, w_apply, w_since, w_tail, w_phase;
      |                          ^~~~~~~
%Warning-UNUSEDSIGNAL: cert/m_tsmx_cert.sv:81:52: Bits of signal are not used: 'w_phase'[30:0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9'
   81 |   logic [31:0] w_remain, w_apply, w_since, w_tail, w_phase;
      |                                                    ^~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:24:27: Parameter is not used: 'LPARA_CTRL_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   24 |   localparam logic [31:0] LPARA_CTRL_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~
                      ... For warning description see https://verilator.org/warn/UNUSEDPARAM?v=5.053
                      ... Use "/* verilator lint_off UNUSEDPARAM */" and lint_on around source to disable this message.
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:28:27: Parameter is not used: 'LPARA_IRQ_EN_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   28 |   localparam logic [31:0] LPARA_IRQ_EN_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:30:27: Parameter is not used: 'LPARA_IRQ_STS_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   30 |   localparam logic [31:0] LPARA_IRQ_STS_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:32:27: Parameter is not used: 'LPARA_FAULT_COUNT_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   32 |   localparam logic [31:0] LPARA_FAULT_COUNT_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:34:27: Parameter is not used: 'LPARA_CRC_COUNT_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   34 |   localparam logic [31:0] LPARA_CRC_COUNT_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:36:27: Parameter is not used: 'LPARA_FRESH_COUNT_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   36 |   localparam logic [31:0] LPARA_FRESH_COUNT_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:38:27: Parameter is not used: 'LPARA_CERT_COUNT_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   38 |   localparam logic [31:0] LPARA_CERT_COUNT_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:40:27: Parameter is not used: 'LPARA_HEALTH_COUNT_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   40 |   localparam logic [31:0] LPARA_HEALTH_COUNT_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:42:27: Parameter is not used: 'LPARA_LOG_LOST_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   42 |   localparam logic [31:0] LPARA_LOG_LOST_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:44:27: Parameter is not used: 'LPARA_LAST_REASON_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   44 |   localparam logic [31:0] LPARA_LAST_REASON_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:46:27: Parameter is not used: 'LPARA_DECISION_CYCLES_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   46 |   localparam logic [31:0] LPARA_DECISION_CYCLES_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDPARAM: csr/m_tsmx_csr.sv:62:27: Parameter is not used: 'LPARA_CONFIG_VALID_RST'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
   62 |   localparam logic [31:0] LPARA_CONFIG_VALID_RST = 32'h00000000,
      |                           ^~~~~~~~~~~~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: csr/m_tsmx_csr.sv:144:22: Signal is not used: 'i_axi_awprot'
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
  144 |   input wire [3-1:0] i_axi_awprot,
      |                      ^~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: csr/m_tsmx_csr.sv:151:22: Signal is not used: 'i_axi_arprot'
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
  151 |   input wire [3-1:0] i_axi_arprot,
      |                      ^~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: csr/m_tsmx_csr.sv:155:24: Bits of signal are not used: 'i_sts_data'[102:89,77]
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_csr'
  155 |   input wire [115-1:0] i_sts_data,
      |                        ^~~~~~~~~~
%Warning-UNUSEDPARAM: ingress/m_tsmx_ingress.sv:20:26: Parameter is not used: 'PARA_PACKET_LIMIT'
                                                     : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   20 |   parameter logic [31:0] PARA_PACKET_LIMIT = 32'd65536,
      |                          ^~~~~~~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:73:36: Signal is not used: 'w_apply'
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   73 |   logic [31:0] w_seq, w_generated, w_apply, w_v, w_a, w_compute, w_schema;
      |                                    ^~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:82:17: Bits of signal are not used: 'w_ego_rest'[159:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   82 |   logic [223:0] w_ego_rest, w_snap_rest;
      |                 ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:82:29: Signal is not used: 'w_snap_rest'
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   82 |   logic [223:0] w_ego_rest, w_snap_rest;
      |                             ^~~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:83:50: Bits of signal are not used: 'w_gen_age'[30:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   83 |   logic [31:0] w_seq_age, w_ego_age, w_snap_age, w_gen_age, w_gen_snap;
      |                                                  ^~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:83:61: Bits of signal are not used: 'w_gen_snap'[30:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   83 |   logic [31:0] w_seq_age, w_ego_age, w_snap_age, w_gen_age, w_gen_snap;
      |                                                             ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:89:17: Bits of signal are not used: 'w_arith_rsp'[640:512,510:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   89 |   logic [640:0] w_arith_rsp;
      |                 ^~~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:103:18: Function variable is not used: 'w_t'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  103 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                  ^~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:103:23: Function variable is not used: 'w_speed'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  103 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                       ^~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:103:32: Function variable is not used: 'w_accel'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  103 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                                ^~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:103:41: Function variable is not used: 'w_lead_v'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  103 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                                         ^~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:114:18: Function variable is not used: 'w_t'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  114 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v, w_mag;
      |                  ^~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_math.sv:86:17: Bits of signal are not used: 'w_arith_resp_data'[639:544,479:352,319:0]
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
   86 |   logic [640:0] w_arith_resp_data;
      |                 ^~~~~~~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: rec/m_tsmx_rec.sv:62:15: Bits of signal are not used: 'w_wr_addr'[9:6]
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_rec'
   62 |   logic [9:0] w_wr_addr;
      |               ^~~~~~~~~
%Warning-UNUSEDSIGNAL: rec/m_tsmx_rec.sv:64:15: Bits of signal are not used: 'w_rd_addr'[9:6]
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_rec'
   64 |   logic [9:0] w_rd_addr;
      |               ^~~~~~~~~
%Warning-UNUSEDPARAM: sel/m_tsmx_sel.sv:18:26: Parameter is not used: 'PARA_PROFILES'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b7'
   18 |   parameter logic [31:0] PARA_PROFILES = 32'd16,
      |                          ^~~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: splice/m_tsmx_splice.sv:49:17: Bits of signal are not used: 'w_arith_resp'[639:544,479:384,319:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b2'
   49 |   logic [640:0] w_arith_resp;
      |                 ^~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: supervisor/m_tsmx_supervisor.sv:26:21: Bits of signal are not used: 'i_req_data'[38]
                                                            : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b8'
   26 |   input wire [43:0] i_req_data,
      |                     ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: health/m_tsmx_health.sv:36:21: Bits of signal are not used: 'i_b3_data'[79:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   36 |   input wire [80:0] i_b3_data,
      |                     ^~~~~~~~~
%Warning-UNUSEDSIGNAL: health/m_tsmx_health_bist.sv:42:33: Signal is not driven, nor used: 'w_gready'
                                                         : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist'
   42 |   logic w_grow_valid, w_gvalid, w_gready;
      |                                 ^~~~~~~~
%Warning-UNUSEDSIGNAL: health/m_tsmx_health_bist.sv:43:17: Bits of signal are not used: 'w_grow'[400:361,0]
                                                         : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist'
   43 |   logic [400:0] w_grow;
      |                 ^~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:34:22: Bits of signal are not used: 'i_row_data'[0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   34 |   input wire [400:0] i_row_data,
      |                      ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:85:17: Bits of signal are not used: 'w_row'[351:288]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   85 |   logic [351:0] w_row, w_nxt;
      |                 ^~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:85:24: Bits of signal are not used: 'w_nxt'[351:288,255:0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   85 |   logic [351:0] w_row, w_nxt;
      |                        ^~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:86:41: Signal is not used: 'w_accel'
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   86 |   logic [31:0] w_h, w_event, w_elapsed, w_accel;
      |                                         ^~~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:88:17: Bits of signal are not used: 'w_object'[255:160]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   88 |   logic [255:0] w_object;
      |                 ^~~~~~~~
%Warning-UNUSEDSIGNAL: mrmgen/m_tsmx_mrmgen.sv:62:17: Bits of signal are not used: 'w_ar_resp'[639:544,479:352,319:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen'
   62 |   logic [640:0] w_ar_resp;
      |                 ^~~~~~~~~
%Warning-UNUSEDPARAM: arith/m_tsmx_arith.sv:51:42: Parameter is not used: 'LPARA_C0'
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
   51 |   localparam logic [5:0] LPARA_Q0=6'd40, LPARA_C0=6'd52, LPARA_C1=6'd53, LPARA_C1E6=6'd54,
      |                                          ^~~~~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:100:24: Bits of signal are not used: 'w_dq1'[159]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  100 |   logic [159:0] w_dn1, w_dq1, w_dn2, w_dq2, w_dmagq, w_dval;
      |                        ^~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:132:66: Bits of function variable are not used: 'w_id'[159:4]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  132 |   function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
      |                                                                  ^~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:132:71: Bits of function variable are not used: 'w_t'[158:32]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  132 |   function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
      |                                                                       ^~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:132:75: Bits of function variable are not used: 'w_initial'[159:64]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  132 |   function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
      |                                                                           ^~~~~~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:175:54: Bits of function variable are not used: 'w_a'[158:128,126:96,94:0]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  175 |   function automatic logic f_msb(input logic [159:0] w_a, input logic [1:0] w_w);
      |                                                      ^~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:183:62: Bits of function variable are not used: 'w_a'[159:128]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  183 |   function automatic logic [159:0] f_trz(input logic [159:0] w_a, input logic [1:0] w_c);
      |                                                              ^~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:191:62: Bits of function variable are not used: 'w_a'[159:128]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen.u_tsmx_arith'
  191 |   function automatic logic [159:0] f_trs(input logic [159:0] w_a, input logic [1:0] w_c);
      |                                                              ^~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom_su.sv:82:22: Signal is not used: 'w_dm'
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom.gen_su[3].u_geom_su'
   82 |   logic [63:0] w_am, w_dm, w_dd, w_n, w_dn, w_vsum;
      |                      ^~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom_su.sv:84:17: Bits of signal are not used: 'w_shift'[127:64]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom.gen_su[3].u_geom_su'
   84 |   logic [127:0] w_shift;
      |                 ^~~~~~~
%Warning-SYNCASYNCNET: top/m_tsmx_rst.sv:20:15: Signal flopped as both synchronous and async: 'm_tsmx_top.u_tsmx_rst.reg_release'
                       top/m_tsmx_rst.sv:20:15: ... Location of async usage
   20 |   logic [1:0] reg_release;
      |               ^~~~~~~~~~~
                       top/m_tsmx_rst.sv:26:24: ... Location of sync usage
   26 |     else reg_release<={reg_release[0],1'b1};
      |                        ^~~~~~~~~~~
                       ... For warning description see https://verilator.org/warn/SYNCASYNCNET?v=5.053
                       ... Use "/* verilator lint_off SYNCASYNCNET */" and lint_on around source to disable this message.
%Warning-UNOPTFLAT: geom/m_tsmx_geom.sv:39:16: Signal unoptimizable: Circular combinational logic: 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_0.gen_geom[0].u_tsmx_geom.o_row_ready'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_0.gen_geom[0].u_tsmx_geom'
   39 |   output logic o_row_ready,
      |                ^~~~~~~~~~~
                    ... For warning description see https://verilator.org/warn/UNOPTFLAT?v=5.053
                    ... Use "/* verilator lint_off UNOPTFLAT */" and lint_on around source to disable this message.
                    geom/m_tsmx_geom.sv:39:16:      Example path: m_tsmx_top.u_tsmx_engine.u_tsmx_sweep_0.gen_geom[0].u_tsmx_geom.o_row_ready
                    top/m_tsmx_sweep.sv:71:3:      Example path: ALWAYS
                    top/m_tsmx_sweep.sv:62:22:      Example path: m_tsmx_top.u_tsmx_engine.u_tsmx_sweep_0.w_geom_req_valid
                    geom/m_tsmx_geom.sv:137:3:      Example path: ALWAYS
                    geom/m_tsmx_geom.sv:39:16:      Example path: m_tsmx_top.u_tsmx_engine.u_tsmx_sweep_0.gen_geom[0].u_tsmx_geom.o_row_ready
%Error: Exiting due to 106 warning(s)

exit code 1
