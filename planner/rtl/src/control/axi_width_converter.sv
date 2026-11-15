/* verilator lint_off DECLFILENAME */
`timescale 1ns/1ps
// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// axi_width_converter.sv — AXI Bus Width Converter 128-bit → 64-bit  (v3 — FINAL)
// Spec: §15.2 (AXI HP0 128-bit → internal 64-bit BRAM paths)
// ================================================================================
// Converts AXI READ responses from 128-bit (HP0 DDR interface) to 64-bit
// for URAM/BRAM writes (posemb_bram, weight_loader URAM writes).
//
// Protocol:
//   BEAT0: out_data = rdata[63:0],    out_resp = rresp,  out_last = 0
//   BEAT1: out_data = rdata[127:64],  out_resp = 2'b00,  out_last = rlast
//
// State machine: IDLE → BEAT0 → BEAT1 → IDLE
//
// ── Design decision: COMBINATORIAL outputs ────────────────────────────────────
//  out_valid, out_data, out_resp, out_last are pure assign statements driven by
//  the REGISTERED state and data_hold.
//
//  Why this fixes all 5 bugs vs. the v1/v2 registered-output approach:
//
//  Root cause of all failures: v1/v2 tried to use non-blocking assignments to
//  update out_data from two different code paths in the same always_ff block
//  (the "last-assign-wins" pre-load trick). Under xsim 2023.2, this interaction
//  between the default assignment and the if-block override did not produce the
//  expected behavior, leaving all errors identical to the original buggy code.
//
//  With combinatorial outputs:
//  • At posedge N, state registers transition (e.g. IDLE→BEAT0) via NBA.
//  • By posedge N + 100 ps (TB capture window), NBA has settled.
//    Combinatorial decode sees NEW state → outputs are correct instantly.
//  • No pre-loading, no last-assign-wins, no timing ambiguity.
//
//  Bug mapping:
//    BUG-1 Spurious valid:      eliminated — out_valid=0 the instant state=IDLE.
//    BUG-2 Pipeline off-by-one: eliminated — no pipeline; BEAT1 visible the
//                               same posedge state transitions to ST_BEAT1.
//    BUG-3 Byte-lane swap:      eliminated — output mux selects correct half
//                               based on state, not on when data was pre-loaded.
//    BUG-4 Backpressure freeze: eliminated — state holds ST_BEAT0 when ready=0;
//                               combinatorial out_data and out_resp are stable.
//    BUG-5 RESP wrong beat:     eliminated — out_resp is a combinatorial function
//                               of state, always correct regardless of backpressure.
// ================================================================================

module axi_width_converter
(
  input  logic          clk,
  input  logic          rst_n,

  // ── AXI READ DATA INPUT (128-bit) ──────────────────────────────────────
  input  logic [127:0]  axi_rdata,
  input  logic  [1:0]   axi_rresp,
  input  logic          axi_rlast,
  input  logic          axi_rvalid,
  output logic          axi_rready,

  // ── OUTPUT: 64-bit beats (×2 per 128-bit input) ────────────────────────
  output logic [63:0]   out_data,
  output logic  [1:0]   out_resp,
  output logic          out_last,
  output logic          out_valid,
  input  logic          out_ready
);

  typedef enum logic [1:0] {
    ST_IDLE  = 2'b00,
    ST_BEAT0 = 2'b01,
    ST_BEAT1 = 2'b10
  } state_t;

  // ── Registered state ────────────────────────────────────────────────────
  state_t       state;
  logic [127:0] data_hold;   // latched full 128-bit word
  logic  [1:0]  resp_hold;   // latched axi_rresp (for BEAT0)
  logic         last_hold;   // latched axi_rlast  (for BEAT1)

  // ── Combinatorial output decode ──────────────────────────────────────────
  //  These update instantly when state/data_hold NBA settle after posedge,
  //  well before the TB's posedge + 100 ps capture window.
  //
  //  axi_rready: only accept when IDLE and downstream is ready
  assign axi_rready = (state == ST_IDLE)  && out_ready;
  //
  //  out_valid: asserted during BEAT0 and BEAT1, de-asserted in IDLE
  assign out_valid  = (state == ST_BEAT0) || (state == ST_BEAT1);
  //
  //  out_data: lower half during BEAT0, upper half during BEAT1
  assign out_data   = (state == ST_BEAT0) ? data_hold[63:0]    // BEAT0
                                          : data_hold[127:64];  // BEAT1 (and IDLE — don't care)
  //
  //  out_resp: AXI resp code on BEAT0, always zero on BEAT1
  assign out_resp   = (state == ST_BEAT0) ? resp_hold
                                          : 2'b00;
  //
  //  out_last: always 0 on BEAT0, propagate rlast on BEAT1
  assign out_last   = (state == ST_BEAT1) ? last_hold
                                          : 1'b0;

  // ── Registered state machine ─────────────────────────────────────────────
  //  Only state, data_hold, resp_hold, last_hold are registered.
  //  No out_* assignments here → zero multiple-NBA-to-same-variable risk.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_IDLE;
      data_hold <= '0;
      resp_hold <= '0;
      last_hold <= '0;
    end else begin
      case (state)

        // ── IDLE: accept AXI beat when downstream is ready ───────────────
        //  axi_rready (combinatorial) is 1 here by definition.
        ST_IDLE: begin
          if (axi_rvalid && out_ready) begin
            data_hold <= axi_rdata;
            resp_hold <= axi_rresp;
            last_hold <= axi_rlast;
            state     <= ST_BEAT0;
            // After this NBA: state=BEAT0, combinatorial shows:
            //   out_valid=1, out_data=rdata[63:0], out_resp=rresp, out_last=0
          end
          // else: state stays IDLE, out_valid stays 0 (combinatorial)
        end

        // ── BEAT0: present lower half, advance when consumer is ready ────
        ST_BEAT0: begin
          if (out_ready) begin
            state <= ST_BEAT1;
            // After this NBA: state=BEAT1, combinatorial shows:
            //   out_valid=1, out_data=data_hold[127:64], out_resp=0, out_last=last_hold
          end
          // else: state stays BEAT0, combinatorial holds outputs stable — ✓ backpressure
        end

        // ── BEAT1: present upper half, return to IDLE when consumer is ready
        ST_BEAT1: begin
          if (out_ready) begin
            state <= ST_IDLE;
            // After this NBA: state=IDLE, combinatorial shows:
            //   out_valid=0   ← no spurious valid
          end
          // else: state stays BEAT1, combinatorial holds BEAT1 outputs stable
        end

        default: state <= ST_IDLE;

      endcase
    end
  end

endmodule
// ================================================================================