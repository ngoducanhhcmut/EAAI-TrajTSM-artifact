// =============================================================================
// FILE        : test_hmao_error_paths.sv
// PROJECT     : HMAO Engine - Hardware Integration Tests
// DESCRIPTION : Test error detection and fail-safe behavior across all paths
//               CRC failures, kinematic violations, numerical errors, etc.
//
// TEST OBJECTIVES:
//   HW_INT_301: CRC32 mismatch → immediate VETO + fault
//   HW_INT_302: Kinematic violation (speed > 35m/s) → VETO
//   HW_INT_303: Numerical overflow → VETO + overflow flag
//   HW_INT_304: Watchdog timeout → MRM trigger + fault
//   HW_INT_305: SMPU violation → access denied, no corruption
//   HW_INT_306: All faults propagate to FMU (fault interface)
//
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module test_hmao_error_paths;

  parameter real CLK_PERIOD = 2.5;
  
  logic clk = 0;
  logic rst_n = 0;
  
  // Input signals
  logic [31:0]  trajectory_crc_received;
  logic [31:0]  trajectory_crc_computed;
  logic         crc_mismatch;
  
  logic [31:0]  waypoint_velocity;
  logic         kinematic_error;
  
  logic         numerical_overflow;
  logic         numerical_underflow;
  
  logic         watchdog_timeout;
  logic         mrm_triggered;
  
  logic [31:0]  smpu_access_addr;
  logic         smpu_access_valid;
  logic         smpu_access_denied;
  
  // Fault output
  logic [6:0]   fault_flags;
  logic         fault_valid;
  logic         fault_ack;
  
  // Status
  logic         hmao_halted;
  logic [2:0]   engine_state;
  
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;
  
  always #(CLK_PERIOD/2) clk = ~clk;
  
  task test_assert(logic condition, string message);
    test_count++;
    if (condition) begin
      pass_count++;
      $display("[PASS] HW_INT_%03d: %s", 300 + test_count, message);
    end else begin
      fail_count++;
      $display("[FAIL] HW_INT_%03d: %s", 300 + test_count, message);
    end
  endtask
  
  // =========================================================================
  // TEST HW_INT_301: CRC32 Mismatch Error
  // =========================================================================
  
  task test_301_crc_mismatch_error();
    $display("\n========== HW_INT_301: CRC32 Mismatch Error ==========\n");
    
    rst_n <= 0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    
    // Simulation: CRC computed from trajectory data doesn't match header
    trajectory_crc_received <= 32'hDEADBEEF;
    trajectory_crc_computed <= 32'hCAFEBABE;  // Different!
    crc_mismatch <= 1;
    @(posedge clk);
    crc_mismatch <= 0;
    
    // Wait for fault detection
    repeat(1000) @(posedge clk);
    
    // Should immediately set TRAJECTORY_CRC_FAIL fault (bit 3)
    test_assert((fault_flags & 7'b0001000) != 0,
                "CRC mismatch triggers TRAJECTORY_CRC_FAIL fault");
    
    test_assert(fault_valid, "Fault immediately reported to FMU");
    test_assert(hmao_halted, "Engine halts on CRC error");
    
  endtask
  
  // =========================================================================
  // TEST HW_INT_302: Kinematic Violation
  // =========================================================================
  
  task test_302_kinematic_violation();
    $display("\n========== HW_INT_302: Kinematic Violation Error ==========\n");
    
    rst_n <= 0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    
    // Inject velocity exceeding limit (35 m/s)
    waypoint_velocity <= 32'h41900000;  // 40.0 m/s in IEEE 754 float
    kinematic_error <= 1;
    @(posedge clk);
    kinematic_error <= 0;
    
    repeat(1000) @(posedge clk);
    
    // Should set KINEMATIC_INVALID fault (bit 6)
    test_assert((fault_flags & 7'b1000000) != 0,
                "Speed > 35m/s triggers KINEMATIC_INVALID fault");
    
    test_assert(fault_valid, "Kinematic violation reported");
    test_assert(hmao_halted, "Engine prevents execution on kinematic error");
    
  endtask
  
  // =========================================================================
  // TEST HW_INT_303: Numerical Overflow Protection
  // =========================================================================
  
  task test_303_numerical_overflow();
    $display("\n========== HW_INT_303: Numerical Overflow Protection ==========\n");
    
    rst_n <= 0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    
    // Simulation: Overflow detected in zonotope computation
    numerical_overflow <= 1;
    @(posedge clk);
    numerical_overflow <= 0;
    
    repeat(1000) @(posedge clk);
    
    // Should set NUMERICAL_OVERFLOW fault (bit 5)
    test_assert((fault_flags & 7'b0100000) != 0,
                "Arithmetic overflow triggers NUMERICAL_OVERFLOW fault");
    
    // VETO decision should be forced
    test_assert(fault_valid, "Overflow fault reported immediately");
    
  endtask
  
  // =========================================================================
  // TEST HW_INT_304: Watchdog Timeout Safety
  // =========================================================================
  
  task test_304_watchdog_timeout();
    $display("\n========== HW_INT_304: Watchdog Timeout & MRM Trigger ==========\n");
    
    rst_n <= 0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    
    // After 7ms timeout with no completion, watchdog fires
    repeat(2_800_000) @(posedge clk);  // 7ms worth of cycles
    
    watchdog_timeout <= 1;
    @(posedge clk);
    watchdog_timeout <= 0;
    
    // Should trigger MRM immediately
    test_assert(mrm_triggered, "Watchdog timeout triggers MRM");
    
    // Should also set fault
    test_assert((fault_flags & 7'b0000001) != 0,
                "HMAO_HANG fault set on timeout");
    
    test_assert(hmao_halted, "Engine halted on watchdog timeout");
    
  endtask
  
  // =========================================================================
  // TEST HW_INT_305: SMPU Access Violation
  // =========================================================================
  
  task test_305_smpu_violation();
    $display("\n========== HW_INT_305: SMPU Access Violation Protection ==========\n");
    
    rst_n <= 0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    
    // Attempt write to trajectory buffer (READ-ONLY) at 0x8030_XXXX
    smpu_access_addr <= 32'h8030_0100;  // Trajectory buffer
    smpu_access_valid <= 1;  // Write request
    @(posedge clk);
    
    // SMPU should deny access
    test_assert(smpu_access_denied, "SMPU denies write to READ-ONLY trajectory buffer");
    
    // Should set fault
    test_assert((fault_flags & 7'b0010000) != 0,
                "SMPU_VIOLATION fault set");
    
    smpu_access_valid <= 0;
    @(posedge clk);
    
  endtask
  
  // =========================================================================
  // TEST HW_INT_306: Fault Propagation to FMU
  // =========================================================================
  
  task test_306_fault_propagation();
    $display("\n========== HW_INT_306: Fault Propagation to FMU (SFI) ==========\n");
    
    rst_n <= 0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    
    // Generate multiple fault types (accumulate)
    crc_mismatch <= 1;
    @(posedge clk);
    crc_mismatch <= 0;
    
    repeat(100) @(posedge clk);
    
    kinematic_error <= 1;
    @(posedge clk);
    kinematic_error <= 0;
    
    repeat(100) @(posedge clk);
    
    // Both faults should be OR'd together in fault_flags
    test_assert((fault_flags & 7'b1001000) == 7'b1001000,
                "Multiple faults accumulated in fault_flags");
    
    // FMU ack should eventually clear stubs
    fault_ack <= 1;
    @(posedge clk);
    fault_ack <= 0;
    
    repeat(100) @(posedge clk);
    
    test_assert(fault_valid, "FMU acknowledges fault receipt");
    
  endtask
  
  initial begin
    $display("\n╔════════════════════════════════════════════════════════════════╗");
    $display("║  HMAO Hardware Error Path Test Suite                          ║");
    $display("║  Testing: Fault Detection, Safety Fail-Safes, FMU Reporting   ║");
    $display("╚════════════════════════════════════════════════════════════════╝\n");
    
    test_301_crc_mismatch_error();
    test_302_kinematic_violation();
    test_303_numerical_overflow();
    test_304_watchdog_timeout();
    test_305_smpu_violation();
    test_306_fault_propagation();
    
    $display("\n╔════════════════════════════════════════════════════════════════╗");
    $display("║                     TEST SUMMARY                              ║");
    $display("╠════════════════════════════════════════════════════════════════╣");
    $display("║ Total Tests:  %0d                                              ║", test_count);
    $display("║ Passed:       %0d                                              ║", pass_count);
    $display("║ Failed:       %0d                                              ║", fail_count);
    $display("╚════════════════════════════════════════════════════════════════╝\n");
    
    $finish;
  end

endmodule
