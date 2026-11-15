`timescale 1ns / 1ps
/* verilator lint_off WIDTHEXPAND */

module bert_weight_loader
  import planning_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,
  input  logic         bert_wload_start,
  input  logic  [1:0]  bert_wload_layer,
  output logic         bert_wload_done,
  output logic         dma_active,

  output logic [31:0]  m_axi_araddr,
  output logic  [7:0]  m_axi_arlen,
  output logic  [2:0]  m_axi_arsize,
  output logic  [1:0]  m_axi_arburst,
  output logic  [5:0]  m_axi_arid,
  output logic         m_axi_arvalid,
  input  logic         m_axi_arready,
  input  logic [127:0] m_axi_rdata,
  input  logic  [1:0]  m_axi_rresp,
  input  logic  [5:0]  m_axi_rid,
  input  logic         m_axi_rvalid,
  input  logic         m_axi_rlast,
  output logic         m_axi_rready,

  output logic [18:0]  wl_uram_addr,
  output logic [63:0]  wl_uram_wdata,
  output logic         wl_uram_we
);

  localparam logic [1:0] ST_IDLE = 2'd0;
  localparam logic [1:0] ST_DMA  = 2'd1;
  localparam logic [1:0] ST_DONE = 2'd2;

  logic [1:0]   state;
  logic         start_seen;
  logic [11:0]  txn_count;
  logic [17:0]  uram_wr_cnt;
  logic [31:0]  cur_base_addr;
  logic         ar_pending;
  logic         write_busy;
  logic         sub_beat;
  logic [127:0] rdata_latch;

  function automatic logic [31:0] bert_layer_base(input logic [1:0] layer);
    case (layer)
      2'd0:    bert_layer_base = DDR4_BERT_WEIGHT;
      2'd1:    bert_layer_base = DDR4_BERT_WEIGHT + 32'h0018_0000;
      2'd2:    bert_layer_base = DDR4_BERT_WEIGHT + 32'h0030_0000;
      default: bert_layer_base = DDR4_BERT_WEIGHT + 32'h0048_0000;
    endcase
  endfunction

  assign m_axi_arsize  = 3'b100;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arid    = 6'd0;
  // [PERF] Mở rready cả ở chu kỳ ghi cuối của beat hiện tại (write_busy &&
  // sub_beat) để nhận beat kế không hở chu kỳ → throughput 2 cy/beat.
  assign m_axi_rready  = ~write_busy | sub_beat;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state           <= ST_IDLE;
      start_seen      <= 1'b0;
      bert_wload_done <= 1'b0;
      dma_active      <= 1'b0;
      m_axi_araddr    <= '0;
      m_axi_arlen     <= 8'd0;
      m_axi_arvalid   <= 1'b0;
      ar_pending      <= 1'b0;
      txn_count       <= '0;
      uram_wr_cnt     <= '0;
      cur_base_addr   <= '0;
      write_busy      <= 1'b0;
      sub_beat        <= 1'b0;
      rdata_latch     <= '0;
      wl_uram_addr    <= '0;
      wl_uram_wdata   <= '0;
      wl_uram_we      <= 1'b0;
    end else begin
      bert_wload_done <= 1'b0;
      wl_uram_we      <= 1'b0;
`ifdef SIMULATION
      if (!bert_wload_start) begin
        start_seen <= 1'b0;
      end

      case (state)
        ST_IDLE: begin
          dma_active   <= 1'b0;
          write_busy   <= 1'b0;
          m_axi_arvalid<= 1'b0;
          ar_pending   <= 1'b0;
          if (bert_wload_start && !start_seen) begin
            start_seen    <= 1'b1;
            state         <= ST_DMA;
            dma_active    <= 1'b1;
            cur_base_addr <= bert_layer_base(bert_wload_layer);
            txn_count     <= 12'd0;
            uram_wr_cnt   <= 18'd0;
          end
        end

        ST_DMA: begin
          dma_active <= 1'b1;
          if (!ar_pending && !m_axi_arvalid) begin
            m_axi_arvalid <= 1'b1;
            m_axi_araddr  <= cur_base_addr;
            m_axi_arlen   <= 8'd15;
          end
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            ar_pending    <= 1'b1;
          end
          if (ar_pending && m_axi_rvalid) begin
            wl_uram_we    <= 1'b1;
            wl_uram_addr  <= {1'b0, uram_wr_cnt};
            wl_uram_wdata <= 64'd0;
            uram_wr_cnt   <= uram_wr_cnt + 18'd1;
            if (m_axi_rlast) begin
              ar_pending      <= 1'b0;
              bert_wload_done <= 1'b1;
              dma_active      <= 1'b0;
              state           <= ST_IDLE;
            end
          end
        end

        default: begin
          state         <= ST_IDLE;
          dma_active    <= 1'b0;
          m_axi_arvalid <= 1'b0;
          ar_pending    <= 1'b0;
          write_busy    <= 1'b0;
        end
      endcase
`else
      if (!bert_wload_start) begin
        start_seen <= 1'b0;
      end

      if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arvalid <= 1'b0;
        ar_pending    <= 1'b1;
      end
      // [FIX] qualify bằng rready: rlast beat có thể được slave TRÌNH ra trong
      // lúc rready=0 (đang ghi URAM); clear sớm sẽ phát AR kế → 2 outstanding.
      if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
        ar_pending <= 1'b0;
      end

      case (state)
        ST_IDLE: begin
          dma_active <= 1'b0;
          write_busy <= 1'b0;
          if (bert_wload_start && !start_seen) begin
            start_seen    <= 1'b1;
            state         <= ST_DMA;
            dma_active    <= 1'b1;
            cur_base_addr <= bert_layer_base(bert_wload_layer);
            txn_count     <= 12'd0;
            uram_wr_cnt   <= 18'd0;
            ar_pending    <= 1'b0;
            m_axi_arvalid <= 1'b0;
            sub_beat      <= 1'b0;
          end
        end

        ST_DMA: begin
          dma_active <= 1'b1;
          // [PERF] Phát AR bất kể write_busy (vẫn 1 outstanding qua ar_pending)
          // để burst kế nối đuôi không tạo bong bóng trên kênh R.
          if (!m_axi_arvalid && !ar_pending && txn_count < 12'd384) begin
            m_axi_arvalid <= 1'b1;
            m_axi_araddr  <= cur_base_addr + {txn_count, 12'd0};
            m_axi_arlen   <= 8'd255;
            txn_count     <= txn_count + 12'd1;
          end
          if (!write_busy) begin
            if (m_axi_rvalid) begin
              rdata_latch <= m_axi_rdata;
              write_busy  <= 1'b1;
              sub_beat    <= 1'b0;
            end
          end else begin
            wl_uram_addr  <= {7'(uram_wr_cnt >> 12), uram_wr_cnt[11:0]};
            wl_uram_wdata <= sub_beat ? rdata_latch[127:64] : rdata_latch[63:0];
            wl_uram_we    <= 1'b1;
            uram_wr_cnt   <= uram_wr_cnt + 18'd1;
            if (sub_beat) begin
              if (uram_wr_cnt == 18'd196607) begin
                write_busy <= 1'b0;
                state      <= ST_DONE;
              end else if (m_axi_rvalid) begin
                // [PERF] Nhận beat kế NGAY trong chu kỳ ghi nửa cao (rready=1
                // nhờ sub_beat): ghi dùng giá trị rdata_latch trước sườn,
                // latch mới cập nhật sau sườn (NBA) → 2 cy/beat thay vì 3.
                // Đo được: 295,301 → ~197k chu kỳ/layer.
                rdata_latch <= m_axi_rdata;
                sub_beat    <= 1'b0;
              end else begin
                write_busy <= 1'b0;
              end
            end else begin
              sub_beat <= 1'b1;
            end
          end
        end

        ST_DONE: begin
          bert_wload_done <= 1'b1;
          dma_active      <= 1'b0;
          write_busy      <= 1'b0;
          state           <= ST_IDLE;
        end

        default: begin
          state        <= ST_IDLE;
          dma_active   <= 1'b0;
          write_busy   <= 1'b0;
          m_axi_arvalid<= 1'b0;
          ar_pending   <= 1'b0;
          sub_beat     <= 1'b0;
        end
      endcase
`endif
    end
  end

// [Fix AG2] Bat khi ASSERT_ON HOAC dieu kien cu (SIMULATION). Dieu kien viet
// NGAY TAI CHO: macro dinh nghia o tep khac KHONG thay duoc khi xvlog
// bien dich tung tep rieng (da thu thuc nghiem 30/09/2026).
`ifdef ASSERT_ON
  `define _AG_EN_BWL
`elsif SIMULATION
  `define _AG_EN_BWL
`endif
`ifdef _AG_EN_BWL
  initial $display("[AG] assertion BAT: bert_weight_loader.sv %m");
  property p_no_axi_err;
    @(posedge clk) disable iff (!rst_n)
    m_axi_rvalid |-> m_axi_rresp == 2'b00;
  endproperty
  assert property (p_no_axi_err)
    else $error("bert_weight_loader: AXI rresp error = %b", m_axi_rresp);
`endif

endmodule
