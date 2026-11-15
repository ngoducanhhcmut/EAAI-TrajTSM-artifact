//==============================================================================
// File: weight_loader.sv  (FIXED 2026-04-02)
// Description: Unified DMA Engine for all weight / data loading operations
//
//   Single AXI HP0 128-bit READ-ONLY master. Handles ALL DMA phases:
//     Static boot:  Steps A (Scale), B (Bias), C (LN params) → static_boot_done
//     WM_FETCH:     Steps HDR → OBJ → LANE → wm_fetch_done
//     posemb DMA:   DDR4_POS_EMB → pos_emb BRAM → posemb_dma_done
//     GRU load:     Steps D (weights) → E (W_out) → F (bias) → G (scale/ZP) → H (wp_proj)
//     BERT load:    DDR4_BERT_WEIGHT + layer×stride → URAM portB → bert_wload_done
//
//   FSM PRIORITY (highest first):
//     static_boot_start > wm_fetch_start > posemb_dma_start
//     > gru_wload_start > bert_wload_start
//
//   AXI HP0 constraints:
//     - arsize = 3'b100 (16 bytes per beat)
//     - arburst = 2'b01 (INCR)
//     - arlen = 8'd255 for BERT/GRU bursts; 8'd0 for short single-beat
//     - arid = 6'd0 (single ID)
//     - Max 1 outstanding transaction
//
//   Write-expansion mechanism (BUG FIX):
//     rdata_latch [127:0] : latches AXI rdata when a beat is accepted
//     write_busy          : asserted while expanding one beat into N writes
//     m_axi_rready = ~write_busy : back-pressure prevents next beat until done
//
//     BRAM path (scale/bias/LN/WM/GRU):
//       Each 128-bit beat → 4 × 32-bit writes, sequenced by word_idx (0..3)
//       = 4 clock cycles per beat
//
//     URAM path (BERT/GRU weights):
//       Each 128-bit beat → 2 × 64-bit writes, sequenced by sub_beat (0,1)
//       = 2 clock cycles per beat
//       BERT total: 98304 beats × 2 = 196608 URAM writes
//       GRU-D total: 49152 beats × 2 = 98304 URAM writes
//
// Spec: VLA_HMAO_SPEC_v15_5.txt §15.6, §15.7, §3.7.5
// Author: VLA-HMAO Team
//==============================================================================

