# HMAO Engine - RISC-V Integration Test Firmware

## Overview

This firmware provides comprehensive integration tests for the HMAO (Hardware-Managed Assurance Offload) Engine, specifically testing the interactions between the RISC-V DCLS cores and various subsystems in the HMAO SoC.

## Test Structure

The test suite consists of **5 independent test modules**, each targeting specific module interactions:

### **Test 001: RISC-V ↔ HMAO Register Interface**
- **Location:** `test_001_register_interface()`
- **Purpose:** Verify RISC-V can read/write HMAO control registers
- **What it tests:**
  - HMAO_STATUS initial state (FSM idle)
  - HMAO_DECISION safe default (VETO=0)
  - HMAO_START pulse trigger
  - HMAO_STATUS BUSY bit (0x40)
  - HMAO_LATENCY_CYCLES accumulation

**Key Interaction:** RISC-V ↔ HMAO Register File via memory-mapped I/O

---

### **Test 002: RISC-V ↔ Trajectory Memory & CRC Validation**
- **Location:** `test_002_trajectory_memory()`
- **Purpose:** Verify trajectory buffer operations and CRC32 checksumming
- **What it tests:**
  - Trajectory buffer write (50 waypoints × 7 float32 fields = 1,400 bytes)
  - CRC32 computation and write at offset 0x0568
  - CRC32 read-back verification
  - Trajectory bounds validation (X, Y coordinates)

**Memory Layout (Trajectory Waypoint):**
```
Offset  Field           Type        Size
0x00    x               float32     4 bytes
0x04    y               float32     4 bytes
0x08    z               float32     4 bytes
0x0C    vx              float32     4 bytes
0x10    vy              float32     4 bytes
0x14    heading         float32     4 bytes
0x18    timestamp       float32     4 bytes
```

**Key Interaction:** RISC-V ↔ Trajectory Buffer Memory (0x8030_0000)

---

### **Test 003: RISC-V ↔ World Model Memory Access**
- **Location:** `test_003_world_model_memory()`
- **Purpose:** Verify world model object access and caching behavior
- **What it tests:**
  - World model base address validation
  - Write 8 sample obstacles with realistic properties
  - Read-back verification of object positions
  - Memory address mapping (64 bytes per object)
  - Capacity checks (8MB ÷ 64 bytes/object = 131,072 objects max)

**Memory Layout (World Model Object - 64 bytes):**
```
Byte Range  Field                   Type        Size
0-11        position[3]             float32×3   12 bytes
12-23       velocity[3]             float32×3   12 bytes
24-35       dimensions[3]           float32×3   12 bytes
36-39       heading                 float32     4 bytes
40-41       track_id                uint16      2 bytes
42          class                   uint8       1 byte
43          confidence              uint8       1 byte
44-63       predicted_trajectory    int16×10    20 bytes
```

**Key Interaction:** RISC-V ↔ World Model Buffer (0x8040_0000)

---

### **Test 004: RISC-V ↔ Adaptive Margin Controller (Quality Vector)**
- **Location:** `test_004_adaptive_margin()`
- **Purpose:** Test quality input registers and margin adaptation
- **What it tests:**
  - Write quality vector registers (GPS, Camera, Friction, Actuator)
  - Read and verify quality values
  - Weighted quality score computation
  - Adaptive margin calculation
  - Margin increase with degraded sensor quality

**Quality Vector Registers:**
```
Register            Offset  Width   Meaning
GPS_QUALITY         0x20    8-bit   0=bad, 255=excellent
CAMERA_QUALITY      0x24    8-bit   0=blind, 255=clear
ROAD_FRICTION       0x28    8-bit   0=icy, 255=grippy
ACTUATOR_HEALTH     0x2C    8-bit   0=degraded, 255=healthy
WEATHER_SEVERITY    0x30    8-bit   0=clear, 255=severe
```

