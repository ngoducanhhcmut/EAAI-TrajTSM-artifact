// =============================================================================
// FILE        : hmao_interfaces.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 2.2, 3.x, 13.3
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : SystemVerilog interface definitions for all major buses.
//               Separate interface for read-only (HMAO) and write (RISCV).
// =============================================================================

`ifndef HMAO_INTERFACES_SV
`define HMAO_INTERFACES_SV

import hmao_pkg::*;

// =============================================================================
// AXI4 Read-Only Interface (HMAO → Trajectory Buffer / World Model)
// HMAO Engine is READ-ONLY master (SMPU enforced)
// =============================================================================
interface axi4_ro_if #(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 256,   // 256-bit for WM object fetch (2 beats = 64B)
  parameter int unsigned ID_W   = 4
) (
  input logic aclk,
  input logic aresetn
);

  // Read Address Channel
  // verilator lint_off BLKANDNBLK
  logic [ID_W-1:0]      arid;
  logic [ADDR_W-1:0]    araddr;
  logic [7:0]           arlen;          // burst length
  logic [2:0]           arsize;         // transfer size
  logic [1:0]           arburst;        // INCR burst
  logic                 arvalid;
  logic                 arready;
  logic [7:0]           aruser;         // carries master_id = HMAO_MASTER_ID

  // Read Data Channel
  logic [ID_W-1:0]      rid;
  logic [DATA_W-1:0]    rdata;
  logic [1:0]           rresp;
  logic                 rlast;
  logic                 rvalid;
  logic                 rready;

  // SMPU Violation indicator (from SMPU back to requester)
  logic                 smpu_decerr;    // HIGH = DECERR from SMPU write attempt
  // verilator lint_on BLKANDNBLK

  // Master port (HMAO drives AR, accepts R)
  modport master (
    output arid, araddr, arlen, arsize, arburst, arvalid, aruser, rready,
    input  arready, rid, rdata, rresp, rlast, rvalid, smpu_decerr
  );

  // Slave port (memory / SMPU accepts AR, drives R)
  modport slave (
    input  arid, araddr, arlen, arsize, arburst, arvalid, aruser, rready,
    output arready, rid, rdata, rresp, rlast, rvalid, smpu_decerr
  );

endinterface : axi4_ro_if

// =============================================================================
// AXI4-Lite Interface (RISCV ↔ HMAO Register File)
// RISCV reads/writes HMAO MMIO registers
// =============================================================================
interface axilite_if #(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 32
) (
  input logic aclk,
  input logic aresetn
);

  // Write Address Channel
  logic [ADDR_W-1:0]    awaddr;
  logic [2:0]           awprot;
  logic                 awvalid;
  logic                 awready;

  // Write Data Channel
  logic [DATA_W-1:0]    wdata;
  logic [DATA_W/8-1:0]  wstrb;
  logic                 wvalid;
  logic                 wready;

  // Write Response Channel
  logic [1:0]           bresp;
  logic                 bvalid;
  logic                 bready;

  // Read Address Channel
  logic [ADDR_W-1:0]    araddr;
  logic [2:0]           arprot;
  logic                 arvalid;
  logic                 arready;

  // Read Data Channel
  logic [DATA_W-1:0]    rdata;
  logic [1:0]           rresp;
  logic                 rvalid;
  logic                 rready;

  modport master (
    output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
           araddr, arprot, arvalid, rready,
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
  );

  modport slave (
    input  awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
           araddr, arprot, arvalid, rready,
    output awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
  );

endinterface : axilite_if

// =============================================================================
// RISCV Memory Interface (request/valid handshake - matches thienhau RISCV)
// Spec Ref: RISCV repo README - "Bus Interface: request/valid handshaking"
// =============================================================================
interface riscv_mem_if (
  input logic clk,
  input logic rst_n
);

  // Instruction memory interface
  logic [31:0]  imem_addr;
  logic         imem_req;
  logic [31:0]  imem_rdata;
  logic         imem_valid;
  logic         imem_stall;

  // Data memory interface
  logic [31:0]  dmem_addr;
  logic [31:0]  dmem_wdata;
  logic [3:0]   dmem_we;          // byte-enable write enable
  logic         dmem_req;
  logic [31:0]  dmem_rdata;
  logic         dmem_valid;
  logic         dmem_stall;

  modport core (
    output imem_addr, imem_req, dmem_addr, dmem_wdata, dmem_we, dmem_req,
    input  imem_rdata, imem_valid, imem_stall, dmem_rdata, dmem_valid, dmem_stall
  );

  modport mem (
    input  imem_addr, imem_req, dmem_addr, dmem_wdata, dmem_we, dmem_req,
    output imem_rdata, imem_valid, imem_stall, dmem_rdata, dmem_valid, dmem_stall
  );

