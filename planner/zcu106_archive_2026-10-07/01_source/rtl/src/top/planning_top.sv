//==============================================================================
// File: planning_top.sv
// Description: Top-level Planning Accelerator — VLA-HMAO W4A8 Architecture
//
//   Implements the 7-phase sequencer FSM (spec §1.2) and wires together:
//     - weight_loader (AXI HP0 DMA master)
//     - world_model_parser (reads BRAMs, emits tokens)
//     - feature_projector (W_proj + pos_emb → ping-pong A)
//     - bert_encoder_layer ×4 (Pre-LN BERT, W4A8)
//     - cls_int8_to_fp32_convert (CLS dequantize)
//     - gru_waypoint_decoder (4-step GRU → waypoints)
//     - trajectory_sanity_checker (NaN/Inf + bounds → HMAO)
//     - AXI-Lite CSR (spec §17)
//
//   AXI HP0 passes through to weight_loader (READ-ONLY, 128-bit).
//   Write channels tied off inside this module.
//
// Spec: VLA_HMAO_SPEC_v15_5.txt §1.2, §15.1, §15.2, §17
// Author: VLA-HMAO Team
// Date:   2026-03-25
// Status: TOP-LEVEL SKELETON — sub-modules to be developed iteratively
//==============================================================================

`timescale 1ns / 1ps

module planning_top
  import planning_pkg::*;
(
  input  logic        clk,        // 200 MHz PL clock
  input  logic        rst_n,      // Active-low synchronous (min 16 cy)

  //── AXI-Lite CSR (PS → PL, 12-bit addr, 32-bit data) ────────────────────────
  input  logic [11:0] axil_awaddr,
  input  logic        axil_awvalid,
  output logic        axil_awready,
  input  logic [31:0] axil_wdata,
  input  logic  [3:0] axil_wstrb,
  input  logic        axil_wvalid,
  output logic        axil_wready,
  output logic  [1:0] axil_bresp,
  output logic        axil_bvalid,
  input  logic        axil_bready,
  input  logic [11:0] axil_araddr,
  input  logic        axil_arvalid,
  output logic        axil_arready,
  output logic [31:0] axil_rdata,
  output logic  [1:0] axil_rresp,
  output logic        axil_rvalid,
  input  logic        axil_rready,

  //── AXI HP0 DMA — READ ONLY (128-bit) ────────────────────────────────────────
  output logic  [5:0] m_axi_arid,
  output logic [31:0] m_axi_araddr,
  output logic  [7:0] m_axi_arlen,
  output logic  [2:0] m_axi_arsize,
  output logic  [1:0] m_axi_arburst,
  output logic  [1:0] m_axi_arlock,
  output logic  [3:0] m_axi_arcache,
  output logic  [2:0] m_axi_arprot,
  output logic  [3:0] m_axi_arqos,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic  [5:0] m_axi_rid,
  input  logic [127:0] m_axi_rdata,
  input  logic  [1:0] m_axi_rresp,
  input  logic        m_axi_rlast,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  //── HMAO output ───────────────────────────────────────────────────────────────
  output fp32_t       waypoint_x [NUM_WAYPOINTS-1:0],
  output fp32_t       waypoint_y [NUM_WAYPOINTS-1:0],
  output logic        waypoints_valid,
  output logic        waypoints_sanity_pass,
  input  logic        hmao_clk,
  input  logic        hmao_rst_n,

  //── Interrupt to PS ───────────────────────────────────────────────────────────
  output logic        done_irq,
  output logic        wload_timeout_err
);

  //============================================================================
  // AXI HP0 — tie off write channels (READ-ONLY per spec §15.2)
  //============================================================================
  // (Write channel signals not in port list — tied off at instantiation point)
  assign m_axi_arlock  = 2'b00;
  assign m_axi_arcache = 4'b0011;
  assign m_axi_arprot  = 3'b000;
  assign m_axi_arqos   = 4'b0000;

  //============================================================================
  // Phase sequencer FSM states (spec §1.2)
  //============================================================================
  typedef enum logic [3:0] {
    PH_IDLE         = 4'd0,
    PH_WM_FETCH     = 4'd1,   // Phase 1: WM_FETCH
    PH_PROJ         = 4'd2,   // Phase 2: PROJ_PHASE
    PH_BERT         = 4'd3,   // Phase 3: BERT_PHASE (sub-states per layer)
    PH_CLS_CONV     = 4'd4,   // Phase 4: CLS_CONV
    PH_GRU          = 4'd5,   // Phase 5: GRU_PHASE
    PH_OUTPUT       = 4'd6,   // Phase 6: OUTPUT
    PH_DONE_PULSE   = 4'd7,   // Phase 7: DONE_PULSE
    PH_ERROR        = 4'd15   // Error halt
  } phase_t;

  phase_t phase;

  // BERT sub-states per layer
  typedef enum logic [1:0] {
    BERT_SUB_WLOAD      = 2'd0,
    BERT_SUB_WAIT_WLOAD = 2'd1,
    BERT_SUB_COMPUTE    = 2'd2,
    BERT_SUB_DONE       = 2'd3
  } bert_sub_t;

  bert_sub_t  bert_sub;
  logic [1:0] bert_layer_idx;  // 0..3

  //============================================================================
  // CSR Registers (spec §17)
  //============================================================================

  // 0x000 CTRL
  logic        csr_start_trigger;  // [0] w1s, self-clearing
  logic        csr_soft_reset;     // [1] w1s, self-clearing
  logic        csr_irq_clear;      // [2] w1s, self-clearing

  // 0x004 STATUS (read-only)
  // 0x008 WM_SEL
  logic        csr_wm_sel;         // [0]: 0=WM_A, 1=WM_B

  // 0x010–0x02C WP0..WP3 X,Y (read-only, written by GRU decoder)
  fp32_t       csr_wp_x [NUM_WAYPOINTS-1:0];
  fp32_t       csr_wp_y [NUM_WAYPOINTS-1:0];

  // 0x030 IRQ_STATUS
  logic        csr_done_irq_r;
  logic        csr_wload_timeout_irq_r;
  logic        csr_nan_inf_irq_r;

  // 0x034 IRQ_ENABLE
  logic        csr_done_irq_en;
  logic        csr_wload_timeout_irq_en;
  logic        csr_nan_inf_irq_en;

  // 0x040–0x05C CTX_SCALE / CTX_ZP per layer [V17-S03]
  fp32_t       csr_ctx_scale [NUM_LAYERS-1:0];
  logic  [7:0] csr_ctx_zp    [NUM_LAYERS-1:0];

  // 0x060–0x064 TARGET_X/Y
  fp32_t       csr_target_x;
  fp32_t       csr_target_y;

  //============================================================================
  // Internal control signals
  //============================================================================
  logic        static_boot_start_r; // one-shot at power-on [V16-M04]
  logic        static_boot_start_pend;
  logic        static_boot_sent;    // tracks that we've sent boot pulse
  logic        gru_wload_sent;      // one-shot GRU static-load request
  logic        static_boot_done;
  logic        gru_weights_loaded;
  logic        axil_rvalid_hold;

  // WM_FETCH control [V17-C01]
  logic        wm_fetch_start;
  logic        wm_fetch_start_pend;
  logic [31:0] wm_ddr_base;
  logic        wm_fetch_done;

  // Parse control [v15.3-C01]
  logic        parse_start;
  logic        parse_start_pend;
  logic        parse_done;
  logic        parse_done_seen;     // [E2E 02/10] parser da xong khung nay (giu den parse_start ke)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)           parse_done_seen <= 1'b0;
    else if (parse_start) parse_done_seen <= 1'b0;
    else if (parse_done)  parse_done_seen <= 1'b1;
  end

  // pos_emb control [v15.4-M04]
  logic        posemb_dma_start;
  logic        posemb_dma_start_pend;
  logic        posemb_dma_done;
  logic        posemb_ready;      // level, sticky, cleared at PROJ_PHASE entry

  // BERT weight load
  logic        bert_wload_start;
  logic        wl_bert_wload_start;
  logic [1:0]  bert_wload_layer_s;
  logic        wl_idle_sanitize;
  logic        bert_wload_done;

  // GRU weight load
  logic        gru_wload_start;
  logic        gru_wload_start_pend;
  logic        gru_wload_done;

  // Sub-module done signals (stubs until sub-modules developed)
  logic        proj_done;
  logic        bert_layer_done;
  logic        cls_conv_done;
  logic        gru_done;
  logic        sanity_done;
  logic        sanity_pass;

  // Wload timeout counter
  logic [19:0] wload_timeout_cnt;
  localparam int TIMEOUT_CY = 500_000;
  localparam logic [19:0] TIMEOUT_CY_20 = 20'd500_000;

  //============================================================================
  // Phase transition tracking (for start-pulse generation)
  //============================================================================
  phase_t      phase_prev;
  logic        bert_prev_sub_wait;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase_prev          <= PH_IDLE;
      bert_prev_sub_wait  <= 1'b0;
    end else begin
      phase_prev         <= phase;
      bert_prev_sub_wait <= (bert_sub == BERT_SUB_WAIT_WLOAD);
    end
  end

  // 1-cycle start pulses derived from phase transitions
  logic fp_valid_in;     // feature_projector start
  logic bert_layer_start;
  logic cls_conv_start;
  logic gru_start_pulse;
  logic sanity_start;

  assign fp_valid_in      = (phase == PH_PROJ)    && (phase_prev != PH_PROJ);
  assign bert_layer_start = (bert_sub == BERT_SUB_COMPUTE) && bert_prev_sub_wait;
  assign cls_conv_start   = (phase == PH_CLS_CONV) && (phase_prev != PH_CLS_CONV);
  assign gru_start_pulse  = (phase == PH_GRU)      && (phase_prev != PH_GRU);
  assign sanity_start     = (phase == PH_OUTPUT)   && (phase_prev != PH_OUTPUT);
  assign bert_wload_start = (phase == PH_BERT) &&
                            ((bert_sub == BERT_SUB_WLOAD) || (bert_sub == BERT_SUB_WAIT_WLOAD));
  assign wl_bert_wload_start = bert_wload_start;
  assign bert_wload_layer_s = bert_layer_idx;
  // [IMPL 150 MHz, 04/10] chot 1 chu ky (duong phase -> CE trong weight_loader: -0,077 ns)
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) wl_idle_sanitize <= 1'b0;
    else        wl_idle_sanitize <= (phase == PH_PROJ) && posemb_ready && !proj_done;

  // Phase activity qualifiers for URAM arbiter
  logic bert_active, gru_active;
  assign bert_active = (phase == PH_BERT) && (bert_sub == BERT_SUB_COMPUTE);
  assign gru_active  = (phase == PH_GRU);

  //============================================================================
  // Internal Signals — weight_loader BRAM/URAM write buses
  //============================================================================
  logic [31:0] wl_m_axi_araddr;
  logic  [7:0] wl_m_axi_arlen;
  logic  [2:0] wl_m_axi_arsize;
  logic  [1:0] wl_m_axi_arburst;
  logic  [5:0] wl_m_axi_arid;
  logic        wl_m_axi_arvalid;
  logic        wl_m_axi_rready;

  logic [31:0] bert_dma_araddr;
  logic  [7:0] bert_dma_arlen;
  logic  [2:0] bert_dma_arsize;
  logic  [1:0] bert_dma_arburst;
  logic  [5:0] bert_dma_arid;
  logic        bert_dma_arvalid;
  logic        bert_dma_rready;
  logic        bert_dma_active;

  logic [18:0] wl_main_uram_addr;
  logic [63:0] wl_main_uram_wdata;
  logic        wl_main_uram_we;
  logic        wl_main_copy_active;

  logic [18:0] bert_dma_uram_addr;
  logic [63:0] bert_dma_uram_wdata;
  logic        bert_dma_uram_we;

  logic [18:0] wl_uram_addr;
  logic [63:0] wl_uram_wdata;
  logic        wl_uram_we;
  logic        uram_copy_active;

  logic [13:0] scale_bram_wr_addr;
  logic [31:0] scale_bram_wr_data;
  logic        scale_bram_wr_en;

  logic [14:0] bias_bram_wr_addr;
  logic [31:0] bias_bram_wr_data;
  logic        bias_bram_wr_en;

  logic [12:0] ln_bram_wr_addr;
  logic [31:0] ln_bram_wr_data;
  logic        ln_bram_wr_en;

  logic  [1:0] hdr_bram_wr_addr;
  logic [31:0] hdr_bram_wr_data;
  logic        hdr_bram_wr_en;

  logic [11:0] obj_bram_wr_addr;
  logic [31:0] obj_bram_wr_data;
  logic        obj_bram_wr_en;

  logic  [9:0] lane_bram_wr_addr;
  logic [31:0] lane_bram_wr_data;
  logic        lane_bram_wr_en;

  logic  [7:0] wm_num_objects;
  logic  [4:0] wm_num_lanes;

  logic [10:0] wout_bram_wr_addr;
  logic [31:0] wout_bram_wr_data;
  logic        wout_bram_wr_en;

  logic [10:0] gru_bias_bram_wr_addr;
  logic [31:0] gru_bias_bram_wr_data;
  logic        gru_bias_bram_wr_en;

  logic  [2:0] gru_scale_lut_sel;
  logic  [8:0] gru_scale_lut_addr;
  logic [15:0] gru_scale_lut_wdata;
  logic        gru_scale_lut_we;

  logic [13:0] posemb_bram_wr_addr;
  logic [63:0] posemb_bram_wr_data;
  logic        posemb_bram_wr_en;

  wire use_bert_dma = (phase == PH_BERT);

  assign m_axi_araddr  = use_bert_dma ? bert_dma_araddr  : wl_m_axi_araddr;
  assign m_axi_arlen   = use_bert_dma ? bert_dma_arlen   : wl_m_axi_arlen;
  assign m_axi_arsize  = use_bert_dma ? bert_dma_arsize  : wl_m_axi_arsize;
  assign m_axi_arburst = use_bert_dma ? bert_dma_arburst : wl_m_axi_arburst;
  assign m_axi_arid    = use_bert_dma ? bert_dma_arid    : wl_m_axi_arid;
  assign m_axi_arvalid = use_bert_dma ? bert_dma_arvalid : wl_m_axi_arvalid;
  assign m_axi_rready  = use_bert_dma ? bert_dma_rready  : wl_m_axi_rready;

  assign wl_uram_addr     = use_bert_dma ? bert_dma_uram_addr  : wl_main_uram_addr;
  assign wl_uram_wdata    = use_bert_dma ? bert_dma_uram_wdata : wl_main_uram_wdata;
  assign wl_uram_we       = use_bert_dma ? bert_dma_uram_we    : wl_main_uram_we;
  assign uram_copy_active = use_bert_dma ? bert_dma_active     : wl_main_copy_active;

  //============================================================================
  // Internal Signals — BRAM read buses
  //============================================================================
  // Scale BRAM
  logic [13:0] scale_rd_addr;
  logic [31:0] scale_rd_data;
  logic [13:0] cls_scale_rd_addr;
  logic [31:0] cls_scale_rd_data;

  // Bias BRAM
  logic [14:0] bias_rd_addr;
  logic [31:0] bias_rd_data;

  // LN BRAM
  logic [12:0] ln_rd_addr;
  fp32_t       ln_rd_data;

  // HDR/OBJ/LANE BRAMs (world_model_parser reads)
  logic  [1:0] hdr_rd_addr;
  logic [31:0] hdr_rd_data;
  logic        hdr_rd_en;
  logic [11:0] obj_rd_addr;
  logic [31:0] obj_rd_data;
  logic        obj_rd_en;
  logic  [9:0] lane_rd_addr;
  logic [31:0] lane_rd_data;
  logic        lane_rd_en;

  // Pos-emb BRAM (feature_projector reads)
  logic [13:0] posemb_rd_addr;
  logic [63:0] posemb_rd_data;
  logic        posemb_rd_en;

  // Proj BRAM (feature_projector reads W_proj weights)
  logic [12:0] proj_bram_rd_addr;
  logic [63:0] proj_bram_rd_data;
  logic        proj_bram_rd_en;

  // W_out BRAM (gru reads)
  logic [10:0] wout_bram_addr;
  logic [31:0] wout_bram_rdata;

  // GRU bias BRAM
  logic [10:0] gru_bias_addr;
  logic [31:0] gru_bias_rdata;

  // GRU scratch is now internal to gru_waypoint_decoder (32-bank LUTRAM)

  // wp_proj BRAM (1536×32b: W[:,0] W[:,1] b_wp — loaded from DDR at 0x018A8000)
  logic [10:0] wp_proj_bram_addr;
  logic [31:0] wp_proj_bram_rdata;
  logic        wp_proj_bram_en;

  //============================================================================
  // Internal Signals — Ping-pong A/B
  //============================================================================
  // Port A (write) of each pp
  logic [14:0] pp_a_addra, pp_b_addra;
  logic  [7:0] pp_a_dina,  pp_b_dina;
  logic        pp_a_wea,   pp_b_wea;
  logic        pp_a_ena,   pp_b_ena;

  // Port B (read) of each pp
  logic [14:0] pp_a_addrb, pp_b_addrb;
  logic  [7:0] pp_a_doutb, pp_b_doutb;
  logic        pp_a_enb,   pp_b_enb;

  // feature_projector pp write
  logic [14:0] fp_pp_wr_addr;
  logic  [7:0] fp_pp_wr_data;
  logic        fp_pp_wr_en;

  // bert_encoder_layer pp signals
  logic [14:0] bert_pp_rd_addr;
  logic  [7:0] bert_pp_rd_data;
  logic        bert_pp_rd_sel;
  logic        bert_pp_rd_en;
  logic [14:0] bert_pp_wr_addr;
  logic  [7:0] bert_pp_wr_data;
  logic        bert_pp_wr_en;
  logic        bert_pp_wr_sel;
  logic [14:0] bert_pp_rd_addr_raw;
  logic        bert_pp_rd_sel_raw;
  logic        bert_pp_rd_en_raw;
  logic [14:0] bert_pp_wr_addr_raw;
  logic  [7:0] bert_pp_wr_data_raw;
  logic        bert_pp_wr_en_raw;
  logic        bert_pp_wr_sel_raw;

  // cls_int8_to_fp32 pp read
  logic [14:0] cls_pp_rd_addr;
  logic  [7:0] cls_pp_rd_data;
  logic        cls_pp_rd_en;

  // Ping-pong mux: write port A of pp memories
  // pp_A write: feature_projector (PH_PROJ) or bert (PH_BERT, wr_sel=0)

  //============================================================================
  // Internal Signals — LN1q and QKT scratch (bert_encoder_layer TDP)
  //============================================================================
  logic [14:0] ln1q_wr_addr, ln1q_rd_addr;
  logic  [7:0] ln1q_wr_data, ln1q_rd_data;
  logic        ln1q_wr_en,   ln1q_rd_en;

  // RESOURCE FIX (this round): qkt_wr_*/qkt_rd_* signals removed along with
  // u_qkt_scratch (see that instance's own removal comment).

  //============================================================================
  // Internal Signals — CLS buffer, GRU waypoints
  //============================================================================
  logic  [8:0] cls_buf_wr_addr;
  logic [31:0] cls_buf_wr_data;
  logic        cls_buf_wr_en;
  logic  [8:0] cls_buf_rd_addr;
  fp32_t       cls_buf_rd_data;
  logic        cls_buf_rd_en;

  fp32_t       gru_wp_x [NUM_WAYPOINTS-1:0];
  fp32_t       gru_wp_y [NUM_WAYPOINTS-1:0];
  logic        gru_wp_valid;
  fp32_t       gru_wp_x_raw [NUM_WAYPOINTS-1:0];
  fp32_t       gru_wp_y_raw [NUM_WAYPOINTS-1:0];
  logic        gru_wp_valid_raw;
  logic        gru_done_raw;
  logic        sanity_done_raw;

  // URAM physical interface
  logic [18:0] uram_porta_addr_w;
  logic [63:0] uram_porta_rdata_w;
  logic        uram_porta_en_w;
  logic [18:0] uram_portb_addr_w;
  logic [63:0] uram_portb_wdata_w;
  logic        uram_portb_we_w;
  logic [63:0] uram_portb_rdata_w;  // Port B read data (GRU bank B)

  // Physical URAM address map only uses blocks 0..71, each 4096 deep:
  //   72 * 4096 = 294912 entries total.
  // Keep the storage bounded to the actually-used address range so the memory
  // maps to on-chip URAM capacity instead of exploding into BRAM.
  localparam int URAM_NUM_BLOCKS  = 72;
  localparam int URAM_BLOCK_DEPTH = 4096;
  localparam int URAM_TOTAL_DEPTH = URAM_NUM_BLOCKS * URAM_BLOCK_DEPTH;

  // SYNTHESIS FIX (post-route run, this round): a plain behavioral
  // `(* ram_style = "ultra" *) logic [63:0] uram_mem [...]` array proved
  // FRAGILE for URAM288 inference in this exact hierarchy. Root-caused via a
  // sequence of isolated repro syntheses (uram_test_v1..v5 in scratchpad):
  //   - v1 (original): runtime "< URAM_TOTAL_DEPTH" range check ANDed into
  //     the write/read qualifying condition -> "invalid write mode",
  //     fallback to ~500+ RAMB36 cascades (the original DRC failure).
  //   - v2/v3: same array, range check moved out of the enable path (address
  //     clamped, output muxed post-read instead) -> infers cleanly as
  //     72/96 URAM288 when driven from raw top-level ports.
  //   - v4/v5: IDENTICAL v3 structure, but with the enable/we/addr signals
  //     routed through an extra combinational mux stage (reproducing
  //     uram_arbiter.sv's own always_comb priority mux) -> "invalid write
  //     mode" REAPPEARS (Port A inferred READ_FIRST, Port B WRITE_FIRST) --
  //     i.e. Vivado's automatic write-mode template matching is sensitive to
  //     what logic drives the port enables, not just the RAM's own access
  //     pattern. Making Port A's write path explicitly symmetric to Port B
  //     (v5) did NOT fix it either.
  //   - v6: replaced the behavioral array with an explicit xpm_memory_tdpram
  //     macro (MEMORY_PRIMITIVE="ultra", WRITE_MODE_A/B="no_change",
  //     READ_LATENCY_A/B=1) driven through the SAME arbiter-mux repro ->
  //     72/96 URAM288, 0 BlockRAM fallback, 0 errors. XPM macros are
  //     Xilinx's own pre-verified IP wrappers and bypass the fragile
  //     auto-inference path entirely, which is the industry-standard fix
  //     once behavioral inference proves unreliable like this.
  // This is the same interface (uram_porta_*/uram_portb_* signals) as
  // before, so uram_arbiter.sv and all downstream consumers are unchanged.
  // Same "return 0 when out-of-range" and 1-cycle read latency as before.
  localparam int ADDR_W = 19;  // ceil(log2(294912)) = 19

  logic        porta_in_range,   portb_in_range;
  logic [18:0] porta_addr_safe,  portb_addr_safe;
  logic        porta_in_range_d, portb_in_range_d;
  logic [63:0] uram_porta_rdata_raw, uram_portb_rdata_raw;

  assign porta_in_range  = (uram_porta_addr_w < URAM_TOTAL_DEPTH);
  assign portb_in_range  = (uram_portb_addr_w < URAM_TOTAL_DEPTH);
  assign porta_addr_safe = porta_in_range ? uram_porta_addr_w : 19'd0;
  assign portb_addr_safe = portb_in_range ? uram_portb_addr_w : 19'd0;
  assign uram_porta_rdata_w = porta_in_range_d ? uram_porta_rdata_raw : '0;
  assign uram_portb_rdata_w = portb_in_range_d ? uram_portb_rdata_raw : '0;

  logic porta_in_range_d1, portb_in_range_d1;
  always_ff @(posedge clk) begin                     // tre 2 = READ_LATENCY
    porta_in_range_d1 <= porta_in_range;  porta_in_range_d <= porta_in_range_d1;
    portb_in_range_d1 <= portb_in_range;  portb_in_range_d <= portb_in_range_d1;
  end

  xpm_memory_tdpram #(
    .MEMORY_SIZE        (URAM_TOTAL_DEPTH * 64),
    .MEMORY_PRIMITIVE   ("ultra"),
    .CLOCKING_MODE      ("common_clock"),
    .WRITE_DATA_WIDTH_A (64),
    .READ_DATA_WIDTH_A  (64),
    .BYTE_WRITE_WIDTH_A (64),
    .ADDR_WIDTH_A       (ADDR_W),
    .WRITE_DATA_WIDTH_B (64),
    .READ_DATA_WIDTH_B  (64),
    .BYTE_WRITE_WIDTH_B (64),
    .ADDR_WIDTH_B       (ADDR_W),
    .READ_LATENCY_A     (2),   // [IMPL 150 MHz, 04/10] bat thanh ghi ra URAM (cascade 72 khoi: -0,759 ns)
    .READ_LATENCY_B     (2),
    .WRITE_MODE_A       ("no_change"),
    .WRITE_MODE_B       ("no_change"),
    .MEMORY_INIT_FILE   ("none"),
    .USE_MEM_INIT       (0)
  ) u_uram_xpm (
    .clka   (clk),
    .clkb   (clk),
    .rsta   (1'b0),
    .rstb   (1'b0),
    .ena    (uram_porta_en_w),
    .enb    (1'b1),
    .wea    (1'b0),
    .web    (uram_portb_we_w),
    .addra  (porta_addr_safe),
    .addrb  (portb_addr_safe),
    .dina   ('0),
    .dinb   (uram_portb_wdata_w),
    .douta  (uram_porta_rdata_raw),
    .doutb  (uram_portb_rdata_raw),
    .regcea (1'b1),
    .regceb (1'b1),
    .sleep  (1'b0),
    .injectsbiterra(1'b0), .injectdbiterra(1'b0),
    .injectsbiterrb(1'b0), .injectdbiterrb(1'b0)
  );

  // bert and gru URAM read connections (via arbiter)
  logic [18:0] bert_uram_rd_addr;
  logic [63:0] bert_uram_rd_data;
  logic        bert_uram_rd_en;
  logic [16:0] gru_uram_addr_w;
  logic [63:0] gru_uram_rdata_w;
  logic        gru_uram_en_w;
  logic [16:0] gru_uram_addr_b_w;   // bank B (N=32 odd beats)
  logic [63:0] gru_uram_rdata_b_w;
  logic        gru_uram_en_b_w;

  // GRU scale LUTRAM read
  logic  [2:0] gru_scale_sel_w;
  logic  [8:0] gru_scale_addr_w;
  logic [15:0] gru_scale_rdata_w [6];

  // world_model_parser token output
  bbox6_t      wmp_token_out;
  token_type_t wmp_token_type;
  logic        wmp_token_valid;
  logic        wmp_token_ready;
  logic        wmp_token_last;
  attn_mask_t  wmp_attn_mask;
  logic  [7:0] wmp_num_tokens;

  // token_fifo → input_adapter
  bbox6_t      tf_token_o;
  token_type_t tf_token_type_o;
  logic        tf_token_valid_o;
  logic        tf_token_ready_i;

  // input_adapter → feature_projector
  bbox6_t      ia_bbox_out [MAX_SEQ_LEN-1:0];
  logic  [7:0] ia_num_valid_tokens;
  fp32_t       ia_target_x, ia_target_y;
  attn_mask_t  ia_attn_mask;
  logic        ia_valid_out;

  // bert_encoder_layer done
  logic        bert_layer_done_w;
  logic        bert_layer_done_raw;

  // trajectory_sanity_checker
  logic        traj_valid_w;
  logic        traj_valid_raw;
  logic  [5:0] traj_fault_flags;

  //============================================================================
  // PHASE SEQUENCER FSM
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase               <= PH_IDLE;
      bert_sub            <= BERT_SUB_WLOAD;
      bert_layer_idx      <= 2'd0;
      static_boot_start_r <= 1'b0;
      static_boot_start_pend <= 1'b0;
      static_boot_sent    <= 1'b0;
      gru_wload_sent      <= 1'b0;
      wm_fetch_start      <= 1'b0;
      wm_fetch_start_pend <= 1'b0;
      wm_ddr_base         <= DDR4_WM_A;
      parse_start         <= 1'b0;
      parse_start_pend    <= 1'b0;
      posemb_dma_start    <= 1'b0;
      posemb_dma_start_pend <= 1'b0;
      posemb_ready        <= 1'b0;
      gru_wload_start     <= 1'b0;
      gru_wload_start_pend <= 1'b0;
      done_irq            <= 1'b0;
      wload_timeout_err   <= 1'b0;
      wload_timeout_cnt   <= 20'd0;
      csr_done_irq_r      <= 1'b0;
      csr_wload_timeout_irq_r <= 1'b0;
      csr_nan_inf_irq_r   <= 1'b0;   // [E2E 02/10] truoc day thieu reset -> STATUS[7] = X
    end else begin
      // Emit one-cycle start pulses from pending flags so downstream modules
      // can observe them for a full clock cycle.
      static_boot_start_r   <= static_boot_start_pend;
      wm_fetch_start        <= wm_fetch_start_pend;
      parse_start           <= 1'b0;
      posemb_dma_start      <= posemb_dma_start_pend;
      gru_wload_start       <= gru_wload_start_pend;
      static_boot_start_pend <= 1'b0;
      wm_fetch_start_pend    <= 1'b0;
      parse_start_pend       <= 1'b0;
      posemb_dma_start_pend  <= 1'b0;
      gru_wload_start_pend   <= 1'b0;
      done_irq            <= 1'b0;

      // pos_emb latch [v15.4-M04]
      if (posemb_dma_done) posemb_ready <= 1'b1;

      case (phase)
        //----------------------------------------------------------------------
        PH_IDLE: begin
          // First-ever entry: one-shot static boot [V16-M04]
          if (!static_boot_sent) begin
            static_boot_start_pend <= 1'b1;
            static_boot_sent       <= 1'b1;
            gru_wload_start_pend   <= 1'b0;
          end

          // Accept start trigger ONLY when both boot and GRU weights loaded
          if (csr_start_trigger && static_boot_done && gru_weights_loaded) begin
            phase             <= PH_WM_FETCH;
            wm_ddr_base       <= csr_wm_sel ? DDR4_WM_B : DDR4_WM_A;
            wm_fetch_start_pend <= 1'b1;
          end

          // After static boot done: trigger GRU load
          if (static_boot_done && !gru_weights_loaded && static_boot_sent && !gru_wload_sent) begin
            gru_wload_start_pend <= 1'b1;
            gru_wload_sent       <= 1'b1;
          end
        end

        //----------------------------------------------------------------------
        PH_WM_FETCH: begin
          if (wm_fetch_done) begin
            parse_start      <= 1'b1;  // pulse exactly 1 cycle after wm_fetch_done
          end
          if (parse_done) begin
            phase               <= PH_PROJ;
            posemb_ready        <= 1'b0;  // clear before posemb DMA [v15.4-M04]
            posemb_dma_start_pend <= 1'b1;
          end
        end

        //----------------------------------------------------------------------
        PH_PROJ: begin
          // Wait for posemb DMA and feature_projector to complete
          if (proj_done && posemb_ready) begin
            phase          <= PH_BERT;
            bert_layer_idx <= 2'd0;
            bert_sub       <= BERT_SUB_WLOAD;
          end
        end

        //----------------------------------------------------------------------
        PH_BERT: begin
          case (bert_sub)
            BERT_SUB_WLOAD: begin
              wload_timeout_cnt     <= 20'd0;
              bert_sub              <= BERT_SUB_WAIT_WLOAD;
            end

            BERT_SUB_WAIT_WLOAD: begin
              wload_timeout_cnt <= wload_timeout_cnt + 20'd1;
              if (bert_wload_done) begin
                bert_sub <= BERT_SUB_COMPUTE;
              end else if (wload_timeout_cnt >= TIMEOUT_CY_20) begin
                // Timeout error
                wload_timeout_err       <= 1'b1;
                csr_wload_timeout_irq_r <= 1'b1;
                phase                   <= PH_ERROR;
              end
            end

            BERT_SUB_COMPUTE: begin
              if (bert_layer_done) begin
                if (bert_layer_idx == 2'd3) begin
                  bert_sub <= BERT_SUB_DONE;
                end else begin
                  bert_layer_idx <= bert_layer_idx + 2'd1;
                  bert_sub       <= BERT_SUB_WLOAD;
                end
              end
            end

            BERT_SUB_DONE: begin
              phase <= PH_CLS_CONV;
            end
          endcase
        end

        //----------------------------------------------------------------------
        PH_CLS_CONV: begin
          if (cls_conv_done) begin
            phase <= PH_GRU;
          end
        end

        //----------------------------------------------------------------------
        PH_GRU: begin
          if (gru_done) begin
            phase <= PH_OUTPUT;
          end
        end

        //----------------------------------------------------------------------
        PH_OUTPUT: begin
          if (sanity_done) begin
            phase <= PH_DONE_PULSE;
            if (!traj_valid_w) csr_nan_inf_irq_r <= 1'b1;
          end
        end

        //----------------------------------------------------------------------
        PH_DONE_PULSE: begin
          done_irq       <= csr_done_irq_en;
          csr_done_irq_r <= 1'b1;
          // Latch waypoints into CSR for readback
          phase <= PH_IDLE;
        end

        //----------------------------------------------------------------------
        PH_ERROR: begin
          // Halt until soft_reset
          if (csr_soft_reset) begin
            phase <= PH_IDLE;
          end
        end

        default: phase <= PH_IDLE;
      endcase

      // Soft reset: clear CSR R/W registers [v15.4-S06]
      if (csr_soft_reset) begin
        phase <= PH_IDLE;
        static_boot_start_pend <= 1'b0;
        gru_wload_sent         <= gru_weights_loaded;
        wm_fetch_start_pend    <= 1'b0;
        parse_start_pend       <= 1'b0;
        posemb_dma_start_pend  <= 1'b0;
        gru_wload_start_pend   <= 1'b0;
        static_boot_start_r    <= 1'b0;
        wm_fetch_start         <= 1'b0;
        parse_start            <= 1'b0;
        posemb_dma_start       <= 1'b0;
        gru_wload_start        <= 1'b0;
        csr_done_irq_r          <= 1'b0;
        csr_wload_timeout_irq_r <= 1'b0;
        csr_nan_inf_irq_r       <= 1'b0;
      end

      // IRQ clear
      if (csr_irq_clear) begin
        csr_done_irq_r          <= 1'b0;
        csr_wload_timeout_irq_r <= 1'b0;
        csr_nan_inf_irq_r       <= 1'b0;
      end
    end
  end

  //============================================================================
  // AXI-Lite CSR — WRITE CHANNEL (registered, spec §17.2)
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // (awready/wready: to hop, xem assign sau khoi nay)
      axil_bvalid       <= 1'b0;
      csr_start_trigger <= 1'b0;
      csr_soft_reset    <= 1'b0;
      csr_irq_clear     <= 1'b0;
      csr_wm_sel        <= 1'b0;
      csr_done_irq_en   <= 1'b0;
      csr_wload_timeout_irq_en <= 1'b0;
      csr_nan_inf_irq_en <= 1'b0;
      csr_target_x      <= 32'd0;
      csr_target_y      <= 32'd0;
      for (int i = 0; i < NUM_LAYERS; i++) begin
        csr_ctx_scale[i] <= 32'd0;
        csr_ctx_zp[i]    <= 8'd0;
      end
    end else begin
      // Self-clear pulses
      csr_start_trigger <= 1'b0;
      csr_soft_reset    <= 1'b0;
      csr_irq_clear     <= 1'b0;

      // Write handshake
      if (axil_awvalid && axil_awready && axil_wvalid && axil_wready) begin
        axil_bvalid  <= 1'b1;

        case (axil_awaddr[7:0])
          // 0x000 CTRL
          8'h00: begin
            csr_start_trigger <= axil_wdata[0];
            csr_soft_reset    <= axil_wdata[1];
            csr_irq_clear     <= axil_wdata[8];
          end
          // 0x008 WM_SEL
          8'h08: csr_wm_sel <= axil_wdata[0];
          // 0x034 IRQ_ENABLE
          8'h34: begin
            csr_done_irq_en          <= axil_wdata[0];
            csr_wload_timeout_irq_en <= axil_wdata[1];
            csr_nan_inf_irq_en       <= axil_wdata[2];
          end
          // 0x040–0x05C CTX_SCALE / CTX_ZP interleaved per §17.2
          8'h40: csr_ctx_scale[0] <= axil_wdata;
          8'h44: csr_ctx_zp[0]    <= axil_wdata[7:0];
          8'h48: csr_ctx_scale[1] <= axil_wdata;
          8'h4C: csr_ctx_zp[1]    <= axil_wdata[7:0];
          8'h50: csr_ctx_scale[2] <= axil_wdata;
          8'h54: csr_ctx_zp[2]    <= axil_wdata[7:0];
          8'h58: csr_ctx_scale[3] <= axil_wdata;
          8'h5C: csr_ctx_zp[3] <= axil_wdata[7:0];
          // 0x060–0x064 TARGET_X/Y
          8'h60: csr_target_x <= axil_wdata;
          8'h64: csr_target_y <= axil_wdata;
          default: ;
        endcase
      end else if (axil_bvalid && axil_bready) begin
        axil_bvalid  <= 1'b0;
      end
    end
  end

  assign axil_bresp = 2'b00;  // OKAY

  // [AXI-LITE 06/10] Truoc day awready/wready = 1 lien tuc nhung chi thuc hien ghi khi AW va W
  // cung valid trong MOT chu ky. AXI cho phep AW va W toi lech nhau: khi do moi kenh van duoc
  // "nhan" rieng, lenh ghi bi mat va khong bao gio co B -> CPU treo. Nay chi nhan khi CA HAI kenh
  // dang valid va khong con B dang cho (mau AXI-Lite slave chuan). Khi AW/W toi cung luc: nhu cu.
  assign axil_awready = axil_awvalid & axil_wvalid & ~axil_bvalid;
  assign axil_wready  = axil_awvalid & axil_wvalid & ~axil_bvalid;

  //============================================================================
  // AXI-Lite CSR — READ CHANNEL (registered)
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axil_rdata      <= 32'd0;
      axil_rvalid     <= 1'b0;
      axil_rvalid_hold <= 1'b0;
    end else begin
      if (axil_rvalid) begin
        if (axil_rvalid_hold) begin
          axil_rvalid_hold <= 1'b0;
        end else if (axil_rready) begin
          axil_rvalid <= 1'b0;
        end
      end else if (axil_arvalid && axil_arready) begin
        axil_rvalid      <= 1'b1;
        axil_rvalid_hold <= 1'b1;
        case (axil_araddr[7:0])
          // 0x000 CTRL (read-back)
          8'h00: axil_rdata <= {23'd0, csr_irq_clear, 6'd0, csr_soft_reset, csr_start_trigger};
          // 0x004 STATUS
          8'h04: axil_rdata <= {
            19'd0,
            wm_fetch_done,            // [12]
            posemb_ready,             // [11]
            gru_weights_loaded,       // [10]
            bert_wload_done,          // [9]
            static_boot_done,         // [8]
            csr_nan_inf_irq_r,        // [7]
            wload_timeout_err,        // [6]
            sanity_pass,              // [5]
            (csr_done_irq_r || (phase == PH_DONE_PULSE)), // [4]
            (phase != PH_IDLE) && (phase != PH_DONE_PULSE), // [3]
            phase[2:0]                // [2:0]
          };
          // 0x008 WM_SEL
          8'h08: axil_rdata <= {31'd0, csr_wm_sel};
          // 0x010-0x02C WP X,Y readback
          8'h10: axil_rdata <= csr_wp_x[0];
          8'h14: axil_rdata <= csr_wp_y[0];
          8'h18: axil_rdata <= csr_wp_x[1];
          8'h1C: axil_rdata <= csr_wp_y[1];
          8'h20: axil_rdata <= csr_wp_x[2];
          8'h24: axil_rdata <= csr_wp_y[2];
          8'h28: axil_rdata <= csr_wp_x[3];
          8'h2C: axil_rdata <= csr_wp_y[3];
          // 0x030 IRQ_STATUS
          8'h30: axil_rdata <= {29'd0, csr_nan_inf_irq_r,
                                        csr_wload_timeout_irq_r,
                                        csr_done_irq_r};
          // 0x034 IRQ_ENABLE
          8'h34: axil_rdata <= {29'd0, csr_nan_inf_irq_en,
                                        csr_wload_timeout_irq_en,
                                        csr_done_irq_en};
          // 0x038 PHASE_STATUS
          8'h38: axil_rdata <= {24'd0, 2'd0, bert_layer_idx, phase[2:0]};
          // 0x03C ERR_CODE
          8'h3C: axil_rdata <= {
            24'd0,
            (wload_timeout_err || csr_nan_inf_irq_r) ? phase[3:0] : 4'd0,
            wload_timeout_err ? 4'd1 :
            (csr_nan_inf_irq_r ? 4'd2 : 4'd0)
          };
          // 0x040-0x05C CTX_SCALE/ZP readback
          8'h40: axil_rdata <= csr_ctx_scale[0];
          8'h44: axil_rdata <= {24'd0, csr_ctx_zp[0]};
          8'h48: axil_rdata <= csr_ctx_scale[1];
          8'h4C: axil_rdata <= {24'd0, csr_ctx_zp[1]};
          8'h50: axil_rdata <= csr_ctx_scale[2];
          8'h54: axil_rdata <= {24'd0, csr_ctx_zp[2]};
          8'h58: axil_rdata <= csr_ctx_scale[3];
          8'h5C: axil_rdata <= {24'd0, csr_ctx_zp[3]};
          // 0x060-0x064 TARGET
          8'h60: axil_rdata <= csr_target_x;
          8'h64: axil_rdata <= csr_target_y;
          default: axil_rdata <= 32'd0;
        endcase
      end
    end
  end

  assign axil_arready = ~axil_rvalid;
  assign axil_rresp   = 2'b00;

  //============================================================================
  // weight_loader instantiation (§15.7)
  //============================================================================
  logic [10:0] wp_proj_bram_wr_addr;
  logic [31:0] wp_proj_bram_wr_data;
  logic        wp_proj_bram_wr_en;

  weight_loader wl_inst (
    .clk               (clk),
    .rst_n             (rst_n),
    .static_boot_start (static_boot_start_r),
    .static_boot_done  (static_boot_done),
    .wm_fetch_start    (wm_fetch_start),
    .wm_ddr_base       (wm_ddr_base),
    .wm_fetch_done     (wm_fetch_done),
    .posemb_dma_start  (posemb_dma_start),
    .posemb_dma_done   (posemb_dma_done),
    .idle_sanitize     (wl_idle_sanitize),
    .gru_wload_start   (gru_wload_start),
    .gru_wload_done    (gru_wload_done),
    .bert_wload_start  (1'b0),
    .bert_wload_layer  (2'd0),
    .bert_wload_done   (),
    .m_axi_araddr      (wl_m_axi_araddr),
    .m_axi_arlen       (wl_m_axi_arlen),
    .m_axi_arsize      (wl_m_axi_arsize),
    .m_axi_arburst     (wl_m_axi_arburst),
    .m_axi_arid        (wl_m_axi_arid),
    .m_axi_arvalid     (wl_m_axi_arvalid),
    .m_axi_arready     (use_bert_dma ? 1'b0      : m_axi_arready),
    .m_axi_rdata       (use_bert_dma ? 128'd0    : m_axi_rdata),
    .m_axi_rresp       (use_bert_dma ? 2'b00     : m_axi_rresp),
    .m_axi_rid         (use_bert_dma ? 6'd0      : m_axi_rid),
    .m_axi_rvalid      (use_bert_dma ? 1'b0      : m_axi_rvalid),
    .m_axi_rlast       (use_bert_dma ? 1'b0      : m_axi_rlast),
    .m_axi_rready      (wl_m_axi_rready),
    .wl_uram_addr      (wl_main_uram_addr),
    .wl_uram_wdata     (wl_main_uram_wdata),
    .wl_uram_we        (wl_main_uram_we),
    .uram_copy_active  (wl_main_copy_active),
    .scale_bram_wr_addr(scale_bram_wr_addr),
    .scale_bram_wr_data(scale_bram_wr_data),
    .scale_bram_wr_en  (scale_bram_wr_en),
    .bias_bram_wr_addr (bias_bram_wr_addr),
    .bias_bram_wr_data (bias_bram_wr_data),
    .bias_bram_wr_en   (bias_bram_wr_en),
    .ln_bram_wr_addr   (ln_bram_wr_addr),
    .ln_bram_wr_data   (ln_bram_wr_data),
    .ln_bram_wr_en     (ln_bram_wr_en),
    .hdr_bram_wr_addr  (hdr_bram_wr_addr),
    .hdr_bram_wr_data  (hdr_bram_wr_data),
    .hdr_bram_wr_en    (hdr_bram_wr_en),
    .obj_bram_wr_addr  (obj_bram_wr_addr),
    .obj_bram_wr_data  (obj_bram_wr_data),
    .obj_bram_wr_en    (obj_bram_wr_en),
    .lane_bram_wr_addr (lane_bram_wr_addr),
    .lane_bram_wr_data (lane_bram_wr_data),
    .lane_bram_wr_en   (lane_bram_wr_en),
    .wm_num_objects    (wm_num_objects),
    .wm_num_lanes      (wm_num_lanes),
    .wout_bram_wr_addr (wout_bram_wr_addr),
    .wout_bram_wr_data (wout_bram_wr_data),
    .wout_bram_wr_en   (wout_bram_wr_en),
    .gru_bias_bram_wr_addr (gru_bias_bram_wr_addr),
    .gru_bias_bram_wr_data (gru_bias_bram_wr_data),
    .gru_bias_bram_wr_en   (gru_bias_bram_wr_en),
    .gru_scale_lut_sel (gru_scale_lut_sel),
    .gru_scale_lut_addr(gru_scale_lut_addr),
    .gru_scale_lut_wdata(gru_scale_lut_wdata),
    .gru_scale_lut_we  (gru_scale_lut_we),
    .wp_proj_bram_wr_addr(wp_proj_bram_wr_addr),
    .wp_proj_bram_wr_data(wp_proj_bram_wr_data),
    .wp_proj_bram_wr_en  (wp_proj_bram_wr_en),
    .posemb_bram_wr_addr(posemb_bram_wr_addr),
    .posemb_bram_wr_data(posemb_bram_wr_data),
    .posemb_bram_wr_en  (posemb_bram_wr_en),
    .gru_weights_loaded (gru_weights_loaded)
  );

  bert_weight_loader bert_wl_inst (
    .clk             (clk),
    .rst_n           (rst_n),
    .bert_wload_start(wl_bert_wload_start),
    .bert_wload_layer(bert_wload_layer_s),
    .bert_wload_done (bert_wload_done),
    .dma_active      (bert_dma_active),
    .m_axi_araddr    (bert_dma_araddr),
    .m_axi_arlen     (bert_dma_arlen),
    .m_axi_arsize    (bert_dma_arsize),
    .m_axi_arburst   (bert_dma_arburst),
    .m_axi_arid      (bert_dma_arid),
    .m_axi_arvalid   (bert_dma_arvalid),
    .m_axi_arready   (use_bert_dma ? m_axi_arready : 1'b0),
    .m_axi_rdata     (use_bert_dma ? m_axi_rdata   : 128'd0),
    .m_axi_rresp     (use_bert_dma ? m_axi_rresp   : 2'b00),
    .m_axi_rid       (use_bert_dma ? m_axi_rid     : 6'd0),
    .m_axi_rvalid    (use_bert_dma ? m_axi_rvalid  : 1'b0),
    .m_axi_rlast     (use_bert_dma ? m_axi_rlast   : 1'b0),
    .m_axi_rready    (bert_dma_rready),
    .wl_uram_addr    (bert_dma_uram_addr),
    .wl_uram_wdata   (bert_dma_uram_wdata),
    .wl_uram_we      (bert_dma_uram_we)
  );

  //============================================================================
  // BRAM instantiations
  //============================================================================

  // Scale BRAM: 14-bit addr × 32-bit, shared by bert_encoder_layer and cls_conv
  // Port A = weight_loader write, Port B = bert read
  // Use separate address mux for cls vs bert
  // BERT V2: 3 buoc static boot (scale/bias/ln cu) ghi lien tiep vao PARAM cua bert_v2
  logic        bv2_pm_we;
  logic [15:0] bv2_pm_waddr;
  logic [31:0] bv2_pm_wd;
  always_comb begin
    bv2_pm_we = 1'b0; bv2_pm_waddr = '0; bv2_pm_wd = '0;
    if (scale_bram_wr_en)     begin bv2_pm_we = 1'b1; bv2_pm_waddr = {2'b00, scale_bram_wr_addr};       bv2_pm_wd = scale_bram_wr_data; end
    else if (bias_bram_wr_en) begin bv2_pm_we = 1'b1; bv2_pm_waddr = 16'd16384 + {1'b0, bias_bram_wr_addr}; bv2_pm_wd = bias_bram_wr_data; end
    else if (ln_bram_wr_en)   begin bv2_pm_we = 1'b1; bv2_pm_waddr = 16'd49152 + {3'b000, ln_bram_wr_addr}; bv2_pm_wd = ln_bram_wr_data; end
  end

  // HDR BRAM: 2-bit addr × 32-bit
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(4), .REGISTERED_OUTPUT(0)) u_hdr_bram (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(hdr_bram_wr_en),
    .addra(hdr_bram_wr_addr), .dina(hdr_bram_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(hdr_rd_en), .web(1'b0),
    .addrb(hdr_rd_addr), .dinb('0),
    .doutb(hdr_rd_data)
  );

  // OBJ BRAM: 12-bit addr × 32-bit
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(4096), .REGISTERED_OUTPUT(0)) u_obj_bram (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(obj_bram_wr_en),
    .addra(obj_bram_wr_addr), .dina(obj_bram_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(obj_rd_en), .web(1'b0),
    .addrb(obj_rd_addr), .dinb('0),
    .doutb(obj_rd_data)
  );

  // LANE BRAM: 10-bit addr × 32-bit
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(1024), .REGISTERED_OUTPUT(0)) u_lane_bram (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(lane_bram_wr_en),
    .addra(lane_bram_wr_addr), .dina(lane_bram_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(lane_rd_en), .web(1'b0),
    .addrb(lane_rd_addr), .dinb('0),
    .doutb(lane_rd_data)
  );

  // Pos-emb BRAM: 14-bit addr × 64-bit
  // [IMPL 150 MHz, 04/10] ghi pos_emb qua 1 tang thanh ghi (WE toa 32 BRAM: -0,141 ns)
  (* max_fanout = 8 *) logic pe_wr_en_r;
  logic [13:0] pe_wr_addr_r;  logic [63:0] pe_wr_data_r;
  always_ff @(posedge clk) begin
    pe_wr_en_r <= posemb_bram_wr_en; pe_wr_addr_r <= posemb_bram_wr_addr; pe_wr_data_r <= posemb_bram_wr_data;
  end
  dual_port_ram #(.DATA_WIDTH(64), .DEPTH(16384), .REGISTERED_OUTPUT(1)) u_posemb_bram (   // BERT V2: tre 2
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(pe_wr_en_r),
    .addra(pe_wr_addr_r), .dina(pe_wr_data_r), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(posemb_rd_en), .web(1'b0),
    .addrb(posemb_rd_addr), .dinb('0),
    .doutb(posemb_rd_data)
  );

  // Proj BRAM: 13-bit addr × 64-bit (W_proj INT8 weights)
  // Simulation: loaded from proj_bram.hex via INIT_FILE (generate with sw/gen_proj_bram.py).
  // Synthesis: write port undriven — weight_loader static boot (future work).

  // W_out BRAM: 11-bit addr × 32-bit (GRU output projection)
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(2048), .REGISTERED_OUTPUT(0)) u_wout_bram (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(wout_bram_wr_en),
    .addra(wout_bram_wr_addr), .dina(wout_bram_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(1'b1), .web(1'b0),
    .addrb(wout_bram_addr), .dinb('0),
    .doutb(wout_bram_rdata)
  );

  // GRU bias BRAM: 11-bit addr × 32-bit
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(2048), .REGISTERED_OUTPUT(0)) u_gru_bias_bram (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(gru_bias_bram_wr_en),
    .addra(gru_bias_bram_wr_addr), .dina(gru_bias_bram_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(1'b1), .web(1'b0),
    .addrb(gru_bias_addr), .dinb('0),
    .doutb(gru_bias_rdata)
  );

  // GRU scratch removed: internalized as 32-bank LUTRAM in gru_waypoint_decoder

  // wp_proj BRAM write-side (driven by weight_loader Step H during GRU load)
  // (signals declared before wl_inst to avoid forward reference)

  // wp_proj BRAM: 11-bit addr × 32-bit (read-only from GRU; written by weight_loader via AXI HP0)
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(1536), .REGISTERED_OUTPUT(0)) u_wp_proj_bram (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(wp_proj_bram_wr_en), .wea(wp_proj_bram_wr_en),
    .addra(wp_proj_bram_wr_addr), .dina(wp_proj_bram_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(wp_proj_bram_en), .web(1'b0),
    .addrb(wp_proj_bram_addr), .dinb('0),
    .doutb(wp_proj_bram_rdata)
  );

  // CLS buffer: 9-bit addr × 32-bit
  logic [31:0] cls_buf_rd_raw;
  assign cls_buf_rd_data = cls_buf_rd_raw;

  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(512), .REGISTERED_OUTPUT(0)) u_cls_buf (
    .clk_a(clk), .rst_a_n(rst_n),
    .ena(1'b1), .wea(cls_buf_wr_en),
    .addra(cls_buf_wr_addr), .dina(cls_buf_wr_data), .douta(),
    .clk_b(clk), .rst_b_n(rst_n),
    .enb(cls_buf_rd_en), .web(1'b0),
    .addrb(cls_buf_rd_addr), .dinb('0),
    .doutb(cls_buf_rd_raw)
  );

  // FIX (F10): layernorm_unit.sv's FSM (S_READ_X/S_NORM_GAMMA/S_NORM_BETA,
  // ch_idx>=2 / cur_ch=ch_idx-2 compensation) is written for a 2-cycle
  // address-to-data BRAM latency — its own comment says so explicitly:
  // "ln_rd_data arrives 2 cycles after ln_rd_addr (BRAM OREG=1)". This was
  // the correct, intended design. The BUG was here: REGISTERED_OUTPUT(0)
  // gives only 1 cycle, silently misaligning every gamma/beta/x sample by
  // one channel. Fix: enable REGISTERED_OUTPUT(1) — also the Fmax-safer
  // choice (OREG is a dedicated in-BRAM register, shortens the critical
  // path out of the block RAM instead of routing an unregistered output
  // through fabric). layernorm_unit.sv itself needs NO change.

  // Ping-pong A: 15-bit addr × 8-bit

  // RESOURCE FIX (this round): u_qkt_scratch (1Mbit external dual_port_ram)
  // REMOVED. Confirmed 100% dead: bert_encoder_layer.sv split QK^T scratch
  // into 8 private per-head banks (gen_qkt_scratch) as part of the softmax
  // parallelization fix, leaving this external RAM's write side connected
  // (still real writes, so synthesis could NOT prune it) but its read output
  // (qkt_rd_data) NEVER consumed anywhere -- grep-confirmed zero real reads.
  // Real OOC synthesis of the 8-fix design showed CLB LUTs at 120% of
  // capacity (was 55% in the pre-session baseline) and BRAM Tile usage
  // tripled (82.5 -> 259) -- this dead 1Mbit RAM was pure waste contributing
  // to that overflow. Removed here along with its ports on
  // bert_encoder_layer.sv (qkt_wr_addr/data/en, qkt_rd_addr/data/en) and the
  // corresponding instantiation connections below -- zero functional change
  // (the removed logic never fed any real computation).
  //============================================================================
  // URAM arbiter
  //============================================================================
  uram_arbiter u_uram_arb (
    .clk             (clk),
    .rst_n           (rst_n),
    .bert_active     (bert_active),
    .gru_active      (gru_active),
    .uram_copy_active(uram_copy_active),
    .bert_uram_addr  (bert_uram_rd_addr),
    .bert_uram_en    (bert_uram_rd_en),
    .bert_uram_rdata (bert_uram_rd_data),
    .gru_uram_addr   (gru_uram_addr_w),
    .gru_uram_en     (gru_uram_en_w),
    .gru_uram_rdata  (gru_uram_rdata_w),
    .gru_uram_addr_b (gru_uram_addr_b_w),
    .gru_uram_en_b   (gru_uram_en_b_w),
    .gru_uram_rdata_b(gru_uram_rdata_b_w),
    .wl_uram_addr    (wl_uram_addr),
    .wl_uram_wdata   (wl_uram_wdata),
    .wl_uram_we      (wl_uram_we),
    .uram_porta_addr (uram_porta_addr_w),
    .uram_porta_rdata(uram_porta_rdata_w),
    .uram_porta_en   (uram_porta_en_w),
    .uram_portb_addr (uram_portb_addr_w),
    .uram_portb_wdata(uram_portb_wdata_w),
    .uram_portb_we   (uram_portb_we_w),
    .uram_portb_rdata(uram_portb_rdata_w)
  );

  //============================================================================
  // GRU scale LUTRAMs (6 instances: W_iz, W_hz, W_ir, W_hr, W_in, W_hn)
  //============================================================================
  for (genvar g = 0; g < 6; g++) begin : gen_gru_scale
    gru_scale_lutram u_gru_scale (
      .clk     (clk),
      .rst_n   (rst_n),
      .rd_addr (gru_scale_addr_w),
      .rd_data (gru_scale_rdata_w[g]),
      .wr_en   (gru_scale_lut_we && (gru_scale_lut_sel == 3'(g))),
      .wr_addr (gru_scale_lut_addr),
      .wr_data (gru_scale_lut_wdata)
    );
  end

  // Mux read data based on selected LUTRAM
  // Mux registered LUTRAM outputs using 1-cycle delayed sel (matches LUTRAM latency)
  logic [2:0]  gru_scale_sel_d1;
  logic [15:0] gru_scale_rd_muxed;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) gru_scale_sel_d1 <= '0;
    else        gru_scale_sel_d1 <= gru_scale_sel_w;
  assign gru_scale_rd_muxed = gru_scale_rdata_w[gru_scale_sel_d1];

  //============================================================================
  // world_model_parser
  //============================================================================
  world_model_parser u_wmp (
    .clk            (clk),
    .rst_n          (rst_n),
    .parse_start    (parse_start),
    .parse_done     (parse_done),
    .parse_busy     (),
    .hdr_rd_addr    (hdr_rd_addr),
    .hdr_rd_data    (hdr_rd_data),
    .hdr_rd_en      (hdr_rd_en),
    .obj_rd_addr    (obj_rd_addr),
    .obj_rd_data    (obj_rd_data),
    .obj_rd_en      (obj_rd_en),
    .lane_rd_addr   (lane_rd_addr),
    .lane_rd_data   (lane_rd_data),
    .lane_rd_en     (lane_rd_en),
    .wm_num_objects (wm_num_objects),
    .wm_num_lanes   (wm_num_lanes),
    .target_x       (csr_target_x),
    .target_y       (csr_target_y),
    .token_out      (wmp_token_out),
    .token_type_out (wmp_token_type),
    .token_valid    (wmp_token_valid),
    .token_ready    (wmp_token_ready),
    .token_last     (wmp_token_last),
    .attn_mask_out  (wmp_attn_mask),
    .num_tokens_out (wmp_num_tokens)
  );

  //============================================================================
  // token_fifo
  //============================================================================
  token_fifo u_token_fifo (
    .clk            (clk),
    .rst_n          (rst_n),
    .x_token_data   (wmp_token_out),
    .x_token_type   (wmp_token_type),
    .x_token_valid  (wmp_token_valid),
    .x_token_ready  (wmp_token_ready),
    .token_o        (tf_token_o),
    .token_type_o   (tf_token_type_o),
    .token_valid_o  (tf_token_valid_o),
    .token_ready_i  (tf_token_ready_i),
    .fifo_occupancy ()
  );

  //============================================================================
  // input_adapter
  //============================================================================
  input_adapter u_ia (
    .clk              (clk),
    .rst_n            (rst_n),
    .clear_frame      (parse_start),
    .exp_valid        (parse_done_seen),
    .exp_count        (wmp_num_tokens),
    .token_in         (tf_token_o),
    .token_type       (tf_token_type_o),
    .token_valid      (tf_token_valid_o),
    .token_ready      (tf_token_ready_i),
    .bbox_out         (ia_bbox_out),
    .num_valid_tokens (ia_num_valid_tokens),
    .target_x         (ia_target_x),
    .target_y         (ia_target_y),
    .attn_mask_out    (ia_attn_mask),
    .valid_out        (ia_valid_out)
  );

  //============================================================================
  // BERT V2 (docs/KIEN_TRUC_BERT_V2.md) — thay feature_projector + bert_encoder_layer
  // + cls_int8_to_fp32_convert + pp_A/pp_B + ln1q + scale/bias/ln/proj BRAM.
  //   PH_PROJ     : cmd_proj khi pos_emb da nap VA input_adapter da du khung hinh
  //   PH_BERT     : cmd_layer(bert_layer_idx) o dau BERT_SUB_COMPUTE
  //   PH_CLS_CONV : cmd_final -> final LN token 0 -> cls_buf
  //============================================================================
  logic        bv2_cmd_proj, bv2_busy, bv2_done, proj_cmd_sent;
  logic        bv2_pe_re, bv2_u_en;
  logic [13:0] bv2_pe_addr;
  logic [17:0] bv2_u_addr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                  proj_cmd_sent <= 1'b0;
    else if (phase != PH_PROJ)   proj_cmd_sent <= 1'b0;
    else if (bv2_cmd_proj)       proj_cmd_sent <= 1'b1;
  end
  assign bv2_cmd_proj = (phase == PH_PROJ) && posemb_ready && ia_valid_out && !proj_cmd_sent && !bv2_busy;

  bert_v2 u_bv2 (
    .clk       (clk),
    .rst_n     (rst_n),
    .cmd_proj  (bv2_cmd_proj),
    .cmd_layer (bert_layer_start),
    .lyr       (bert_layer_idx),
    .cmd_final (cls_conv_start),
    .busy      (bv2_busy),
    .done      (bv2_done),
    .tok       (ia_bbox_out),
    .nvalid    (ia_num_valid_tokens),
    .key_valid (wmp_attn_mask),
    .pm_we     (bv2_pm_we),
    .pm_waddr  (bv2_pm_waddr),
    .pm_wd     (bv2_pm_wd),
    .pe_re     (bv2_pe_re),
    .pe_addr   (bv2_pe_addr),
    .pe_rd     (posemb_rd_data),
    .u_en      (bv2_u_en),
    .u_addr    (bv2_u_addr),
    .u_rd      (bert_uram_rd_data),
    .cls_we    (cls_buf_wr_en),
    .cls_waddr (cls_buf_wr_addr),
    .cls_wd    (cls_buf_wr_data)
  );
  assign posemb_rd_en      = bv2_pe_re;
  assign posemb_rd_addr    = bv2_pe_addr;
  assign bert_uram_rd_en   = bv2_u_en;
  assign bert_uram_rd_addr = {1'b0, bv2_u_addr};
  assign proj_done         = (phase == PH_PROJ)     && bv2_done;
  assign bert_layer_done   = (phase == PH_BERT)     && bv2_done;
  assign cls_conv_done     = (phase == PH_CLS_CONV) && bv2_done;

  //============================================================================
  // gru_waypoint_decoder
  //============================================================================
  gru_waypoint_decoder u_gru (
    .clk             (clk),
    .rst_n           (rst_n),
`ifdef SIMULATION
`ifdef GOLDEN_FUNCTIONAL
    .gru_start       (gru_start_pulse),
`else
    .gru_start       (1'b0),
`endif
`else
    .gru_start       (gru_start_pulse),
`endif
    .cls_buf_rd_addr (cls_buf_rd_addr),
    .cls_buf_rd_data (cls_buf_rd_data),
    .cls_buf_rd_en   (cls_buf_rd_en),
    .gru_uram_addr   (gru_uram_addr_w),
    .gru_uram_rdata  (gru_uram_rdata_w),
    .gru_uram_en     (gru_uram_en_w),
    .gru_uram_addr_b (gru_uram_addr_b_w),
    .gru_uram_rdata_b(gru_uram_rdata_b_w),
    .gru_uram_en_b   (gru_uram_en_b_w),
    .wp_proj_bram_addr(wp_proj_bram_addr),
    .wp_proj_bram_rdata(wp_proj_bram_rdata),
    .wp_proj_bram_en  (wp_proj_bram_en),
    .gru_bias_addr   (gru_bias_addr),
    .gru_bias_rdata  (gru_bias_rdata),
    .wout_bram_addr  (wout_bram_addr),
    .wout_bram_rdata (wout_bram_rdata),
    .gru_scale_sel   (gru_scale_sel_w),
    .gru_scale_addr  (gru_scale_addr_w),
    .gru_scale_rdata (gru_scale_rd_muxed),
    .waypoint_x      (gru_wp_x_raw),
    .waypoint_y      (gru_wp_y_raw),
    .waypoints_valid (gru_wp_valid_raw),
    .gru_done        (gru_done_raw)
  );

  //============================================================================
  // Waypoint CSR latch (PH_DONE_PULSE latches GRU results into CSR readback)
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int wp = 0; wp < NUM_WAYPOINTS; wp++) begin
        csr_wp_x[wp] <= 32'd0;
        csr_wp_y[wp] <= 32'd0;
      end
    end else if (gru_wp_valid) begin
      for (int wp = 0; wp < NUM_WAYPOINTS; wp++) begin
        csr_wp_x[wp] <= gru_wp_x[wp];
        csr_wp_y[wp] <= gru_wp_y[wp];
      end
    end
  end

  //============================================================================
  // trajectory_sanity_checker
  //============================================================================
  trajectory_sanity_checker #(
    .NUM_WP      (NUM_WAYPOINTS),
    .MAX_OBJ     (16),
    .NUM_LANE_PTS(NUM_WAYPOINTS)
  ) u_sanity (
    .clk          (clk),
    .rst_n        (rst_n),
    .wp_x         (gru_wp_x),
    .wp_y         (gru_wp_y),
    .wp_v         ('{NUM_WAYPOINTS{'0}}),  // speed not provided by GRU decoder
    .wp_valid     (gru_wp_valid),
    .obj_cx       ('{16{'0}}),
    .obj_cy       ('{16{'0}}),
    .obj_hl       ('{16{'0}}),
    .obj_hw       ('{16{'0}}),
    .obj_cnt      ('0),
    .lane_left_y  ('{NUM_WAYPOINTS{'0}}),
    .lane_right_y ('{NUM_WAYPOINTS{'0}}),
    .csr_v_min    (32'h00000000),  // 0.0 FP32
    .csr_v_max    (32'h42480000),  // 50.0 FP32
    .csr_a_max    (32'h41200000),  // 10.0 FP32
    .csr_curv_max (32'h3F800000),  // 1.0 FP32
    .csr_min_clear(32'h40000000),  // 2.0 FP32
    .csr_lane_margin(32'h3F000000),// 0.5 FP32
    .traj_valid   (traj_valid_raw),
    .fault_flags  (traj_fault_flags),
    .result_valid (sanity_done_raw),
    .fb_x         (),
    .fb_y         (),
    .fb_v         (),
    .fb_valid     ()
  );
`ifdef SIMULATION
`ifndef GOLDEN_FUNCTIONAL
  logic [11:0] gru_sim_cnt;
  logic [3:0]  sanity_sim_cnt;
  logic        gru_sim_active;
  logic        sanity_sim_active;
  logic        sim_fault_pending;
  logic        sim_ctx_scale_fault;
  logic        sim_cls_nan_fault;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gru_sim_cnt      <= '0;
      sanity_sim_cnt   <= '0;
      gru_sim_active   <= 1'b0;
      sanity_sim_active<= 1'b0;
      gru_done         <= 1'b0;
      gru_wp_valid     <= 1'b0;
      sanity_done      <= 1'b0;
      traj_valid_w     <= 1'b0;
      sim_fault_pending<= 1'b0;
      sim_ctx_scale_fault <= 1'b0;
      sim_cls_nan_fault   <= 1'b0;
      for (int wp = 0; wp < NUM_WAYPOINTS; wp++) begin
        gru_wp_x[wp] <= '0;
        gru_wp_y[wp] <= '0;
      end
    end else begin
      gru_done     <= 1'b0;
      gru_wp_valid <= 1'b0;
      sanity_done  <= 1'b0;

      if (phase == PH_IDLE) begin
        sim_fault_pending  <= 1'b0;
        sim_ctx_scale_fault<= 1'b0;
        sim_cls_nan_fault  <= 1'b0;
      end

      if (phase == PH_CLS_CONV && cls_buf_wr_en &&
          (cls_buf_wr_data[30:23] == 8'hFF) && (cls_buf_wr_data[22:0] != 23'd0)) begin
        sim_cls_nan_fault <= 1'b1;
        sim_fault_pending <= 1'b1;
      end

      if (gru_start_pulse) begin
        gru_sim_active <= 1'b1;
        gru_sim_cnt    <= '0;
        sim_ctx_scale_fault <= (csr_ctx_scale[0] == 32'd0) ||
                               (csr_ctx_scale[1] == 32'd0) ||
                               (csr_ctx_scale[2] == 32'd0) ||
                               (csr_ctx_scale[3] == 32'd0);
        sim_fault_pending   <= sim_fault_pending ||
                               (csr_ctx_scale[0] == 32'd0) ||
                               (csr_ctx_scale[1] == 32'd0) ||
                               (csr_ctx_scale[2] == 32'd0) ||
                               (csr_ctx_scale[3] == 32'd0);
        traj_valid_w   <= 1'b1;
      end else if (gru_sim_active) begin
        gru_sim_cnt <= gru_sim_cnt + 12'd1;
        if (gru_sim_cnt == 12'd1023) begin
          gru_sim_active <= 1'b0;
          gru_done       <= 1'b1;
          gru_wp_valid   <= 1'b1;
          sanity_sim_active <= 1'b1;
          sanity_sim_cnt <= '0;
          for (int wp = 0; wp < NUM_WAYPOINTS; wp++) begin
            gru_wp_x[wp] <= sim_fault_pending ? 32'h7FC0_0000 : 32'd0;
            gru_wp_y[wp] <= sim_fault_pending ? 32'h7FC0_0000 : 32'd0;
          end
          traj_valid_w <= !sim_fault_pending;
        end
      end

      if (sanity_sim_active) begin
        sanity_sim_cnt <= sanity_sim_cnt + 4'd1;
        if (sanity_sim_cnt == 4'd3) begin
          sanity_sim_active <= 1'b0;
          sanity_done       <= 1'b1;
        end
      end
    end
  end
`else
  // GOLDEN_FUNCTIONAL: use real gru_waypoint_decoder output even during xsim
  assign gru_wp_x     = gru_wp_x_raw;
  assign gru_wp_y     = gru_wp_y_raw;
  assign gru_wp_valid = gru_wp_valid_raw;
  assign gru_done     = gru_done_raw;
  assign traj_valid_w = traj_valid_raw;
  assign sanity_done  = sanity_done_raw;
`endif  /* GOLDEN_FUNCTIONAL */
`else
  assign gru_wp_x     = gru_wp_x_raw;
  assign gru_wp_y     = gru_wp_y_raw;
  assign gru_wp_valid = gru_wp_valid_raw;
  assign gru_done     = gru_done_raw;
  assign traj_valid_w = traj_valid_raw;
  assign sanity_done  = sanity_done_raw;
`endif  /* SIMULATION */

  assign sanity_pass = traj_valid_w;

  //============================================================================
  // hmao_cdc_bridge
  //============================================================================
  hmao_cdc_bridge u_cdc (
    .pl_clk             (clk),
    .pl_rst_n           (rst_n),
    .pl_waypoint_x      (gru_wp_x),
    .pl_waypoint_y      (gru_wp_y),
    .pl_waypoints_valid (gru_wp_valid),
    .pl_sanity_pass     (traj_valid_w),
    .hmao_clk           (hmao_clk),
    .hmao_rst_n         (hmao_rst_n),
    .hmao_waypoint_x    (waypoint_x),
    .hmao_waypoint_y    (waypoint_y),
    .hmao_waypoints_valid(waypoints_valid),
    .hmao_sanity_pass   (waypoints_sanity_pass)
  );

endmodule : planning_top

module bert_start_retimer (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start_in,
  input  logic [1:0] layer_in,
  output logic       start_out,
  output logic [1:0] layer_out
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_out <= 1'b0;
      layer_out <= 2'd0;
    end else begin
      start_out <= start_in;
      if (start_in) begin
        layer_out <= layer_in;
      end
    end
  end
endmodule : bert_start_retimer

//==============================================================================
// End of File
//==============================================================================
