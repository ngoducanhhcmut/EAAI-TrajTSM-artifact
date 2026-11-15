# HMAO Firmware Integration Test Suite

## Overview

This firmware provides a complete RISC-V RV32IM test suite for verifying HMAO module functionality at the software level. It tests the interaction between the RISC-V CPU and HMAO hardware via memory-mapped I/O (MMIO).

## Test Functions

| Test | Function | Purpose | Assertions |
|------|----------|---------|-----------|
| **TEST_001** | `test_001_register_interface()` | MMIO read/write to control/status registers | 6 |
| **TEST_002** | `test_002_memory_access()` | Read trajectory buffer and 8MB world model | 6 |
| **TEST_003** | `test_003_crc32_validation()` | CRC32 checksum computation and validation | 6 |
| **TEST_004** | `test_004_adaptive_margin()` | Dynamic safety margin scaling | 6 |
| **TEST_005** | `test_005_full_integration()` | Complete pipeline execution (all modules) | 6 |
| | | **TOTAL:** | **~30** |

## Building the Firmware

### Prerequisites

Install RISC-V cross-compiler:

```bash
# Option 1: Download pre-built binaries (recommended)
# https://github.com/riscv-collab/riscv-gnu-toolchain/releases
# Extract and add to PATH

# Option 2: Build from source (takes ~30 minutes)
git clone https://github.com/riscv-collab/riscv-gnu-toolchain.git
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32im
make -j$(nproc)
export PATH=/opt/riscv/bin:$PATH
```

Verify installation:
```bash
riscv32-unknown-elf-gcc --version
riscv32-unknown-elf-objdump --version
```

### Build Firmware

```bash
cd sim/firmware_integration_tests/firmware/

# Build all formats (ELF, HEX, binary, listing)
make firmware

# Clean previous build
make clean

# Rebuild from scratch
make clean && make firmware

# Show firmware details
make info

# Generate assembly listing
make disasm

# Show firmware size
make size
```

### Output Files

After building, check the `build/` directory:

```
build/
├── hmao_integration_test.elf       Executable (with debug symbols)
├── hmao_integration_test.hex       Intel HEX format (for memory loader)
├── hmao_integration_test.bin       Raw binary image
├── hmao_integration_test.lst       Disassembly + source code
└── firmware.map                    Link map with symbol addresses
```

## Test Details

### TEST_001: Register Interface

**Objective:** Verify MMIO reads/writes to HMAO control registers

**Test Cases:**
```
TEST_001.1  - Read status register
TEST_001.2  - Write and read margin register (verify write sticks)
TEST_001.3  - Control register default state
TEST_001.4  - Test ID register writable
TEST_001.5  - Sequential reads consistent
TEST_001.6  - Error flags register readable
```

**Register Map Tested:**
```
HMAO_CTRL           0x00    Control (RW)
HMAO_STATUS         0x04    Status (RO)
HMAO_MARGIN         0x0C    Safety margin (RW)
HMAO_TEST_ID        0x24    Test ID (RW)
HMAO_ERROR_FLAGS    0x14    Error flags (RO)
```

### TEST_002: Memory Access

**Objective:** Verify CPU can read trajectory and world model data

**Test Cases:**
```
TEST_002.1  - Read trajectory buffer base
TEST_002.2  - Read world model base
TEST_002.3  - Read safety data region
TEST_002.4  - Sequential trajectory reads
TEST_002.5  - World model object access
TEST_002.6  - DMEM write/read
```

**Memory Regions Tested:**
```
TRAJECTORY_BUFFER   0x80300000  (64KB READ-ONLY)
WORLD_MODEL         0x80400000  (8MB READ-ONLY)
SAFETY_DATA         0x80200000  (1MB READ-ONLY)
DMEM                0x10000000  (256KB R/W)
```

### TEST_003: CRC32 Validation

**Objective:** Verify CRC32 computation for data integrity checking

**Test Cases:**
```
TEST_003.1  - CRC32 of empty data
TEST_003.2  - CRC32 of known data pattern ('123')
TEST_003.3  - CRC32 deterministic (same input = same output)
TEST_003.4  - Different data produces different CRC
TEST_003.5  - HMAO CRC register matches computed CRC
TEST_003.6  - CRC validation flag (no errors)
```

