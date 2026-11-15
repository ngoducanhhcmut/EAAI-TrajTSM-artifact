// =============================================================================
// FILE        : hmao_axi_if.sv
// PROJECT     : HMAO Engine
// DESCRIPTION : AXI4 Read-Only Interface — standalone file.
//               Extracted from hmao_interfaces.sv for use in simsets
//               (U8/U9 collision_sat) that do NOT need hmao_pipe_if.
//               Reason: hmao_pipe_if contains
//                   waypoint_t waypoints [0:TRAJ_WAYPOINTS-1]
//               (unpacked array of packed struct) which triggers
//               Verific VeriVisitor::TraverseArray infinite recursion
//               in xelab 2025.2, crashing ALL simsets that compile it
//               even if hmao_pipe_if is never instantiated.
// =============================================================================

`timescale 1ns/1ps

// AXI4 Read-Only Interface (HMAO → Trajectory Buffer / World Model)
// HMAO Engine is READ-ONLY master (SMPU enforced)
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
