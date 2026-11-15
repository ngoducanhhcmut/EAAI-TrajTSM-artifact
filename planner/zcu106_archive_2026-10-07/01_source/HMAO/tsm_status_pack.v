// =============================================================================
// tsm_status_pack.v — dong goi ket qua TSM thanh 2 tu 32 bit cho axi_gpio_1 (chi doc).
//
// v2d (05/10/2026): truoc day chi hmao_complete (ngat) ra toi PS; PS khong doc duoc
// GRANT/VETO. Khoi nay chi noi day (to hop), khong co thanh ghi.
//
//   GPIO1 (0xA002_0000):
//     [0]     decision        1 = GRANT, 0 = VETO
//     [1]     complete        muc hmao_complete (ngat chua xoa)
//     [7:2]   0
//     [14:8]  fault_bits      hmao_fault_t: [6] WDT [5] zonotope [4] ADMM [3] CRC
//                             [2] SMPU [1] tran so hoc / dinh dang [0] dong hoc
//     [15]    fault_valid
//     [23:16] violation_type  01 ngang, 02 doc, ...
//     [31:24] stage_state     01 tang 1, 02 tang 2
//   GPIO2 (0xA002_0008):
//     [15:0]  time_step_idx   buoc dau tien va cham
//     [31:16] obstacle_id     track_id cua vat can
//
// Cac tin hieu nguon thuoc clk_pl_2 va giu on dinh tu luc hmao_complete len toi lan
// hmao_start sau; PS chi doc sau ngat -> du lieu tinh, rang buoc max_delay trong
// constrain/hmao_bd_timing.xdc.
// =============================================================================
module tsm_status_pack (
  input  wire        hmao_decision,
  input  wire        hmao_complete,
  input  wire [63:0] hmao_violation,
  input  wire [6:0]  fault_bits,
  input  wire        fault_valid,
  output wire [31:0] gpio_status,
  output wire [31:0] gpio_detail
);
  assign gpio_status = {hmao_violation[63:56], hmao_violation[55:48], fault_valid, fault_bits,
                        6'b0, hmao_complete, hmao_decision};
  assign gpio_detail = {hmao_violation[47:32], hmao_violation[31:16]};
endmodule