**Margin Output Registers (Q8.8 fixed-point):**
```
LATERAL_MARGIN      0x34    16-bit  Q8.8 format (meters)
LONGITUDINAL_MARGIN 0x38    16-bit  Q8.8 format (meters)
TIME_MARGIN         0x3C    16-bit  Q8.8 format (seconds)
```

**Key Interaction:** RISC-V ↔ Adaptive Margin Controller + QM CDC (Quality Vector inputs)

---

### **Test 005: Full Integration Test (All Interactions)**
- **Location:** `test_005_full_integration()`
- **Purpose:** End-to-end verification of entire HMAO subsystem
- **What it tests:**
  - Quality vector set to good conditions
  - Trajectory population with valid kinematic data
  - CRC32 computation and installation
  - World model population with safe obstacles
  - HMAO_START pulse trigger
  - Completion polling (timeout = 100k cycles ≈ 0.25ms)
  - HMAO_DECISION verification
  - Violation flags interpretation (if VETO)
  - Latency measurement (should be < 7ms)
  - All margin registers readable

**Expected Behavior:**
- With safe trajectory and far-away obstacles → GRANT (decision=1)
- With valid trajectory but kinematic violation → VETO (decision=0) + violation flags
- Latency within bounded range: 200K–7M cycles @ 400MHz

**Key Interaction:** All subsystems working together

---

## Building the Firmware

### Prerequisites
- RISC-V toolchain: `riscv32-unknown-elf-gcc`, `riscv32-unknown-elf-ld`, etc.
- GNU make
- (Optional) Binutils for disassembly

### Build Steps

```bash
cd RISCV-RV32IM-Processor-main/firmware
make clean
make firmware
```

### Output Files
- `build/bin/hmao_integration_test.elf` - Executable ELF binary
- `build/bin/hmao_integration_test.bin` - Raw binary (for loading to memory)
- `build/bin/hmao_integration_test.hex` - Intel HEX format
- `build/bin/hmao_integration_test.lst` - Disassembly listing

### Verify Build
```bash
file build/bin/hmao_integration_test.elf
size build/bin/hmao_integration_test.elf
riscv32-unknown-elf-objdump -d build/bin/hmao_integration_test.elf | head -50
```

---

## Integration with Testbench (tb_hmao_soc.sv)

To integrate the firmware into the existing SystemVerilog testbench:

### 1. Load Firmware to RISC-V Instruction Memory

In `tb_hmao_soc.sv`, modify the memory initialization:

```systemverilog
// Load firmware binary into RISC-V instruction memory
initial begin
    $readmemh("path/to/hmao_integration_test.hex", tb_hmao_soc.u_dut.u_riscv_dcls.imem);
end
```

Or extend the testbench to use `$readmemb`:

```systemverilog
reg [31:0] firmware_image [0:16383];  // 64KB IMEM
initial begin
    $readmemh("../firmware/build/bin/hmao_integration_test.hex", firmware_image);
end
```

### 2. Boot RISC-V After Reset

Ensure the testbench allows RISC-V to run:

```systemverilog
// De-assert RISC-V reset  
hmao_rst_n = 1'b0;
#(20 * CLK_PERIOD_NS);
hmao_rst_n = 1'b1;

// Allow RISC-V to execute firmware
#(10_000_000 * CLK_PERIOD_NS);  // Wait for firmware to complete (~10ms simulation)
```

### 3. Monitor Test Output via Printf

The firmware uses `printf()` for test reporting. To capture output in simulation:

```systemverilog
// Example UVM or SystemVerilog monitor
task monitor_test_output();
    string line;
    forever begin
        // Check if RISC-V has output data on UART or debug port
        // (If using $display from firmware, output goes to simulator console)
        if (debug_riscv_halted) begin
            $display("[FIRMWARE COMPLETE] RISC-V halted");
            break;
        end
        #(100 * CLK_PERIOD_NS);
    end
endtask
```

### 4. Example Full Integration in Testbench

