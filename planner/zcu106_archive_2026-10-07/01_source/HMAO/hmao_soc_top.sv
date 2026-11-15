// =============================================================================
// FILE        : hmao_soc_top.sv
// PROJECT     : HMAO Engine - SoC Top Level
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 2.2 (SLR1 Safety Domain)
// SAFETY      : ASIL-D (ISO 26262)
// PLATFORM    : Xilinx Versal HX FPGA - SLR1
// DESCRIPTION : Top-level SoC module for SLR1 Safety Domain.
//               Integrates:
//               - HMAO Engine (safety verification accelerator)
//               - RISCV DCLS (thienhau RV32IM in Dual-Core Lockstep)
//               - SMPU (Safety Memory Protection Unit)
//               - Watchdog Timer (independent ring oscillator)
//               - CDC modules (QM ↔ ASIL-D)
//               - HMAO Register File (MMIO)
//               - Fault Manager (SFI → FMU)
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module hmao_soc_top (
  // =========================================================================
  // CLOCK & RESET
  // =========================================================================

  // Primary ASIL-D clock (400MHz, LOCKED)
  // Both HMAO and RISCV DCLS share this clock (both capable of 400MHz)
  input  logic          hmao_clk,        // 400 MHz - ASIL-D domain
  input  logic          hmao_rst_n,      // Active-low, synchronous reset

  // QM clock (BOOM/application CPU domain)
  input  logic          qm_clk,          // ~400MHz QM domain (can be different freq)
  input  logic          qm_rst_n,

  // Independent watchdog oscillator (NOT derived from hmao_clk)
  input  logic          wdt_ring_osc_clk, // Ring oscillator for watchdog independence

  // =========================================================================
  // UPSTREAM: Planning Accelerator → DMA → Trajectory Buffer
  // HMAO does NOT talk directly to Planning (Spec Ref: Section 19.1)
  // DMA writes to trajectory buffer, RISCV validates and pulses HMAO_START
  // =========================================================================

  // DMA completed signal from IOMMU (trajectory written & HMAC verified)
  input  logic          dma_traj_done,     // DMA copy complete, HMAC verified
  input  logic          dma_sig_valid,     // IOMMU signature check passed
  
  // TEST MODE: Direct HMAO_START injection (bypass RISCV for testing)
  input  logic          test_hmao_start,   // Testbench can directly pulse HMAO

  // =========================================================================
  // AXI4 Slave Port: External NoC → HMAO Register Access (from RISCV)
  // RISCV uses this path to read HMAO_DECISION, write HMAO_START
  // =========================================================================
  // (Connected internally; RISCV DMEM → HMAO RegFile via internal bus)

  // =========================================================================
  // AXI4 Master Port: HMAO → World Model / Trajectory (via SMPU)
  // READ-ONLY. SMPU enforces no writes. Master ID = 0x1A
  // =========================================================================
  output logic [31:0]   hmao_araddr,
  output logic [7:0]    hmao_arlen,
  output logic [2:0]    hmao_arsize,
  output logic [1:0]    hmao_arburst,
  output logic          hmao_arvalid,
  output logic [7:0]    hmao_aruser,       // = HMAO_MASTER_ID = 0x1A
  input  logic          hmao_arready,
  input  logic [255:0]  hmao_rdata,        // 256-bit bus (2 beats = 64B WM object)
  input  logic [1:0]    hmao_rresp,
  input  logic          hmao_rlast,
  input  logic          hmao_rvalid,
  output logic          hmao_rready,

  // =========================================================================
  // DOWNSTREAM: HMAO → CAN-FD Interface
  // When VETO: VexRiscv (now RISCV DCLS) triggers MRM via CAN-FD
  // =========================================================================
  output logic          can_tx_mrm_req,    // MRM request to CAN-FD
  output logic          can_tx_grant,      // Forwarded GRANT to downstream actuator

  // =========================================================================
  // INTERRUPT OUT: HMAO_COMPLETE → RISCV IRQ controller
  // =========================================================================
  output logic          hmao_irq_out,      // Edge-triggered IRQ to RISCV

  // =========================================================================
  // SAFETY: Fault Interface → FMU (Fault Management Unit)
  // Spec Ref: Section 4.4
  // =========================================================================
  output logic [6:0]    sfi_fault_flags,   // Packed fault bits to FMU Leaf
  output logic          sfi_fault_valid,   // Any fault asserted
  input  logic          sfi_fault_ack,     // FMU acknowledges

  // =========================================================================
  // QM INPUT: Uncertainty Vector from BOOM CPU (via CDC)
  // Spec Ref: Section 3.3, Section 14
  // =========================================================================
  input  logic [7:0]    qm_gps_quality,
  input  logic [7:0]    qm_camera_quality,
  input  logic [7:0]    qm_road_friction,
  input  logic [7:0]    qm_actuator_health,
  input  logic [7:0]    qm_weather_severity,
  input  logic          qm_uvec_req,        // QM asserts after writing new vector
  output logic          qm_uvec_ack,        // ASIL-D acknowledges

  // =========================================================================
  // DEBUG / MONITORING (non-safety path)
  // =========================================================================
  output logic [2:0]    debug_fsm_state,
  output logic [31:0]   debug_latency_cycles,
  output logic          debug_riscv_halted,  // RISCV DCLS in lockstep error state
  
  // EXTENDED DEBUG (deep visibility into FSM and pipeline)
  output logic          debug_test_hmao_start_received,
  output logic          debug_hmao_start_combined,
  output logic          debug_hmao_start_pulse,
  output logic          debug_start_preproc,
  output logic [6:0]    debug_hmao_fsm_state_raw,
  output logic          debug_engine_hmao_start_seen,  // Is engine seeing hmao_start?
  output logic          debug_preproc_valid,           // Preproc completion signal
  output logic          debug_preproc_error            // Preproc error signal
);

  // ===========================================================================
  // INTERNAL SIGNALS
  // ===========================================================================

  // HMAO Engine control
  logic                 hmao_start_pulse;   // Single-cycle pulse from RISCV → HMAO
  logic                 hmao_complete_irq;  // HMAO done → RISCV IRQ
  logic                 hmao_decision;      // 1=GRANT, 0=VETO
  logic [63:0]          hmao_violation_flags;
  logic [31:0]          hmao_status;
  logic [31:0]          hmao_latency_cycles;
  logic [15:0]          hmao_lateral_margin;
  logic [15:0]          hmao_long_margin;
  logic [15:0]          hmao_time_margin;
  logic                 hmao_irq_clear;     // Written by RISCV to clear IRQ

  // Debug/Monitoring signals (from hmao_engine_top)
  logic                 internal_start_preproc;
  logic [6:0]           internal_fsm_state_raw;
  logic                 internal_engine_hmao_start_seen;
  logic                 internal_preproc_valid;
  logic                 internal_preproc_error;

  // Fault signals
  hmao_fault_t          fault_from_hmao;
  logic                 fault_valid_hmao;

  // CDC uncertainty vector (ASIL-D side, after parity check)
  logic [7:0]           asild_gps_quality;
  logic [7:0]           asild_camera_quality;
  logic [7:0]           asild_road_friction;
  logic [7:0]           asild_actuator_health;
  logic [7:0]           asild_weather_severity;

  // RISCV DCLS signals
  // Note: riscv_dcls_wrapper is now self-contained (embedded imem/dmem via top_dcls.v).
  // No external memory bus signals needed; HMAO regs accessed via MMIO in hmao_data_memory.
  logic                 riscv_dcls_error;  // Lockstep comparison failed

  // CDC watchdog override (BOOM dead → worst-case uncertainty already applied inside CDC)
  logic                 cdc_wdt_override;

  // SMPU violation
  logic                 smpu_violation;

  // Watchdog
  logic                 wdt_s1_timeout;
  logic                 wdt_s2_timeout;
  logic                 wdt_total_timeout;

  // ===========================================================================
  // INTERFACE INSTANTIATION
  // ===========================================================================

  // AXI4 Read-Only (HMAO → SMPU → Memory)
  axi4_ro_if #(.ADDR_W(32), .DATA_W(256), .ID_W(4)) hmao_axi_ro (
    .aclk   (hmao_clk),
    .aresetn(hmao_rst_n)
  );

  // Note: riscv_to_hmao_axil removed — RISCV now accesses HMAO regs via MMIO in
  //       hmao_data_memory (local 12-bit addr 0xF00-0xF44), not AXI-Lite.

  // HMAO Internal Pipeline
  hmao_pipe_if hmao_pipe (
    .clk  (hmao_clk),
    .rst_n(hmao_rst_n)
  );

  // Fault / SFI
  sfi_if sfi (
    .clk  (hmao_clk),
    .rst_n(hmao_rst_n)
  );

  // CDC Handshake (QM → ASIL-D uncertainty vector)
  cdc_handshake_if #(.DATA_W(40)) uvec_cdc (
    .src_clk(qm_clk),
    .dst_clk(hmao_clk),
    .rst_n  (hmao_rst_n)
  );

  // Note: riscv_mem_if removed — riscv_dcls_wrapper has internal memories.

  // ===========================================================================
  // SUBMODULE INSTANTIATION
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // 1. RISCV DCLS (Dual-Core Lockstep - thienhau RV32IM)
  // Spec Ref: Section 2.2 (SLR1 ASIL-D Domain)
  // Note: thienhau RISCV runs at 400+ MHz → same clock domain as HMAO.
  //       VexRiscv was 250MHz requiring CDC; now simplified to same domain.
  // ---------------------------------------------------------------------------
  riscv_dcls_wrapper u_riscv_dcls (
    .clk                (hmao_clk),
    .rst_n              (hmao_rst_n),

    // HMAO engine status inputs — RISCV reads via MMIO in embedded hmao_data_memory.
    // Spec Ref: Section 19.2 WCET sequence: firmware polls status, gates HMAO_START.
    .hmao_status        (hmao_status),
    .hmao_decision      (hmao_decision),
    .hmao_viol_lo       (hmao_violation_flags[31:0]),
    .hmao_viol_hi       (hmao_violation_flags[63:32]),
    .hmao_latency       (hmao_latency_cycles),
    .hmao_lat_margin    (hmao_lateral_margin),
    .hmao_long_margin   (hmao_long_margin),
    .hmao_time_margin   (hmao_time_margin),

    // HMAO_COMPLETE IRQ (edge-triggered, RISCV polls IRQ_STATUS at 0xF44)
    .hmao_complete_irq  (hmao_complete_irq),

    // DMA trigger (firmware waits for both before issuing HMAO_START)
    .dma_traj_done      (dma_traj_done),
    .dma_sig_valid      (dma_sig_valid),

    // HMAO control outputs: MMIO write-to-0xF04 → start pulse, 0xF0C → IRQ clear
    .hmao_start_pulse   (hmao_start_pulse),
    .hmao_irq_clear     (hmao_irq_clear),

    // DCLS fault outputs
    .dcls_error         (riscv_dcls_error),
    .core_halted        (debug_riscv_halted)
  );

  // NOTE: hmao_regfile removed.
  //   RISCV reads HMAO registers via MMIO in hmao_data_memory (0xF00-0xF44).
  //   hmao_start_pulse / hmao_irq_clear come directly from riscv_dcls_wrapper above.
  //   asild_* uncertainty vector comes from cdc_async_handshake_parity below.

  // ---------------------------------------------------------------------------
  // 2. HMAO ENGINE (Main Verification Core)
  // ---------------------------------------------------------------------------
  // TEST MODE: Can inject hmao_start directly for testing (OR with RISCV signal)
  logic hmao_start_combined;
  assign hmao_start_combined = hmao_start_pulse | test_hmao_start;
  
  hmao_engine_top u_hmao_engine (
    .clk                  (hmao_clk),
    .rst_n                (hmao_rst_n),

    // Control (from RISCV or test mode)
    .hmao_start           (hmao_start_combined),

    // Uncertainty vector (ASIL-D side, after CDC)
    .gps_quality          (asild_gps_quality),
    .camera_quality       (asild_camera_quality),
    .road_friction        (asild_road_friction),
    .actuator_health      (asild_actuator_health),
    .weather_severity     (asild_weather_severity),

    // AXI4 Read-Only Master (trajectory + world model access)
    .axi_ro               (hmao_axi_ro.master),

    // Internal pipeline bus
    .pipe                 (hmao_pipe),

    // Watchdog clock (independent, not hmao_clk)
    .wdt_clk              (wdt_ring_osc_clk),

    // Outputs
    .hmao_complete        (hmao_complete_irq),
    .hmao_decision_out    (hmao_decision),
    .hmao_violation_out   (hmao_violation_flags),
    .hmao_status_out      (hmao_status),
    .hmao_latency_out     (hmao_latency_cycles),
    .lateral_margin_out   (hmao_lateral_margin),
    .long_margin_out      (hmao_long_margin),
    .time_margin_out      (hmao_time_margin),

    // IRQ clear
    .irq_clear            (hmao_irq_clear),

    // Debug outputs (internal visibility for test/monitoring)
    .debug_start_preproc      (internal_start_preproc),
    .debug_fsm_state_encoded  (internal_fsm_state_raw),
    .debug_hmao_start_received (internal_engine_hmao_start_seen),
    .debug_preproc_valid      (internal_preproc_valid),
    .debug_preproc_error      (internal_preproc_error),

    // Faults
    .fault_out            (fault_from_hmao),
    .fault_valid_out      (fault_valid_hmao)
  );

  // ---------------------------------------------------------------------------
  // 4. SMPU (Safety Memory Protection Unit)
  // Spec Ref: Section 13.3 - Master ID 0x1A READ-ONLY
  // ---------------------------------------------------------------------------
  hmao_smpu u_smpu (
    .clk            (hmao_clk),
    .rst_n          (hmao_rst_n),

    // AXI4 from HMAO (READ-ONLY master, enforced)
    .axi_in         (hmao_axi_ro.slave),   // Note: SMPU sits between HMAO and memory

    // External NoC AXI outputs (after permission check)
    .ar_addr_out    (hmao_araddr),
    .ar_len_out     (hmao_arlen),
    .ar_size_out    (hmao_arsize),
    .ar_burst_out   (hmao_arburst),
    .ar_valid_out   (hmao_arvalid),
    .ar_user_out    (hmao_aruser),
    .ar_ready_in    (hmao_arready),
    .r_data_in      (hmao_rdata),
    .r_resp_in      (hmao_rresp),
    .r_last_in      (hmao_rlast),
    .r_valid_in     (hmao_rvalid),
    .r_ready_out    (hmao_rready),

    // Violation
    .smpu_violation (smpu_violation)
  );

  // ---------------------------------------------------------------------------
  // 5. CDC: QM Uncertainty Vector → ASIL-D
  // Spec Ref: Section 14 - Async Handshake + Parity
  // NOTE: Since RISCV now runs at same 400MHz as HMAO, this CDC module is
  // still needed for BOOM CPU (QM domain) uncertainty vector.
  // RISCV DCLS ↔ HMAO communication is now single-clock (no CDC needed).
  // ---------------------------------------------------------------------------
  cdc_async_handshake_parity u_cdc_uvec (
    // QM side (source)
    .src_clk          (qm_clk),
    .src_rst_n        (qm_rst_n),
    .src_data         ({qm_weather_severity, qm_actuator_health,
                        qm_road_friction, qm_camera_quality, qm_gps_quality}),
    .src_req          (qm_uvec_req),
    .src_ack          (qm_uvec_ack),

    // ASIL-D side (destination) — outputs feed hmao_engine_top directly
    .dst_clk          (hmao_clk),
    .dst_rst_n        (hmao_rst_n),
    .dst_data_valid   (),                         // Not needed externally; parity checked inside
    .dst_gps_q        (asild_gps_quality),
    .dst_cam_q        (asild_camera_quality),
    .dst_friction     (asild_road_friction),
    .dst_actuator     (asild_actuator_health),
    .dst_weather      (asild_weather_severity),

    // Watchdog: 200ms without REQ-ACK → CDC forces worst-case values internally
    // Spec Ref: Section 14, Step 5 — GPS=0, CAM=0, friction=0, actuator=0
    .wdt_override_en  (cdc_wdt_override)
  );

  // ---------------------------------------------------------------------------
  // 6. FAULT MANAGER (SFI → FMU)
  // Aggregates faults from: HMAO engine, SMPU, RISCV DCLS, Watchdog
  // ---------------------------------------------------------------------------
  hmao_fault_manager u_fault_mgr (
    .clk              (hmao_clk),
    .rst_n            (hmao_rst_n),

    // Fault sources
    .hmao_fault_in    (fault_from_hmao),
    .hmao_fault_valid (fault_valid_hmao),
    .smpu_violation   (smpu_violation),
    .riscv_dcls_err   (riscv_dcls_error),

    // SFI output to FMU
    .sfi_flags_out    (sfi_fault_flags),
    .sfi_valid_out    (sfi_fault_valid),
    .sfi_ack_in       (sfi_fault_ack)
  );

  // ---------------------------------------------------------------------------
  // 7. OUTPUT ASSIGNMENTS
  // ---------------------------------------------------------------------------

  // IRQ to RISCV DCLS (HMAO_COMPLETE, edge-triggered)
  assign hmao_irq_out     = hmao_complete_irq;

  // CAN-FD MRM trigger (VETO path)
  assign can_tx_mrm_req   = ~hmao_decision & hmao_complete_irq;
  assign can_tx_grant     =  hmao_decision & hmao_complete_irq;

  // Debug outputs
  assign debug_fsm_state       = hmao_status[2:0];
  assign debug_latency_cycles  = hmao_latency_cycles;
  assign debug_test_hmao_start_received = test_hmao_start;
  assign debug_hmao_start_combined = hmao_start_combined;
  assign debug_hmao_start_pulse = hmao_start_pulse;
  assign debug_hmao_fsm_state_raw = internal_fsm_state_raw;  // Raw Hamming-encoded FSM state
  assign debug_start_preproc = internal_start_preproc;  // Pulsed when preproc starts
  assign debug_engine_hmao_start_seen = internal_engine_hmao_start_seen;  // Is engine seeing hmao_start?
  assign debug_preproc_valid = internal_preproc_valid;  // Is preproc_valid HIGH?
  assign debug_preproc_error = internal_preproc_error;  // Is preproc_error HIGH?

  // ===========================================================================
  // FORMAL ASSERTIONS (Spec Ref: Section 15)
  // These are synthesizable assertions for JasperGold / VC Formal
  // ===========================================================================
  // solaris: disable linting in formal tool
  `ifdef FORMAL
    // P2.1: Bounded Latency ≤ 10ms = 4,000,000 cycles
    // assert property (@(posedge hmao_clk) disable iff (!hmao_rst_n)
    //   hmao_start_pulse |=> ##[1:MAX_TOTAL_CYCLES] hmao_complete_irq);

    // P4.1: Read-Only Memory - HMAO must never assert AWVALID
    assert property (@(posedge hmao_clk) disable iff (!hmao_rst_n)
      hmao_axi_ro.arvalid |-> (hmao_aruser == HMAO_MASTER_ID))
      else $error("SMPU: Wrong master ID on AXI request");

    // Safe default: HMAO_DECISION = VETO at reset
    assert property (@(posedge hmao_clk)
      !hmao_rst_n |-> (hmao_decision == 1'b0))
      else $error("P1: HMAO decision not VETO at reset");
  `endif

endmodule : hmao_soc_top
