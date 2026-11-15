# RTL rule check

Files: m_tsmx_arith.sv, m_tsmx_arith_div.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| WARN | HIE-02 | m_tsmx_arith.sv:16 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | PAR-03 | m_tsmx_arith.sv:79 | literal 32'd160 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:91 | literal 128'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:93 | literal 128'd2000000000000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:94 | literal 128'd1000000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:96 | literal 128'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:106 | literal 96'd2000000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:107 | literal 96'd2000000000000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_arith.sv:108 | literal 96'd1000000 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: none
Rules warned: HIE-02, PAR-03
Rules clean: ARI-04, CMT-01, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, ENM-01, ENM-03, ENM-04, ENM-05, FIL-01, FIL-02, FIL-03, HIE-01, HIE-03, HIE-05, NAM-07, NAM-08, NAM-TBL, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P4, P6, P7, PAR-01, PAR-02, R-019, SCP-01, SEC-8.1, SEQ-01, TYP-02
