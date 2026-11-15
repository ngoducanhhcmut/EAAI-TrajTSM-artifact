/*=============================================================================
 * FILE        : hmao_integration_test.h
 * PROJECT     : HMAO Engine - Firmware Integration Test Suite
 * DESCRIPTION : Header file with register definitions, memory map, and
 *               helper function declarations for RISC-V firmware testing
 *
 * ARCH        : RISC-V RV32IM (32-bit with Multiply extension)
 * CLOCK       : 400 MHz (HMAO clock domain)
 * MEMORY      : 64KB IMEM + 256KB DMEM
 *
 * REGISTER BASE: 0xA410_0000 (HMAO control registers, 64KB space)
 *
 * TEST COVERAGE:
 *   • TEST_001: Register Interface (MMIO read/write)
 *   • TEST_002: Memory Access (trajectory buffer, world model)
 *   • TEST_003: CRC32 Validation
 *   • TEST_004: Adaptive Margin Scaling
 *   • TEST_005: Full Integration
 *
 *=============================================================================*/

#ifndef HMAO_INTEGRATION_TEST_H
#define HMAO_INTEGRATION_TEST_H

#include <stdint.h>
#include <string.h>

/* =============================================================================
 * MEMORY MAP
 * =============================================================================*/

/* RISC-V Memory Layout */
#define IMEM_BASE           0x00000000      // Instruction Memory (64KB)
#define IMEM_SIZE           0x10000
#define DMEM_BASE           0x10000000      // Data Memory (256KB)
#define DMEM_SIZE           0x40000

/* HMAO Engine Memory Map */
#define HMAO_BASE           0xA4100000      // Control registers (64KB)
#define HMAO_SIZE           0x10000

/* Input Data Memory */
#define TRAJECTORY_BUFFER   0x80300000      // Trajectory buffer (READ-ONLY, 64KB)
#define WORLD_MODEL         0x80400000      // World model (READ-ONLY, 8MB)
#define SAFETY_DATA         0x80200000      // Safety data (READ-ONLY, 1MB)

/* =============================================================================
 * REGISTER DEFINITIONS (HMAO)
 * =============================================================================*/

/* Register Offset from HMAO_BASE */
#define HMAO_CTRL           0x00            // Control Register (RW)
#define HMAO_STATUS         0x04            // Status Register (RO)
#define HMAO_DECISION       0x08            // GRANT/VETO Decision (RO)
#define HMAO_MARGIN         0x0C            // Safety Margin Value (RW)
#define HMAO_CONFIDENCE     0x10            // Confidence Level (RO)
#define HMAO_ERROR_FLAGS    0x14            // Error Flags (RO)
#define HMAO_CRC_RESULT     0x18            // CRC32 Result (RO)
#define HMAO_READY          0x1C            // Ready/Busy Flag (RO)
#define HMAO_LATENCY        0x20            // Computation Latency (RO)
#define HMAO_TEST_ID        0x24            // Test ID Register (RW)
#define HMAO_FMU_OUTPUT     0x28            // FMU/VETO Output (RO)
#define HMAO_CDC_STATUS     0x2C            // CDC Quality Vector Status (RO)
#define HMAO_ADMM_ITER      0x30            // ADMM Iterations (RO)

/* HMAO_CTRL Bits */
#define CTRL_START          (1 << 0)        // Start computation
#define CTRL_SOFT_RESET     (1 << 1)        // Software reset
#define CTRL_ENABLE_MARGIN  (1 << 2)        // Enable dynamic margin
#define CTRL_CRC_EN         (1 << 3)        // Enable CRC validation
#define CTRL_TEST_MODE      (1 << 4)        // Enable test mode

/* HMAO_STATUS Bits */
#define STATUS_READY        (1 << 0)        // Module ready
#define STATUS_BUSY         (1 << 1)        // Computation in progress
#define STATUS_DONE         (1 << 2)        // Computation done
#define STATUS_ERROR        (1 << 3)        // Error detected

/* HMAO_DECISION Values */
#define DECISION_GRANT      0x01            // Safe - proceed (GRANT)
#define DECISION_VETO       0x00            // Unsafe - stop (VETO)

