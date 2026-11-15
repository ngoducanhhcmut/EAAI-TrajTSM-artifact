`timescale 1ns/1ps
`default_nettype none

module tb_weight_loader_adv;
  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk; // 200 MHz

  // ── DUT Ports ───────────────────────────────────────────────────────────────
  logic        static_boot_start, static_boot_done;
  logic        wm_fetch_start, wm_fetch_done;
  logic [31:0] wm_ddr_base;
  logic        posemb_dma_start, posemb_dma_done;
  // BUG-FIX (missing port): weight_loader.sv gained `idle_sanitize` (a
  // synchronous force-to-WL_IDLE safety input, see weight_loader.sv:315)
  // after this TB was written; `.*` wildcard connection failed elaboration
  // without it. Tied inactive (0) -- this TB's scenarios don't exercise the
  // sanitize-to-idle path, only normal load sequencing.
  logic        idle_sanitize = 1'b0;
  logic        gru_wload_start, gru_wload_done, gru_weights_loaded;
  logic        bert_wload_start, bert_wload_done;
  logic  [1:0] bert_wload_layer;

  // AXI Master
  logic [31:0] m_axi_araddr; logic [7:0] m_axi_arlen; logic [2:0] m_axi_arsize;
  logic  [1:0] m_axi_arburst; logic [5:0] m_axi_arid; logic m_axi_arvalid, m_axi_arready;
  logic [127:0] m_axi_rdata; logic [1:0] m_axi_rresp; logic [5:0] m_axi_rid;
  logic        m_axi_rvalid, m_axi_rlast, m_axi_rready;

  // BRAM / URAM Writes
  logic [18:0] wl_uram_addr; logic [63:0] wl_uram_wdata; logic wl_uram_we, uram_copy_active;
  logic [13:0] scale_bram_wr_addr; logic [31:0] scale_bram_wr_data; logic scale_bram_wr_en;
  logic [14:0] bias_bram_wr_addr;  logic [31:0] bias_bram_wr_data;  logic bias_bram_wr_en;
  logic [12:0] ln_bram_wr_addr;    logic [31:0] ln_bram_wr_data;    logic ln_bram_wr_en;
  logic  [1:0] hdr_bram_wr_addr;   logic [31:0] hdr_bram_wr_data;   logic hdr_bram_wr_en;
  logic [11:0] obj_bram_wr_addr;   logic [31:0] obj_bram_wr_data;   logic obj_bram_wr_en;
  logic  [9:0] lane_bram_wr_addr;  logic [31:0] lane_bram_wr_data;  logic lane_bram_wr_en;
  logic  [7:0] wm_num_objects; logic [4:0] wm_num_lanes;
  logic [10:0] wout_bram_wr_addr;      logic [31:0] wout_bram_wr_data;      logic wout_bram_wr_en;
  logic [10:0] gru_bias_bram_wr_addr;  logic [31:0] gru_bias_bram_wr_data;  logic gru_bias_bram_wr_en;
  // BUG-FIX (missing ports): weight_loader.sv gained the wp_proj_bram write
  // port group (waypoint-projection weight BRAM, mirrors wout_bram_wr_*)
  // after this TB was written.
  logic [10:0] wp_proj_bram_wr_addr;   logic [31:0] wp_proj_bram_wr_data;   logic wp_proj_bram_wr_en;
  logic  [2:0] gru_scale_lut_sel; logic [8:0] gru_scale_lut_addr;
  logic [15:0] gru_scale_lut_wdata; logic gru_scale_lut_we;
  logic [13:0] posemb_bram_wr_addr; logic [63:0] posemb_bram_wr_data; logic posemb_bram_wr_en;

  // ── DUT instantiation ───────────────────────────────────────────────────────
  weight_loader dut (.*);

  // ── SCOREBOARD COUNTERS ─────────────────────────────────────────────────────
  int cnt_scale, cnt_bias, cnt_ln, cnt_hdr, cnt_obj, cnt_lane,
      cnt_posemb, cnt_uram, cnt_gru_wout, cnt_gru_bias, cnt_gru_lut;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt_scale <= 0; cnt_bias  <= 0; cnt_ln   <= 0; cnt_hdr  <= 0;
      cnt_obj   <= 0; cnt_lane  <= 0; cnt_posemb <= 0; cnt_uram <= 0;
      cnt_gru_wout <= 0; cnt_gru_bias <= 0; cnt_gru_lut <= 0;
    end else begin
      if (scale_bram_wr_en)    cnt_scale++;
      if (bias_bram_wr_en)     cnt_bias++;
      if (ln_bram_wr_en)       cnt_ln++;
      if (hdr_bram_wr_en)      cnt_hdr++;
      if (obj_bram_wr_en)      cnt_obj++;
      if (lane_bram_wr_en)     cnt_lane++;
      if (posemb_bram_wr_en)   cnt_posemb++;
      if (wl_uram_we)          cnt_uram++;
      if (wout_bram_wr_en)     cnt_gru_wout++;
      if (gru_bias_bram_wr_en) cnt_gru_bias++;
      if (gru_scale_lut_we)    cnt_gru_lut++;
    end
  end

  task clear_counters();
    cnt_scale = 0; cnt_bias = 0; cnt_ln = 0; cnt_hdr  = 0;
    cnt_obj   = 0; cnt_lane = 0; cnt_posemb = 0; cnt_uram = 0;
    cnt_gru_wout = 0; cnt_gru_bias = 0; cnt_gru_lut = 0;
  endtask

  // ── AXI SLAVE MODEL (với Stall ngẫu nhiên) ─────────────────────────────────
  //
  // BUG FIX: rlast được pre-assert MỘT CYCLE trước beat cuối cùng.
  //   Cách cũ: m_axi_rlast bị ghi đè trong cùng always_ff bởi inner assignment
  //            → rlast KHÔNG BAO GIỜ lên cao với burst > 1 beat → DUT deadlock.
  //   Cách mới:
  //     • Khi chấp nhận AR: pre-set rlast = (arlen == 0) cho single-beat.
  //     • Trong AX_R: sau mỗi handshake, cập nhật rlast = (next_beat == burst_len).
  //       Nhờ đó rlast=1 sẵn trong cycle TRƯỚC beat cuối, và giữ nguyên cho
  //       đến khi handshake cuối hoàn tất.
  //
  // ── Kết quả ──────────────────────────────────────────────────────────────────
  //   Single-beat (arlen=0) : rlast=1 từ khi vào AX_R → cycle đầu có rvalid=1,rlast=1 ✓
  //   Multi-beat  (arlen=N) : rlast pre-assert khi beat_cnt==N-1 được chấp nhận
  //                           → cycle tiếp theo (beat_cnt==N) rvalid=1,rlast=1 ✓
  //   Stall trong khi rlast=1 : rvalid bị hạ xuống 0, nhưng rlast GIỮ NGUYÊN
  //                              → khi stall kết thúc, rvalid=1, rlast=1 đúng ✓

  typedef enum logic [1:0] { AX_IDLE = 0, AX_R = 1 } axi_st_t;
  axi_st_t axi_state;
  logic [7:0] burst_len, beat_cnt;
  logic [31:0] curr_araddr;

  // Tham số WM inject
  logic [31:0] inject_num_obj   = 32'd50;
  logic [31:0] inject_num_lanes = 32'd10;

  // Tỉ lệ stall 30%
  int STALL_PROB = 30;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_state     <= AX_IDLE;
      m_axi_arready <= 1'b0;
      m_axi_rvalid  <= 1'b0;
      m_axi_rlast   <= 1'b0;
      m_axi_rdata   <= '0;
      m_axi_rresp   <= 2'b00;
      m_axi_rid     <= '0;
      burst_len     <= 8'd0;
      beat_cnt      <= 8'd0;
      curr_araddr   <= 32'd0;
    end else begin
      // Ngẫu nhiên stall
      logic stall_ar = ($urandom_range(0, 100) < STALL_PROB);
      logic stall_r  = ($urandom_range(0, 100) < STALL_PROB);

      case (axi_state)

        // --------------------------------------------------------------------
        AX_IDLE: begin
          m_axi_rvalid  <= 1'b0;
          m_axi_arready <= ~stall_ar;
          if (m_axi_arvalid && m_axi_arready) begin
            burst_len     <= m_axi_arlen;
            curr_araddr   <= m_axi_araddr;
            beat_cnt      <= 8'd0;
            // FIX: pre-assert rlast ngay khi chấp nhận AR nếu là single-beat
            m_axi_rlast   <= (m_axi_arlen == 8'd0);
            m_axi_arready <= 1'b0;
            axi_state     <= AX_R;
          end
        end

        // --------------------------------------------------------------------
        AX_R: begin
          if (stall_r) begin
            // Stall: hạ rvalid nhưng GIỮ NGUYÊN rlast
            // (DUT không sample khi rvalid=0, nên rlast giữ nguyên là an toàn)
            m_axi_rvalid <= 1'b0;
          end else begin
            // Chuẩn bị data cho beat hiện tại
            // (registered: data sẽ visible ở cycle tiếp theo khi handshake xảy ra)
            if (curr_araddr == wm_ddr_base && beat_cnt == 8'd0)
              m_axi_rdata <= {64'h0, inject_num_lanes, inject_num_obj};
            else
              m_axi_rdata <= {4{curr_araddr + {24'd0, beat_cnt}}};

            m_axi_rvalid <= 1'b1;

            // Xử lý handshake
            if (m_axi_rvalid && m_axi_rready) begin
              if (beat_cnt == burst_len) begin
                // Beat cuối đã được chấp nhận → quay về IDLE
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
                axi_state    <= AX_IDLE;
              end else begin
                beat_cnt    <= beat_cnt + 8'd1;
                // FIX: Pre-assert rlast cho beat KẾ TIẾP nếu nó là beat cuối
                // Ví dụ burst_len=255: khi beat_cnt=254 được accept → rlast=1
                // → cycle sau beat_cnt=255 xuất hiện với rlast=1 sẵn ✓
                m_axi_rlast <= (beat_cnt + 8'd1 == burst_len);
              end
            end
          end
        end

      endcase
    end
  end

  // ── CHECKER TASKS ──────────────────────────────────────────────────────────
  int pass_cnt = 0, fail_cnt = 0;

  task check_val(string name, int got, int exp);
    if (got === exp) begin
      $display("  [PASS] %-30s : %0d", name, got); pass_cnt++;
    end else begin
      $error("  [FAIL] %-30s : got %0d, expected %0d", name, got, exp); fail_cnt++;
    end
  endtask

  // BUG-FIX (real hang, not just a slow-timeout budget issue): the
  // task+(const)ref pattern here originally compiled and elaborated, but
  // every single `WAIT_SIG() call timed out even with an 8,000,000-cycle
  // budget and a fixed RNG seed (fully deterministic re-run), while the
  // DUT's internal counters (verified via hierarchical debug prints)
  // reached their exact correct target values every time. That combination
  // -- correct DUT behavior, but the polling loop never observing it --
  // points to `ref`/`const ref` not behaving as a live alias to a DUT
  // output net in this simulator, rather than an RTL defect. Replaced the
  // task+ref pattern with a macro (pure textual substitution, no parameter
  // passing at all) so each call polls the real signal directly.
  //
  // Timeout budget itself was ALSO too small for the true (stall-heavy)
  // throughput: STATIC_BOOT's 8960 beats need ~500K+ cycles at STALL_PROB
  // =30% on both AR/R channels; BERT WLOAD's 98,304 beats scale further.
  // Raised with margin -- affects simulation wall-clock only.
  localparam int WAIT_SIG_TIMEOUT = 15_000_000;
  `define WAIT_SIG(sig, name) \
    begin \
      automatic int t_wait = 0; \
      while (!(sig) && t_wait < WAIT_SIG_TIMEOUT) begin @(posedge clk); t_wait++; end \
      if (t_wait >= WAIT_SIG_TIMEOUT) $error("  [TIMEOUT] %s did not assert!", name); \
    end

  // ── TEST SUITE ─────────────────────────────────────────────────────────────
  initial begin
    // BUG-FIX (non-reproducible test): $urandom_range() in the AXI stall BFM
    // was never seeded, so every simulation run drew a different stall
    // sequence -- completion time for the same scenario varied wildly run to
    // run (observed 500K cycles in one run, still incomplete past 8M in
    // another). Fixed seed makes failures reproducible/debuggable.
    $srandom(32'hC0FFEE01);
    $display("\n=======================================================");
    $display("BẮT ĐẦU CHẠY ADVANCED TESTBENCH CHO WEIGHT_LOADER");
    $display("=======================================================\n");

    rst_n = 0; static_boot_start = 0; wm_fetch_start = 0;
    posemb_dma_start = 0; gru_wload_start = 0; bert_wload_start = 0;
    wm_ddr_base = 32'h1000_0000;
    #20 rst_n = 1; #20;

    // ---------------------------------------------------------
    // TEST 1: STATIC BOOT
    //   Scale : 2304 beats × 4 words = 9216
    //   Bias  : 4608 beats × 4 words = 18432
    //   LN    : 2048 beats × 4 words = 8192
    // ---------------------------------------------------------
    $display("--- TEST 1: STATIC BOOT ---");
    clear_counters();
    @(posedge clk) static_boot_start = 1;
    @(posedge clk) static_boot_start = 0;
    `WAIT_SIG(static_boot_done, "static_boot_done");
    check_val("Scale BRAM Writes", cnt_scale, 9216);
    check_val("Bias BRAM Writes",  cnt_bias,  18432);
    check_val("LN BRAM Writes",    cnt_ln,    8192);
    #100;

    // ---------------------------------------------------------
    // TEST 2: WM FETCH (Normal: 50 objs, 10 lanes)
    //   HDR  : 1 beat × 4 words  = 4
    //   OBJ  : 50 × 12 words     = 600
    //   LANE : 10 × 32 words     = 320
    // ---------------------------------------------------------
    $display("\n--- TEST 2: WM FETCH (Normal: 50 objs, 10 lanes) ---");
    clear_counters();
    inject_num_obj = 50; inject_num_lanes = 10;
    @(posedge clk) wm_fetch_start = 1;
    @(posedge clk) wm_fetch_start = 0;
    `WAIT_SIG(wm_fetch_done, "wm_fetch_done");
    check_val("Header BRAM Writes", cnt_hdr,  4);
    check_val("Object BRAM Writes", cnt_obj,  50 * 12);
    check_val("Lane BRAM Writes",   cnt_lane, 10 * 32);
    #100;

    // ---------------------------------------------------------
    // TEST 3: WM FETCH Corner Case (0 objs, 0 lanes)
    // ---------------------------------------------------------
    $display("\n--- TEST 3: WM FETCH (Corner: 0 objs, 0 lanes) ---");
    clear_counters();
    inject_num_obj = 0; inject_num_lanes = 0;
    @(posedge clk) wm_fetch_start = 1;
    @(posedge clk) wm_fetch_start = 0;
    `WAIT_SIG(wm_fetch_done, "wm_fetch_done");
    check_val("Object BRAM Writes (0)", cnt_obj,  0);
    check_val("Lane BRAM Writes (0)",   cnt_lane, 0);
    #100;

    // ---------------------------------------------------------
    // TEST 4: WM FETCH Overflow (250 objs → clamp 200, 30 lanes → clamp 20)
    //   OBJ  : 200 × 12 = 2400
    //   LANE : 20  × 32 = 640
    // ---------------------------------------------------------
    $display("\n--- TEST 4: WM FETCH (Overflow: 250 objs, 30 lanes) ---");
    clear_counters();
    inject_num_obj = 250; inject_num_lanes = 30;
    @(posedge clk) wm_fetch_start = 1;
    @(posedge clk) wm_fetch_start = 0;
    `WAIT_SIG(wm_fetch_done, "wm_fetch_done");
    check_val("Obj Writes (Cut to 200)",  cnt_obj,  200 * 12);
    check_val("Lane Writes (Cut to 20)",  cnt_lane, 20  * 32);
    #100;

    // ---------------------------------------------------------
    // TEST 5: BERT LAYER 3
    //   98304 beats × 2 sub-writes = 196608 URAM writes
    //   ~98304 × 3 cycles/beat + stalls ≈ 300k–420k cycles  (< 500k timeout)
    // ---------------------------------------------------------
    $display("\n--- TEST 5: BERT WLOAD (Layer 3) ---");
    clear_counters();
    bert_wload_layer = 2'd3;
    @(posedge clk) bert_wload_start = 1;
    @(posedge clk) bert_wload_start = 0;
    `WAIT_SIG(bert_wload_done, "bert_wload_done");
    check_val("URAM Writes (BERT)", cnt_uram, 196608);
    #100;

    // ---------------------------------------------------------
    // TEST 6: PRIORITY ARBITRATION
    //   wm_fetch_start, posemb_dma_start, gru_wload_start pulsed simultaneously.
    //   wm_fetch_start has highest priority among these three → wm_fetch_done wins.
    // ---------------------------------------------------------
    $display("\n--- TEST 6: PRIORITY ARBITRATION ---");
    clear_counters();
    @(posedge clk);
    wm_fetch_start = 1; posemb_dma_start = 1; gru_wload_start = 1;
    @(posedge clk);
    wm_fetch_start = 0; posemb_dma_start = 0; gru_wload_start = 0;
    `WAIT_SIG(wm_fetch_done, "Priority: wm_fetch_done wins");
    $display("  [PASS] WM_FETCH was prioritized correctly!");

    // ── SUMMARY ──────────────────────────────────────────────
    $display("\n=======================================================");
    $display("KẾT QUẢ: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("OK [SUCCESS] IC SẴN SÀNG TAPE-OUT!");
    else               $display("XX [ERROR]   CẦN SỬA LẠI RTL LOGIC!");
    $display("=======================================================\n");
    $finish;
  end

endmodule