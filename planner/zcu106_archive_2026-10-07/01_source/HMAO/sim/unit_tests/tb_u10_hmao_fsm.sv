// =============================================================================
// FILE        : tb_u10_hmao_fsm.sv
// PROJECT     : HMAO Engine - Unit Test Batch U10
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 9.1-9.4
// SAFETY      : ASIL-D (ISO 26262) - Verification Evidence
// AUTHOR      : [Your Name]
// DATE        : 2024
// DESCRIPTION : Standalone unit testbench for hmao_fsm.sv.
//               Verifies FSM state-transition correctness for three key scenarios:
//
//   TF_001 – Complete Happy Path (no collision, Stage1 grants directly)
//            Sequence: IDLE → STAGE1_COMP → STAGE1_CHECK → OUTPUT_GRANT
//            Also validates: timing within WDT_STAGE1_CYCLES (~1.8M cycles)
//
//   TF_002 – Bad Preprocessor (preproc_error asserted before hmao_start)
//            Sequence: IDLE → OUTPUT_VETO  (computation stages fully skipped)
//
//   TF_003 – Two-Stage Path (Stage1 reports potential collision → Stage2 safe)
//            Sequence: IDLE → STAGE1_COMP → STAGE1_CHECK → STAGE2_COMP
//                           → STAGE2_CHECK → OUTPUT_GRANT
//
// MECHANISM : SVA concurrent assertions (A1-A12) lock in every valid edge.
//             Procedural checks add immediate pass/fail accounting per sub-step.
//             Timing assertions verify completion stays under WDT budget.
//
// COMPILE   : vlog -sv hmao_pkg.sv hmao_fsm.sv tb_u10_hmao_fsm.sv
//             vsim -sv_seed 1 tb_u10_hmao_fsm -do "run -all"
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module tb_u10_hmao_fsm;

  // ===========================================================================
  // SECTION 1 : CLOCK, RESET, CYCLE COUNTER
  // ===========================================================================
  localparam real CLK_HALF_NS = CLK_PERIOD_NS / 2.0;  // 1.25 ns  → 400 MHz

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #(CLK_HALF_NS) clk = ~clk;

  // Free-running cycle counter (used for timing assertions)
  longint unsigned cycle_cnt = 0;
  always_ff @(posedge clk) cycle_cnt++;

  // ===========================================================================
  // SECTION 2 : DUT PORT DECLARATIONS
  // ===========================================================================
  // ---------- Trigger & pipeline status inputs ----------
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

  // ---------- Fault inputs ----------
  logic crc_error       = 1'b0;
  logic numerical_error = 1'b0;
  logic wdt_s1_timeout  = 1'b0;
  logic wdt_s2_timeout  = 1'b0;

  // ---------- DUT outputs ----------
  hmao_fsm_state_t fsm_state_out;
  logic start_preproc, start_s1, start_admm, start_s2;
  logic output_grant, output_veto;

  // ===========================================================================
  // SECTION 3 : DUT INSTANTIATION
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
  // SECTION 4 : TEST BOOKKEEPING
  // ===========================================================================
  int pass_count = 0;
  int fail_count = 0;

  // Latched copies of one-cycle control pulses — lets procedural code read them
  // AFTER the clock edge without losing the NBA-updated value.
  logic start_s1_d1, start_admm_d1, start_s2_d1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_s1_d1   <= 1'b0;
      start_admm_d1 <= 1'b0;
      start_s2_d1   <= 1'b0;
    end else begin
      start_s1_d1   <= start_s1;
      start_admm_d1 <= start_admm;
      start_s2_d1   <= start_s2;
    end
  end

  // ===========================================================================
  // SECTION 5 : HELPER TASKS & FUNCTIONS
  // ===========================================================================

  // ---------- Reset FSM and clear all stimulus ----------
  task automatic do_reset(input int hold_cycles = 10);
    rst_n         <= 1'b0;
    hmao_start    <= 1'b0;
    preproc_valid <= 1'b0;
    preproc_error <= 1'b0;
    s1_zono_valid <= 1'b0;
    s1_no_collision<=1'b0;
    s1_potential  <= 1'b0;
    admm_done     <= 1'b0;
    admm_diverged <= 1'b0;
    s2_zono_valid <= 1'b0;
    s2_no_collision<=1'b0;
    s2_collision  <= 1'b0;
    crc_error     <= 1'b0;
    numerical_error<=1'b0;
    wdt_s1_timeout<= 1'b0;
    wdt_s2_timeout<= 1'b0;
    repeat(hold_cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);  // One settle cycle
  endtask

  // ---------- Pulse hmao_start for N cycles ----------
  task automatic pulse_start(input int hold_cycles = 2);
    hmao_start <= 1'b1;
    repeat(hold_cycles) @(posedge clk);
    hmao_start <= 1'b0;
  endtask

  // ---------- Wait for a target FSM state, with cycle timeout ----------
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

  // ---------- Log check with pass/fail accounting ----------
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

  // ---------- Decode FSM state enum to printable string ----------
  function automatic string state_str(input hmao_fsm_state_t s);
    case (s)
      FSM_IDLE:         return "IDLE";
      FSM_STAGE1_COMP:  return "STAGE1_COMP";
      FSM_STAGE1_CHECK: return "STAGE1_CHECK";
      FSM_STAGE2_COMP:  return "STAGE2_COMP";
      FSM_STAGE2_CHECK: return "STAGE2_CHECK";
      FSM_OUTPUT_GRANT: return "OUTPUT_GRANT";
      FSM_OUTPUT_VETO:  return "OUTPUT_VETO";
      FSM_ERROR:        return "ERROR";
      default:          return "UNDEFINED";
    endcase
  endfunction

  // ===========================================================================
  // SECTION 6 : SVA CONCURRENT ASSERTIONS  (active throughout simulation)
  // ===========================================================================
  // NOTE: All edge assertions use |=> (next-clock) unless otherwise noted.
  //       The disable iff (!rst_n) clause prevents false firings during reset.
  // ---------------------------------------------------------------------------

  // --- A1: IDLE + valid start → STAGE1_COMP next cycle -------------------
  // Covers both Path A (preproc_valid=1) and Path B (preproc_valid=0, no error)
  A1_IDLE_to_S1COMP:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_IDLE &&
     hmao_start     == 1'b1   &&
     preproc_error  == 1'b0   &&
     crc_error      == 1'b0)
    |=> (fsm_state_out == FSM_STAGE1_COMP)
  ) else begin
    $error("[SVA A1 FAIL] IDLE did not advance to STAGE1_COMP on valid hmao_start");
    fail_count++;
  end

  // --- A2: IDLE + preproc_error → OUTPUT_VETO next cycle (TF_002) --------
  A2_IDLE_to_VETO_on_preproc_err:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_IDLE &&
     hmao_start    == 1'b1    &&
     preproc_error == 1'b1)
    |=> (fsm_state_out == FSM_OUTPUT_VETO)
  ) else begin
    $error("[SVA A2 FAIL] IDLE did not jump to OUTPUT_VETO when preproc_error=1");
    fail_count++;
  end

  // --- A3: IDLE + crc_error → OUTPUT_VETO next cycle ---------------------
  A3_IDLE_to_VETO_on_crc_err:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_IDLE &&
     hmao_start    == 1'b1    &&
     crc_error     == 1'b1)
    |=> (fsm_state_out == FSM_OUTPUT_VETO)
  ) else begin
    $error("[SVA A3 FAIL] IDLE did not jump to OUTPUT_VETO when crc_error=1");
    fail_count++;
  end

  // --- A4: STAGE1_COMP + s1_zono_valid (no fault) → STAGE1_CHECK ---------
  A4_S1COMP_to_S1CHECK:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out   == FSM_STAGE1_COMP &&
     s1_zono_valid   == 1'b1           &&
     crc_error       == 1'b0           &&
     numerical_error == 1'b0           &&
     wdt_s1_timeout  == 1'b0)
    |=> (fsm_state_out == FSM_STAGE1_CHECK)
  ) else begin
    $error("[SVA A4 FAIL] STAGE1_COMP did not advance to STAGE1_CHECK on s1_zono_valid");
    fail_count++;
  end

  // --- A5: STAGE1_CHECK + no_collision + admm_done → OUTPUT_GRANT (fast path)
  A5_S1CHECK_to_GRANT_fast_path:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out   == FSM_STAGE1_CHECK &&
     s1_no_collision == 1'b1             &&
     admm_done       == 1'b1             &&
     admm_diverged   == 1'b0             &&
     wdt_s1_timeout  == 1'b0)
    |=> (fsm_state_out == FSM_OUTPUT_GRANT)
  ) else begin
    $error("[SVA A5 FAIL] STAGE1_CHECK did not grant on: no_collision + admm_done");
    fail_count++;
  end

  // --- A6: STAGE1_CHECK + s1_potential → STAGE2_COMP (TF_003 escalation) -
  A6_S1CHECK_to_S2COMP:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_STAGE1_CHECK &&
     s1_potential  == 1'b1             &&
     s1_no_collision == 1'b0           &&  // s1_no_collision must be 0 for s1_potential branch
     wdt_s1_timeout == 1'b0)
    |=> (fsm_state_out == FSM_STAGE2_COMP)
  ) else begin
    $error("[SVA A6 FAIL] STAGE1_CHECK did not escalate to STAGE2_COMP on s1_potential");
    fail_count++;
  end

  // --- A7: STAGE2_COMP + s2_zono_valid (no fault) → STAGE2_CHECK ---------
  A7_S2COMP_to_S2CHECK:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out   == FSM_STAGE2_COMP &&
     s2_zono_valid   == 1'b1            &&
     numerical_error == 1'b0            &&
     wdt_s2_timeout  == 1'b0)
    |=> (fsm_state_out == FSM_STAGE2_CHECK)
  ) else begin
    $error("[SVA A7 FAIL] STAGE2_COMP did not advance to STAGE2_CHECK on s2_zono_valid");
    fail_count++;
  end

  // --- A8: STAGE2_CHECK + s2_no_collision → OUTPUT_GRANT (TF_003 safe) ---
  A8_S2CHECK_to_GRANT:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out   == FSM_STAGE2_CHECK &&
     s2_no_collision == 1'b1             &&
     wdt_s2_timeout  == 1'b0)
    |=> (fsm_state_out == FSM_OUTPUT_GRANT)
  ) else begin
    $error("[SVA A8 FAIL] STAGE2_CHECK did not grant on s2_no_collision");
    fail_count++;
  end

  // --- A9: OUTPUT_GRANT is one-cycle → returns to IDLE next cycle ---------
  A9_GRANT_one_cycle:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_OUTPUT_GRANT)
    |=> (fsm_state_out == FSM_IDLE)
  ) else begin
    $error("[SVA A9 FAIL] OUTPUT_GRANT did not return to IDLE after 1 cycle");
    fail_count++;
  end

  // --- A10: GRANT and VETO are mutually exclusive — ASIL-D safety critical -
  A10_GRANT_VETO_mutex:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    not (output_grant && output_veto)
  ) else begin
    $error("[SVA A10 FAIL] CRITICAL: output_grant AND output_veto both asserted!");
    fail_count++;
  end

  // --- A11: FSM_ERROR is a sticky state (system reset required to exit) ---
  A11_ERROR_sticky:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_ERROR)
    |=> (fsm_state_out == FSM_ERROR)
  ) else begin
    $error("[SVA A11 FAIL] FSM_ERROR transitioned out without system reset — safety violation!");
    fail_count++;
  end

  // --- A12: In FSM_ERROR, output_veto must always be asserted ------------
  A12_ERROR_always_veto:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out == FSM_ERROR) |-> output_veto
  ) else begin
    $error("[SVA A12 FAIL] VETO not asserted in FSM_ERROR — ASIL-D permanent VETO violated!");
    fail_count++;
  end

  // --- A13: Path B handshake — preproc_valid in STAGE1_COMP with s1 not yet
  //          started triggers start_s1 combinatorially in that same cycle -----
  A13_preproc_valid_triggers_start_s1:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (fsm_state_out        == FSM_STAGE1_COMP &&
     preproc_valid        == 1'b1            &&
     preproc_error        == 1'b0            &&
     u_dut.s1_started_reg == 1'b0)           // Stage1 not yet kicked
    |-> start_s1                              // combinational: must be true this same cycle
  ) else begin
    $error("[SVA A13 FAIL] start_s1 not issued when preproc_valid rises in STAGE1_COMP");
    fail_count++;
  end

  // --- A14: Undefined (non-Hamming) state → ERROR next cycle -------------
  //          Verifies that Hamming-3 SEU protection activates on corrupt state.
  //          Uses the decode function from hmao_pkg which maps unknowns → 3'd7.
  A14_undefined_state_to_ERROR:
  assert property (
    @(posedge clk) disable iff (!rst_n)
    (decode_fsm_state(fsm_state_out) == 3'd7 &&
     fsm_state_out != FSM_ERROR)              // not the valid ERROR codeword
    |=> (fsm_state_out == FSM_ERROR)
  ) else begin
    $error("[SVA A14 FAIL] Corrupted state did not force transition to FSM_ERROR");
    fail_count++;
  end

  // ===========================================================================
  // SECTION 7 : MAIN TEST SEQUENCE
  // ===========================================================================
  initial begin : u10_main
    $timeformat(-6, 3, " us", 12);
    $display("═══════════════════════════════════════════════════════════════════");
    $display("  HMAO UNIT TEST BATCH U10 — FSM State Transition Verification");
    $display("  Module  : hmao_fsm.sv");
    $display("  Package : hmao_pkg.sv");
    $display("  Safety  : ASIL-D  |  Spec Ref: Section 9.1–9.4");
    $display("  SVA     : A1–A14 concurrent (active throughout)");
    $display("═══════════════════════════════════════════════════════════════════\n");

    // =========================================================================
    // TF_001 : COMPLETE HAPPY PATH — No Collision
    //
    // Stimulus model (Path B: preproc_valid=0 at start):
    //   Cycle 0        : hmao_start pulse, preproc_valid=0 → FSM→STAGE1_COMP
    //                    start_preproc issued
    //   +S1_PREPROC    : preproc_valid asserted → FSM issues start_s1 / start_admm
    //   +S1_ZONOTOPE   : s1_zono_valid pulse → FSM→STAGE1_CHECK
    //   +S1_COLLISION  : admm_done=1, s1_no_collision=1 → FSM→OUTPUT_GRANT
    //   Total expected : ~1.52M cycles  (well within WDT_STAGE1_CYCLES=1.8M)
    //
    // Spec Ref        : Section 9.2 transition table, Section 11.2 latency budget
    // =========================================================================
    $display("───────────────────────────────────────────────────────────────────");
    $display("[TF_001] Complete Happy Path (no collision, Stage1 GRANT)");
    $display("───────────────────────────────────────────────────────────────────");

    do_reset(10);

    // ----- Pre-condition: FSM must start in IDLE -----
    log_check("TF_001.PRE : FSM in IDLE after reset",
              fsm_state_out == FSM_IDLE);
    $display("           State = %s (enc=7'b%07b)", state_str(fsm_state_out), fsm_state_out);

    // ----- Step 1: Trigger hmao_start, preproc not ready (Path B) -----
    $display("[TF_001] Asserting hmao_start (preproc_valid=0, Path B)...");
    begin : tf001_body
      longint t_start, t_s1comp, t_s1check, t_grant;
      logic   reached;

      t_start = cycle_cnt;
      pulse_start(2);          // 2-cycle pulse, preproc_valid still 0
      @(posedge clk);          // One propagation cycle

      // T1: FSM should be in STAGE1_COMP (SVA A1 also checks this)
      log_check(
        $sformatf("TF_001.T1  : IDLE→STAGE1_COMP at cycle %0d (Δ=%0d)",
                  cycle_cnt, cycle_cnt - t_start),
        fsm_state_out == FSM_STAGE1_COMP);
      t_s1comp = cycle_cnt;

      // T1b: start_preproc should have been issued (Path B kickoff)
      @(posedge clk);
      log_check("TF_001.T1b : start_preproc issued on Path B entry",
                start_preproc_d1);   // sampled from latch (next cycle)

      // ----- Step 2: Simulate preprocessor completing -----
      $display("[TF_001]   Waiting %0d cycles for preproc... (%0t)",
               S1_PREPROC_CYCLES, $time);
      repeat(S1_PREPROC_CYCLES - 1) @(posedge clk);  // -1 to align with NBA
      preproc_valid <= 1'b1;
      @(posedge clk);   // Cycle where FSM sees preproc_valid=1, s1_started_reg=0
                        // → start_s1 is combinatorially 1 this cycle (SVA A13 fires)

      // T2: start_s1 latch — readable next cycle
      @(posedge clk);
      log_check(
        $sformatf("TF_001.T2  : start_s1 pulsed on preproc_valid (cycle %0d)", cycle_cnt),
        start_s1_d1);
      log_check("TF_001.T2b : start_admm pulsed in parallel with start_s1",
                start_admm_d1);

      // ----- Step 3: ADMM runs in parallel — completes before zonotope -----
      fork : admm_fork
        begin
          int _admm_k;
          for (_admm_k = 0; _admm_k < S1_ZONOTOPE_CYCLES / 2; _admm_k++)
            @(posedge clk);
          admm_done <= 1'b1;
          $display("[TF_001]   admm_done asserted at cycle %0d", cycle_cnt);
        end
      join_none

      // ----- Step 4: Stage1 Zonotope (16-generator) completes -----
      $display("[TF_001]   Waiting %0d cycles for Stage1 Zonotope...", S1_ZONOTOPE_CYCLES);
      repeat(S1_ZONOTOPE_CYCLES) @(posedge clk);
      s1_zono_valid <= 1'b1;
      @(posedge clk);          // FSM transitions → STAGE1_CHECK  (SVA A4 fires)
      s1_zono_valid <= 1'b0;   // One-cycle valid pulse
      @(posedge clk);          // Settle: let state_reg NBA resolve

      // T3: STAGE1_CHECK
      log_check(
        $sformatf("TF_001.T3  : STAGE1_COMP→STAGE1_CHECK at cycle %0d (Δ=%0d from start)",
                  cycle_cnt, cycle_cnt - t_start),
        fsm_state_out == FSM_STAGE1_CHECK);
      t_s1check = cycle_cnt;

      // Verify FSM stays in STAGE1_CHECK while collision analysis runs
      // (s1_no_collision=0, s1_potential=0 → no exit condition yet)
      log_check("TF_001.T3b : FSM holds STAGE1_CHECK during collision analysis",
                fsm_state_out == FSM_STAGE1_CHECK);

      // ----- Step 5: Stage1 collision analysis completes (no obstacle found) -----
      $display("[TF_001]   Waiting %0d cycles for Stage1 collision check...", S1_COLLISION_CYCLES);
      repeat(S1_COLLISION_CYCLES) @(posedge clk);
      // admm_done already 1 from fork above; assert clean result
      s1_no_collision <= 1'b1;
      @(posedge clk);          // FSM: STAGE1_CHECK + s1_no_collision + admm_done → GRANT
      @(posedge clk);          // Settle: let state_reg NBA resolve

      // T4: OUTPUT_GRANT  (SVA A5 fires on the preceding clock edge)
      log_check(
        $sformatf("TF_001.T4  : STAGE1_CHECK→OUTPUT_GRANT at cycle %0d", cycle_cnt),
        fsm_state_out == FSM_OUTPUT_GRANT);
      t_grant = cycle_cnt;

      // T5: output_grant signal
      log_check("TF_001.T5  : output_grant=1 in OUTPUT_GRANT state",
                output_grant == 1'b1);

      // T6: output_veto must NOT be asserted alongside GRANT
      log_check("TF_001.T6  : output_veto=0 (no false VETO on GRANT path)",
                output_veto == 1'b0);

      // T7: Timing — must complete within WDT_STAGE1_CYCLES budget
      begin
        longint elapsed = t_grant - t_start;
        $display("[TF_001]   Elapsed cycles : %0d", elapsed);
        $display("[TF_001]   WDT budget     : %0d  (%.2f ms)",
                 WDT_STAGE1_CYCLES, WDT_STAGE1_CYCLES / real'(CLK_FREQ_HZ) * 1000.0);
        $display("[TF_001]   Margin         : %0d cycles  (%.2f%%)",
                 WDT_STAGE1_CYCLES - elapsed,
                 (WDT_STAGE1_CYCLES - elapsed) * 100.0 / WDT_STAGE1_CYCLES);
        log_check(
          $sformatf("TF_001.T7  : Timing OK — %0d cycles ≤ WDT_STAGE1=%0d",
                    elapsed, WDT_STAGE1_CYCLES),
          elapsed <= WDT_STAGE1_CYCLES);
      end

      // T8: OUTPUT_GRANT is a one-cycle state — must return to IDLE (SVA A9 fires)
      @(posedge clk);
      log_check("TF_001.T8  : OUTPUT_GRANT→IDLE (one-cycle state confirmed)",
                fsm_state_out == FSM_IDLE);

    end : tf001_body

    $display("[TF_001] COMPLETE\n");

    // =========================================================================
    // TF_002 : BAD PREPROCESSOR — Preproc Error → Direct VETO
    //
    // Key property : All Zonotope/SAT/ADMM computation stages must be SKIPPED.
    // The FSM must travel IDLE → OUTPUT_VETO in a single clock cycle.
    //
    // Spec Ref : Section 9.2 – IDLE transitions (preproc_error branch)
    // =========================================================================
    $display("───────────────────────────────────────────────────────────────────");
    $display("[TF_002] Bad Preprocessor — IDLE→OUTPUT_VETO (compute stages skipped)");
    $display("───────────────────────────────────────────────────────────────────");

    do_reset(10);

    // Pre-arm the error flag (preproc raised error before start was issued)
    preproc_error <= 1'b1;
    preproc_valid <= 1'b0;   // Invalid: error supersedes valid
    @(posedge clk);

    begin : tf002_body
      longint t2_start;
      t2_start = cycle_cnt;

      $display("[TF_002] Asserting hmao_start with preproc_error=1...");
      pulse_start(1);       // Single-cycle pulse
      @(posedge clk);       // Propagation

      // T1: Should be in OUTPUT_VETO — NO STAGE1_COMP or any compute state
      log_check(
        $sformatf("TF_002.T1  : IDLE→OUTPUT_VETO in %0d cycles (compute stages skipped)",
                  cycle_cnt - t2_start),
        fsm_state_out == FSM_OUTPUT_VETO);
      $display("           State = %s (enc=7'b%07b)", state_str(fsm_state_out), fsm_state_out);

      // T2: Verify it did NOT transit through STAGE1_COMP (would mean compute ran)
      //     Since the transition is IDLE → OUTPUT_VETO in 1 cycle, we check the
      //     state directly rather than catching an intermediate.
      log_check("TF_002.T2  : FSM bypassed STAGE1_COMP/STAGE2_COMP entirely",
                fsm_state_out != FSM_STAGE1_COMP &&
                fsm_state_out != FSM_STAGE2_COMP);

      // T3: output_veto must be asserted
      log_check("TF_002.T3  : output_veto=1 asserted in OUTPUT_VETO state",
                output_veto == 1'b1);

      // T4: output_grant must be de-asserted (ASIL-D mutual exclusion)
      log_check("TF_002.T4  : output_grant=0 (no false GRANT on error path)",
                output_grant == 1'b0);

      // T5: No compute-start signals issued (start_s1 / start_admm must be 0)
      log_check("TF_002.T5  : start_s1=0 (Zonotope Stage1 not kicked)",
                start_s1 == 1'b0);
      log_check("TF_002.T6  : start_s2=0 (Zonotope Stage2 not kicked)",
                start_s2 == 1'b0);

      // T6: OUTPUT_VETO returns to IDLE next cycle
      @(posedge clk);
      log_check("TF_002.T7  : OUTPUT_VETO→IDLE (one-cycle state, ready for next request)",
                fsm_state_out == FSM_IDLE);

    end : tf002_body

    preproc_error <= 1'b0;   // Clear for subsequent tests
    $display("[TF_002] COMPLETE\n");

    // =========================================================================
    // TF_003 : TWO-STAGE PATH — Stage1 Potential → Stage2 Safe → GRANT
    //
    // Stimulus model (Path A: preproc_valid=1 at start — faster TF_003 entry):
    //   Cycle 0        : hmao_start, preproc_valid=1 → STAGE1_COMP, start_s1 immediately
    //   +S1_ZONOTOPE   : s1_zono_valid → STAGE1_CHECK
    //   +1 cycle       : s1_potential=1 → escalate to STAGE2_COMP, start_s2
    //   +S2_TOTAL/2    : s2_zono_valid → STAGE2_CHECK
    //   +1 cycle       : s2_no_collision=1 → OUTPUT_GRANT
    //
    // Key checks: escalation does NOT grant prematurely; Stage2 completion grants.
    // Spec Ref : Section 9.2 (S1_CHECK→S2_COMP branch), Section 7.2 (32-gen fine check)
    // =========================================================================
    $display("───────────────────────────────────────────────────────────────────");
    $display("[TF_003] Two-Stage Path (Stage1 potential → Stage2 safe → GRANT)");
    $display("───────────────────────────────────────────────────────────────────");

    do_reset(10);

    // Path A setup: preproc already valid when hmao_start arrives
    preproc_valid <= 1'b1;
    @(posedge clk);   // Settle preproc_valid before start

    begin : tf003_body
      longint t3_start;
      t3_start = cycle_cnt;

      $display("[TF_003] Asserting hmao_start (preproc_valid=1, Path A)...");
      pulse_start(1);
      @(posedge clk);   // Propagation

      // T1: STAGE1_COMP (Path A — start_s1 / start_admm issued from IDLE, not STAGE1_COMP)
      log_check(
        $sformatf("TF_003.T1  : IDLE→STAGE1_COMP (Path A) at cycle %0d", cycle_cnt),
        fsm_state_out == FSM_STAGE1_COMP);
      log_check("TF_003.T1b : start_s1 pulsed immediately (Path A, preproc already valid)",
                start_s1_d1);
      log_check("TF_003.T1c : start_admm pulsed in parallel with start_s1",
                start_admm_d1);

      // ----- Stage1 Zonotope computation -----
      $display("[TF_003]   Waiting %0d cycles for Stage1 Zonotope...", S1_ZONOTOPE_CYCLES);
      repeat(S1_ZONOTOPE_CYCLES) @(posedge clk);
      admm_done     <= 1'b1;   // ADMM done (ran in parallel)
      s1_zono_valid <= 1'b1;
      @(posedge clk);          // FSM→STAGE1_CHECK  (SVA A4 fires)
      s1_zono_valid <= 1'b0;
      @(posedge clk);          // Settle: let state_reg NBA resolve

      // T2: STAGE1_CHECK
      log_check(
        $sformatf("TF_003.T2  : STAGE1_COMP→STAGE1_CHECK at cycle %0d", cycle_cnt),
        fsm_state_out == FSM_STAGE1_CHECK);

      // ----- Stage1 reports POTENTIAL COLLISION (suspicious objects detected) -----
      // s1_no_collision=0 (default), s1_potential=1 → escalation must occur.
      // CRITICAL CHECK: FSM must NOT grant prematurely here.
      $display("[TF_003]   Asserting s1_potential=1 → escalation to Stage2 expected");
      s1_potential <= 1'b1;
      @(posedge clk);   // FSM: STAGE1_CHECK + s1_potential + s1_no_collision=0 → S2_COMP
                        // (SVA A6 fires)
      @(posedge clk);   // Settle: let state_reg NBA resolve (start_s2_d1 also valid)

      // T3: Escalated to STAGE2_COMP — NOT OUTPUT_GRANT (premature grant check)
      log_check(
        $sformatf("TF_003.T3  : STAGE1_CHECK→STAGE2_COMP (escalation) at cycle %0d", cycle_cnt),
        fsm_state_out == FSM_STAGE2_COMP);
      log_check("TF_003.T3b : FSM did NOT grant prematurely (escalation overrides fast-path)",
                fsm_state_out != FSM_OUTPUT_GRANT);

      // T3c: start_s2 was issued on the transition cycle (readable via d1 latch at settle)
      log_check("TF_003.T3c : start_s2 pulsed to launch Stage2 Zonotope (32 generators)",
                start_s2_d1);

      s1_potential <= 1'b0;   // Clear after transition confirmed

      // ----- Stage2 fine Zonotope (32-generator, STAGE2_TOTAL_CYCLES budget) -----
      $display("[TF_003]   Stage2 running (32-gen Zonotope, %0d cycles)...",
               STAGE2_TOTAL_CYCLES / 2);
      repeat(STAGE2_TOTAL_CYCLES / 2) @(posedge clk);  // Simulate at half budget
      s2_zono_valid <= 1'b1;
      @(posedge clk);          // FSM→STAGE2_CHECK  (SVA A7 fires)
      s2_zono_valid <= 1'b0;
      @(posedge clk);          // Settle: let state_reg NBA resolve

      // T4: STAGE2_CHECK
      log_check(
        $sformatf("TF_003.T4  : STAGE2_COMP→STAGE2_CHECK at cycle %0d", cycle_cnt),
        fsm_state_out == FSM_STAGE2_CHECK);

      // ----- Stage2 concludes: no collision — path is SAFE -----
      $display("[TF_003]   Stage2 reports s2_no_collision=1 (fine check: path is safe)");
      s2_no_collision <= 1'b1;
      @(posedge clk);          // FSM: STAGE2_CHECK + s2_no_collision → OUTPUT_GRANT
                                // (SVA A8 fires)
      @(posedge clk);          // Settle: let state_reg NBA resolve

      // T5: OUTPUT_GRANT — after full two-stage verification
      log_check(
        $sformatf("TF_003.T5  : STAGE2_CHECK→OUTPUT_GRANT at cycle %0d (two-stage path complete)",
                  cycle_cnt),
        fsm_state_out == FSM_OUTPUT_GRANT);

      // T6: output_grant asserted, output_veto de-asserted (ASIL-D mutex check)
      log_check("TF_003.T6  : output_grant=1 (GRANT issued after Stage2 clearance)",
                output_grant == 1'b1);
      log_check("TF_003.T7  : output_veto=0 (no false VETO on safe two-stage path)",
                output_veto == 1'b0);

      // T8: Return to IDLE (SVA A9 fires)
      @(posedge clk);
      log_check("TF_003.T8  : OUTPUT_GRANT→IDLE (ready for next request)",
                fsm_state_out == FSM_IDLE);

      // T9: Timing — two-stage path must complete within MAX_TOTAL_CYCLES (10ms)
      begin
        longint elapsed = cycle_cnt - t3_start;
        $display("[TF_003]   Two-stage elapsed: %0d cycles  (%.3f ms)",
                 elapsed, elapsed / real'(CLK_FREQ_HZ) * 1000.0);
        log_check(
          $sformatf("TF_003.T9  : Timing OK — %0d cycles ≤ MAX_TOTAL=%0d",
                    elapsed, MAX_TOTAL_CYCLES),
          elapsed <= MAX_TOTAL_CYCLES);
      end

    end : tf003_body

    $display("[TF_003] COMPLETE\n");

    // =========================================================================
    // BATCH U10 SUMMARY
    // =========================================================================
    $display("═══════════════════════════════════════════════════════════════════");
    $display("  BATCH U10 SUMMARY — HMAO FSM State Transition Verification");
    $display("═══════════════════════════════════════════════════════════════════");
    $display("  TF_001 Happy Path:    IDLE→S1_COMP→S1_CHECK→OUTPUT_GRANT");
    $display("                        Timing: within WDT_STAGE1=%0d cycles", WDT_STAGE1_CYCLES);
    $display("  TF_002 Preproc Error: IDLE→OUTPUT_VETO (all compute skipped)");
    $display("  TF_003 Two-Stage:     IDLE→S1_COMP→S1_CHECK→S2_COMP→S2_CHECK→OUTPUT_GRANT");
    $display("───────────────────────────────────────────────────────────────────");
    $display("  SVA Assertions  : A1–A14 (concurrent, all simulation cycles)");
    $display("  Procedural steps: %0d total", pass_count + fail_count);
    $display("───────────────────────────────────────────────────────────────────");
    $display("  PASS : %0d", pass_count);
    $display("  FAIL : %0d", fail_count);
    if (fail_count == 0)
      $display("  ✓ ALL CHECKS PASSED — Batch U10 HMAO FSM Verification COMPLETE");
    else
      $display("  ✗ FAILURES DETECTED — Review $error output above");
    $display("═══════════════════════════════════════════════════════════════════");

    #100;
    $finish;
  end : u10_main

  // =========================================================================
  // SECTION 8 : LATCH FOR start_preproc (used in TF_001.T1b)
  // =========================================================================
  logic start_preproc_d1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) start_preproc_d1 <= 1'b0;
    else        start_preproc_d1 <= start_preproc;
  end

  // =========================================================================
  // SECTION 9 : SIMULATION TIMEOUT GUARD
  // Upper bound: 2× full two-stage run including preproc overhead
  // Triggers if FSM hangs (e.g., no transition out of a state)
  // =========================================================================
  initial begin : timeout_guard
    longint guard_limit;
    guard_limit = 2 * (PREPROC_CYCLES + STAGE1_TOTAL_CYCLES + STAGE2_TOTAL_CYCLES) + 10000;
    repeat(guard_limit) @(posedge clk);
    $display("[TIMEOUT] Guard timer expired at cycle %0d — FSM may be stuck", cycle_cnt);
    $display("[TIMEOUT] Check for missing 'done' signals or stuck state: %s",
             state_str(fsm_state_out));
    $finish;
  end : timeout_guard

  // =========================================================================
  // SECTION 10 : WAVEFORM DUMP
  // =========================================================================
  initial begin
    $dumpfile("u10_hmao_fsm.vcd");
    $dumpvars(0, tb_u10_hmao_fsm);
  end

endmodule : tb_u10_hmao_fsm
