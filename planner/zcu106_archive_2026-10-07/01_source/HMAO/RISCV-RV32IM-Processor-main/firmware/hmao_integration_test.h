// =============================================================================
// FILE        : hmao_integration_test.h
// PROJECT     : HMAO Engine - RISC-V Integration Test
// DESCRIPTION : Header file with register definitions and test utilities
// =============================================================================

#ifndef HMAO_INTEGRATION_TEST_H
#define HMAO_INTEGRATION_TEST_H

#include <stdint.h>

// ============================================================================
// REGISTER MAP - HMAO CONTROL REGISTERS
// ============================================================================

typedef struct {
    volatile uint32_t status;              /*!< 0x000: HMAO Status Register */
    volatile uint32_t start;               /*!< 0x004: HMAO Start Trigger */
    volatile uint32_t decision;            /*!< 0x008: HMAO Decision Output */
    volatile uint32_t irq_clear;           /*!< 0x00C: IRQ Clear Register */
    volatile uint32_t violation_lo;        /*!< 0x010: Violation Flags [31:0] */
    volatile uint32_t violation_hi;        /*!< 0x014: Violation Flags [63:32] */
    volatile uint32_t latency_cycles;      /*!< 0x018: Latency in cycles */
    volatile uint8_t  _reserved[4];        
    volatile uint8_t  gps_quality;         /*!< 0x020: GPS Quality (0-255) */
    volatile uint8_t  camera_quality;      /*!< 0x024: Camera Quality (0-255) */
    volatile uint8_t  road_friction;       /*!< 0x028: Road Friction (0-255) */
    volatile uint8_t  actuator_health;     /*!< 0x02C: Actuator Health (0-255) */
    volatile uint8_t  weather_severity;    /*!< 0x030: Weather Severity (0-255) */
    volatile uint16_t lateral_margin;      /*!< 0x034: Lateral Margin (Q8.8) */
    volatile uint16_t longitudinal_margin; /*!< 0x036: Longitudinal Margin (Q8.8) */
    volatile uint16_t time_margin;         /*!< 0x038: Time Margin (Q8.8) */
} hmao_regs_t;

// ============================================================================
// REGISTER BIT DEFINITIONS
// ============================================================================

// HMAO_STATUS register bits
#define HMAO_STATUS_FSM_MASK        (0x7 << 0)   /*!< FSM state [2:0] */
#define HMAO_STATUS_CRC_ERR         (1 << 3)     /*!< Trajectory CRC error */
#define HMAO_STATUS_WDT_TIMEOUT     (1 << 4)     /*!< Watchdog timeout */
#define HMAO_STATUS_NUMERICAL_ERR   (1 << 5)     /*!< Numerical error */
#define HMAO_STATUS_BUSY            (1 << 6)     /*!< Engine busy processing */

// HMAO_DECISION output
#define HMAO_DECISION_VETO          0            /*!< Reject trajectory */
#define HMAO_DECISION_GRANT         1            /*!< Accept trajectory */

// ============================================================================
// MEMORY LAYOUT
// ============================================================================

#define TRAJECTORY_BUFFER_BASE      0x8030_0000
#define TRAJECTORY_BUFFER_SIZE      0x00000578   // 1,400 bytes payload + 4 CRC

#define WORLD_MODEL_BASE            0x8040_0000
#define WORLD_MODEL_SIZE            0x0020_0000  // 8 MB

#define SAFE_DATA_BASE              0x8020_0000
#define SAFE_DATA_SIZE              0x0010_0000  // 1 MB

// ============================================================================
// TRAJECTORY WAYPOINT STRUCTURE
// ============================================================================

typedef struct {
    float x;          /*!< X coordinate (meters) */
    float y;          /*!< Y coordinate (meters) */
    float z;          /*!< Z coordinate (meters) */
    float vx;         /*!< X velocity (m/s) */
    float vy;         /*!< Y velocity (m/s) */
    float heading;    /*!< Yaw angle (radians) */
    float timestamp;  /*!< Time since start (seconds) */
} trajectory_waypoint_t;

// ============================================================================
// WORLD MODEL OBJECT STRUCTURE (64 bytes per object)
// ============================================================================

typedef struct {
    float position[3];          /*!< [0-11] X, Y, Z (meters) */
    float velocity[3];          /*!< [12-23] Vx, Vy, Vz (m/s) */
    float dimensions[3];        /*!< [24-35] Length, Width, Height (meters) */
    float heading;              /*!< [36-39] Yaw angle (radians) */
    uint16_t track_id;          /*!< [40-41] Object tracking ID */
    uint8_t class;              /*!< [42] Enum: 0=Car, 1=Truck, 2=Motorcycle, 3=Pedestrian */
    uint8_t confidence;         /*!< [43] AI confidence (0-100) */
    uint8_t predicted_trajectory[20];  /*!< [44-63] 5 waypoints × (2× int16 offset) */
} world_model_object_t;

// ============================================================================
// UTILITY FUNCTIONS (defined in hmao_integration_test.c)
// ============================================================================

/**
 * @brief Compute CRC32 checksum for trajectory data
 * @param data Pointer to data buffer
 * @param length Length of data in bytes
 * @return Computed CRC32 value
 */
uint32_t crc32_compute(const uint8_t *data, uint32_t length);

/**
 * @brief Run all HMAO integration tests
 */
void hmao_run_all_tests(void);

#endif // HMAO_INTEGRATION_TEST_H
