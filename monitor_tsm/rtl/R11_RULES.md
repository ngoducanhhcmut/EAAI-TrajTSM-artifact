# RTL rule check

Files: m_tsmx_health.sv, m_tsmx_health_bist.sv, m_tsmx_health_lane.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| WARN | HIE-02 | m_tsmx_health.sv:15 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_tsmx_health_bist.sv:15 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | PAR-03 | m_tsmx_health.sv:83 | literal 64'd766660 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_health.sv:92 | literal 64'd1800000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_health.sv:93 | literal 64'd950000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_health.sv:95 | literal 64'd20000000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_health.sv:97 | literal 64'd4000000 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_tsmx_health.sv:103 | literal 32'd1000000 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: none
Rules warned: HIE-02, PAR-03
Rules clean: ARI-04, CMT-01, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, ENM-01, ENM-03, ENM-04, ENM-05, FIL-01, FIL-02, FIL-03, HIE-01, HIE-03, HIE-05, NAM-07, NAM-08, NAM-TBL, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P4, P6, P7, PAR-01, PAR-02, R-019, SCP-01, SEC-8.1, SEQ-01, TYP-02
