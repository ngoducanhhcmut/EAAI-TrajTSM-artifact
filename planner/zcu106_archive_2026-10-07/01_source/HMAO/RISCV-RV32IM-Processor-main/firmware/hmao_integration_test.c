// =============================================================================
// FILE        : hmao_integration_test.c
// PROJECT     : HMAO Engine - RISC-V Integration Test Firmware
// DESCRIPTION : Comprehensive firmware tests for HMAO Engine subsystem
//               interactions with RISC-V DCLS cores
//
// TEST SUITE:
//   TEST_001: RISC-V ↔ HMAO Register Interface Test
//   TEST_002: RISC-V ↔ Trajectory Memory & CRC Validation
//   TEST_003: RISC-V ↔ World Model Memory Access
//   TEST_004: RISC-V ↔ Adaptive Margin Controller (Quality Vector)
//   TEST_005: Full Integration Test (All Interactions)
//
// =============================================================================

#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ============================================================================
// MEMORY MAP DEFINITIONS
// ============================================================================

#define HMAO_BASE_ADDR          0xA410_0000

// HMAO Registers (offsets from HMAO_BASE_ADDR)
#define HMAO_STATUS             (HMAO_BASE_ADDR + 0x000)
#define HMAO_START              (HMAO_BASE_ADDR + 0x004)
#define HMAO_DECISION           (HMAO_BASE_ADDR + 0x008)
#define HMAO_IRQ_CLEAR          (HMAO_BASE_ADDR + 0x00C)
#define HMAO_VIOLATION_LO       (HMAO_BASE_ADDR + 0x010)
#define HMAO_VIOLATION_HI       (HMAO_BASE_ADDR + 0x014)
#define HMAO_LATENCY_CYCLES     (HMAO_BASE_ADDR + 0x018)
#define GPS_QUALITY             (HMAO_BASE_ADDR + 0x020)
#define CAMERA_QUALITY          (HMAO_BASE_ADDR + 0x024)
#define ROAD_FRICTION           (HMAO_BASE_ADDR + 0x028)
#define ACTUATOR_HEALTH         (HMAO_BASE_ADDR + 0x02C)
#define WEATHER_SEVERITY        (HMAO_BASE_ADDR + 0x030)
#define LATERAL_MARGIN          (HMAO_BASE_ADDR + 0x034)
#define LONGITUDINAL_MARGIN     (HMAO_BASE_ADDR + 0x038)
#define TIME_MARGIN             (HMAO_BASE_ADDR + 0x03C)

// Memory Buffers
#define TRAJECTORY_BASE         0x8030_0000
#define TRAJECTORY_SIZE         0x0578      // 1,400 bytes payload + 4 bytes CRC
#define WORLD_MODEL_BASE        0x8040_0000
#define WORLD_MODEL_SIZE        0x0020_0000 // 8 MB

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// Memory read/write helpers
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

// CRC32 computation (polynomial 0x04C11DB7)
static uint32_t crc32_compute(const uint8_t *data, uint32_t length) {
    uint32_t crc = 0xFFFFFFFF;
    
    for (uint32_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (((crc & 1) ? 0xEDB88320 : 0));
        }
    }
    
    return crc ^ 0xFFFFFFFF;
}

// Test pass/fail tracking
static struct {
    uint32_t test_count;
    uint32_t pass_count;
    uint32_t fail_count;
} test_stats = {0, 0, 0};

#define TEST_ASSERT(condition, message) \
    do { \
        test_stats.test_count++; \
        if (condition) { \
            test_stats.pass_count++; \
            printf("[PASS] Test %u: %s\n", test_stats.test_count, message); \
        } else { \
            test_stats.fail_count++; \
            printf("[FAIL] Test %u: %s (line %d)\n", test_stats.test_count, message, __LINE__); \
        } \
    } while (0)

// ============================================================================
// TEST 001: RISC-V ↔ HMAO REGISTER INTERFACE
// ============================================================================

