// ============================================================================
// File     : rtl/src/bert/gru_waypoint_decoder.sv
// Module   : gru_waypoint_decoder
// Spec     : §7 (GRU Computation) + §15.12 (Interface) — VLA-HMAO v15.5
//
// Summary  : Decodes 4 (x,y) waypoints from CLS FP32 token by running 4 GRU
//            steps.  Each step computes (PyTorch-compatible, §7.1):
//              z_t = σ( W_iz·x + W_hz·h + b_z )
//              r_t = σ( W_ir·x + W_hr·h + b_r )
//              n_t = tanh( W_in·x + b_n_ih + r_t ⊙ (W_hn·h + b_n_hh) )
//              h_t = (1-z_t)⊙n_t + z_t⊙h_prev
//              wp  = W_out·h_t + b_out          → waypoint (x,y)
//
// Quantisation: INT4 weights (URAM, 6 matrices) via gru_int4_dequant.
//               FP32 accumulation via gru_fp32_fmac.
//               Per-row scale/ZP from gru_scale_lutram (6 instances).
//
// Latency  : ≤ GRU_LATENCY_CY = 6 500 000 cy @ 200 MHz  (§7.2).
//            6 297 600 MAC cycles + ~200 000 overhead.
//
// Sub-module pipeline latencies (§7.4–7.6):
//   gru_int4_dequant  : DEQUANT_LAT = 8 cy  (fully pipelined, 1/cy throughput)
//   gru_fp32_fmac     : FMAC_LAT   = 6 cy  (fully pipelined, 1/cy throughput)
//   gru_scale_lutram  : SCALE_LAT  = 1 cy
//   fp32_sigmoid_lut  : SIG_LAT    = 3 cy  (2 instances: z-gate, r-gate)
//   fp32_tanh_lut     : TANH_LAT   = 3 cy  (1 instance: n-gate)
//   nan_inf_detector  : 1 cy               (on fmac_acc output)
//   Xilinx FP32 adder/sub/mul wrappers: FP_LAT = 3 cy each
//
// INT4 pipeline alignment (§7.5 [v15.3-B04]):
//   acc_clear issued at row start (col=0).  First dequant also issued at
//   col=0; first fma_en fires at col=8 (dequant latency).
//   8 – 0 = 8 ≥ 6 ✓  (acc_clear constraint met).
//   b-operand (x_t / h_prev) is fetched at the same cycle as dequant and
//   delayed through a DEQUANT_LAT-stage shift register to align with
//   dequant output.
//
// URAM addressing (§7.3):
//   gru_uram_addr[16:12] = rel_block[4:0]  (0..23; abs = 48 + rel_block)
//   gru_uram_addr[11: 0] = within[11:0]
//   rel_block = matrix_id*4 + row[8:7]          (4 blocks per matrix)
//   within    = row[6:0]*32 + col[9:4]           (32 beats/row, 16 INT4/beat)
//
// Scratch layout (FP32 × 32b, single-port BRAM):
//   [   0..  511] h_prev / h_t  (zeroed before step 0 [v15.3-R11])
//   [ 512..1023 ] z_t  (first holds W_iz·x partial sum, then z_t)
//   [1024..1535 ] r_t  (first holds W_ir·x partial sum, then r_t)
//   [1536..2047 ] n_ih = W_in·x + b_n_ih
//   [2048..2559 ] n_hh = W_hn·h + b_n_hh         (per spec §15.12)
//
// [v15.3-R11] : scratch[0..511] zeroed at INIT phase (every gru_start).
// [V15-C02]   : wout_bram_addr is [10:0] (was [9:0] — now covers 0..1025).
// [§15.12]    : TDP RAW ≥ 1 cy enforced after n_hh scratch write.
// ============================================================================
`timescale 1ns/1ps

module gru_waypoint_decoder
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,

  // ── Control ───────────────────────────────────────────────────────────────
  input  logic          gru_start,          // 1-cycle pulse; begin all 4 steps

  // ── CLS FP32 buffer read (x_t; same for all 4 steps) ─────────────────────
  output logic  [8:0]   cls_buf_rd_addr,    // 0..511
  input  fp32_t         cls_buf_rd_data,
  output logic          cls_buf_rd_en,

  // ── URAM bank A (even beat-pairs, rel-blocks 0..11 = abs 48..59) ──────────
  output logic [16:0]   gru_uram_addr,      // [16:12]=rel_block 0..11, [11:0]=within
  input  logic [63:0]   gru_uram_rdata,     // 16 INT4 packed (lo→hi nibble order)
  output logic          gru_uram_en,

  // ── URAM bank B (odd beat-pairs, rel-blocks 12..23 = abs 60..71) ──────────
  output logic [16:0]   gru_uram_addr_b,    // [16:12]=rel_block 12..23, [11:0]=within
  input  logic [63:0]   gru_uram_rdata_b,
  output logic          gru_uram_en_b,

  // ── Bias BRAM (FP32, 2048×32b = 4 bias vectors × 512) ───────────────────
  output logic [10:0]   gru_bias_addr,      // 0..2047
  input  logic [31:0]   gru_bias_rdata,

  // ── W_out BRAM (FP32, 1026×32b) [V15-C02: addr [10:0]] ──────────────────
  // addr 0..511  : W_out[0,*] (x-row)     addr 512..1023: W_out[1,*] (y-row)
  // addr 1024    : b_out[0]               addr 1025      : b_out[1]
  output logic [10:0]   wout_bram_addr,
  input  logic [31:0]   wout_bram_rdata,

  // ── GRU per-row scale LUTRAMs (external 6-instance bank) ─────────────────
  // sel: 0=W_iz 1=W_hz 2=W_ir 3=W_hr 4=W_in 5=W_hn  (§7.3, §15.17)
  output logic  [2:0]   gru_scale_sel,
  output logic  [8:0]   gru_scale_addr,
  input  logic [15:0]   gru_scale_rdata,    // {scale_q8[7:0], zp[7:0]}

  // ── wp_proj BRAM (FP32, 1536×32b: W[:,0] W[:,1] b_wp) ───────────────────
  output logic [10:0]   wp_proj_bram_addr,
  input  logic [31:0]   wp_proj_bram_rdata,
  output logic          wp_proj_bram_en,

  // ── Waypoint outputs ──────────────────────────────────────────────────────
  output fp32_t         waypoint_x [NUM_WAYPOINTS-1:0],
  output fp32_t         waypoint_y [NUM_WAYPOINTS-1:0],
  output logic          waypoints_valid,    // 1-cy pulse after step 3
  output logic          gru_done            // 1-cy pulse after all 4 steps
);

// ============================================================================
// PARAMETERS
// ============================================================================
  localparam int DEQUANT_LAT   = 8;
  localparam int FMAC_LAT      = 6;
  // TIMING FIX (post-route 185MHz closure): fp32_sigmoid_lut/fp32_tanh_lut
  // latency grew 3->4->5 cycles across two pipelining rounds (first split
  // barrel-shift from divide+clamp+read; second split IEEE-754 decode from
  // the barrel-shift itself, since post-route re-synth showed the first
  // split alone wasn't enough -- WNS only improved -7.791->-3.751ns; see
  // those files' own header comments for the full root-cause history).
  // Every post_cnt case label downstream of a sigmoid/tanh issue point in
  // this FSM's hand-scheduled S_MV_POST case blocks (mat=1, mat=3, mat=5)
  // has been shifted by the same fixed +1 cycle again to match -- this is
  // documentation only, SIG_LAT/TANH_LAT are not read anywhere else in this
  // file (the real schedule is the literal post_cnt case labels below).
  // SIG_LAT grew again (6->7, 4th pipelining round): fp32_sigmoid_lut's
  // divide-by-6 was further isolated onto its own registered stage (split
  // from the round-bias/width-narrow step) after an isolated post-synth
  // check of the 3rd-round design still showed a small negative WNS
  // (-0.305ns); see that module's own header comment for the full
  // history. TANH_LAT is unaffected -- fp32_tanh_lut has no divide (only a
  // power-of-2 shift), so its own critical path was never the bottleneck
  // and stays at 5 cycles.
  localparam int SIG_LAT       = 7;
  localparam int TANH_LAT      = 5;
  localparam int FP_LAT        = 3;   // adder/sub/mul Xilinx FP IP pipeline depth
  localparam int URAM_LAT      = 3;   // URAM read latency [IMPL 150 MHz, 04/10: XPM READ_LATENCY 2 + arbiter = 3]
  localparam int BEATS_PER_ROW = GRU_HIDDEN / 16; // 32 (16 INT4 per 64-bit beat)
  localparam int BEAT_PAIRS    = BEATS_PER_ROW / 2;  // 16 (dual-port read per cycle)
  localparam int N_PAR         = 32;  // parallel MACs (= BEAT_PAIRS × 2 nibbles)
  localparam int DRAIN_LAT     = DEQUANT_LAT + FMAC_LAT + 1; // 15 drain cycles: dq_valid_in NBA→visible +1; DEQUANT +8; FMAC_en→acc_NBA +6; acc_NBA→valid +1 = 16cy from uram_beat_valid, drain must cover this

  localparam fp32_t FP32_ONE  = 32'h3F800000;  // 1.0f
  localparam fp32_t FP32_ZERO = 32'h00000000;

  // Bias base addresses (§7.1 pre-combined vectors)
  localparam int BIAS_BZ    =    0;   // b_z   = b_iz + b_hz  (vector 0)
  localparam int BIAS_BR    =  512;   // b_r                  (vector 1)
  localparam int BIAS_N_IH  = 1024;   // b_n_ih               (vector 2)
  localparam int BIAS_N_HH  = 1536;   // b_n_hh               (vector 3)

  // Scratch base addresses
  localparam int SCR_H     =    0;   // h_prev / h_t
  localparam int SCR_Z     =  512;   // z_t  (temp: W_iz·x partial)
  localparam int SCR_R     = 1024;   // r_t  (temp: W_ir·x partial)
  localparam int SCR_N_IH  = 1536;   // n_ih
  localparam int SCR_N_HH  = 2048;   // n_hh (§15.12)
  localparam int SCR_X_T   = 2560;   // x_t_eff = cls + W_wp*prev_wp + b_wp (steps 1-3)

  // Matrix ordering:
  //  idx  name  b-src   gate  bias-vec   scratch-dst
  //   0   W_iz  CLS(x)   z    —          SCR_Z (partial sum only)
  //   1   W_hz  SCR_H    z    BIAS_BZ    SCR_Z (full z_t after sigmoid)
  //   2   W_ir  CLS(x)   r    —          SCR_R (partial sum only)
  //   3   W_hr  SCR_H    r    BIAS_BR    SCR_R (full r_t after sigmoid)
  //   4   W_in  CLS(x)   n    BIAS_N_IH  SCR_N_IH
  //   5   W_hn  SCR_H    n    BIAS_N_HH  SCR_N_HH + inline h_t compute

  function automatic logic mat_is_hidden(logic [2:0] m);
    // Returns 1 for hidden matrices (b = h_prev from scratch)
    return m[0]; // odd indices: 1,3,5
  endfunction

// ============================================================================
// FSM STATE ENCODING
// ============================================================================
  typedef enum logic [4:0] {
    S_IDLE,          // await gru_start
    S_INIT,          // zero scratch[0..511] (h_0 = 0, [v15.3-R11])

    // ── INT4 matrix-vector multiply (shared for all 6 matrices) ────────────
    S_MV_SETUP,      // cycle 0 of row: acc_clear + scale_req + first URAM req
    S_MV_COL,        // ~32 cycles: 16 beat-pairs × 2cy/pair (N=32 parallel MACs)
    S_MV_DRAIN,      // DRAIN_LAT=13 cycles: wait for last FMA to propagate
    S_ADDER_TREE,    // 1 cycle: reduce 32 partial accumulators → acc_row
    S_MV_POST,       // mat-specific post-row operations (sub-sequenced by post_cnt)

    // ── FP32 W_out projection (2 rows: x then y) ───────────────────────────
    S_WOUT_SETUP,    // acc_clear + 6-cy wait (overlap with BRAM pre-reads)
    S_WOUT_COL,      // 512 FP32 MACs (h_t from scratch, W_out from bram)
    S_WOUT_DRAIN,    // FMAC_LAT drain
    S_WOUT_BIAS,     // read b_out, add via FP adder, latch waypoint

    // ── Autoregressive wp_proj injection (before steps 1-3) ─────────────────
    S_WP_APPLY,      // compute x_t_eff[j]=cls[j]+W_wp[j,:]*prev_wp+b_wp[j] → scratch

    S_HT_COMMIT,     // copy h_t from SCR_X_T(80..95) → SCR_H(0..15) after mat=5 (fix F8)

    S_STEP_DONE,     // increment step counter; loop back or finish
    S_DONE
  } gru_state_t;

  gru_state_t state;

// ============================================================================
// COUNTERS & CONTROL REGISTERS
// ============================================================================
  logic [1:0] step_cnt = '0;        // 0..3
  logic [2:0] mat_idx = '0;         // 0..5
  logic [9:0] row_cnt = '0;         // 0..511 output row (output channel)
  logic [9:0] col_cnt = '0;         // 0..511 col counter (reused in S_WOUT_COL)
  logic [3:0] beat_pair_cnt = '0;   // 0..15: current beat-pair in S_MV_COL
  // Widened 5->6 bits (post_cnt now must reach 32, see mat=5's row-advance
  // step) after SIG_LAT/TANH_LAT grew 3->4 cycles (timing fix, see above).
  logic [5:0] post_cnt = '0;        // sub-cycle counter within S_MV_POST
  logic [4:0] drain_cnt = '0;       // 0..(DRAIN_LAT-1)=0..12 (5-bit, was 3-bit)
  // [Fix Q] Do tre duong ong cay cong (5 tang); FSM dem at_cnt den AT_LAT.
  // [Fix X2] AT_LAT = 10, KHONG phai 9.
  // Truy vet tung nhip: nhip 1 nap, nhip 2-5 muc 1, nhip 6-7 muc 2, nhip 8 muc 3,
  // nhip 9 muc 4, nhip 10 muc 5. FSM chot acc_row khi at_cnt == AT_LAT, ma gan
  // khong chan chi co hieu luc CUOI nhip -> chot o at_cnt=9 se lay ket qua MUC 4
  // (tong 16 lan dau) chu khong phai tong du 32 lan. Do duoc: 0/4 waypoint dat.
  localparam int AT_LAT = 30;   // [TIMING 150 MHz] cay cong co duong ong (xem adder_tree_cap)
  logic [4:0] at_cnt = '0;
  logic [9:0] init_cnt = '0;        // 0..511 for S_INIT scratch zeroing + CLS pre-load
  logic [2:0] setup_cnt = '0;       // 0..(FMAC_LAT-1) for S_WOUT_SETUP
  logic wout_row = '0;        // 0 = x-row (W_out[0]), 1 = y-row (W_out[1])
  logic [1:0] wout_sub = '0;  // [TIMING 150 MHz] dem 0..3, giu moi cot WOUT 4 chu ky

  // S_WP_APPLY counters and pipeline registers
  logic [4:0] wp_ph = '0;           // 0..17: sub-phase within each output row
  logic [9:0] wp_cnt = '0;          // 0..511: current output element j
  fp32_t wp_x_prev = '0;       // prev waypoint x (latched at S_STEP_DONE)
  fp32_t wp_y_prev = '0;       // prev waypoint y
  fp32_t wp_w1_latch = '0;     // W_wp[j,1] latched from BRAM at wp_ph=2
  fp32_t wp_b_latch = '0;      // b_wp[j]   latched from BRAM at wp_ph=3
  fp32_t wp_cls_latch = '0;    // cls_buf[j] latched at wp_ph=3
  fp32_t wp_m0 = '0;           // W_wp[j,0]*wp_x_prev, latched at wp_ph=4

// ============================================================================
// URAM PIPELINE REGISTERS
// ============================================================================
  logic [63:0] uram_beat_a_reg = '0;   // 16 INT4 nibbles from bank A (even beat)
  logic [63:0] uram_beat_b_reg = '0;   // 16 INT4 nibbles from bank B (odd beat)
  logic uram_beat_valid = '0;   // both beat registers hold valid data
  logic [3:0] uram_lat_cnt = '0;      // countdown from URAM_LAT-1 to 0
  logic uram_read_pending = '0; // URAM read in flight

  // Scale/ZP for current row (latched from gru_scale_rdata after 1 cy)
  logic [15:0] row_scale_reg = '0;     // {scale_q8[7:0], zp[7:0]}
  logic row_scale_valid = '0;

// ============================================================================
// b-OPERAND DELAY PIPELINE (N=32 parallel)
// Align 32 b-values (x_t / h_prev) with dequant output.
// par_b_pipe[k][0] is loaded from internal LUTRAM 1 cy after address issued.
// par_b_pipe[k][DEQUANT_LAT-1] arrives at FMAC simultaneously with dq_valid_out.
// ============================================================================
  fp32_t par_b_pipe [N_PAR-1:0][DEQUANT_LAT-1:0];
  // Sequential read path for S_MV_POST, S_WOUT_COL (single-element, 1-cy latency)
  logic [4:0] scr_rd_bank = '0;    // scratch bank 0..31
  logic [6:0] scr_rd_baddr = '0;   // scratch bank address 0..95
  fp32_t scr_rdata = '0;      // registered output (BRAM_LAT=1 emulation)
  // Address register for b-operand parallel read (issued 1 cy before par_b_pipe load)
  logic [6:0] scr_bp_addr_reg = '0; // registered beat-pair base address

// ============================================================================
// INTERNAL SCRATCH LUTRAM (32-bank × 96-entry × FP32)
// Replaces external gru_scratch_bram.  Element e: bank=e%32, baddr=e/32.
//   SCR_H   [  0.. 511]: bank k, baddr  0..15  (base addr per bank = 0)
//   SCR_Z   [512..1023]: bank k, baddr 16..31  (base = 16)
//   SCR_R   [1024..1535]: bank k, baddr 32..47 (base = 32)
//   SCR_N_IH[1536..2047]: bank k, baddr 48..63 (base = 48)
//   SCR_N_HH[2048..2559]: bank k, baddr 64..79 (base = 64)
//   SCR_X_T [2560..3071]: bank k, baddr 80..95 (base = 80)
// ============================================================================
  // [Fix AA] 32 mang 1 CHIEU rieng, suy ra LUTRAM - thay cho mang 2 chieu.
  //
  // Ban cu `fp32_t scr [N_PAR-1:0][95:0]` co CA HAI chi so la bien va bi ghi tu
  // 11 cau lenh rai rac, nen Vivado tu choi suy ra RAM (Synth 8-7186 "incorrect
  // usage") va dung 98.304 flip-flop + cay mux 96:1 moi bank. Do duoc tren
  // gru_fixY: 23.222 F7MUX (20,2% toan chip), 109.287 FF, chi 1.475 CARRY8 -
  // khoi nay la may MULTIPLEXER chu khong phai may so hoc.
  //
  // Mau nay chinh la mau da hoat dong trong bert_encoder_layer (gen_k_scratch,
  // gen_pp_mirror...). ram_style=distributed: LUTRAM doc BAT DONG BO, tuc ngu
  // nghia GIONG HET mang thanh ghi (doc to hop, ghi dong bo) -> khong doi do tre.

  // ---- Cong GHI hop nhat (xem always_comb scr_write_port ben duoi) ----------
  logic        scr_we     = 1'b0;   // ghi MOT bank
  logic        scr_we_all = 1'b0;   // ghi dong loat 32 bank (chi dung o S_INIT)
  logic [4:0]  scr_wbank  = '0;
  logic [6:0]  scr_waddr  = '0;
  fp32_t       scr_wdata  = '0;

  // ---- 4 cong DOC (bat dong bo). Bank bien -> doc het roi mux dau ra. -------
  // A: 32 bank song song, dia chi CHUNG  = scr_bp_addr_reg          (dong ~575)
  // B: mot phan tu, bank scr_rd_bank     addr scr_rd_baddr          (dong ~532)
  // C: mot phan tu, bank col_cnt[4:0]    addr col_cnt[9:5]          (dong ~604)
  // D: mot phan tu, bank row_cnt[4:0]    addr 80+row_cnt[9:5]  (S_HT_COMMIT)
  fp32_t scr_qa [N_PAR-1:0];
  fp32_t scr_qb [N_PAR-1:0];
  fp32_t scr_qc [N_PAR-1:0];
  fp32_t scr_qd [N_PAR-1:0];

  genvar gsb;
  generate
    for (gsb = 0; gsb < N_PAR; gsb++) begin : gen_scr_bank
      (* ram_style = "distributed" *)
      fp32_t mem [0:95];

      always_ff @(posedge clk) begin
        if (scr_we_all || (scr_we && scr_wbank == 5'(gsb)))
          mem[scr_waddr] <= scr_wdata;
      end

      assign scr_qa[gsb] = mem[scr_bp_addr_reg];
      assign scr_qb[gsb] = mem[scr_rd_baddr];
      assign scr_qc[gsb] = mem[{3'b0, col_cnt[9:5]}];
      assign scr_qd[gsb] = mem[7'd80 + {3'b0, row_cnt[9:5]}];
    end
  endgenerate

  // Mux dau ra cho 3 cong bank-bien
  wire fp32_t scr_rd_b = scr_qb[scr_rd_bank];
  wire fp32_t scr_rd_c = scr_qc[col_cnt[4:0]];
  wire fp32_t scr_rd_d = scr_qd[row_cnt[4:0]];

  // Doc bank-bien chi de $display (chi mo phong; tong hop bo $display nen
  // khong ton dien tich). Dung case chi so HANG vi khong the index generate
  // bang bien.
  function automatic fp32_t scr_dbg(input int bk, input int ad);
    case (bk)
       0: return gen_scr_bank[0].mem[ad];
       1: return gen_scr_bank[1].mem[ad];
       2: return gen_scr_bank[2].mem[ad];
       3: return gen_scr_bank[3].mem[ad];
       4: return gen_scr_bank[4].mem[ad];
       5: return gen_scr_bank[5].mem[ad];
       6: return gen_scr_bank[6].mem[ad];
       7: return gen_scr_bank[7].mem[ad];
       8: return gen_scr_bank[8].mem[ad];
       9: return gen_scr_bank[9].mem[ad];
      10: return gen_scr_bank[10].mem[ad];
      11: return gen_scr_bank[11].mem[ad];
      12: return gen_scr_bank[12].mem[ad];
      13: return gen_scr_bank[13].mem[ad];
      14: return gen_scr_bank[14].mem[ad];
      15: return gen_scr_bank[15].mem[ad];
      16: return gen_scr_bank[16].mem[ad];
      17: return gen_scr_bank[17].mem[ad];
      18: return gen_scr_bank[18].mem[ad];
      19: return gen_scr_bank[19].mem[ad];
      20: return gen_scr_bank[20].mem[ad];
      21: return gen_scr_bank[21].mem[ad];
      22: return gen_scr_bank[22].mem[ad];
      23: return gen_scr_bank[23].mem[ad];
      24: return gen_scr_bank[24].mem[ad];
      25: return gen_scr_bank[25].mem[ad];
      26: return gen_scr_bank[26].mem[ad];
      27: return gen_scr_bank[27].mem[ad];
      28: return gen_scr_bank[28].mem[ad];
      29: return gen_scr_bank[29].mem[ad];
      30: return gen_scr_bank[30].mem[ad];
      31: return gen_scr_bank[31].mem[ad];
      default: return 32'h0;
    endcase
  endfunction

// ============================================================================
// INTERNAL CLS LOCAL BUFFER (32-bank × 16-entry × FP32)
// Holds all 512 CLS FP32 values pre-loaded during S_INIT.
// cls_local[k][bp] = cls_buf[bp*32+k]  (bank k, beat-pair bp = 0..15).
// ============================================================================
  fp32_t cls_local [N_PAR-1:0][BEAT_PAIRS-1:0];

  // CLS pre-load control: issued during S_INIT alongside scratch zeroing
  logic [8:0] cls_ld_addr_d1 = '0;  // registered cls_buf_rd_addr for latching
  logic cls_ld_en_d1 = '0;    // registered cls_buf_rd_en

// ============================================================================
// INTERMEDIATE FP32 REGISTERS (post-row combine phase)
// ============================================================================
  fp32_t acc_row = '0;       // adder-tree reduction result (from par_fmac_acc[*])
  fp32_t scr_rdata_d;   // sequential scratch read result (1-cy registered)
  fp32_t bias_rd_r = '0;     // Bias BRAM read data captured
  fp32_t partial_r = '0;     // Partial sum from first matrix of a gate pair
  fp32_t z_t_r = '0;         // z_t for current row
  fp32_t r_t_r = '0;         // r_t for current row
  fp32_t n_ih_r = '0;        // n_ih for current row
  fp32_t n_hh_r = '0;        // n_hh for current row
  fp32_t n_t_r = '0;         // n_t for current row
  fp32_t h_prev_r = '0;      // h_prev for current row (latched during W_hn post)

  // FP32 arithmetic unit I/O (3-stage pipeline each)
  // Maps to Xilinx FP IP v7.1: Add/Sub/Mul, single-precision.
  // SYNTHESIS: Replace these behavioural pipelines with Xilinx FP32 IP cores.
  fp32_t fp_add_a = '0, fp_add_b = '0;
  fp32_t fp_sub_a = '0, fp_sub_b = '0;
  fp32_t fp_mul_a = '0, fp_mul_b = '0;

  fp32_t fp_add_pipe [FP_LAT:1];
  fp32_t fp_sub_pipe [FP_LAT:1];
  fp32_t fp_mul_pipe [FP_LAT:1];

  fp32_t fp_add_out;   // = fp_add_pipe[FP_LAT]
  fp32_t fp_sub_out;   // = fp_sub_pipe[FP_LAT]
  fp32_t fp_mul_out;   // = fp_mul_pipe[FP_LAT]

  // Waypoint projection accumulator
  fp32_t wp_acc = '0;        // accumulates dot product for current W_out row

// ============================================================================
// SUB-MODULE SIGNAL DECLARATIONS (N=32 parallel instances)
// ============================================================================

  // 32× gru_int4_dequant
  logic  [3:0]  dq_w_int4    [N_PAR-1:0];
  logic  [7:0]  dq_scale_q8;           // shared (same row → same scale)
  logic  [7:0]  dq_zp;                 // shared
  logic         dq_valid_in  [N_PAR-1:0];
  fp32_t        dq_w_fp32    [N_PAR-1:0];
  logic         dq_valid_out [N_PAR-1:0];

  // 32× gru_fp32_fmac
  fp32_t  par_fmac_a   [N_PAR-1:0];
  fp32_t  par_fmac_b   [N_PAR-1:0];
  logic fmac_acc_clear = '0;             // shared: same acc_clear for all instances
  logic   par_fmac_en  [N_PAR-1:0];  // driven from dq_valid_out[k]
  fp32_t  par_fmac_acc [N_PAR-1:0];
  logic   par_fmac_rv  [N_PAR-1:0];

  // Single gru_fp32_fmac for WOUT mode (S_WOUT_COL — still sequential)
  fp32_t  wout_fmac_a, wout_fmac_b;
  logic   wout_fmac_en;
  logic wout_fmac_en_q = '0;    // registered FSM-driven value
  fp32_t  wout_fmac_acc;
  logic   wout_fmac_rv;
  logic fmac_acc_clear_wout = '0;

  // fp32_sigmoid_lut ×2 (z-gate, r-gate)
  fp32_t sig_z_in = '0, sig_z_out;
  logic sig_z_vin = '0, sig_z_vout;
  fp32_t sig_r_in = '0, sig_r_out;
  logic sig_r_vin = '0, sig_r_vout;

  // fp32_tanh_lut
  fp32_t tanh_in = '0, tanh_out;
  logic tanh_vin = '0, tanh_vout;

  // nan_inf_detector on fmac_acc
  logic nan_fault = '0;   // Routes to trajectory_sanity_checker (§15.14)

  // Mode flag (distinguishes INT4 matvec from FP32 WOUT projection)
  logic fmac_wout_mode = '0;   // 1 = WOUT path uses wout_fmac; 0 = N=32 INT4 matvec

// ============================================================================
// URAM ADDRESS DECODER — beat-interleaved N=32 layout
//   Bank A (Port A): rel_block = mat*2 + row[8]      (0..11, abs 48..59)
//   Bank B (Port B): rel_block = 12 + mat*2 + row[8] (12..23, abs 60..71)
//   within = {row[7:0], beat_pair_cnt[3:0]}  (12-bit)
// ============================================================================
  logic [4:0]  uram_rel_a, uram_rel_b;
  logic [11:0] uram_within_bp;  // within for current beat_pair

  assign uram_rel_a     = {2'b0, mat_idx} * 5'd2 + {4'b0, row_cnt[8]};
  assign uram_rel_b     = 5'd12 + {2'b0, mat_idx} * 5'd2 + {4'b0, row_cnt[8]};
  assign uram_within_bp = {row_cnt[7:0], beat_pair_cnt};
  assign gru_uram_addr   = {uram_rel_a, uram_within_bp};
  assign gru_uram_addr_b = {uram_rel_b, uram_within_bp};

// ============================================================================
// SUB-MODULE INSTANTIATIONS
// ============================================================================

  // 32 parallel dequant instances (INT4 matvec)
  generate
    for (genvar k = 0; k < N_PAR; k++) begin : g_dq
      gru_int4_dequant u_dq (
        .clk        (clk),
        .rst_n      (rst_n),
        .w_int4     (dq_w_int4[k]),
        .w_scale_q8 (dq_scale_q8),
        .w_zp       (dq_zp),
        .valid_in   (dq_valid_in[k]),
        .w_fp32     (dq_w_fp32[k]),
        .valid_out  (dq_valid_out[k])
      );
    end
  endgenerate

  // 32 parallel FMAC instances (INT4 matvec)
  generate
    for (genvar k = 0; k < N_PAR; k++) begin : g_fmac
      gru_fp32_fmac u_fmac (
        .clk          (clk),
        .rst_n        (rst_n),
        .a            (par_fmac_a[k]),
        .b            (par_fmac_b[k]),
        .acc_clear    (fmac_acc_clear),
        .fma_en       (par_fmac_en[k]),
        .acc          (par_fmac_acc[k]),
        .result_valid (par_fmac_rv[k])
      );
    end
  endgenerate

  // Single FMAC for WOUT FP32 projection (S_WOUT_COL, sequential)
`ifdef XPROBE
  // Lay mau acc_row tai S_MV_POST post_cnt==0 (luc nay acc_row DA on dinh),
  // kem toan hang b dang dung de xac nhan doc dung vung scratch.
  logic [5:0] xp_mat_done = '0;
  always_ff @(posedge clk) begin
    if (rst_n && state == S_MV_POST && post_cnt == 6'd0 && step_cnt == 2'd0
        && row_cnt == 10'd0 && !xp_mat_done[mat_idx]) begin
      xp_mat_done[mat_idx] <= 1'b1;
      $display("[MATDBG mat=%0d] acc_row=%08h scale=%0d zp=%0d bp_addr=%0d b0=%08h b1=%08h",
               mat_idx, acc_row, dq_scale_q8, dq_zp, scr_bp_addr_reg,
               gen_scr_bank[0].mem[scr_bp_addr_reg], gen_scr_bank[1].mem[scr_bp_addr_reg]);
    end
    if (rst_n && state == S_MV_SETUP && step_cnt == 2'd0 && mat_idx == 3'd0
        && row_cnt == 10'd0 && !xp_mat_done[5]) begin
      $display("[SCRDBG] SCR_X_T[0..2]=%08h %08h %08h   SCR_H[0..2]=%08h %08h %08h",
               gen_scr_bank[0].mem[80], gen_scr_bank[1].mem[80], gen_scr_bank[2].mem[80],
               gen_scr_bank[0].mem[0],  gen_scr_bank[1].mem[0],  gen_scr_bank[2].mem[0]);
    end
  end
`endif

  gru_fp32_fmac u_fmac_wout (
    .clk          (clk),
    .rst_n        (rst_n),
    .a            (wout_fmac_a),
    .b            (wout_fmac_b),
    .acc_clear    (fmac_acc_clear_wout),
    .fma_en       (wout_fmac_en),
    .acc          (wout_fmac_acc),
    .result_valid (wout_fmac_rv)
  );

  fp32_sigmoid_lut u_sigmoid_z (
    .clk      (clk), .rst_n  (rst_n),
    .x_in     (sig_z_in),  .valid_in  (sig_z_vin),
    .y_out    (sig_z_out), .valid_out (sig_z_vout)
  );

  fp32_sigmoid_lut u_sigmoid_r (
    .clk      (clk), .rst_n  (rst_n),
    .x_in     (sig_r_in),  .valid_in  (sig_r_vin),
    .y_out    (sig_r_out), .valid_out (sig_r_vout)
  );

  fp32_tanh_lut u_tanh (
    .clk      (clk), .rst_n  (rst_n),
    .x_in     (tanh_in),  .valid_in  (tanh_vin),
    .y_out    (tanh_out), .valid_out (tanh_vout)
  );

  // NaN/Inf detection on acc_row after adder tree (§15.14)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) nan_fault <= 1'b0;
    else if (state == S_ADDER_TREE)
      nan_fault <= (acc_row[30:23] == 8'hFF);
  end

// ============================================================================
// BEHAVIOURAL FP32 ARITHMETIC PIPELINE
// SYNTHESIS: Replace with Xilinx Floating-Point IP v7.1 cores.
//   Each is a 3-stage pipeline on fp32_t (logic [31:0]).
//   No valid/enable signals — always-on pipeline.
// ============================================================================
`ifdef SYNTHESIS
  // [TIMING 150 MHz, 03/10] Don vi FP32 CO DUONG ONG 3 tang thay cho ham to hop o tang 1:
  // fp32_add_p #(LEGACY_ZERO=1) == fp32_add_f, fp32_mul_p == fp32_mul_f (tung bit, 700.000 cap
  // moi loai: tb/unit/tb_fp32_add_legacy, tb_fp32_mul_equiv). Do tre giu nguyen FP_LAT = 3
  // (dau vao thanh ghi o canh X -> ket qua hop le o chu ky X+4, nhu fp_*_pipe[FP_LAT] cu).
  fp32_t fp_add_r, fp_sub_r, fp_mul_r;
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_fpa (.clk, .a(fp_add_a), .b(fp_add_b), .r(fp_add_r));
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_fps (.clk, .a(fp_sub_a), .b({~fp_sub_b[31], fp_sub_b[30:0]}), .r(fp_sub_r));
  fp32_mul_p                       u_fpm (.clk, .a(fp_mul_a), .b(fp_mul_b), .r(fp_mul_r));
`else
  always_ff @(posedge clk) begin : fp32_arith_pipes
    shortreal ra_add, rb_add, ra_sub, rb_sub, ra_mul, rb_mul;

    ra_add = $bitstoshortreal(fp_add_a);
    rb_add = $bitstoshortreal(fp_add_b);
    fp_add_pipe[1] <= $shortrealtobits(ra_add + rb_add);

    ra_sub = $bitstoshortreal(fp_sub_a);
    rb_sub = $bitstoshortreal(fp_sub_b);
    fp_sub_pipe[1] <= $shortrealtobits(ra_sub - rb_sub);

    ra_mul = $bitstoshortreal(fp_mul_a);
    rb_mul = $bitstoshortreal(fp_mul_b);
    fp_mul_pipe[1] <= $shortrealtobits(ra_mul * rb_mul);

    for (int s = 2; s <= FP_LAT; s++) begin
      fp_add_pipe[s] <= fp_add_pipe[s-1];
      fp_sub_pipe[s] <= fp_sub_pipe[s-1];
      fp_mul_pipe[s] <= fp_mul_pipe[s-1];
    end
  end
`endif

`ifdef SYNTHESIS
  assign fp_add_out = fp_add_r;
  assign fp_sub_out = fp_sub_r;
  assign fp_mul_out = fp_mul_r;
`else
  assign fp_add_out = fp_add_pipe[FP_LAT];
  assign fp_sub_out = fp_sub_pipe[FP_LAT];
  assign fp_mul_out = fp_mul_pipe[FP_LAT];
`endif

// ============================================================================
// INTERNAL SCRATCH REGISTERED READ (single element, 1-cycle latency)
// Used by S_MV_POST and S_WOUT_COL for sequential element access.
// ============================================================================
  always_ff @(posedge clk) begin : scr_seq_read
    scr_rdata <= scr_rd_b;   // [Fix AA] cong doc B
  end
  // Alias for backward-compatible naming (replaces gru_scratch_rdata)
  wire fp32_t scratch_rd_r = scr_rdata;  // used in S_MV_POST locals

// ============================================================================
// CLS LOCAL BUFFER AUTO-LATCH
// Whenever cls_buf_rd_en was issued, latch read data into cls_local[k][bp].
// cls_ld_addr_d1 holds the address from the previous cycle.
// ============================================================================
  initial begin : cls_local_init   // [Fix I] khop hanh vi nap cau hinh FPGA
    for (int bi = 0; bi < N_PAR; bi++)
      for (int bj = 0; bj < 16; bj++) cls_local[bi][bj] = '0;
  end

  always_ff @(posedge clk) begin : cls_latch
    cls_ld_addr_d1 <= cls_buf_rd_addr;
    cls_ld_en_d1   <= cls_buf_rd_en;
    if (cls_ld_en_d1) begin
      // addr_d1 = previously issued address; data now available in cls_buf_rd_data
      cls_local[cls_ld_addr_d1[4:0]][{1'b0, cls_ld_addr_d1[8:5]}]
        <= cls_buf_rd_data;
    end
  end

// ============================================================================
// PARALLEL b-OPERAND PIPELINE (N=32)
// par_b_pipe[k][0] loads from scr_bp_addr_reg (registered 1cy after issue).
// Shifts through DEQUANT_LAT-1 more stages → arrives at par_b_pipe[k][7]
// at the same time as dq_valid_out[k] (= dq_valid_in + DEQUANT_LAT cycles).
// ============================================================================
  always_ff @(posedge clk) begin : par_b_shift
    if (!rst_n) begin
      for (int k = 0; k < N_PAR; k++)
        for (int i = 0; i < DEQUANT_LAT; i++) par_b_pipe[k][i] <= FP32_ZERO;
      scr_bp_addr_reg <= 7'd0;
    end else begin
      scr_bp_addr_reg <= (mat_is_hidden(mat_idx))
                         ? {3'b0, beat_pair_cnt}              // SCR_H base=0
                         : 7'd80 + {3'b0, beat_pair_cnt};    // SCR_X_T base=80
      // Load par_b_pipe[k][0] from registered source (1-cy latency)
      // All steps (0-3): input matrices use SCR_X_T (set by S_WP_APPLY, incl. step 0 with b_wp)
      for (int k = 0; k < N_PAR; k++) begin
        par_b_pipe[k][0] <= scr_qa[k];   // [Fix AA] cong doc A
      end
      // Shift pipeline
      for (int k = 0; k < N_PAR; k++)
        for (int i = 1; i < DEQUANT_LAT; i++)
          par_b_pipe[k][i] <= par_b_pipe[k][i-1];
    end
  end

// ============================================================================
// PARALLEL FMAC INPUTS
//   INT4 matvec: a[k] = dq_w_fp32[k], b[k] = par_b_pipe[k][DEQUANT_LAT-1]
//   WOUT path uses wout_fmac_a/b separately
// ============================================================================
  generate
    for (genvar k = 0; k < N_PAR; k++) begin : g_fmac_in
      assign par_fmac_a[k] = dq_w_fp32[k];
      assign par_fmac_b[k] = par_b_pipe[k][DEQUANT_LAT-1];
      assign par_fmac_en[k] = dq_valid_out[k];
    end
  endgenerate

// ============================================================================
// WOUT FMAC INPUTS (sequential FP32 W_out projection)
// ============================================================================
  // wout_scr_rdata: registered read from internal scr for h_t in S_WOUT_COL
  fp32_t wout_scr_data = '0;
  always_ff @(posedge clk) begin : wout_scr_rd
    // col_cnt[4:0] = bank, col_cnt[9:5] = baddr within SCR_H
    wout_scr_data <= scr_rd_c;   // [Fix AA] cong doc C
  end
  assign wout_fmac_a  = wout_bram_rdata;
  assign wout_fmac_b  = wout_scr_data;
  assign wout_fmac_en = fmac_wout_mode ? wout_fmac_en_q : 1'b0;

// ============================================================================
// PARALLEL DEQUANT INPUT DRIVE (N=32)
//   k=0..15:  nibble from uram_beat_a_reg (bank A, even beat)
//   k=16..31: nibble from uram_beat_b_reg (bank B, odd beat)
//   scale_q8/zp shared (same row → same quantization parameters).
// ============================================================================
  assign dq_scale_q8 = row_scale_reg[15:8];
  assign dq_zp       = row_scale_reg[7:0];
  generate
    for (genvar k = 0; k < N_PAR; k++) begin : g_dq_in
      assign dq_w_int4[k] = (k < 16) ? uram_beat_a_reg[k*4 +: 4]
                                      : uram_beat_b_reg[(k-16)*4 +: 4];
    end
  endgenerate

// ============================================================================
// ADDER-TREE COMBINATIONAL REDUCTION (N=32 par_fmac_acc → scalar)
// Behavioral simulation model; replace with Xilinx FP32 adder-tree IP for synthesis.
// ============================================================================
  fp32_t acc_tree;
`ifndef SYNTHESIS
  always_comb begin : adder_tree_comb
    shortreal sum_sr;
    sum_sr = 0.0;
    for (int k = 0; k < N_PAR; k++)
      sum_sr += $bitstoshortreal(par_fmac_acc[k]);
    acc_tree = $shortrealtobits(sum_sr);
  end
`else
  // [Fix X] Cay cong DON KENH: 4 bo cong thay vi 31.
  //
  // Ly do: cay 31 bo chi lam viec 6 chu ky tren ~65 chu ky moi hang (~9% thoi
  // gian) nhung chiem cho 100%. Build truoc that bai vi TAC NGHEN dinh tuyen
  // (216.196 tin hieu khong dinh tuyen duoc, muc 6-7) du tai nguyen moi dung
  // 79,5%. Moi bo cong FP32 ton ~900 LUT nen 27 bo bo di tiet kiem ~24.000 LUT.
  //
  // THU TU CONG GIU NGUYEN Y HET cay can bang cu -> ket qua giong het tung bit.
  //   at_cnt=0        : nap 32 gia tri
  //   at_cnt=1..4     : muc 1 (32->16), 4 phep/chu ky
  //   at_cnt=5..6     : muc 2 (16->8)
  //   at_cnt=7        : muc 3 (8->4)
  //   at_cnt=8        : muc 4 (4->2)
  //   at_cnt=9        : muc 5 (2->1)
  // Tong 10 chu ky thay vi 6 -> +4 chu ky/hang = +0,73% thoi gian.
  //
  // An toan ghi-doc: moi chu ky ghi atw[p..p+3] va doc atw[2p..2p+7]; vi p < 2p
  // nen nguon luon duoc doc TRUOC khi bi ghi de.
  fp32_t atw [0:31];

  // [Fix Y] CHIA SE PHAN CUNG — 4 bo cong, khong phai 30.
  //
  // Ban Fix X viet moi tang thanh mot nhanh `case` rieng. Vi cac nhanh ghi vao
  // PHAN TU KHAC NHAU cua atw, Vivado khong the gop chung bo cong: no tong hop
  // 7 nhanh x 4 + 2 (default) = 30 ban fp32_add_f to hop song song. Do la ly do
  // (u_gru) chiem 48.953 LUT va vung Y23..Y200 co Avg LUT Input = 5,3..5,6
  // (may logic fan-in cao -> nhu cau dinh tuyen cuc dai -> tac nghen muc 6).
  //
  // Sua: dua 4 bo cong ra always_comb DUNG CHUNG; toan hang chon qua at_src_base,
  // `case` chi con mux DICH bang chi so HANG (nen atw van la thanh ghi, khong bi
  // suy ra RAM). So hoc va thu tu cong giu nguyen tung bit; so chu ky van la 10.
  // [TIMING 150 MHz, 02/10] Cay cong co DUONG ONG: toan hang chot vao thanh ghi o chu ky
  // "bat" (cap), cong bang fp32_add_p #(LEGACY_ZERO=1) 3 tang (chung minh trung tung bit
  // voi fp32_add_f: tb/unit/tb_fp32_add_legacy.sv, 700.000 cap), ket qua ghi atw o cap+4.
  // Thu tu va cap toan hang GIU NGUYEN 9 buoc cu -> ket qua giong het tung bit.
  //   buoc : 1  2  3  4  5  6  7  8  9      (buoc cu = at_cnt cu)
  //   cap  : 1  2  3  4  9  10 15 20 25
  //   ghi  : 5  6  7  8  13 14 19 24 29      ; chot acc_row o at_cnt = AT_LAT = 30
  //   nguon: 0  8  16 24 0  8  0  0  0       ; dich: 0 4 8 12 0 4 0 0 0
  // Phu thuoc: buoc 5 doc atw[0..7] (ghi o 5,6), buoc 6 doc atw[8..15] (ghi o 7,8),
  // buoc 7 doc atw[0..7] (ghi o 13,14), buoc 8 doc 19, buoc 9 doc 24 -> deu sau khi ghi.
  logic       at_cap;
  logic [4:0] at_src_base;
  always_comb begin
    at_cap = 1'b1; at_src_base = 5'd0;
    case (at_cnt)
      5'd1, 5'd9, 5'd15, 5'd20, 5'd25: at_src_base = 5'd0;
      5'd2, 5'd10:                     at_src_base = 5'd8;
      5'd3:                            at_src_base = 5'd16;
      5'd4:                            at_src_base = 5'd24;
      default:                         at_cap = 1'b0;
    endcase
  end

  fp32_t at_opa [0:3], at_opb [0:3], at_sum [0:3];
  always_ff @(posedge clk) begin : adder_tree_cap
    if (state == S_ADDER_TREE && at_cap)
      for (int j = 0; j < 4; j++) begin
        at_opa[j] <= atw[at_src_base + 5'(2*j)];
        at_opb[j] <= atw[at_src_base + 5'(2*j) + 5'd1];
      end
  end
  for (genvar gj = 0; gj < 4; gj++) begin : g_at_add
    fp32_add_p #(.LEGACY_ZERO(1'b1)) u_at_add (.clk, .a(at_opa[gj]), .b(at_opb[gj]), .r(at_sum[gj]));
  end

  always_ff @(posedge clk) begin : adder_tree_mux
    if (!rst_n) begin
      for (int k = 0; k < 32; k++) atw[k] <= FP32_ZERO;
    end else if (state == S_ADDER_TREE) begin
      case (at_cnt)
        5'd0:                               for (int k = 0; k < 32; k++) atw[k] <= par_fmac_acc[k];
        5'd5, 5'd13, 5'd19, 5'd24, 5'd29:   for (int j = 0; j < 4; j++) atw[j]    <= at_sum[j];
        5'd6, 5'd14:                        for (int j = 0; j < 4; j++) atw[4+j]  <= at_sum[j];
        5'd7:                               for (int j = 0; j < 4; j++) atw[8+j]  <= at_sum[j];
        5'd8:                               for (int j = 0; j < 4; j++) atw[12+j] <= at_sum[j];
        default: ;
      endcase
    end
  end
  assign acc_tree = atw[0];
`endif


// ============================================================================
// [Fix AA] CONG GHI HOP NHAT cho scratch
//
// Truoc day 11 cau lenh rai rac trong FSM ghi truc tiep vao scr[bank][addr].
// Day la ly do Vivado tu choi suy ra RAM. Nay tat ca gop vao MOT cong ghi.
//
// TUONG DUONG: cac tin hieu duoi day duoc lai TO HOP tu chinh cac thanh ghi ma
// FSM dung (state/mat_idx/post_cnt/row_cnt/wp_cnt/init_cnt), nen tai suon xung
// clock cong ghi thay dung dia chi + du lieu ma lenh cu se ghi. Da doi chieu
// tung dieu kien bao ve: S_MV_POST -> case(mat_idx) -> case/if(post_cnt), khong
// co dieu kien long ngoai nao khac.
// ============================================================================
  always_comb begin : scr_write_port
    scr_we     = 1'b0;
    scr_we_all = 1'b0;
    scr_wbank  = 5'd0;
    scr_waddr  = 7'd0;
    scr_wdata  = FP32_ZERO;

    case (state)
      S_INIT : begin
        // Xoa toan bo 32 bank x 96 o trong 96 chu ky dau (gop ca hai lenh cu).
        if (init_cnt < 10'd96) begin
          scr_we_all = 1'b1;
          scr_waddr  = init_cnt[6:0];
          scr_wdata  = FP32_ZERO;
        end
      end

      S_MV_POST : begin
        scr_wbank = row_cnt[4:0];
        case (mat_idx)
          3'd0 : if (post_cnt == 6'd0)  begin scr_we = 1'b1; scr_waddr = 7'd16 + {3'b0, row_cnt[9:5]}; scr_wdata = acc_row;    end
          3'd1 : if (post_cnt == 6'd18) begin scr_we = 1'b1; scr_waddr = 7'd16 + {3'b0, row_cnt[9:5]}; scr_wdata = sig_z_out;  end
          3'd2 : if (post_cnt == 6'd0)  begin scr_we = 1'b1; scr_waddr = 7'd32 + {3'b0, row_cnt[9:5]}; scr_wdata = acc_row;    end
          3'd3 : if (post_cnt == 6'd18) begin scr_we = 1'b1; scr_waddr = 7'd32 + {3'b0, row_cnt[9:5]}; scr_wdata = sig_r_out;  end
          3'd4 : if (post_cnt == 6'd6)  begin scr_we = 1'b1; scr_waddr = 7'd48 + {3'b0, row_cnt[9:5]}; scr_wdata = fp_add_out; end
          3'd5 : begin
            if (post_cnt == 6'd6)       begin scr_we = 1'b1; scr_waddr = 7'd64 + {3'b0, row_cnt[9:5]}; scr_wdata = fp_add_out; end
            if (post_cnt == 6'd32)      begin scr_we = 1'b1; scr_waddr = 7'd80 + {3'b0, row_cnt[9:5]}; scr_wdata = fp_add_out; end
          end
          default : ;
        endcase
      end

      S_HT_COMMIT : begin
        // Nguon la cong doc D (bat dong bo) -> doc-ghi cung chu ky, dung nhu cu.
        scr_we    = 1'b1;
        scr_wbank = row_cnt[4:0];
        scr_waddr = {3'b0, row_cnt[9:5]};
        scr_wdata = scr_rd_d;
      end

      S_WP_APPLY : begin
        if (wp_ph == 5'd22) begin
          scr_we    = 1'b1;
          scr_wbank = wp_cnt[4:0];
          scr_waddr = 7'd80 + {3'b0, wp_cnt[9:5]};
          scr_wdata = fp_add_out;
        end
      end

      default : ;
    endcase
  end

// ============================================================================
// MAIN FSM
// ============================================================================
  always_ff @(posedge clk or negedge rst_n) begin : main_fsm
    if (!rst_n) begin
      state             <= S_IDLE;
      step_cnt          <= 2'd0;
      mat_idx           <= 3'd0;
      row_cnt           <= 10'd0;
      col_cnt           <= 10'd0;
      beat_pair_cnt     <= 4'd0;
      post_cnt          <= 5'd0;
      drain_cnt         <= 5'd0;
      init_cnt          <= 10'd0;
      setup_cnt         <= 3'd0;
      wout_row          <= 1'b0;
      uram_beat_a_reg   <= 64'd0;
      uram_beat_b_reg   <= 64'd0;
      uram_beat_valid   <= 1'b0;
      uram_lat_cnt      <= 4'd0;
      uram_read_pending <= 1'b0;
      row_scale_reg     <= 16'd0;
      row_scale_valid   <= 1'b0;
      acc_row           <= FP32_ZERO;
      partial_r         <= FP32_ZERO;
      z_t_r             <= FP32_ZERO;
      r_t_r             <= FP32_ZERO;
      n_ih_r            <= FP32_ZERO;
      n_hh_r            <= FP32_ZERO;
      n_t_r             <= FP32_ZERO;
      h_prev_r          <= FP32_ZERO;
      wp_acc            <= FP32_ZERO;
      bias_rd_r         <= FP32_ZERO;
      waypoints_valid   <= 1'b0;
      gru_done          <= 1'b0;
      fmac_wout_mode    <= 1'b0;
      wout_fmac_en_q    <= 1'b0;
      wp_ph             <= 5'd0;
      wp_cnt            <= 10'd0;
      wp_x_prev         <= FP32_ZERO;
      wp_y_prev         <= FP32_ZERO;
      wp_w1_latch       <= FP32_ZERO;
      wp_b_latch        <= FP32_ZERO;
      wp_cls_latch      <= FP32_ZERO;
      wp_m0             <= FP32_ZERO;
      wp_proj_bram_en   <= 1'b0;
      gru_uram_en_b     <= 1'b0;
      fmac_acc_clear_wout <= 1'b0;
      gru_scale_sel     <= 3'd0;
      gru_scale_addr    <= 9'd0;
      for (int k = 0; k < N_PAR; k++) dq_valid_in[k] <= 1'b0;
      for (int w = 0; w < NUM_WAYPOINTS; w++) begin
        waypoint_x[w] <= FP32_ZERO;
        waypoint_y[w] <= FP32_ZERO;
      end
    end else begin
      // Default: pulse outputs cleared each cycle
      waypoints_valid     <= 1'b0;
      gru_done            <= 1'b0;
      for (int k = 0; k < N_PAR; k++) dq_valid_in[k] <= 1'b0;
      wout_fmac_en_q      <= 1'b0;
      fmac_acc_clear      <= 1'b0;
      fmac_acc_clear_wout <= 1'b0;
      gru_uram_en         <= 1'b0;
      gru_uram_en_b       <= 1'b0;
      cls_buf_rd_en       <= 1'b0;
      wp_proj_bram_en     <= 1'b0;
      sig_z_vin           <= 1'b0;
      sig_r_vin           <= 1'b0;
      tanh_vin            <= 1'b0;

      case (state)

        // ──────────────────────────────────────────────────────────────────
        S_IDLE : begin
          fmac_wout_mode <= 1'b0;
          if (gru_start) begin
            step_cnt  <= 2'd0;
            mat_idx   <= 3'd0;
            row_cnt   <= 10'd0;
            init_cnt  <= 10'd0;
            // [E2E 03/10] Waypoint "truoc" cua buoc 0 PHAI = 0 o MOI khung (mo hinh: prev_wp = 0).
            // Truoc day chi xoa khi rst_n -> khung thu 2 tro di dung WP3 cua khung truoc:
            // tb_planning_top_e2e nhieu khung lien tiep: khung#0 dung (<= 11 um), khung#1.. lech
            // 0,5..4,9 m du CLS dung tung bit.
            wp_x_prev <= FP32_ZERO;
            wp_y_prev <= FP32_ZERO;
            state     <= S_INIT;
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // INIT: Zero internal scratch[0..511] (h_0=0) and pre-load CLS buffer.
        //   Each cycle: write scr[e%32][e/32]=0 for element e=init_cnt.
        //   Simultaneously read cls_buf[init_cnt] → cls_local auto-latched next cycle.
        //   After 512 cycles: proceed to first matrix.
        // ──────────────────────────────────────────────────────────────────
        S_INIT : begin
          // [Fix AA] Lenh ghi cu o day DU THUA va da bo: no xoa (bank 0..31,
          // addr 0..15), con lenh cua Fix H ben duoi xoa (bank 0..31, addr 0..95)
          // -> bao trum hoan toan. Nay ca hai gop thanh MOT cong ghi broadcast
          // (xem always_comb scr_write_port).
          // [Fix H] Xoa TOAN BO scratch (32 bang x 96 o), khong chi vung SCR_H.
          // Truoc day chi 512 o (baddr 0..15) duoc xoa; cac vung con lai khoi dong
          // la X, va S_WP_APPLY doc chung ngay o buoc 0 -> X lan vao ca chuoi tinh.
          // 96 chu ky dau cua S_INIT xoa song song ca 32 bang.
          // [Fix AA] chuyen sang cong ghi broadcast scr_we_all (always_comb).
          // Pre-load CLS (auto-latched into cls_local by cls_latch always_ff)
          cls_buf_rd_addr <= init_cnt[8:0];
          cls_buf_rd_en   <= 1'b1;
          init_cnt        <= init_cnt + 10'd1;
          if (init_cnt == 10'd511) begin
            row_cnt          <= 10'd0;
            col_cnt          <= 10'd0;
            beat_pair_cnt    <= 4'd0;
            // [fix12] Run S_WP_APPLY for step 0 too: x_eff=cls+0+0+b_wp (prev_wp=0 from reset)
            wp_cnt           <= 10'd0;
            wp_ph            <= 5'd0;
            state            <= S_WP_APPLY;
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // MV_SETUP: Start of a new output row.
        //   - Latch scale, assert acc_clear for all 32 FMACs.
        //   - URAM reads for beat_pair=0 were pre-issued; start countdown.
        // ──────────────────────────────────────────────────────────────────
        S_MV_SETUP : begin
          row_scale_reg   <= gru_scale_rdata;
          row_scale_valid <= 1'b1;
          fmac_acc_clear  <= 1'b1;  // clear all 32 FMAC accumulators simultaneously
          uram_lat_cnt    <= URAM_LAT[3:0]; // URAM_LAT full counts: enable NBA at T_e-1, S_MV_SETUP at T_e, first S_MV_COL at T_e+1; data valid at T_e+2
`ifndef SYNTHESIS
          if (step_cnt == 2'd0 && mat_idx == 3'd0 && row_cnt == 10'd0)
            $display("[DBG_SETUP] step=0 mat=0 row=0: scale_rdata=%04h scr[0][80]=%08h(%f) scr[1][80]=%08h(%f) cls_local[0][0]=%08h(%f)",
                     gru_scale_rdata,
                     gen_scr_bank[0].mem[80], $bitstoshortreal(gen_scr_bank[0].mem[80]),
                     gen_scr_bank[1].mem[80], $bitstoshortreal(gen_scr_bank[1].mem[80]),
                     cls_local[0][0], $bitstoshortreal(cls_local[0][0]));
          if (step_cnt != 2'd0 && mat_idx == 3'd0 && row_cnt == 10'd0)
            $display("[DBG_SETUP] step=%0d mat=0 row=0: scr[0][80]=%08h(%f)",
                     step_cnt, gen_scr_bank[0].mem[80], $bitstoshortreal(gen_scr_bank[0].mem[80]));
          if (step_cnt == 2'd0 && row_cnt < 10'd64)
            $display("[DBG_SCALE] step=0 mat=%0d row=%0d: scale_rdata=%04h",
                     mat_idx, row_cnt, gru_scale_rdata);
`endif
          uram_read_pending <= 1'b1;
          beat_pair_cnt   <= 4'd0;
          col_cnt         <= 10'd0;
          state           <= S_MV_COL;
        end

        // ──────────────────────────────────────────────────────────────────
        // MV_COL: N=32 parallel beat-pair loop (16 beat-pairs × 2cy each)
        //   Even cycles: latch dual URAM beat (URAM_LAT=2 countdown).
        //   Odd cycles : issue 32 parallel dequants + b-read + next URAM.
        // ──────────────────────────────────────────────────────────────────
        S_MV_COL : begin
`ifndef SYNTHESIS
          // Broad MVC trace: fires every S_MV_COL cycle for first 3 rows of mat=0 step=0
          if (step_cnt == 2'd0 && mat_idx == 3'd0 && row_cnt < 10'd1)
            $display("[MVC t=%0t] lat=%0d rpend=%b bvld=%b bp=%0d rdata_a=%016h rdata_b=%016h",
                     $time, uram_lat_cnt, uram_read_pending, uram_beat_valid,
                     beat_pair_cnt, gru_uram_rdata, gru_uram_rdata_b);
`endif
          // URAM latency countdown
          if (uram_read_pending && uram_lat_cnt != 4'd0)
            uram_lat_cnt <= uram_lat_cnt - 4'd1;

          // Latch both beats when countdown expires
          if (uram_read_pending && uram_lat_cnt == 4'd1) begin
            uram_beat_a_reg   <= gru_uram_rdata;
            uram_beat_b_reg   <= gru_uram_rdata_b;
            uram_beat_valid   <= 1'b1;
            uram_read_pending <= 1'b0;
`ifndef SYNTHESIS
            if (step_cnt == 2'd0 && mat_idx == 3'd0 && row_cnt < 10'd2)
              $display("[DBG_URAM] step=%0d mat=%0d row=%0d bp=%0d A=%016h B=%016h",
                       step_cnt, mat_idx, row_cnt, beat_pair_cnt, gru_uram_rdata, gru_uram_rdata_b);
`endif
          end

          // Process current beat-pair when latched
          if (uram_beat_valid) begin
            // Issue 32 parallel dequants (nibble assignments via combinational g_dq_in)
            for (int k = 0; k < N_PAR; k++) dq_valid_in[k] <= 1'b1;
`ifndef SYNTHESIS
            if (step_cnt == 2'd0 && mat_idx == 3'd0 && row_cnt < 10'd1)
              $display("[BEAT t=%0t] bp=%0d A=%016h B=%016h", $time, beat_pair_cnt, uram_beat_a_reg, uram_beat_b_reg);
`endif

            // b-operand address issued this cycle; par_b_pipe[k][0] loads next cycle
            // (scr_bp_addr_reg is updated in par_b_shift always_ff using beat_pair_cnt)

            uram_beat_valid  <= 1'b0;
            beat_pair_cnt    <= beat_pair_cnt + 4'd1;

            // Pre-fetch next beat-pair (if not last)
            if (beat_pair_cnt < 4'd15) begin
              gru_uram_en       <= 1'b1;
              gru_uram_en_b     <= 1'b1;
              uram_lat_cnt      <= URAM_LAT[3:0] + 4'd1; // +1 because gru_uram_en NBA fires same cycle: planning_top samples at T+1 not T
              uram_read_pending <= 1'b1;
            end

            // Last beat-pair done → drain
            if (beat_pair_cnt == 4'd15) begin
              drain_cnt <= 5'd0;
              state     <= S_MV_DRAIN;
            end
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // MV_DRAIN: Wait DRAIN_LAT=13 cycles for last FMA to propagate.
        // ──────────────────────────────────────────────────────────────────
        S_MV_DRAIN : begin
          drain_cnt <= drain_cnt + 5'd1;
          if (drain_cnt == 5'(DRAIN_LAT - 1)) begin
            state <= S_ADDER_TREE;
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // S_ADDER_TREE: 1-cycle behavioral reduction of 32 par_fmac_acc → acc_row.
        // ──────────────────────────────────────────────────────────────────
        S_ADDER_TREE : begin
          // [Fix Q] Cho AT_LAT chu ky cho duong ong cay cong day du truoc khi chot.
          if (at_cnt == AT_LAT[4:0]) begin
            acc_row  <= acc_tree;
            post_cnt <= 5'd0;
            at_cnt   <= 5'd0;
            state    <= S_MV_POST;
          end else begin
            at_cnt   <= at_cnt + 5'd1;
          end
`ifndef SYNTHESIS
          if (step_cnt == 2'd0 && row_cnt < 10'd64)
            $display("[DBG_ACC] step=0 mat=%0d row=%0d acc_tree=%08h(%f) scale=%08h",
                     mat_idx, row_cnt, acc_tree,
                     $bitstoshortreal(acc_tree), row_scale_reg);
`endif
        end

        // ──────────────────────────────────────────────────────────────────
        // MV_POST: Matrix-specific post-row operations.
        //
        //  mat=0 (W_iz): store acc (W_iz·x partial) to scratch[SCR_Z+row]
        //  mat=1 (W_hz): read scratch[SCR_Z+row] (partial), add acc + partial + bias
        //                → feed sigmoid_z → write z_t to scratch[SCR_Z+row]
        //  mat=2 (W_ir): store acc (W_ir·x partial) to scratch[SCR_R+row]
        //  mat=3 (W_hr): read scratch[SCR_R+row] (partial), add + bias
        //                → feed sigmoid_r → write r_t to scratch[SCR_R+row]
        //  mat=4 (W_in): add acc + bias_n_ih → write n_ih to scratch[SCR_N_IH+row]
        //  mat=5 (W_hn): add acc + bias_n_hh → write n_hh to scratch[SCR_N_HH+row]
        //                → 1-cy TDP RAW wait → read n_hh, n_ih, r_t, h_prev
        //                → n_t = tanh(n_ih + r_t⊙n_hh)
        //                → h_t = (1-z_t)⊙n_t + z_t⊙h_prev
        //                → write h_t to scratch[SCR_H+row]
        //
        //  post_cnt sequences the multi-cycle post-row steps.
        //  The FP unit pipelines (FP_LAT=3) and LUT pipelines (SIG_LAT/TANH_LAT=3)
        //  are used inline here; each step waits for the appropriate latency.
        // ──────────────────────────────────────────────────────────────────
        S_MV_POST : begin
          post_cnt <= post_cnt + 5'd1;

          case (mat_idx)

            // ── mat=0 (W_iz): write partial W_iz·x to scr[SCR_Z+row] ──
            3'd0 : begin
              if (post_cnt == 5'd0) begin
                // [Fix AA] ghi qua cong hop nhat (mat=0 post=0)
                // [fix15] Pre-fetch scale for next row (LUTRAM 1-cycle latency)
                if (row_cnt == 10'd511) begin
                  gru_scale_sel  <= 3'd1;
                  gru_scale_addr <= 9'd0;
                end else begin
                  gru_scale_sel  <= 3'd0;
                  gru_scale_addr <= row_cnt[8:0] + 9'd1;
                end
              end
              if (post_cnt == 5'd1) begin
                // Advance row or matrix
                if (row_cnt == 10'd511) begin
                  row_cnt <= 10'd0;
                  mat_idx <= 3'd1;
                  gru_scale_sel    <= 3'd1;
                  gru_scale_addr   <= 9'd0;
                  gru_uram_en      <= 1'b1;
                  gru_uram_en_b    <= 1'b1;
                  uram_read_pending<= 1'b1;
                  uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                  state            <= S_MV_SETUP;
                end else begin
                  row_cnt <= row_cnt + 10'd1;
                  gru_scale_sel    <= 3'd0;
                  gru_scale_addr   <= row_cnt[8:0] + 9'd1;
                  gru_uram_en      <= 1'b1;
                  gru_uram_en_b    <= 1'b1;
                  uram_read_pending<= 1'b1;
                  uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                  state            <= S_MV_SETUP;
                end
              end
            end

            // ── mat=1 (W_hz): partial=scratch[SCR_Z+r], combine → sigmoid → z_t ──
            // post_cnt:
            //   0: read scratch[SCR_Z+row] and bias[BIAS_BZ+row]
            //   1: data arrives (BRAM_LAT=1); latch scratch_rd_r and bias_rd_r
            //   2: start fp_add: partial_r + acc_row → raw_gate_sum (3 cy latency)
            //      also start bias add chain
            //   3,4,5: wait FP_LAT=3
            //   5: fp_add_out = partial + acc; start another add with bias: need 2 adds
            //      simplification: compute (partial_r + acc_row) then (+bias) = 6 cy total
            //      Use add_a/add_b for partial+acc, then feed result + bias
            //   Actually schedule: cy0=read, cy1=latch, cy2=issue add(partial,acc),
            //   cy5=add done, cy5 issue add(result,bias), cy8=bias_add done → sigmoid
            //   cy11=sigmoid done → write z_t
            //   Total post_cnt: 0..12 = 13 cycles per row
            3'd1 : begin
              case (post_cnt)
                5'd0: begin
                  // Issue scr read for SCR_Z+row (partial W_iz·x) and bias read
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= 7'd16 + {3'b0, row_cnt[9:5]};
                  gru_bias_addr <= (BIAS_BZ[10:0] + {1'b0, row_cnt});
                end
                5'd1: begin
                  // scr_rdata = partial (scratch_rd_r wire); latch bias
                  bias_rd_r <= gru_bias_rdata;
                end
                5'd2: begin
                  // Start add: partial + acc_row (W_iz·x + W_hz·h)
                  fp_add_a <= scratch_rd_r;   // wire alias for scr_rdata
                  fp_add_b <= acc_row;
                end
                // FIX NBA timing: fp_add inputs set at cy2 via NBA → output valid at cy6 (not cy5)
                5'd6: begin
                  fp_add_a <= fp_add_out;
                  // gru_bias_addr set at cy0, BRAM latency=2cy → rdata valid from cy2 onward
                  fp_add_b <= gru_bias_rdata;
                end
                // FIX: second fp_add inputs set at cy6 → output valid at cy10 (not cy8)
                5'd10: begin
                  sig_z_in  <= fp_add_out;
                  sig_z_vin <= 1'b1;
`ifndef SYNTHESIS
                  if (step_cnt == 2'd0 && row_cnt < 10'd64)
                    $display("[DBG_ZG] step=0 row=%0d sig_z_in=%08h(%f) scratch_partial=%08h bias_rdata=%08h acc=%08h",
                             row_cnt, fp_add_out, $bitstoshortreal(fp_add_out),
                             scr_dbg(int'(row_cnt[4:0]), int'(7'd16+{3'b0,row_cnt[9:5]})),
                             gru_bias_rdata, acc_row);
`endif
                end
                // FIX: sig_z_vin set at cy10 NBA → sigmoid starts cy11 → output valid at cy18
                // (was cy17 when SIG_LAT=6; SIG_LAT is now 7, see timing-fix comment above)
                6'd18: begin
                  // [Fix AA] ghi qua cong hop nhat (mat=1 post=18)
                  // [fix15] Pre-fetch scale for next row
                  if (row_cnt == 10'd511) begin
                    gru_scale_sel  <= 3'd2;
                    gru_scale_addr <= 9'd0;
                  end else begin
                    gru_scale_sel  <= 3'd1;
                    gru_scale_addr <= row_cnt[8:0] + 9'd1;
                  end
`ifndef SYNTHESIS
                  if (step_cnt == 2'd0 && row_cnt < 10'd64)
                    $display("[DBG_ZT] step=0 row=%0d z_t=%08h(%f)",
                             row_cnt, sig_z_out, $bitstoshortreal(sig_z_out));
`endif
                end
                6'd19: begin
                  if (row_cnt == 10'd511) begin
                    row_cnt <= 10'd0;
                    mat_idx <= 3'd2;
                    gru_scale_sel    <= 3'd2;
                    gru_scale_addr   <= 9'd0;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end else begin
                    row_cnt <= row_cnt + 10'd1;
                    gru_scale_sel    <= 3'd1;
                    gru_scale_addr   <= row_cnt[8:0] + 9'd1;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end
                end
                default: ;
              endcase
            end

            // ── mat=2 (W_ir): write partial W_ir·x to scr[SCR_R+row] ──
            3'd2 : begin
              if (post_cnt == 5'd0) begin
                // [Fix AA] ghi qua cong hop nhat (mat=2 post=0)
                // [fix15] Pre-fetch scale for next row
                if (row_cnt == 10'd511) begin
                  gru_scale_sel  <= 3'd3;
                  gru_scale_addr <= 9'd0;
                end else begin
                  gru_scale_sel  <= 3'd2;
                  gru_scale_addr <= row_cnt[8:0] + 9'd1;
                end
              end
              if (post_cnt == 5'd1) begin
                if (row_cnt == 10'd511) begin
                  row_cnt <= 10'd0;
                  mat_idx <= 3'd3;
                  gru_scale_sel    <= 3'd3;
                  gru_scale_addr   <= 9'd0;
                  gru_uram_en      <= 1'b1;
                  gru_uram_en_b    <= 1'b1;
                  uram_read_pending<= 1'b1;
                  uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                  state            <= S_MV_SETUP;
                end else begin
                  row_cnt <= row_cnt + 10'd1;
                  gru_scale_sel    <= 3'd2;
                  gru_scale_addr   <= row_cnt[8:0] + 9'd1;
                  gru_uram_en      <= 1'b1;
                  gru_uram_en_b    <= 1'b1;
                  uram_read_pending<= 1'b1;
                  uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                  state            <= S_MV_SETUP;
                end
              end
            end

            // ── mat=3 (W_hr): partial=scr[SCR_R+r], combine → sigmoid → r_t ──
            3'd3 : begin
              case (post_cnt)
                5'd0: begin
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= 7'd32 + {3'b0, row_cnt[9:5]};
                  gru_bias_addr <= (BIAS_BR[10:0] + {1'b0, row_cnt});
                end
                5'd1: begin
                  bias_rd_r <= gru_bias_rdata;
                end
                5'd2: begin
                  fp_add_a <= scratch_rd_r;
                  fp_add_b <= acc_row;
                end
                // FIX NBA timing: same as mat=1 (cy2→cy6, cy6→cy10, cy10→cy17)
                5'd6: begin
                  fp_add_a <= fp_add_out;
                  fp_add_b <= gru_bias_rdata;  // addr set cy0, valid from cy2+
                end
                5'd10: begin
                  sig_r_in  <= fp_add_out;
                  sig_r_vin <= 1'b1;
                end
                // Was cy17 when SIG_LAT=6; SIG_LAT is now 7 (timing fix, see header).
                6'd18: begin
                  // [Fix AA] ghi qua cong hop nhat (mat=3 post=18)
                  // [fix15] Pre-fetch scale for next row
                  if (row_cnt == 10'd511) begin
                    gru_scale_sel  <= 3'd4;
                    gru_scale_addr <= 9'd0;
                  end else begin
                    gru_scale_sel  <= 3'd3;
                    gru_scale_addr <= row_cnt[8:0] + 9'd1;
                  end
                end
                6'd19: begin
                  if (row_cnt == 10'd511) begin
                    row_cnt <= 10'd0;
                    mat_idx <= 3'd4;
                    gru_scale_sel    <= 3'd4;
                    gru_scale_addr   <= 9'd0;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end else begin
                    row_cnt <= row_cnt + 10'd1;
                    gru_scale_sel    <= 3'd3;
                    gru_scale_addr   <= row_cnt[8:0] + 9'd1;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end
                end
                default: ;
              endcase
            end

            // ── mat=4 (W_in): n_ih = acc + bias_n_ih → scr[SCR_N_IH+row] ──
            3'd4 : begin
              case (post_cnt)
                5'd0: begin
                  gru_bias_addr <= (BIAS_N_IH[10:0] + {1'b0, row_cnt});
                end
                5'd2: begin
                  // gru_bias_addr set at cy0, BRAM 2cy latency → gru_bias_rdata valid here
                  fp_add_a <= acc_row;
                  fp_add_b <= gru_bias_rdata;
                end
                // fp_add inputs at cy2 NBA → output valid at cy6
                5'd6: begin
                  // [Fix AA] ghi qua cong hop nhat (mat=4 post=6)
                  // [fix15] Pre-fetch scale for next row
                  if (row_cnt == 10'd511) begin
                    gru_scale_sel  <= 3'd5;
                    gru_scale_addr <= 9'd0;
                  end else begin
                    gru_scale_sel  <= 3'd4;
                    gru_scale_addr <= row_cnt[8:0] + 9'd1;
                  end
`ifndef SYNTHESIS
                  if (step_cnt == 2'd0 && row_cnt < 10'd64)
                    $display("[DBG_NIH] step=0 row=%0d n_ih=%08h(%f) acc=%08h bias_rdata=%08h",
                             row_cnt, fp_add_out, $bitstoshortreal(fp_add_out),
                             acc_row, gru_bias_rdata);
`endif
                end
                5'd7: begin
                  if (row_cnt == 10'd511) begin
                    row_cnt <= 10'd0;
                    mat_idx <= 3'd5;
                    gru_scale_sel    <= 3'd5;
                    gru_scale_addr   <= 9'd0;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end else begin
                    row_cnt <= row_cnt + 10'd1;
                    gru_scale_sel    <= 3'd4;
                    gru_scale_addr   <= row_cnt[8:0] + 9'd1;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end
                end
                default: ;
              endcase
            end

            // ── mat=5 (W_hn): Full n_t and h_t computation per row ──────────
            // n_hh = W_hn·h + b_n_hh → scratch[SCR_N_HH+row]
            // TDP RAW ≥1 cy (§15.12)
            // n_t  = tanh(n_ih + r_t ⊙ n_hh)
            // h_t  = (1−z_t)⊙n_t + z_t⊙h_prev → scratch[SCR_H+row]
            //
            // post_cnt timeline:
            //   0: read bias[BIAS_N_HH+row]
            //   1: latch bias; start add acc+bias
            //   2: issue fp_add(acc_row, bias_rd_r)   [bias_rd_r latched at cy1]
            //   5: n_hh=fp_add_out ready; write scratch[SCR_N_HH+row]
            //   6: TDP RAW wait (≥1 cy) [§15.12]
            //   7: read scratch[SCR_N_HH+row] (n_hh); read scratch[SCR_R+row] (r_t)
            //   8: latch n_hh=scratch_rd_r; read scratch[SCR_N_IH+row] (n_ih)
            //      latch r_t_r from saved r_t (use bias_rd_r as temp)
            //   9: latch n_ih_r; read scratch[SCR_H+row] (h_prev)
            //       issue fp_mul(r_t_r, n_hh_r)  — r_t ⊙ n_hh
            //  10: latch h_prev_r; read scratch[SCR_Z+row] (z_t)
            //  11: latch z_t_r
            //  12: fp_mul done (r_t⊙n_hh); issue fp_add(n_ih_r, fp_mul_out)
            //  15: n_ih+r_t⊙n_hh ready; feed to tanh
            //  19: tanh_vin issued at cy18 NBA -> tanh sees valid_in at cy19
            //  23: tanh done (TANH_LAT=4, timing fix); n_t_r = tanh_out
            //      issue fp_sub(FP32_ONE, z_t_r)  → (1-z_t)
            //      issue fp_mul(z_t_r, h_prev_r)  → z_t⊙h_prev
            //  27: (1-z_t)⊙n_t ready; issue fp_add((1-z_t)⊙n_t, z_t⊙h_prev)
            //  31: h_t ready; write scratch[SCR_H+row]
            //  28: advance row / matrix
            3'd5 : begin
              case (post_cnt)
                5'd0: begin
                  gru_bias_addr <= (BIAS_N_HH[10:0] + {1'b0, row_cnt});
                end
                5'd2: begin
                  // gru_bias_addr set cy0, BRAM 2cy latency → gru_bias_rdata valid here
                  fp_add_a <= acc_row;
                  fp_add_b <= gru_bias_rdata;
                end
                5'd6: begin
                  // n_hh write (fp_add from cy2, out at cy6); also issue n_hh read same cycle
                  // (FF-array write NBA at cy6 → readable by scr_seq_read at cy7 active ✓)
                  // [Fix AA] ghi qua cong hop nhat (mat=5 post=6)
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= 7'd64 + {3'b0, row_cnt[9:5]};
                end
                5'd7: begin
                  // n_hh propagating; issue r_t read
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= 7'd32 + {3'b0, row_cnt[9:5]};
                end
                5'd8: begin
                  // Latch n_hh (2 cy from issue at cy6); issue n_ih read
                  n_hh_r       <= scr_rdata;
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= 7'd48 + {3'b0, row_cnt[9:5]};
                end
                5'd9: begin
                  // Latch r_t; issue h_prev read
                  r_t_r        <= scr_rdata;
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= {3'b0, row_cnt[9:5]};
                end
                5'd10: begin
                  // Latch n_ih; issue z_t read; start r_t ⊙ n_hh
                  n_ih_r       <= scr_rdata;
                  scr_rd_bank  <= row_cnt[4:0];
                  scr_rd_baddr <= 7'd16 + {3'b0, row_cnt[9:5]};
                  fp_mul_a     <= r_t_r;
                  fp_mul_b     <= n_hh_r;
                end
                5'd11: begin
                  // Latch h_prev
                  h_prev_r <= scr_rdata;
                end
                5'd12: begin
                  // Latch z_t
                  z_t_r <= scr_rdata;
                end
                // FIX NBA timing (all pipeline reads shifted +1 cycle):
                // fp_mul inputs at cy10 NBA → fp_mul_out valid at cy14 active (not cy13)
                5'd14: begin
                  fp_add_a <= n_ih_r;
                  fp_add_b <= fp_mul_out;
                end
                // fp_add inputs at cy14 NBA → fp_add_out valid at cy18 active (not cy16)
                5'd18: begin
                  tanh_in  <= fp_add_out;
                  tanh_vin <= 1'b1;
                  fp_mul_a <= z_t_r;
                  fp_mul_b <= h_prev_r;
                  fp_sub_a <= FP32_ONE;
                  fp_sub_b <= z_t_r;
`ifndef SYNTHESIS
                  if (step_cnt == 2'd0 && row_cnt < 10'd64)
                    $display("[DBG_NT] step=0 row=%0d n_ih=%08h(%f) n_hh=%08h(%f) r_t=%08h(%f) z_t=%08h(%f) n_gate_in=%08h(%f)",
                             row_cnt,
                             n_ih_r, $bitstoshortreal(n_ih_r),
                             n_hh_r, $bitstoshortreal(n_hh_r),
                             r_t_r,  $bitstoshortreal(r_t_r),
                             z_t_r,  $bitstoshortreal(z_t_r),
                             fp_add_out, $bitstoshortreal(fp_add_out));
`endif
                end
                // tanh/fp_mul/fp_sub inputs at cy18 NBA → outputs valid at cy24
                // (was cy23 when TANH_LAT=4; TANH_LAT is now 5, see timing-fix comment above)
                6'd24: begin
                  n_t_r    <= tanh_out;
                  fp_mul_a <= fp_sub_out;
                  fp_mul_b <= tanh_out;
                  h_prev_r <= fp_mul_out;   // z_t⊙h_prev storage
                end
                // fp_mul3 inputs at cy24 NBA → fp_mul3_out valid at cy28 (was cy27)
                6'd28: begin
                  fp_add_a <= fp_mul_out;
                  fp_add_b <= h_prev_r;   // z_t⊙h_prev stored here
                end
                // fp_add2 inputs at cy28 NBA → fp_add2_out valid at cy32 (was cy31)
                // [fix F8] h_t written to SCR_X_T (80..95) to avoid contaminating h_prev reads.
                // S_HT_COMMIT will copy to SCR_H (0..15) after all 512 rows finish.
                6'd32: begin
                  // [Fix AA] ghi qua cong hop nhat (mat=5 post=32)
                  // [fix15] Pre-fetch scale for next row (non-terminal rows only)
                  if (row_cnt != 10'd511) begin
                    gru_scale_sel  <= 3'd5;
                    gru_scale_addr <= row_cnt[8:0] + 9'd1;
                  end
`ifndef SYNTHESIS
                  if (step_cnt == 2'd0 && row_cnt < 10'd64)
                    $display("[DBG GRU] step=0 h_t[%0d]=%08h(%f)", row_cnt, fp_add_out, $bitstoshortreal(fp_add_out));
`endif
                end
                6'd33: begin
                  if (row_cnt == 10'd511) begin
                    // [fix F8] Commit h_t from SCR_X_T → SCR_H before wout/next step
                    row_cnt        <= 10'd0;
                    state          <= S_HT_COMMIT;
                  end else begin
                    row_cnt <= row_cnt + 10'd1;
                    gru_scale_sel    <= 3'd5;
                    gru_scale_addr   <= row_cnt[8:0] + 9'd1;
                    gru_uram_en      <= 1'b1;
                    gru_uram_en_b    <= 1'b1;
                    uram_read_pending<= 1'b1;
                    uram_lat_cnt     <= URAM_LAT[3:0] - 1;
                    state            <= S_MV_SETUP;
                  end
                end
                default: ;
              endcase
            end

            default: ;
          endcase
        end

        // ──────────────────────────────────────────────────────────────────
        // S_WOUT_SETUP: Prepare for FP32 W_out projection.
        //   acc_clear and FMAC_LAT-cycle wait before first FMA.
        //   Overlap with initial BRAM pre-reads.
        // ──────────────────────────────────────────────────────────────────
        S_WOUT_SETUP : begin
          setup_cnt <= setup_cnt + 3'd1;

          // Issue BRAM pre-reads on the first cycle so data is ready for col 0.
          // Also assert fmac_acc_clear_wout for exactly ONE cycle so clr_pipe[6]
          // fires at col_cnt=0 (6 cycles later), clearing before any FMA lands.
          // wout_scr_rd automatically reads scr[col_cnt[4:0]][{3'b0,col_cnt[9:5]}] each cycle.
          if (setup_cnt == 3'd0) begin
            col_cnt             <= 10'd0;
            wout_bram_addr      <= {wout_row, 9'd0};
            fmac_acc_clear_wout <= 1'b1;
          end

          // After FMAC_LAT cycles the accumulator is guaranteed clear.
          if (setup_cnt == 3'(FMAC_LAT - 1)) begin
            setup_cnt <= 3'd0;
            state     <= S_WOUT_COL;
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // S_WOUT_COL: 512-cycle FP32 dot product.
        //   Each cycle: issue reads for next col, fma_en on current data.
        //   Addresses staggered by BRAM_LAT=1 cy.
        //   First FMAC fires at col=1 (using col=0 BRAM data);
        //   acc_clear was asserted at WOUT_SETUP, giving ≥6 cy before fma_en.
        // ──────────────────────────────────────────────────────────────────
        S_WOUT_COL : begin
          // [TIMING 150 MHz, 03/10] Moi cot giu 4 chu ky (dia chi BRAM/scratch khong doi trong
          // luc giu -> du lieu van can dung); fma_en chi o chu ky thu 4 -> cach >= 4 (xem FMAC).
          wout_sub       <= wout_sub + 2'd1;
          wout_fmac_en_q <= 1'b0;
          if (wout_sub == 2'd3) begin
          col_cnt <= col_cnt + 10'd1;

          // Issue BRAM read for next column (wout_scr_rd auto-reads scr[col_cnt])
          if (col_cnt < 10'd511) begin
            wout_bram_addr <= ({wout_row, 9'b0} + {1'b0, col_cnt[8:0] + 9'd1});
          end

          wout_fmac_en_q <= 1'b1;

`ifndef SYNTHESIS
          // Print partial wout accumulation: wout_fmac_acc lags by FMAC_LAT=6 cycles.
          // At col_cnt=k, the FMA for col=k-1 fires. So wout_fmac_acc at col_cnt=k
          // reflects Σ col=0..k-7 (col_cnt-7 columns accumulated so far).
          // Print at col_cnt=FMAC_LAT+1=7 (h[0] just landed), every 32 thereafter, and col=511.
          if (step_cnt == 2'd0 && wout_row == 1'b0) begin
            if (col_cnt == 10'd7 || (col_cnt[4:0] == 5'd7 && col_cnt >= 10'd7))
              $display("[DBG_WOUT_COL] step=0 col_cnt=%0d wout_fmac_acc=%08h(%f) bram=%08h scr=%08h",
                       col_cnt, wout_fmac_acc, $bitstoshortreal(wout_fmac_acc),
                       wout_bram_rdata, wout_scr_data);
          end
`endif

          if (col_cnt == 10'd511) begin
            drain_cnt <= 3'd0;
            state     <= S_WOUT_DRAIN;
          end
          end   // wout_sub == 3
        end

        // ──────────────────────────────────────────────────────────────────
        // S_WOUT_DRAIN: FMAC_LAT cycles to flush final FMA.
        // ──────────────────────────────────────────────────────────────────
        S_WOUT_DRAIN : begin
          drain_cnt <= drain_cnt + 5'd1;
          // Last FMA (col=511) fires at drain_cnt=0; result lands at drain_cnt=7.
          // Col=510 fires at col_cnt=511 (1 cy before DRAIN); result at drain_cnt=6.
          // Need drain_cnt == FMAC_LAT+1 = 7 to capture all 512 columns.
          if (drain_cnt == 5'(FMAC_LAT + 1)) begin
            wp_acc <= wout_fmac_acc;
            state  <= S_WOUT_BIAS;
`ifndef SYNTHESIS
            $display("[DBG GRU] step=%0d row=%0d wout_fmac_acc=%08h",
                     step_cnt, wout_row, wout_fmac_acc);
`endif
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // S_WOUT_BIAS: Read b_out, add to wp_acc, latch waypoint.
        //   b_out[0] at addr 1024, b_out[1] at addr 1025.
        //   FP_LAT=3 cycles for the addition.
        // ──────────────────────────────────────────────────────────────────
        S_WOUT_BIAS : begin
          post_cnt <= post_cnt + 5'd1;
          case (post_cnt)
            5'd0: begin
              wout_bram_addr <= wout_row ? 11'd1025 : 11'd1024;
            end
            5'd1: begin
              // BRAM addr set at case 0 via NBA; doutb_int updates at *this* posedge
              // → wout_bram_rdata still has old data here; wait one more cycle
`ifndef SYNTHESIS
              $display("[DBG BIAS1_STALE] step=%0d wout_row=%0d bram_rdata_stale=%08h",
                       step_cnt, wout_row, wout_bram_rdata);
`endif
            end
            5'd2: begin
              // b_out now valid: bram NBA from case 0 committed, posedge 1 fired mem[1024/5]
              fp_add_a <= wp_acc;
              fp_add_b <= wout_bram_rdata;
`ifndef SYNTHESIS
              $display("[DBG BIAS2] step=%0d wout_row=%0d wp_acc=%08h bram_rdata=%08h",
                       step_cnt, wout_row, wp_acc, wout_bram_rdata);
`endif
            end
            // 5'd3, 5'd4, 5'd5: fp_add pipeline (FP_LAT=3 after inputs set at case 2)
            5'd6: begin
              // fp_add_out valid: inputs committed at end of posedge 2, pipe[1] correct at
              // posedge 3, pipe[2] at posedge 4, pipe[3]=fp_add_out readable at posedge 6
`ifndef SYNTHESIS
              $display("[DBG BIAS6] step=%0d wout_row=%0d fp_add_out=%08h",
                       step_cnt, wout_row, fp_add_out);
`endif
              if (!wout_row) begin
                waypoint_x[step_cnt] <= fp_add_out;
                wout_row    <= 1'b1;
                col_cnt     <= 10'd0;
                post_cnt    <= 5'd0;
                wout_bram_addr <= 11'd512;
                state          <= S_WOUT_SETUP;
              end else begin
                waypoint_y[step_cnt] <= fp_add_out;
                state <= S_STEP_DONE;
              end
            end
            default: ;
          endcase
        end

        // ──────────────────────────────────────────────────────────────────
        // S_HT_COMMIT: Copy h_t from SCR_X_T (80..95) → SCR_H (0..15).
        // [fix F8] mat=5 wrote h_t to SCR_X_T to avoid polluting h_prev reads.
        // 512 cycles: row_cnt iterates 0..511.
        // ──────────────────────────────────────────────────────────────────
        S_HT_COMMIT : begin
          // [Fix AA] ghi qua cong hop nhat (S_HT_COMMIT), nguon = scr_rd_d
          // (cong doc D, BAT DONG BO nen doc-ghi cung chu ky van dung nhu cu).
          row_cnt <= row_cnt + 10'd1;
          if (row_cnt == 10'd511) begin
            row_cnt        <= 10'd0;
            wout_row       <= 1'b0;
            fmac_wout_mode <= 1'b1;
            state          <= S_WOUT_SETUP;
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // S_STEP_DONE: Increment step counter.
        //   If step_cnt < 3: run next step (h_t already in scratch).
        //   If step_cnt == 3: assert outputs and finish.
        // ──────────────────────────────────────────────────────────────────
        S_STEP_DONE : begin
          if (step_cnt == 2'd3) begin
            waypoints_valid <= 1'b1;
            gru_done        <= 1'b1;
            state           <= S_DONE;
`ifndef SYNTHESIS
            $display("[DBG DONE] wp_x=[%08h %08h %08h %08h] wp_y=[%08h %08h %08h %08h]",
                     waypoint_x[0], waypoint_x[1], waypoint_x[2], waypoint_x[3],
                     waypoint_y[0], waypoint_y[1], waypoint_y[2], waypoint_y[3]);
`endif
          end else begin
            // Latch current waypoint as prev_wp for S_WP_APPLY autoregressive injection
            wp_x_prev <= waypoint_x[step_cnt];
            wp_y_prev <= waypoint_y[step_cnt];
            step_cnt <= step_cnt + 2'd1;
            mat_idx  <= 3'd0;
            row_cnt  <= 10'd0;
            col_cnt  <= 10'd0;
            fmac_wout_mode <= 1'b0;
            wp_cnt   <= 10'd0;
            wp_ph    <= 5'd0;
            state    <= S_WP_APPLY;
          end
        end

        // ──────────────────────────────────────────────────────────────────
        // S_WP_APPLY: Compute x_t_eff[j] = cls[j] + W_wp[j,0]*wp_x_prev
        //             + W_wp[j,1]*wp_y_prev + b_wp[j] and store to
        //             scratch[SCR_X_T+j] for j=0..511.
        //
        // 18-cycle pipeline per row (wp_ph 0..17), then wp_cnt increments:
        //   ph 0 : issue wp_proj_bram read for W[:,0] at addr j
        //   ph 1 : W[j,0] ready; drive fp_mul_a=W[j,0], fp_mul_b=wp_x_prev
        //          issue wp_proj_bram read for W[:,1] at addr 512+j
        //   ph 2 : W[j,1] ready; latch wp_w1_latch
        //          issue wp_proj_bram read for b at addr 1024+j
        //          issue cls_buf read at addr j
        //   ph 3 : b[j] ready; latch wp_b_latch; cls[j] ready; latch wp_cls_latch
        //   ph 4 : fp_mul_out = W[j,0]*wp_x_prev; latch wp_m0
        //          drive fp_mul_a=wp_w1_latch, fp_mul_b=wp_y_prev
        //   ph 7 : fp_mul_out = W[j,1]*wp_y_prev
        //          drive fp_add_a=wp_m0, fp_add_b=fp_mul_out
        //   ph10 : fp_add_out = m0+m1; drive fp_add_a=fp_add_out, fp_add_b=wp_b_latch
        //   ph13 : fp_add_out = m0+m1+b; drive fp_add_a=fp_add_out, fp_add_b=wp_cls_latch
        //   ph17 : fp_add_out = final; write scratch[SCR_X_T+j]
        //   ph18 : done/next row
        // BRAM 2-cycle latency fix: all BRAM read points shifted +1 vs original comments.
        // ──────────────────────────────────────────────────────────────────
        S_WP_APPLY : begin
          if (wp_ph == 5'd23) begin
            if (wp_cnt == 10'd511) begin
              // All 512 outputs computed → start GRU matrices
              gru_scale_sel    <= 3'd0;
              gru_scale_addr   <= 9'd0;
              gru_uram_en      <= 1'b1;
              gru_uram_en_b    <= 1'b1;
              uram_read_pending<= 1'b1;
              uram_lat_cnt     <= URAM_LAT[3:0] - 1;
              state            <= S_MV_SETUP;
            end else begin
              wp_cnt <= wp_cnt + 10'd1;
              wp_ph  <= 5'd0;
            end
          end else begin
            wp_ph <= wp_ph + 5'd1;
            case (wp_ph)
              5'd0: begin
                wp_proj_bram_addr <= {2'b00, wp_cnt[8:0]};   // W[j,0] at addr j
                wp_proj_bram_en   <= 1'b1;
              end
              5'd1: begin
                // Issue W[j,1] address; BRAM latency=2cy so W[j,0] not yet ready
                wp_proj_bram_addr <= {2'b01, wp_cnt[8:0]};   // W[j,1] at 512+j
                wp_proj_bram_en   <= 1'b1;
              end
              5'd2: begin
                // W[j,0] now valid (addr set cy0, BRAM 2cy latency); start first multiply
                fp_mul_a <= wp_proj_bram_rdata;
                fp_mul_b <= wp_x_prev;
                wp_proj_bram_addr <= {2'b10, wp_cnt[8:0]};   // b[j] at 1024+j
                wp_proj_bram_en   <= 1'b1;
                cls_buf_rd_addr   <= wp_cnt[8:0];
                cls_buf_rd_en     <= 1'b1;
              end
              5'd3: begin
                // W[j,1] now valid (addr set cy1); latch for later
                wp_w1_latch <= wp_proj_bram_rdata;
              end
              5'd4: begin
                // b[j] and cls[j] valid (addrs set cy2, 2cy latency)
                wp_b_latch   <= wp_proj_bram_rdata;
                wp_cls_latch <= cls_buf_rd_data;
                wp_proj_bram_en <= 1'b0;
                cls_buf_rd_en   <= 1'b0;
              end
              5'd6: begin
                // fp_mul_out = W[j,0]*wp_x_prev (NBA at cy2, +4 NBA-delay = cy6)
                wp_m0    <= fp_mul_out;
                fp_mul_a <= wp_w1_latch;
                fp_mul_b <= wp_y_prev;
              end
              5'd10: begin
                // fp_mul_out = W[j,1]*wp_y_prev (NBA at cy6, ready cy10)
                fp_add_a <= wp_m0;
                fp_add_b <= fp_mul_out;
              end
              5'd14: begin
                // fp_add_out = m0+m1 (NBA at cy10, ready cy14)
                fp_add_a <= fp_add_out;
                fp_add_b <= wp_b_latch;
              end
              5'd18: begin
                // fp_add_out = m0+m1+b (NBA at cy14, ready cy18)
                fp_add_a <= fp_add_out;
                fp_add_b <= wp_cls_latch;
              end
              5'd22: begin
                // fp_add_out = x_t_eff[j] = cls+b+m0+m1 (NBA at cy18, ready cy22)
                // [Fix AA] ghi qua cong hop nhat (S_WP_APPLY wp_ph=22)
                // [fix15] When this is the last WP element, pre-fetch scale for
                // mat=0 row=0 so it arrives 1 cycle later at S_MV_SETUP entry.
                if (wp_cnt == 10'd511) begin
                  gru_scale_sel  <= 3'd0;
                  gru_scale_addr <= 9'd0;
                end
`ifndef SYNTHESIS
                if (wp_cnt < 10'd4)
                  $display("[DBG_WPA22] step=%0d j=%0d fp_add=%08h(%f) b=%08h(%f) cls=%08h(%f)",
                           step_cnt, wp_cnt, fp_add_out, $bitstoshortreal(fp_add_out),
                           wp_b_latch, $bitstoshortreal(wp_b_latch),
                           wp_cls_latch, $bitstoshortreal(wp_cls_latch));
`endif
              end
              default: ;
            endcase
          end
        end

        // ──────────────────────────────────────────────────────────────────
        S_DONE : begin
          // Outputs latched; remain in DONE until next gru_start
          if (gru_start) begin
            step_cnt  <= 2'd0;
            mat_idx   <= 3'd0;
            row_cnt   <= 10'd0;
            init_cnt  <= 10'd0;
            fmac_wout_mode <= 1'b0;
            // [E2E 03/10] Khung thu 2 tro di vao S_INIT TU S_DONE (khong qua S_IDLE) -> phai xoa
            // waypoint truoc o day nua. tb GRU2 (2 lan cung CLS): x_t khac 512/512, cls/thang/W giong.
            wp_x_prev <= FP32_ZERO;
            wp_y_prev <= FP32_ZERO;
            state     <= S_INIT;
          end
        end

        default: state <= S_IDLE;

      endcase
    end
  end

// ============================================================================
// SCALE LUTRAM DRIVE — combinational select based on mat_idx
// ============================================================================
  // gru_scale_sel and gru_scale_addr are driven by FSM at row-start transitions.
  // For S_MV_SETUP the sel/addr have already been set by the previous state.

endmodule : gru_waypoint_decoder

// ============================================================================
// SUB-MODULE STUB DECLARATIONS
// (Replace with actual Xilinx IP or behavioural implementations in project)
// ============================================================================

// ── gru_int4_dequant ─────────────────────────────────────────────────────────
// w_fp32 = (sign_extend(w_int4,4) - w_zp) × (w_scale_q8 / 256.0)
// Latency: 8 cy.  DSP: ~3.
module gru_int4_dequant
  import planning_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,        // [Fix G] them reset de chan X lan vao scratch
  input  logic  [3:0]  w_int4,
  input  logic  [7:0]  w_scale_q8,
  input  logic  [7:0]  w_zp,
  input  logic         valid_in,
  output fp32_t        w_fp32,
  output logic         valid_out
);
  localparam int LAT = 8;
  fp32_t pipe [LAT:1];
  logic  vpipe [LAT:1];
  logic [3:0] in_w; logic [7:0] in_zp, in_sc;

`ifdef SYNTHESIS
  // [Fix G] (int4 - zp) * scale_q8 * 2^-8 -> FP32 chinh xac tuyet doi.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int s = 1; s <= LAT; s++) begin
        pipe[s]  <= 32'd0;
        vpipe[s] <= 1'b0;
      end
    end else begin
      // [IMPL 150 MHz, 04/10] tang 1 chi chot dau vao; tang 2 tinh fp32_from_dequant
      // (truoc day to hop ngay tang 1 tu tin hieu o xa: -0,661 ns sau route). Do tre van = LAT.
      in_w <= w_int4; in_zp <= w_zp; in_sc <= w_scale_q8;
      pipe[2]  <= fp32_from_dequant(in_w, in_zp, in_sc);
      vpipe[1] <= valid_in;
      for (int s = 3; s <= LAT; s++) pipe[s] <= pipe[s-1];
      for (int s = 2; s <= LAT; s++) vpipe[s] <= vpipe[s-1];
    end
  end
`else
  always_ff @(posedge clk) begin
    shortreal sv;
    logic signed [4:0] se;
    se = {w_int4[3], w_int4};            // sign-extend 4→5 bit
    sv = shortreal'(signed'(se) - signed'({1'b0, w_zp})) *
         ($bitstoshortreal(32'h3B800000) * shortreal'(w_scale_q8));
         // 2^-8 = 0x3B800000; scale/256 = scale * 2^-8
    pipe[1]  <= $shortrealtobits(sv);
    vpipe[1] <= valid_in;
    for (int s = 2; s <= LAT; s++) begin
      pipe[s]  <= pipe[s-1];
      vpipe[s] <= vpipe[s-1];
    end
  end
`endif
  assign w_fp32    = pipe[LAT];
  assign valid_out = vpipe[LAT];
endmodule

// ── gru_fp32_fmac ─────────────────────────────────────────────────────────────
// Pipelined FP32 FMA accumulator.  Latency ~6 cy.  DSP: ~5.
// acc_clear: synchronous; effect visible after FULL PIPELINE FLUSH (6 cy).
module gru_fp32_fmac
  import planning_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,
  input  fp32_t  a,
  input  fp32_t  b,
  input  logic   acc_clear,
  input  logic   fma_en,
  output fp32_t  acc,
  output logic   result_valid
);
  localparam int LAT = 6;
  fp32_t prod_pipe [LAT:1];
  logic  en_pipe   [LAT:1];
  logic  clr_pipe  [LAT:1];
  fp32_t accumulator = '0;

`ifdef SYNTHESIS
  // [TIMING 150 MHz, 03/10] Tich luy FP32 bang fp32_add_p #(LEGACY_ZERO=1) 3 tang (trung tung
  // bit voi fp32_add_f: tb/unit/tb_fp32_add_legacy). Tich di qua 3 tang (thay vi 6) roi vao bo
  // cong 3 tang -> accumulator duoc GHI DUNG canh cu (en o tang LAT=6), khong doi bo dem drain.
  // DIEU KIEN: hai lan fma_en cua cung FMAC cach nhau >= 4 chu ky (bo cong doc accumulator o
  // tang 3, ket qua lan truoc ghi o cuoi tang 6). MV: 4 chu ky/beat; WOUT: giu cot 4 chu ky.
  fp32_t add_r, mul_r;
  // Nhan: fp32_mul_p (== fp32_mul_f tung bit) 3 tang -> mul_r hop le dung luc prod_pipe[3] cu.
  fp32_mul_p                       u_acc_mul (.clk, .a(a), .b(b), .r(mul_r));
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_acc_add (.clk, .a(accumulator), .b(mul_r), .r(add_r));
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accumulator <= 32'h0;
      for (int s = 1; s <= LAT; s++) begin
        prod_pipe[s] <= 32'h0;
        en_pipe[s]   <= 1'b0;
        clr_pipe[s]  <= 1'b0;
      end
    end else begin
      en_pipe[1]   <= fma_en;
      clr_pipe[1]  <= acc_clear;
      for (int s = 2; s <= LAT; s++) begin
        en_pipe[s]   <= en_pipe[s-1];
        clr_pipe[s]  <= clr_pipe[s-1];
      end
      if (clr_pipe[LAT])
        accumulator <= 32'h0;
      else if (en_pipe[LAT])
        accumulator <= add_r;               // = fp32_add_f(accumulator@tang3, prod@tang3)
    end
  end
`ifdef ASSERT_ON
  always @(posedge clk) if (rst_n && en_pipe[3] && (en_pipe[4] || en_pipe[5] || en_pipe[6]))
    $error("[gru_fp32_fmac] fma_en cach nhau < 4 chu ky (%m)");
  always @(posedge clk) if (rst_n && clr_pipe[3] && (en_pipe[4] || en_pipe[5] || en_pipe[6]))
    $error("[gru_fp32_fmac] acc_clear trong khi phep cong dang chay (%m)");
`endif
`else
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accumulator <= 32'h0;
      for (int s = 1; s <= LAT; s++) begin
        prod_pipe[s] <= 32'h0;
        en_pipe[s]   <= 1'b0;
        clr_pipe[s]  <= 1'b0;
      end
    end else begin
      shortreal ra, rb;
      ra = $bitstoshortreal(a);
      rb = $bitstoshortreal(b);
      prod_pipe[1] <= $shortrealtobits(ra * rb);
      en_pipe[1]   <= fma_en;
      clr_pipe[1]  <= acc_clear;
      for (int s = 2; s <= LAT; s++) begin
        prod_pipe[s] <= prod_pipe[s-1];
        en_pipe[s]   <= en_pipe[s-1];
        clr_pipe[s]  <= clr_pipe[s-1];
      end
      if (clr_pipe[LAT])
        accumulator <= 32'h0;
      else if (en_pipe[LAT]) begin
        shortreal cur, prd;
        cur = $bitstoshortreal(accumulator);
        prd = $bitstoshortreal(prod_pipe[LAT]);
        accumulator <= $shortrealtobits(cur + prd);
      end
    end
  end
`endif
  assign acc          = accumulator;
  assign result_valid = en_pipe[LAT];
endmodule