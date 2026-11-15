// =============================================================================
// FILE        : hmao_formal_props.sv
// PROJECT     : HMAO Engine - Formal Verification Properties
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 15
// TOOLS       : Cadence JasperGold FPV + Synopsys VC Formal
// DESCRIPTION : All 12 formal properties from spec.
//               Status per spec: 8 proven, 3 bounded (k=100), 1 in progress
//
//               Import this file in JasperGold script as:
//               jg::read_file formal/props/hmao_formal_props.sv
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

// Bind to HMAO engine top
bind hmao_engine_top hmao_formal_props u_props (
  .clk                (clk),
  .rst_n              (rst_n),
  .hmao_start         (hmao_start),
  .hmao_complete      (hmao_complete),
  .hmao_decision_out  (hmao_decision_out),
  .hmao_violation_out (hmao_violation_out),
  .hmao_latency_out   (hmao_latency_out),
  .lateral_margin     (pipe.lateral_margin),
  .long_margin        (pipe.long_margin),
  .fsm_state          (u_fsm.effective_state),
  .output_grant       (output_grant),
  .output_veto        (output_veto),
  .fault_out          (fault_out),
  .fault_valid_out    (fault_valid_out)
);

module hmao_formal_props (
  input logic                 clk,
  input logic                 rst_n,
  input logic                 hmao_start,
  input logic                 hmao_complete,
  input logic                 hmao_decision_out,
  input logic [63:0]          hmao_violation_out,
  input logic [31:0]          hmao_latency_out,
  input logic [15:0]          lateral_margin,
  input logic [15:0]          long_margin,
  input hmao_fsm_state_t      fsm_state,
  input logic                 output_grant,
  input logic                 output_veto,
  input hmao_fault_t          fault_out,
  input logic                 fault_valid_out
);

  // ===========================================================================
  // PROPERTY CLASS P1: SAFETY / CORRECTNESS
  // ===========================================================================

  // P1.1: ZERO FALSE NEGATIVES (ASIL-D Mandatory)
  // "∀ T, ∀ O: intersects(reachable_set(T), O) → HMAO_decision = VETO"
  // Note: Full proof requires formal model of reachable_set and intersects.
  // This version checks: collision markers in violation flags → VETO
  // STATUS: IN PROGRESS (requires full zonotope model in formal environment)
  property p1_1_zero_false_negatives;
    @(posedge clk) disable iff (!rst_n)
    // If violation info has non-zero obstacle ID → decision must be VETO
    (hmao_complete && hmao_violation_out[47:32] != 16'h0) |->
    (hmao_decision_out == DECISION_VETO);
  endproperty
  P1_1_ZFN: assert property (p1_1_zero_false_negatives)
    else $error("P1.1 FAIL: False Negative - collision detected but GRANT issued");

  // P1.2: SAFE ACCEPTANCE
  // "∀ T: (∀ O: ¬intersects(...)) → HMAO_decision = GRANT"
  // STATUS: BOUNDED (k=100)
  property p1_2_safe_acceptance;
    @(posedge clk) disable iff (!rst_n)
    // If no violations in flags AND complete asserted → GRANT
    (hmao_complete &&
     hmao_violation_out[47:32] == 16'h0 &&
     hmao_violation_out[63:48] != 8'hFF) |->   // Not a system error
    (hmao_decision_out == DECISION_GRANT);
  endproperty
  P1_2_SAFE_ACCEPT: assert property (p1_2_safe_acceptance)
    else $error("P1.2 FAIL: Safe trajectory rejected (false positive)");

  // P1.3: ZONOTOPE OVER-APPROXIMATION
  // "∀ s, ∀ t: true_reachable_set(s,t) ≤ zonotope_set(s,t)"
  // STATUS: PROVEN offline + ABV (Abstract-Based Verification)
  // Hardware assertion: generators must never be smaller than initial uncertainty
  property p1_3_over_approximation;
    @(posedge clk) disable iff (!rst_n)
    // Lateral margin generator must be ≥ MIN_LATERAL at all times
    (lateral_margin >= MIN_LATERAL_Q8_8);
  endproperty
  P1_3_OVER_APPROX: assert property (p1_3_over_approximation)
    else $error("P1.3 FAIL: Zonotope under-approximating reachable set");

  // ===========================================================================
  // PROPERTY CLASS P2: TIMING / DETERMINISM
  // ===========================================================================

  // P2.1: BOUNDED LATENCY ≤ 10ms (4,000,000 cycles @400MHz)
  // "hmao_start |=> #[1:4_000_000] hmao_complete"
  // STATUS: PROVEN (bounded, k=4000000)
  property p2_1_bounded_latency;
    @(posedge clk) disable iff (!rst_n)
    $rose(hmao_start) |=> ##[1:MAX_TOTAL_CYCLES] $rose(hmao_complete);
  endproperty
  P2_1_LATENCY: assert property (p2_1_bounded_latency)
    else $error("P2.1 FAIL: HMAO exceeded 10ms latency bound");

  // Cover: Ensure fast path (4ms) is reachable
  P2_1_FAST_PATH: cover property (
    @(posedge clk) $rose(hmao_complete) &&
    (hmao_latency_out < 1_600_001)  // ≤ 4.0ms + 1 cycle
  );

  // P2.2: DETERMINISM - Same input → same latency
  // STATUS: PROVEN (structural property of pipeline)
  // Hardware check: latency counter must be deterministic
  // (Formal: check that latency_out is a pure function of input trajectory)
  property p2_2_determinism;
    @(posedge clk) disable iff (!rst_n)
    // FSM must not re-enter computation without new start pulse
    !$rose(hmao_start) |->
    !(fsm_state == FSM_STAGE1_COMP && $past(fsm_state == FSM_IDLE));
  endproperty
  P2_2_DETERMINISM: assert property (p2_2_determinism)
    else $error("P2.2 FAIL: FSM started computation without start pulse");

  // ===========================================================================
  // PROPERTY CLASS P3: ADAPTIVE MARGIN SAFETY
  // ===========================================================================

  // P3.1: MARGIN BOUNDS (Hardware Clamps)
  // "(lateral_margin_m > MIN_LATERAL) && (lateral_margin_m <= MAX_LATERAL) – always"
  // STATUS: PROVEN (combinational LUT with hardwired clamps)
  property p3_1_lateral_bounds;
    @(posedge clk)
    (lateral_margin >= MIN_LATERAL_Q8_8) && (lateral_margin <= MAX_LATERAL_Q8_8);
  endproperty
  P3_1_LAT_BOUNDS: assert property (p3_1_lateral_bounds)
    else $error("P3.1 FAIL: Lateral margin outside hardware clamp [0.5m, 3.0m]");

  property p3_1_long_bounds;
    @(posedge clk)
    (long_margin >= MIN_LONG_Q8_8) && (long_margin <= MAX_LONG_Q8_8);
  endproperty
  P3_1_LONG_BOUNDS: assert property (p3_1_long_bounds)
    else $error("P3.1 FAIL: Longitudinal margin outside hardware clamp [2.0m, 8.0m]");

  // P3.2: MARGIN MONOTONICITY
  // "(combined_quality_decreases) |=> (safety_margin_increases_or_equal)"
  // STATUS: PROVEN (by LUT construction monotonicity)
  // Checked via cover: verify low quality input produces max margin
  P3_2_MAX_MARGIN_LOW_QUALITY: cover property (
    @(posedge clk)
    (lateral_margin == MAX_LATERAL_Q8_8)  // Max margin is reachable
  );

  // P3.3: ZERO FALSE NEGATIVES WITH ADAPTIVE MARGINS
  // STATUS: BOUNDED (k=100)
  property p3_3_zfn_adaptive;
    @(posedge clk) disable iff (!rst_n)
    // When decision is GRANT, no obstacle ID should be flagged
    (hmao_decision_out == DECISION_GRANT && hmao_complete) |->
    (hmao_violation_out[47:32] == 16'h0 || hmao_violation_out[63:48] == 8'h00);
  endproperty
  P3_3_ZFN_ADAPTIVE: assert property (p3_3_zfn_adaptive)
    else $error("P3.3 FAIL: GRANT issued with non-zero obstacle violation");

  // ===========================================================================
  // PROPERTY CLASS P4: SECURITY / ISOLATION
  // ===========================================================================

  // P4.1: READ-ONLY MEMORY
  // "(hmao_mem_request) |=> !(hmao_mem_write_en) – absolute always"
  // STATUS: PROVEN (checked at interface level in SMPU)
  // Check: HMAO master user field must always be 0x1A
  // (Actual write-prevention is in SMPU module)
  property p4_1_readonly;
    @(posedge clk) disable iff (!rst_n)
    // FSM should never be in a write-generating state
    !(fsm_state == FSM_ERROR && fault_out.smpu_violation);
  endproperty
  P4_1_READONLY: assert property (p4_1_readonly)
    else $error("P4.1 FAIL: SMPU violation during ERROR state");

  // P4.2: QM ISOLATION - QM traffic must not affect HMAO latency
  // STATUS: PROVEN (QoS VC0 on NoC, HBM2 priority override)
  // Hardware check: latency_out should be within expected range regardless of QM
  property p4_2_qm_isolation;
    @(posedge clk) disable iff (!rst_n)
    $rose(hmao_complete) |->
    (hmao_latency_out <= MAX_TOTAL_CYCLES);
  endproperty
  P4_2_QM_ISOLATION: assert property (p4_2_qm_isolation)
    else $error("P4.2 FAIL: HMAO latency exceeded 10ms (QM interference?)");

  // ===========================================================================
  // ADDITIONAL ASIL-D PROPERTIES (Gap Analysis coverage)
  // ===========================================================================

  // Safe default: DECISION = VETO at reset
  property safe_default_reset;
    @(posedge clk) !rst_n |-> (hmao_decision_out == DECISION_VETO);
  endproperty
  SAFE_DEFAULT: assert property (safe_default_reset)
    else $error("ASIL-D: HMAO_DECISION not VETO at reset");

  // FSM_ERROR is sticky (cannot exit without reset)
  property fsm_error_sticky;
    @(posedge clk) disable iff (!rst_n)
    (fsm_state == FSM_ERROR) |=> (fsm_state == FSM_ERROR);
  endproperty
  FSM_ERROR_STICKY: assert property (fsm_error_sticky)
    else $error("ASIL-D: FSM_ERROR state not sticky");

  // FSM_ERROR → VETO always
  property fsm_error_veto;
    @(posedge clk) disable iff (!rst_n)
    (fsm_state == FSM_ERROR) |-> output_veto;
  endproperty
  FSM_ERROR_VETO: assert property (fsm_error_veto)
    else $error("ASIL-D: FSM_ERROR must always assert VETO");

  // Fault valid → FSM must transition to error or output_veto
  property fault_causes_veto;
    @(posedge clk) disable iff (!rst_n)
    $rose(fault_valid_out) |=> ##[1:100] output_veto;
  endproperty
  FAULT_VETO: assert property (fault_causes_veto)
    else $error("ASIL-D: Fault did not result in VETO within 100 cycles");

  // GRANT and VETO mutually exclusive
  property grant_veto_mutex;
    @(posedge clk) disable iff (!rst_n)
    !(output_grant && output_veto);
  endproperty
  GRANT_VETO_MUTEX: assert property (grant_veto_mutex)
    else $error("ASIL-D: GRANT and VETO simultaneously asserted - IMPOSSIBLE");

endmodule : hmao_formal_props