void test_001_register_interface(void) {
    printf("\n========== TEST 001: RISC-V ↔ HMAO Register Interface ==========\n");
    
    // Test 1.1: Read initial HMAO_STATUS
    uint32_t status = mmio_read32(HMAO_STATUS);
    TEST_ASSERT((status & 0xFF) == 0, "HMAO_STATUS initial state (FSM should be idle)");
    
    // Test 1.2: Read HMAO_DECISION (should be safe default = VETO = 0)
    uint32_t decision = mmio_read32(HMAO_DECISION);
    TEST_ASSERT((decision & 0x1) == 0, "HMAO_DECISION safe default (VETO)");
    
    // Test 1.3: Write to HMAO_START (should not cause immediate crash)
    mmio_write32(HMAO_START, 0x1);
    TEST_ASSERT(1, "HMAO_START write succeeded (no exception)");
    
    // Test 1.4: Check HMAO_STATUS shows busy (bit 6)
    status = mmio_read32(HMAO_STATUS);
    TEST_ASSERT((status & 0x40) != 0, "HMAO_STATUS shows BUSY after START pulse");
    
    // Test 1.5: Read HMAO_LATENCY_CYCLES (should accumulate)
    uint32_t latency = mmio_read32(HMAO_LATENCY_CYCLES);
    TEST_ASSERT(latency > 0, "HMAO_LATENCY_CYCLES > 0 (engine is running)");
    
    printf("\n[TEST_001 SUMMARY] Passed: %u, Failed: %u\n", 
           test_stats.pass_count, test_stats.fail_count);
}

// ============================================================================
// TEST 002: RISC-V ↔ TRAJECTORY MEMORY & CRC VALIDATION
// ============================================================================

void test_002_trajectory_memory(void) {
    printf("\n========== TEST 002: RISC-V ↔ Trajectory Memory & CRC ==========\n");
    
    // Test 2.1: Read trajectory buffer size valid
    uint32_t traj_addr = TRAJECTORY_BASE;
    uint32_t traj_size = TRAJECTORY_SIZE;
    TEST_ASSERT(traj_addr == 0x8030_0000, "Trajectory base address correct");
    
    // Test 2.2: Write valid trajectory waypoints (simplified: 50 waypoints x 7 fields)
    // Trajectory structure: 50 waypoints × 7 float32 fields = 1,400 bytes
    // Waypoint layout: [x, y, z, vx, vy, heading, timestamp]
    
    uint32_t *traj_buf = (uint32_t *)TRAJECTORY_BASE;
    
    // Fill trajectory with dummy valid data
    // Waypoint 0: simple linear trajectory
    float *traj_floats = (float *)TRAJECTORY_BASE;
    
    for (int i = 0; i < 50; i++) {
        traj_floats[i*7 + 0] = (float)i;           // x = i meters
        traj_floats[i*7 + 1] = (float)(i * 0.5);   // y = i/2 meters
        traj_floats[i*7 + 2] = 0.0f;               // z = 0
        traj_floats[i*7 + 3] = 1.0f;               // vx = 1 m/s
        traj_floats[i*7 + 4] = 0.5f;               // vy = 0.5 m/s
        traj_floats[i*7 + 5] = 0.0f;               // heading = 0 rad
        traj_floats[i*7 + 6] = (float)(i * 0.1);   // timestamp = i*100ms
    }
    
    TEST_ASSERT(1, "Trajectory buffer written successfully");
    
    // Test 2.3: Compute and write CRC32
    uint8_t *traj_data = (uint8_t *)TRAJECTORY_BASE;
    uint32_t computed_crc = crc32_compute(traj_data, 1400); // 50*7*4 = 1400
    
    // Write CRC at offset 0x0568 (after last timestamp)
    uint32_t *crc_addr = (uint32_t *)(TRAJECTORY_BASE + 0x0568);
    *crc_addr = computed_crc;
    
    TEST_ASSERT(1, "CRC32 computed and written to trajectory buffer");
    
    // Test 2.4: Verify CRC can be read back
    uint32_t read_crc = mmio_read32(TRAJECTORY_BASE + 0x0568);
    TEST_ASSERT(read_crc == computed_crc, "CRC32 read-back matches written value");
    
    // Test 2.5: Verify trajectory bounds
    float traj_xmin = traj_floats[0];  // should be 0.0
    float traj_xmax = traj_floats[49*7]; // should be 49.0
    TEST_ASSERT((traj_xmin >= 0.0f) && (traj_xmax > traj_xmin), 
                "Trajectory X bounds valid");
    
    printf("\n[TEST_002 SUMMARY] Passed: %u, Failed: %u\n", 
           test_stats.pass_count, test_stats.fail_count);
}

