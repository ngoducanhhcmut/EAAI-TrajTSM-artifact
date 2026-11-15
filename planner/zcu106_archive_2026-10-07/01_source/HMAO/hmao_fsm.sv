// =============================================================================
// FILE        : hmao_fsm.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 9
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : Control FSM with Hamming Distance = 3 state encoding.
//               Any single or double bit-flip in state register → Undefined
//               state → watchdog block detects & resets safely.
//               Transition table: Section 9.2
//               SAFE DEFAULT = VETO (0=VETO is reset and error default)
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module hmao_fsm (
  input  logic            clk,
  input  logic            rst_n,

  // Trigger
  input  logic            hmao_start,

  // Pipeline status
  input  logic            preproc_valid,
  input  logic            preproc_error,
  input  logic            s1_zono_valid,
  input  logic            s1_no_collision,
  input  logic            s1_potential,
  input  logic            admm_done,
  input  logic            admm_diverged,
  input  logic            s2_zono_valid,
  input  logic            s2_no_collision,
  input  logic            s2_collision,

  // Fault/error inputs
  input  logic            crc_error,
  input  logic            numerical_error,
  input  logic            wdt_s1_timeout,
  input  logic            wdt_s2_timeout,

  // FSM state output
  output hmao_fsm_state_t fsm_state_out,

  // Control outputs (active for 1 cycle to start sub-module)
  output logic            start_preproc,
  output logic            start_s1,
  output logic            start_admm,
  output logic            start_s2,
  output logic            output_grant,
  output logic            output_veto
);

  // ===========================================================================
  // STATE REGISTERS (two redundant copies for ASIL-D)
  // ===========================================================================
  // [BUG-FIX FSM-001] Register merging defeated the SEU redundancy.
  //   Evidence (post-synth netlist, system_hmao_engine_0_2_sim_netlist.v):
  //     state_reg_a -> 6x FDCE cells present (state_reg_a_reg[0..5])
  //     state_reg_b -> ZERO occurrences, under ANY name variant
  //   Root cause chain: a and b are driven identically, so Vivado proves them
  //   logic-equivalent -> the (a !== b) comparator constant-folds to 0 -> the
  //   FSM_ERROR branch becomes dead logic -> state_reg_b loses its only
  //   consumer and is swept entirely. The SEU cross-check was silently a
  //   no-op on real silicon while looking correct in RTL and in simulation.
  //   dont_touch pins BOTH copies so the comparator keeps two distinct nets.
  //   MUST re-verify on the post-synth netlist after any re-synthesis --
  //   see docs/LuanVan_GiaiDoan2_BanThao_HoanChinh.md 3.3.1.
  (* dont_touch = "true" *) hmao_fsm_state_t state_reg_a;
  (* dont_touch = "true" *) hmao_fsm_state_t state_reg_b;
  hmao_fsm_state_t next_state;
  hmao_fsm_state_t effective_state;

  // Track whether Stage1 zonotope has been started (handles late preproc case)
  logic s1_started_reg;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_started_reg <= 1'b0;
    end else if (effective_state == FSM_IDLE) begin
      s1_started_reg <= 1'b0;  // Reset for next HMAO run
    end else if (start_s1) begin
      s1_started_reg <= 1'b1;  // Stage1 has been kicked
    end
  end

  // ===========================================================================
  // STATE REGISTER UPDATE (non-blocking, ASIL-D: both copies)
  // ===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_reg_a <= FSM_IDLE;
      state_reg_b <= FSM_IDLE;
    end else begin
      state_reg_a <= next_state;
      state_reg_b <= next_state;
    end
  end

  // Cross-check: if state registers disagree → treat as FSM_ERROR
  // This detects SEU (Single Event Upsets) in the state flip-flops
  always_comb begin
    if (state_reg_a !== state_reg_b) begin
      // Registers disagree: silent fault → force ERROR immediately
      effective_state = FSM_ERROR;
    end else begin
      effective_state = state_reg_a;
    end
  end

  assign fsm_state_out = effective_state;

  // ===========================================================================
  // NEXT STATE LOGIC (combinational)
  // Spec Ref: Section 9.2 - Transition Table
  // RULE: All case statements MUST have a default branch (RTL coding rule 17.1)
  // ===========================================================================
  always_comb begin
    // Default: stay in current state (prevents unintended transitions)
    next_state   = effective_state;
    start_preproc = 1'b0;
    start_s1      = 1'b0;
    start_admm    = 1'b0;
    start_s2      = 1'b0;
    output_grant  = 1'b0;
    output_veto   = 1'b0;

    unique case (effective_state)
      // -----------------------------------------------------------------------
      // IDLE: Wait for HMAO_START from RISCV DCLS
      // Spec Ref: Section 9.2 - IDLE transitions
      // -----------------------------------------------------------------------
      FSM_IDLE: begin
        if (hmao_start) begin
          if (preproc_valid && !preproc_error) begin
            // Pre-processing already done (pipelined ahead): jump to Stage1
            next_state   = FSM_STAGE1_COMP;
            start_s1     = 1'b1;
            start_admm   = 1'b1;   // Start ADMM in parallel
          end else if (preproc_error || crc_error) begin
            // Pre-proc found error: immediate VETO
            next_state   = FSM_OUTPUT_VETO;
            output_veto  = 1'b1;
          end else begin
            // Pre-processing not done yet: start it
            next_state    = FSM_STAGE1_COMP;  // Will wait for preproc internally
            start_preproc = 1'b1;
          end
        end
      end

      // -----------------------------------------------------------------------
      // STAGE1_COMPUTE: Zonotope 16g + ADMM running in parallel
      // Handles two entry paths:
      //   Path A: hmao_start with preproc_valid=1 → start_s1 already sent from IDLE
      //   Path B: hmao_start with preproc_valid=0 → start_preproc sent; wait for
      //           preproc to complete, then start Stage1 here
      // -----------------------------------------------------------------------
      FSM_STAGE1_COMP: begin
        if (crc_error || numerical_error) begin
          next_state  = FSM_ERROR;
          output_veto = 1'b1;
        end else if (wdt_s1_timeout) begin
          next_state  = FSM_ERROR;
          output_veto = 1'b1;
        end else if (preproc_error) begin
          // Preproc completed with error (detected while waiting in STAGE1_COMP)
          next_state   = FSM_OUTPUT_VETO;
          output_veto  = 1'b1;
        end else if (!preproc_valid && !s1_started_reg) begin
          // Preproc hasn't started yet - issue start command
          start_preproc = 1'b1;
        end else if (preproc_valid && !s1_started_reg) begin
          // Path B: preproc just finished → kick Stage1 zonotope + ADMM now
          start_s1   = 1'b1;
          start_admm = 1'b1;
        end else if (s1_zono_valid) begin
          next_state  = FSM_STAGE1_CHECK;
        end
        // else: stay in STAGE1_COMP, waiting
      end

      // -----------------------------------------------------------------------
      // STAGE1_CHECK: Collision check Stage 1
      // -----------------------------------------------------------------------
      FSM_STAGE1_CHECK: begin
        if (s1_no_collision && admm_done && !admm_diverged) begin
          // Fast path: no collision → GRANT (4ms path)
          next_state   = FSM_OUTPUT_GRANT;
          output_grant = 1'b1;
        end else if (s1_no_collision && admm_diverged) begin
          // ADMM diverged: conservative → go to Stage 2
          next_state   = FSM_STAGE2_COMP;
          start_s2     = 1'b1;
        end else if (s1_potential) begin
          // Stage 1 says potential collision: Stage 2 needed
          next_state   = FSM_STAGE2_COMP;
          start_s2     = 1'b1;
        end else if (wdt_s1_timeout) begin
          next_state   = FSM_ERROR;
          output_veto  = 1'b1;
        end
        // else: stay in STAGE1_CHECK, processing
      end

      // -----------------------------------------------------------------------
      // STAGE2_COMPUTE: Fine Zonotope 32g (conditional on POTENTIAL_COLLIDE)
      // -----------------------------------------------------------------------
      FSM_STAGE2_COMP: begin
        if (numerical_error) begin
          next_state  = FSM_ERROR;
          output_veto = 1'b1;
        end else if (wdt_s2_timeout) begin
          next_state  = FSM_ERROR;
          output_veto = 1'b1;
        end else if (s2_zono_valid) begin
          next_state  = FSM_STAGE2_CHECK;
        end
      end

      // -----------------------------------------------------------------------
      // STAGE2_CHECK: Final collision check
      // -----------------------------------------------------------------------
      FSM_STAGE2_CHECK: begin
        if (s2_no_collision) begin
          next_state   = FSM_OUTPUT_GRANT;
          output_grant = 1'b1;
        end else if (s2_collision) begin
          next_state   = FSM_OUTPUT_VETO;
          output_veto  = 1'b1;
        end else if (wdt_s2_timeout) begin
          next_state   = FSM_ERROR;
          output_veto  = 1'b1;
        end
        // else: stay in STAGE2_CHECK
      end

      // -----------------------------------------------------------------------
      // OUTPUT_GRANT: Assert GRANT, wait for RISCV to read, then go IDLE
      // -----------------------------------------------------------------------
      FSM_OUTPUT_GRANT: begin
        // One-cycle state: return to IDLE. output_grant was pulsed for 1 cycle
        // in STAGE1_CHECK/STAGE2_CHECK (edge-triggered IRQ — pulse, not level).
        next_state   = FSM_IDLE;
      end

      // -----------------------------------------------------------------------
      // OUTPUT_VETO: Assert VETO, trigger MRM, then go IDLE
      // -----------------------------------------------------------------------
      FSM_OUTPUT_VETO: begin
        next_state  = FSM_IDLE;
        output_veto = 1'b1;   // Continuously VETO while in this state
      end

      // -----------------------------------------------------------------------
      // ERROR: Stuck state. VETO always asserted. Requires system reset.
      // Spec Ref: Section 9.2 - ERROR (stuck - system reset required)
      // -----------------------------------------------------------------------
      FSM_ERROR: begin
        next_state  = FSM_ERROR;  // Stuck: only system reset can exit
        output_veto = 1'b1;       // Permanently VETO
        // FMU will detect HMAO_HANG fault and initiate MRM reset
      end

      // -----------------------------------------------------------------------
      // UNDEFINED: Corrupted state (Hamming-3 protection detected flip)
      // Force transition to ERROR immediately
      // -----------------------------------------------------------------------
      default: begin
        next_state  = FSM_ERROR;
        output_veto = 1'b1;
      end
    endcase
  end

  // ===========================================================================
  // FORMAL ASSERTIONS
  // ===========================================================================
  `ifdef FORMAL
    // State register cross-check must detect any mismatch
    assert property (@(posedge clk) disable iff (!rst_n)
      (state_reg_a !== state_reg_b) |-> (effective_state == FSM_ERROR))
      else $error("FSM: State register cross-check failed to detect mismatch");

    // FSM_ERROR is sticky
    assert property (@(posedge clk) disable iff (!rst_n)
      (effective_state == FSM_ERROR) |=> (effective_state == FSM_ERROR))
      else $error("FSM_ERROR must be a stuck state (requires system reset)");

    // output_grant and output_veto are mutually exclusive
    assert property (@(posedge clk) disable iff (!rst_n)
      !(output_grant && output_veto))
      else $error("FSM: GRANT and VETO asserted simultaneously - impossible");

    // In ERROR state, output_veto must always be 1
    assert property (@(posedge clk) disable iff (!rst_n)
      (effective_state == FSM_ERROR) |-> output_veto)
      else $error("FSM_ERROR: VETO must always be asserted in error state");
  `endif

endmodule : hmao_fsm