**CRC32 Parameters:**
```
Polynomial:  0xEDB88320 (reversed)
Initial:     0xFFFFFFFF
Final XOR:   0xFFFFFFFF
RefIn:       True
RefOut:      True
```

### TEST_004: Adaptive Margin Scaling

**Objective:** Verify dynamic safety margin adjustment based on confidence

**Test Cases:**
```
TEST_004.1  - Set margin to low value (100mm)
TEST_004.2  - Set margin to high value (1000mm)
TEST_004.3  - Enable dynamic margin scaling
TEST_004.4  - Confidence level query
TEST_004.5  - Margin adapts with confidence
TEST_004.6  - Disable dynamic margin
```

**Safety Margin Scaling:**
- Low confidence → Larger margin (conservative)
- High confidence → Smaller margin (aggressive)
- Range: 50mm (min) to 5000mm (max)

### TEST_005: Full Integration

**Objective:** Verify complete HMAO pipeline execution

**Test Cases:**
```
TEST_005.1  - HMAO module ready after reset
TEST_005.2  - Enable all features (margin, CRC, test mode)
TEST_005.3  - Start computation and execute
TEST_005.4  - Latency within ASIL-D budget (< 7ms)
TEST_005.5  - No errors detected after completion
TEST_005.6  - Final GRANT/VETO decision
```

**Expected Timeline:**
```
Reset           0.0ms
PreProcessor    0.5ms
Zonotope Gen    1.5ms
Collision Det   2.0ms
ADMM Solve      2.0ms
─────────────────────
TOTAL          ~4-7ms (within ASIL-D 10ms bound)
```

## Memory Map

### RISC-V Memory Layout

```
IMEM (Instruction Memory)
  0x00000000  Program code (64KB)
  0x0000FFFF  

DMEM (Data Memory)
  0x10000000  Data segment
  0x10000000  Heap (8KB)
  0x10002000  Stack (grows down)
  0x1003FFFF  (256KB total)

Peripheral Memory
  0x80200000  Safety data (1MB)
  0x80300000  Trajectory buffer (64KB)
  0x80400000  World model (8MB)
  0xA4100000  HMAO control registers (64KB)
```

### HMAO Register Map

```
Offset  Register Name           Type    Purpose
─────────────────────────────────────────────────────────
0x00    HMAO_CTRL              RW      Control control bits
0x04    HMAO_STATUS            RO      Module status flags
0x08    HMAO_DECISION          RO      GRANT(0x01) / VETO(0x00)
0x0C    HMAO_MARGIN            RW      Safety margin (mm)
0x10    HMAO_CONFIDENCE        RO      Confidence level
0x14    HMAO_ERROR_FLAGS       RO      Error status bits
0x18    HMAO_CRC_RESULT        RO      CRC32 result
0x1C    HMAO_READY             RO      Ready/Busy flag
0x20    HMAO_LATENCY           RO      Computation latency (us)
0x24    HMAO_TEST_ID           RW      Test ID for tracking
0x28    HMAO_FMU_OUTPUT        RO      FMU/VETO signal
0x2C    HMAO_CDC_STATUS        RO      CDC quality Q_m
0x30    HMAO_ADMM_ITER         RO      ADMM iterations
```

## Integration with Testbench

### Current State

The main testbench (`tb_hmao_soc.sv`) currently **bypasses the RISC-V CPU** and directly pulses the `HMAO_START` signal. To enable firmware testing:

### 1. Create RISC-V CPU with IMEM Loader

Modify `tb_hmao_soc.sv`:

```systemverilog
// Before: direct HMAO control
// hmao_engine_inst.hmao_start <= 1'b1;

// After: Let firmware control via CPU
reg [31:0] imem [0:16383];   // 64KB instruction memory

initial begin
    // Load firmware HEX into IMEM
    $readmemh("firmware/build/hmao_integration_test.hex", imem);
    
    // CPU instruction fetches from IMEM
    // CPU can write to HMAO registers via memory map
end
```

### 2. Enable RISC-V CPU

```systemverilog
// Instantiate RISC-V processor (if not already present)
riscv_cpu #(
    .IMEM_ADDR(32'h0000_0000),
    .DMEM_ADDR(32'h1000_0000)
) cpu (
    .clk(clk),
    .rst(rst),
    .imem_data_o(imem_do),
    .imem_addr_o(imem_addr),
    .mmio_data_o(mmio_do),
    .mmio_addr_o(mmio_addr),
    .mmio_we(mmio_we)
);
```