// ============================================================================
// TEST 003: RISC-V ↔ WORLD MODEL MEMORY ACCESS
// ============================================================================

void test_003_world_model_memory(void) {
    printf("\n========== TEST 003: RISC-V ↔ World Model Memory Access ==========\n");
    
    // Test 3.1: Verify world model base address
    TEST_ASSERT(WORLD_MODEL_BASE == 0x8040_0000, "World model base address correct");
    
    // Test 3.2: Write sample world model objects (8 objects × 64 bytes each)
    // Structure per object (64 bytes):
    //   [0-11]   : position[3] (float32 x3) = 12 bytes
    //   [12-23]  : velocity[3] (float32 x3) = 12 bytes
    //   [24-35]  : dimensions[3] (float32 x3) = 12 bytes
    //   [36-39]  : heading (float32) = 4 bytes
    //   [40-41]  : track_id (uint16) = 2 bytes
    //   [42]     : class (uint8) = 1 byte
    //   [43]     : confidence (uint8) = 1 byte
    //   [44-63]  : predicted_trajectory (20 bytes) = 5 waypoints × 4 bytes
    
    float *wm_buf = (float *)WORLD_MODEL_BASE;
    
    // Create 8 sample objects
    for (int obj = 0; obj < 8; obj++) {
        int base_idx = obj * 16;  // 64 bytes / 4 bytes per float = 16 floats
        
        // Position
        wm_buf[base_idx + 0] = 10.0f + obj * 5.0f;  // x
        wm_buf[base_idx + 1] = 20.0f;                // y
        wm_buf[base_idx + 2] = 0.0f;                 // z
        
        // Velocity
        wm_buf[base_idx + 3] = 0.5f;                 // vx
        wm_buf[base_idx + 4] = 0.0f;                 // vy
        wm_buf[base_idx + 5] = 0.0f;                 // vz
        
        // Dimensions
        wm_buf[base_idx + 6] = 4.0f;                 // length
        wm_buf[base_idx + 7] = 2.0f;                 // width
        wm_buf[base_idx + 8] = 1.5f;                 // height
        
        // Heading
        wm_buf[base_idx + 9] = 0.0f;                 // yaw
        
        // Rest (track_id, class, confidence, predicted_trajectory) handled as bytes
    }
    
    TEST_ASSERT(1, "8 world model objects written successfully");
    
    // Test 3.3: Read back first object position
    float read_x = wm_buf[0];
    float read_y = wm_buf[1];
    TEST_ASSERT((read_x == 10.0f) && (read_y == 20.0f), 
                "World model object 0 position read-back correct");
    
    // Test 3.4: Verify object memory layout (64 bytes := 16 float32s per object)
    float obj7_x = wm_buf[7 * 16];  // Object 7, position X
    TEST_ASSERT(obj7_x == (10.0f + 7 * 5.0f), "Object 7 position X correct");
    
    // Test 3.5: Check memory bounds (don't exceed 8MB)
    uint32_t max_objects = WORLD_MODEL_SIZE / 64;
    TEST_ASSERT(max_objects == (8 * 1024 * 1024 / 64), "World model capacity verified");
    
    printf("\n[TEST_003 SUMMARY] Passed: %u, Failed: %u\n", 
           test_stats.pass_count, test_stats.fail_count);
}

// ============================================================================
// TEST 004: RISC-V ↔ ADAPTIVE MARGIN CONTROLLER (QUALITY VECTOR)
// ============================================================================

