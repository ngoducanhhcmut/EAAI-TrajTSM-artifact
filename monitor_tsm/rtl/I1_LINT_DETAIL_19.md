$ /home/ngoducanh/oss-cad-suite/bin/verilator_bin --lint-only -Wall --top-module m_tsmx_top arb/m_tsmx_arb.sv arith/m_tsmx_arith.sv cert/m_tsmx_cert.sv csr/m_tsmx_csr.sv codec/m_tsmx_codec_core.sv codec/m_tsmx_codec.sv top/m_tsmx_hash.sv health/m_tsmx_health.sv geom/m_tsmx_geom_su.sv geom/m_tsmx_geom.sv mrmgen/m_tsmx_mrmgen.sv health/m_tsmx_health_bist.sv health/m_tsmx_health_lane.sv ingress/m_tsmx_ingress.sv top/m_tsmx_math.sv rec/m_tsmx_rec.sv sel/m_tsmx_sel.sv splice/m_tsmx_splice.sv supervisor/m_tsmx_supervisor.sv top/m_tsmx_sweep.sv top/m_tsmx_engine.sv top/m_tsmx_io.sv top/m_tsmx_rst.sv top/m_tsmx_top.sv
(cwd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/rtl)

%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:160:28: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_cell' generates 8 bits.
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  160 |   assign w_row = (reg_cell < PARA_MAX_CELLS
      |                            ^
                      ... For warning description see https://verilator.org/warn/WIDTHEXPAND?v=5.053
                      ... Use "/* verilator lint_off WIDTHEXPAND */" and lint_on around source to disable this message.
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:163:28: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_cell' generates 8 bits.
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  163 |   assign w_nxt = (reg_cell < PARA_MAX_CELLS
      |                            ^
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:179:19: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_actor' generates 8 bits.
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  179 |     if (reg_actor < PARA_MAX_OBJ) w_object = w_ord;
      |                   ^
%Warning-WIDTHCONCAT: geom/m_tsmx_geom.sv:436:18: Replication of more that --replication-limit 8192 is suspect: 8200
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  436 |       reg_world<='0;
      |                  ^~
                      ... For warning description see https://verilator.org/warn/WIDTHCONCAT?v=5.053
                      ... Use "/* verilator lint_off WIDTHCONCAT */" and lint_on around source to disable this message.
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:90:15: Replication of more that --replication-limit 8192 is suspect: 8584
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   90 |     o_b3_data='0; o_b3_valid=1'b0; o_b3_ready=1'b0;
      |               ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:91:13: Replication of more that --replication-limit 8192 is suspect: 8200
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   91 |     w_world='0; w_lane={64'hffffffffffe488c0,64'd1800000,64'd0,
      |             ^~
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:168:16: Replication of more that --replication-limit 8192 is suspect: 33824
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
  168 |       reg_req<='0; reg_idx<='0; reg_good<=1'b0;
      |                ^~
%Warning-WIDTHTRUNC: top/m_tsmx_sweep.sv:125:25: Bit extraction of var[15:0] requires 4 bit index, not 8 bits.
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_1'
  125 |               w_mask_nxt[reg_base+8'(idx)]=w_geom_resp_data[81*idx+80];
      |                         ^
                     ... For warning description see https://verilator.org/warn/WIDTHTRUNC?v=5.053
                     ... Use "/* verilator lint_off WIDTHTRUNC */" and lint_on around source to disable this message.
%Warning-WIDTHCONCAT: top/m_tsmx_sweep.sv:157:20: Replication of more that --replication-limit 8192 is suspect: 8200
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_sweep_1'
  157 |       reg_world <= '0;
      |                    ^~
%Warning-WIDTHTRUNC: rec/m_tsmx_rec.sv:189:69: Bit extraction of array[63:0] requires 6 bit index, not 10 bits.
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_rec'
  189 |       if ({1'b0, i_log_idx} < reg_count) w_log_data_nxt = reg_events[w_rd_addr];
      |                                                                     ^
%Warning-WIDTHTRUNC: rec/m_tsmx_rec.sv:207:28: Bit extraction of array[63:0] requires 6 bit index, not 10 bits.
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_rec'
  207 |     if (w_wr_en) reg_events[w_wr_addr] <= i_req_data;
      |                            ^
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:189:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h0' generates 2 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  189 |         case(reg_op)
      |         ^~~~
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:189:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h2' generates 2 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  189 |         case(reg_op)
      |         ^~~~
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:189:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h3' generates 2 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  189 |         case(reg_op)
      |         ^~~~
%Warning-WIDTHCONCAT: top/m_tsmx_math.sv:443:37: Replication of more that --replication-limit 8192 is suspect: 8200
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
  443 |     if (!i_rst_n_core) reg_world <= '0;
      |                                     ^~
%Warning-WIDTHCONCAT: top/m_tsmx_hash.sv:85:19: Replication of more that --replication-limit 8192 is suspect: 8416
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_hash'
   85 |       reg_data <= '0;
      |                   ^~
%Warning-WIDTHEXPAND: arb/m_tsmx_arb.sv:131:58: Bit extraction of var[31:0] requires 5 bit index, not 4 bits.
                                              : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_arb'
  131 |           if (w_cand < 8'(LPARA_PROFILES) && LPARA_FINITE[w_cand[3:0]] && w_label == ENUM_LABEL_COND) begin
      |                                                          ^
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:96:54: Replication of more that --replication-limit 8192 is suspect: 44673
                                            : ... note: In instance 'm_tsmx_top.u_tsmx_io'
   96 |     o_req_ready=1'b0; o_core_valid=1'b0; o_core_data='0; o_core_reason='0;
      |                                                      ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:592:89: Replication of more that --replication-limit 8192 is suspect: 33824
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  592 |     w_rec_req_valid=1'b0; w_rec_req_data='0; w_health_req_valid=1'b0; w_health_req_data='0;
      |                                                                                         ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:655:23: Replication of more that --replication-limit 8192 is suspect: 8200
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  655 |           w_world_nxt='0;
      |                       ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1178:18: Replication of more that --replication-limit 8192 is suspect: 44673
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1178 |       reg_req <= '0;
      |                  ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1200:20: Replication of more that --replication-limit 8192 is suspect: 8200
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1200 |       reg_world <= '0;
      |                    ^~
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1202:19: Replication of more that --replication-limit 8192 is suspect: 8200
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
 1202 |       reg_lead <= '0;
      |                   ^~
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:238:18: Bits of signal are not used: 'w_arb_resp_data'[1996:1897]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  238 |   logic [1996:0] w_arb_resp_data;
      |                  ^~~~~~~~~~~~~~~
                       ... For warning description see https://verilator.org/warn/UNUSEDSIGNAL?v=5.053
                       ... Use "/* verilator lint_off UNUSEDSIGNAL */" and lint_on around source to disable this message.
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:251:16: Bits of signal are not used: 'reg_xprod'[46:0]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  251 |   logic [64:0] reg_xprod,reg_xmprod;
      |                ^~~~~~~~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:251:26: Bits of signal are not used: 'reg_xmprod'[38:0]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  251 |   logic [64:0] reg_xprod,reg_xmprod;
      |                          ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:258:48: Bits of signal are not used: 'w_applydiff'[30:0]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  258 |   logic [31:0] w_tickdiff,w_remaining,w_ackage,w_applydiff;
      |                                                ^~~~~~~~~~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:283:16: Bits of signal are not used: 'w_dup_mask'[15:1]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine'
  283 |   logic [15:0] w_dup_mask;
      |                ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_io.sv:72:16: Signal is not used: 'w_rxword'
                                             : ... note: In instance 'm_tsmx_top.u_tsmx_io'
   72 |   logic [31:0] w_rxword;
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
%Warning-UNUSEDPARAM: ingress/m_tsmx_ingress.sv:22:26: Parameter is not used: 'PARA_PACKET_LIMIT'
                                                     : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   22 |   parameter logic [31:0] PARA_PACKET_LIMIT = 32'd65536,
      |                          ^~~~~~~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:76:36: Signal is not used: 'w_apply'
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   76 |   logic [31:0] w_seq, w_generated, w_apply, w_v, w_a, w_compute, w_schema;
      |                                    ^~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:85:17: Bits of signal are not used: 'w_ego_rest'[159:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   85 |   logic [223:0] w_ego_rest, w_snap_rest;
      |                 ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:85:29: Signal is not used: 'w_snap_rest'
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   85 |   logic [223:0] w_ego_rest, w_snap_rest;
      |                             ^~~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:86:50: Bits of signal are not used: 'w_gen_age'[30:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   86 |   logic [31:0] w_seq_age, w_ego_age, w_snap_age, w_gen_age, w_gen_snap;
      |                                                  ^~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:86:61: Bits of signal are not used: 'w_gen_snap'[30:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   86 |   logic [31:0] w_seq_age, w_ego_age, w_snap_age, w_gen_age, w_gen_snap;
      |                                                             ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:92:17: Bits of signal are not used: 'w_arith_rsp'[640:512,510:0]
                                                      : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
   92 |   logic [640:0] w_arith_rsp;
      |                 ^~~~~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:106:18: Function variable is not used: 'w_t'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  106 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                  ^~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:106:23: Function variable is not used: 'w_speed'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  106 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                       ^~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:106:32: Function variable is not used: 'w_accel'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  106 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                                ^~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:106:41: Function variable is not used: 'w_lead_v'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  106 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v;
      |                                         ^~~~~~~~
%Warning-UNUSEDSIGNAL: ingress/m_tsmx_ingress.sv:117:18: Function variable is not used: 'w_t'
                                                       : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b1'
  117 |     logic [31:0] w_t, w_speed, w_accel, w_lead_v, w_mag;
      |                  ^~~
%Warning-UNUSEDSIGNAL: top/m_tsmx_math.sv:98:17: Bits of signal are not used: 'w_arith_resp_data'[639:544,479:352,319:0]
                                               : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_tsmx_math'
   98 |   logic [640:0] w_arith_resp_data;
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
%Warning-UNUSEDSIGNAL: splice/m_tsmx_splice.sv:52:17: Bits of signal are not used: 'w_arith_resp'[639:544,479:384,319:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b2'
   52 |   logic [640:0] w_arith_resp;
      |                 ^~~~~~~~~~~~
%Warning-UNUSEDSIGNAL: supervisor/m_tsmx_supervisor.sv:26:21: Bits of signal are not used: 'i_req_data'[38]
                                                            : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b8'
   26 |   input wire [43:0] i_req_data,
      |                     ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: health/m_tsmx_health.sv:33:22: Bits of signal are not used: 'i_b4_data'[400:393]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   33 |   input wire [401:0] i_b4_data,
      |                      ^~~~~~~~~
%Warning-UNUSEDSIGNAL: health/m_tsmx_health.sv:36:21: Bits of signal are not used: 'i_b3_data'[79:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health'
   36 |   input wire [80:0] i_b3_data,
      |                     ^~~~~~~~~
%Warning-UNUSEDSIGNAL: health/m_tsmx_health_bist.sv:52:17: Bits of signal are not used: 'w_grow'[400:361,0]
                                                         : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist'
   52 |   logic [400:0] w_grow;
      |                 ^~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:38:22: Bits of signal are not used: 'i_row_data'[0]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   38 |   input wire [400:0] i_row_data,
      |                      ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:91:17: Bits of signal are not used: 'reg_rowc'[351:256]
                                                : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
   91 |   logic [351:0] reg_rowc;
      |                 ^~~~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:105:24: Bits of signal are not used: 'w_nxt'[351:288,255:0]
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  105 |   logic [351:0] w_row, w_nxt;
      |                        ^~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:106:41: Signal is not used: 'w_accel'
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  106 |   logic [31:0] w_h, w_event, w_elapsed, w_accel;
      |                                         ^~~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom.sv:108:17: Bits of signal are not used: 'w_object'[255:160]
                                                 : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom'
  108 |   logic [255:0] w_object;
      |                 ^~~~~~~~
%Warning-UNUSEDSIGNAL: mrmgen/m_tsmx_mrmgen.sv:62:17: Bits of signal are not used: 'w_ar_resp'[639:544,479:352,319:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_mrmgen'
   62 |   logic [640:0] w_ar_resp;
      |                 ^~~~~~~~~
%Warning-UNUSEDPARAM: geom/m_tsmx_geom_su.sv:69:26: Parameter is not used: 'LPARA_D1E6'
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom.gen_su[3].u_geom_su'
   69 |   localparam logic [1:0] LPARA_D1E6=2'd0, LPARA_D2E6=2'd1, LPARA_D2E12=2'd2, LPARA_D5P18=2'd3;
      |                          ^~~~~~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom_su.sv:106:16: Bits of signal are not used: 'w_dn41'[5:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom.gen_su[3].u_geom_su'
  106 |   logic [40:0] w_dn41;
      |                ^~~~~~
%Warning-UNUSEDSIGNAL: geom/m_tsmx_geom_su.sv:107:16: Bits of signal are not used: 'w_dn40'[5:0]
                                                    : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_health.u_tsmx_health_bist.u_tsmx_geom.gen_su[3].u_geom_su'
  107 |   logic [39:0] w_dn40;
      |                ^~~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:95:16: Bits of signal are not used: 'w_lnext'[17:0]
                                                  : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
   95 |   logic [22:0] w_lnext;
      |                ^~~~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:134:24: Bits of signal are not used: 'w_dq1'[159]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  134 |   logic [159:0] w_dn1, w_dq1, w_dn2, w_dq2, w_dmagq, w_dval;
      |                        ^~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:166:66: Bits of function variable are not used: 'w_id'[159:4]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  166 |   function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
      |                                                                  ^~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:166:71: Bits of function variable are not used: 'w_t'[158:32]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  166 |   function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
      |                                                                       ^~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:166:75: Bits of function variable are not used: 'w_initial'[159:64]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  166 |   function automatic logic [159:0] f_profile(input logic [159:0] w_id,w_t,w_initial);
      |                                                                           ^~~~~~~~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:210:54: Bits of function variable are not used: 'w_a'[158:128,126:96,94:0]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  210 |   function automatic logic f_msb(input logic [159:0] w_a, input logic [1:0] w_w);
      |                                                      ^~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:218:62: Bits of function variable are not used: 'w_a'[159:128]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  218 |   function automatic logic [159:0] f_trz(input logic [159:0] w_a, input logic [1:0] w_c);
      |                                                              ^~~
%Warning-UNUSEDSIGNAL: arith/m_tsmx_arith.sv:226:62: Bits of function variable are not used: 'w_a'[159:128]
                                                   : ... note: In instance 'm_tsmx_top.u_tsmx_engine.u_b9.u_arith'
  226 |   function automatic logic [159:0] f_trs(input logic [159:0] w_a, input logic [1:0] w_c);
      |                                                              ^~~
%Warning-SYNCASYNCNET: top/m_tsmx_rst.sv:20:15: Signal flopped as both synchronous and async: 'm_tsmx_top.u_tsmx_rst.reg_release'
                       top/m_tsmx_rst.sv:20:15: ... Location of async usage
   20 |   logic [1:0] reg_release;
      |               ^~~~~~~~~~~
                       top/m_tsmx_rst.sv:26:24: ... Location of sync usage
   26 |     else reg_release<={reg_release[0],1'b1};
      |                        ^~~~~~~~~~~
                       ... For warning description see https://verilator.org/warn/SYNCASYNCNET?v=5.053
                       ... Use "/* verilator lint_off SYNCASYNCNET */" and lint_on around source to disable this message.
%Error: Exiting due to 87 warning(s)

exit code 1
