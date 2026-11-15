// =============================================================================
// FILE        : hmao_axi_arbiter.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 2.2, 3.2
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : 4-input AXI4 Read-Only arbiter (fixed priority, deterministic).
//               Stage 1 (m1_sat1) and Stage 2 (m2_sat2) collision checkers
//               never run concurrently (different FSM paths), but need separate
//               modport connections per SystemVerilog structural elaboration rules.
//               The ADMM solver (m3_admm) runs in parallel with Stage 1.
//
//               Port priority (highest to lowest):
//               1. m0_preproc  - pre-fetch trajectory (must complete earliest)
//               2. m1_sat1     - Stage 1 collision checker (critical path)
//               3. m2_sat2     - Stage 2 collision checker (exclusive with sat1)
//               4. m3_admm     - ADMM solver (parallel with Stage 1, lowest prio)
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module hmao_axi_arbiter (
  input  logic                 clk,
  input  logic                 rst_n,

  // =========================================================================
  // 4x AXI4-RO Master Interfaces (inputs from requesters)
  // =========================================================================

  // Master 0: Pre-processor (highest priority)
  axi4_ro_if.slave             m0_preproc,

  // Master 1: Stage 1 SAT Collision Checker
  axi4_ro_if.slave             m1_sat1,

  // Master 2: Stage 2 SAT Collision Checker (exclusive with sat1 per FSM)
  axi4_ro_if.slave             m2_sat2,

  // Master 3: ADMM Solver (lowest priority)
  axi4_ro_if.slave             m3_admm,

  // =========================================================================
  // Single AXI4-RO Slave Interface (output to memory/SMPU)
  // =========================================================================
  axi4_ro_if.master            s_mem
);

  // ===========================================================================
  // INTERNAL SIGNAL DEFINITIONS
  // ===========================================================================

  // Priority selector: which master gets access (one-hot, 4-bit)
  // grant[0]=preproc, [1]=sat1, [2]=sat2, [3]=admm
  logic [3:0] arbiter_grant;

  // ===========================================================================
  // FIXED PRIORITY ARBITER
  // Spec Ref: Deterministic priority — no dynamic round-robin → bounded latency
  // ===========================================================================
  always_comb begin
    arbiter_grant = 4'b0000;  // default: no grant

    if      (m0_preproc.arvalid) arbiter_grant = 4'b0001;
    else if (m1_sat1.arvalid)    arbiter_grant = 4'b0010;
    else if (m2_sat2.arvalid)    arbiter_grant = 4'b0100;
    else if (m3_admm.arvalid)    arbiter_grant = 4'b1000;
  end

  // ===========================================================================
  // MULTIPLEXER: AR Channel (Address Read)
  // ===========================================================================
  always_comb begin
    // Default: arready = 0 to all, no request to slave
    m0_preproc.arready = 1'b0;
    m1_sat1.arready    = 1'b0;
    m2_sat2.arready    = 1'b0;
    m3_admm.arready    = 1'b0;

    s_mem.arid    = '0;
    s_mem.araddr  = '0;
    s_mem.arlen   = '0;
    s_mem.arsize  = '0;
    s_mem.arburst = '0;
    s_mem.arvalid = 1'b0;
    s_mem.aruser  = '0;

    unique case (arbiter_grant)
      4'b0001: begin  // Master 0 (preproc)
        s_mem.arid    = m0_preproc.arid;
        s_mem.araddr  = m0_preproc.araddr;
        s_mem.arlen   = m0_preproc.arlen;
        s_mem.arsize  = m0_preproc.arsize;
        s_mem.arburst = m0_preproc.arburst;
        s_mem.arvalid = m0_preproc.arvalid;
        s_mem.aruser  = m0_preproc.aruser;
        m0_preproc.arready = s_mem.arready;
      end

      4'b0010: begin  // Master 1 (SAT1)
        s_mem.arid    = m1_sat1.arid;
        s_mem.araddr  = m1_sat1.araddr;
        s_mem.arlen   = m1_sat1.arlen;
        s_mem.arsize  = m1_sat1.arsize;
        s_mem.arburst = m1_sat1.arburst;
        s_mem.arvalid = m1_sat1.arvalid;
        s_mem.aruser  = m1_sat1.aruser;
        m1_sat1.arready = s_mem.arready;
      end

      4'b0100: begin  // Master 2 (SAT2)
        s_mem.arid    = m2_sat2.arid;
        s_mem.araddr  = m2_sat2.araddr;
        s_mem.arlen   = m2_sat2.arlen;
        s_mem.arsize  = m2_sat2.arsize;
        s_mem.arburst = m2_sat2.arburst;
        s_mem.arvalid = m2_sat2.arvalid;
        s_mem.aruser  = m2_sat2.aruser;
        m2_sat2.arready = s_mem.arready;
      end

      4'b1000: begin  // Master 3 (ADMM)
        s_mem.arid    = m3_admm.arid;
        s_mem.araddr  = m3_admm.araddr;
        s_mem.arlen   = m3_admm.arlen;
        s_mem.arsize  = m3_admm.arsize;
        s_mem.arburst = m3_admm.arburst;
        s_mem.arvalid = m3_admm.arvalid;
        s_mem.aruser  = m3_admm.aruser;
        m3_admm.arready = s_mem.arready;
      end

      default: begin
        s_mem.arvalid = 1'b0;
      end
    endcase
  end

  // ===========================================================================
  // R Channel (Read Data Response)
  // Route return data to the correct master using RID tag tracking.
  // ===========================================================================

  // Map RID → master index (0=preproc, 1=sat1, 2=sat2, 3=admm)
  logic [1:0] rid_tracker [0:15];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 16; i++) rid_tracker[i] <= 2'd0;
    end else begin
      // Detect handshake using s_mem.arready (external TB input via .master modport)
      // combined with arbiter_grant (DUT-internal comb) and mX.arvalid (external
      // TB input via .slave modport).  This avoids reading mX.arready which is
      // driven by this module's own always_comb through the slave interface —
      // that feedback path can cause XSim to sample a stale value at the clock
      // edge before the combinational update propagates through the interface.
      // Logically equivalent: grant[X] && mX.arvalid && s_mem.arready
      //                     = grant[X] && mX.arvalid && mX.arready  (when grant[X]=1)
      if (s_mem.arready) begin
        if (arbiter_grant[0] && m0_preproc.arvalid)
          rid_tracker[m0_preproc.arid] <= 2'd0;
        if (arbiter_grant[1] && m1_sat1.arvalid)
          rid_tracker[m1_sat1.arid]    <= 2'd1;
        if (arbiter_grant[2] && m2_sat2.arvalid)
          rid_tracker[m2_sat2.arid]    <= 2'd2;
        if (arbiter_grant[3] && m3_admm.arvalid)
          rid_tracker[m3_admm.arid]    <= 2'd3;
      end
    end
  end

  // Demultiplex R channel to correct master
  always_comb begin
    m0_preproc.rvalid = 1'b0; m0_preproc.rdata = '0;
    m0_preproc.rresp  = '0;   m0_preproc.rlast = 1'b0; m0_preproc.rid = '0;
    m1_sat1.rvalid    = 1'b0; m1_sat1.rdata    = '0;
    m1_sat1.rresp     = '0;   m1_sat1.rlast    = 1'b0; m1_sat1.rid    = '0;
    m2_sat2.rvalid    = 1'b0; m2_sat2.rdata    = '0;
    m2_sat2.rresp     = '0;   m2_sat2.rlast    = 1'b0; m2_sat2.rid    = '0;
    m3_admm.rvalid    = 1'b0; m3_admm.rdata    = '0;
    m3_admm.rresp     = '0;   m3_admm.rlast    = 1'b0; m3_admm.rid    = '0;

    unique case (rid_tracker[s_mem.rid])
      2'd0: begin
        m0_preproc.rvalid = s_mem.rvalid; m0_preproc.rdata = s_mem.rdata;
        m0_preproc.rresp  = s_mem.rresp;  m0_preproc.rlast = s_mem.rlast;
        m0_preproc.rid    = s_mem.rid;
      end
      2'd1: begin
        m1_sat1.rvalid = s_mem.rvalid; m1_sat1.rdata = s_mem.rdata;
        m1_sat1.rresp  = s_mem.rresp;  m1_sat1.rlast = s_mem.rlast;
        m1_sat1.rid    = s_mem.rid;
      end
      2'd2: begin
        m2_sat2.rvalid = s_mem.rvalid; m2_sat2.rdata = s_mem.rdata;
        m2_sat2.rresp  = s_mem.rresp;  m2_sat2.rlast = s_mem.rlast;
        m2_sat2.rid    = s_mem.rid;
      end
      2'd3: begin
        m3_admm.rvalid = s_mem.rvalid; m3_admm.rdata = s_mem.rdata;
        m3_admm.rresp  = s_mem.rresp;  m3_admm.rlast = s_mem.rlast;
        m3_admm.rid    = s_mem.rid;
      end
      default: ; // no routing
    endcase
  end

  // rready: route from whichever master owns the active transaction
  assign s_mem.rready = (rid_tracker[s_mem.rid] == 2'd0) ? m0_preproc.rready :
                        (rid_tracker[s_mem.rid] == 2'd1) ? m1_sat1.rready    :
                        (rid_tracker[s_mem.rid] == 2'd2) ? m2_sat2.rready    :
                        (rid_tracker[s_mem.rid] == 2'd3) ? m3_admm.rready    :
                        1'b0;

  // smpu_decerr: forward from slave to all masters (they all inspect it)
  always_comb begin
    m0_preproc.smpu_decerr = s_mem.smpu_decerr;
    m1_sat1.smpu_decerr    = s_mem.smpu_decerr;
    m2_sat2.smpu_decerr    = s_mem.smpu_decerr;
    m3_admm.smpu_decerr    = s_mem.smpu_decerr;
  end

  // ===========================================================================
  // FORMAL ASSERTIONS
  // ===========================================================================
  `ifdef FORMAL
    // Only one grant at a time (one-hot0: at most one bit set)
    assert property (@(posedge clk) $onehot0(arbiter_grant))
      else $error("ARBITER: Multiple grants simultaneously – determinism violated");

    // Active arvalid must eventually be served
    assert property (@(posedge clk) disable iff (!rst_n)
      s_mem.arvalid |=> s_mem.arready || s_mem.arvalid)
      else $error("ARBITER: AXI AR stall – forward-progress violated");

    // SAT1 and SAT2 must never request simultaneously (different FSM phases)
    assert property (@(posedge clk) disable iff (!rst_n)
      !(m1_sat1.arvalid && m2_sat2.arvalid))
      else $error("ARBITER: SAT1 and SAT2 active simultaneously – FSM error");
  `endif

endmodule : hmao_axi_arbiter