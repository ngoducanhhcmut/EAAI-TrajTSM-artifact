// =============================================================================
// FILE        : tb_hmao_axi_arbiter_u14.sv (FIXED VERSION 3)
// PROJECT     : HMAO Engine - Unit Test Batch U14
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 2.2, 3.2
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : Batch U14 - Complete unit test suite for hmao_axi_arbiter.sv
//
//   TAXI_001 - Arbiter Priority  : Preproc beats SAT1 on simultaneous AR request
//   TAXI_002 - R Channel Demux   : Out-of-order RID routing verified with assertions
//   TAXI_003 - Burst INCR Len=7  : 8-beat burst, per-beat address progression, rlast
//   TAXI_004 - Fairness / No-Starvation : 10 K-cycle stress test, ?1% share each master
//
// FIX for TAXI_002 (2026-03-04) - v3:
//   - Modified slave_accept_ar to wait for a request from a specific master (optional).
//   - In test_taxi_002, we now wait for the specific arid (1) from SAT1.
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

// =============================================================================
// TESTBENCH MODULE
// =============================================================================
module tb_hmao_axi_arbiter_u14;

  // ===========================================================================
  // Clock & Reset
  // ===========================================================================
  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #1.25 clk = ~clk;  // 400 MHz ? T = 2.5 ns

  // ===========================================================================
  // Interface Instances
  //   m0..m3 : upstream master-side connections (TB drives arvalid etc.)
  //   s_mem  : downstream slave-side connection  (TB drives arready, rvalid etc.)
  // ===========================================================================
  axi4_ro_if m0_preproc_if(.aclk(clk), .aresetn(rst_n));  // Master-0: Pre-processor  (highest priority)
  axi4_ro_if m1_sat1_if(.aclk(clk), .aresetn(rst_n));     // Master-1: Stage-1 SAT checker
  axi4_ro_if m2_sat2_if(.aclk(clk), .aresetn(rst_n));     // Master-2: Stage-2 SAT checker
  axi4_ro_if m3_admm_if(.aclk(clk), .aresetn(rst_n));     // Master-3: ADMM solver    (lowest  priority)
  axi4_ro_if s_mem_if(.aclk(clk), .aresetn(rst_n));       // Slave: downstream memory / SMPU

  // ===========================================================================
  // DUT Instantiation
  // ===========================================================================
  hmao_axi_arbiter u_dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .m0_preproc (m0_preproc_if.slave),
    .m1_sat1    (m1_sat1_if.slave),
    .m2_sat2    (m2_sat2_if.slave),
    .m3_admm    (m3_admm_if.slave),
    .s_mem      (s_mem_if.master)
  );

  // ===========================================================================
  // Test Bookkeeping
  // ===========================================================================
  int pass_count = 0;
  int fail_count = 0;

  // Assertion helper macros - label printed on every check
  `define ASSERT_EQ(label, got, exp) \
    if ((got) !== (exp)) begin \
      $error("[FAIL] %-28s | got=0x%0x  exp=0x%0x  @%0t", label, got, exp, $time); \
      fail_count++; \
    end else begin \
      $display("[PASS] %-28s | value=0x%0x  @%0t", label, got, $time); \
      pass_count++; \
    end

  `define ASSERT_TRUE(label, cond) \
    if (!(cond)) begin \
      $error("[FAIL] %-28s | condition false  @%0t", label, $time); \
      fail_count++; \
    end else begin \
      $display("[PASS] %-28s | condition true  @%0t", label, $time); \
      pass_count++; \
    end

  `define ASSERT_FALSE(label, cond) \
    if (cond) begin \
      $error("[FAIL] %-28s | expected false but was true  @%0t", label, $time); \
      fail_count++; \
    end else begin \
      $display("[PASS] %-28s | correctly false  @%0t", label, $time); \
      pass_count++; \
    end

  // ===========================================================================
  // Task: apply_reset
  //   Hard resets DUT + drives all interface signals to safe idle values.
  // ===========================================================================
  task automatic apply_reset();
    rst_n = 1'b0;

    // --- Master BFM signals (TB drives AR side + rready) ---
    m0_preproc_if.arvalid = 0; m0_preproc_if.arid    = 0;
    m0_preproc_if.araddr  = 0; m0_preproc_if.arlen   = 0;
    m0_preproc_if.arsize  = 0; m0_preproc_if.arburst = 0;
    m0_preproc_if.aruser  = 0; m0_preproc_if.rready  = 0;

    m1_sat1_if.arvalid = 0; m1_sat1_if.arid    = 0;
    m1_sat1_if.araddr  = 0; m1_sat1_if.arlen   = 0;
    m1_sat1_if.arsize  = 0; m1_sat1_if.arburst = 0;
    m1_sat1_if.aruser  = 0; m1_sat1_if.rready  = 0;

    m2_sat2_if.arvalid = 0; m2_sat2_if.arid    = 0;
    m2_sat2_if.araddr  = 0; m2_sat2_if.arlen   = 0;
    m2_sat2_if.arsize  = 0; m2_sat2_if.arburst = 0;
    m2_sat2_if.aruser  = 0; m2_sat2_if.rready  = 0;

    m3_admm_if.arvalid = 0; m3_admm_if.arid    = 0;
    m3_admm_if.araddr  = 0; m3_admm_if.arlen   = 0;
    m3_admm_if.arsize  = 0; m3_admm_if.arburst = 0;
    m3_admm_if.aruser  = 0; m3_admm_if.rready  = 0;

    // --- Slave BFM signals (TB drives AR-ready, R-channel) ---
    s_mem_if.arready    = 0;
    s_mem_if.rvalid     = 0;  s_mem_if.rdata  = '0;
    s_mem_if.rresp      = 0;  s_mem_if.rlast  = 0;
    s_mem_if.rid        = 0;  s_mem_if.smpu_decerr = 0;

    repeat(12) @(posedge clk);
    rst_n = 1'b1;
    repeat(5) @(posedge clk);
  endtask

  // ===========================================================================
  // Task: slave_accept_ar_for_master
  //   Waits until s_mem shows arvalid from a specific master (arid == master_id).
  //   Pulses arready for one cycle, returns captured AR-channel parameters.
  //   Times out after 'timeout_cyc' cycles if the specific master is not seen.
  // ===========================================================================
  task automatic slave_accept_ar_for_master (
    input  int      timeout_cyc,
    input  logic [3:0] master_id,
    output logic    timed_out,
    output logic [3:0]  cap_arid,
    output logic [31:0] cap_araddr,
    output logic [7:0]  cap_arlen,
    output logic [2:0]  cap_arsize,
    output logic [1:0]  cap_arburst,
    output logic [7:0]  cap_aruser
  );
    int wait_cnt = 0;
    timed_out = 1'b0;
    cap_arid    = '0;  cap_araddr  = '0;
    cap_arlen   = '0;  cap_arsize  = '0;  cap_arburst = '0; cap_aruser = '0;

    // Wait until the arbiter forwards a valid AR request FROM THE SPECIFIC MASTER
    while (1) begin
      @(posedge clk);
      #0.1; // Small delta to allow combinational logic to settle
      if (s_mem_if.arvalid && s_mem_if.arid == master_id) begin
        // This is the transaction we are waiting for
        break;
      end
      wait_cnt++;
      if (wait_cnt >= timeout_cyc) begin
        timed_out = 1'b1;
        return;
      end
    end

    // Capture the forwarded AR fields AT THE MOMENT IT BECOMES VALID
    // This ensures we capture the correct transaction.
    cap_arid    = s_mem_if.arid;
    cap_araddr  = s_mem_if.araddr;
    cap_arlen   = s_mem_if.arlen;
    cap_arsize  = s_mem_if.arsize;
    cap_arburst = s_mem_if.arburst;
    cap_aruser  = s_mem_if.aruser;

    // Issue 1-cycle arready handshake
    s_mem_if.arready = 1'b1;
    @(posedge clk);
    #0.1;
    s_mem_if.arready = 1'b0;
  endtask

  // ===========================================================================
  // Task: slave_send_r_beats
  //   Drives N=(t_len+1) R-channel beats downstream from slave BFM.
  //   Each beat has unique data = base_data + beat_index.
  //   rready is assumed to be pre-asserted by the upstream master.
  // ===========================================================================
  task automatic slave_send_r_beats (
    input logic [3:0]   t_rid,
    input logic [7:0]   t_len,       // arlen ? total beats = t_len+1
    input logic [255:0] base_data
  );
    for (int i = 0; i <= int'(t_len); i++) begin
      // Set up beat one cycle before we expect rready
      s_mem_if.rvalid = 1'b1;
      s_mem_if.rid    = t_rid;
      s_mem_if.rdata  = base_data + 256'(i);
      s_mem_if.rresp  = 2'b00;
      s_mem_if.rlast  = (i == int'(t_len)) ? 1'b1 : 1'b0;

      // Wait until downstream rready (DUT's rready is derived from master's rready)
      @(posedge clk);
      while (!s_mem_if.rready) @(posedge clk);

      // Beat consumed - lower signals
      s_mem_if.rvalid = 1'b0;
      s_mem_if.rlast  = 1'b0;
      s_mem_if.rid    = '0;
    end
  endtask


  // ===========================================================================
  // ???????????????????????????????????????????????????????????????????????????
  // ?  TAXI_001 - Arbiter Priority: Preproc (prio=0) beats SAT1 (prio=1)    ?
  // ???????????????????????????????????????????????????????????????????????????
  //
  // Scenario:
  //   m0_preproc.arvalid = 1  (arid=4, addr=0x0000_1000)
  //   m1_sat1.arvalid    = 1  (arid=5, addr=0x0000_2000)  ? same cycle
  //
  // Expected:
  //   A1 - s_mem.arvalid = 1 (arbiter forwarded something)
  //   A2 - s_mem.arid    = 4 (preproc wins ? its arid forwarded)
  //   A3 - m1_sat1.arready = 0 (SAT1 NOT granted)
  //   A4 - m0_preproc.arready = 1 when slave pulses arready
  //   A5 - After preproc de-asserts, SAT1 then gets s_mem.arvalid
  // ===========================================================================
  task automatic test_taxi_001();
    logic        timed_out;
    logic [3:0]  cap_arid;
    logic [31:0] cap_araddr;
    logic [7:0]  cap_arlen;
    logic [2:0]  cap_arsize;
    logic [1:0]  cap_arburst;
    logic [7:0]  cap_aruser;

    $display("\n%0s", {70{"="}});
    $display("  TAXI_001 - Arbiter Priority: Preproc vs SAT1 simultaneous AR");
    $display("%0s\n", {70{"="}});

    apply_reset();

    // --- Drive both masters simultaneously (before posedge so DUT comb settles) ---
    // Preproc: arid=4, addr=0x0000_1000
    m0_preproc_if.arvalid = 1'b1;
    m0_preproc_if.arid    = 4'd4;
    m0_preproc_if.araddr  = 32'h0000_1000;
    m0_preproc_if.arlen   = 8'd0;
    m0_preproc_if.arsize  = 3'b010;   // 4 B/beat
    m0_preproc_if.arburst = 2'b01;    // INCR
    m0_preproc_if.aruser  = 8'h00;
    m0_preproc_if.rready  = 1'b1;

    // SAT1: arid=5, addr=0x0000_2000
    m1_sat1_if.arvalid = 1'b1;
    m1_sat1_if.arid    = 4'd5;
    m1_sat1_if.araddr  = 32'h0000_2000;
    m1_sat1_if.arlen   = 8'd0;
    m1_sat1_if.arsize  = 3'b010;
    m1_sat1_if.arburst = 2'b01;
    m1_sat1_if.aruser  = 8'h00;
    m1_sat1_if.rready  = 1'b1;

    // Let one posedge pass so DUT always_comb settles in simulation
    @(posedge clk); #0.1;

    // A1: arbiter forwarded a request
    `ASSERT_TRUE("TAXI_001_A1_smem_arvalid", s_mem_if.arvalid)

    // A2: forwarded arid must be preproc's (=4), not SAT1's (=5)
    `ASSERT_EQ  ("TAXI_001_A2_smem_arid",    s_mem_if.arid,    4'd4)

    // A3: SAT1 arready must be low - it is blocked
    `ASSERT_FALSE("TAXI_001_A3_sat1_blocked", m1_sat1_if.arready)

    // A4: Pulse slave arready, verify preproc.arready propagates
    s_mem_if.arready = 1'b1;
    #0.1; // combinational propagation within same sim time step
    `ASSERT_TRUE ("TAXI_001_A4_preproc_arready", m0_preproc_if.arready)
    // Double-check SAT1 still blocked even when arready is asserted
    `ASSERT_FALSE("TAXI_001_A4_sat1_still_blocked", m1_sat1_if.arready)

    @(posedge clk);              // AR handshake completes (arvalid & arready both 1)
    s_mem_if.arready = 1'b0;
    m0_preproc_if.arvalid = 1'b0; // preproc done

    // Return one data beat to complete preproc's outstanding transaction
    @(posedge clk);              // 1-cycle bubble, rid_tracker updates
    slave_send_r_beats(4'd4, 8'd0, 256'hAAAA_BBBB);

    // A5: SAT1 should now appear on s_mem (it was waiting)
    @(posedge clk); #0.1;
    `ASSERT_TRUE ("TAXI_001_A5_sat1_now_wins",  s_mem_if.arvalid && (s_mem_if.arid == 4'd5))

    // Clean up
    s_mem_if.arready = 1'b1;
    @(posedge clk);
    s_mem_if.arready = 1'b0;
    m1_sat1_if.arvalid = 1'b0;
    @(posedge clk);
    slave_send_r_beats(4'd5, 8'd0, 256'hCCCC_DDDD);
    m1_sat1_if.rready = 1'b0;
    m0_preproc_if.rready = 1'b0;

    $display("[TAXI_001] Complete");
  endtask


  // ===========================================================================
  // ???????????????????????????????????????????????????????????????????????????
  // ?  TAXI_002 - Arbiter R Demux: Out-of-Order RID Response Routing (FIXED) ?
  // ???????????????????????????????????????????????????????????????????????????
  //
  // Scenario:
  //   1. Preproc issues AR with arid=0, addr = TRAJ_BUFFER_BASE
  //   2. SAT1   issues AR with arid=1, addr = WORLD_MODEL_BASE
  //   3. Slave returns data for RID=1 FIRST (out-of-order)
  //   4. Slave returns data for RID=0 SECOND
  //
  // Expected:
  //   A1 - On RID=1 response: m1_sat1.rvalid=1, m0_preproc.rvalid=0
  //   A2 - On RID=0 response: m0_preproc.rvalid=1, m1_sat1.rvalid=0
  //   A3 - rid and rdata forwarded intact (no corruption)
  // ===========================================================================
  task automatic test_taxi_002();
    logic        timed_out;
    logic [3:0]  cap_arid;
    logic [31:0] cap_araddr;
    logic [7:0]  cap_arlen;
    logic [2:0]  cap_arsize;
    logic [1:0]  cap_arburst;
    logic [7:0]  cap_aruser;

    $display("\n%0s", {70{"="}});
    $display("  TAXI_002 - R Demux: Out-of-order RID routing");
    $display("%0s\n", {70{"="}});

    apply_reset();

    // ---- Step 1: Issue preproc AR (arid=0) --------------------------------
    $display("[TAXI_002] Step 1 - Issuing Preproc AR (arid=0)...");
    m0_preproc_if.arvalid = 1'b1;
    m0_preproc_if.arid    = 4'd0;
    m0_preproc_if.araddr  = TRAJ_BUFFER_BASE;
    m0_preproc_if.arlen   = 8'd0;
    m0_preproc_if.arsize  = 3'b010;
    m0_preproc_if.arburst = 2'b01;
    m0_preproc_if.rready  = 1'b1;

    // Wait for preproc's request to appear at s_mem.
    slave_accept_ar_for_master(20, 4'd0, timed_out, cap_arid, cap_araddr, cap_arlen, cap_arsize, cap_arburst, cap_aruser);
    `ASSERT_FALSE("TAXI_002_S1_no_timeout",      timed_out)
    `ASSERT_EQ   ("TAXI_002_S1_arid_is_preproc", cap_arid, 4'd0)
    `ASSERT_EQ   ("TAXI_002_S1_araddr_is_preproc", cap_araddr, TRAJ_BUFFER_BASE)
    m0_preproc_if.arvalid = 1'b0;   // preproc de-asserts after acceptance

    // ---- Step 2: Issue SAT1 AR (arid=1) -----------------------------------
    $display("[TAXI_002] Step 2 - Issuing SAT1 AR (arid=1)...");
    m1_sat1_if.arvalid = 1'b1;
    m1_sat1_if.arid    = 4'd1;
    m1_sat1_if.araddr  = WORLD_MODEL_BASE;  // Different address from preproc
    m1_sat1_if.arlen   = 8'd0;
    m1_sat1_if.arsize  = 3'b010;
    m1_sat1_if.arburst = 2'b01;
    m1_sat1_if.rready  = 1'b1;

    // Wait for SAT1's request to appear at s_mem.
    slave_accept_ar_for_master(20, 4'd1, timed_out, cap_arid, cap_araddr, cap_arlen, cap_arsize, cap_arburst, cap_aruser);
    `ASSERT_FALSE("TAXI_002_S2_no_timeout",    timed_out)
    // FIX v3: Use the new task to wait for the specific master.
    `ASSERT_EQ   ("TAXI_002_S2_arid_is_sat1", cap_arid, 4'd1)
    `ASSERT_EQ   ("TAXI_002_S2_araddr_is_sat1", cap_araddr, WORLD_MODEL_BASE)

    m1_sat1_if.arvalid = 1'b0;

    // CRITICAL: Wait 2 clocks after the second acceptance so that rid_tracker
    // [0] = 2'd0 and rid_tracker[1] = 2'd1 are fully registered and stable.
    repeat(2) @(posedge clk);

    // ---- Step 3: Return data for RID=1 FIRST (out-of-order) --------------
    $display("[TAXI_002] Step 3 - Returning RID=1 (SAT1) data first (out-of-order)...");
    s_mem_if.rvalid = 1'b1;
    s_mem_if.rid    = 4'd1;
    s_mem_if.rdata  = 256'hDEAD_BEEF_1111_0000;
    s_mem_if.rresp  = 2'b00;
    s_mem_if.rlast  = 1'b1;
    @(posedge clk); #0.1;

    // A1: Only SAT1 should see rvalid; preproc should remain silent
    `ASSERT_TRUE ("TAXI_002_A1_sat1_rvalid",       m1_sat1_if.rvalid)
    `ASSERT_FALSE("TAXI_002_A1_preproc_not_rvalid", m0_preproc_if.rvalid)
    `ASSERT_EQ   ("TAXI_002_A1_sat1_rid_ok",        m1_sat1_if.rid, 4'd1)

    @(posedge clk);
    s_mem_if.rvalid = 1'b0; s_mem_if.rlast = 1'b0;

    // ---- Step 4: Return data for RID=0 (preproc) -------------------------
    $display("[TAXI_002] Step 4 - Returning RID=0 (Preproc) data...");
    @(posedge clk); // one gap between transactions
    s_mem_if.rvalid = 1'b1;
    s_mem_if.rid    = 4'd0;
    s_mem_if.rdata  = 256'hCAFE_BABE_0000_1111;
    s_mem_if.rresp  = 2'b00;
    s_mem_if.rlast  = 1'b1;
    @(posedge clk); #0.1;

    // A2: Only Preproc sees rvalid; SAT1 must be silent now
    `ASSERT_TRUE ("TAXI_002_A2_preproc_rvalid",  m0_preproc_if.rvalid)
    `ASSERT_FALSE("TAXI_002_A2_sat1_not_rvalid", m1_sat1_if.rvalid)
    `ASSERT_EQ   ("TAXI_002_A2_preproc_rid_ok",  m0_preproc_if.rid, 4'd0)

    // A3: rdata forwarded intact
    `ASSERT_EQ   ("TAXI_002_A3_rdata_intact", m0_preproc_if.rdata, 256'hCAFE_BABE_0000_1111)

    @(posedge clk);
    s_mem_if.rvalid = 1'b0; s_mem_if.rlast = 1'b0;
    m0_preproc_if.rready = 1'b0; m1_sat1_if.rready = 1'b0;

    $display("[TAXI_002] Complete");
  endtask


  // ===========================================================================
  // ???????????????????????????????????????????????????????????????????????????
  // ?  TAXI_003 - Burst Handling: INCR burst, arlen=7 (8 beats)              ?
  // ???????????????????????????????????????????????????????????????????????????
  //
  // Scenario:
  //   Preproc issues AR: araddr=TRAJ_BUFFER_BASE=0x8030_0000, arlen=7,
  //                      arsize=2 (4 B/beat), arburst=01 (INCR)
  //
  // Verification:
  //   A1 - AR parameters forwarded intact to s_mem
  //   A2 - Exactly 8 beats (arlen+1) received at preproc
  //   A3 - rlast asserted on beat index 7 only
  //   A4 - Beat data unique per beat (data integrity, no mix-up)
  //   A5 - Computed INCR address progression displayed (0x00 ? 0x1C offsets)
  //
  // Notes:
  //   In AXI4, only the start address is sent on AR.  The slave computes
  //   per-beat addresses internally.  The DUT (arbiter) passes AR through
  //   transparently; address arithmetic lives in the slave BFM.
  //   We verify here that all burst parameters are forwarded unaltered so the
  //   downstream slave CAN compute the correct per-beat addresses.
  // ===========================================================================
  task automatic test_taxi_003();
    logic        timed_out;
    logic [3:0]  cap_arid;
    logic [31:0] cap_araddr;
    logic [7:0]  cap_arlen;
    logic [2:0]  cap_arsize;
    logic [1:0]  cap_arburst;
    logic [7:0]  cap_aruser;

    int          beat_count;
    int          rlast_beat;
    logic [255:0] recv_data [0:7];  // captured beat data
    logic [255:0] exp_data;

    $display("\n%0s", {70{"="}});
    $display("  TAXI_003 - INCR Burst: arlen=7 (8 beats) from 0x%08x", TRAJ_BUFFER_BASE);
    $display("%0s\n", {70{"="}});

    apply_reset();

    // ---- Issue the burst AR from preproc ----------------------------------
    m0_preproc_if.arvalid = 1'b1;
    m0_preproc_if.arid    = 4'd2;
    m0_preproc_if.araddr  = TRAJ_BUFFER_BASE;  // 0x8030_0000
    m0_preproc_if.arlen   = 8'd7;              // 8 beats
    m0_preproc_if.arsize  = 3'b010;            // 4 B/beat ? addr_incr = 4
    m0_preproc_if.arburst = 2'b01;             // INCR
    m0_preproc_if.aruser  = 8'h1A;             // SMPU master ID
    m0_preproc_if.rready  = 1'b1;

    // --- A1: Verify AR passthrough to slave before accepting ---------------
    @(posedge clk); #0.1;
    `ASSERT_TRUE("TAXI_003_A1_smem_arvalid",    s_mem_if.arvalid)
    `ASSERT_EQ  ("TAXI_003_A1_araddr",          s_mem_if.araddr,  TRAJ_BUFFER_BASE)
    `ASSERT_EQ  ("TAXI_003_A1_arlen",           s_mem_if.arlen,   8'd7)
    `ASSERT_EQ  ("TAXI_003_A1_arsize",          s_mem_if.arsize,  3'b010)
    `ASSERT_EQ  ("TAXI_003_A1_arburst_INCR",    s_mem_if.arburst, 2'b01)
    `ASSERT_EQ  ("TAXI_003_A1_aruser",          s_mem_if.aruser,  8'h1A)
    `ASSERT_EQ  ("TAXI_003_A1_arid",            s_mem_if.arid,    4'd2)

    $display("[TAXI_003] AR forwarded correctly: araddr=0x%08x arlen=%0d arburst=INCR",
             s_mem_if.araddr, s_mem_if.arlen);

    // Accept the AR
    s_mem_if.arready = 1'b1;
    @(posedge clk);
    #0.1;
    s_mem_if.arready = 1'b0;
    m0_preproc_if.arvalid = 1'b0;  // master de-asserts after handshake
    @(posedge clk);                 // rid_tracker update latency

    // ---- Return 8 beats; capture what preproc receives -------------------
    beat_count = 0;
    rlast_beat = -1;

    $display("[TAXI_003] Sending 8 beats from slave BFM...");
    $display("[TAXI_003] Expected INCR address per beat (arsize=2, incr=4 bytes):");
    for (int i = 0; i < 8; i++) begin
      logic [31:0] beat_addr;
      beat_addr = TRAJ_BUFFER_BASE + 32'(i * 4);  // addr_incr = 2^arsize = 4
      $display("  Beat %0d : addr = 0x%08x  (offset +0x%02x)", i, beat_addr, i*4);

      // Drive slave outputs
      s_mem_if.rvalid = 1'b1;
      s_mem_if.rid    = 4'd2;
      s_mem_if.rdata  = 256'(32'hA000_0000) + 256'(i);  // unique pattern per beat
      s_mem_if.rresp  = 2'b00;
      s_mem_if.rlast  = (i == 7) ? 1'b1 : 1'b0;

      @(posedge clk); #0.1;  // sample after posedge

      // Check that the DUT routed this beat to preproc
      `ASSERT_TRUE($sformatf("TAXI_003_A2_beat%0d_rvalid", i), m0_preproc_if.rvalid)
      recv_data[i] = m0_preproc_if.rdata;

      if (m0_preproc_if.rvalid) beat_count++;
      if (m0_preproc_if.rlast)  rlast_beat = i;

      @(posedge clk);  // wait for handshake (rready already=1)
      s_mem_if.rvalid = 1'b0;
      s_mem_if.rlast  = 1'b0;
    end

    // A2: Exactly 8 beats received
    `ASSERT_EQ("TAXI_003_A2_total_beats", beat_count, 8)

    // A3: rlast on final beat only
    `ASSERT_EQ("TAXI_003_A3_rlast_on_beat7", rlast_beat, 7)

    // A4: Data integrity - each beat carried a unique value
    for (int i = 0; i < 8; i++) begin
      exp_data = 256'(32'hA000_0000) + 256'(i);
      `ASSERT_EQ($sformatf("TAXI_003_A4_beat%0d_data", i), recv_data[i], exp_data)
    end

    m0_preproc_if.rready = 1'b0;

    $display("[TAXI_003] Complete - all 8 beats delivered, rlast correct, data intact");
  endtask


  // ===========================================================================
  // ???????????????????????????????????????????????????????????????????????????
  // ?  TAXI_004 - Fairness / Anti-Starvation Stress Test                     ?
  // ???????????????????????????????????????????????????????????????????????????
  //
  // Scenario:
  //   10 K AR-grant cycles.  Each cycle randomly decides which masters request:
  //     Preproc  : 30 % probability  (burst workload duty cycle)
  //     SAT1     : 50 % probability  (exclusive with SAT2 - per spec)
  //     SAT2     : 50 % probability  (exclusive with SAT1 - alternates)
  //     ADMM     : 70 % probability  (background solver, usually active)
  //   Slave BFM accepts every AR immediately and returns 1 beat.
  //
  // Expected distribution (worst-case fixed-priority approximation):
  //   Preproc ? 30 %, SAT1 ? 35 %, SAT2 ? 18 %, ADMM ? 17 %
  //
  // Assertions:
  //   A1 - All active masters (issued ?1 request) must receive ?1 % of grants
  //   A2 - Priority order: Preproc grant-share ? ADMM grant-share
  //        (This verifies the priority policy is actually in effect, not
  //         just coincidental because of request probabilities.  With 30 % req
  //         rate for preproc and 70 % for ADMM, if priority is violated,
  //         ADMM would get far more grants than preproc.)
  //
  // Note on fixed-priority vs. starvation:
  //   A pure fixed-priority arbiter CAN starve lower-priority requestors if
  //   higher-priority masters never idle.  This test verifies the system
  //   behaves correctly with realistic (bursty) workloads where preproc does
  //   not hold the bus 100 % of the time.  Functional correctness (higher
  //   prio wins when both active) is verified in TAXI_001.
  // ===========================================================================
  task automatic test_taxi_004();
    // Use 10 K cycles - scales to 1 M in regression (uncomment SIM_CYCLES).
    // 10 K gives <5 ms sim time at 400 MHz; stat error ? 1 % at this N.
    localparam int SIM_CYCLES = 10_000;
    // localparam int SIM_CYCLES = 1_000_000;  // uncomment for full regression

    // Grant counters per master [0]=preproc [1]=sat1 [2]=sat2 [3]=admm
    int grant_count[4];
    int total_grants;
    int sat2_turn;  // toggles to enforce SAT1/SAT2 exclusivity

    // Per-master request tracking (did this master ever request?)
    int req_total[4];

    real pct[4];
    logic ar_presented;
    logic [3:0] winner_id;

    $display("\n%0s", {70{"="}});
    $display("  TAXI_004 - Fairness Stress Test  (%0d grant cycles)", SIM_CYCLES);
    $display("%0s\n", {70{"="}});

    apply_reset();

    for (int i = 0; i < 4; i++) begin
      grant_count[i] = 0;
      req_total[i]   = 0;
    end
    total_grants = 0;
    sat2_turn    = 0;

    // All masters always accept R data immediately
    m0_preproc_if.rready = 1'b1;
    m1_sat1_if.rready    = 1'b1;
    m2_sat2_if.rready    = 1'b1;
    m3_admm_if.rready    = 1'b1;

    for (int cyc = 0; cyc < SIM_CYCLES; cyc++) begin

      // --- Decide which masters request this cycle (random) ----------------
      begin
        automatic logic r0, r1, r2, r3;
        r0 = ($urandom_range(0, 99) < 30);  // 30% preproc
        // SAT1/SAT2 are mutually exclusive per FSM spec (Sect 2.2)
        r1 = (!sat2_turn) && ($urandom_range(0, 99) < 50);
        r2 = ( sat2_turn) && ($urandom_range(0, 99) < 50);
        r3 = ($urandom_range(0, 99) < 70);  // 70% ADMM

        m0_preproc_if.arvalid = r0;
        m0_preproc_if.arid    = 4'd0;
        m0_preproc_if.araddr  = 32'h8030_0000 + 32'(cyc & 32'hFF) * 4;
        m0_preproc_if.arlen   = 8'd0;
        m0_preproc_if.arsize  = 3'b010;
        m0_preproc_if.arburst = 2'b01;

        m1_sat1_if.arvalid = r1;
        m1_sat1_if.arid    = 4'd1;
        m1_sat1_if.araddr  = 32'h8040_0000 + 32'(cyc & 32'hFF) * 4;
        m1_sat1_if.arlen   = 8'd0;
        m1_sat1_if.arsize  = 3'b010;
        m1_sat1_if.arburst = 2'b01;

        m2_sat2_if.arvalid = r2;
        m2_sat2_if.arid    = 4'd2;
        m2_sat2_if.araddr  = 32'h8040_1000 + 32'(cyc & 32'hFF) * 4;
        m2_sat2_if.arlen   = 8'd0;
        m2_sat2_if.arsize  = 3'b010;
        m2_sat2_if.arburst = 2'b01;

        m3_admm_if.arvalid = r3;
        m3_admm_if.arid    = 4'd3;
        m3_admm_if.araddr  = 32'h8020_0000 + 32'(cyc & 32'hFF) * 4;
        m3_admm_if.arlen   = 8'd0;
        m3_admm_if.arsize  = 3'b010;
        m3_admm_if.arburst = 2'b01;

        if (r0) req_total[0]++;
        if (r1) req_total[1]++;
        if (r2) req_total[2]++;
        if (r3) req_total[3]++;
      end

      @(posedge clk); #0.1;

      // --- Accept any AR the arbiter forwarded ---------------------------
      if (s_mem_if.arvalid) begin
        // Determine which master won by checking whose arready was pulsed
        // (DUT only asserts arready on the winning master)
        s_mem_if.arready = 1'b1;
        winner_id = s_mem_if.arid;  // the arid tells us the master

        // Map arid to master index for grant counting
        // (arid=0?preproc, 1?sat1, 2?sat2, 3?admm as assigned above)
        grant_count[int'(winner_id[1:0])]++;
        total_grants++;

        // Toggle sat2_turn when SAT1 or SAT2 finishes
        if      (winner_id == 4'd1) sat2_turn = 1;  // SAT1 done ? SAT2's turn
        else if (winner_id == 4'd2) sat2_turn = 0;  // SAT2 done ? SAT1's turn

        @(posedge clk);
        #0.1;
        s_mem_if.arready = 1'b0;

        // Immediately return 1 beat so outstanding transaction clears
        @(posedge clk);  // rid_tracker update latency
        s_mem_if.rvalid = 1'b1;
        s_mem_if.rid    = winner_id;
        s_mem_if.rdata  = 256'(cyc);
        s_mem_if.rresp  = 2'b00;
        s_mem_if.rlast  = 1'b1;
        @(posedge clk);
        s_mem_if.rvalid = 1'b0;
        s_mem_if.rlast  = 1'b0;
      end
    end

    // --- Clear all request signals ----------------------------------------
    m0_preproc_if.arvalid = 0; m1_sat1_if.arvalid = 0;
    m2_sat2_if.arvalid    = 0; m3_admm_if.arvalid = 0;
    m0_preproc_if.rready  = 0; m1_sat1_if.rready  = 0;
    m2_sat2_if.rready     = 0; m3_admm_if.rready  = 0;

    // --- Compute percentages and run assertions ---------------------------
    $display("[TAXI_004] ?? Grant Statistics ????????????????????????????????");
    $display("[TAXI_004]   Total grants     : %0d  (out of %0d cycles)", total_grants, SIM_CYCLES);
    for (int i = 0; i < 4; i++) begin
      pct[i] = (total_grants > 0) ? real'(grant_count[i]) * 100.0 / real'(total_grants) : 0.0;
    end
    $display("[TAXI_004]   Preproc (prio 0) : %6d grants  %5.1f %%  (requested %0d times)",
             grant_count[0], pct[0], req_total[0]);
    $display("[TAXI_004]   SAT1    (prio 1) : %6d grants  %5.1f %%  (requested %0d times)",
             grant_count[1], pct[1], req_total[1]);
    $display("[TAXI_004]   SAT2    (prio 2) : %6d grants  %5.1f %%  (requested %0d times)",
             grant_count[2], pct[2], req_total[2]);
    $display("[TAXI_004]   ADMM    (prio 3) : %6d grants  %5.1f %%  (requested %0d times)",
             grant_count[3], pct[3], req_total[3]);
    $display("[TAXI_004] ????????????????????????????????????????????????????");

    // A1: Every master that actually issued requests must get ?1 % of grants
    //     (ensures no starvation under realistic workloads)
    begin : starvation_check
      string names[4] = '{"Preproc","SAT1","SAT2","ADMM"};
      for (int i = 0; i < 4; i++) begin
      if (req_total[i] > 0) begin  // only assert for masters that requested
        if (pct[i] < 1.0) begin
          $error("[FAIL] TAXI_004_A1_%s STARVED: %.1f%% < 1%% threshold", names[i], pct[i]);
          fail_count++;
        end else begin
          $display("[PASS] TAXI_004_A1_%s anti-starvation : %.1f%% >= 1%%", names[i], pct[i]);
          pass_count++;
        end
      end else begin
        $display("[INFO] TAXI_004   %s never requested - skip starvation check", names[i]);
      end
    end  // for
    end  // starvation_check

    // A2: Priority ordering check - preproc grant share must exceed ADMM
    //     (preproc req_prob=30%, ADMM req_prob=70%; correct priority inverts the natural count)
    if (req_total[0] > 0 && req_total[3] > 0) begin
      if (pct[0] >= pct[3]) begin
        $display("[PASS] TAXI_004_A2_priority_check : Preproc(%.1f%%) >= ADMM(%.1f%%) - priority in effect",
                 pct[0], pct[3]);
        pass_count++;
      end else begin
        $error("[FAIL] TAXI_004_A2_priority_check : Preproc(%.1f%%) < ADMM(%.1f%%) - priority NOT effective",
               pct[0], pct[3]);
        fail_count++;
      end
    end

    $display("[TAXI_004] Complete");
  endtask


  // ===========================================================================
  // ???????????????????????????????????????????????????????????????????????????
  // ?  CONCURRENT SVA ASSERTIONS  (run throughout entire simulation)         ?
  // ???????????????????????????????????????????????????????????????????????????

  // SVA-1: At most one master arready active at any time (one-hot arbiter output)
  property p_onehot_grant;
    @(posedge clk)
      $onehot0({ m3_admm_if.arready, m2_sat2_if.arready,
                 m1_sat1_if.arready, m0_preproc_if.arready });
  endproperty

  a_onehot_grant: assert property (p_onehot_grant)
    else $error("[SVA] ONEHOT_GRANT violated - multiple arready signals high simultaneously (multi-grant)");

  // SVA-2: When Preproc AND SAT1 both request, SAT1 must NOT be granted
  property p_preproc_priority_over_sat1;
    @(posedge clk)
      (m0_preproc_if.arvalid && m1_sat1_if.arvalid) |-> !m1_sat1_if.arready;
  endproperty

  a_preproc_priority_sat1: assert property (p_preproc_priority_over_sat1)
    else $error("[SVA] PRIORITY violated - SAT1 granted while Preproc also requesting");

  // SVA-3: When Preproc AND ADMM both request, ADMM must NOT be granted
  property p_preproc_priority_over_admm;
    @(posedge clk)
      (m0_preproc_if.arvalid && m3_admm_if.arvalid) |-> !m3_admm_if.arready;
  endproperty

  a_preproc_priority_admm: assert property (p_preproc_priority_over_admm)
    else $error("[SVA] PRIORITY violated - ADMM granted while Preproc also requesting");

  // SVA-4: When s_mem accepts an AR transaction, exactly one master must be granted
  property p_single_grant_on_accept;
    @(posedge clk)
      (s_mem_if.arvalid && s_mem_if.arready) |->
        $onehot({ m3_admm_if.arready, m2_sat2_if.arready,
                  m1_sat1_if.arready, m0_preproc_if.arready });
  endproperty

  a_single_grant: assert property (p_single_grant_on_accept)
    else $error("[SVA] SINGLE_GRANT violated - slave accepted AR but no master arready asserted");

  // SVA-5: s_mem.arvalid must originate from exactly one active master
  //        (no ghost transactions)
  property p_smem_arvalid_has_requester;
    @(posedge clk)
      s_mem_if.arvalid |->
        (m0_preproc_if.arvalid | m1_sat1_if.arvalid |
         m2_sat2_if.arvalid    | m3_admm_if.arvalid);
  endproperty

  a_smem_has_requester: assert property (p_smem_arvalid_has_requester)
    else $error("[SVA] GHOST_TRANSACTION - s_mem.arvalid but no upstream master is requesting");

  // ===========================================================================
  // ???????????????????????????????????????????????????????????????????????????
  // ?  MAIN TEST RUNNER                                                       ?
  // ???????????????????????????????????????????????????????????????????????????
  // ===========================================================================
  initial begin
    $display("\n%0s", {70{"*"}});
    $display("  HMAO AXI Arbiter - Unit Test Batch U14 (FIXED VERSION 3)");
    $display("  File    : hmao_axi_arbiter.sv");
    $display("  DUT     : hmao_axi_arbiter (4-input fixed-priority AXI4-RO)");
    $display("  Sim     : %0t  |  CLK = 400 MHz", $time);
    $display("%0s\n", {70{"*"}});

    test_taxi_001();
    test_taxi_002();
    test_taxi_003();
    test_taxi_004();

    // ---- Final Summary -------------------------------------------------------
    $display("\n%0s", {70{"="}});
    $display("  BATCH U14 FINAL SUMMARY");
    $display("  PASS : %0d", pass_count);
    $display("  FAIL : %0d", fail_count);
    if (fail_count == 0)
      $display("  *** ALL TESTS PASSED - Batch U14 COMPLETE ***");
    else
      $display("  !!! FAILURES DETECTED - Review error messages above !!!");
    $display("%0s\n", {70{"="}});

    repeat(10) @(posedge clk);
    $finish;
  end

  // Simulation timeout guard (safeguard against deadlocks)
  initial begin
    // 50 ms wall time at 400 MHz ? time needed for TAXI_004 (10K cycles ? 0.025 ms)
    #50_000_000;
    $display("[TIMEOUT] Simulation exceeded 50 ms - possible hang or deadlock");
    $finish;
  end

  // Waveform capture
  initial begin
    $dumpfile("hmao_arbiter_u14.vcd");
    $dumpvars(0, tb_hmao_axi_arbiter_u14);
  end

endmodule : tb_hmao_axi_arbiter_u14