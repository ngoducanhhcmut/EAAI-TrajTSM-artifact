// =============================================================================
// tb_weight_loader.sv â€” Unit Testbench for weight_loader
// Tests AXI DMA engine: start/done handshaking and BRAM/URAM write outputs
// Smoke test: model AXI slave as always-ready with simple data
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_weight_loader;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk;

  // â”€â”€ DUT ports â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  logic          static_boot_start;
  logic          static_boot_done;

  logic          wm_fetch_start;
  logic [31:0]   wm_ddr_base;
  logic          wm_fetch_done;

  logic          posemb_dma_start;
  logic          posemb_dma_done;

  logic          gru_wload_start;
  logic          gru_wload_done;

  logic          bert_wload_start;
  logic  [1:0]   bert_wload_layer;
  logic          bert_wload_done;

  // AXI4 master (DMA read channel)
  logic [31:0]   m_axi_araddr;
  logic  [7:0]   m_axi_arlen;
  logic  [2:0]   m_axi_arsize;
  logic  [1:0]   m_axi_arburst;
  logic  [5:0]   m_axi_arid;
  logic          m_axi_arvalid;
  logic          m_axi_arready;
  logic [127:0]  m_axi_rdata;
  logic  [1:0]   m_axi_rresp;
  logic  [5:0]   m_axi_rid;
  logic          m_axi_rvalid;
  logic          m_axi_rlast;
  logic          m_axi_rready;

  // URAM write port
  logic [18:0]   wl_uram_addr;
  logic [63:0]   wl_uram_wdata;
  logic          wl_uram_we;
  logic          uram_copy_active;

  // Scale/bias/LN BRAMs
  logic [13:0]   scale_bram_wr_addr;
  logic [31:0]   scale_bram_wr_data;
  logic          scale_bram_wr_en;
  logic [14:0]   bias_bram_wr_addr;
  logic [31:0]   bias_bram_wr_data;
  logic          bias_bram_wr_en;
  logic [12:0]   ln_bram_wr_addr;
  logic [31:0]   ln_bram_wr_data;
  logic          ln_bram_wr_en;

  // WM BRAMs
  logic  [1:0]   hdr_bram_wr_addr;
  logic [31:0]   hdr_bram_wr_data;
  logic          hdr_bram_wr_en;
  logic [11:0]   obj_bram_wr_addr;
  logic [31:0]   obj_bram_wr_data;
  logic          obj_bram_wr_en;
  logic  [9:0]   lane_bram_wr_addr;
  logic [31:0]   lane_bram_wr_data;
  logic          lane_bram_wr_en;
  logic  [7:0]   wm_num_objects;
  logic  [4:0]   wm_num_lanes;

  // GRU BRAMs
  logic [10:0]   wout_bram_wr_addr;
  logic [31:0]   wout_bram_wr_data;
  logic          wout_bram_wr_en;
  logic [10:0]   gru_bias_bram_wr_addr;
  logic [31:0]   gru_bias_bram_wr_data;
  logic          gru_bias_bram_wr_en;
  logic  [2:0]   gru_scale_lut_sel;
  logic  [8:0]   gru_scale_lut_addr;
  logic [15:0]   gru_scale_lut_wdata;
  logic          gru_scale_lut_we;

  // Posemb BRAM
  logic [13:0]   posemb_bram_wr_addr;
  logic [63:0]   posemb_bram_wr_data;
  logic          posemb_bram_wr_en;

  logic          gru_weights_loaded;

  weight_loader dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .static_boot_start     (static_boot_start),
    .static_boot_done      (static_boot_done),
    .wm_fetch_start        (wm_fetch_start),
    .wm_ddr_base           (wm_ddr_base),
    .wm_fetch_done         (wm_fetch_done),
    .posemb_dma_start      (posemb_dma_start),
    .posemb_dma_done       (posemb_dma_done),
    .gru_wload_start       (gru_wload_start),
    .gru_wload_done        (gru_wload_done),
    .bert_wload_start      (bert_wload_start),
    .bert_wload_layer      (bert_wload_layer),
    .bert_wload_done       (bert_wload_done),
    .m_axi_araddr          (m_axi_araddr),
    .m_axi_arlen           (m_axi_arlen),
    .m_axi_arsize          (m_axi_arsize),
    .m_axi_arburst         (m_axi_arburst),
    .m_axi_arid            (m_axi_arid),
    .m_axi_arvalid         (m_axi_arvalid),
    .m_axi_arready         (m_axi_arready),
    .m_axi_rdata           (m_axi_rdata),
    .m_axi_rresp           (m_axi_rresp),
    .m_axi_rid             (m_axi_rid),
    .m_axi_rvalid          (m_axi_rvalid),
    .m_axi_rlast           (m_axi_rlast),
    .m_axi_rready          (m_axi_rready),
    .wl_uram_addr          (wl_uram_addr),
    .wl_uram_wdata         (wl_uram_wdata),
    .wl_uram_we            (wl_uram_we),
    .uram_copy_active      (uram_copy_active),
    .scale_bram_wr_addr    (scale_bram_wr_addr),
    .scale_bram_wr_data    (scale_bram_wr_data),
    .scale_bram_wr_en      (scale_bram_wr_en),
    .bias_bram_wr_addr     (bias_bram_wr_addr),
    .bias_bram_wr_data     (bias_bram_wr_data),
    .bias_bram_wr_en       (bias_bram_wr_en),
    .ln_bram_wr_addr       (ln_bram_wr_addr),
    .ln_bram_wr_data       (ln_bram_wr_data),
    .ln_bram_wr_en         (ln_bram_wr_en),
    .hdr_bram_wr_addr      (hdr_bram_wr_addr),
    .hdr_bram_wr_data      (hdr_bram_wr_data),
    .hdr_bram_wr_en        (hdr_bram_wr_en),
    .obj_bram_wr_addr      (obj_bram_wr_addr),
    .obj_bram_wr_data      (obj_bram_wr_data),
    .obj_bram_wr_en        (obj_bram_wr_en),
    .lane_bram_wr_addr     (lane_bram_wr_addr),
    .lane_bram_wr_data     (lane_bram_wr_data),
    .lane_bram_wr_en       (lane_bram_wr_en),
    .wm_num_objects        (wm_num_objects),
    .wm_num_lanes          (wm_num_lanes),
    .wout_bram_wr_addr     (wout_bram_wr_addr),
    .wout_bram_wr_data     (wout_bram_wr_data),
    .wout_bram_wr_en       (wout_bram_wr_en),
    .gru_bias_bram_wr_addr (gru_bias_bram_wr_addr),
    .gru_bias_bram_wr_data (gru_bias_bram_wr_data),
    .gru_bias_bram_wr_en   (gru_bias_bram_wr_en),
    .gru_scale_lut_sel     (gru_scale_lut_sel),
    .gru_scale_lut_addr    (gru_scale_lut_addr),
    .gru_scale_lut_wdata   (gru_scale_lut_wdata),
    .gru_scale_lut_we      (gru_scale_lut_we),
    .posemb_bram_wr_addr   (posemb_bram_wr_addr),
    .posemb_bram_wr_data   (posemb_bram_wr_data),
    .posemb_bram_wr_en     (posemb_bram_wr_en),
    .gru_weights_loaded    (gru_weights_loaded)
  );

  // â”€â”€ AXI Slave model: always ready, return burst of zero data â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // State: IDLE â†’ AR_ACCEPT â†’ R_SEND â†’ IDLE
  typedef enum logic [1:0] { AX_IDLE=0, AX_AR=1, AX_R=2 } axi_st_t;
  axi_st_t axi_state;
  logic [7:0] beat_cnt;
  logic [7:0] burst_len;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_state    <= AX_IDLE;
      m_axi_arready <= 1'b0;
      m_axi_rvalid  <= 1'b0;
      m_axi_rlast   <= 1'b0;
      m_axi_rdata   <= 128'h0;
      m_axi_rresp   <= 2'b0;
      m_axi_rid     <= 6'h0;
      beat_cnt      <= 8'h0;
      burst_len     <= 8'h0;
    end else begin
      case (axi_state)
        AX_IDLE: begin
          m_axi_arready <= 1'b1;
          m_axi_rvalid  <= 1'b0;
          if (m_axi_arvalid && m_axi_arready) begin
            burst_len     <= m_axi_arlen;
            beat_cnt      <= 8'h0;
            m_axi_rid     <= m_axi_arid;
            m_axi_arready <= 1'b0;
            // Pre-set rlast for single-beat (arlen=0); multi-beat sets it ahead
            m_axi_rlast   <= (m_axi_arlen == 8'd0);
            axi_state     <= AX_R;
          end
        end
        AX_R: begin
          m_axi_rvalid <= 1'b1;
          m_axi_rdata  <= {beat_cnt, beat_cnt, beat_cnt, beat_cnt,
                           beat_cnt, beat_cnt, beat_cnt, beat_cnt,
                           beat_cnt, beat_cnt, beat_cnt, beat_cnt,
                           beat_cnt, beat_cnt, beat_cnt, beat_cnt};
          // rlast is set ONE beat ahead (inside handshake) to avoid
          // same-cycle override that suppresses it on the last beat.
          if (m_axi_rvalid && m_axi_rready) begin
            if (beat_cnt == burst_len) begin
              m_axi_rvalid <= 1'b0;
              m_axi_rlast  <= 1'b0;
              axi_state    <= AX_IDLE;
            end else begin
              beat_cnt    <= beat_cnt + 1;
              m_axi_rlast <= (beat_cnt + 8'd1 == burst_len);
            end
          end
        end
        default: axi_state <= AX_IDLE;
      endcase
    end
  end

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  // Poll a DUT-driven done pulse. Macro thay cho task ref: xelab coi ref
  // trÃªn biáº¿n Ä‘Ã£ Ä‘Æ°á»£c DUT output port lÃ¡i lÃ  driver thá»© hai (VRFC 10-3823).
  int wd_t;
`define WAIT_DONE(done_sig, name, timeout_cyc) \
    begin \
      wd_t = 0; \
      while (!(done_sig) && wd_t < (timeout_cyc)) begin \
        tick(1); \
        wd_t++; \
      end \
      if (done_sig) begin \
        $display("  PASS [%-30s] done in %0d cycles", name, wd_t); \
        pass_cnt++; \
      end else begin \
        $error("  FAIL [%-30s] timed out after %0d cycles", name, (timeout_cyc)); \
        fail_cnt++; \
      end \
    end

  // â”€â”€ Main Test â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  initial begin
    $display("=== tb_weight_loader : weight_loader ===");

    static_boot_start = 0;
    wm_fetch_start    = 0;
    wm_ddr_base       = 32'h2000_0000;
    posemb_dma_start  = 0;
    gru_wload_start   = 0;
    bert_wload_start  = 0;
    bert_wload_layer  = 2'd0;

    rst_n = 0;
    tick(3);
    rst_n = 1;
    tick(2);

    // T1: After reset, all done signals = 0
    check_bit("after_reset_boot_done", static_boot_done, 1'b0);
    check_bit("after_reset_gru_loaded", gru_weights_loaded, 1'b0);

    // T2: static_boot_start â†’ static_boot_done (loads scale/bias/LN BRAMs)
    @(posedge clk); #0.1;
    static_boot_start = 1'b1;
    @(posedge clk); #0.1;
    static_boot_start = 1'b0;
    `WAIT_DONE(static_boot_done, "static_boot", 100000);

    tick(5);

    // T3: wm_fetch_start â†’ wm_fetch_done (loads HDR/OBJ/LANE BRAMs)
    @(posedge clk); #0.1;
    wm_fetch_start = 1'b1;
    wm_ddr_base    = 32'h3000_0000;
    @(posedge clk); #0.1;
    wm_fetch_start = 1'b0;
    `WAIT_DONE(wm_fetch_done, "wm_fetch", 100000);

    tick(5);

    // T4: posemb_dma_start â†’ posemb_dma_done
    @(posedge clk); #0.1;
    posemb_dma_start = 1'b1;
    @(posedge clk); #0.1;
    posemb_dma_start = 1'b0;
    `WAIT_DONE(posemb_dma_done, "posemb_dma", 100000);

    tick(5);

    // T5: gru_wload_start â†’ gru_wload_done (loads GRU URAM blocks)
    @(posedge clk); #0.1;
    gru_wload_start = 1'b1;
    @(posedge clk); #0.1;
    gru_wload_start = 1'b0;
    `WAIT_DONE(gru_wload_done, "gru_wload", 200000);

    // gru_weights_loaded should be sticky after gru_wload_done
    tick(3);
    check_bit("gru_weights_loaded_sticky", gru_weights_loaded, 1'b1);

    tick(5);

    // T6: bert_wload_start for layer 0 â†’ bert_wload_done
    @(posedge clk); #0.1;
    bert_wload_start = 1'b1;
    bert_wload_layer = 2'd0;
    @(posedge clk); #0.1;
    bert_wload_start = 1'b0;
    // BERT: 384 bursts x 256 beats, ~3 cy/beat expansion => ~300-400k cycles
    `WAIT_DONE(bert_wload_done, "bert_wload_l0", 700000);

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: weight_loader");
      $finish(0);
    end else
      $fatal(1, "FAIL: weight_loader â€” %0d test(s) failed", fail_cnt);
  end

  initial begin
    #10000000;
    $fatal(1, "TIMEOUT: simulation exceeded 10 ms");
  end

endmodule
`default_nettype wire
