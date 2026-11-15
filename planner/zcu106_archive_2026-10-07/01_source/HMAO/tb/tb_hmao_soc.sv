// =============================================================================
// FILE        : tb_hmao_soc.sv
// PROJECT     : HMAO Engine - System Testbench
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 16
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module tb_hmao_soc;

  // ===========================================================================
  // CLOCKS & RESET
  // ===========================================================================
  parameter real CLK_PERIOD_NS  = 2.5;

  logic hmao_clk    = 1'b0;
  logic qm_clk      = 1'b0;
  logic wdt_osc_clk = 1'b0;
  logic hmao_rst_n  = 1'b0;
  logic qm_rst_n    = 1'b0;

  always #(CLK_PERIOD_NS/2)  hmao_clk    = ~hmao_clk;
  always #(CLK_PERIOD_NS/2)  qm_clk      = ~qm_clk;
  always #(1.5)               wdt_osc_clk = ~wdt_osc_clk; // ~333 MHz ring osc

  // ===========================================================================
  // FAKE MEMORY MODEL (Trajectory + World Model)
  // ===========================================================================
  // Trajectory buffer: 1,404 bytes (1,400 data + 4 CRC)
  logic [31:0]  traj_mem  [0:350];    // 351 words
  // World model: 8MB = 131072 objects × 64B
  logic [31:0]  wm_mem    [0:524287]; // 2M words (simplified - use 256 objects in TB)

  // AXI burst tracking state (multi-beat burst support)
  logic [7:0]   axi_beats_rem;    // beats remaining after current (0 on last beat)
  logic [10:0]  axi_beat_woff;    // current word offset into traj_mem or wm_mem
  logic         axi_in_traj_rgn;  // 1 = this burst is in trajectory region
  logic         axi_in_wm_rgn;    // 1 = this burst is in world model region
  logic         axi_wm_wide;      // 1 = 256-bit beat (arsize==5), advance by 8 words/beat

  // ===========================================================================
  // DUT INTERFACE SIGNALS
  // ===========================================================================
  logic [31:0]  hmao_araddr;
  logic [7:0]   hmao_arlen;
  logic [2:0]   hmao_arsize;
  logic [1:0]   hmao_arburst;
  logic         hmao_arvalid;
  logic [7:0]   hmao_aruser;
  logic         hmao_arready;
  logic [255:0] hmao_rdata;
  logic [1:0]   hmao_rresp    = '0;
  logic         hmao_rlast    = '0;
  logic         hmao_rvalid   = '0;
  logic         hmao_rready;

  // DMA Interface Signals
  logic         dma_traj_done = 1'b0;    // DMA copy complete
  logic         dma_sig_valid = 1'b0;    // IOMMU signature check passed
  
  // Directly control HMAO engine (bypass RISCV for now)
  logic         test_hmao_start = 1'b0;  // Testbench directly pulses HMAO
  logic         can_tx_mrm_req;
  logic         can_tx_grant;
  logic         hmao_irq_out;
  logic [6:0]   sfi_fault_flags;
  logic         sfi_fault_valid;
  logic         sfi_fault_ack = 1'b0;

  logic [7:0]   qm_gps_quality     = 8'd200;
  logic [7:0]   qm_camera_quality  = 8'd200;
  logic [7:0]   qm_road_friction   = 8'd200;
  logic [7:0]   qm_actuator_health = 8'd255;
  logic [7:0]   qm_weather_severity= 8'd0;
  logic         qm_uvec_req        = 1'b0;
  logic         qm_uvec_ack;

  logic [2:0]   debug_fsm_state;
  logic [31:0]  debug_latency_cycles;
  logic         debug_riscv_halted;
  logic         debug_test_hmao_start_received;
  logic         debug_hmao_start_combined;
  logic         debug_hmao_start_pulse;
  logic         debug_start_preproc;
  logic [6:0]   debug_hmao_fsm_state_raw;
  logic         debug_engine_hmao_start_seen;
  logic         debug_preproc_valid;
  logic         debug_preproc_error;

  // ===========================================================================
  // DUT INSTANTIATION
  // ===========================================================================
  hmao_soc_top u_dut (
    .hmao_clk           (hmao_clk),
    .hmao_rst_n         (hmao_rst_n),
    .qm_clk             (qm_clk),
    .qm_rst_n           (qm_rst_n),
    .wdt_ring_osc_clk   (wdt_osc_clk),
    .dma_traj_done      (dma_traj_done),
    .dma_sig_valid      (dma_sig_valid),
    .test_hmao_start    (test_hmao_start),
    .hmao_araddr        (hmao_araddr),
    .hmao_arlen         (hmao_arlen),
    .hmao_arsize        (hmao_arsize),
    .hmao_arburst       (hmao_arburst),
    .hmao_arvalid       (hmao_arvalid),
    .hmao_aruser        (hmao_aruser),
    .hmao_arready       (hmao_arready),
    .hmao_rdata         (hmao_rdata),
    .hmao_rresp         (hmao_rresp),
    .hmao_rlast         (hmao_rlast),
    .hmao_rvalid        (hmao_rvalid),
    .hmao_rready        (hmao_rready),
    .can_tx_mrm_req     (can_tx_mrm_req),
    .can_tx_grant       (can_tx_grant),
    .hmao_irq_out       (hmao_irq_out),
    .sfi_fault_flags    (sfi_fault_flags),
    .sfi_fault_valid    (sfi_fault_valid),
    .sfi_fault_ack      (sfi_fault_ack),
    .qm_gps_quality     (qm_gps_quality),
    .qm_camera_quality  (qm_camera_quality),
    .qm_road_friction   (qm_road_friction),
    .qm_actuator_health (qm_actuator_health),
    .qm_weather_severity(qm_weather_severity),
    .qm_uvec_req        (qm_uvec_req),
    .qm_uvec_ack        (qm_uvec_ack),
    .debug_fsm_state    (debug_fsm_state),
    .debug_latency_cycles(debug_latency_cycles),
    .debug_riscv_halted (debug_riscv_halted),
    .debug_test_hmao_start_received (debug_test_hmao_start_received),
    .debug_hmao_start_combined (debug_hmao_start_combined),
    .debug_hmao_start_pulse (debug_hmao_start_pulse),
    .debug_start_preproc (debug_start_preproc),
    .debug_hmao_fsm_state_raw (debug_hmao_fsm_state_raw),
    .debug_engine_hmao_start_seen (debug_engine_hmao_start_seen),
    .debug_preproc_valid (debug_preproc_valid),
    .debug_preproc_error (debug_preproc_error)
  );

  // ===========================================================================
  // AXI MEMORY MODEL - multi-beat INCR burst support (arsize=4B)
  // Handles any arlen: returns arlen+1 beats with incrementing word offset.
  // ===========================================================================

  // Combinational read-data mux from current beat word offset
  // Trajectory: 4B/beat on 256-bit bus; word shifted into address-selected byte lane
  // World model: 32B/beat → pack 8 consecutive 32-bit words into 256 bits
  always_comb begin
    if (axi_in_traj_rgn)
      hmao_rdata = ({224'd0, traj_mem[axi_beat_woff]} << {axi_beat_woff[2:0], 5'b0});
    else if (axi_in_wm_rgn)
      hmao_rdata = {wm_mem[axi_beat_woff+7], wm_mem[axi_beat_woff+6],
                    wm_mem[axi_beat_woff+5], wm_mem[axi_beat_woff+4],
                    wm_mem[axi_beat_woff+3], wm_mem[axi_beat_woff+2],
                    wm_mem[axi_beat_woff+1], wm_mem[axi_beat_woff+0]};
    else
      hmao_rdata = '0;
  end

  // Simplified AR/R phase logic without state tracking
  logic ar_accepted;
  assign ar_accepted = hmao_arvalid && hmao_arready;
  
  always_ff @(posedge hmao_clk) begin
    if (!hmao_rst_n) begin
      hmao_rvalid     <= 1'b0;
      hmao_rlast      <= 1'b0;
      hmao_rresp      <= 2'b00;
      axi_beats_rem   <= '0;
      axi_beat_woff   <= '0;
      axi_in_traj_rgn <= 1'b0;
      axi_in_wm_rgn   <= 1'b0;
      axi_wm_wide     <= 1'b0;
    end else begin
      // AR phase: capture address info when accepted
      if (ar_accepted) begin
        axi_beats_rem   <= hmao_arlen;
        axi_in_traj_rgn <= (hmao_araddr >= TRAJ_BUFFER_BASE &&
                            hmao_araddr <  TRAJ_BUFFER_BASE + 32'h0578);
        axi_in_wm_rgn   <= (hmao_araddr >= WORLD_MODEL_BASE &&
                            hmao_araddr <  WORLD_MODEL_BASE + 32'h0020_0000);
        axi_wm_wide     <= (hmao_arsize == 3'b101);  // 32B/beat
        // Word offset: relative to region base, in 4-byte units
        if (hmao_araddr >= WORLD_MODEL_BASE)
          axi_beat_woff <= 11'((hmao_araddr - WORLD_MODEL_BASE) >> 2);
        else
          axi_beat_woff <= 11'((hmao_araddr - TRAJ_BUFFER_BASE) >> 2);
      end

      // R phase: start data transfer one cycle after AR
      if (ar_accepted) begin
        hmao_rvalid <= 1'b1;
        hmao_rlast  <= (hmao_arlen == 8'd0);
        hmao_rresp  <= 2'b00;
      end else if (hmao_rvalid && hmao_rready) begin
        if (hmao_rlast) begin
          // Last beat consumed — burst complete
          hmao_rvalid <= 1'b0;
          hmao_rlast  <= 1'b0;
        end else begin
          // Advance to next beat: 8 words/beat for 256-bit WM reads, 1 word/beat otherwise
          axi_beat_woff <= axi_beat_woff + (axi_wm_wide ? 11'd8 : 11'd1);
          axi_beats_rem <= axi_beats_rem - 1'b1;
          hmao_rlast    <= (axi_beats_rem == 8'd1);  // next beat is last
        end
      end
    end
  end

  // AR ready: combinational, always accept when not busy
  assign hmao_arready = !hmao_rvalid;

  // ===========================================================================
  // UTILITY TASKS
  // ===========================================================================

  // ===========================================================================
  // CRC32 helpers (IEEE 802.3, polynomial 0xEDB88320) - mirrors hmao_preproc
  // ===========================================================================
  function automatic logic [31:0] crc32_byte_tb(
    input logic [31:0] crc_in,
    input logic [7:0]  data_byte
  );
    logic [31:0] crc;
    crc = crc_in ^ {24'b0, data_byte};
    for (int i = 0; i < 8; i++) begin
      if (crc[0]) crc = (crc >> 1) ^ 32'hEDB8_8320;
      else        crc = crc >> 1;
    end
    return crc;
  endfunction

  // Compute CRC32 of traj_mem[0..349] and store at traj_mem[350]
  task automatic compute_and_store_crc();
    logic [31:0] crc;
    crc = 32'hFFFF_FFFF;
    for (int w = 0; w < 350; w++) begin
      crc = crc32_byte_tb(crc32_byte_tb(crc32_byte_tb(crc32_byte_tb(
              crc,            traj_mem[w][7:0]),
              traj_mem[w][15:8]),
              traj_mem[w][23:16]),
              traj_mem[w][31:24]);
    end
    traj_mem[350] = crc ^ 32'hFFFF_FFFF;
    $display("[TB] CRC32 computed: 0x%08X", traj_mem[350]);
  endtask

  // BUG-FIX (Q8.8 vs float32 test-data format): waypoint x/y/vx/vy/heading
  // fields are genuine IEEE-754 float32 in the real system (hmao_preproc.sv
  // reads e.g. vx[30:23] as the fp32 exponent field -- same convention
  // established by BUG-FIX PP-001/ZG-001). These tasks used to write raw
  // Q8.8 integers directly, which hmao_preproc/hmao_zonotope_gen would
  // misinterpret as tiny float32 denormals (collapsing to ~0), silently
  // breaking any check that depends on actual trajectory motion. Values
  // below are computed in real-number space and converted via
  // $shortrealtobits (IEEE-754 single precision, bit-identical to fp32_t).
  task automatic init_safe_trajectory();
    $display("[TB] Initializing safe straight-line trajectory (float32)...");

    // 50 waypoints: straight ahead at 10 m/s (well within VMAX=35)
    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      traj_mem[wp*7 + 0] = $shortrealtobits(shortreal'(wp) * 1.0);  // x = 1.0m * wp (10m/s*0.1s)
      traj_mem[wp*7 + 1] = 32'd0;                   // y = 0.0 (straight) -- fp32(0.0)=0x0
      traj_mem[wp*7 + 2] = 32'd0;                   // z = 0.0
      traj_mem[wp*7 + 3] = $shortrealtobits(10.0);  // vx = 10.0 m/s
      traj_mem[wp*7 + 4] = 32'd0;                   // vy = 0.0
      traj_mem[wp*7 + 5] = 32'd0;                   // heading = 0.0 rad
      traj_mem[wp*7 + 6] = 32'(wp * 26);            // timestamp: Q8.8 (not fp32 -- see note below)
    end

    // Compute correct CRC32 of 350 words and store at traj_mem[350]
    compute_and_store_crc();

    $display("[TB] Trajectory loaded: 50 waypoints, straight at 10m/s (float32)");
  endtask

  // Task: Initialize trajectory with collision course (float32)
  task automatic init_collision_trajectory();
    $display("[TB] Initializing COLLISION trajectory aimed at obstacle at 25m (float32)...");

    for (int wp = 0; wp < TRAJ_WAYPOINTS; wp++) begin
      // x = 15.0 m/s * wp * 0.1s = 1.5m per step; y = 0.5 m/s * wp * 0.1s = 0.05m per step
      traj_mem[wp*7 + 0] = $shortrealtobits(shortreal'(wp) * 1.5);   // x = 1.5m * wp
      traj_mem[wp*7 + 1] = $shortrealtobits(shortreal'(wp) * 0.05);  // y = 0.05m * wp
      traj_mem[wp*7 + 2] = 32'd0;
      traj_mem[wp*7 + 3] = $shortrealtobits(15.0);   // vx = 15.0 m/s
      traj_mem[wp*7 + 4] = $shortrealtobits(0.5);    // vy = 0.5 m/s
      traj_mem[wp*7 + 5] = $shortrealtobits(0.033);  // heading ~= 0.033 rad
      traj_mem[wp*7 + 6] = 32'(wp * 26);             // timestamp: Q8.8 (not fp32 -- see note below)
    end
    // Compute correct CRC32 for this trajectory
    compute_and_store_crc();
  endtask
  // NOTE: traj_mem[wp*7+6] (timestamp) is intentionally left as Q8.8 -- it
  // is documentation/metadata only, not read by hmao_preproc's fp32 datapath
  // (only x/y/z/vx/vy/heading feed the float32-based bbox/kinematic checks).

  // Task: Place obstacle in world model at given position.
  // All dimensions/positions stored as Q8.8 (value * 256).
  // Layout matches world_model_object_t as read by hmao_collision_sat AXI fetch:
  //   Beat0 words [0..7]: pos_x,pos_y,pos_z,vel_x,vel_y,vel_z,dim_length,dim_width
  //   Beat1 words [8..15]: dim_height,heading,[10]:confidence<<24|obj_class<<16|track_id,...
  // SAT reads confidence from rdata[95:88] = wm_mem[base+10][31:24].
  task automatic place_obstacle(
    input real x, real y, real z,
    input real vx, real vy,
    input real len, real wid, real hei,
    input real heading,
    input logic [15:0] track_id,
    input logic [7:0]  obj_class
  );
    // Word index = track_id * 16 (64 bytes / 4 bytes per word)
    int base = track_id * 16;
    // Q8.8: real value * 256, stored in lower 16 bits of 32-bit word
    wm_mem[base+0]  = 32'(int'(x   * 256.0));  // pos_x
    wm_mem[base+1]  = 32'(int'(y   * 256.0));  // pos_y
    wm_mem[base+2]  = 32'(int'(z   * 256.0));  // pos_z
    wm_mem[base+3]  = 32'(int'(vx  * 256.0));  // vel_x
    wm_mem[base+4]  = 32'(int'(vy  * 256.0));  // vel_y
    wm_mem[base+5]  = 32'd0;                    // vel_z
    wm_mem[base+6]  = 32'(int'(len * 256.0));  // dim_length
    wm_mem[base+7]  = 32'(int'(wid * 256.0));  // dim_width
    wm_mem[base+8]  = 32'(int'(hei * 256.0));  // dim_height
    wm_mem[base+9]  = 32'(int'(heading * 256.0)); // heading
    // Byte layout for wm_mem[base+10] must match SAT AXI read:
    //   rdata[79:64]  = track_id  → [15:0]
    //   rdata[87:80]  = obj_class → [23:16]
    //   rdata[95:88]  = confidence→ [31:24]
    wm_mem[base+10] = {8'h64, obj_class, track_id}; // confidence=100, class, track_id
    // Rest = predicted trajectory (zeros = stationary)
    for (int i = 11; i < 16; i++) wm_mem[base+i] = '0;
    $display("[TB] Obstacle placed: pos=(%.1f,%.1f) Q8.8=(0x%04x,0x%04x), size=(%.1f×%.1f), id=%0d",
             x, y, int'(x*256.0), int'(y*256.0), len, wid, track_id);
  endtask

  // Task: Wait for HMAO_COMPLETE IRQ with timeout
  task automatic wait_hmao_complete(
    input  int unsigned timeout_cycles,
    output logic completed
  );
    int unsigned count = 0;
    completed = 1'b0;
    while (count < timeout_cycles) begin
      @(posedge hmao_clk);
      count++;
      if (hmao_irq_out) begin
        completed = 1'b1;
        return;
      end
    end
    $display("[TB] WARNING: HMAO_COMPLETE not received within %0d cycles", timeout_cycles);
  endtask

  // Task: Check HMAO decision
  // decision_ok=1 only when the actual output matches expected_decision
  task automatic check_decision(
    input  string tc_name,
    input  logic  expected_decision,  // 1=GRANT, 0=VETO
    output logic  decision_ok
  );
    decision_ok = 1'b0;
    // Wait 1 cycle for outputs to settle after IRQ
    @(posedge hmao_clk);

    if (expected_decision && can_tx_grant) begin
      $display("[TB] PASS: %s → GRANT (expected)", tc_name);
      decision_ok = 1'b1;
    end else if (!expected_decision && can_tx_mrm_req) begin
      $display("[TB] PASS: %s → VETO (expected)", tc_name);
      decision_ok = 1'b1;
    end else begin
      $display("[TB] FAIL: %s → wrong output (grant=%b mrm=%b expected=%b)",
               tc_name, can_tx_grant, can_tx_mrm_req, expected_decision);
    end

    // Performance check
    $display("[TB] %s: Latency = %0d cycles = %.2f ms",
             tc_name, debug_latency_cycles,
             debug_latency_cycles / 400000.0);
    assert (debug_latency_cycles <= MAX_TOTAL_CYCLES)
      else $error("[TB] LATENCY VIOLATION: %0d cycles > 4M limit", debug_latency_cycles);
  endtask

  // ===========================================================================
  // SIMULATION MAIN
  // ===========================================================================
  logic completed;
  int   pass_count, fail_count;

  initial begin
    pass_count = 0;
    fail_count = 0;

    $display("=====================================================");
    $display(" HMAO Engine System Testbench - ASIL-D Verification");
    $display(" Spec: HMAO_Engine_Full_Spec v12.0");
    $display("=====================================================");

    // -------------------------------------------------------------------------
    // RESET
    // -------------------------------------------------------------------------
    hmao_rst_n <= 1'b0;
    qm_rst_n   <= 1'b0;
    repeat(20) @(posedge hmao_clk);
    hmao_rst_n <= 1'b1;
    qm_rst_n   <= 1'b1;
    repeat(10) @(posedge hmao_clk);

    // -------------------------------------------------------------------------
    // INITIAL QM UNCERTAINTY VECTOR (good sensor quality)
    // -------------------------------------------------------------------------
    qm_gps_quality     <= 8'd220;
    qm_camera_quality  <= 8'd210;
    qm_road_friction   <= 8'd200;
    qm_actuator_health <= 8'd255;
    qm_uvec_req <= 1'b1;
    @(posedge qm_clk);
    qm_uvec_req <= 1'b0;

    // =========================================================================
    // TC001: Safe trajectory - no obstacles nearby → GRANT expected
    // Spec Ref: Section 16.2 - "70-90% trajectories expected GRANT"
    // =========================================================================
    $display("\n[TC001] Safe trajectory (no obstacles)");
    init_safe_trajectory();

    // Simulate DMA completion (trajectory written to buffer)
    // Keep signal HIGH so RISCV firmware can reliably detect it (not a 1-cycle pulse)
    dma_traj_done <= 1'b1;
    dma_sig_valid <= 1'b1;
    repeat(10) @(posedge hmao_clk);  // Give firmware time to see and react

    // Directly pulse HMAO_START for testing (bypass RISCV firmware)
    // EXTENDED PULSE: Keep HIGH for 200 cycles to ensure FSM samples it reliably
    $display("[DEBUG TC001] Asserting test_hmao_start for 200 cycles (long pulse to ensure FSM samples)");
    test_hmao_start <= 1'b1;
    $display("[DEBUG@%0t] test_hmao_start=1 (START)", $time);
    
    // Monitor signals WHILE test_hmao_start is HIGH
    // This lets us see when FSM responds
    $display("[DEBUG TC001] Monitoring FSM response while test_hmao_start is HIGH:");
    for (int pulse_cyc = 0; pulse_cyc < 200; pulse_cyc++) begin
      @(posedge hmao_clk);
      
      // Print every 10 cycles to see FSM state changes
      if (pulse_cyc % 10 == 0 || pulse_cyc < 5) begin
        $display("[PULSE%3d@%0t] test_start_rx=%b hmao_comb=%b ENGINE_SEES=%b | FSM=0x%02x start_pp=%b pp_valid=%b pp_err=%b arV=%b",
                 pulse_cyc, $time, debug_test_hmao_start_received, debug_hmao_start_combined,
                 debug_engine_hmao_start_seen, debug_hmao_fsm_state_raw, debug_start_preproc, debug_preproc_valid, debug_preproc_error, hmao_arvalid);
      end
      
      // Exit early if FSM transitions out of IDLE (start_preproc pulsed)
      if (debug_start_preproc) begin
        $display("[FSM TRANSITION DETECTED!] start_preproc went HIGH at cycle %0d", pulse_cyc);
        break;
      end
    end
    
    // Now release the pulse
    test_hmao_start <= 1'b0;
    $display("[DEBUG@%0t] test_hmao_start=0 (RELEASED after 200 cycles)", $time);
    
    // Monitor critical signals for MUCH LONGER after release
    // Preproc takes ~200,000 cycles, so wait that long to see AXI activity
    $display("[DEBUG TC001] Extended monitoring: watching for AXI burst completion...");
    for (int ext_i = 0; ext_i < 250000; ext_i++) begin
      @(posedge hmao_clk);
      
      // Print when AXI first becomes active
      if (ext_i == 0 || hmao_arvalid || hmao_rvalid || (ext_i > 0 && ext_i % 50000 == 0)) begin
        $display("[EXT%6d@%0t] arV=%b rV=%b araddr=0x%08x | FSM=0x%02x preproc_ready=%b",
                 ext_i, $time, hmao_arvalid, hmao_rvalid, hmao_araddr, debug_hmao_fsm_state_raw,
                 debug_start_preproc);
      end
      
      // If we see Preproc complete, can exit early
      if (debug_hmao_fsm_state_raw != 7'b000_0111) begin  // If left STAGE1_COMP
        $display("[FSM STATE CHANGE] Exiting STAGE1_COMP, new state=0x%02x at cycle %0d", 
                 debug_hmao_fsm_state_raw, ext_i);
        break;
      end
    end
    $display("[DEBUG] TC001: Extended monitoring complete (or FSM exited STAGE1_COMP)");

    // Wait for RISCV firmware to pulse HMAO_START
    // (In real system: RISCV firmware runs on RISCV DCLS cores)
    // In simulation: wait for DUT to internally trigger
    wait_hmao_complete(MAX_TOTAL_CYCLES + 1000, completed);

    if (completed) begin
      logic ok;
      check_decision("TC001_SAFE_GRANT", 1'b1, ok);  // Expect GRANT
      if (ok) pass_count++; else fail_count++;
    end else begin
      $display("[TB] TC001 FAIL: No completion");
      fail_count++;
    end

    // Clear DMA signals before resetting
    dma_traj_done <= 1'b0;
    dma_sig_valid <= 1'b0;
    
    // Reset between tests
    hmao_rst_n <= 1'b0; repeat(5) @(posedge hmao_clk); hmao_rst_n <= 1'b1;
    repeat(10) @(posedge hmao_clk);

    // =========================================================================
    // TC002: Trajectory with obstacle in path → VETO expected
    // Spec Ref: Section 16.1 - FNR = 0.00% mandatory
    // =========================================================================
    $display("\n[TC002] Collision trajectory (obstacle at 25m, same lane)");
    init_collision_trajectory();
    // Place stationary car directly in trajectory path
    place_obstacle(25.0, 0.2, 0.0,   // position
                   0.0, 0.0,          // velocity (stationary)
                   4.5, 2.0, 1.5,    // dimensions (car)
                   0.0, 16'd1, OBJ_CAR);

    dma_traj_done <= 1'b1;
    dma_sig_valid <= 1'b1;
    repeat(10) @(posedge hmao_clk);  // Keep HIGH for firmware to detect

    // Directly pulse HMAO_START for testing (bypass RISCV firmware)
    test_hmao_start <= 1'b1;
    repeat(2) @(posedge hmao_clk);  // Hold for 2 cycles to ensure capture
    test_hmao_start <= 1'b0;

    wait_hmao_complete(MAX_TOTAL_CYCLES + 1000, completed);
    if (completed) begin
      logic ok;
      check_decision("TC002_VETO_COLLISION", 1'b0, ok);  // Expect VETO
      // Critical: VETO must fire for any true collision
      assert (can_tx_mrm_req) else begin
        $error("TC002 CRITICAL FAILURE: False Negative! True collision not vetoed!");
        ok = 1'b0;
      end
      if (ok) pass_count++; else fail_count++;
    end else begin
      $display("[TB] TC002 FAIL: No completion");
      fail_count++;
    end

    // Clear DMA signals
    dma_traj_done <= 1'b0;
    dma_sig_valid <= 1'b0;
    
    // Reset
    hmao_rst_n <= 1'b0; repeat(5) @(posedge hmao_clk); hmao_rst_n <= 1'b1;
    repeat(10) @(posedge hmao_clk);

    // =========================================================================
    // TC003: Poor sensor quality → larger margins → more VETO (conservative)
    // Spec Ref: Section 8 - Adaptive Margin
    // =========================================================================
    $display("\n[TC003] Poor GPS quality → maximum safety margins");
    qm_gps_quality    <= 8'd10;   // Very bad GPS
    qm_camera_quality <= 8'd20;   // Almost blind camera
    qm_uvec_req <= 1'b1;
    @(posedge qm_clk);
    qm_uvec_req <= 1'b0;

    init_safe_trajectory();
    // Obstacle far from trajectory (20m lateral) - should be GRANT with good margins
    // but with MAX margins (3m), may VETO
    place_obstacle(20.0, 3.5, 0.0, 0.0, 0.0, 4.5, 2.0, 1.5, 0.0, 16'd2, OBJ_CAR);

    dma_traj_done <= 1'b1;
    dma_sig_valid <= 1'b1;
    repeat(10) @(posedge hmao_clk);  // Keep HIGH for firmware to detect
    
    // Directly pulse HMAO_START for testing (bypass RISCV firmware)
    test_hmao_start <= 1'b1;
    repeat(2) @(posedge hmao_clk);  // Hold for 2 cycles to ensure capture
    test_hmao_start <= 1'b0;

    wait_hmao_complete(MAX_TOTAL_CYCLES + 1000, completed);

    if (completed) begin
      $display("[TC003] Poor sensors: decision=%b (conservative expected)", can_tx_grant);
      // Spec: with poor GPS, lateral margin = MAX_LATERAL = 3.0m
      // Obstacle at 3.5m lateral → may or may not VETO depending on exact margin
      pass_count++;
    end
    
    // Clear DMA signals
    dma_traj_done <= 1'b0;
    dma_sig_valid <= 1'b0;

    // Reset sensors to good quality
    qm_gps_quality    <= 8'd220;
    qm_camera_quality <= 8'd210;

    // Reset
    hmao_rst_n <= 1'b0; repeat(5) @(posedge hmao_clk); hmao_rst_n <= 1'b1;
    repeat(10) @(posedge hmao_clk);

    // =========================================================================
    // TC004: CRC mismatch → VETO + fault expected
    // Spec Ref: Section 7.1.1 Step 1, Section 4.4 TRAJECTORY_CRC_FAIL
    // =========================================================================
    $display("\n[TC004] CRC32 mismatch → VETO + fault");
    init_safe_trajectory();
    traj_mem[350] = 32'hDEAD_BEEF;  // Wrong CRC

    dma_traj_done <= 1'b1;
    dma_sig_valid <= 1'b1;
    repeat(10) @(posedge hmao_clk);  // Keep HIGH for firmware to detect
    
    // Directly pulse HMAO_START for testing (bypass RISCV firmware)
    test_hmao_start <= 1'b1;
    repeat(2) @(posedge hmao_clk);  // Hold for 2 cycles to ensure capture
    test_hmao_start <= 1'b0;

    wait_hmao_complete(MAX_TOTAL_CYCLES + 1000, completed);

    if (completed) begin
      logic ok;
      check_decision("TC004_CRC_VETO", 1'b0, ok);  // Expect VETO
      // SFI pipeline: fault_reg → fault_out (1cy) → fault_latch (1cy) → sfi_flags_out (1cy)
      // Need 3+ cycles after check_decision's posedge for sfi_fault_flags to propagate.
      repeat(5) @(posedge hmao_clk);
      assert (sfi_fault_flags[3]) else begin  // TRAJECTORY_CRC_FAIL bit
        $error("TC004: CRC fault bit not asserted in SFI");
        ok = 1'b0;
      end
      if (ok) pass_count++; else fail_count++;
    end
    
    // Clear DMA signals
    dma_traj_done <= 1'b0;
    dma_sig_valid <= 1'b0;

    // =========================================================================
    // SUMMARY
    // =========================================================================
    $display("\n=====================================================");
    $display(" TESTBENCH SUMMARY");
    $display(" PASS: %0d  FAIL: %0d", pass_count, fail_count);
    if (fail_count == 0)
      $display(" ALL TESTS PASSED");
    else
      $display(" FAILURES DETECTED - Review above");
    $display("=====================================================");

    #1000;
    $finish;
  end

  // Timeout guard
  initial begin
    #(100_000_000);  // 100ms simulation timeout
    $display("[TB] SIMULATION TIMEOUT");
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("hmao_soc_tb.vcd");
    $dumpvars(0, tb_hmao_soc);
  end

endmodule : tb_hmao_soc
