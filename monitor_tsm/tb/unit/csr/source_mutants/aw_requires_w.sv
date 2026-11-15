/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : AXI4-Lite CSR subordinate, atomic status and sticky diagnostics.
 * Assumptions  : See R4_DECISIONS.md; reset release is synchronized by the wrapper.
 * Protocol     : AXI4-Lite; PROT accepted; spec fixes axi rather than axil names.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_csr #(
  // Parameter Description: project byte address width; Config1 fixes this width.
  // Parameter values: 16 only; default 16.
  // Parameter unit: bit
  parameter logic [31:0] PARA_ADDR_W = 32'd16,
  // Parameter Description: project bus word width; byte strobes are fixed at four.
  // Parameter values: 32 only; default 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_DATA_W = 32'd32,
  localparam logic [31:0] LPARA_CTRL_ADDR = 32'h00000000,
  localparam logic [31:0] LPARA_CTRL_RST = 32'h00000000,
  localparam logic [31:0] LPARA_STS_ADDR = 32'h00000004,
  localparam logic [31:0] LPARA_STS_RST = 32'h0002001c,
  localparam logic [31:0] LPARA_IRQ_EN_ADDR = 32'h00000008,
  localparam logic [31:0] LPARA_IRQ_EN_RST = 32'h00000000,
  localparam logic [31:0] LPARA_IRQ_STS_ADDR = 32'h0000000c,
  localparam logic [31:0] LPARA_IRQ_STS_RST = 32'h00000000,
  localparam logic [31:0] LPARA_FAULT_COUNT_ADDR = 32'h00000010,
  localparam logic [31:0] LPARA_FAULT_COUNT_RST = 32'h00000000,
  localparam logic [31:0] LPARA_CRC_COUNT_ADDR = 32'h00000014,
  localparam logic [31:0] LPARA_CRC_COUNT_RST = 32'h00000000,
  localparam logic [31:0] LPARA_FRESH_COUNT_ADDR = 32'h00000018,
  localparam logic [31:0] LPARA_FRESH_COUNT_RST = 32'h00000000,
  localparam logic [31:0] LPARA_CERT_COUNT_ADDR = 32'h0000001c,
  localparam logic [31:0] LPARA_CERT_COUNT_RST = 32'h00000000,
  localparam logic [31:0] LPARA_HEALTH_COUNT_ADDR = 32'h00000020,
  localparam logic [31:0] LPARA_HEALTH_COUNT_RST = 32'h00000000,
  localparam logic [31:0] LPARA_LOG_LOST_ADDR = 32'h00000024,
  localparam logic [31:0] LPARA_LOG_LOST_RST = 32'h00000000,
  localparam logic [31:0] LPARA_LAST_REASON_ADDR = 32'h00000028,
  localparam logic [31:0] LPARA_LAST_REASON_RST = 32'h00000000,
  localparam logic [31:0] LPARA_DECISION_CYCLES_ADDR = 32'h0000002c,
  localparam logic [31:0] LPARA_DECISION_CYCLES_RST = 32'h00000000,
  localparam logic [31:0] LPARA_PROFILE_COUNT_ADDR = 32'h00000030,
  localparam logic [31:0] LPARA_PROFILE_COUNT_RST = 32'h00000010,
  localparam logic [31:0] LPARA_PROFILE_LIMIT_ADDR = 32'h00000034,
  localparam logic [31:0] LPARA_PROFILE_LIMIT_RST = 32'h00000080,
  localparam logic [31:0] LPARA_PROFILE_MASK_ADDR = 32'h00000038,
  localparam logic [31:0] LPARA_PROFILE_MASK_RST = 32'h0000ffff,
  localparam logic [31:0] LPARA_FRESH_TIMEOUT_US_ADDR = 32'h0000003c,
  localparam logic [31:0] LPARA_FRESH_TIMEOUT_US_RST = 32'h000249f0,
  localparam logic [31:0] LPARA_ODD_V_MAX_ADDR = 32'h00000040,
  localparam logic [31:0] LPARA_ODD_V_MAX_RST = 32'h00989680,
  localparam logic [31:0] LPARA_ACK_TIMEOUT_US_ADDR = 32'h00000044,
  localparam logic [31:0] LPARA_ACK_TIMEOUT_US_RST = 32'h00009c40,
  localparam logic [31:0] LPARA_LEASE_MAX_US_ADDR = 32'h00000048,
  localparam logic [31:0] LPARA_LEASE_MAX_US_RST = 32'h0007a120,
  localparam logic [31:0] LPARA_CONFIG_VALID_ADDR = 32'h0000004c,
  localparam logic [31:0] LPARA_CONFIG_VALID_RST = 32'h00000000,
  localparam logic [31:0] LPARA_PROFILE_0_DECEL_ADDR = 32'h00000050,
  localparam logic [31:0] LPARA_PROFILE_0_DECEL_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_0_JERK_ADDR = 32'h00000054,
  localparam logic [31:0] LPARA_PROFILE_0_JERK_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_1_DECEL_ADDR = 32'h00000058,
  localparam logic [31:0] LPARA_PROFILE_1_DECEL_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_1_JERK_ADDR = 32'h0000005c,
  localparam logic [31:0] LPARA_PROFILE_1_JERK_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_2_DECEL_ADDR = 32'h00000060,
  localparam logic [31:0] LPARA_PROFILE_2_DECEL_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_2_JERK_ADDR = 32'h00000064,
  localparam logic [31:0] LPARA_PROFILE_2_JERK_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_3_DECEL_ADDR = 32'h00000068,
  localparam logic [31:0] LPARA_PROFILE_3_DECEL_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_3_JERK_ADDR = 32'h0000006c,
  localparam logic [31:0] LPARA_PROFILE_3_JERK_RST = 32'h00000000,
  localparam logic [31:0] LPARA_PROFILE_4_DECEL_ADDR = 32'h00000070,
  localparam logic [31:0] LPARA_PROFILE_4_DECEL_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_4_JERK_ADDR = 32'h00000074,
  localparam logic [31:0] LPARA_PROFILE_4_JERK_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_5_DECEL_ADDR = 32'h00000078,
  localparam logic [31:0] LPARA_PROFILE_5_DECEL_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_5_JERK_ADDR = 32'h0000007c,
  localparam logic [31:0] LPARA_PROFILE_5_JERK_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_6_DECEL_ADDR = 32'h00000080,
  localparam logic [31:0] LPARA_PROFILE_6_DECEL_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_6_JERK_ADDR = 32'h00000084,
  localparam logic [31:0] LPARA_PROFILE_6_JERK_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_7_DECEL_ADDR = 32'h00000088,
  localparam logic [31:0] LPARA_PROFILE_7_DECEL_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_7_JERK_ADDR = 32'h0000008c,
  localparam logic [31:0] LPARA_PROFILE_7_JERK_RST = 32'h00000000,
  localparam logic [31:0] LPARA_PROFILE_8_DECEL_ADDR = 32'h00000090,
  localparam logic [31:0] LPARA_PROFILE_8_DECEL_RST = 32'h005b8d80,
  localparam logic [31:0] LPARA_PROFILE_8_JERK_ADDR = 32'h00000094,
  localparam logic [31:0] LPARA_PROFILE_8_JERK_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_9_DECEL_ADDR = 32'h00000098,
  localparam logic [31:0] LPARA_PROFILE_9_DECEL_RST = 32'h005b8d80,
  localparam logic [31:0] LPARA_PROFILE_9_JERK_ADDR = 32'h0000009c,
  localparam logic [31:0] LPARA_PROFILE_9_JERK_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_10_DECEL_ADDR = 32'h000000a0,
  localparam logic [31:0] LPARA_PROFILE_10_DECEL_RST = 32'h005b8d80,
  localparam logic [31:0] LPARA_PROFILE_10_JERK_ADDR = 32'h000000a4,
  localparam logic [31:0] LPARA_PROFILE_10_JERK_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_11_DECEL_ADDR = 32'h000000a8,
  localparam logic [31:0] LPARA_PROFILE_11_DECEL_RST = 32'h005b8d80,
  localparam logic [31:0] LPARA_PROFILE_11_JERK_ADDR = 32'h000000ac,
  localparam logic [31:0] LPARA_PROFILE_11_JERK_RST = 32'h00000000,
  localparam logic [31:0] LPARA_PROFILE_12_DECEL_ADDR = 32'h000000b0,
  localparam logic [31:0] LPARA_PROFILE_12_DECEL_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_12_JERK_ADDR = 32'h000000b4,
  localparam logic [31:0] LPARA_PROFILE_12_JERK_RST = 32'h001e8480,
  localparam logic [31:0] LPARA_PROFILE_13_DECEL_ADDR = 32'h000000b8,
  localparam logic [31:0] LPARA_PROFILE_13_DECEL_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_13_JERK_ADDR = 32'h000000bc,
  localparam logic [31:0] LPARA_PROFILE_13_JERK_RST = 32'h003d0900,
  localparam logic [31:0] LPARA_PROFILE_14_DECEL_ADDR = 32'h000000c0,
  localparam logic [31:0] LPARA_PROFILE_14_DECEL_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_14_JERK_ADDR = 32'h000000c4,
  localparam logic [31:0] LPARA_PROFILE_14_JERK_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_15_DECEL_ADDR = 32'h000000c8,
  localparam logic [31:0] LPARA_PROFILE_15_DECEL_RST = 32'h007a1200,
  localparam logic [31:0] LPARA_PROFILE_15_JERK_ADDR = 32'h000000cc,
  localparam logic [31:0] LPARA_PROFILE_15_JERK_RST = 32'h00000000,
  localparam logic [31:0] LPARA_CONFIG_IRQ = 32'h20,
  localparam logic [31:0] LPARA_BYTE_W = 32'd8,
  localparam logic [31:0] LPARA_MODE_L3 = 32'd3,
  localparam logic [31:0] LPARA_REASON_CRC = 32'd9,
  localparam logic [31:0] LPARA_REASON_CLK = 32'd1,
  localparam logic [31:0] LPARA_REASON_SAMPLE = 32'd2,
  localparam logic [31:0] LPARA_REASON_EGO = 32'd11,
  localparam logic [31:0] LPARA_REASON_FRESH = 32'd12,
  localparam logic [31:0] LPARA_REASON_FREEZE = 32'd13,
  localparam logic [31:0] LPARA_COMMIT_OK = 32'd0,
  localparam logic [31:0] LPARA_COMMIT_DONE = 32'd31,
  localparam logic [31:0] LPARA_COMMIT_PENDING = 32'd32,
  localparam logic [31:0] LPARA_COMMIT_NONE = 32'd35
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire [PARA_ADDR_W-1:0] i_axi_awaddr,
  input wire [3-1:0] i_axi_awprot,
  input wire i_axi_awvalid,
  input wire [PARA_DATA_W-1:0] i_axi_wdata,
  input wire [4-1:0] i_axi_wstrb,
  input wire i_axi_wvalid,
  input wire i_axi_bready,
  input wire [PARA_ADDR_W-1:0] i_axi_araddr,
  input wire [3-1:0] i_axi_arprot,
  input wire i_axi_arvalid,
  input wire i_axi_rready,
  input wire i_sts_valid,
  input wire [115-1:0] i_sts_data,
  output logic o_axi_awready,
  output logic o_axi_wready,
  output logic o_axi_bvalid,
  output logic [2-1:0] o_axi_bresp,
  output logic o_axi_arready,
  output logic o_axi_rvalid,
  output logic [2-1:0] o_axi_rresp,
  output logic [PARA_DATA_W-1:0] o_axi_rdata,
  output logic [4-1:0] o_config_data,
  output logic o_int_irq
);
  logic reg_aw_full;
  logic w_aw_full_nxt;
  logic reg_w_full;
  logic w_w_full_nxt;
  logic [PARA_ADDR_W-1:0] reg_awaddr;
  logic [PARA_ADDR_W-1:0] w_awaddr_nxt;
  logic [PARA_DATA_W-1:0] reg_wdata;
  logic [PARA_DATA_W-1:0] w_wdata_nxt;
  logic [4-1:0] reg_wstrb;
  logic [4-1:0] w_wstrb_nxt;
  logic reg_bvalid;
  logic w_bvalid_nxt;
  logic [2-1:0] reg_bresp;
  logic [2-1:0] w_bresp_nxt;
  logic reg_rvalid;
  logic w_rvalid_nxt;
  logic [2-1:0] reg_rresp;
  logic [2-1:0] w_rresp_nxt;
  logic [PARA_DATA_W-1:0] reg_rdata;
  logic [PARA_DATA_W-1:0] w_rdata_nxt;
  logic reg_en;
  logic w_en_nxt;
  logic reg_config_valid;
  logic w_config_valid_nxt;
  logic reg_bist_wait;
  logic w_bist_wait_nxt;
  logic reg_soft_rst;
  logic w_soft_rst_nxt;
  logic reg_bist_start;
  logic w_bist_start_nxt;
  logic [8-1:0] reg_irq_en;
  logic [8-1:0] w_irq_en_nxt;
  logic [8-1:0] reg_irq_sts;
  logic [8-1:0] w_irq_sts_nxt;
  logic [32-1:0] reg_sts;
  logic [32-1:0] w_sts_nxt;
  logic [32-1:0] reg_fault_cnt;
  logic [32-1:0] w_fault_cnt_nxt;
  logic [32-1:0] reg_crc_cnt;
  logic [32-1:0] w_crc_cnt_nxt;
  logic [32-1:0] reg_fresh_cnt;
  logic [32-1:0] w_fresh_cnt_nxt;
  logic [32-1:0] reg_cert_cnt;
  logic [32-1:0] w_cert_cnt_nxt;
  logic [32-1:0] reg_health_cnt;
  logic [32-1:0] w_health_cnt_nxt;
  logic [32-1:0] reg_lost;
  logic [32-1:0] w_lost_nxt;
  logic [8-1:0] reg_reason;
  logic [8-1:0] w_reason_nxt;
  logic [32-1:0] reg_cycles;
  logic [32-1:0] w_cycles_nxt;
  logic w_wr;
  logic w_bad;
  logic w_active;
  logic [31:0] w_mask;
  logic [31:0] w_rd_data;
  logic [1:0] w_rd_resp;
  logic [7:0] w_irq_set;
  logic [7:0] w_reason;
  logic [7:0] w_commit;
  logic [2:0] w_mode;
  logic w_healthy;

  // Single slots accept AW and W independently; B backpressure blocks only writes.
  assign o_axi_awready = i_rst_n_core && !reg_aw_full && !reg_bvalid && i_axi_wvalid;
  assign o_axi_wready = i_rst_n_core && !reg_w_full && !reg_bvalid;
  assign o_axi_arready = i_rst_n_core && !reg_rvalid;
  assign o_axi_bvalid = i_rst_n_core && reg_bvalid;
  assign o_axi_bresp = o_axi_bvalid ? reg_bresp : 2'b00;
  assign o_axi_rvalid = i_rst_n_core && reg_rvalid;
  assign o_axi_rresp = o_axi_rvalid ? reg_rresp : 2'b00;
  assign o_axi_rdata = o_axi_rvalid ? reg_rdata : '0;
  assign o_config_data = {reg_config_valid, reg_en, reg_soft_rst, reg_bist_start};
  assign o_int_irq = |(reg_irq_en & reg_irq_sts);
  assign w_wr = reg_aw_full && reg_w_full && !reg_bvalid;
  assign w_active = reg_en || reg_sts[0] || (i_sts_valid && i_sts_data[76]);
  assign w_reason = i_sts_data[113:106];
  assign w_mode = i_sts_data[105:103];
  assign w_commit = i_sts_data[85:78];
  assign w_healthy = i_sts_data[73];
  assign w_irq_set = i_sts_valid ? i_sts_data[7:0] : 8'h00;

  // Enabled byte lanes only; no arithmetic divider or multiplier is inferred.
  always_comb begin : p_com_mask
    w_mask = '0;
    for (int idx = 0; idx < 4; idx++) begin
      w_mask[idx*LPARA_BYTE_W +: LPARA_BYTE_W] = {LPARA_BYTE_W{reg_wstrb[idx]}};
    end
  end

  // Read captures the pre-edge snapshot, including on a simultaneous status/write edge.
  always_comb begin : p_com_rd
    w_rd_data = '0;
    w_rd_resp = 2'b00;
    case (32'(i_axi_araddr))
      LPARA_CTRL_ADDR: w_rd_data = {31'b0,reg_en};
      LPARA_STS_ADDR: w_rd_data = reg_sts;
      LPARA_IRQ_EN_ADDR: w_rd_data = {24'b0,reg_irq_en};
      LPARA_IRQ_STS_ADDR: w_rd_data = {24'b0,reg_irq_sts};
      LPARA_FAULT_COUNT_ADDR: w_rd_data = reg_fault_cnt;
      LPARA_CRC_COUNT_ADDR: w_rd_data = reg_crc_cnt;
      LPARA_FRESH_COUNT_ADDR: w_rd_data = reg_fresh_cnt;
      LPARA_CERT_COUNT_ADDR: w_rd_data = reg_cert_cnt;
      LPARA_HEALTH_COUNT_ADDR: w_rd_data = reg_health_cnt;
      LPARA_LOG_LOST_ADDR: w_rd_data = reg_lost;
      LPARA_LAST_REASON_ADDR: w_rd_data = {24'b0,reg_reason};
      LPARA_DECISION_CYCLES_ADDR: w_rd_data = reg_cycles;
      LPARA_PROFILE_COUNT_ADDR: w_rd_data = LPARA_PROFILE_COUNT_RST;
      LPARA_PROFILE_LIMIT_ADDR: w_rd_data = LPARA_PROFILE_LIMIT_RST;
      LPARA_PROFILE_MASK_ADDR: w_rd_data = LPARA_PROFILE_MASK_RST;
      LPARA_FRESH_TIMEOUT_US_ADDR: w_rd_data = LPARA_FRESH_TIMEOUT_US_RST;
      LPARA_ODD_V_MAX_ADDR: w_rd_data = LPARA_ODD_V_MAX_RST;
      LPARA_ACK_TIMEOUT_US_ADDR: w_rd_data = LPARA_ACK_TIMEOUT_US_RST;
      LPARA_LEASE_MAX_US_ADDR: w_rd_data = LPARA_LEASE_MAX_US_RST;
      LPARA_CONFIG_VALID_ADDR: w_rd_data = {31'b0,reg_config_valid};
      LPARA_PROFILE_0_DECEL_ADDR: w_rd_data = LPARA_PROFILE_0_DECEL_RST;
      LPARA_PROFILE_0_JERK_ADDR: w_rd_data = LPARA_PROFILE_0_JERK_RST;
      LPARA_PROFILE_1_DECEL_ADDR: w_rd_data = LPARA_PROFILE_1_DECEL_RST;
      LPARA_PROFILE_1_JERK_ADDR: w_rd_data = LPARA_PROFILE_1_JERK_RST;
      LPARA_PROFILE_2_DECEL_ADDR: w_rd_data = LPARA_PROFILE_2_DECEL_RST;
      LPARA_PROFILE_2_JERK_ADDR: w_rd_data = LPARA_PROFILE_2_JERK_RST;
      LPARA_PROFILE_3_DECEL_ADDR: w_rd_data = LPARA_PROFILE_3_DECEL_RST;
      LPARA_PROFILE_3_JERK_ADDR: w_rd_data = LPARA_PROFILE_3_JERK_RST;
      LPARA_PROFILE_4_DECEL_ADDR: w_rd_data = LPARA_PROFILE_4_DECEL_RST;
      LPARA_PROFILE_4_JERK_ADDR: w_rd_data = LPARA_PROFILE_4_JERK_RST;
      LPARA_PROFILE_5_DECEL_ADDR: w_rd_data = LPARA_PROFILE_5_DECEL_RST;
      LPARA_PROFILE_5_JERK_ADDR: w_rd_data = LPARA_PROFILE_5_JERK_RST;
      LPARA_PROFILE_6_DECEL_ADDR: w_rd_data = LPARA_PROFILE_6_DECEL_RST;
      LPARA_PROFILE_6_JERK_ADDR: w_rd_data = LPARA_PROFILE_6_JERK_RST;
      LPARA_PROFILE_7_DECEL_ADDR: w_rd_data = LPARA_PROFILE_7_DECEL_RST;
      LPARA_PROFILE_7_JERK_ADDR: w_rd_data = LPARA_PROFILE_7_JERK_RST;
      LPARA_PROFILE_8_DECEL_ADDR: w_rd_data = LPARA_PROFILE_8_DECEL_RST;
      LPARA_PROFILE_8_JERK_ADDR: w_rd_data = LPARA_PROFILE_8_JERK_RST;
      LPARA_PROFILE_9_DECEL_ADDR: w_rd_data = LPARA_PROFILE_9_DECEL_RST;
      LPARA_PROFILE_9_JERK_ADDR: w_rd_data = LPARA_PROFILE_9_JERK_RST;
      LPARA_PROFILE_10_DECEL_ADDR: w_rd_data = LPARA_PROFILE_10_DECEL_RST;
      LPARA_PROFILE_10_JERK_ADDR: w_rd_data = LPARA_PROFILE_10_JERK_RST;
      LPARA_PROFILE_11_DECEL_ADDR: w_rd_data = LPARA_PROFILE_11_DECEL_RST;
      LPARA_PROFILE_11_JERK_ADDR: w_rd_data = LPARA_PROFILE_11_JERK_RST;
      LPARA_PROFILE_12_DECEL_ADDR: w_rd_data = LPARA_PROFILE_12_DECEL_RST;
      LPARA_PROFILE_12_JERK_ADDR: w_rd_data = LPARA_PROFILE_12_JERK_RST;
      LPARA_PROFILE_13_DECEL_ADDR: w_rd_data = LPARA_PROFILE_13_DECEL_RST;
      LPARA_PROFILE_13_JERK_ADDR: w_rd_data = LPARA_PROFILE_13_JERK_RST;
      LPARA_PROFILE_14_DECEL_ADDR: w_rd_data = LPARA_PROFILE_14_DECEL_RST;
      LPARA_PROFILE_14_JERK_ADDR: w_rd_data = LPARA_PROFILE_14_JERK_RST;
      LPARA_PROFILE_15_DECEL_ADDR: w_rd_data = LPARA_PROFILE_15_DECEL_RST;
      LPARA_PROFILE_15_JERK_ADDR: w_rd_data = LPARA_PROFILE_15_JERK_RST;
      default: w_rd_resp = 2'b10;
    endcase
  end

  // Slot next state and register writes; a rejected access never modifies its target.
  always_comb begin : p_com_nxt
    w_aw_full_nxt = reg_aw_full;
    w_w_full_nxt = reg_w_full;
    w_awaddr_nxt = reg_awaddr;
    w_wdata_nxt = reg_wdata;
    w_wstrb_nxt = reg_wstrb;
    w_bvalid_nxt = reg_bvalid;
    w_bresp_nxt = reg_bresp;
    w_rvalid_nxt = reg_rvalid;
    w_rresp_nxt = reg_rresp;
    w_rdata_nxt = reg_rdata;
    w_en_nxt = reg_en;
    w_config_valid_nxt = reg_config_valid;
    w_bist_wait_nxt = reg_bist_wait;
    w_soft_rst_nxt = reg_soft_rst;
    w_bist_start_nxt = reg_bist_start;
    w_irq_en_nxt = reg_irq_en;
    w_irq_sts_nxt = reg_irq_sts;
    w_sts_nxt = reg_sts;
    w_fault_cnt_nxt = reg_fault_cnt;
    w_crc_cnt_nxt = reg_crc_cnt;
    w_fresh_cnt_nxt = reg_fresh_cnt;
    w_cert_cnt_nxt = reg_cert_cnt;
    w_health_cnt_nxt = reg_health_cnt;
    w_lost_nxt = reg_lost;
    w_reason_nxt = reg_reason;
    w_cycles_nxt = reg_cycles;
    w_bad = 1'b0;
    w_soft_rst_nxt = 1'b0;
    w_bist_start_nxt = 1'b0;
    if (o_axi_awready && i_axi_awvalid) begin
      w_aw_full_nxt = 1'b1;
      w_awaddr_nxt = i_axi_awaddr;
    end
    if (o_axi_wready && i_axi_wvalid) begin
      w_w_full_nxt = 1'b1;
      w_wdata_nxt = i_axi_wdata;
      w_wstrb_nxt = i_axi_wstrb;
    end
    if (o_axi_bvalid && i_axi_bready) w_bvalid_nxt = 1'b0;
    if (o_axi_rvalid && i_axi_rready) w_rvalid_nxt = 1'b0;
    if (o_axi_arready && i_axi_arvalid) begin
      w_rvalid_nxt = 1'b1;
      w_rdata_nxt = w_rd_data;
      w_rresp_nxt = w_rd_resp;
    end
    if (i_sts_valid) begin
      w_sts_nxt = '0;
      w_sts_nxt[0] = i_sts_data[76];
      w_sts_nxt[1] = w_healthy;
      w_sts_nxt[2] = !w_healthy || (w_mode == 3'(LPARA_MODE_L3)) || i_sts_data[86];
      w_sts_nxt[5:3] = w_mode;
      w_sts_nxt[6] = i_sts_data[75];
      w_sts_nxt[7] = i_sts_data[74];
      w_sts_nxt[8] = i_sts_data[72];
      w_sts_nxt[17:16] = i_sts_data[88:87];
      w_lost_nxt = i_sts_data[39:8];
      if (reg_sts[1] && !w_healthy && (reg_health_cnt != 32'hffffffff))
        w_health_cnt_nxt = 32'(reg_health_cnt + 32'd1);
      if (i_sts_data[7]) begin
        w_reason_nxt = w_reason;
        w_cycles_nxt = i_sts_data[71:40];
        if (!i_sts_data[114] && (reg_fault_cnt != 32'hffffffff))
          w_fault_cnt_nxt = 32'(reg_fault_cnt + 32'd1);
        if ((w_reason == 8'(LPARA_REASON_CRC)) && (reg_crc_cnt != 32'hffffffff))
          w_crc_cnt_nxt = 32'(reg_crc_cnt + 32'd1);
        case (w_reason)
          8'(LPARA_REASON_CLK),8'(LPARA_REASON_SAMPLE),8'(LPARA_REASON_EGO),8'(LPARA_REASON_FRESH),8'(LPARA_REASON_FREEZE): begin
            if (reg_fresh_cnt != 32'hffffffff)
              w_fresh_cnt_nxt = 32'(reg_fresh_cnt + 32'd1);
          end
          default: begin end
        endcase
        case (w_commit)
          8'(LPARA_COMMIT_OK),8'(LPARA_COMMIT_DONE),8'(LPARA_COMMIT_PENDING),8'(LPARA_COMMIT_NONE): begin end
          default: begin
            if (reg_cert_cnt != 32'hffffffff)
              w_cert_cnt_nxt = 32'(reg_cert_cnt + 32'd1);
          end
        endcase
      end
      if (reg_bist_wait && i_sts_data[72] && w_healthy) begin
        w_config_valid_nxt = 1'b1;
        w_bist_wait_nxt = 1'b0;
      end
    end
    if (w_wr) begin
      w_aw_full_nxt = 1'b0;
      w_w_full_nxt = 1'b0;
      w_bvalid_nxt = 1'b1;
      w_bresp_nxt = 2'b00;
      case (32'(reg_awaddr))
        LPARA_CTRL_ADDR: begin
          if (reg_wstrb[0]) begin
            if ((reg_wdata[2] && (w_active || reg_wdata[1] || reg_wdata[0])) ||
                (reg_wdata[1] && (w_active || reg_wdata[0])) ||
                (reg_wdata[0] && (w_active || !reg_config_valid))) begin
              w_bad = 1'b1;
            end else begin
              w_en_nxt = reg_wdata[0];
              w_soft_rst_nxt = reg_wdata[1];
              w_bist_start_nxt = reg_wdata[2];
              if (reg_wdata[2] || reg_wdata[1]) begin
                w_config_valid_nxt = 1'b0;
                w_bist_wait_nxt = reg_wdata[2];
                w_sts_nxt[8] = 1'b0;
              end
            end
          end
        end
        LPARA_IRQ_EN_ADDR: begin
          if (reg_wstrb[0]) w_irq_en_nxt = reg_wdata[7:0];
        end
        LPARA_IRQ_STS_ADDR: begin
          if (reg_wstrb[0]) w_irq_sts_nxt = reg_irq_sts & ~reg_wdata[7:0];
        end
        LPARA_PROFILE_COUNT_ADDR: begin
          if (|(w_mask & 32'h000000ff)) begin
            if (w_active ||
                ((reg_wdata & w_mask & 32'h000000ff) != (LPARA_PROFILE_COUNT_RST & w_mask)))
              w_bad = 1'b1;
            w_config_valid_nxt = 1'b0;
            w_bist_wait_nxt = 1'b0;
          end
        end
        LPARA_PROFILE_LIMIT_ADDR: begin
          if (|(w_mask & 32'h000000ff)) begin
            if (w_active ||
                ((reg_wdata & w_mask & 32'h000000ff) != (LPARA_PROFILE_LIMIT_RST & w_mask)))
              w_bad = 1'b1;
            w_config_valid_nxt = 1'b0;
            w_bist_wait_nxt = 1'b0;
          end
        end
        LPARA_PROFILE_MASK_ADDR: begin
          if (|(w_mask & 32'h0000ffff)) begin
            if (w_active ||
                ((reg_wdata & w_mask & 32'h0000ffff) != (LPARA_PROFILE_MASK_RST & w_mask)))
              w_bad = 1'b1;
            w_config_valid_nxt = 1'b0;
            w_bist_wait_nxt = 1'b0;
          end
        end
        LPARA_FRESH_TIMEOUT_US_ADDR: begin
          if (|(w_mask & 32'hffffffff)) begin
            if (w_active ||
                ((reg_wdata & w_mask & 32'hffffffff) != (LPARA_FRESH_TIMEOUT_US_RST & w_mask)))
              w_bad = 1'b1;
            w_config_valid_nxt = 1'b0;
            w_bist_wait_nxt = 1'b0;
          end
        end
        LPARA_ODD_V_MAX_ADDR: begin
          if (|(w_mask & 32'hffffffff)) begin
            if (w_active ||
                ((reg_wdata & w_mask & 32'hffffffff) != (LPARA_ODD_V_MAX_RST & w_mask)))
              w_bad = 1'b1;
            w_config_valid_nxt = 1'b0;
            w_bist_wait_nxt = 1'b0;
          end
        end
        default: w_bad = 1'b1;
      endcase
    end
    if (w_wr && w_bad) w_bresp_nxt = 2'b10;
    if (o_axi_arready && i_axi_arvalid && (w_rd_resp != 2'b00)) w_bad = 1'b1;
    if (w_bad) begin

      w_config_valid_nxt = 1'b0;
      w_bist_wait_nxt = 1'b0;
    end
    w_irq_sts_nxt = w_irq_sts_nxt | w_irq_set | (w_bad ? 8'(LPARA_CONFIG_IRQ) : 8'h00);
  end

  // Asynchronous invalidation; next-state is sampled only on the rising core edge.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_regs
    if (!i_rst_n_core) begin
      reg_aw_full <= '0;
      reg_w_full <= '0;
      reg_awaddr <= '0;
      reg_wdata <= '0;
      reg_wstrb <= '0;
      reg_bvalid <= '0;
      reg_bresp <= '0;
      reg_rvalid <= '0;
      reg_rresp <= '0;
      reg_rdata <= '0;
      reg_en <= '0;
      reg_config_valid <= '0;
      reg_bist_wait <= '0;
      reg_soft_rst <= '0;
      reg_bist_start <= '0;
      reg_irq_en <= '0;
      reg_irq_sts <= '0;
      reg_sts <= LPARA_STS_RST;
      reg_fault_cnt <= '0;
      reg_crc_cnt <= '0;
      reg_fresh_cnt <= '0;
      reg_cert_cnt <= '0;
      reg_health_cnt <= '0;
      reg_lost <= '0;
      reg_reason <= '0;
      reg_cycles <= '0;
    end else begin
      reg_aw_full <= w_aw_full_nxt;
      reg_w_full <= w_w_full_nxt;
      reg_awaddr <= w_awaddr_nxt;
      reg_wdata <= w_wdata_nxt;
      reg_wstrb <= w_wstrb_nxt;
      reg_bvalid <= w_bvalid_nxt;
      reg_bresp <= w_bresp_nxt;
      reg_rvalid <= w_rvalid_nxt;
      reg_rresp <= w_rresp_nxt;
      reg_rdata <= w_rdata_nxt;
      reg_en <= w_en_nxt;
      reg_config_valid <= w_config_valid_nxt;
      reg_bist_wait <= w_bist_wait_nxt;
      reg_soft_rst <= w_soft_rst_nxt;
      reg_bist_start <= w_bist_start_nxt;
      reg_irq_en <= w_irq_en_nxt;
      reg_irq_sts <= w_irq_sts_nxt;
      reg_sts <= w_sts_nxt;
      reg_fault_cnt <= w_fault_cnt_nxt;
      reg_crc_cnt <= w_crc_cnt_nxt;
      reg_fresh_cnt <= w_fresh_cnt_nxt;
      reg_cert_cnt <= w_cert_cnt_nxt;
      reg_health_cnt <= w_health_cnt_nxt;
      reg_lost <= w_lost_nxt;
      reg_reason <= w_reason_nxt;
      reg_cycles <= w_cycles_nxt;
    end
  end
endmodule
`default_nettype wire