`timescale 1ns / 1ps
/* verilator lint_off WIDTHEXPAND */

module weight_loader
  import planning_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  //── Control inputs ────────────────────────────────────────────────────────────
  input  logic        static_boot_start,
  output logic        static_boot_done,

  input  logic        wm_fetch_start,
  input  logic [31:0] wm_ddr_base,
  output logic        wm_fetch_done,

  input  logic        posemb_dma_start,
  output logic        posemb_dma_done,
  input  logic        idle_sanitize,

  input  logic        gru_wload_start,
  output logic        gru_wload_done,

  input  logic        bert_wload_start,
  input  logic  [1:0] bert_wload_layer,
  output logic        bert_wload_done,

  //── AXI HP0 Read Master (128-bit) ────────────────────────────────────────────
  output logic [31:0] m_axi_araddr,
  output logic  [7:0] m_axi_arlen,
  output logic  [2:0] m_axi_arsize,
  output logic  [1:0] m_axi_arburst,
  output logic  [5:0] m_axi_arid,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [127:0] m_axi_rdata,
  input  logic  [1:0] m_axi_rresp,
  input  logic  [5:0] m_axi_rid,
  input  logic        m_axi_rvalid,
  input  logic        m_axi_rlast,
  output logic        m_axi_rready,

  //── URAM Port B write ─────────────────────────────────────────────────────────
  output logic [18:0] wl_uram_addr,
  output logic [63:0] wl_uram_wdata,
  output logic        wl_uram_we,
  output logic        uram_copy_active,

  //── Scale BRAM write (Step A) ─────────────────────────────────────────────────
  output logic [13:0] scale_bram_wr_addr,
  output logic [31:0] scale_bram_wr_data,
  output logic        scale_bram_wr_en,

  //── Bias BRAM write (Step B) ──────────────────────────────────────────────────
  output logic [14:0] bias_bram_wr_addr,
  output logic [31:0] bias_bram_wr_data,
  output logic        bias_bram_wr_en,

  //── LN BRAM write (Step C) ────────────────────────────────────────────────────
  output logic [12:0] ln_bram_wr_addr,
  output logic [31:0] ln_bram_wr_data,
  output logic        ln_bram_wr_en,

  //── World model BRAM writes ───────────────────────────────────────────────────
  output logic  [1:0] hdr_bram_wr_addr,
  output logic [31:0] hdr_bram_wr_data,
  output logic        hdr_bram_wr_en,
  output logic [11:0] obj_bram_wr_addr,
  output logic [31:0] obj_bram_wr_data,
  output logic        obj_bram_wr_en,
  output logic  [9:0] lane_bram_wr_addr,
  output logic [31:0] lane_bram_wr_data,
  output logic        lane_bram_wr_en,
  output logic  [7:0] wm_num_objects,
  output logic  [4:0] wm_num_lanes,

  //── GRU W_out BRAM write (Step E) ─────────────────────────────────────────────
  output logic [10:0] wout_bram_wr_addr,
  output logic [31:0] wout_bram_wr_data,
  output logic        wout_bram_wr_en,

  //── GRU gate bias BRAM write (Step F) ─────────────────────────────────────────
  output logic [10:0] gru_bias_bram_wr_addr,
  output logic [31:0] gru_bias_bram_wr_data,
  output logic        gru_bias_bram_wr_en,

  //── GRU scale LUTRAM write (Step G) ───────────────────────────────────────────
  output logic  [2:0] gru_scale_lut_sel,
  output logic  [8:0] gru_scale_lut_addr,
  output logic [15:0] gru_scale_lut_wdata,
  output logic        gru_scale_lut_we,

  //── GRU wp_proj BRAM write (Step H) ──────────────────────────────────────────
  output logic [10:0] wp_proj_bram_wr_addr,
  output logic [31:0] wp_proj_bram_wr_data,
  output logic        wp_proj_bram_wr_en,

  //── Pos emb BRAM write ────────────────────────────────────────────────────────
  output logic [13:0] posemb_bram_wr_addr,
  output logic [63:0] posemb_bram_wr_data,
  output logic        posemb_bram_wr_en,

  //── Status ────────────────────────────────────────────────────────────────────
  output logic        gru_weights_loaded
);

  //============================================================================
  // FSM States
  //============================================================================
  localparam logic [4:0] WL_IDLE        = 5'd0;
  localparam logic [4:0] WL_STATIC_A    = 5'd1;
  localparam logic [4:0] WL_STATIC_B    = 5'd2;
  localparam logic [4:0] WL_STATIC_C    = 5'd3;
  localparam logic [4:0] WL_STATIC_DONE = 5'd4;
  localparam logic [4:0] WL_WM_HDR      = 5'd5;
  localparam logic [4:0] WL_WM_OBJ      = 5'd6;
  localparam logic [4:0] WL_WM_LANE     = 5'd7;
  localparam logic [4:0] WL_WM_DONE     = 5'd8;
  localparam logic [4:0] WL_POSEMB      = 5'd9;
  localparam logic [4:0] WL_POSEMB_DONE = 5'd10;
  localparam logic [4:0] WL_GRU_D       = 5'd11;
  localparam logic [4:0] WL_GRU_E       = 5'd12;
  localparam logic [4:0] WL_GRU_F       = 5'd13;
  localparam logic [4:0] WL_GRU_G       = 5'd14;
  localparam logic [4:0] WL_GRU_DONE    = 5'd15;
  localparam logic [4:0] WL_BERT_DMA    = 5'd16;
  localparam logic [4:0] WL_BERT_DONE   = 5'd17;
  localparam logic [4:0] WL_GRU_H       = 5'd18;  // Step H: wp_proj BRAM load

  logic [4:0] wl_state;
  logic [4:0] wl_state_prev;
  logic       wl_state_x_seen;

  //============================================================================
  // AXI / burst tracking
  //============================================================================
  logic [16:0] beat_count;
  logic [16:0] target_beats;
  logic [11:0] txn_count;
  logic [11:0] txn_target;
  logic [31:0] cur_base_addr;
  logic        ar_pending;
  logic        bert_start_pending;
  logic        bert_wload_req; // one-shot guard while bert_wload_start is held high

  //============================================================================
  // Write-expansion signals  (FIX: core of the 1/4-count bug fix)
  //============================================================================
  logic [127:0] rdata_latch;   // latched AXI beat data
  logic         write_busy;    // high while expanding 1 beat → N writes
  logic         bert_write_busy; // dedicated BERT URAM beat expander
  logic  [1:0]  word_idx;      // 0..3  — selects 32-bit word for BRAM writes
  logic         sub_beat;      // 0/1   — selects 64-bit half for URAM writes

  //============================================================================
  // BRAM write counters  (word-granularity)
  //============================================================================
  logic [14:0] scale_wr_cnt;   // 0..16383  (BERT V2 PARAM[0..16383], 4096 beats)
  logic [15:0] bias_wr_cnt;    // 0..32767  (BERT V2 PARAM[16384..49151], 8192 beats)
  logic [13:0] ln_wr_cnt;      // 0..8191   (8192 words = 2048 beats)
  logic [11:0] obj_wr_cnt;     // 0..2399
  logic  [9:0] lane_wr_cnt;    // 0..639
  logic [10:0] wout_wr_cnt;
  logic [11:0] grubias_wr_cnt;
  logic [10:0] wp_proj_wr_cnt;  // 0..1535 (1536 FP32 words = 6144 bytes)
  logic [13:0] posemb_wr_cnt;
  logic [17:0] uram_wr_cnt;    // 0..196607 (BERT) / 0..98303 (GRU-D)
  logic [11:0] bert_txn_count; // 0..383 (BERT: 384 bursts x 256 beats)

  // Beat-interleaved URAM address helper for GRU-D writes (N=32 layout).
  // uram_wr_cnt decoding for GRU-D:
  //   [0]     = sub_beat (0→bank A even beat, 1→bank B odd beat)
  //   [4:1]   = beat_pair (0..15)
  //   [12:5]  = row[7:0]
  //   [13]    = row[8]
  //   [17:14] = mat (0..5)
  // Bank A: abs_block = 48 + mat*2 + row[8];  Bank B: 60 + mat*2 + row[8]
  // within = {row[7:0], beat_pair} = {uram_wr_cnt[12:5], uram_wr_cnt[4:1]}
  logic [6:0] wl_gru_abs_block;
  assign wl_gru_abs_block = uram_wr_cnt[0]
    ? (7'd60 + {3'b0, uram_wr_cnt[17:14], 1'b0} + {6'b0, uram_wr_cnt[13]})
    : (7'd48 + {3'b0, uram_wr_cnt[17:14], 1'b0} + {6'b0, uram_wr_cnt[13]});

  //============================================================================
  // GRU scale LUT counters
  //============================================================================
  logic [11:0] gru_scale_cnt;
  logic  [2:0] gru_lut_mat;
  logic  [8:0] gru_lut_row;

  //============================================================================
  // WM header latch
  //============================================================================
  logic [31:0] hdr_word0;
  logic [31:0] hdr_word1;
  logic  [1:0] hdr_wr_cnt;

  function automatic logic [31:0] bert_layer_base(input logic [1:0] layer);
    case (layer)
      2'd0:    bert_layer_base = DDR4_BERT_WEIGHT;
      2'd1:    bert_layer_base = DDR4_BERT_WEIGHT + 32'h0018_0000;
      2'd2:    bert_layer_base = DDR4_BERT_WEIGHT + 32'h0030_0000;
      default: bert_layer_base = DDR4_BERT_WEIGHT + 32'h0048_0000;
    endcase
  endfunction

  //============================================================================
  // Fixed AXI outputs
  //============================================================================
  assign m_axi_arsize  = 3'b100;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arid    = 6'd0;
  // FIX: back-pressure during write expansion — slave holds rvalid until rready=1
  assign m_axi_rready  = ~write_busy;

`ifdef WL_DEBUG
  logic [31:0] wl_dbg_hb;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) wl_dbg_hb <= '0;
    else begin
      wl_dbg_hb <= wl_dbg_hb + 1;
      if (wl_dbg_hb % 2000 == 0) begin
        $display("[WL_HB] t=%0t state=%0d scale=%0d bias=%0d ln=%0d obj=%0d lane=%0d arvalid=%0b arready=%0b ar_pending=%0b rvalid=%0b rready=%0b write_busy=%0b word_idx=%0d",
          $time, wl_state, scale_wr_cnt, bias_wr_cnt, ln_wr_cnt, obj_wr_cnt, lane_wr_cnt,
          m_axi_arvalid, m_axi_arready, ar_pending, m_axi_rvalid, m_axi_rready, write_busy, word_idx);
      end
    end
  end