```systemverilog
module tb_hmao_soc;
    // ... existing code ...
    
    initial begin
        // 1. Load firmware
        $readmemh("../firmware/build/bin/hmao_integration_test.hex", 
                  u_riscv_dcls.imem);
        
        // 2. Apply reset
        hmao_rst_n = 1'b0;
        qm_rst_n = 1'b0;
        #(20 * CLK_PERIOD_NS);
        hmao_rst_n = 1'b1;
        qm_rst_n = 1'b1;
        
        // 3. Allow RISC-V firmware to run
        #(12_000_000 * CLK_PERIOD_NS);
        
        // 4. Check final test results (if using a register to store pass/fail count)
        $display("Test execution complete");
        $finish;
    end
    
endmodule
```

---

## Test Output Example

```
╔══════════════════════════════════════════════════════════════╗
║           HMAO Engine - RISC-V Integration Test Suite        ║
║                   Version 1.0 - ASIL-D                       ║
╚══════════════════════════════════════════════════════════════╝

========== TEST 001: RISC-V ↔ HMAO Register Interface ==========
[PASS] Test 1: HMAO_STATUS initial state (FSM should be idle)
[PASS] Test 2: HMAO_DECISION safe default (VETO)
[PASS] Test 3: HMAO_START write succeeded (no exception)
[PASS] Test 4: HMAO_STATUS shows BUSY after START pulse
[PASS] Test 5: HMAO_LATENCY_CYCLES > 0 (engine is running)

[TEST_001 SUMMARY] Passed: 5, Failed: 0

========== TEST 002: RISC-V ↔ Trajectory Memory & CRC ==========
[PASS] Test 6: Trajectory base address correct
[PASS] Test 7: Trajectory buffer written successfully
[PASS] Test 8: CRC32 computed and written to trajectory buffer
[PASS] Test 9: CRC32 read-back matches written value
[PASS] Test 10: Trajectory X bounds valid

[TEST_002 SUMMARY] Passed: 5, Failed: 0

========== TEST 003: RISC-V ↔ World Model Memory Access ==========
[PASS] Test 11: World model base address correct
[PASS] Test 12: 8 world model objects written successfully
[PASS] Test 13: World model object 0 position read-back correct
[PASS] Test 14: Object 7 position X correct
[PASS] Test 15: World model capacity verified

[TEST_003 SUMMARY] Passed: 5, Failed: 0

========== TEST 004: RISC-V ↔ Adaptive Margin Controller ==========
[PASS] Test 16: Quality vector registers written
[PASS] Test 17: Quality vector values read-back correctly
[PASS] Test 18: Combined quality score within valid range
[PASS] Test 19: Adaptive margins computed and readable
[PASS] Test 20: Lateral margin increases with poor quality sensor inputs

[TEST_004 SUMMARY] Passed: 5, Failed: 0

========== TEST 005: Full Integration Test ==========
[PASS] Test 21: Integration test started
[PASS] Test 22: Quality vector set to good conditions
[PASS] Test 23: Trajectory memory populated with valid data
[PASS] Test 24: World model populated with safe obstacle
[PASS] Test 25: HMAO_START pulse issued
[PASS] Test 26: HMAO computation completed within timeout
[PASS] Test 27: HMAO_DECISION output is valid (GRANT or VETO)
[PASS] Test 28: Violation flags populated if VETO decision
[PASS] Test 29: Latency within expected range (<7ms @ 400MHz)
[PASS] Test 30: All margin registers readable and non-zero

[TEST_005 SUMMARY] Passed: 10, Failed: 0

╔══════════════════════════════════════════════════════════════╗
║                     FINAL TEST SUMMARY                       ║
╠══════════════════════════════════════════════════════════════╣
║ Total Tests:  30                                             ║
║ Passed:       30                                             ║
║ Failed:       0                                              ║
║                                                              ║
║            ✓ ALL TESTS PASSED - SYSTEM VERIFIED ✓            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

## Memory Safety & ASIL-D Compliance

### Key Design Principles

1. **No Dynamic Allocation** - All buffers are statically allocated at known addresses
2. **Bounded Loops** - All loops have explicit iteration counts (no infinite loops)
3. **CRC Validation** - Trajectory integrity verified via CRC32
4. **Register Protection** - HMAO registers are read-only where applicable
5. **Safe Defaults** - HMAO_DECISION defaults to VETO (fail-safe)

### Register Access Patterns

- **Read-Only Registers:** `HMAO_DECISION`, `HMAO_VIOLATION_*`, `HMAO_LATENCY_CYCLES`, margins
- **Write-Only Registers:** `HMAO_START`, quality vector registers
- **Read-Write Registers:** `HMAO_STATUS`, `HMAO_IRQ_CLEAR`

---

## Firmware Memory Layout

```
IMEM (0x0000_0000 - 0x0000_FFFF):  64 KB Instruction Memory
  └─ .text.init     (0x0000_0000)  Entry point (_start)
  └─ .text          (0x0000_0010)  Main test code
  └─ .rodata        (...)           CRC lookup tables, strings