/* Error Flags (HMAO_ERROR_FLAGS) */
#define ERR_CRC_FAIL        (1 << 0)        // CRC validation failed
#define ERR_KINEMATIC       (1 << 1)        // Kinematic constraint error
#define ERR_NUMERICAL       (1 << 2)        // Numerical stability error
#define ERR_TIMEOUT         (1 << 3)        // Watchdog timeout
#define ERR_SMPU            (1 << 4)        // SMPU parity error
#define ERR_CDC             (1 << 5)        // CDC metastability error
#define ERR_ADMM_DIV        (1 << 6)        // ADMM divergence error

/* =============================================================================
 * DATA STRUCTURES
 * =============================================================================*/

/* Trajectory Waypoint (3D position) */
typedef struct {
    int32_t x;                              // X position (mm)
    int32_t y;                              // Y position (mm)
    int32_t z;                              // Z position (mm)
} trajectory_waypoint_t;

/* World Model Object */
typedef struct {
    uint32_t id;                            // Object ID
    int32_t x, y, z;                        // Position (mm)
    uint32_t radius;                        // Bounding sphere radius (mm)
} world_model_object_t;

/* Test Result Structure */
typedef struct {
    uint32_t test_num;                      // Test number (1-5)
    uint32_t assertions_pass;               // Passed assertions
    uint32_t assertions_fail;               // Failed assertions
    uint32_t exec_time_us;                  // Execution time (microseconds)
    uint8_t  status;                        // PASS/FAIL
} test_result_t;

/* HMAO Register View (for easy access) */
typedef volatile struct {
    uint32_t ctrl;                          // 0x00
    uint32_t status;                        // 0x04
    uint32_t decision;                      // 0x08
    uint32_t margin;                        // 0x0C
    uint32_t confidence;                    // 0x10
    uint32_t error_flags;                   // 0x14
    uint32_t crc_result;                    // 0x18
    uint32_t ready;                         // 0x1C
    uint32_t latency;                       // 0x20
    uint32_t test_id;                       // 0x24
    uint32_t fmu_output;                    // 0x28
    uint32_t cdc_status;                    // 0x2C
    uint32_t admm_iter;                     // 0x30
} hmao_regs_t;

/* =============================================================================
 * FUNCTION DECLARATIONS
 * =============================================================================*/

/* Memory I/O Functions */
static inline uint32_t mmio_read32(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

static inline void mmio_write32(uint32_t addr, uint32_t value) {
    *(volatile uint32_t *)addr = value;
}

static inline uint8_t mmio_read8(uint32_t addr) {
    return *(volatile uint8_t *)addr;
}

static inline void mmio_write8(uint32_t addr, uint8_t value) {
    *(volatile uint8_t *)addr = value;
}

/* Wait Functions */
void wait_ready(void);
void wait_done(uint32_t timeout_ms);
void wait_ms(uint32_t ms);
void wait_us(uint32_t us);

/* CRC32 Computation */
uint32_t crc32_compute(const uint8_t *data, uint32_t length);

/* HMAO Register Access */
void hmao_reset(void);
void hmao_set_margin(uint32_t margin);
void hmao_start(void);
void hmao_wait_ready(void);
uint32_t hmao_get_decision(void);
uint32_t hmao_get_error_flags(void);
uint32_t hmao_get_latency(void);

/* Test Functions */
int test_001_register_interface(void);
int test_002_memory_access(void);
int test_003_crc32_validation(void);
int test_004_adaptive_margin(void);
int test_005_full_integration(void);

/* Utility Functions */
void put_char(char c);
void put_string(const char *s);
void put_hex32(uint32_t val);
void put_dec32(uint32_t val);
void init_uart(void);

/* Test Assert Macro */
#define TEST_ASSERT(condition, msg) \
    do { \
        if (condition) { \
            put_string("[PASS] "); \
            put_string(msg); \
            put_string("\r\n"); \
        } else { \
            put_string("[FAIL] "); \
            put_string(msg); \
            put_string("\r\n"); \
        } \
    } while(0)

#endif /* HMAO_INTEGRATION_TEST_H */