`endif

  //============================================================================
  // Main FSM
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wl_state              <= WL_IDLE;
      wl_state_prev         <= WL_IDLE;
      wl_state_x_seen       <= 1'b0;
      m_axi_arvalid      <= 1'b0;
      m_axi_araddr       <= '0;
      m_axi_arlen        <= 8'd0;
      static_boot_done   <= 1'b0;
      wm_fetch_done      <= 1'b0;
      posemb_dma_done    <= 1'b0;
      gru_wload_done     <= 1'b0;
      bert_wload_done    <= 1'b0;
      gru_weights_loaded <= 1'b0;
      uram_copy_active   <= 1'b0;
      beat_count         <= '0;
      target_beats       <= '0;
      txn_count          <= '0;
      txn_target         <= '0;
      sub_beat           <= 1'b0;
      word_idx           <= 2'd0;
      write_busy         <= 1'b0;   // FIX: new signal
      bert_write_busy    <= 1'b0;
      rdata_latch        <= '0;     // FIX: new signal
      scale_wr_cnt       <= '0;
      bias_wr_cnt        <= '0;
      ln_wr_cnt          <= '0;
      obj_wr_cnt         <= '0;
      lane_wr_cnt        <= '0;
      wout_wr_cnt        <= '0;
      grubias_wr_cnt     <= '0;
      wp_proj_wr_cnt     <= '0;
      posemb_wr_cnt      <= '0;
      uram_wr_cnt        <= '0;
      gru_lut_mat        <= '0;
      gru_lut_row        <= '0;
      gru_scale_cnt      <= '0;
      hdr_wr_cnt         <= '0;
      wm_num_objects     <= '0;
      wm_num_lanes       <= '0;
      ar_pending         <= 1'b0;
      bert_start_pending <= 1'b0;
      bert_wload_req     <= 1'b0;
      scale_bram_wr_en   <= 1'b0;
      bias_bram_wr_en    <= 1'b0;
      ln_bram_wr_en      <= 1'b0;
      hdr_bram_wr_en     <= 1'b0;
      obj_bram_wr_en     <= 1'b0;
      lane_bram_wr_en    <= 1'b0;
      wout_bram_wr_en    <= 1'b0;
      gru_bias_bram_wr_en<= 1'b0;
      gru_scale_lut_we   <= 1'b0;
      wp_proj_bram_wr_en <= 1'b0;
      posemb_bram_wr_en  <= 1'b0;
      wl_uram_we         <= 1'b0;
    end else if (idle_sanitize) begin
      wl_state            <= WL_IDLE;
      m_axi_arvalid       <= 1'b0;
      ar_pending          <= 1'b0;
      write_busy          <= 1'b0;
      bert_write_busy     <= 1'b0;
      bert_start_pending  <= 1'b0;
      bert_wload_req      <= 1'b0;
      sub_beat            <= 1'b0;
      wl_uram_we          <= 1'b0;
      scale_bram_wr_en    <= 1'b0;
      bias_bram_wr_en     <= 1'b0;
      ln_bram_wr_en       <= 1'b0;
      hdr_bram_wr_en      <= 1'b0;
      obj_bram_wr_en      <= 1'b0;
      lane_bram_wr_en     <= 1'b0;
      wout_bram_wr_en     <= 1'b0;
      gru_bias_bram_wr_en <= 1'b0;
      gru_scale_lut_we    <= 1'b0;
      wp_proj_bram_wr_en  <= 1'b0;
      posemb_bram_wr_en   <= 1'b0;
      wm_fetch_done       <= 1'b0;
      posemb_dma_done     <= 1'b0;
      gru_wload_done      <= 1'b0;
      bert_wload_done     <= 1'b0;
      uram_copy_active    <= 1'b0;
    end else begin
      // Keep the FSM register explicitly driven every cycle. This also
      // recovers to IDLE if the simulator ever corrupts the state register.
      wl_state            <= (((^wl_state) === 1'bx) ? WL_IDLE : wl_state);

      //------------------------------------------------------------------------
      // Clear one-cycle pulse outputs
      //------------------------------------------------------------------------
      wm_fetch_done       <= 1'b0;
      posemb_dma_done     <= 1'b0;
      gru_wload_done      <= 1'b0;
      bert_wload_done     <= 1'b0;
      scale_bram_wr_en    <= 1'b0;
      bias_bram_wr_en     <= 1'b0;
      ln_bram_wr_en       <= 1'b0;
      hdr_bram_wr_en      <= 1'b0;
      obj_bram_wr_en      <= 1'b0;
      lane_bram_wr_en     <= 1'b0;
      wout_bram_wr_en     <= 1'b0;
      gru_bias_bram_wr_en <= 1'b0;
      gru_scale_lut_we    <= 1'b0;
      wp_proj_bram_wr_en  <= 1'b0;
      posemb_bram_wr_en   <= 1'b0;
      wl_uram_we          <= 1'b0;

      //------------------------------------------------------------------------
      // AXI AR channel: deassert after handshake
      //------------------------------------------------------------------------
      if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arvalid <= 1'b0;
        ar_pending    <= 1'b1;
      end
      if (m_axi_rvalid && ((m_axi_arlen == 8'd0) || m_axi_rlast)) begin
        ar_pending <= 1'b0;
      end
      bert_start_pending <= 1'b0;
      bert_wload_req     <= 1'b0;
      bert_write_busy    <= 1'b0;
      if ((^wl_state) === 1'bx) begin
        wl_state      <= WL_IDLE;
        wl_state_prev <= WL_IDLE;
      end else begin
        wl_state_prev <= wl_state;
      end

      //========================================================================
      case (wl_state)
      //========================================================================

        //----------------------------------------------------------------------
        WL_IDLE: begin
          uram_copy_active <= 1'b0;
          write_busy       <= 1'b0;
          bert_write_busy  <= 1'b0;
          priority case (1'b1)
            static_boot_start: begin
              wl_state         <= WL_STATIC_A;
              cur_base_addr <= DDR4_PARAM_A;   // BERT V2: PARAM[0..16383]
              scale_wr_cnt  <= 15'd0;
              word_idx      <= 2'd0;
            end

            wm_fetch_start: begin
              wl_state         <= WL_WM_HDR;
              cur_base_addr <= wm_ddr_base;
              hdr_wr_cnt    <= 2'd0;
            end

            posemb_dma_start: begin
              wl_state         <= WL_POSEMB;
              cur_base_addr <= DDR4_POS_EMB;
              target_beats  <= 17'd8192;
              txn_target    <= 12'd32;
              txn_count     <= 12'd0;
              beat_count    <= 17'd0;
              posemb_wr_cnt <= 14'd0;
              sub_beat      <= 1'b0;
            end

            gru_wload_start: begin
              wl_state            <= WL_GRU_D;
              cur_base_addr    <= DDR4_GRU_WEIGHT;
              txn_count        <= 12'd0;
              uram_wr_cnt      <= 18'd0;
              sub_beat         <= 1'b0;
              write_busy       <= 1'b0;
              bert_write_busy  <= 1'b0;
              ar_pending       <= 1'b0;
              m_axi_arvalid    <= 1'b0;
              uram_copy_active <= 1'b1;
            end

            // BUG-FIX: entry point was missing entirely (see WL_BERT_DMA
            // comment). Lowest priority per the module header's documented
            // order (line 14): "... > gru_wload_start > bert_wload_start".
            bert_wload_start: begin
              wl_state         <= WL_BERT_DMA;
              cur_base_addr    <= bert_layer_base(bert_wload_layer);
              bert_txn_count   <= 12'd0;
              uram_wr_cnt      <= 18'd0;
              sub_beat         <= 1'b0;
              write_busy       <= 1'b0;
              ar_pending       <= 1'b0;
              m_axi_arvalid    <= 1'b0;
              uram_copy_active <= 1'b1;
            end

            default: begin end
          endcase
        end

        //======================================================================
        // STATIC BOOT — Steps A / B / C
        //
        // FIX: replaced for-loop with write_busy + word_idx sequencer.
        //      Each 128-bit AXI beat is latched → 4 × 32-bit BRAM writes
        //      over 4 consecutive clock cycles.
        //      m_axi_rready = ~write_busy provides back-pressure.
        //======================================================================

        //----------------------------------------------------------------------
        // WL_STATIC_A: Scale BRAM — 2304 beats → 9216 32-bit words
        //----------------------------------------------------------------------
        WL_STATIC_A: begin
          if (!write_busy) begin
            // Issue next single-beat AR when bus is free
            if (!m_axi_arvalid && !ar_pending && scale_wr_cnt < 15'd16384) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= cur_base_addr + {scale_wr_cnt, 2'd0}; // word×4B
              m_axi_arlen   <= 8'd0;
            end
            // Latch incoming beat and start write expansion
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              word_idx    <= 2'd0;
            end
          end else begin
            // Write expansion: one 32-bit word per clock cycle
            scale_bram_wr_en   <= 1'b1;
            scale_bram_wr_addr <= scale_wr_cnt[13:0] + 14'(word_idx);
            scale_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy   <= 1'b0;
              scale_wr_cnt <= scale_wr_cnt + 15'd4;
              // Transition after the last group (words 9212..9215)
              if (scale_wr_cnt == 15'd16380) begin
                wl_state         <= WL_STATIC_B;
                cur_base_addr <= DDR4_PARAM_B;   // BERT V2: PARAM[16384..49151]
                bias_wr_cnt   <= 16'd0;
              end
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_STATIC_B: Bias BRAM — 4608 beats → 18432 32-bit words
        //----------------------------------------------------------------------
        WL_STATIC_B: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && bias_wr_cnt < 16'd32768) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= cur_base_addr + {bias_wr_cnt, 2'd0};
              m_axi_arlen   <= 8'd0;
            end
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              word_idx    <= 2'd0;
            end
          end else begin
            bias_bram_wr_en   <= 1'b1;
            bias_bram_wr_addr <= bias_wr_cnt[14:0] + 15'(word_idx);
            bias_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy  <= 1'b0;
              bias_wr_cnt <= bias_wr_cnt + 16'd4;
              if (bias_wr_cnt == 16'd32764) begin
                wl_state         <= WL_STATIC_C;
                cur_base_addr <= DDR4_PARAM_C;   // BERT V2: PARAM[49152..57343]
                ln_wr_cnt     <= 14'd0;
              end
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_STATIC_C: LN BRAM — 2048 beats → 8192 32-bit words
        //----------------------------------------------------------------------
        WL_STATIC_C: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && ln_wr_cnt < 14'd8192) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= cur_base_addr + {ln_wr_cnt, 2'd0};
              m_axi_arlen   <= 8'd0;
            end
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              word_idx    <= 2'd0;
            end
          end else begin
            ln_bram_wr_en   <= 1'b1;
            ln_bram_wr_addr <= ln_wr_cnt[12:0] + 13'(word_idx);
            ln_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy <= 1'b0;
              ln_wr_cnt  <= ln_wr_cnt + 14'd4;
              if (ln_wr_cnt == 14'd8188) begin
                wl_state <= WL_STATIC_DONE;
              end
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        WL_STATIC_DONE: begin
          static_boot_done <= 1'b1;
          wl_state            <= WL_IDLE;
        end

        //======================================================================
        // WM_FETCH — HDR / OBJ / LANE
        //
        // Same write_busy + word_idx pattern.
        //======================================================================

        //----------------------------------------------------------------------
        // WL_WM_HDR: 1 beat (16B) → 4 header words
        //----------------------------------------------------------------------
        WL_WM_HDR: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= cur_base_addr;
              m_axi_arlen   <= 8'd0;
            end
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              word_idx    <= 2'd0;
              // Latch num_objects / num_lanes immediately from live rdata
              wm_num_objects <= (m_axi_rdata[31:0]  > 32'd200) ? 8'd200 : m_axi_rdata[7:0];
              wm_num_lanes   <= (m_axi_rdata[63:32] > 32'd20)  ? 5'd20  : m_axi_rdata[36:32];
              obj_wr_cnt     <= 12'd0;
            end
          end else begin
            // Write 4 header words to hdr_bram
            hdr_bram_wr_en   <= 1'b1;
            hdr_bram_wr_addr <= 2'(word_idx);
            hdr_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy <= 1'b0;
              wl_state      <= WL_WM_OBJ;
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_WM_OBJ: min(num_obj,200) × 12 words  (12 words = 3 beats / obj)
        //----------------------------------------------------------------------
        WL_WM_OBJ: begin
          if (!write_busy) begin
            // Transition guard: check completion or zero-object corner case
            if (obj_wr_cnt >= ({4'd0, wm_num_objects} * 12'd12) || wm_num_objects == 8'd0) begin
              lane_wr_cnt   <= 10'd0;
              cur_base_addr <= wm_ddr_base + 32'h0000_2590;
              wl_state         <= WL_WM_LANE;
            end else begin
              if (!m_axi_arvalid && !ar_pending) begin
                m_axi_arvalid <= 1'b1;
                m_axi_araddr  <= wm_ddr_base + 32'd16 + {obj_wr_cnt, 2'd0};
                m_axi_arlen   <= 8'd0;
              end
              if (m_axi_rvalid) begin
                rdata_latch <= m_axi_rdata;
                write_busy  <= 1'b1;
                word_idx    <= 2'd0;
              end
            end
          end else begin
            obj_bram_wr_en   <= 1'b1;
            obj_bram_wr_addr <= obj_wr_cnt[11:0] + 12'(word_idx);
            obj_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy <= 1'b0;
              obj_wr_cnt <= obj_wr_cnt + 12'd4;
`ifdef WL_DEBUG
              $display("[WL_DBG OBJ] t=%0t obj_wr_cnt->%0d target=%0d wm_num_objects=%0d", $time, obj_wr_cnt+12'd4, ({4'd0,wm_num_objects}*12'd12), wm_num_objects);
