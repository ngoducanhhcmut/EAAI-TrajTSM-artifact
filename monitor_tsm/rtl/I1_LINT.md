COMMAND: /home/ngoducanh/oss-cad-suite/bin/tabbypy3 -B /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/.agents/skills/vlsit-rtl-generator/scripts/vlsit_lint_rtl.py lint /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/rtl/filelist_top.f --top m_tsmx_top --log /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/rtl/I1_LINT_DETAIL.md
tool: verilator (LINT) | top: m_tsmx_top | files: 24
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:160:28: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_cell' generates 8 bits.
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:163:28: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_cell' generates 8 bits.
%Warning-WIDTHEXPAND: geom/m_tsmx_geom.sv:179:19: Operator LT expects 32 bits on the LHS, but LHS's VARREF 'reg_actor' generates 8 bits.
%Warning-WIDTHCONCAT: geom/m_tsmx_geom.sv:436:18: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:90:15: Replication of more that --replication-limit 8192 is suspect: 8584
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:91:13: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-WIDTHCONCAT: health/m_tsmx_health.sv:168:16: Replication of more that --replication-limit 8192 is suspect: 33824
%Warning-WIDTHTRUNC: top/m_tsmx_sweep.sv:125:25: Bit extraction of var[15:0] requires 4 bit index, not 8 bits.
%Warning-WIDTHCONCAT: top/m_tsmx_sweep.sv:157:20: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-WIDTHTRUNC: rec/m_tsmx_rec.sv:189:69: Bit extraction of array[63:0] requires 6 bit index, not 10 bits.
%Warning-WIDTHTRUNC: rec/m_tsmx_rec.sv:207:28: Bit extraction of array[63:0] requires 6 bit index, not 10 bits.
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:189:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h0' generates 2 bits.
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:189:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h2' generates 2 bits.
%Warning-WIDTHEXPAND: top/m_tsmx_math.sv:189:9: Operator CASE expects 3 bits on the Case Item, but Case Item's CONST '2'h3' generates 2 bits.
%Warning-WIDTHCONCAT: top/m_tsmx_math.sv:443:37: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-WIDTHCONCAT: top/m_tsmx_hash.sv:85:19: Replication of more that --replication-limit 8192 is suspect: 8416
%Warning-WIDTHEXPAND: arb/m_tsmx_arb.sv:131:58: Bit extraction of var[31:0] requires 5 bit index, not 4 bits.
%Warning-WIDTHCONCAT: top/m_tsmx_io.sv:96:54: Replication of more that --replication-limit 8192 is suspect: 44673
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:592:89: Replication of more that --replication-limit 8192 is suspect: 33824
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:655:23: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1178:18: Replication of more that --replication-limit 8192 is suspect: 44673
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1200:20: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-WIDTHCONCAT: top/m_tsmx_engine.sv:1202:19: Replication of more that --replication-limit 8192 is suspect: 8200
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:238:18: Bits of signal are not used: 'w_arb_resp_data'[1996:1897]
%Warning-UNUSEDSIGNAL: top/m_tsmx_engine.sv:251:16: Bits of signal are not used: 'reg_xprod'[46:0]
... more in the log
log: /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/rtl/I1_LINT_DETAIL_19.md
RESULT: PASS (0 errors, 87 warnings)
