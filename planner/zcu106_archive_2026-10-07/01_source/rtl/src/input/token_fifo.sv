// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// token_fifo.sv — Token Input FIFO (LUTRAM-based)
// Spec v15.5 §15.15
// ================================================================================
// This module implements a LUTRAM-based FIFO to buffer tokens from 
// world_model_parser and feed them to input_adapter for projection.
// 
// Port signals:
//   - Receive side: x_token_valid/ready handshake
//   - Send side: token_valid/ready handshake
//   - Occupancy counter for debugging/flow control
//
// [FIX] Chuyển read side sang FWFT (First Word Fall Through):
//   - token_o, token_type_o: combinatorial từ fifo_ram[rd_ptr] (không qua FF)
//   - token_valid_o:         combinatorial từ (rd_ptr != wr_ptr)
//   - rd_ptr chỉ advance khi token_valid_o && token_ready_i (handshake đúng)
//   Lý do: output registered cũ khiến TB thấy data trễ 1 cycle so với rd_ptr
//   hiện tại, gây ra lỗi "Got = Exp - 1" nhất quán ở Test 4 và Test 7.

/* verilator lint_off TIMESCALEMOD */
`timescale 1ns / 1ps

module token_fifo
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,

  // ── Write port (from world_model_parser) ─────────────────────────────
  input  bbox6_t        x_token_data,       // 24B token
  input  token_type_t   x_token_type,       // CLS, EGO, OBJECT, LANE, TARGET
  input  logic          x_token_valid,      // write strobe
  output logic          x_token_ready,      // FIFO not full

  // ── Read port (to input_adapter) ─────────────────────────────────────
  output bbox6_t        token_o,
  output token_type_t   token_type_o,
  output logic          token_valid_o,      // data available
  input  logic          token_ready_i,      // consumer drains

  // ── Status ───────────────────────────────────────────────────────────
  output logic [7:0]    fifo_occupancy      // 0..64
);

  // ── FIFO depth: 64 entries (MAX_SEQ_LEN=64 per spec §15.15) ──────────
  localparam int FIFO_DEPTH = 64;
  localparam int ADDR_BITS  = 6;           // log2(64)

  // ── LUTRAM storage ──────────────────────────────────────────────────
  // Store token_type (4-bit) + bbox6_t (192-bit) per entry
  // Total: 196-bit per entry, fits in 2× LUTRAM36 (2×32×36b SRAM per depth)
  // Quad-indexed as 256×24B = 6KB LUTRAM (negligible ~190 LUT6)
  
  typedef struct packed {
    bbox6_t   bbox;
    token_type_t token_type;
  } fifo_entry_t;

  fifo_entry_t          fifo_ram [FIFO_DEPTH-1:0];  // LUTRAM via synthesis pragmas
  
  logic [ADDR_BITS:0]   wr_ptr, rd_ptr;      // 7-bit to detect full/empty (ADDR_BITS+1)
  logic [ADDR_BITS:0]   wr_ptr_nxt, rd_ptr_nxt;

  logic                 fifo_empty, fifo_full;
  logic [7:0]           occupancy_cnt;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // FSM: track write/read pointers (circular buffer, 7-bit for MSB wrap detect)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
    end else begin
      wr_ptr <= wr_ptr_nxt;
      rd_ptr <= rd_ptr_nxt;
    end

  // ── Write pointer update ──────────────────────────────────────────────
  always_comb begin
    wr_ptr_nxt = wr_ptr;
    if (x_token_valid && x_token_ready)
      wr_ptr_nxt = wr_ptr + 7'd1;  // wrap at 128 (MSB cycles); depth=64
  end

  // ── Read pointer update ───────────────────────────────────────────────
  // [FIX] Advance rd_ptr khi có handshake hoàn chỉnh: valid && ready
  //       (thay vì chỉ kiểm tra token_ready_i && rd_ptr != wr_ptr)
  //       Tương đương về logic nhưng rõ ràng hơn với FWFT interface.
  always_comb begin
    rd_ptr_nxt = rd_ptr;
    if (token_valid_o && token_ready_i)
      rd_ptr_nxt = rd_ptr + 7'd1;
  end

  // ── Empty/Full flags ──────────────────────────────────────────────────
  // Empty: wr_ptr[5:0] == rd_ptr[5:0] && wr_ptr[6] == rd_ptr[6]
  // Full:  wr_ptr[5:0] == rd_ptr[5:0] && wr_ptr[6] != rd_ptr[6]
  always_comb begin
    fifo_empty = (wr_ptr == rd_ptr);
    fifo_full  = (wr_ptr[ADDR_BITS-1:0] == rd_ptr[ADDR_BITS-1:0]) &&
                 (wr_ptr[ADDR_BITS]     != rd_ptr[ADDR_BITS]);
  end

  // ── Occupancy counter ─────────────────────────────────────────────────
  // [FIX F-P1-3] Hiệu 7-bit (mod 128) luôn đúng vì occupancy ∈ [0,64] < 128;
  // bao cả empty (=0) và full (=64). Công thức cũ sai ở vùng wrapped
  // (wr_ptr < rd_ptr numerically): 8'(wr_ptr+64)-8'(rd_ptr) underflow 8-bit,
  // vd wr=1, rd=100 → báo 221/193 thay vì giá trị thật (chứng minh bởi
  // TEST 8 của tb_token_fifo_advanced: 804 mismatch trước khi sửa).
  always_comb occupancy_cnt = {1'b0, 7'(wr_ptr - rd_ptr)};

  assign fifo_occupancy = occupancy_cnt;  // 8-bit occupancy 0..64

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WRITE SIDE: Accept token if not full
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  always_ff @(posedge clk)
    if (x_token_valid && x_token_ready) begin
      fifo_ram[wr_ptr[ADDR_BITS-1:0]].bbox       <= x_token_data;
      fifo_ram[wr_ptr[ADDR_BITS-1:0]].token_type <= x_token_type;
    end

  assign x_token_ready = ~fifo_full;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // READ SIDE: FWFT — Combinatorial output (zero latency)
  //
  // [FIX] token_o và token_valid_o là combinatorial:
  //   - token_o phản chiếu fifo_ram[rd_ptr] NGAY LẬP TỨC
  //   - token_valid_o = !fifo_empty NGAY LẬP TỨC
  //   - Khi TB đọc token_o tại bất kỳ thời điểm nào sau valid=1,
  //     nó luôn thấy đúng entry hiện tại, không bị trễ 1 cycle.
  //
  // So sánh với thiết kế cũ (registered output):
  //   - Cũ: token_o <= fifo_ram[rd_ptr] — latch qua FF, trễ 1 cycle
  //   - Mới: token_o = fifo_ram[rd_ptr] — assign trực tiếp, tức thì
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  assign token_o       = fifo_ram[rd_ptr[ADDR_BITS-1:0]].bbox;
  assign token_type_o  = fifo_ram[rd_ptr[ADDR_BITS-1:0]].token_type;
  assign token_valid_o = ~fifo_empty;

endmodule
// ================================================================================