`endif
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_WM_LANE: min(num_lanes,20) × 32 words  (32 words = 8 beats / lane)
        //----------------------------------------------------------------------
        WL_WM_LANE: begin
          if (!write_busy) begin
            if (lane_wr_cnt >= ({5'd0, wm_num_lanes} * 10'd32) || wm_num_lanes == 5'd0) begin
              wl_state <= WL_WM_DONE;
            end else begin
              if (!m_axi_arvalid && !ar_pending) begin
                m_axi_arvalid <= 1'b1;
                m_axi_araddr  <= cur_base_addr + {lane_wr_cnt, 2'd0};
                m_axi_arlen   <= 8'd0;
              end
              if (m_axi_rvalid) begin
                rdata_latch <= m_axi_rdata;
                write_busy  <= 1'b1;
                word_idx    <= 2'd0;
              end
            end
          end else begin
            lane_bram_wr_en   <= 1'b1;
            lane_bram_wr_addr <= lane_wr_cnt[9:0] + 10'(word_idx);
            lane_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy  <= 1'b0;
              lane_wr_cnt <= lane_wr_cnt + 10'd4;
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        WL_WM_DONE: begin
          wm_fetch_done <= 1'b1;
          wl_state         <= WL_IDLE;
        end

        //======================================================================
        // WL_POSEMB: 8192 beats (128KB), 32 × 256-beat bursts
        // Each 128-bit beat → 2 × 64-bit posemb BRAM writes (sub_beat toggle)
        // NOTE: posemb is NOT exercised by the active test suite; logic unchanged
        //       from original to preserve existing behaviour.
        //======================================================================
        WL_POSEMB: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && txn_count < txn_target) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= DDR4_POS_EMB + {txn_count, 12'd0};
              m_axi_arlen   <= 8'd255;
              txn_count     <= txn_count + 12'd1;
            end
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              sub_beat    <= 1'b0;
            end
          end else begin
            posemb_bram_wr_en   <= 1'b1;
            posemb_bram_wr_addr <= posemb_wr_cnt[13:0];
            posemb_bram_wr_data <= sub_beat ? rdata_latch[127:64] : rdata_latch[63:0];
            posemb_wr_cnt       <= posemb_wr_cnt + 14'd1;
            if (sub_beat) begin
              write_busy <= 1'b0;
              beat_count <= beat_count + 17'd1;
              if (beat_count == target_beats - 17'd1) begin
                wl_state <= WL_POSEMB_DONE;
              end
            end else begin
              sub_beat <= 1'b1;
            end
          end
        end

        WL_POSEMB_DONE: begin
          posemb_dma_done <= 1'b1;
          write_busy      <= 1'b0;
          wl_state           <= WL_IDLE;
        end

        //======================================================================
        // GRU LOAD — Steps D / E / F / G
        //======================================================================

        //----------------------------------------------------------------------
        // WL_GRU_D: GRU weights → URAM 48..71 (768 KB, 192 × 256-beat bursts)
        //
        // FIX: write_busy + sub_beat → 2 × 64-bit writes per 128-bit beat
        //      Total URAM writes: 49152 beats × 2 = 98304
        //      Termination: uram_wr_cnt == 98303 on second sub-write
        //----------------------------------------------------------------------
        WL_GRU_D: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && txn_count < 12'd192) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= DDR4_GRU_WEIGHT + {txn_count, 12'd0};
              m_axi_arlen   <= 8'd255;
              txn_count     <= txn_count + 12'd1;
            end
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              sub_beat    <= 1'b0;
            end
          end else begin
            wl_uram_addr  <= {wl_gru_abs_block, uram_wr_cnt[12:5], uram_wr_cnt[4:1]};
            wl_uram_wdata <= sub_beat ? rdata_latch[127:64] : rdata_latch[63:0];
            wl_uram_we    <= 1'b1;
            uram_wr_cnt   <= uram_wr_cnt + 18'd1;
`ifndef SYNTHESIS
            if (uram_wr_cnt <= 18'd7)
              $display("[DBG WL_D INIT] uram_wr_cnt=%0d sub=%0b abs_blk=%0d addr=0x%05h data=%016h t=%0t",
                       uram_wr_cnt, sub_beat, wl_gru_abs_block,
                       {wl_gru_abs_block, uram_wr_cnt[12:5], uram_wr_cnt[4:1]},
                       sub_beat ? rdata_latch[127:64] : rdata_latch[63:0], $time);
            // Trace near burst-191: uram_wr_cnt=97792 is beat 0 of burst 191
            if (uram_wr_cnt >= 18'd97790 && uram_wr_cnt <= 18'd97796)
              $display("[DBG WL_D TRACE] uram_wr_cnt=%0d sub=%0b txn=%0d t=%0t", uram_wr_cnt, sub_beat, txn_count, $time);
            // Trace the last 6 sub_beats leading to transition
            if (uram_wr_cnt >= 18'd98298 && uram_wr_cnt < 18'd98303)
              $display("[DBG WL_D TRAIL] uram=%0d sub=%0b rvalid=%0b rlast=%0b ar_pend=%0b t=%0t",
                       uram_wr_cnt, sub_beat, m_axi_rvalid, m_axi_rlast, ar_pending, $time);
            if (uram_wr_cnt == 18'd98303)
              $display("[DBG WL_D END] TRANSITION uram=%0d sub=%0b txn=%0d rlast=%0b ar_pend=%0b t=%0t",
                       uram_wr_cnt, sub_beat, txn_count, m_axi_rlast, ar_pending, $time);
`endif
            if (sub_beat) begin
              write_busy <= 1'b0;
              if (uram_wr_cnt == 18'd98303) begin
                uram_wr_cnt   <= 18'd0;
                txn_count     <= 12'd0;
                wout_wr_cnt   <= 11'd0;
                ar_pending    <= 1'b0;  // slave still serving burst-191; force clear so WL_E guard works
                wl_state      <= WL_GRU_E;
              end
            end else begin
              sub_beat <= 1'b1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_GRU_E: GRU W_out + b_out (1026 FP32 words, 257 single-beat txns)
        // Fixed: write_busy + word_idx sequencer — was for-loop NBA bug that
        // dropped 3 out of every 4 words (only last NBA assignment won).
        //----------------------------------------------------------------------
        WL_GRU_E: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && wout_wr_cnt < 11'd1028) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= DDR4_GRU_WOUT_STAG + {wout_wr_cnt, 2'd0};
              m_axi_arlen   <= 8'd0;
`ifndef SYNTHESIS
              if (wout_wr_cnt < 11'd4)
                $display("[DBG WL_E AR] wout_wr_cnt=%0d araddr_next=0x%08h",
                         wout_wr_cnt, DDR4_GRU_WOUT_STAG + {wout_wr_cnt, 2'd0});
`endif
            end
`ifndef SYNTHESIS
            if (wout_wr_cnt < 11'd4 && m_axi_rvalid)
              $display("[DBG WL_E PRE] wout_wr_cnt=%0d rvalid=%0b ar_pending=%0b rlast=%0b t=%0t",
                       wout_wr_cnt, m_axi_rvalid, ar_pending, m_axi_rlast, $time);
`endif
            if (m_axi_rvalid && ar_pending) begin  // guard: ar_pending=0 at WL_D→E; blocks stale burst-191 rvalid
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              word_idx    <= 2'd0;
`ifndef SYNTHESIS
              if (wout_wr_cnt < 11'd4)
                $display("[DBG WL_E LATCH] wout_wr_cnt=%0d rdata=0x%032h t=%0t",
                         wout_wr_cnt, m_axi_rdata, $time);
`endif
            end
          end else begin
            // One FP32 per cycle; skip addresses beyond 1025 (b_out at 1024..1025)
            if (wout_wr_cnt + 11'(word_idx) <= 11'd1025) begin
              wout_bram_wr_en   <= 1'b1;
              wout_bram_wr_addr <= wout_wr_cnt[10:0] + 11'(word_idx);
              wout_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
`ifndef SYNTHESIS
              if (wout_wr_cnt == 11'd0 && word_idx <= 2'd1)
                $display("[DBG WL_E] wout_bram[%0d] <= %08h",
                         wout_wr_cnt[10:0]+11'(word_idx), rdata_latch[word_idx*32+:32]);
              if (wout_wr_cnt == 11'd1024)
                $display("[DBG WL_E] wout_bram[%0d] (bout) <= %08h",
                         wout_wr_cnt[10:0]+11'(word_idx), rdata_latch[word_idx*32+:32]);
`endif
            end
            if (word_idx == 2'd3) begin
              write_busy  <= 1'b0;
              wout_wr_cnt <= wout_wr_cnt + 11'd4;
              if (wout_wr_cnt >= 11'd1024) begin
                grubias_wr_cnt <= 12'd0;
                wl_state       <= WL_GRU_F;
              end
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_GRU_F: GRU gate biases (2048 FP32 words, 8 KB)
        // Fixed: write_busy + word_idx sequencer — was for-loop NBA bug.
        //----------------------------------------------------------------------
        WL_GRU_F: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && grubias_wr_cnt < 12'd2048) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= DDR4_GRU_BIAS + {grubias_wr_cnt, 2'd0};
              m_axi_arlen   <= 8'd0;
            end
            if (m_axi_rvalid && ar_pending) begin  // guard: ar_pending=0 at E→F; blocks stale WL_GRU_E rvalid
              rdata_latch    <= m_axi_rdata;
              write_busy     <= 1'b1;
              word_idx       <= 2'd0;
            end
          end else begin
            gru_bias_bram_wr_en   <= 1'b1;
            gru_bias_bram_wr_addr <= grubias_wr_cnt[10:0] + 11'(word_idx);
            gru_bias_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
`ifndef SYNTHESIS
            if (grubias_wr_cnt == 12'd0 && word_idx <= 2'd1)
              $display("[DBG WL_F] gru_bias[%0d] <= %08h",
                       grubias_wr_cnt[10:0]+11'(word_idx), rdata_latch[word_idx*32+:32]);
`endif
            if (word_idx == 2'd3) begin
              write_busy     <= 1'b0;
              grubias_wr_cnt <= grubias_wr_cnt + 12'd4;
              if (grubias_wr_cnt >= 12'd2044) begin
                gru_scale_cnt <= 12'd0;
                gru_lut_mat   <= 3'd0;
                gru_lut_row   <= 9'd0;
                wl_state      <= WL_GRU_G;
              end
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_GRU_G: GRU scale/ZP LUTRAM (3072 × 16-bit entries, 6 KB)
        // Fixed: write_busy + word_idx + sub_beat for 8 entries per beat.
        // {word_idx[1:0], sub_beat} = 3-bit entry index 0..7 within each beat.
        //----------------------------------------------------------------------
        WL_GRU_G: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && gru_scale_cnt < 12'd3072) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= DDR4_GRU_SCALE + {gru_scale_cnt, 1'd0};
              m_axi_arlen   <= 8'd0;
            end
            if (m_axi_rvalid && ar_pending) begin  // guard: ar_pending=0 at F→G; blocks stale WL_GRU_F rvalid
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              word_idx    <= 2'd0;
              sub_beat    <= 1'b0;
            end
          end else begin
            // Write one 16-bit scale/ZP entry per cycle
            gru_scale_lut_we    <= 1'b1;
            gru_scale_lut_sel   <= gru_lut_mat;
            gru_scale_lut_addr  <= gru_lut_row;
            gru_scale_lut_wdata <= sub_beat
              ? rdata_latch[word_idx*32+16 +: 16]
              : rdata_latch[word_idx*32    +: 16];
`ifndef SYNTHESIS
            if (gru_lut_mat == 3'd0 && gru_lut_row < 9'd4)
              $display("[DBG WL_G] scale_lut[0][%0d] <= %04h  (sub=%0b wi=%0d)",
                       gru_lut_row,
                       sub_beat ? rdata_latch[word_idx*32+16+:16] : rdata_latch[word_idx*32+:16],
                       sub_beat, word_idx);
`endif
            // Advance row/mat
            if (gru_lut_row == 9'd511) begin
              gru_lut_row <= 9'd0;
              gru_lut_mat <= gru_lut_mat + 3'd1;
            end else begin
              gru_lut_row <= gru_lut_row + 9'd1;
            end
            // Sub-beat (low 16 bits) → then word_idx (next 32-bit word)
            if (sub_beat) begin
              sub_beat <= 1'b0;
              if (word_idx == 2'd3) begin
                write_busy    <= 1'b0;
                gru_scale_cnt <= gru_scale_cnt + 12'd8;
                if (gru_scale_cnt >= 12'd3064) begin
                  wp_proj_wr_cnt <= 11'd0;
                  wl_state       <= WL_GRU_H;
                end
              end else begin
                word_idx <= word_idx + 2'd1;
              end
            end else begin
              sub_beat <= 1'b1;
            end
          end
        end

        //----------------------------------------------------------------------
        // WL_GRU_H: wp_proj BRAM — 1536 FP32 words (6144 B) from DDR4_GRU_WP_PROJ
        // Uses write_busy + word_idx pattern (correct 4-word-per-beat sequencing).
        //----------------------------------------------------------------------
        WL_GRU_H: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && wp_proj_wr_cnt < 11'd1536) begin
              m_axi_arvalid <= 1'b1;
              m_axi_araddr  <= DDR4_GRU_WP_PROJ + {wp_proj_wr_cnt, 2'd0};
              m_axi_arlen   <= 8'd0;
            end
            if (m_axi_rvalid && ar_pending) begin  // guard: ar_pending=0 at G→H; blocks stale WL_GRU_G rvalid
              rdata_latch    <= m_axi_rdata;
              write_busy     <= 1'b1;
              word_idx       <= 2'd0;
            end
          end else begin
            wp_proj_bram_wr_en   <= 1'b1;
            wp_proj_bram_wr_addr <= wp_proj_wr_cnt[10:0] + 11'(word_idx);
            wp_proj_bram_wr_data <= rdata_latch[word_idx*32 +: 32];
            if (word_idx == 2'd3) begin
              write_busy     <= 1'b0;
              wp_proj_wr_cnt <= wp_proj_wr_cnt + 11'd4;
              if (wp_proj_wr_cnt == 11'd1532) begin
                wl_state <= WL_GRU_DONE;
              end
            end else begin
              word_idx <= word_idx + 2'd1;
            end
          end
        end

        WL_GRU_DONE: begin
          gru_wload_done     <= 1'b1;
          gru_weights_loaded <= 1'b1;
          uram_copy_active   <= 1'b0;
          wl_state              <= WL_IDLE;
        end

        //----------------------------------------------------------------------
        // BUG-FIX (WL_BERT_DMA was declared but never implemented -- no case
        // arm existed, bert_wload_start had no entry point in WL_IDLE's
        // priority-case, so pulsing it did nothing and bert_wload_done never
        // asserted). Implemented per the address scheme verified against
        // bert_encoder_layer.sv's uram_addr_calc() (the actual, currently-
        // used BERT weight reader -- wo_projection.sv's separate addressing
        // is DEAD CODE, replaced by an inline 128-parallel path, see
        // bert_encoder_layer.sv:577,834).
        //
        // uram_addr_calc: base_blk(WQ=0,WK=4,WV=8,WO=12,W1=16+subp*4,
        // W2=32+subp*4), entry_idx=(out_row<<5)|beat, block+=entry_idx>>12,
        // entry_within=entry_idx&0xFFF. Verified: WQ/WK/WV/WO are each
        // 512 rows x 32 beats = 16,384 words (exactly 4 blocks x 4096
        // entries); W1/W2 are 4 sub-passes x 16,384 words each = 65,536
        // words (16 blocks each). Total = 4x16384 + 2x65536 = 196,608
        // words -- matches TEST 5's expected URAM write count exactly.
        //
        // KEY SIMPLIFICATION: DDR4 source is laid out in the SAME linear
        // order as the URAM destination blocks (WQ,WK,WV,WO,W1 x4 subp,
        // W2 x4 subp -- 12 contiguous 16,384-word chunks, chunk*4 = base
        // block, matching uram_addr_calc exactly). This makes a single
        // linear counter (bert_uram_wr_cnt) map DIRECTLY to the 19-bit
        // uram_addr with NO per-matrix bit-shuffle: block=cnt[17:12],
        // entry_within=cnt[11:0] -- i.e. uram_addr = {1'b0, cnt[17:0]}.
        // Per-layer DDR4 size: (4x128KB + 2x512KB) = 1.5MB = bert_layer_
        // base()'s own 0x180000 stride between layers (self-consistent).
        //----------------------------------------------------------------------
        WL_BERT_DMA: begin
          if (!write_busy) begin
            if (!m_axi_arvalid && !ar_pending && bert_txn_count < 12'd384) begin
              m_axi_arvalid <= 1'b1;
              // 384 bursts x 256 beats x 16B/beat = 1,572,864 B = 1.5 MB/layer
              m_axi_araddr  <= cur_base_addr + {bert_txn_count, 12'd0};
              m_axi_arlen   <= 8'd255;
              bert_txn_count <= bert_txn_count + 12'd1;
            end
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              sub_beat    <= 1'b0;
            end
          end else begin
            // Linear address: see comment above -- no per-matrix remap needed
            // because DDR4 source order matches URAM block order exactly.
            wl_uram_addr  <= {1'b0, uram_wr_cnt[17:0]};
            wl_uram_wdata <= sub_beat ? rdata_latch[127:64] : rdata_latch[63:0];
            wl_uram_we    <= 1'b1;
            uram_wr_cnt   <= uram_wr_cnt + 18'd1;
            if (sub_beat) begin
              write_busy <= 1'b0;
              if (uram_wr_cnt == 18'd196607) begin
                uram_wr_cnt    <= 18'd0;
                bert_txn_count <= 12'd0;
                ar_pending     <= 1'b0;  // mirror WL_GRU_D's guard for the next state
                wl_state       <= WL_BERT_DONE;
              end
            end else begin
              sub_beat <= 1'b1;
            end
          end
        end

        WL_BERT_DONE: begin
          bert_wload_done  <= 1'b1;
          uram_copy_active <= 1'b0;
          wl_state         <= WL_IDLE;
        end

        default: wl_state <= WL_IDLE;
      endcase
    end
  end

  //============================================================================
  // Assertions (simulation only)
  //============================================================================
// [Fix AG2] Bat khi ASSERT_ON HOAC dieu kien cu (SIMULATION). Dieu kien viet
// NGAY TAI CHO: macro dinh nghia o tep khac KHONG thay duoc khi xvlog
// bien dich tung tep rieng (da thu thuc nghiem 30/09/2026).
`ifdef ASSERT_ON
  `define _AG_EN_WL
`elsif SIMULATION
  `define _AG_EN_WL
`endif
`ifdef _AG_EN_WL
  initial $display("[AG] assertion BAT: weight_loader.sv %m");
  property p_no_axi_err;
    @(posedge clk) disable iff (!rst_n)
    m_axi_rvalid |-> m_axi_rresp == 2'b00;
  endproperty
  assert property (p_no_axi_err)
    else $error("weight_loader: AXI rresp error = %b", m_axi_rresp);
`endif

endmodule : weight_loader

module weight_loader_wrapper
  import planning_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        static_boot_start,
  output logic        static_boot_done,
  input  logic        wm_fetch_start,
  input  logic [31:0] wm_ddr_base,
  output logic        wm_fetch_done,
  input  logic        posemb_dma_start,
  output logic        posemb_dma_done,
  input  logic        idle_sanitize,
  input  logic        gru_wload_start,
  output logic        gru_wload_done,
  input  logic        bert_wload_start,
  input  logic  [1:0] bert_wload_layer,
  output logic        bert_wload_done,
  output logic [31:0] m_axi_araddr,
  output logic  [7:0] m_axi_arlen,
  output logic  [2:0] m_axi_arsize,
  output logic  [1:0] m_axi_arburst,
  output logic  [5:0] m_axi_arid,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [127:0] m_axi_rdata,
  input  logic  [1:0] m_axi_rresp,
  input  logic  [5:0] m_axi_rid,
  input  logic        m_axi_rvalid,
  input  logic        m_axi_rlast,
  output logic        m_axi_rready,
  output logic [18:0] wl_uram_addr,
  output logic [63:0] wl_uram_wdata,
  output logic        wl_uram_we,
  output logic        uram_copy_active,
  output logic [13:0] scale_bram_wr_addr,
  output logic [31:0] scale_bram_wr_data,
  output logic        scale_bram_wr_en,
  output logic [14:0] bias_bram_wr_addr,
  output logic [31:0] bias_bram_wr_data,
  output logic        bias_bram_wr_en,
  output logic [12:0] ln_bram_wr_addr,
  output logic [31:0] ln_bram_wr_data,
  output logic        ln_bram_wr_en,
  output logic  [1:0] hdr_bram_wr_addr,
  output logic [31:0] hdr_bram_wr_data,
  output logic        hdr_bram_wr_en,
  output logic [11:0] obj_bram_wr_addr,
  output logic [31:0] obj_bram_wr_data,
  output logic        obj_bram_wr_en,
  output logic  [9:0] lane_bram_wr_addr,
  output logic [31:0] lane_bram_wr_data,
  output logic        lane_bram_wr_en,
  output logic  [7:0] wm_num_objects,
  output logic  [4:0] wm_num_lanes,
  output logic [10:0] wout_bram_wr_addr,
  output logic [31:0] wout_bram_wr_data,
  output logic        wout_bram_wr_en,
  output logic [10:0] gru_bias_bram_wr_addr,
  output logic [31:0] gru_bias_bram_wr_data,
  output logic        gru_bias_bram_wr_en,
  output logic  [2:0] gru_scale_lut_sel,
  output logic  [8:0] gru_scale_lut_addr,
  output logic [15:0] gru_scale_lut_wdata,
  output logic        gru_scale_lut_we,
  output logic [10:0] wp_proj_bram_wr_addr,
  output logic [31:0] wp_proj_bram_wr_data,
  output logic        wp_proj_bram_wr_en,
  output logic [13:0] posemb_bram_wr_addr,
  output logic [63:0] posemb_bram_wr_data,
  output logic        posemb_bram_wr_en,
  output logic        gru_weights_loaded
);
  logic       bert_wload_start_q;
  logic [1:0] bert_wload_layer_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bert_wload_start_q <= 1'b0;
      bert_wload_layer_q <= 2'd0;
    end else begin
      bert_wload_start_q <= bert_wload_start;
      if (bert_wload_start) begin
        bert_wload_layer_q <= bert_wload_layer;
      end
    end
  end

  weight_loader u_weight_loader (
    .clk               (clk),
    .rst_n             (rst_n),
    .static_boot_start (static_boot_start),
    .static_boot_done  (static_boot_done),
    .wm_fetch_start    (wm_fetch_start),
    .wm_ddr_base       (wm_ddr_base),
    .wm_fetch_done     (wm_fetch_done),
    .posemb_dma_start  (posemb_dma_start),
    .posemb_dma_done   (posemb_dma_done),
    .idle_sanitize     (idle_sanitize),
    .gru_wload_start   (gru_wload_start),
    .gru_wload_done    (gru_wload_done),
    .bert_wload_start  (bert_wload_start_q),
    .bert_wload_layer  (bert_wload_layer_q),
    .bert_wload_done   (bert_wload_done),
    .m_axi_araddr      (m_axi_araddr),
    .m_axi_arlen       (m_axi_arlen),
    .m_axi_arsize      (m_axi_arsize),
    .m_axi_arburst     (m_axi_arburst),
    .m_axi_arid        (m_axi_arid),
    .m_axi_arvalid     (m_axi_arvalid),
    .m_axi_arready     (m_axi_arready),
    .m_axi_rdata       (m_axi_rdata),
    .m_axi_rresp       (m_axi_rresp),
    .m_axi_rid         (m_axi_rid),
    .m_axi_rvalid      (m_axi_rvalid),
    .m_axi_rlast       (m_axi_rlast),
    .m_axi_rready      (m_axi_rready),
    .wl_uram_addr      (wl_uram_addr),
    .wl_uram_wdata     (wl_uram_wdata),
    .wl_uram_we        (wl_uram_we),
    .uram_copy_active  (uram_copy_active),
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
    .gru_bias_bram_wr_addr(gru_bias_bram_wr_addr),
    .gru_bias_bram_wr_data(gru_bias_bram_wr_data),
    .gru_bias_bram_wr_en(gru_bias_bram_wr_en),
    .gru_scale_lut_sel (gru_scale_lut_sel),
    .gru_scale_lut_addr(gru_scale_lut_addr),
    .gru_scale_lut_wdata(gru_scale_lut_wdata),
    .gru_scale_lut_we  (gru_scale_lut_we),
    .wp_proj_bram_wr_addr(wp_proj_bram_wr_addr),
    .wp_proj_bram_wr_data(wp_proj_bram_wr_data),
    .wp_proj_bram_wr_en  (wp_proj_bram_wr_en),
    .posemb_bram_wr_addr(posemb_bram_wr_addr),
    .posemb_bram_wr_data(posemb_bram_wr_data),
    .posemb_bram_wr_en (posemb_bram_wr_en),
    .gru_weights_loaded(gru_weights_loaded)
  );
endmodule : weight_loader_wrapper

//==============================================================================
// End of File
//==============================================================================