DMEM (0x1000_0000 - 0x1004_FFFF): 256 KB Data Memory
  └─ .data          (0x1000_0000)  Initialized globals
  └─ .bss           (...)           Uninitialized globals
  └─ Stack          (0x1003_FFFF)   Grows downward
```

---

## Troubleshooting

### Issue: "Firmware not running after reset"
- **Check:** RISC-V reset sequence (hmao_rst_n must be asserted then de-asserted)
- **Check:** Instruction memory is loaded before reset release
- **Check:** Stack pointer is set correctly in `boot.s`

### Issue: "CRC32 mismatch"
- **Check:** Trajectory buffer write order (0x0000-0x056B for data, 0x0568 for CRC)
- **Check:** CRC polynomial (should be 0x04C11DB7 for IEEE 32-bit)

### Issue: "HMAO_DECISION always VETO"
- **Check:** Trajectory waypoints are reasonable (no NaN, Inf, or huge values)
- **Check:** Kinematic feasibility (acceleration, yaw rate constraints)
- **Check:** World model obstacles don't intersect trajectory

### Issue: "Simulation timeout (firmware hangs)"
- **Check:** HMAO engine is responding (HMAO_STATUS BUSY bit)
- **Check:** Timeout threshold in Test 005 is large enough (100k+ cycles)
- **Check:** No infinite loops in C code

---

## Extending the Test Suite

To add new tests:

1. Create a new function `test_00X_<description>(void)`
2. Use `TEST_ASSERT()` macro for pass/fail conditions
3. Call it from `hmao_run_all_tests()`
4. Update documentation with test description

Example:
```c
void test_006_custom_test(void) {
    printf("\n========== TEST 006: Custom Test ==========\n");
    
    uint32_t value = mmio_read32(SOME_REGISTER);
    TEST_ASSERT(value == 0x12345678, "Custom assertion message");
    
    printf("\n[TEST_006 SUMMARY] Passed: %u, Failed: %u\n", 
           test_stats.pass_count, test_stats.fail_count);
}
```

---

## References

- **HMAO Engine Specification:** `docs.txt` (Section 2-8)
- **RISC-V ISA:** RV32IM (32-bit RISC-V with Multiply extension)
- **SoC Top Module:** `hmao_soc_top.sv`
- **Testbench:** `tb_hmao_soc.sv`

---

## License & Safety

This firmware is part of the HMAO Engine project and is subject to ASIL-D (ISO 26262) safety requirements. All modifications must maintain:
- **Zero false negatives** in collision detection
- **Bounded latency** (≤7ms per verification)
- **Fail-safe defaults** (VETO on any error)

---

## Author & Contact

- **Project:** HMAO Engine - Hardware Safety Verification
- **Version:** Firmware v1.0
- **Date:** 2026-03-04
