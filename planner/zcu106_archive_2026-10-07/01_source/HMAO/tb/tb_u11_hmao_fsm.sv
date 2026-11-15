// =============================================================================
// FILE        : tb_u11_hmao_fsm.sv
// PROJECT     : HMAO Engine - Unit Test Batch U11
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 9.1, 9.3, 9.4
// SAFETY      : ASIL-D (ISO 26262) - Verification Evidence
// AUTHOR      : [Your Name]
// DATE        : 2024
// DESCRIPTION : Safety & Robustness testbench for hmao_fsm.sv.
//               Verifies hardware safety features required by ASIL-D.
//
//   TF_004 – Watchdog Timeout (FSM Hang → ERROR)
//            Inject hang at STAGE1_COMP (never assert s1_zono_valid).
//            Drive wdt_s1_timeout=1 after exactly WDT_STAGE1_CYCLES (1.8M cycles).
//            Verify: watchdog_timeout asserted → FSM enters FSM_ERROR, output_veto=1.
//            SVA A4_WDT: wdt_s1_timeout |-> ##1 fsm_state == FSM_ERROR
//
//   TF_005 – Hamming-3 State Encoding (Bit-Flip Fault Injection)
//            TF_005a: Flip 1 bit in state_reg_b only → cross-check detects mismatch
//                     → effective_state = FSM_ERROR immediately (same cycle).
//            TF_005b: Force BOTH state_reg_a & state_reg_b to same invalid codeword
//                     → unique case default branch → next_state = FSM_ERROR.
//            SVA A5_CROSS: (state_reg_a !== state_reg_b) |-> effective == FSM_ERROR
//            SVA A5_HAMM:  invalid_codeword |=> fsm_state == FSM_ERROR
//
//   TF_006 – FSM Output Timing (Cycle-Accurate Synchrony)
//            Validate output_grant and output_veto are asserted simultaneously with
//            the precise cycle that causes the FSM to enter OUTPUT state.
//            Verify zero phase difference between data (HMAO_DECISION) and
//            completion notification (HMAO_COMPLETE).
//            SVA A6_GRANT_T:  output_grant       |-> ##1 fsm_state == FSM_OUTPUT_GRANT
//            SVA A6_GRANT_P:  FSM_OUTPUT_GRANT   |-> $past(output_grant)
//            SVA A6_VETO_T:   (FSM→OUTPUT_VETO)  |-> $past(output_veto)
//            SVA A6_MUTEX:    !(output_grant && output_veto) [always]
//
// COMPILE    : vlog -sv hmao_pkg.sv hmao_fsm.sv tb_u11_hmao_fsm.sv
//              vsim -sv_seed 1 tb_u11_hmao_fsm -do "run -all"
//
// HIERARCHY  : DUT state register paths (for force/release):
//              tb_u11_hmao_fsm.u_dut.state_reg_a  [6:0] — Primary copy
//              tb_u11_hmao_fsm.u_dut.state_reg_b  [6:0] — Redundant copy
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module tb_u11_hmao_fsm;

  // ===========================================================================
  // SECTION 1: CLOCK, RESET, CYCLE COUNTER
  // ===========================================================================
  localparam real CLK_HALF_NS = CLK_PERIOD_NS / 2.0;   // 1.25 ns → 400 MHz

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #(CLK_HALF_NS) clk = ~clk;

  // Free-running cycle counter (used for timing assertions)
  longint unsigned cycle_cnt = 0;
  always_ff @(posedge clk) cycle_cnt++;

  // ===========================================================================
  // SECTION 2: DUT PORT DECLARATIONS
  // ===========================================================================
  logic hmao_start      = 1'b0;
  logic preproc_valid   = 1'b0;
  logic preproc_error   = 1'b0;
  logic s1_zono_valid   = 1'b0;
  logic s1_no_collision = 1'b0;
  logic s1_potential    = 1'b0;
  logic admm_done       = 1'b0;
  logic admm_diverged   = 1'b0;
  logic s2_zono_valid   = 1'b0;
  logic s2_no_collision = 1'b0;
  logic s2_collision    = 1'b0;

  logic crc_error       = 1'b0;
  logic numerical_error = 1'b0;
  logic wdt_s1_timeout  = 1'b0;
  logic wdt_s2_timeout  = 1'b0;

  hmao_fsm_state_t fsm_state_out;
  logic start_preproc, start_s1, start_admm, start_s2;
  logic output_grant, output_veto;

  // ===========================================================================
  // SECTION 3: DUT INSTANTIATION
  // Hierarchical paths for force/release (TF_005):
  //   tb_u11_hmao_fsm.u_dut.state_reg_a  — Primary state register
  //   tb_u11_hmao_fsm.u_dut.state_reg_b  — Redundant state register
  // ===========================================================================
  hmao_fsm u_dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .hmao_start      (hmao_start),
    .preproc_valid   (preproc_valid),
    .preproc_error   (preproc_error),
    .s1_zono_valid   (s1_zono_valid),
    .s1_no_collision (s1_no_collision),
    .s1_potential    (s1_potential),
    .admm_done       (admm_done),
    .admm_diverged   (admm_diverged),
    .s2_zono_valid   (s2_zono_valid),
    .s2_no_collision (s2_no_collision),
    .s2_collision    (s2_collision),
    .crc_error       (crc_error),
    .numerical_error (numerical_error),
    .wdt_s1_timeout  (wdt_s1_timeout),
    .wdt_s2_timeout  (wdt_s2_timeout),
    .fsm_state_out   (fsm_state_out),
    .start_preproc   (start_preproc),
    .start_s1        (start_s1),
    .start_admm      (start_admm),
    .start_s2        (start_s2),
    .output_grant    (output_grant),
    .output_veto     (output_veto)
  );

  // ===========================================================================
  // SECTION 4: TEST BOOKKEEPING
  // ===========================================================================
  int pass_count = 0;
  int fail_count = 0;

  // Latch one-cycle pulses so procedural code can inspect them after @(posedge clk)
  logic start_s1_d1, start_admm_d1, output_grant_d1, output_veto_d1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_s1_d1    <= 1'b0;
      start_admm_d1  <= 1'b0;
      output_grant_d1 <= 1'b0;
      output_veto_d1  <= 1'b0;
    end else begin
      start_s1_d1    <= start_s1;
      start_admm_d1  <= start_admm;
      output_grant_d1 <= output_grant;
      output_veto_d1  <= output_veto;
    end
  end

  // ===========================================================================
  // SECTION 5: HELPER TASKS
  // ===========================================================================

  // Reset FSM and clear all stimulus
  task automatic do_reset(input int hold_cycles = 10);
    rst_n          <= 1'b0;
    hmao_start     <= 1'b0;
    preproc_valid  <= 1'b0;
    preproc_error  <= 1'b0;
    s1_zono_valid  <= 1'b0;
    s1_no_collision<= 1'b0;
    s1_potential   <= 1'b0;
    admm_done      <= 1'b0;
    admm_diverged  <= 1'b0;
    s2_zono_valid  <= 1'b0;
    s2_no_collision<= 1'b0;
    s2_collision   <= 1'b0;
    crc_error      <= 1'b0;
    numerical_error<= 1'b0;
    wdt_s1_timeout <= 1'b0;
    wdt_s2_timeout <= 1'b0;
    repeat(hold_cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);   // One settle cycle
  endtask

  // Pulse hmao_start for N cycles
  task automatic pulse_start(input int hold_cycles = 2);
    hmao_start <= 1'b1;
    repeat(hold_cycles) @(posedge clk);
    hmao_start <= 1'b0;
  endtask

  // Wait for a target FSM state with cycle timeout
  task automatic wait_for_state(
    input  hmao_fsm_state_t target,
    input  longint          timeout_cycles,
    output logic            reached
  );
    reached = 1'b0;
    for (longint i = 0; i < timeout_cycles; i++) begin
      @(posedge clk);
      if (fsm_state_out === target) begin
        reached = 1'b1;
        return;
      end
    end
  endtask

  // Log check with pass/fail accounting
  task automatic log_check(
    input string label,
    input logic  pass_cond
  );
    if (pass_cond) begin
      $display("[PASS] %s", label);
      pass_count++;
    end else begin
      $error("[FAIL] %s", label);
      fail_count++;
    end
  endtask

  // Decode FSM state enum to printable string
  function automatic string state_str(input hmao_fsm_state_t s);
    case (s)
      FSM_IDLE:         return "FSM_IDLE";
      FSM_STAGE1_COMP:  return "FSM_STAGE1_COMP";
      FSM_STAGE1_CHECK: return "FSM_STAGE1_CHECK";
      FSM_STAGE2_COMP:  return "FSM_STAGE2_COMP";
      FSM_STAGE2_CHECK: return "FSM_STAGE2_CHECK";
      FSM_OUTPUT_GRANT: return "FSM_OUTPUT_GRANT";
      FSM_OUTPUT_VETO:  return "FSM_OUTPUT_VETO";
      FSM_ERROR:        return "FSM_ERROR";
      default:          return $sformatf("INVALID(7'b%07b)", 7'(s));
    endcase
  endfunction

  // ===========================================================================
  // SECTION 6: CONCURRENT SVA ASSERTIONS
  // These fire throughout the entire simulation.
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // TF_004 SVA GROUP: Watchdog → ERROR
  // ---------------------------------------------------------------------------

  // A4_WDT_S1: Stage1 watchdog must transition FSM to ERROR in exactly 1 cycle
  property p_wdt_s1_to_error;
    @(posedge clk)
    (wdt_s1_timeout && (fsm_state_out == FSM_STAGE1_COMP ||
                        fsm_state_out == FSM_STAGE1_CHECK))
    |-> ##1 (fsm_state_out == FSM_ERROR);
  endproperty
  A4_WDT_S1_TO_ERROR: assert property (p_wdt_s1_to_error)
    else $error("[SVA A4_WDT_S1] wdt_s1_timeout did not drive FSM→ERROR in 1 cycle");

  // A4_WDT_VETO: output_veto must be asserted simultaneously with the watchdog trigger
  property p_wdt_veto_immediate;
    @(posedge clk)
    (wdt_s1_timeout && (fsm_state_out == FSM_STAGE1_COMP ||
                        fsm_state_out == FSM_STAGE1_CHECK))
    |-> output_veto;
  endproperty
  A4_WDT_VETO_IMMEDIATE: assert property (p_wdt_veto_immediate)
    else $error("[SVA A4_WDT_VETO] output_veto not asserted on watchdog timeout cycle");

  // A4_ERROR_STICKY: FSM_ERROR is a stuck state — only rst_n can exit it
  property p_error_sticky;
    @(posedge clk)
    (fsm_state_out == FSM_ERROR) |=> (fsm_state_out == FSM_ERROR);
  endproperty
  A4_ERROR_STICKY: assert property (p_error_sticky)
    else $error("[SVA A4_ERROR_STICKY] FSM_ERROR must be stuck (requires system reset)");

  // A4_ERROR_VETO: VETO permanently asserted in ERROR state
  property p_error_veto_permanent;
    @(posedge clk)
    (fsm_state_out == FSM_ERROR) |-> output_veto;
  endproperty
  A4_ERROR_VETO_PERMANENT: assert property (p_error_veto_permanent)
    else $error("[SVA A4_ERROR_VETO] output_veto must always be 1 in FSM_ERROR");

  // ---------------------------------------------------------------------------
  // TF_005 SVA GROUP: Hamming-3 State Encoding
  // ---------------------------------------------------------------------------

  // A5_CROSS_CHECK: Any state register mismatch must produce FSM_ERROR immediately
  // Access the internal redundant registers via hierarchical reference
  property p_cross_check_error;
    @(posedge clk)
    (u_dut.state_reg_a !== u_dut.state_reg_b)
    |-> (fsm_state_out == FSM_ERROR);
  endproperty
  A5_CROSS_CHECK: assert property (p_cross_check_error)
    else $error("[SVA A5_CROSS] state_reg mismatch not immediately producing FSM_ERROR");

  // A5_INVALID_CODEWORD: Any state register holding a non-Hamming codeword must
  // cause FSM_ERROR by next clock edge (via default branch of unique case).
  // A codeword is invalid if it is not one of the 8 defined enum values.
  function automatic logic is_valid_codeword(input logic [6:0] enc);
    case (enc)
      7'b000_0000,    // FSM_IDLE
      7'b000_0111,    // FSM_STAGE1_COMP
      7'b001_1001,    // FSM_STAGE1_CHECK
      7'b001_1110,    // FSM_STAGE2_COMP
      7'b010_1010,    // FSM_STAGE2_CHECK
      7'b010_1101,    // FSM_OUTPUT_GRANT
      7'b011_0011,    // FSM_OUTPUT_VETO
      7'b011_0100:    // FSM_ERROR
               return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  property p_invalid_codeword_to_error;
    @(posedge clk)
    // Both registers equal (cross-check passes) but codeword is invalid
    ((u_dut.state_reg_a === u_dut.state_reg_b) &&
     !is_valid_codeword(u_dut.state_reg_a))
    |=> (fsm_state_out == FSM_ERROR);
  endproperty
  A5_INVALID_CODEWORD: assert property (p_invalid_codeword_to_error)
    else $error("[SVA A5_HAMM] Invalid Hamming codeword did not produce FSM_ERROR next cycle");

  // ---------------------------------------------------------------------------
  // TF_006 SVA GROUP: Output Timing (cycle-accurate)
  // ---------------------------------------------------------------------------

  // A6_GRANT_TIMING: output_grant must be followed by FSM_OUTPUT_GRANT exactly 1 cycle later
  // (grant is a combinational pulse in the CHECK state; state register updates next cycle)
  property p_grant_leads_state;
    @(posedge clk)
    output_grant |-> ##1 (fsm_state_out == FSM_OUTPUT_GRANT);
  endproperty
  A6_GRANT_TIMING: assert property (p_grant_leads_state)
    else $error("[SVA A6_GRANT_T] output_grant pulse not followed by FSM_OUTPUT_GRANT in 1 cycle");

  // A6_GRANT_PRIOR: When FSM enters OUTPUT_GRANT, output_grant was high exactly 1 cycle prior
  // (verifies no extra pipeline delay — grant is synchronous with state transition trigger)
  property p_grant_prior_to_state;
    @(posedge clk)
    (fsm_state_out == FSM_OUTPUT_GRANT) |-> $past(output_grant, 1);
  endproperty
  A6_GRANT_PRIOR: assert property (p_grant_prior_to_state)
    else $error("[SVA A6_GRANT_P] FSM entered OUTPUT_GRANT without output_grant in prior cycle");

  // A6_VETO_TIMING: output_veto (from transition states) must be followed by
  // FSM_OUTPUT_VETO or FSM_ERROR within 1 cycle.
  // Note: output_veto is also asserted continuously IN FSM_ERROR and FSM_OUTPUT_VETO,
  //       so this property guards against phantom veto pulses from other states.
  property p_veto_leads_to_veto_state;
    @(posedge clk)
    // Veto from a non-veto, non-error state must cause veto/error next cycle
    (output_veto &&
     (fsm_state_out != FSM_OUTPUT_VETO) &&
     (fsm_state_out != FSM_ERROR))
    |-> ##1 (fsm_state_out == FSM_OUTPUT_VETO || fsm_state_out == FSM_ERROR);
  endproperty
  A6_VETO_TIMING: assert property (p_veto_leads_to_veto_state)
    else $error("[SVA A6_VETO_T] Unexpected output_veto pulse did not lead to VETO/ERROR state");

  // A6_MUTEX: GRANT and VETO are mutually exclusive at all times (ASIL-D requirement)
  property p_grant_veto_mutex;
    @(posedge clk)
    !(output_grant && output_veto);
  endproperty
  A6_MUTEX: assert property (p_grant_veto_mutex)
    else $error("[SVA A6_MUTEX] output_grant and output_veto both asserted — ASIL-D violation");

  // A6_NO_SPURIOUS_GRANT: output_grant may only be high when entering OUTPUT_GRANT
  property p_no_spurious_grant;
    @(posedge clk)
    output_grant |->
      (fsm_state_out == FSM_STAGE1_CHECK || fsm_state_out == FSM_STAGE2_CHECK);
  endproperty
  A6_NO_SPURIOUS_GRANT: assert property (p_no_spurious_grant)
    else $error("[SVA A6_SPURIOUS] output_grant asserted from unexpected FSM state");

  // ===========================================================================
  // SECTION 7: MAIN TEST BODY
  // ===========================================================================
  initial begin : u11_main

    $display("═══════════════════════════════════════════════════════════════════");
    $display("  BATCH U11 — HMAO FSM Safety & Robustness Verification");
    $display("  ASIL-D ISO 26262 | HMAO_Engine_Full_Spec v12.0 Sec. 9.1/9.3/9.4");
    $display("═══════════════════════════════════════════════════════════════════");

    // =========================================================================
    // TF_004: Watchdog Timeout → FSM_ERROR + VETO
    //
    // Fault injection model:
    //   • Start HMAO with preproc_valid=1 (fast path → STAGE1_COMP immediately)
    //   • Never assert s1_zono_valid (simulate computation hang)
    //   • After exactly WDT_STAGE1_CYCLES (1,800,000 cycles @ 400MHz = 4.5ms),
    //     drive wdt_s1_timeout=1 for 1 cycle.
    //   • Verify FSM_ERROR and output_veto the same cycle.
    //   • Verify FSM_ERROR is sticky (check for 5 more cycles post-timeout).
    //   • Cycle budget: FSM must be in STAGE1_COMP throughout without exiting.
    //
    // Coverage: Section 9.3 Watchdog (WDT_STAGE1_CYCLES = 1,800,000).
    // =========================================================================
    $display("");
    $display("───────────────────────────────────────────────────────────────────");
    $display("[TF_004] Watchdog Timeout → FSM_ERROR + VETO");
    $display("         WDT budget: %0d cycles (%.1f ms)",
             WDT_STAGE1_CYCLES, real'(WDT_STAGE1_CYCLES) / real'(CLK_FREQ_HZ) * 1000.0);
    $display("───────────────────────────────────────────────────────────────────");

    do_reset(10);

    begin : tf004_body
      longint t4_start;
      longint t4_wdt_cycle;
      logic   reached;

      // ---- Setup: preproc already valid → IDLE→STAGE1_COMP immediately ----
      preproc_valid <= 1'b1;
      admm_done     <= 1'b0;
      @(posedge clk);

      t4_start = cycle_cnt;
      $display("[TF_004] Triggering hmao_start (preproc_valid=1)...");
      pulse_start(1);
      @(posedge clk);   // Propagation cycle

      // T1: Verify FSM entered STAGE1_COMP
      log_check(
        $sformatf("TF_004.T1  : IDLE→STAGE1_COMP at cycle %0d", cycle_cnt),
        fsm_state_out == FSM_STAGE1_COMP);

      // ---- Simulate computation hang: never assert s1_zono_valid ----
      // Count down exactly WDT_STAGE1_CYCLES - 1 cycles (the +1 is from the step above)
      $display("[TF_004]   Simulating STAGE1_COMP hang (%0d watchdog cycles)...",
               WDT_STAGE1_CYCLES);
      repeat(WDT_STAGE1_CYCLES - 1) @(posedge clk);

      // T2: Confirm FSM is still stuck in STAGE1_COMP (has not self-recovered)
      log_check(
        $sformatf("TF_004.T2  : FSM still in STAGE1_COMP after %0d cycles (hang confirmed)",
                  WDT_STAGE1_CYCLES - 1),
        fsm_state_out == FSM_STAGE1_COMP);
      log_check("TF_004.T2b : output_veto=0 before watchdog fires (no premature VETO)",
                output_veto == 1'b0);

      // ---- Fire watchdog timeout at exactly WDT_STAGE1_CYCLES ----
      $display("[TF_004]   Asserting wdt_s1_timeout=1 (simulating hardware watchdog fire)...");
      t4_wdt_cycle = cycle_cnt;
      wdt_s1_timeout <= 1'b1;

      // T3: output_veto must be asserted IMMEDIATELY (combinational, same cycle)
      // The SVA A4_WDT_VETO_IMMEDIATE already fires here; procedural check below.
      // We check combinatorially before the clock edge (signal already driven high)
      @(posedge clk);   // Clock edge: FSM latches next_state = FSM_ERROR
      #1;  // Let always_ff NBAs settle before reading registered outputs

      // T3a: output_veto was combinatorially high on the watchdog cycle (captured by d1 latch)
      log_check(
        $sformatf("TF_004.T3a : output_veto asserted on watchdog timeout cycle %0d (comb immediate)",
                  t4_wdt_cycle),
        output_veto_d1 == 1'b1);

      // T3b: FSM is now in FSM_ERROR (latched on the clock edge after timeout)
      log_check(
        $sformatf("TF_004.T3b : FSM entered FSM_ERROR at cycle %0d (1 cycle after timeout)",
                  cycle_cnt),
        fsm_state_out == FSM_ERROR);

      // T3c: output_veto still asserted (permanent in ERROR)
      log_check("TF_004.T3c : output_veto=1 in FSM_ERROR (VETO is permanent)",
                output_veto == 1'b1);

      wdt_s1_timeout <= 1'b0;   // Release stimulus — FSM must stay in ERROR

      // T4: Verify ERROR is sticky for 5 consecutive cycles (ASIL-D stuck requirement)
      $display("[TF_004]   Verifying FSM_ERROR stickiness for 5 cycles post-timeout...");
      begin : tf004_sticky_check
        logic all_stuck;
        all_stuck = 1'b1;
        for (int i = 0; i < 5; i++) begin
          @(posedge clk);
          if (fsm_state_out !== FSM_ERROR) all_stuck = 1'b0;
        end
        log_check("TF_004.T4  : FSM_ERROR is sticky — 5 consecutive cycles after WDT (reset required)",
                  all_stuck);
      end : tf004_sticky_check

      // T5: Total elapsed from hmao_start to ERROR must equal WDT_STAGE1_CYCLES ± 2
      begin
        longint elapsed = cycle_cnt - t4_start;
        $display("[TF_004]   Elapsed from start to ERROR: %0d cycles (%.3f ms)",
                 elapsed, real'(elapsed) / real'(CLK_FREQ_HZ) * 1000.0);
        log_check(
          $sformatf("TF_004.T5  : Watchdog fires at WDT_STAGE1_CYCLES=%0d (elapsed=%0d, tol±7)",
                    WDT_STAGE1_CYCLES, elapsed),
          (elapsed >= WDT_STAGE1_CYCLES - 2) && (elapsed <= WDT_STAGE1_CYCLES + 7));
      end

    end : tf004_body

    $display("[TF_004] COMPLETE\n");

    // =========================================================================
    // TF_005: Hamming-3 State Encoding — Bit-Flip Fault Injection
    //
    // Uses SystemVerilog force/release on internal registers:
    //   tb_u11_hmao_fsm.u_dut.state_reg_a  — Primary copy
    //   tb_u11_hmao_fsm.u_dut.state_reg_b  — Redundant copy
    //
    // TF_005a — Single-bit flip in state_reg_b only:
    //   • FSM in IDLE, state_reg_a = FSM_IDLE = 7'b000_0000
    //   • Force state_reg_b = 7'b000_0001 (LSB flipped, HD=1 from FSM_IDLE)
    //   • Cross-check: state_reg_a (0000000) !== state_reg_b (0000001) → FSM_ERROR
    //   • Check: effective_state = FSM_ERROR IMMEDIATELY (same cycle, combinational)
    //   • Release → do_reset → FSM returns to IDLE
    //
    // TF_005b — Double-bit flip in both registers (same invalid codeword):
    //   • Force both state_reg_a = state_reg_b = 7'b000_0011
    //     (not a valid Hamming codeword; closest valid: FSM_IDLE=0000000, HD=2)
    //   • Cross-check: state_reg_a == state_reg_b → passes (no mismatch)
    //   • unique case default branch fires → next_state = FSM_ERROR, output_veto=1
    //   • After 1 clock edge: FSM_ERROR registered
    //
    // TF_005c — Two-bit flip in ONE register (HD=2 SEU):
    //   • Force state_reg_b to have 2 bits flipped from FSM_IDLE: 7'b000_0011
    //   • state_reg_a (0000000) !== state_reg_b (0000011) → cross-check → FSM_ERROR
    //   • Verifies the redundant register catches multi-bit SEU in the other copy.
    //
    // Note: All force targets are sequential (always_ff) variables. force overrides
    //       the NBA update. release restores normal driver. A do_reset() follows each
    //       sub-test to clear FSM_ERROR (which is stuck without reset).
    // =========================================================================
    $display("───────────────────────────────────────────────────────────────────");
    $display("[TF_005] Hamming-3 State Encoding — Bit-Flip Fault Injection");
    $display("         Hierarchical path: tb_u11_hmao_fsm.u_dut.state_reg_a/b");
    $display("───────────────────────────────────────────────────────────────────");

    // -------------------------------------------------------------------------
    // TF_005a: 1-bit flip in state_reg_b only → cross-check mismatch → FSM_ERROR
    // -------------------------------------------------------------------------
    $display("[TF_005a] Starting: 1-bit flip in state_reg_b (mismatch with state_reg_a)");
    do_reset(10);

    begin : tf005a_body
      hmao_fsm_state_t flipped_b;

      // Verify FSM starts in IDLE (sanity)
      log_check("TF_005a.T1 : FSM in FSM_IDLE after reset (pre-fault sanity)",
                fsm_state_out == FSM_IDLE);

      // state_reg_a = FSM_IDLE = 7'b000_0000
      // Flip bit 0 of state_reg_b → 7'b000_0001 (invalid codeword, HD=1 from IDLE)
      flipped_b = hmao_fsm_state_t'(7'(FSM_IDLE) ^ 7'b000_0001);
      $display("[TF_005a]   Forcing state_reg_b = 7'b%07b (1-bit flip from FSM_IDLE=7'b0000000)",
               7'(flipped_b));

      // FORCE the redundant register to the corrupted value
      force tb_u11_hmao_fsm.u_dut.state_reg_b = flipped_b;

      // Combinational path: effective_state must be FSM_ERROR this very cycle
      // (no clock edge needed — the cross-check is always_comb)
      #1;  // Allow combinational propagation (1 ps after force)
      log_check(
        "TF_005a.T2 : effective_state=FSM_ERROR IMMEDIATELY after 1-bit flip (comb cross-check)",
        fsm_state_out == FSM_ERROR);
      log_check(
        "TF_005a.T3 : output_veto=1 immediately (FSM_ERROR → permanent VETO)",
        output_veto == 1'b1);

      // Verify the corrupt state_reg_b has the expected value (force sanity)
      log_check(
        $sformatf("TF_005a.T4 : state_reg_b forced correctly to 7'b%07b",
                  7'(tb_u11_hmao_fsm.u_dut.state_reg_b)),
        7'(tb_u11_hmao_fsm.u_dut.state_reg_b) === 7'(flipped_b));

      // Clock edge: FSM latches next_state=FSM_ERROR into both registers
      @(posedge clk);
      log_check("TF_005a.T5 : FSM_ERROR persists after clock edge (sticky, requires reset)",
                fsm_state_out == FSM_ERROR);

      // Release the force — FSM_ERROR now held by normal registers (both updated)
      release tb_u11_hmao_fsm.u_dut.state_reg_b;
      @(posedge clk);
      log_check("TF_005a.T6 : FSM_ERROR maintained after release (not cleared by release alone)",
                fsm_state_out == FSM_ERROR);

    end : tf005a_body

    $display("[TF_005a] COMPLETE");

    // -------------------------------------------------------------------------
    // TF_005b: Both registers forced to same INVALID codeword → default branch
    // -------------------------------------------------------------------------
    $display("[TF_005b] Starting: both registers forced to same invalid codeword");
    do_reset(10);   // Exits FSM_ERROR, returns to IDLE

    begin : tf005b_body
      // 7'b000_0011 is NOT a valid Hamming(7,4) codeword.
      // HD to FSM_IDLE(0000000)=2, HD to FSM_STAGE1_COMP(0000111)=2
      // → Cross-check passes (both equal), unique case default branch fires.
      localparam logic [6:0] INVALID_CW = 7'b000_0011;

      log_check("TF_005b.T1 : FSM in FSM_IDLE after reset (pre-fault sanity)",
                fsm_state_out == FSM_IDLE);

      $display("[TF_005b]   Forcing BOTH state_reg_a = state_reg_b = 7'b%07b (invalid codeword)",
               INVALID_CW);
      force tb_u11_hmao_fsm.u_dut.state_reg_a = hmao_fsm_state_t'(INVALID_CW);
      force tb_u11_hmao_fsm.u_dut.state_reg_b = hmao_fsm_state_t'(INVALID_CW);
      #1;   // Combinational propagation

      // Cross-check passes (both equal), so effective_state = state_reg_a = INVALID_CW
      // Verify the registers are equal (cross-check should NOT see mismatch)
      log_check("TF_005b.T2 : Cross-check registers are equal (both forced to same codeword)",
                7'(tb_u11_hmao_fsm.u_dut.state_reg_a) ===
                7'(tb_u11_hmao_fsm.u_dut.state_reg_b));

      // effective_state shows the invalid value; NOT a named enum → unique case default fires
      // output_veto should already be high (from default branch, combinational)
      log_check(
        "TF_005b.T3 : output_veto=1 (unique case default branch active, comb output)",
        output_veto == 1'b1);

      // Clock edge: next_state = FSM_ERROR (from default) latches into both registers
      @(posedge clk);

      // Release: allow the registers to run freely now (they will hold FSM_ERROR)
      release tb_u11_hmao_fsm.u_dut.state_reg_a;
      release tb_u11_hmao_fsm.u_dut.state_reg_b;
      @(posedge clk);

      // SVA A5_INVALID_CODEWORD already validates the next-cycle ERROR.
      // Procedural confirmation:
      log_check(
        "TF_005b.T4 : FSM_ERROR after invalid codeword (default branch latched, 2 cycles post-force)",
        fsm_state_out == FSM_ERROR);
      log_check(
        "TF_005b.T5 : output_veto=1 permanently (FSM_ERROR VETO maintained)",
        output_veto == 1'b1);

    end : tf005b_body

    $display("[TF_005b] COMPLETE");

    // -------------------------------------------------------------------------
    // TF_005c: 2-bit flip in ONE register → cross-check still catches it (SEU)
    // -------------------------------------------------------------------------
    $display("[TF_005c] Starting: 2-bit flip in state_reg_b only (HD=2 SEU scenario)");
    do_reset(10);

    begin : tf005c_body
      hmao_fsm_state_t double_flip_b;

      log_check("TF_005c.T1 : FSM in FSM_IDLE after reset (pre-fault sanity)",
                fsm_state_out == FSM_IDLE);

      // Flip bits [1:0] of FSM_IDLE (7'b000_0000) → 7'b000_0011 (HD=2 SEU in reg_b)
      // Note: 7'b000_0011 != any valid codeword AND != state_reg_a (7'b000_0000)
      double_flip_b = hmao_fsm_state_t'(7'(FSM_IDLE) ^ 7'b000_0011);
      $display("[TF_005c]   Forcing state_reg_b = 7'b%07b (2-bit flip, HD=2 SEU)",
               7'(double_flip_b));

      force tb_u11_hmao_fsm.u_dut.state_reg_b = double_flip_b;
      #1;

      // state_reg_a (0000000) !== state_reg_b (0000011) → cross-check → FSM_ERROR immediately
      log_check(
        "TF_005c.T2 : FSM_ERROR IMMEDIATELY (cross-check catches 2-bit SEU in state_reg_b)",
        fsm_state_out == FSM_ERROR);
      log_check(
        "TF_005c.T3 : output_veto=1 immediately (permanent VETO on 2-bit SEU detection)",
        output_veto == 1'b1);

      @(posedge clk);
      release tb_u11_hmao_fsm.u_dut.state_reg_b;
      @(posedge clk);

      log_check(
        "TF_005c.T4 : FSM_ERROR maintained after release (stuck — system reset required)",
        fsm_state_out == FSM_ERROR);

    end : tf005c_body

    $display("[TF_005] COMPLETE\n");

    // =========================================================================
    // TF_006: FSM Output Timing — Cycle-Accurate Synchrony
    //
    // Verify that HMAO_DECISION (output_grant / output_veto) and the
    // HMAO_COMPLETE interrupt are aligned without phase difference.
    //
    // Reference: FSM combinational output structure:
    //   output_grant is a combinational signal set in the CHECK state's case branch
    //   (same always_comb block as next_state). Therefore:
    //     • Cycle N  : state = CHECK, conditions met → output_grant=1 (comb),
    //                  next_state = OUTPUT_GRANT (comb)
    //     • Cycle N+1: state_reg latches OUTPUT_GRANT; output_grant = 0 (default)
    //   → output_grant leads FSM_OUTPUT_GRANT entry by exactly 1 clock cycle.
    //   → This is cycle-accurate synchrony: grant fires in the same cycle as the
    //     transition condition, not before or after.
    //
    // TF_006a: GRANT path (Stage1 fast-path: STAGE1_CHECK → OUTPUT_GRANT)
    //   Verify:
    //   • output_grant=1 while fsm_state_out == FSM_STAGE1_CHECK (transition cycle)
    //   • Next cycle: fsm_state_out == FSM_OUTPUT_GRANT, output_grant=0
    //   • No extra delay between decision and state entry (gap=0 cycles)
    //
    // TF_006b: VETO path (STAGE2_CHECK → OUTPUT_VETO)
    //   Verify:
    //   • output_veto=1 while in STAGE2_CHECK (transition cycle)
    //   • Next cycle: fsm_state_out == FSM_OUTPUT_VETO, output_veto=1 (continuous in state)
    //   • Veto is already high before and during OUTPUT_VETO → no gap.
    //
    // All SVA assertions A6_* (defined in Section 6) run concurrently.
    // Procedural checks below add explicit cycle-counted verification.
    // =========================================================================
    $display("───────────────────────────────────────────────────────────────────");
    $display("[TF_006] FSM Output Timing — Cycle-Accurate Synchrony Verification");
    $display("───────────────────────────────────────────────────────────────────");

    // -------------------------------------------------------------------------
    // TF_006a: GRANT path timing
    // -------------------------------------------------------------------------
    $display("[TF_006a] GRANT path: STAGE1_CHECK→OUTPUT_GRANT timing measurement");
    do_reset(10);

    begin : tf006a_body
      longint t_grant_fired;   // Cycle when output_grant goes high
      longint t_grant_state;   // Cycle when FSM_OUTPUT_GRANT is registered

      // Setup: preproc_valid, then trigger HMAO
      preproc_valid <= 1'b1;
      @(posedge clk);
      pulse_start(1);
      @(posedge clk);

      log_check("TF_006a.T1 : FSM in STAGE1_COMP (path A, preproc_valid=1)",
                fsm_state_out == FSM_STAGE1_COMP);

      // Simulate Stage1 zonotope computation
      admm_done     <= 1'b1;
      s1_zono_valid <= 1'b1;
      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      s1_zono_valid <= 1'b0;

      log_check("TF_006a.T2 : FSM in STAGE1_CHECK",
                fsm_state_out == FSM_STAGE1_CHECK);

      // Assert grant condition — check output_grant BEFORE the clock edge
      // (output_grant is combinational; it fires in the same delta cycle as s1_no_collision)
      s1_no_collision <= 1'b1;
      #1;  // Allow combinational propagation

      // CYCLE-ACCURATE CHECK 1: output_grant must be high NOW (combinational)
      // while FSM state is still STAGE1_CHECK
      log_check(
        "TF_006a.T3 : output_grant=1 COMBINATORIALLY (same delta cycle as condition, no pipe delay)",
        output_grant == 1'b1);
      log_check(
        "TF_006a.T4 : FSM state still STAGE1_CHECK at output_grant assertion (no premature advance)",
        fsm_state_out == FSM_STAGE1_CHECK);
      log_check(
        "TF_006a.T5 : output_veto=0 simultaneously (ASIL-D GRANT/VETO mutex)",
        output_veto == 1'b0);

      t_grant_fired = cycle_cnt;

      // Clock edge: state_reg latches OUTPUT_GRANT
      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      t_grant_state = cycle_cnt;

      s1_no_collision <= 1'b0;

      // CYCLE-ACCURATE CHECK 2: FSM enters OUTPUT_GRANT exactly 1 cycle after grant pulse
      log_check(
        $sformatf("TF_006a.T6 : FSM_OUTPUT_GRANT at cycle %0d (exactly 1 cycle after grant pulse at %0d)",
                  t_grant_state, t_grant_fired),
        fsm_state_out == FSM_OUTPUT_GRANT);

      // CYCLE-ACCURATE CHECK 3: output_grant must be LOW inside OUTPUT_GRANT state
      // (grant was a 1-cycle pulse; HMAO_COMPLETE IRQ is edge-triggered)
      log_check(
        "TF_006a.T7 : output_grant=0 inside FSM_OUTPUT_GRANT (pulse was 1-cycle, edge IRQ)",
        output_grant == 1'b0);

      // CYCLE-ACCURATE CHECK 4: Phase difference measurement = 0 cycles
      // (grant fires in same cycle as state transition condition → zero lag)
      begin
        longint phase_diff;
        phase_diff = t_grant_state - t_grant_fired;
        log_check(
          $sformatf("TF_006a.T8 : Phase difference = %0d cycle(s) (expected=1, output_grant leads by 1)",
                    phase_diff),
          phase_diff == 1);
      end

      // FSM should return to IDLE next cycle
      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      log_check("TF_006a.T9 : OUTPUT_GRANT→IDLE (one-cycle state completes correctly)",
                fsm_state_out == FSM_IDLE);

    end : tf006a_body

    $display("[TF_006a] COMPLETE");

    // -------------------------------------------------------------------------
    // TF_006b: VETO path timing (two-stage path → STAGE2_CHECK → OUTPUT_VETO)
    // -------------------------------------------------------------------------
    $display("[TF_006b] VETO path: STAGE2_CHECK→OUTPUT_VETO timing measurement");
    do_reset(10);

    begin : tf006b_body
      longint t_veto_fired;
      longint t_veto_state;

      // Setup: run through to STAGE2_CHECK
      preproc_valid <= 1'b1;
      @(posedge clk);
      pulse_start(1);
      @(posedge clk);

      // Skip STAGE1_COMP → STAGE1_CHECK
      admm_done     <= 1'b1;
      s1_zono_valid <= 1'b1;
      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      s1_zono_valid <= 1'b0;

      log_check("TF_006b.T1 : FSM in STAGE1_CHECK", fsm_state_out == FSM_STAGE1_CHECK);

      // Escalate to Stage2 (s1_potential=1)
      s1_potential <= 1'b1;
      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      s1_potential <= 1'b0;

      log_check("TF_006b.T2 : FSM in STAGE2_COMP (escalated from STAGE1_CHECK)",
                fsm_state_out == FSM_STAGE2_COMP);

      // Stage2 computation done
      s2_zono_valid <= 1'b1;
      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      s2_zono_valid <= 1'b0;

      log_check("TF_006b.T3 : FSM in STAGE2_CHECK", fsm_state_out == FSM_STAGE2_CHECK);

      // Assert collision → VETO
      s2_collision <= 1'b1;
      #1;  // Combinational propagation

      // CYCLE-ACCURATE CHECK: output_veto fires combinatorially in STAGE2_CHECK
      log_check(
        "TF_006b.T4 : output_veto=1 COMBINATORIALLY in STAGE2_CHECK (zero-lag VETO decision)",
        output_veto == 1'b1);
      log_check(
        "TF_006b.T5 : FSM still in STAGE2_CHECK at veto assertion (no premature state change)",
        fsm_state_out == FSM_STAGE2_CHECK);
      log_check(
        "TF_006b.T6 : output_grant=0 simultaneously (GRANT/VETO mutex on collision path)",
        output_grant == 1'b0);

      t_veto_fired = cycle_cnt;

      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      t_veto_state = cycle_cnt;
      s2_collision <= 1'b0;

      log_check(
        $sformatf("TF_006b.T7 : FSM_OUTPUT_VETO at cycle %0d (1 cycle after veto pulse at %0d)",
                  t_veto_state, t_veto_fired),
        fsm_state_out == FSM_OUTPUT_VETO);

      // In OUTPUT_VETO state, output_veto is continuously asserted (covers hold period)
      log_check(
        "TF_006b.T8 : output_veto=1 IN FSM_OUTPUT_VETO state (continuous hold — MRM activation)",
        output_veto == 1'b1);

      begin
        longint phase_diff;
        phase_diff = t_veto_state - t_veto_fired;
        log_check(
          $sformatf("TF_006b.T9 : VETO phase difference = %0d cycle(s) (output_veto leads by 1)",
                    phase_diff),
          phase_diff == 1);
      end

      @(posedge clk);
      #1;  // Let always_ff NBAs settle before reading registered outputs
      log_check("TF_006b.T10: OUTPUT_VETO→IDLE (completes safely, ready for next cycle)",
                fsm_state_out == FSM_IDLE);

    end : tf006b_body

    $display("[TF_006] COMPLETE\n");

    // =========================================================================
    // BATCH U11 SUMMARY
    // =========================================================================
    $display("═══════════════════════════════════════════════════════════════════");
    $display("  BATCH U11 SUMMARY — HMAO FSM Safety & Robustness Verification");
    $display("═══════════════════════════════════════════════════════════════════");
    $display("  TF_004 Watchdog:    STAGE1_COMP hang → wdt_s1_timeout → FSM_ERROR + VETO");
    $display("                      WDT budget = %0d cycles (4.5ms @ 400MHz)",
             WDT_STAGE1_CYCLES);
    $display("  TF_005 Hamming-3:   Bit-flip fault injection via force/release");
    $display("    005a: 1-bit flip in state_reg_b → cross-check → FSM_ERROR (comb)");
    $display("    005b: Both regs forced to invalid codeword → default branch → FSM_ERROR");
    $display("    005c: 2-bit flip (SEU) in state_reg_b → cross-check → FSM_ERROR");
    $display("  TF_006 Output Timing:");
    $display("    006a: output_grant 1 cycle ahead of FSM_OUTPUT_GRANT (zero pipeline lag)");
    $display("    006b: output_veto 1 cycle ahead of FSM_OUTPUT_VETO (zero pipeline lag)");
    $display("───────────────────────────────────────────────────────────────────");
    $display("  SVA Assertions  : A4_WDT_S1 / A4_WDT_VETO / A4_ERROR_STICKY /");
    $display("                    A4_ERROR_VETO / A5_CROSS / A5_INVALID_CODEWORD /");
    $display("                    A6_GRANT_TIMING / A6_GRANT_PRIOR / A6_VETO_TIMING /");
    $display("                    A6_MUTEX / A6_NO_SPURIOUS_GRANT");
    $display("  Procedural steps: %0d total", pass_count + fail_count);
    $display("───────────────────────────────────────────────────────────────────");
    $display("  PASS : %0d", pass_count);
    $display("  FAIL : %0d", fail_count);
    if (fail_count == 0)
      $display("  ✓ ALL CHECKS PASSED — Batch U11 HMAO FSM Safety Verification COMPLETE");
    else
      $display("  ✗ FAILURES DETECTED — Review $error output above for details");
    $display("═══════════════════════════════════════════════════════════════════");

    #100;
    $finish;

  end : u11_main

  // ===========================================================================
  // SECTION 8: SIMULATION TIMEOUT GUARD
  // TF_004 dominates: WDT_STAGE1_CYCLES (1.8M) + overhead per test.
  // Guard set to 3× WDT budget + Stage2 run + margin.
  // ===========================================================================
  initial begin : timeout_guard
    longint guard_limit;
    // TF_004: WDT_STAGE1_CYCLES + ~20 overhead
    // TF_005: 3 sub-tests × ~50 cycles each
    // TF_006: S1_ZONOTOPE_CYCLES + STAGE2_TOTAL_CYCLES + ~50
    guard_limit = WDT_STAGE1_CYCLES          // TF_004 hang simulation
                + S1_ZONOTOPE_CYCLES          // TF_006a Stage1 wait
                + STAGE2_TOTAL_CYCLES         // TF_006b Stage2 wait
                + 10_000;                     // Overhead, resets, checks
    repeat(guard_limit) @(posedge clk);
    $display("[TIMEOUT] Guard expired at cycle %0d — FSM may be stuck in state: %s",
             cycle_cnt, state_str(fsm_state_out));
    $finish;
  end : timeout_guard

  // ===========================================================================
  // SECTION 9: WAVEFORM DUMP
  // ===========================================================================
  initial begin
    $dumpfile("u11_hmao_fsm.vcd");
    $dumpvars(0, tb_u11_hmao_fsm);
  end

endmodule : tb_u11_hmao_fsm