### 3. Connect HMAO Control

```systemverilog
// RISC-V writes to MMIO address space
always @(posedge clk) begin
    if (mmio_we && mmio_addr >= 32'hA410_0000) begin
        case (mmio_addr)
            32'hA410_0000: hmao_ctrl <= mmio_do;      // CTRL
            32'hA410_000C: hmao_margin <= mmio_do;    // MARGIN
            // ... handle all write-able registers
        endcase
    end
end

// RISC-V reads from MMIO address space
always @(*) begin
    if (mmio_addr >= 32'hA410_0000) begin
        case (mmio_addr)
            32'hA410_0004: mmio_di = hmao_status;     // STATUS (RO)
            32'hA410_0008: mmio_di = hmao_decision;   // DECISION (RO)
            32'hA410_0014: mmio_di = hmao_error_flags;// ERROR FLAGS (RO)
            // ... handle all read-able registers
        endcase
    end
end
```

### 4. Run Simulation with Firmware

```bash
cd sim/
vsim -c do "vlog tb/tb_hmao_soc.sv; run -all; quit"
```

## Debugging

### View Assembly Code

```bash
cd firmware/
make disasm
cat build/hmao_integration_test.lst | head -100
```

### Check Symbol Addresses

```bash
riscv32-unknown-elf-nm -n build/hmao_integration_test.elf
```

### Get Firmware Info

```bash
riscv32-unknown-elf-readelf -h build/hmao_integration_test.elf
riscv32-unknown-elf-readelf -s build/hmao_integration_test.elf
```

### Generate Hex Dump

```bash
riscv32-unknown-elf-objdump -s -j .text build/hmao_integration_test.elf
```

## Performance Metrics

### Code Size

```
Typical Size: 8-12 KB ELF
- .text (code):     4-6 KB
- .rodata (data):   2-3 KB
- .data (init):     1-2 KB
- .bss (uninit):    1 KB
```

### Execution Time

```
TEST_001: Register Interface      ~2 ms
TEST_002: Memory Access            ~3 ms
TEST_003: CRC32 (5 samples)         ~1 ms
TEST_004: Adaptive Margin          ~15 ms
TEST_005: Full Integration        ~25 ms
─────────────────────────────────────
TOTAL:                           ~45 ms
```

### Simulation Performance

```
With 400 MHz clock (2.5ns period):
- 45ms firmware execution
- ≈ 18 million clock cycles
- Typical sim time: 5-10 seconds (varies by simulator)
```

## Files

```
firmware/
├── Makefile                         Build configuration
├── hmao_integration_test.c          Main test code (500+ lines)
├── hmao_integration_test.h          Register definitions & structures
├── boot.s                           RISC-V startup assembly
├── linker_script.ld                 Memory layout configuration
└── build/                           Build output (after make)
    ├── hmao_integration_test.elf
    ├── hmao_integration_test.hex
    ├── hmao_integration_test.bin
    ├── hmao_integration_test.lst
    └── firmware.map
```

## Troubleshooting

### Compiler Error: "riscv32-unknown-elf-gcc: not found"

**Solution:** Install RISC-V toolchain and add to PATH
```bash
export PATH=/opt/riscv/bin:$PATH
# or update .bashrc/.zshrc permanently
```

### Linker Error: "undefined reference to _start"

**Solution:** Check boot.s is in SOURCES in Makefile

### Memory Error: "Could not load firmware into IMEM"

**Solution:** Verify hex file format is correct
```bash
head -5 build/hmao_integration_test.hex
# Should show Intel HEX format: :10 followed by hex data
```

### Simulation Hangs

**Solution:** Check that CPU reset is released after firmware loads
```systemverilog
// In testbench:
initial begin
    rst = 1'b1;
    repeat(10) @(posedge clk);
    rst = 1'b0;  // Release reset to let CPU run firmware
end
```

## References

- RISC-V ISA Specification: https://riscv.org/technical/specifications/
- RISC-V System-on-Chip Implementation Guide
- HMAO Module Specification: [docs.txt](../../docs.txt)

---

**Last Updated:** 2024-12-20  
**Firmware Version:** 1.0  
**Test Coverage:** 30 assertions across 5 test functions

