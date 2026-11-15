// =============================================================================
// FILE        : hmao_pkg.sv
// PROJECT     : HMAO Engine - Hardware-Managed Assurance Offload Safety Verification Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0
// SAFETY      : ASIL-D (ISO 26262)
// PLATFORM    : Xilinx Versal HX FPGA - SLR1
// AUTHOR      : [Your Name]
// DATE        : 2024
// DESCRIPTION : Global package - ALL types, parameters, enums, interfaces.
//               Import this package in every module: import hmao_pkg::*;
// =============================================================================

`ifndef HMAO_PKG_SV
`define HMAO_PKG_SV

package hmao_pkg;

  // ===========================================================================
  // SECTION 1: GLOBAL TIMING PARAMETERS
  // Spec Ref: Section 1.3, 9.3, 11.1, 11.2
  // ===========================================================================

  // Clock
  parameter int unsigned CLK_FREQ_HZ          = 400_000_000;    // 400 MHz
  parameter real         CLK_PERIOD_NS         = 2.5;            // 2.5 ns per cycle

  // RISCV core clock (same domain as HMAO - both 400MHz, simplifies CDC)
  parameter int unsigned RISCV_CLK_FREQ_HZ     = 400_000_000;   // replaces VexRiscv 250MHz

  // Latency budgets (in clock cycles @400MHz)
  parameter int unsigned PREPROC_CYCLES        = 200_000;        // 0.5ms
  parameter int unsigned STAGE1_TOTAL_CYCLES   = 1_600_000;      // 4.0ms
  parameter int unsigned STAGE2_TOTAL_CYCLES   = 1_200_000;      // 3.0ms (additional)
  parameter int unsigned MAX_TOTAL_CYCLES      = 4_000_000;      // 10ms hard deadline

  // Sub-budget Stage 1 (Spec Ref: Section 11.2)
  parameter int unsigned S1_PREPROC_CYCLES     = 120_000;        // 0.3ms
  parameter int unsigned S1_ZONOTOPE_CYCLES    = 600_000;        // 1.5ms
  parameter int unsigned S1_COLLISION_CYCLES   = 800_000;        // 2.0ms
  parameter int unsigned S1_SYNC_CYCLES        = 80_000;         // 0.2ms

  // Board watchdog clock is PL3 = 250 MHz, independent of TSM PL2 = 187.5 MHz.
  // Stage budgets apply only while that stage is active. Total budget includes
  // the 1,500,000-TSM-cycle completion padding (8 ms on the board).
  parameter int unsigned WDT_CLOCK_MHZ        = 250;
  parameter int unsigned WDT_STAGE1_CYCLES     = WDT_CLOCK_MHZ * 7_200;   // 7.2 ms
  parameter int unsigned WDT_STAGE2_CYCLES     = WDT_CLOCK_MHZ * 5_600;   // 5.6 ms
  parameter int unsigned WDT_TOTAL_CYCLES      = WDT_CLOCK_MHZ * 16_000;  // 16 ms

  // CDC Watchdog: 200ms without REQ-ACK → worst-case margins
  parameter int unsigned CDC_WDT_CYCLES        = 80_000_000;     // 200ms @ 400MHz

  // ===========================================================================
  // SECTION 2: MEMORY MAP
  // Spec Ref: Section 5.1
  // ===========================================================================

  parameter logic [31:0] HMAO_REG_BASE         = 32'hA410_0000;
  // v2.1 (05/10/2026): doi tu 0x80xx_xxxx vao DDR_LOW. Trong block design, M_AXI cua TSM
  // (qua S_AXI_HP1) chi anh xa HP1_DDR_LOW = 0x0000_0000-0x7FFF_FFFF; dia chi cu 0x8030_0000
  // nam ngoai -> DECERR tren board. Vung 0x7020_0000-0x70BF_FFFF khong trung trong so
  // VLA-Traj (0x0000_0000-0x0200_0000) va ma firmware R5 (0x4000_0000-0x43FF_FFFF).
  parameter logic [31:0] TRAJ_BUFFER_BASE       = 32'h7030_0000;
  parameter logic [31:0] WORLD_MODEL_BASE       = 32'h7040_0000;
  parameter logic [31:0] SAFETY_DATA_BASE       = 32'h7020_0000;

  // Register offsets from HMAO_REG_BASE
  parameter logic [11:0] REG_OFF_STATUS         = 12'h000;   // HMAO_STATUS[31:0]
  parameter logic [11:0] REG_OFF_START          = 12'h004;   // HMAO_START[0]  (W)
  parameter logic [11:0] REG_OFF_DECISION       = 12'h008;   // HMAO_DECISION[0] (R)
  parameter logic [11:0] REG_OFF_IRQ_CLEAR      = 12'h00C;   // HMAO_IRQ_CLEAR (W)
  parameter logic [11:0] REG_OFF_VIOL_LO        = 12'h010;   // VIOLATION_FLAGS[31:0]
  parameter logic [11:0] REG_OFF_VIOL_HI        = 12'h014;   // VIOLATION_FLAGS[63:32]
  parameter logic [11:0] REG_OFF_LATENCY        = 12'h018;   // HMAO_LATENCY_CYCLES
  parameter logic [11:0] REG_OFF_GPS_Q          = 12'h020;   // GPS_QUALITY
  parameter logic [11:0] REG_OFF_CAM_Q          = 12'h024;   // CAMERA_QUALITY
  parameter logic [11:0] REG_OFF_FRICTION       = 12'h028;   // ROAD_FRICTION
  parameter logic [11:0] REG_OFF_ACTUATOR       = 12'h02C;   // ACTUATOR_HEALTH
  parameter logic [11:0] REG_OFF_WEATHER        = 12'h030;   // WEATHER_SEVERITY
  parameter logic [11:0] REG_OFF_LAT_MARGIN     = 12'h034;   // LATERAL_MARGIN
  parameter logic [11:0] REG_OFF_LONG_MARGIN    = 12'h036;   // LONGITUDINAL_MARGIN
  parameter logic [11:0] REG_OFF_TIME_MARGIN    = 12'h038;   // TIME_MARGIN
  parameter logic [11:0] REG_OFF_S1_CFG         = 12'h040;   // STAGE1_CONFIG (R)
  parameter logic [11:0] REG_OFF_S2_CFG         = 12'h044;   // STAGE2_CONFIG (R)

  // Trajectory buffer layout
  parameter int unsigned TRAJ_WAYPOINTS         = 50;
  parameter int unsigned TRAJ_FIELDS            = 7;           // x,y,z,vx,vy,heading,timestamp
  parameter int unsigned TRAJ_BYTES             = 1400;        // 50x7x4
  parameter int unsigned TRAJ_CRC_OFFSET        = 32'h0568;   // CRC32 trailer

  // World model
  parameter int unsigned WM_OBJECT_BYTES        = 64;          // 64 bytes per obstacle
  parameter int unsigned WM_MAX_OBJECTS         = 131072;      // 8MB / 64B

  // ===========================================================================
  // SECTION 3: ZONOTOPE & COMPUTATION PARAMETERS
  // Spec Ref: Section 7.2
  // ===========================================================================

  parameter int unsigned STAGE1_GENERATORS      = 16;
  parameter int unsigned STAGE2_GENERATORS      = 32;
  parameter int unsigned STAGE1_TIMESTEPS       = 50;          // 10ms Δt → 5s
  parameter int unsigned STAGE2_TIMESTEPS       = 100;         // 5ms Δt → 5s
  parameter int unsigned ADMM_STAGES            = 15;          // Unrolled pipeline depth
  parameter int unsigned MAX_SUSPICIOUS_OBS     = 16;          // Stage1 suspect list

  // Kinematic limits (Spec Ref: Section 7.2.3)
  parameter real         VMAX_MPS               = 35.0;        // 126 km/h
  parameter real         MAX_YAW_RATE           = 0.8;         // rad/s
  parameter real         MAX_ACCEL_MPS2         = 8.0;         // m/s²
  parameter real         MIN_ACCEL_MPS2         = -8.0;        // m/s²

  // Adaptive Margin base values (Q8.8 fixed-point)
  parameter logic [15:0] BASE_LATERAL_Q8_8      = 16'h0180;   // 1.5m
  parameter logic [15:0] BASE_LONG_Q8_8         = 16'h0200;   // 2.0m
  parameter logic [15:0] BASE_TIME_Q8_8         = 16'h0080;   // 0.5s

  // Hardware clamps (Spec Ref: Section 8.5)
  parameter logic [15:0] MIN_LATERAL_Q8_8       = 16'h0080;   // 0.5m
  parameter logic [15:0] MAX_LATERAL_Q8_8       = 16'h0300;   // 3.0m
  parameter logic [15:0] MIN_LONG_Q8_8          = 16'h0200;   // 2.0m
  parameter logic [15:0] MAX_LONG_Q8_8          = 16'h0800;   // 8.0m

  // Hardcoded config registers (Spec Ref: Section 5.2)
  parameter logic [31:0] STAGE1_CONFIG_VAL      = 32'h10320A; // 16gen,10ms,50steps
  parameter logic [31:0] STAGE2_CONFIG_VAL      = 32'h205064; // 32gen,5ms,100steps

  // SMPU Master ID (Spec Ref: Section 13.3)
  parameter logic [7:0]  HMAO_MASTER_ID         = 8'h1A;

  // ===========================================================================
  // SECTION 4: FSM STATE ENCODING
  // Spec Ref: Section 9.1, Section 9.4 - Hamming Distance = 3 encoding
  //
  // Uses 7-bit Hamming(7,4) codewords.  Any single or double bit-flip in the
  // state register produces a non-codeword (undefined state) → default branch
  // of case statement forces FSM_ERROR → permanent VETO.
  //
  // Codeword derivation (Hamming(7,4), systematic, parity at positions 1,2,4):
  //   bit positions (1-indexed): b7 b6 b5 b4 b3 b2 b1
  //   p1(b1) = b3^b5^b7,  p2(b2) = b3^b6^b7,  p4(b4) = b5^b6^b7
  //   Data nibbles 0-7 yield the 8 codewords below (all pairs HD ≥ 3).
  //
  // Minimum Hamming distance between any two valid states = 3 ✓
  // (Verified: IDLE↔S1_COMP=3, S1_COMP↔S1_CHECK=4, etc.)
  // ===========================================================================

  typedef enum logic [6:0] {
    FSM_IDLE          = 7'b000_0000,   // data=0000  HD≥3 from all others
    FSM_STAGE1_COMP   = 7'b000_0111,   // data=0001
    FSM_STAGE1_CHECK  = 7'b001_1001,   // data=0010
    FSM_STAGE2_COMP   = 7'b001_1110,   // data=0011
    FSM_STAGE2_CHECK  = 7'b010_1010,   // data=0100
    FSM_OUTPUT_GRANT  = 7'b010_1101,   // data=0101
    FSM_OUTPUT_VETO   = 7'b011_0011,   // data=0110
    FSM_ERROR         = 7'b011_0100    // data=0111
  } hmao_fsm_state_t;

  // Decode 7-bit Hamming codeword to 3-bit index for HMAO_STATUS[2:0] display.
  // Any unrecognised codeword (bit-flip → invalid) maps to 3'd7 (ERROR).
  function automatic logic [2:0] decode_fsm_state(input logic [6:0] enc);
    case (enc)
      7'b000_0000: decode_fsm_state = 3'd0; // IDLE
      7'b000_0111: decode_fsm_state = 3'd1; // STAGE1_COMP
      7'b001_1001: decode_fsm_state = 3'd2; // STAGE1_CHECK
      7'b001_1110: decode_fsm_state = 3'd3; // STAGE2_COMP
      7'b010_1010: decode_fsm_state = 3'd4; // STAGE2_CHECK
      7'b010_1101: decode_fsm_state = 3'd5; // OUTPUT_GRANT
      7'b011_0011: decode_fsm_state = 3'd6; // OUTPUT_VETO
      7'b011_0100: decode_fsm_state = 3'd7; // ERROR
      default:     decode_fsm_state = 3'd7; // Unknown codeword → treat as ERROR
    endcase
  endfunction

  // ===========================================================================
  // SECTION 5: DECISION & FAULT TYPES
  // Spec Ref: Section 4.1, 4.4
  // ===========================================================================

  typedef enum logic [0:0] {
    DECISION_VETO  = 1'b0,   // Trajectory rejected / default safe
    DECISION_GRANT = 1'b1    // Trajectory approved
  } hmao_decision_t;

  // Fault bits (Spec Ref: Section 4.4)
  typedef struct packed {
    logic hmao_hang;          // [0] Watchdog timeout
    logic zonotope_error;     // [1] Zonotope numerical error
    logic admm_divergence;    // [2] ADMM solver diverged
    logic trajectory_crc_fail;// [3] CRC32 mismatch
    logic smpu_violation;     // [4] Memory access violation
    logic numerical_overflow; // [5] Arithmetic overflow
    logic kinematic_invalid;  // [6] Kinematic check failed
  } hmao_fault_t;

  // Violation flags (Spec Ref: Section 4.2)
  typedef struct packed {
    logic [7:0]  stage_state;      // [63:56] Stage & state
    logic [7:0]  violation_type;   // [55:48] Type of violation
    logic [15:0] obstacle_id;      // [47:32] track_id of obstacle
    logic [15:0] time_step_idx;    // [31:16] Time step index
    logic [15:0] penetration_depth;// [15:0]  Q8.8 penetration depth
  } hmao_violation_t;             // Total: 64 bits

  // Violation type encoding
  typedef enum logic [7:0] {
    VIOL_NONE         = 8'h00,
    VIOL_LATERAL      = 8'h01,
    VIOL_LONGITUDINAL = 8'h02,
    VIOL_KINEMATIC    = 8'h04,
    VIOL_TIME_MARGIN  = 8'h08,
    VIOL_SYSTEM_ERROR = 8'hFF
  } violation_type_t;

  // Stage encoding for violation flags
  typedef enum logic [7:0] {
    VIOL_STAGE1       = 8'h01,
    VIOL_STAGE2       = 8'h02,
    VIOL_SYSTEM       = 8'hFF
  } violation_stage_t;

  // ===========================================================================
  // SECTION 6: UNCERTAINTY VECTOR (CDC between QM and ASIL-D)
  // Spec Ref: Section 3.3, Section 14
  // ===========================================================================

  typedef struct packed {
    logic [7:0] gps_quality;        // 0=HDOP>10, 255=HDOP<2
    logic [7:0] camera_quality;     // 0=blind, 255=clear
    logic [7:0] road_friction;      // 0=ice(μ=0.1), 255=dry(μ=0.9)
    logic [7:0] actuator_health;    // 0=degraded, 255=nominal
    logic [7:0] weather_severity;   // 0=clear, 255=heavy rain
    logic       parity;             // 1-bit parity for CDC integrity
  } uncertainty_vec_t;              // 41 bits total (padded to 48)

  // ===========================================================================
  // SECTION 7: WORLD MODEL OBJECT STRUCT
  // Spec Ref: Section 3.2.1 - Exactly 64 bytes per object
  // ===========================================================================

  typedef struct packed {
    // Bytes 0-11: position [3] (Float32 x3)
    logic [31:0] pos_x;
    logic [31:0] pos_y;
    logic [31:0] pos_z;
    // Bytes 12-23: velocity [3] (Float32 x3)
    logic [31:0] vel_x;
    logic [31:0] vel_y;
    logic [31:0] vel_z;
    // Bytes 24-35: dimensions [3] (Float32 x3) - Length, Width, Height
    logic [31:0] dim_length;
    logic [31:0] dim_width;
    logic [31:0] dim_height;
    // Bytes 36-39: heading (Float32)
    logic [31:0] heading;
    // Bytes 40-41: track_id (Uint16)
    logic [15:0] track_id;
    // Byte 42: class (Uint8) - 0=Car,1=Truck,2=Motorcycle,3=Pedestrian
    logic [7:0]  obj_class;
    // Byte 43: confidence (Uint8) 0-100
    logic [7:0]  confidence;
    // Bytes 44-63: predicted_trajectory (5 waypoints x2 Int16 = 20 bytes)
    logic [79:0] pred_x;   // 5×16b flat (xelab 2025.2: no packed-2D inside struct)
    logic [79:0] pred_y;   // 5×16b flat (xelab 2025.2: no packed-2D inside struct)
  } world_model_object_t;           // = 64 bytes = 512 bits

  // Object class enum
  typedef enum logic [7:0] {
    OBJ_CAR         = 8'd0,
    OBJ_TRUCK       = 8'd1,
    OBJ_MOTORCYCLE  = 8'd2,
    OBJ_PEDESTRIAN  = 8'd3
  } obj_class_t;

  // ===========================================================================
  // SECTION 8: TRAJECTORY WAYPOINT
  // Spec Ref: Section 3.1.1
  // ===========================================================================

  typedef struct packed {
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] z;
    logic [31:0] vx;
    logic [31:0] vy;
    logic [31:0] heading;
    logic [31:0] timestamp;
  } waypoint_t;                     // = 28 bytes = 224 bits

  // ===========================================================================
  // SECTION 9: ZONOTOPE ENCODING (128-bit compact, post order-reduction)
  // Spec Ref: Section 7.2.5
  // ===========================================================================

  // 128-bit Zonotope representation after order reduction
  // Uses Float16 (half precision) for compactness
  typedef struct packed {
    logic [15:0] cx;        // [15:0]   center X (Float16)
    logic [15:0] cy;        // [31:16]  center Y (Float16)
    logic [15:0] g1x;       // [47:32]  primary generator X (Float16)
    logic [15:0] g1y;       // [63:48]  primary generator Y (Float16)
    logic [15:0] g2x;       // [79:64]  secondary generator X (Float16)
    logic [15:0] g2y;       // [95:80]  secondary generator Y (Float16)
    logic [15:0] rem_x;     // [111:96]  remainder generator X (Float16)
    logic [15:0] rem_y;     // [127:112] remainder generator Y (Float16)
  } zonotope_128b_t;        // = 128 bits

  // ===========================================================================
  // SECTION 10: AXI4 INTERFACE PARAMETERS
  // ===========================================================================

  parameter int unsigned AXI_ADDR_W    = 32;
  parameter int unsigned AXI_DATA_W    = 256;      // 256-bit AXI (2 beats = 1 WM object)
  parameter int unsigned AXI_ID_W      = 4;
  parameter int unsigned AXI_STRB_W    = AXI_DATA_W / 8;

  // ===========================================================================
  // SECTION 11: HMAO STATUS REGISTER BIT FIELDS
  // Spec Ref: Section 5.2 - HMAO_STATUS[31:0]
  // ===========================================================================

  typedef struct packed {
    logic [25:0] reserved;     // [31:6] reserved
    logic        busy;         // [6]    HMAO computation in progress
    logic        numerical_err;// [5]    Numerical error occurred
    logic        wdt_expired;  // [4]    Watchdog timer expired
    logic        crc_err;      // [3]    CRC error on trajectory input
    logic [2:0]  fsm_state;    // [2:0]  Current FSM state encoding
  } hmao_status_t;

  // ===========================================================================
  // SECTION 12: HELPER FUNCTIONS
  // ===========================================================================

  // Parity computation (even parity over 40 bits uncertainty vector)
  function automatic logic compute_parity_40b(input logic [39:0] data);
    return ^data;
  endfunction

  // Q8.8 fixed point to real (for assertions/verification only)
  function automatic real q8_8_to_real(input logic [15:0] q);
    return real'($signed(q)) / 256.0;
  endfunction

  // Check if value is within Q8.8 hardware clamp range
  function automatic logic within_lateral_clamp(input logic [15:0] val);
    return (val >= MIN_LATERAL_Q8_8) && (val <= MAX_LATERAL_Q8_8);
  endfunction

endpackage : hmao_pkg

`endif // HMAO_PKG_SV
