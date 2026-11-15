`timescale 1ns/1ps
`default_nettype none
// =============================================================================
// tb_bert_weight_loader.sv — Unit TB cho BERT DMA engine ĐANG SỐNG (F-P1-1/2)
//
// planning_top dùng bert_weight_loader (KHÔNG phải weight_loader.WL_BERT_DMA).
// RTL có nhánh `ifdef SIMULATION là stub (1 burst 16 beat, ghi 64'd0) — nên TB
// này BẮT BUỘC compile KHÔNG có -d SIMULATION để kiểm chứng datapath thật:
//   - 384 AR bursts, arlen=255, araddr = layer_base + txn*4096
//   - 196,608 URAM writes, địa chỉ tuyến tính 0..196607
//   - data khớp nguồn DDR (slave model mã hoá địa chỉ vào data)
//   - done đúng 1 chu kỳ, dma_active đúng pha, one-shot khi start giữ mức
//   - chịu arready trễ ngẫu nhiên + rvalid có khoảng trống (stress mode)
// =============================================================================

module tb_bert_weight_loader;
  import planning_pkg::*;

`ifdef SIMULATION
  initial begin
    $display("FATAL: tb_bert_weight_loader phai compile KHONG co -d SIMULATION");
    $display("       (co define nay thi DUT chi con stub, khong phai datapath that)");
    $fatal(1);
  end
`endif

  logic clk = 1'b0;
  logic rst_n;
  always #2.5 clk = ~clk;   // 200 MHz

  // ── DUT ports ──────────────────────────────────────────────────────────────
  logic         bert_wload_start;
  logic  [1:0]  bert_wload_layer;
  logic         bert_wload_done;
  logic         dma_active;
  logic [31:0]  m_axi_araddr;
  logic  [7:0]  m_axi_arlen;
  logic  [2:0]  m_axi_arsize;
  logic  [1:0]  m_axi_arburst;
  logic  [5:0]  m_axi_arid;
  logic         m_axi_arvalid;
  logic         m_axi_arready;
  logic [127:0] m_axi_rdata;
  logic  [1:0]  m_axi_rresp;
  logic  [5:0]  m_axi_rid;
  logic         m_axi_rvalid;
  logic         m_axi_rlast;
  logic         m_axi_rready;
  logic [18:0]  wl_uram_addr;
  logic [63:0]  wl_uram_wdata;
  logic         wl_uram_we;

  bert_weight_loader dut (.*);

  int pass_cnt = 0;
  int fail_cnt = 0;

  // ── AXI4 read-slave model ──────────────────────────────────────────────────
  // Data = địa chỉ byte của chính chunk 8B đó (zero-extend 32→64):
  //   rdata[63:0]   = base + beat*16
  //   rdata[127:64] = base + beat*16 + 8
  // → URAM write thứ n phải có wdata = 64'(layer_base + n*8) (mapping tuyến tính)
  bit          stress_mode = 0;
  typedef enum logic [1:0] {SL_IDLE, SL_BURST, SL_GAP} sl_t;
  sl_t         sl_state;
  logic [31:0] sl_addr;
  logic  [8:0] sl_beat;
  logic  [7:0] sl_len;
  int          sl_wait;

  wire [31:0] beat_addr = sl_addr + ({23'd0, sl_beat} << 4);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sl_state      <= SL_IDLE;
      m_axi_arready <= 1'b0;
      m_axi_rvalid  <= 1'b0;
      m_axi_rlast   <= 1'b0;
      m_axi_rdata   <= '0;
      m_axi_rresp   <= 2'b00;
      m_axi_rid     <= '0;
      sl_addr       <= '0;
      sl_beat       <= '0;
      sl_len        <= '0;
      sl_wait       <= 0;
    end else begin
      case (sl_state)
        SL_IDLE: begin
          m_axi_rvalid <= 1'b0;
          m_axi_rlast  <= 1'b0;
          if (sl_wait > 0) begin
            sl_wait       <= sl_wait - 1;
            m_axi_arready <= 1'b0;
          end else begin
            m_axi_arready <= 1'b1;
          end
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arready <= 1'b0;
            sl_addr       <= m_axi_araddr;
            sl_len        <= m_axi_arlen;
            sl_beat       <= '0;
            sl_state      <= SL_BURST;
          end
        end

        SL_BURST: begin
          m_axi_arready <= 1'b0;
          m_axi_rvalid  <= 1'b1;
          m_axi_rdata   <= {32'h0, beat_addr + 32'd8, 32'h0, beat_addr};
          m_axi_rlast   <= (sl_beat == {1'b0, sl_len});
          if (m_axi_rvalid && m_axi_rready) begin
            if (m_axi_rlast) begin
              m_axi_rvalid <= 1'b0;
              m_axi_rlast  <= 1'b0;
              sl_state     <= SL_IDLE;
              if (stress_mode) sl_wait <= $urandom_range(0, 3);
            end else begin
              sl_beat <= sl_beat + 9'd1;
              // Ngẫu nhiên chèn khoảng trống rvalid (1/4 xác suất)
              if (stress_mode && ($urandom_range(0, 3) == 0)) begin
                m_axi_rvalid <= 1'b0;
                sl_wait      <= $urandom_range(1, 2);
                sl_state     <= SL_GAP;
              end
            end
          end
        end

        SL_GAP: begin
          m_axi_rvalid <= 1'b0;
          if (sl_wait > 1) sl_wait <= sl_wait - 1;
          else             sl_state <= SL_BURST;
        end

        default: sl_state <= SL_IDLE;
      endcase
    end
  end

  // ── AR observer ────────────────────────────────────────────────────────────
  int          ar_cnt;
  int          arlen_errors;
  int          arattr_errors;
  logic [31:0] first_araddr, last_araddr;

  always @(posedge clk) begin
    if (rst_n && m_axi_arvalid && m_axi_arready) begin
      if (ar_cnt == 0) first_araddr = m_axi_araddr;
      last_araddr = m_axi_araddr;
      if (m_axi_arlen !== 8'd255) arlen_errors++;
      if (m_axi_arsize !== 3'b100 || m_axi_arburst !== 2'b01) arattr_errors++;
      ar_cnt++;
    end
  end

  // ── URAM write scoreboard ──────────────────────────────────────────────────
  longint      wr_cnt;
  int          addr_errors, data_errors;
  logic [31:0] cur_base;

  always @(posedge clk) begin
    if (rst_n && wl_uram_we) begin
      if (wl_uram_addr !== 19'(wr_cnt)) begin
        if (addr_errors < 5)
          $error("URAM addr sai @write %0d: got=%0d exp=%0d",
                 wr_cnt, wl_uram_addr, 19'(wr_cnt));
        addr_errors++;
      end
      if (wl_uram_wdata !== {32'h0, cur_base + 32'(wr_cnt) * 32'd8}) begin
        if (data_errors < 5)
          $error("URAM data sai @write %0d: got=%016h exp=%016h",
                 wr_cnt, wl_uram_wdata, {32'h0, cur_base + 32'(wr_cnt) * 32'd8});
        data_errors++;
      end
      wr_cnt++;
    end
  end

  // done-pulse counter
  int done_cycles;
  always @(posedge clk) if (rst_n && bert_wload_done) done_cycles++;

  // ── Helpers ────────────────────────────────────────────────────────────────
  task tick(input int n = 1);
    repeat (n) @(posedge clk);
    #0.1;
  endtask

  task check_int(input string name, input longint got, input longint exp);
    if (got === exp) begin
      $display("  PASS [%-28s] = %0d", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-28s] got=%0d exp=%0d", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_hex(input string name, input logic [31:0] got, input logic [31:0] exp);
    if (got === exp) begin
      $display("  PASS [%-28s] = 0x%08h", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-28s] got=0x%08h exp=0x%08h", name, got, exp);
      fail_cnt++;
    end
  endtask

  int wl_t;

  // Full-load một layer và verify toàn bộ invariant
  task automatic run_load(input logic [1:0] layer,
                          input bit        hold_start,
                          input int        timeout_cy,
                          input string     tag);
    // reset scoreboard
    wr_cnt = 0; addr_errors = 0; data_errors = 0;
    ar_cnt = 0; arlen_errors = 0; arattr_errors = 0;
    done_cycles = 0;
    cur_base = DDR4_BERT_WEIGHT + 32'h0018_0000 * layer;

    $display("\n--- %s: layer %0d, base=0x%08h, hold_start=%0b, stress=%0b ---",
             tag, layer, cur_base, hold_start, stress_mode);

    @(posedge clk); #0.1;
    bert_wload_layer = layer;
    bert_wload_start = 1'b1;
    if (!hold_start) begin
      @(posedge clk); #0.1;
      bert_wload_start = 1'b0;
    end

    wl_t = 0;
    while (done_cycles == 0 && wl_t < timeout_cy) begin
      @(posedge clk); #0.1;
      wl_t++;
    end
    if (done_cycles == 0) begin
      $error("  FAIL [%-28s] done timeout sau %0d chu ky", {tag, "_done"}, timeout_cy);
      fail_cnt++;
      bert_wload_start = 1'b0;
      return;
    end
    $display("  PASS [%-28s] done sau %0d chu ky", {tag, "_done"}, wl_t);
    pass_cnt++;

    check_int({tag, "_uram_writes"},  wr_cnt,       196608);
    check_int({tag, "_addr_errors"},  addr_errors,  0);
    check_int({tag, "_data_errors"},  data_errors,  0);
    check_int({tag, "_ar_bursts"},    ar_cnt,       384);
    check_int({tag, "_arlen_errors"}, arlen_errors, 0);
    check_int({tag, "_arattr_errors"},arattr_errors,0);
    check_hex({tag, "_first_araddr"}, first_araddr, cur_base);
    check_hex({tag, "_last_araddr"},  last_araddr,  cur_base + 32'h0017_F000);

    // done phải là pulse đúng 1 chu kỳ
    tick(5);
    check_int({tag, "_done_pulse_1cy"}, done_cycles, 1);
    check_int({tag, "_dma_active_off"}, dma_active,  0);

    if (hold_start) begin
      // One-shot: start vẫn đang giữ mức cao → không được load lần 2
      tick(200);
      check_int({tag, "_oneshot_no_reload"}, wr_cnt, 196608);
      check_int({tag, "_oneshot_dma_idle"},  dma_active, 0);
      bert_wload_start = 1'b0;
      tick(2);
    end
  endtask

  // ── Main ───────────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_bert_weight_loader : REAL datapath (no SIMULATION define) ===");

    bert_wload_start = 0;
    bert_wload_layer = 2'd0;
    rst_n = 0;
    tick(4);
    rst_n = 1;
    tick(3);

    // T1: trạng thái sau reset
    check_int("reset_done",       bert_wload_done, 0);
    check_int("reset_dma_active", dma_active,      0);
    check_int("reset_arvalid",    m_axi_arvalid,   0);

    // T2: full load layer 0, start giữ mức cao suốt quá trình (one-shot guard)
    run_load(2'd0, 1'b1, 900_000, "T2_L0");

    // T3: base address của layer 3 (abort sau AR đầu tiên bằng reset)
    begin
      logic [31:0] exp_l3;
      exp_l3 = DDR4_BERT_WEIGHT + 32'h0048_0000;
      ar_cnt = 0;
      @(posedge clk); #0.1;
      bert_wload_layer = 2'd3;
      bert_wload_start = 1'b1;
      @(posedge clk); #0.1;
      bert_wload_start = 1'b0;
      wl_t = 0;
      while (ar_cnt == 0 && wl_t < 100) begin
        @(posedge clk); #0.1;
        wl_t++;
      end
      check_hex("T3_L3_first_araddr", first_araddr, exp_l3);
      // abort: reset toàn hệ
      rst_n = 0;
      tick(4);
      rst_n = 1;
      tick(3);
    end

    // T4: full load layer 1 dưới stress (arready trễ + rvalid gap ngẫu nhiên)
    stress_mode = 1;
    run_load(2'd1, 1'b0, 1_500_000, "T4_L1_stress");
    stress_mode = 0;

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: bert_weight_loader (real datapath)");
      $finish(0);
    end else
      $fatal(1, "FAIL: bert_weight_loader — %0d test(s) failed", fail_cnt);
  end

  initial begin
    #20_000_000;  // 20 ms
    $fatal(1, "TIMEOUT: simulation exceeded 20 ms");
  end

endmodule
`default_nettype wire
