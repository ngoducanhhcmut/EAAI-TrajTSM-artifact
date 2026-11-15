// =============================================================================
// FILE        : riscv_dcls_wrapper.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 2.2 (ASIL-D SLR1)
// SAFETY      : ASIL-D (ISO 26262) - Dual-Core Lockstep
// DESCRIPTION : Wraps TWO instances of the RV32IM processor (top_dcls.v)
//               in Dual-Core Lockstep (DCLS) configuration.
//
//               DCLS Architecture (Spec Ref: Section 2.2):
//               ┌──────────────────────────────────────────────────────┐
//               │  Core A (PRIMARY)           Core B (SHADOW)          │
//               │  ┌──────────────┐           ┌──────────────┐         │
//               │  │  top_dcls    │           │  top_dcls    │         │
//               │  │  riscv_start │← same ───→│  riscv_start │         │
//               │  │  MMIO reads  │← same ───→│  MMIO reads  │         │
//               │  └──────┬───────┘           └──────┬───────┘         │
//               │         │ mmio_start                │ mmio_start     │
//               │         │ mmio_irq_clear            │ mmio_irq_clear │
//               │         ▼                           ▼ (delayed by   │
//               │  ┌──────────────────────────────────N cycles)        │
//               │  │        DCLS VOTER (comparator)                    │
//               │  │  Compare A (delayed N) vs B outputs               │
//               │  │  Mismatch → dcls_error (sticky until reset)       │
//               │  └──────────────────────────────────────────────────┘│
//               │         │ Core A drives live HMAO control            │
//               └─────────┼────────────────────────────────────────────┘
//                         ▼
//                  hmao_start_pulse, hmao_irq_clear (to HMAO engine)
//
//               KEY DESIGN DECISIONS:
//               1. Both cores run same firmware from same imem.mem image
//               2. Both cores receive IDENTICAL MMIO read inputs simultaneously
//               3. Core A's MMIO write outputs drive actual HMAO engine
//               4. Core B's MMIO write outputs are compared to Core A (voter)
//               5. Shadow delay = 2 cycles: creates temporal separation for
//                  glitch/SEU immunity (common cause failure detection)
//               6. DCLS error is STICKY: once asserted, stays until hw reset
//               7. riscv_start = 1: continuous execution (firmware poll loop)
//
//               PROCESSOR USED: RV32IM pipeline from RISCV-RV32IM-Processor-main
//               Top module: top_dcls.v (adapted with MMIO support)
//
//               NOTE: Since both cores run at same 400MHz as HMAO, NO CDC is
//               needed for HMAO_START/HMAO_COMPLETE signals (same clock domain).
//               This simplifies the design vs VexRiscv (was 250MHz, required CDC).
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module riscv_dcls_wrapper (
  input  logic          clk,          // 400 MHz ASIL-D (hmao_clk)
  input  logic          rst_n,        // Active-low synchronous reset

  // =========================================================================
  // HMAO ENGINE STATUS INPUTS (fed identically to both DCLS cores as MMIO)
  // Spec Ref: Section 5.2 register map
  // =========================================================================
  input  logic [31:0]   hmao_status,
  input  logic          hmao_decision,
  input  logic [31:0]   hmao_viol_lo,
  input  logic [31:0]   hmao_viol_hi,
  input  logic [31:0]   hmao_latency,
  input  logic [15:0]   hmao_lat_margin,
  input  logic [15:0]   hmao_long_margin,
  input  logic [15:0]   hmao_time_margin,
  input  logic          hmao_complete_irq,   // HMAO_COMPLETE edge-triggered IRQ

  // DMA status (firmware uses to gate HMAO_START sequence)
  input  logic          dma_traj_done,
  input  logic          dma_sig_valid,

  // =========================================================================
  // HMAO ENGINE CONTROL OUTPUTS (from Core A, validated by voter)
  // Spec Ref: Section 3.4 HMAO_START, Section 4.3 IRQ clear
  // =========================================================================
  output logic          hmao_start_pulse,    // HMAO_START single-cycle pulse
  output logic          hmao_irq_clear,      // HMAO_IRQ_CLEAR single-cycle pulse

  // =========================================================================
  // DCLS FAULT OUTPUTS
  // =========================================================================
  output logic          dcls_error,          // Lockstep comparison mismatch (sticky)
  output logic          core_halted          // Alias for dcls_error (MRM indicator)
);

  // ===========================================================================
  // PARAMETERS
  // ===========================================================================
  // Shadow delay: Core B receives same inputs but delayed by this many cycles.
  // Creates temporal diversity to detect SEU/transient faults that could
  // affect both cores simultaneously (common-cause failure).
  localparam int unsigned SHADOW_DELAY = 2;

  // ===========================================================================
  // INTERNAL: RISCV_START (tie high - firmware runs as continuous polling loop)
  // Spec Ref: Section 19.2 - firmware polls DMA_STATUS then sequences HMAO
  // ===========================================================================
  logic riscv_start;
  assign riscv_start = 1'b1;   // Always running (active reset is sync_reset inside top_dcls)

  // ===========================================================================
  // CORE A (PRIMARY) - Drives actual HMAO control signals
  // ===========================================================================
  logic coreA_mmio_start;
  logic coreA_mmio_irq_clear;
  logic coreA_done;

  top_dcls u_core_A (
    .clk              (clk),
    .reset            (~rst_n),          // top_dcls uses active-HIGH reset
    .riscv_start      (riscv_start),
    .riscv_done       (coreA_done),

    // MMIO read inputs (live, un-delayed)
    .hmao_status      (hmao_status),
    .hmao_decision    (hmao_decision),
    .hmao_viol_lo     (hmao_viol_lo),
    .hmao_viol_hi     (hmao_viol_hi),
    .hmao_latency     (hmao_latency),
    .hmao_lat_margin  (hmao_lat_margin),
    .hmao_long_margin (hmao_long_margin),
    .hmao_time_margin (hmao_time_margin),
    .ext_irq          (hmao_complete_irq),
    .dma_traj_done    (dma_traj_done),
    .dma_sig_valid    (dma_sig_valid),

    // MMIO write outputs (primary - drives HMAO engine)
    .mmio_start       (coreA_mmio_start),
    .mmio_irq_clear   (coreA_mmio_irq_clear)
  );

  // ===========================================================================
  // SHADOW INPUT DELAY REGISTERS
  // Core B receives the same inputs delayed by SHADOW_DELAY cycles.
  // This temporal offset means a transient fault (glitch, power noise, SEU)
  // would affect the two cores at different times → mismatch detected.
  // ===========================================================================
  logic [31:0] del_hmao_status     [0:SHADOW_DELAY-1];
  logic        del_hmao_decision   [0:SHADOW_DELAY-1];
  logic [31:0] del_hmao_viol_lo    [0:SHADOW_DELAY-1];
  logic [31:0] del_hmao_viol_hi    [0:SHADOW_DELAY-1];
  logic [31:0] del_hmao_latency    [0:SHADOW_DELAY-1];
  logic [15:0] del_lat_margin      [0:SHADOW_DELAY-1];
  logic [15:0] del_long_margin     [0:SHADOW_DELAY-1];
  logic [15:0] del_time_margin     [0:SHADOW_DELAY-1];
  logic        del_irq             [0:SHADOW_DELAY-1];
  logic        del_dma_done        [0:SHADOW_DELAY-1];
  logic        del_sig_valid       [0:SHADOW_DELAY-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < SHADOW_DELAY; i++) begin
        del_hmao_status[i]   <= '0;
        del_hmao_decision[i] <= '0;
        del_hmao_viol_lo[i]  <= '0;
        del_hmao_viol_hi[i]  <= '0;
        del_hmao_latency[i]  <= '0;
        del_lat_margin[i]    <= '0;
        del_long_margin[i]   <= '0;
        del_time_margin[i]   <= '0;
        del_irq[i]           <= '0;
        del_dma_done[i]      <= '0;
        del_sig_valid[i]     <= '0;
      end
    end else begin
      // Stage 0: sample live inputs
      del_hmao_status[0]   <= hmao_status;
      del_hmao_decision[0] <= hmao_decision;
      del_hmao_viol_lo[0]  <= hmao_viol_lo;
      del_hmao_viol_hi[0]  <= hmao_viol_hi;
      del_hmao_latency[0]  <= hmao_latency;
      del_lat_margin[0]    <= hmao_lat_margin;
      del_long_margin[0]   <= hmao_long_margin;
      del_time_margin[0]   <= hmao_time_margin;
      del_irq[0]           <= hmao_complete_irq;
      del_dma_done[0]      <= dma_traj_done;
      del_sig_valid[0]     <= dma_sig_valid;

      // Shift remaining stages
      for (int i = 1; i < SHADOW_DELAY; i++) begin
        del_hmao_status[i]   <= del_hmao_status[i-1];
        del_hmao_decision[i] <= del_hmao_decision[i-1];
        del_hmao_viol_lo[i]  <= del_hmao_viol_lo[i-1];
        del_hmao_viol_hi[i]  <= del_hmao_viol_hi[i-1];
        del_hmao_latency[i]  <= del_hmao_latency[i-1];
        del_lat_margin[i]    <= del_lat_margin[i-1];
        del_long_margin[i]   <= del_long_margin[i-1];
        del_time_margin[i]   <= del_time_margin[i-1];
        del_irq[i]           <= del_irq[i-1];
        del_dma_done[i]      <= del_dma_done[i-1];
        del_sig_valid[i]     <= del_sig_valid[i-1];
      end
    end
  end

  // ===========================================================================
  // CORE B (SHADOW) - Receives delayed inputs for temporal diversity
  // ===========================================================================
  logic coreB_mmio_start;
  logic coreB_mmio_irq_clear;
  logic coreB_done;

  top_dcls u_core_B (
    .clk              (clk),
    .reset            (~rst_n),
    .riscv_start      (riscv_start),
    .riscv_done       (coreB_done),

    // MMIO read inputs (delayed by SHADOW_DELAY cycles)
    .hmao_status      (del_hmao_status[SHADOW_DELAY-1]),
    .hmao_decision    (del_hmao_decision[SHADOW_DELAY-1]),
    .hmao_viol_lo     (del_hmao_viol_lo[SHADOW_DELAY-1]),
    .hmao_viol_hi     (del_hmao_viol_hi[SHADOW_DELAY-1]),
    .hmao_latency     (del_hmao_latency[SHADOW_DELAY-1]),
    .hmao_lat_margin  (del_lat_margin[SHADOW_DELAY-1]),
    .hmao_long_margin (del_long_margin[SHADOW_DELAY-1]),
    .hmao_time_margin (del_time_margin[SHADOW_DELAY-1]),
    .ext_irq          (del_irq[SHADOW_DELAY-1]),
    .dma_traj_done    (del_dma_done[SHADOW_DELAY-1]),
    .dma_sig_valid    (del_sig_valid[SHADOW_DELAY-1]),

    // MMIO write outputs (shadow - compared, not driven to HMAO)
    .mmio_start       (coreB_mmio_start),
    .mmio_irq_clear   (coreB_mmio_irq_clear)
  );

  // ===========================================================================
  // SHADOW DELAY PIPELINE FOR CORE A OUTPUTS
  // To compare Core A vs Core B, we must delay Core A's OUTPUTS by
  // SHADOW_DELAY cycles so they align in time with Core B's OUTPUTS.
  // (Core B processes the same stimulus SHADOW_DELAY cycles later.)
  // ===========================================================================
  logic coreA_start_del   [0:SHADOW_DELAY-1];
  logic coreA_iqclr_del   [0:SHADOW_DELAY-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < SHADOW_DELAY; i++) begin
        coreA_start_del[i] <= 1'b0;
        coreA_iqclr_del[i] <= 1'b0;
      end
    end else begin
      coreA_start_del[0] <= coreA_mmio_start;
      coreA_iqclr_del[0] <= coreA_mmio_irq_clear;
      for (int i = 1; i < SHADOW_DELAY; i++) begin
        coreA_start_del[i] <= coreA_start_del[i-1];
        coreA_iqclr_del[i] <= coreA_iqclr_del[i-1];
      end
    end
  end

  // ===========================================================================
  // DCLS VOTER / COMPARATOR
  // Compares Core A (time-delayed) outputs vs Core B (current) outputs.
  // Any mismatch = hardware fault → sticky DCLS error → VETO.
  //
  // Spec Ref: ASIL-D requires spatial & temporal redundancy with
  // independent comparison logic.
  // ===========================================================================
  logic mismatch_comb;
  logic dcls_error_latch;

  // Combinational comparison: aligned Core A vs current Core B
  assign mismatch_comb = (coreA_start_del[SHADOW_DELAY-1] !== coreB_mmio_start) ||
                         (coreA_iqclr_del[SHADOW_DELAY-1] !== coreB_mmio_irq_clear);

  // Sticky latch: once fault detected, stays asserted until hardware reset
  // Spec Ref: Section 1.3 "SAFE DEFAULT = VETO" - fault → VETO until reset
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dcls_error_latch <= 1'b0;
    end else begin
      if (mismatch_comb) begin
        dcls_error_latch <= 1'b1;  // Sticky - only hardware reset can clear
      end
    end
  end

  assign dcls_error  = dcls_error_latch;
  assign core_halted = dcls_error_latch;

  // ===========================================================================
  // OUTPUT ASSIGNMENTS
  // Core A drives the actual HMAO control signals when no DCLS error.
  // On DCLS error, outputs are suppressed (force VETO via soc_top fault path).
  // NOTE: Even if suppressed here, the fault_manager in soc_top will
  // assert VETO via dcls_error → FMU → MRM path.
  // ===========================================================================
  assign hmao_start_pulse = coreA_mmio_start   & ~dcls_error_latch;
  assign hmao_irq_clear   = coreA_mmio_irq_clear & ~dcls_error_latch;

  // ===========================================================================
  // FORMAL ASSERTIONS (ASIL-D - for JasperGold / VC Formal)
  // ===========================================================================
  `ifdef FORMAL
    // Once DCLS error asserted, it must remain asserted until reset
    assert property (@(posedge clk) disable iff (!rst_n)
      dcls_error |=> dcls_error)
      else $error("DCLS: Error latch not sticky - ASIL-D violation");

    // When DCLS error, no HMAO start should be issued
    assert property (@(posedge clk) disable iff (!rst_n)
      dcls_error |-> !hmao_start_pulse)
      else $error("DCLS: HMAO_START issued despite lockstep error");

    // hmao_start_pulse and dcls_error mutually exclusive
    assert property (@(posedge clk) disable iff (!rst_n)
      !(hmao_start_pulse && dcls_error))
      else $error("DCLS: start pulse and error simultaneously - impossible");
  `endif

endmodule : riscv_dcls_wrapper