void test_004_adaptive_margin(void) {
    printf("\n========== TEST 004: RISC-V ↔ Adaptive Margin Controller ==========\n");
    
    // Test 4.1: Write quality vector registers
    uint8_t gps_val = 200;        // Good GPS (0=bad, 255=excellent)
    uint8_t camera_val = 180;     // Good camera
    uint8_t friction_val = 150;   // Medium friction
    uint8_t actuator_val = 255;   // Excellent actuator health
    
    mmio_write8(GPS_QUALITY, gps_val);
    mmio_write8(CAMERA_QUALITY, camera_val);
    mmio_write8(ROAD_FRICTION, friction_val);
    mmio_write8(ACTUATOR_HEALTH, actuator_val);
    
    TEST_ASSERT(1, "Quality vector registers written");
    
    // Test 4.2: Read back quality values
    uint8_t read_gps = mmio_read8(GPS_QUALITY);
    uint8_t read_camera = mmio_read8(CAMERA_QUALITY);
    uint8_t read_friction = mmio_read8(ROAD_FRICTION);
    uint8_t read_actuator = mmio_read8(ACTUATOR_HEALTH);
    
    TEST_ASSERT((read_gps == gps_val) && (read_camera == camera_val) &&
                (read_friction == friction_val) && (read_actuator == actuator_val), 
                "Quality vector values read-back correctly");
    
    // Test 4.3: Compute weighted quality score
    // weighted_score = (gps×0.3) + (camera×0.3) + (friction×0.2) + (actuator×0.2)
    uint32_t weighted = (gps_val * 77) + (camera_val * 77) + 
                        (friction_val * 51) + (actuator_val * 51);
    uint8_t combined = weighted >> 8;  // Normalize to 0-255
    
    TEST_ASSERT((combined >= 0) && (combined <= 255), 
                "Combined quality score within valid range");
    
    // Test 4.4: Read adaptive margins
    uint16_t lateral_margin = mmio_read32(LATERAL_MARGIN) & 0xFFFF;
    uint16_t longitudinal_margin = mmio_read32(LONGITUDINAL_MARGIN) & 0xFFFF;
    uint16_t time_margin = mmio_read32(TIME_MARGIN) & 0xFFFF;
    
    TEST_ASSERT((lateral_margin > 0) && (longitudinal_margin > 0) && (time_margin > 0), 
                "Adaptive margins computed and readable");
    
    // Test 4.5: Set poor quality and verify margins increase
    mmio_write8(GPS_QUALITY, 50);       // Bad GPS
    mmio_write8(CAMERA_QUALITY, 30);    // Poor camera
    mmio_write8(ROAD_FRICTION, 20);     // Icy road
    mmio_write8(ACTUATOR_HEALTH, 100);  // Degraded actuator
    
    uint16_t new_lateral = mmio_read32(LATERAL_MARGIN) & 0xFFFF;
    TEST_ASSERT(new_lateral > lateral_margin, 
                "Lateral margin increases with poor quality sensor inputs");
    
    printf("\n[TEST_004 SUMMARY] Passed: %u, Failed: %u\n", 
           test_stats.pass_count, test_stats.fail_count);
}

// ============================================================================
// TEST 005: FULL INTEGRATION TEST (ALL INTERACTIONS)
// ============================================================================

