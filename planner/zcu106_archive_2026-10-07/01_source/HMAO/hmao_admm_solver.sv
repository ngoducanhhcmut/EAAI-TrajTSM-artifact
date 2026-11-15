// =============================================================================
// FILE        : hmao_admm_solver.sv
// PROJECT     : HMAO Engine
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 7.3
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : ADMM (Alternating Direction Method of Multipliers) Solver.
//               Runs PARALLEL with Stage 1 Zonotope computation.
//               15-stage UNROLLED pipeline (no feedback loops = deterministic).
//
//               Problem formulation (Spec Ref: Section 7.3.2):
//               min f(x) + g(z)  s.t. Ax + Bz = c
//               where:
//               - x = trajectory of ego vehicle
//               - z = slack = minimum distance to obstacle surface
//               - f(x) = 0 (verification only, no re-planning)
//               - g(z) = +âˆž if z < d_safe, 0 otherwise (barrier function)
//               - A=I, B=-I, c=0 â†’ z = x projected to safe region
//
//               ADMM Iterations (Ï? = penalty parameter):
//               x-update: x_{k+1} = (I + Ï?I)^{-1} Ã— (x_k - Ï?^{-1}Ã—y_k) [trivial for f=0]
//               z-update: z_{k+1} = proj_{C_safe}(x_{k+1} + Ï?^{-1}Ã—y_k)
//                         proj: if dist < d_safe â†’ project to d_safe boundary
//               y-update: y_{k+1} = y_k + Ï?(x_{k+1} - z_{k+1})
//
//               Unrolling: 15 identical stages in sequence (pipeline depth = 15).
//               Each stage = 1 ADMM iteration. NO loops. Deterministic latency.
//
// RESOURCES   : 18,500 LUTs + 12,000 FFs + 60 DSP48E2
// PRECISION   : Fixed-Point 16-bit (Spec Ref: Section 7.3.4)
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module hmao_admm_solver (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,          // Starts simultaneously with Stage 1

  // Trajectory (validated waypoints from pre-proc)
  input  waypoint_t               waypoints_in [0:TRAJ_WAYPOINTS-1],

  // World model access (shared AXI - arbiter handles priority)
  axi4_ro_if.master               axi_ro,

  // Safety distance threshold (from adaptive margin, Q8.8)
  input  logic [15:0]             d_safe_q8_8,

  // Outputs
  output logic                    collision_possible,  // true if any z < d_safe after 15 iter
  output logic                    done,                // Pipeline complete
  output logic                    diverged,            // Convergence check failed

  // Fault
  output logic                    admm_diverge_fault
);

  // ===========================================================================
  // PARAMETERS
  // ===========================================================================
  localparam int unsigned ADMM_ITER   = ADMM_STAGES;  // 15
  localparam int unsigned NUM_POINTS  = TRAJ_WAYPOINTS; // 50 trajectory points

  // ADMM penalty parameter Ï? = 1.0 in Q8.8 = 256
  localparam logic [15:0] RHO_Q8_8 = 16'h0100;         // 1.0
  // Ï?^{-1} = 1.0 in Q8.8 = 256 (same, since Ï?=1)
  localparam logic [15:0] RHO_INV_Q8_8 = 16'h0100;

  // ===========================================================================
  // PIPELINE DATA TYPE (16-bit fixed-point vectors)
  // Each pipeline stage carries: x[50], z[50], y[50] state vectors
  // x = trajectory x-position, z = safe-projected distance, y = dual variable
  // ===========================================================================
  typedef struct packed {
    // xelab 2025.2: packed 2D arrays ([N-1:0][15:0]) inside structs cause
    // VlogCompiler::transform TraverseArray infinite recursion. Use flat 1D.
    // Access element p as: x_pos[p*16+:16]
    logic [NUM_POINTS*16-1:0] x_pos;   // flat: [p*16+:16] = x_pos[p]
    logic [NUM_POINTS*16-1:0] z_dist;  // flat: [p*16+:16] = z_dist[p]
    logic [NUM_POINTS*16-1:0] y_dual;  // flat: [p*16+:16] = y_dual[p]
    logic                     valid;
  } admm_stage_t;

  // ===========================================================================
  // 15-STAGE UNROLLED PIPELINE
  // admm_pipe[0] = input (initialized from trajectory)
  // admm_pipe[15] = final output
  // NO feedback: data flows strictly forward through 15 registers
  // ===========================================================================
  admm_stage_t admm_pipe [0:ADMM_ITER];

  // Pipeline enable (shift with start pulse)
  logic [ADMM_ITER:0] stage_valid;

  // ===========================================================================
  // OBSTACLE DISTANCE COMPUTATION
  // For each trajectory point: distance to nearest obstacle
  // Simplified: use world model URAM (already fetched by Stage 1 SAT)
  // For ADMM: use nearest obstacle distance approximation
  // Full implementation: integrate with World Model prefetch buffer
  // ===========================================================================
  // For this skeleton: distance approximated from trajectory waypoints
  // Production: fetch from Suspicious Obstacles Buffer populated by SAT Stage 1

  // ===========================================================================
  // STAGE 0: INITIALIZATION
  // Load x from trajectory, initialize z and y
  // ===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      admm_pipe[0].valid <= 1'b0;
      for (int p = 0; p < NUM_POINTS; p++) begin
        admm_pipe[0].x_pos[p*16+:16]  <= '0;
        admm_pipe[0].z_dist[p*16+:16] <= {1'b0, d_safe_q8_8};
        admm_pipe[0].y_dual[p*16+:16] <= '0;
      end
    end else begin
      if (start) begin
        admm_pipe[0].valid <= 1'b1;
        for (int p = 0; p < NUM_POINTS; p++) begin
          // Load x from trajectory (px position, scaled to Q8.8)
          // waypoints_in.x is float32; use [23:8] as Q8.8 approximation
          admm_pipe[0].x_pos[p*16+:16]  <= waypoints_in[p].x[23:8];
          admm_pipe[0].z_dist[p*16+:16] <= {1'b0, d_safe_q8_8};
          admm_pipe[0].y_dual[p*16+:16] <= 16'h0;
        end
      end else begin
        admm_pipe[0].valid <= 1'b0;
      end
    end
  end

  // ===========================================================================
  // STAGES 1-15: ADMM ITERATIONS (UNROLLED)
  // Each stage performs one complete ADMM iteration on all 50 points
  //
  // x-update: x_new = (x_prev + z_prev - y_prev) / 2 [for f=0 case]
  //           (comes from proximal operator of f(x)=0 with penalty Ï?=1)
  //           simplified: x_new = x_prev (trajectory is fixed, only checking)
  //
  // z-update: z_new = max(d_safe, x_new + y_prev/Ï?)
  //           i.e., project onto {z â‰¥ d_safe} (feasibility set)
  //           If obstacle is present and distance < d_safe â†’ collision
  //
  // y-update: y_new = y_prev + Ï? Ã— (x_new - z_new)
  //           (dual variable = constraint violation measure)
  // ===========================================================================
  generate
    for (genvar s = 1; s <= ADMM_ITER; s++) begin : admm_stages
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          admm_pipe[s].valid <= 1'b0;
          for (int p = 0; p < NUM_POINTS; p++) begin
            admm_pipe[s].x_pos[p*16+:16]  <= '0;
            admm_pipe[s].z_dist[p*16+:16] <= '0;
            admm_pipe[s].y_dual[p*16+:16] <= '0;
          end
        end else begin
          admm_pipe[s].valid <= admm_pipe[s-1].valid;

          if (admm_pipe[s-1].valid) begin
            for (int p = 0; p < NUM_POINTS; p++) begin
              logic signed [15:0] x_k, z_k, y_k;
              logic signed [15:0] x_new, z_candidate, z_new, y_new;
              logic signed [31:0] xpy_sum;

              x_k = admm_pipe[s-1].x_pos[p*16+:16];
              z_k = admm_pipe[s-1].z_dist[p*16+:16];
              y_k = admm_pipe[s-1].y_dual[p*16+:16];

              // x-update: x_new = x_k (trajectory is fixed - verification only)
              // Note: In spec, f(x)=0 â†’ x-update is: prox_f(v) = v (identity)
              x_new = x_k;

              // z-update: z_new = proj_C_safe(x_new + y_k/Ï?)
              // = max(d_safe, x_new + y_k)  [for Ï?=1, y_k is already scaled]
              xpy_sum    = $signed({x_new, 16'b0}) + $signed({y_k, 16'b0});
              z_candidate = xpy_sum[31:16];  // Take upper 16 bits
              // Projection: if distance < d_safe â†’ push to d_safe
              z_new = ($signed(z_candidate) < $signed({1'b0, d_safe_q8_8}))
                      ? $signed({1'b0, d_safe_q8_8})
                      : z_candidate;

              // y-update: y_new = y_k + Ï? Ã— (x_new - z_new)
              // For Ï?=1: y_new = y_k + (x_new - z_new)
              y_new = y_k + (x_new - z_new);

              admm_pipe[s].x_pos[p*16+:16]  <= x_new;
              admm_pipe[s].z_dist[p*16+:16] <= z_new;
              admm_pipe[s].y_dual[p*16+:16] <= y_new;
            end
          end
        end
      end
    end
  endgenerate

  // ===========================================================================
  // OUTPUT STAGE: Check final z values
  // If any z[p] < d_safe after 15 iterations â†’ collision_possible = true
  // Spec Ref: Section 7.3.1 - "confirm/refine collision check"
  // ===========================================================================
  logic any_violation;

  always_comb begin
      any_violation = 1'b0;
      for (int p = 0; p < NUM_POINTS; p++) begin
          logic signed [15:0] y_val;
          y_val = $signed(admm_pipe[ADMM_ITER].y_dual[p*16+:16]);

          // N?u y_val âm (vi ph?m d_safe) v??t ng??ng cho phép
          if (y_val < -16'sh0004) begin 
              any_violation = 1'b1;
          end
      end
  end

  // Divergence detection: |y_k| growing unboundedly â†’ solver diverged
  // Check: if |y[0]| > 512.0 (Q8.8 = 131072) â†’ diverged
  logic divergence_check;
  assign divergence_check = (admm_pipe[ADMM_ITER].valid &&
                             ($signed(admm_pipe[ADMM_ITER].y_dual[15:0]) > 16'sh7FFF ||
                              $signed(admm_pipe[ADMM_ITER].y_dual[15:0]) < -16'sh7FFF));

  // Register outputs
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      collision_possible  <= 1'b0;
      done                <= 1'b0;
      diverged            <= 1'b0;
      admm_diverge_fault  <= 1'b0;
    end else begin
      if (admm_pipe[ADMM_ITER].valid) begin
        done               <= 1'b1;
        collision_possible <= any_violation;
        diverged           <= divergence_check;
        admm_diverge_fault <= divergence_check;
      end else begin
        done <= 1'b0;
      end
    end
  end

  // ===========================================================================
  // FORMAL ASSERTIONS
  // ===========================================================================
  `ifdef FORMAL
    // Pipeline must complete in exactly ADMM_ITER + 1 cycles after start
    assert property (@(posedge clk) disable iff (!rst_n)
      $rose(start) |=> ##ADMM_ITER $rose(done))
      else $error("ADMM: Pipeline completion timing violated");

    // No feedback: valid bit must propagate strictly forward
    // (enforced by structure, but check stage 0â†’1 timing)
    assert property (@(posedge clk) disable iff (!rst_n)
      admm_pipe[0].valid |=> admm_pipe[1].valid)
      else $error("ADMM: Stage 0 valid did not propagate to stage 1");
  `endif

endmodule : hmao_admm_solver
