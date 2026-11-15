// =============================================================================
// FILE        : hmao_pkg_csat.sv
// DESCRIPTION : Stripped hmao_pkg for hmao_collision_sat U8/U9 simsets.
//               Contains ONLY the 3 parameters actually used by
//               hmao_collision_sat.sv + tb_hmao_collision_sat_u8/u9.sv.
//               NO struct, NO enum, NO function typedefs.
//
//               ROOT CAUSE HYPOTHESIS: xelab 2025.2 VlogCompiler::transform
//               calls TraverseArray on packed struct TYPE DEFINITIONS imported
//               via "import hmao_pkg::*", even when no struct instance exists.
//               world_model_object_t (512-bit, 15 fields) + zonotope_128b_t
//               (128-bit, 8 fields) create nested TraverseArray → crash.
//
//               This slim package avoids the crash by providing only scalars.
// =============================================================================
`ifndef HMAO_PKG_CSAT_SV
`define HMAO_PKG_CSAT_SV

package hmao_pkg;

  // AXI master ID (used in axi_ro.aruser)
  parameter logic [7:0]  HMAO_MASTER_ID     = 8'h1A;

  // World model base address (used in axi_ro.araddr)
  parameter logic [31:0] WORLD_MODEL_BASE   = 32'h8040_0000;

  // Max suspicious obstacles (used in suspicious_ids/buf port widths)
  parameter int unsigned MAX_SUSPICIOUS_OBS = 16;

endpackage : hmao_pkg

`endif // HMAO_PKG_CSAT_SV