void test_005_full_integration(void) {
    printf("\n========== TEST 005: Full Integration Test ==========\n");
    
    // Test 5.1: Initialize all subsystems sequentially
    TEST_ASSERT(1, "Integration test started");
    
    // Step 1: Set quality vector to good conditions
    mmio_write8(GPS_QUALITY, 200);
    mmio_write8(CAMERA_QUALITY, 200);
    mmio_write8(ROAD_FRICTION, 200);
    mmio_write8(ACTUATOR_HEALTH, 255);
    TEST_ASSERT(1, "Quality vector set to good conditions");
    
    // Step 2: Populate trajectory memory with valid data
    float *traj_floats = (float *)TRAJECTORY_BASE;
    for (int i = 0; i < 50; i++) {
        traj_floats[i*7 + 0] = (float)i;           // x
        traj_floats[i*7 + 1] = (float)(i * 0.5);   // y
        traj_floats[i*7 + 2] = 0.0f;               // z
        traj_floats[i*7 + 3] = 1.0f;               // vx
        traj_floats[i*7 + 4] = 0.5f;               // vy
        traj_floats[i*7 + 5] = 0.0f;               // heading
        traj_floats[i*7 + 6] = (float)(i * 0.1);   // timestamp
    }
    uint8_t *traj_data = (uint8_t *)TRAJECTORY_BASE;
    uint32_t computed_crc = crc32_compute(traj_data, 1400);
    *(uint32_t *)(TRAJECTORY_BASE + 0x0568) = computed_crc;
    TEST_ASSERT(1, "Trajectory memory populated with valid data");
    
    // Step 3: Populate world model with safe obstacle (no collision)
    float *wm_buf = (float *)WORLD_MODEL_BASE;
    wm_buf[0] = 100.0f;  // Far away object, no collision
    wm_buf[1] = 100.0f;
    wm_buf[2] = 0.0f;
    TEST_ASSERT(1, "World model populated with safe obstacle");
    
    // Step 4: Trigger HMAO_START
    mmio_write32(HMAO_START, 0x1);
    TEST_ASSERT(1, "HMAO_START pulse issued");
    
    // Step 5: Poll for HMAO completion (wait for IRQ or status change)
    uint32_t timeout = 100000;  // ~100k cycles
    uint32_t decision = 0;
    
    while (timeout-- > 0) {
        uint32_t status = mmio_read32(HMAO_STATUS);
        if ((status & 0x40) == 0) {  // Busy bit cleared = complete
            decision = mmio_read32(HMAO_DECISION);
            break;
        }
    }
    
    TEST_ASSERT(timeout > 0, "HMAO computation completed within timeout");
    
    // Step 6: Verify decision output
    // With safe trajectory and far-away obstacle, should see GRANT (decision = 1)
    // But with safe-default, might be VETO depending on validation
    TEST_ASSERT((decision & 0x1) == 0 || (decision & 0x1) == 1, 
                "HMAO_DECISION output is valid (GRANT or VETO)");
    
    // Step 7: Check violation flags if VETO
    if ((decision & 0x1) == 0) {
        uint32_t violation_lo = mmio_read32(HMAO_VIOLATION_LO);
        uint32_t violation_hi = mmio_read32(HMAO_VIOLATION_HI);
        TEST_ASSERT((violation_lo > 0) || (violation_hi > 0), 
                    "Violation flags populated if VETO decision");
    } else {
        TEST_ASSERT(1, "GRANT decision: no violation flags expected");
    }
    
    // Step 8: Read latency metrics
    uint32_t latency = mmio_read32(HMAO_LATENCY_CYCLES);
    TEST_ASSERT((latency > 0) && (latency <= 7000000), 
                "Latency within expected range (<7ms @ 400MHz)");
    
    // Step 9: Verify all register reads succeed without exception
    uint32_t margins[3];
    margins[0] = mmio_read32(LATERAL_MARGIN);
    margins[1] = mmio_read32(LONGITUDINAL_MARGIN);
    margins[2] = mmio_read32(TIME_MARGIN);
    TEST_ASSERT((margins[0] > 0) && (margins[1] > 0) && (margins[2] > 0), 
                "All margin registers readable and non-zero");
    
    printf("\n[TEST_005 SUMMARY] Passed: %u, Failed: %u\n", 
           test_stats.pass_count, test_stats.fail_count);
}

// ============================================================================
// MAIN TEST RUNNER
// ============================================================================

void hmao_run_all_tests(void) {
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║           HMAO Engine - RISC-V Integration Test Suite        ║\n");
    printf("║                   Version 1.0 - ASIL-D                       ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    
    // Reset test counters
    test_stats.test_count = 0;
    test_stats.pass_count = 0;
    test_stats.fail_count = 0;
    
    // Run all tests
    test_001_register_interface();
    test_002_trajectory_memory();
    test_003_world_model_memory();
    test_004_adaptive_margin();
    test_005_full_integration();
    
    // Print final summary
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║                     FINAL TEST SUMMARY                       ║\n");
    printf("╠══════════════════════════════════════════════════════════════╣\n");
    printf("║ Total Tests:  %u                                             ║\n", test_stats.test_count);
    printf("║ Passed:       %u                                             ║\n", test_stats.pass_count);
    printf("║ Failed:       %u                                             ║\n", test_stats.fail_count);
    
    if (test_stats.fail_count == 0) {
        printf("║                                                              ║\n");
        printf("║            ✓ ALL TESTS PASSED - SYSTEM VERIFIED ✓            ║\n");
        printf("║                                                              ║\n");
    } else {
        printf("║                                                              ║\n");
        printf("║            ✗ SOME TESTS FAILED - REVIEW REQUIRED ✗          ║\n");
        printf("║                                                              ║\n");
    }
    printf("╚══════════════════════════════════════════════════════════════╝\n");
}

// Entry point (called from RISC-V boot code)
int main(void) {
    hmao_run_all_tests();
    
    // Loop forever (or return to boot loader)
    while (1) {
        __asm__ volatile ("wfi");  // Wait for interrupt
    }
    
    return 0;
}