endinterface : riscv_mem_if

// =============================================================================
// HMAO Internal Pipeline Interface (between sub-modules)
// =============================================================================
interface hmao_pipe_if (
  input logic clk,
  input logic rst_n
);

  // Pre-processing → Stage 1
  logic                       preproc_valid;         // Pre-proc done & ok
  logic                       preproc_error;         // Pre-proc found error → VETO
  logic [31:0]                bbox_xmin, bbox_xmax;  // Bounding box for obstacle pre-filter
  logic [31:0]                bbox_ymin, bbox_ymax;
  waypoint_t                  waypoints [0:TRAJ_WAYPOINTS-1]; // Validated trajectory

  // Adaptive margin outputs (always combinational)
  logic [15:0]                lateral_margin;        // Q8.8 meters
  logic [15:0]                long_margin;           // Q8.8 meters
  logic [15:0]                time_margin;           // Q8.8 seconds

  // Stage 1 → Collision check
  logic                       s1_zono_valid;         // Stage1 zonotope generation done
  // Flat 1D: element k at [k*128+:128] (xelab2025.2: no packed-array-of-struct)
  logic [STAGE1_TIMESTEPS*128-1:0] s1_zonotopes;

  // Stage 1 collision result
  logic                       s1_no_collision;       // Fast path GRANT
  logic                       s1_potential_collide;  // Need Stage 2
  logic [MAX_SUSPICIOUS_OBS*16-1:0] s1_suspicious_ids; // Flat 1D (xelab2025.2: no packed-2D)

  // ADMM parallel result
  logic                       admm_done;
  logic                       admm_collision_possible;
  logic                       admm_diverged;

  // Stage 2 → Collision check
  logic                       s2_zono_valid;
  // Flat 1D: element k at [k*128+:128] (xelab2025.2: no packed-array-of-struct)
  logic [STAGE2_TIMESTEPS*128-1:0] s2_zonotopes;

  // Stage 2 final result
  logic                       s2_no_collision;
  logic                       s2_collision_confirmed;

  // Final violation info
  hmao_violation_t            violation_info;

  // FSM control signals
  logic                       start_stage1;
  logic                       start_stage2;
  logic                       output_ready;

  modport preproc_out (
    output preproc_valid, preproc_error, bbox_xmin, bbox_xmax,
           bbox_ymin, bbox_ymax, waypoints
  );

  modport stage1_in (
    input  preproc_valid, preproc_error, bbox_xmin, bbox_xmax,
           bbox_ymin, bbox_ymax, waypoints, lateral_margin, long_margin, time_margin
  );

  modport margin_out (
    output lateral_margin, long_margin, time_margin
  );

  modport s1_zono_out (
    output s1_zono_valid, s1_zonotopes
  );

  modport s1_chk_out (
    output s1_no_collision, s1_potential_collide, s1_suspicious_ids
  );

  modport admm_out (
    output admm_done, admm_collision_possible, admm_diverged
  );

  modport s2_zono_out (
    output s2_zono_valid, s2_zonotopes
  );

  modport s2_chk_out (
    output s2_no_collision, s2_collision_confirmed, violation_info
  );

  modport fsm (
    output start_stage1, start_stage2, output_ready,
    input  preproc_valid, preproc_error, s1_no_collision, s1_potential_collide,
           s1_zono_valid, admm_done, admm_diverged, s2_zono_valid,
           s2_no_collision, s2_collision_confirmed
  );

endinterface : hmao_pipe_if

// =============================================================================
// Fault/SFI Interface (HMAO → FMU)
// Spec Ref: Section 4.4
// =============================================================================
interface sfi_if (
  input logic clk,
  input logic rst_n
);
  hmao_fault_t  fault_flags;   // Packed fault bits
  logic         fault_valid;   // Any fault asserted
  logic         fault_ack;     // FMU acknowledges

  modport source (
    output fault_flags, fault_valid,
    input  fault_ack
  );

  modport sink (
    input  fault_flags, fault_valid,
    output fault_ack
  );

endinterface : sfi_if

// =============================================================================
// CDC Handshake Interface (QM → ASIL-D)
// Spec Ref: Section 14
// =============================================================================
interface cdc_handshake_if #(
  parameter int unsigned DATA_W = 40
) (
  input logic src_clk,
  input logic dst_clk,
  input logic rst_n
);

  logic [DATA_W-1:0]  data;         // payload (uncertainty vector bits)
  logic               parity;       // even parity over data
  logic               req;          // QM asserts request
  logic               ack;          // ASIL-D asserts acknowledge

  modport sender (
    output data, parity, req,
    input  ack
  );

  modport receiver (
    input  data, parity, req,
    output ack
  );

endinterface : cdc_handshake_if

`endif // HMAO_INTERFACES_SV
