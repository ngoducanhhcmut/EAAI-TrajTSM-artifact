// =============================================================================
// FILE        : tb_hmao_sat_debug_probe.sv
// PURPOSE     : Waveform/print-level root-cause probe for the Section 28 /
//               Section 18-regression finding: hmao_engine_top now returns
//               GRANT for a real, genuinely-overlapping object (idx=24,
//               scene-0103, clearance=-2.41m) that Section 18 (2026-06-16)
//               proved correctly returns VETO. This TB drives EXACTLY that
//               one case (same traj_mv_024.hex, same object packing as
//               Section 18's own gen_hmao_full_pipeline_real_test.py) and
//               hierarchically probes hmao_collision_sat's u_s1_checker
//               instance at SAT_PREFILTER and SAT_DECIDE to see exactly why
//               it now finds no_collision=1 for this object.
// HAND-WRITTEN, not generated. Delete or move after the investigation.
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module tb_hmao_sat_debug_probe;

  localparam real HMAO_CLK_HALF = 1.25;
  localparam real WDT_CLK_HALF  = 1.852;
  logic hmao_clk = 1'b0;
  logic wdt_clk  = 1'b0;
  always #(HMAO_CLK_HALF) hmao_clk = ~hmao_clk;
  always #(WDT_CLK_HALF)  wdt_clk  = ~wdt_clk;

  logic hmao_rst_n = 1'b0;
  initial begin
    hmao_rst_n = 1'b0;
    repeat(20) @(posedge hmao_clk);
    hmao_rst_n = 1'b1;
  end

  logic       hmao_start    = 1'b0;
  logic [7:0] gps_quality   = 8'd200;
  logic [7:0] cam_quality   = 8'd200;
  logic [7:0] road_friction = 8'd200;
  logic [7:0] act_health    = 8'd255;
  logic [7:0] weather       = 8'd0;
  logic        hmao_complete;
  logic        hmao_decision;
  logic [63:0] hmao_violation;
  logic [31:0] hmao_status;
  logic [31:0] hmao_latency;
  logic [15:0] lat_margin, long_margin, time_margin;
  logic        irq_clear = 1'b0;
  hmao_fault_t fault_out;
  logic        fault_valid;
  logic        dbg_start_preproc, dbg_preproc_valid, dbg_preproc_error;
  logic [6:0]  dbg_fsm_raw;
  logic        dbg_hmao_start_rx;

  logic [31:0] traj_mem [0:350];
  logic [31:0] wm_mem   [0:1663];  // full MAX_OBSTACLES=100 x 64B = 1600 words (was 512, OOB for obs_idx>~31)

  logic [31:0]  hmao_araddr;
  logic [7:0]   hmao_arlen;
  logic [2:0]   hmao_arsize;
  logic [1:0]   hmao_arburst;
  logic         hmao_arvalid;
  logic [7:0]   hmao_aruser;
  logic         hmao_arready;
  logic [255:0] hmao_rdata;
  logic [1:0]   hmao_rresp  = 2'b00;
  logic         hmao_rlast  = 1'b0;
  logic         hmao_rvalid = 1'b0;
  logic         hmao_rready;
  logic [7:0]  axi_beats_rem;
  logic [10:0] axi_beat_woff;
  logic        axi_in_traj_rgn;
  logic        axi_in_wm_rgn;
  logic        axi_wm_wide;
  logic ar_accepted;
  assign ar_accepted = hmao_arvalid && hmao_arready;

  always_comb begin
    if (axi_in_traj_rgn)
      hmao_rdata = ({224'd0, traj_mem[axi_beat_woff]} << {axi_beat_woff[2:0], 5'b0});
    else if (axi_in_wm_rgn)
      hmao_rdata = {wm_mem[axi_beat_woff+7], wm_mem[axi_beat_woff+6],
                    wm_mem[axi_beat_woff+5], wm_mem[axi_beat_woff+4],
                    wm_mem[axi_beat_woff+3], wm_mem[axi_beat_woff+2],
                    wm_mem[axi_beat_woff+1], wm_mem[axi_beat_woff+0]};
    else
      hmao_rdata = '0;
  end

  always_ff @(posedge hmao_clk) begin
    if (!hmao_rst_n) begin
      hmao_rvalid <= 1'b0; hmao_rlast <= 1'b0; hmao_rresp <= 2'b00;
      axi_beats_rem <= '0; axi_beat_woff <= '0;
      axi_in_traj_rgn <= 1'b0; axi_in_wm_rgn <= 1'b0; axi_wm_wide <= 1'b0;
    end else begin
      if (ar_accepted) begin
        axi_beats_rem   <= hmao_arlen;
        axi_in_traj_rgn <= (hmao_araddr >= TRAJ_BUFFER_BASE &&
                            hmao_araddr <  TRAJ_BUFFER_BASE + 32'h0578);
        axi_in_wm_rgn   <= (hmao_araddr >= WORLD_MODEL_BASE &&
                            hmao_araddr <  WORLD_MODEL_BASE + 32'h0020_0000);
        axi_wm_wide     <= (hmao_arsize == 3'b101);
        if (hmao_araddr >= WORLD_MODEL_BASE)
          axi_beat_woff <= 11'((hmao_araddr - WORLD_MODEL_BASE) >> 2);
        else
          axi_beat_woff <= 11'((hmao_araddr - TRAJ_BUFFER_BASE) >> 2);
      end
      if (ar_accepted) begin
        hmao_rvalid <= 1'b1;
        hmao_rlast  <= (hmao_arlen == 8'd0);
        hmao_rresp  <= 2'b00;
      end else if (hmao_rvalid && hmao_rready) begin
        if (hmao_rlast) begin
          hmao_rvalid <= 1'b0; hmao_rlast <= 1'b0;
        end else begin
          axi_beat_woff <= axi_beat_woff + (axi_wm_wide ? 11'd8 : 11'd1);
          axi_beats_rem <= axi_beats_rem - 1'b1;
          hmao_rlast    <= (axi_beats_rem == 8'd1);
        end
      end
    end
  end
  assign hmao_arready = !hmao_rvalid;

  axi4_ro_if #(.ADDR_W(AXI_ADDR_W), .DATA_W(AXI_DATA_W), .ID_W(AXI_ID_W))
    u_axi_ro (.aclk(hmao_clk), .aresetn(hmao_rst_n));
  hmao_pipe_if u_pipe();

  hmao_engine_top u_hmao (
    .clk(hmao_clk), .rst_n(hmao_rst_n), .hmao_start(hmao_start),
    .gps_quality(gps_quality), .camera_quality(cam_quality),
    .road_friction(road_friction), .actuator_health(act_health),
    .weather_severity(weather), .axi_ro(u_axi_ro), .pipe(u_pipe),
    .wdt_clk(wdt_clk), .hmao_complete(hmao_complete),
    .hmao_decision_out(hmao_decision), .hmao_violation_out(hmao_violation),
    .hmao_status_out(hmao_status), .hmao_latency_out(hmao_latency),
    .lateral_margin_out(lat_margin), .long_margin_out(long_margin),
    .time_margin_out(time_margin), .irq_clear(irq_clear),
    .debug_start_preproc(dbg_start_preproc),
    .debug_fsm_state_encoded(dbg_fsm_raw),
    .debug_hmao_start_received(dbg_hmao_start_rx),
    .debug_preproc_valid(dbg_preproc_valid),
    .debug_preproc_error(dbg_preproc_error),
    .fault_out(fault_out), .fault_valid_out(fault_valid)
  );

  assign hmao_araddr  = u_axi_ro.araddr;
  assign hmao_arlen   = u_axi_ro.arlen;
  assign hmao_arsize  = u_axi_ro.arsize;
  assign hmao_arburst = u_axi_ro.arburst;
  assign hmao_arvalid = u_axi_ro.arvalid;
  assign hmao_aruser  = u_axi_ro.aruser;
  assign hmao_rready  = u_axi_ro.rready;
  assign u_axi_ro.arready = hmao_arready;
  assign u_axi_ro.rid     = '0;
  assign u_axi_ro.rdata   = hmao_rdata;
  assign u_axi_ro.rresp   = hmao_rresp;
  assign u_axi_ro.rlast   = hmao_rlast;
  assign u_axi_ro.rvalid  = hmao_rvalid;

  // ===========================================================================
  // PROBE: fire once per sat_state transition for u_s1_checker, print the
  // exact values used in obs_in_bbox / axis_separated decisions.
  // ===========================================================================
  logic [6:0] obs_idx_prev = 7'h7F;
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s1_checker.obs_idx !== obs_idx_prev && u_hmao.u_s1_checker.sat_state == 4'b0001 /* SAT_FETCH */) begin
      obs_idx_prev <= u_hmao.u_s1_checker.obs_idx;
      $display("[OBSIDX @%0t] now scanning obs_idx=%0d", $time, u_hmao.u_s1_checker.obs_idx);
    end
  end

  logic [3:0] sat_state_prev = 4'hF;
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s1_checker.sat_state !== sat_state_prev) begin
      sat_state_prev <= u_hmao.u_s1_checker.sat_state;
      case (u_hmao.u_s1_checker.sat_state)
        4'b0010: begin // SAT_PREFILTER
          $display("[PROBE @%0t] SAT_PREFILTER obs_idx=%0d obs_confidence=%0d obs_pos_x=%0d(=%.3fm) obs_pos_y=%0d(=%.3fm) bbox_xmin=%0d(%.3fm) bbox_xmax=%0d(%.3fm) bbox_ymin=%0d(%.3fm) bbox_ymax=%0d(%.3fm) obs_in_bbox=%b",
            $time, u_hmao.u_s1_checker.obs_idx, u_hmao.u_s1_checker.obs_confidence,
            $signed(u_hmao.u_s1_checker.obs_pos_x), $itor($signed(u_hmao.u_s1_checker.obs_pos_x))/256.0,
            $signed(u_hmao.u_s1_checker.obs_pos_y), $itor($signed(u_hmao.u_s1_checker.obs_pos_y))/256.0,
            $signed(u_pipe.bbox_xmin), $itor($signed(u_pipe.bbox_xmin))/256.0,
            $signed(u_pipe.bbox_xmax), $itor($signed(u_pipe.bbox_xmax))/256.0,
            $signed(u_pipe.bbox_ymin), $itor($signed(u_pipe.bbox_ymin))/256.0,
            $signed(u_pipe.bbox_ymax), $itor($signed(u_pipe.bbox_ymax))/256.0,
            u_hmao.u_s1_checker.obs_in_bbox);
        end
        4'b0111: begin // SAT_DONE
          $display("[PROBE @%0t] SAT_DONE obs_idx=%0d violation_found=%b suspicious_count=%0d no_collision(next)=%b potential_coll(next)=%b",
            $time, u_hmao.u_s1_checker.obs_idx, u_hmao.u_s1_checker.violation_found,
            u_hmao.u_s1_checker.suspicious_count,
            (u_hmao.u_s1_checker.suspicious_count == 0 || !u_hmao.u_s1_checker.violation_found),
            !(u_hmao.u_s1_checker.suspicious_count == 0 || !u_hmao.u_s1_checker.violation_found));
        end
        default: ;
      endcase
    end
  end
  // Also catch every SAT_DECIDE cycle where collision_this_step evaluates,
  // to see the per-axis separation result for the one real step that matters.
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s1_checker.sat_state == 4'b0110 /* SAT_DECIDE */) begin
      $display("[PROBE @%0t] SAT_DECIDE step=%0d axis_sep=%b collision_this_step=%b dv=[%0d %0d %0d %0d %0d %0d %0d %0d] ro=[%0d %0d %0d %0d %0d %0d %0d %0d]",
        $time, u_hmao.u_s1_checker.step_idx, u_hmao.u_s1_checker.axis_separated,
        u_hmao.u_s1_checker.collision_this_step,
        $signed(u_hmao.u_s1_checker.dv0), $signed(u_hmao.u_s1_checker.dv1),
        $signed(u_hmao.u_s1_checker.dv2), $signed(u_hmao.u_s1_checker.dv3),
        $signed(u_hmao.u_s1_checker.dv4), $signed(u_hmao.u_s1_checker.dv5),
        $signed(u_hmao.u_s1_checker.dv6), $signed(u_hmao.u_s1_checker.dv7),
        $signed(u_hmao.u_s1_checker.ro0), $signed(u_hmao.u_s1_checker.ro1),
        $signed(u_hmao.u_s1_checker.ro2), $signed(u_hmao.u_s1_checker.ro3),
        $signed(u_hmao.u_s1_checker.ro4), $signed(u_hmao.u_s1_checker.ro5),
        $signed(u_hmao.u_s1_checker.ro6), $signed(u_hmao.u_s1_checker.ro7));
    end
  end

  // Zonotope generator internals probe (u_s1_zonotope is Stage-1 zonotope_gen instance)
  logic [6:0] zg_step_idx_prev = 7'h7F;
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s1_zonotope.step_idx !== zg_step_idx_prev) begin
      zg_step_idx_prev <= u_hmao.u_s1_zonotope.step_idx;
      $display("[ZGPROBE @%0t] step_idx->%0d gen_flat2=%h gen_flat3=%h rot_active=%b rot_idx=%0d",
        $time, u_hmao.u_s1_zonotope.step_idx,
        u_hmao.u_s1_zonotope.gen_flat[2], u_hmao.u_s1_zonotope.gen_flat[3],
        u_hmao.u_s1_zonotope.rot_active, u_hmao.u_s1_zonotope.rot_idx);
    end
  end

  // DEEP PROBE: dump the RAW zonotopes_out bit-slice for step 21 the instant
  // zonotope_gen finishes (zg_state==ZG_DONE), and every cycle of
  // collision_sat's own mux output + 3-stage pipeline while sat step_idx==21.
  localparam int S21 = 22;  // CE_008: idx=260, closest approach at step 22/49
  logic zg_done_printed = 1'b0;
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s1_zonotope.zg_state == 2'b11 /* ZG_DONE */ && !zg_done_printed) begin
      zg_done_printed <= 1'b1;
      $display("[ZGDONE @%0t] zonotopes_out[21*128+:128]=%h",
        $time, u_hmao.u_s1_zonotope.zonotopes_out[S21*128 +: 128]);
    end
  end

  always @(posedge hmao_clk) begin
    if (u_hmao.u_s1_checker.sat_state == 4'b0011 /* SAT_AXES */ &&
        u_hmao.u_s1_checker.step_idx == S21) begin
      $display("[SAT21 @%0t] zon_cx=%h zon_cy=%h zon_g1x=%h zon_g1y=%h zon_g2x=%h zon_g2y=%h  RAW_SLICE(s=21)=%h  cur_g1x(prev)=%h cur_g2x(prev)=%h",
        $time,
        u_hmao.u_s1_checker.zon_cx, u_hmao.u_s1_checker.zon_cy,
        u_hmao.u_s1_checker.zon_g1x, u_hmao.u_s1_checker.zon_g1y,
        u_hmao.u_s1_checker.zon_g2x, u_hmao.u_s1_checker.zon_g2y,
        u_hmao.u_s1_checker.zonotopes_in[S21*128 +: 128],
        u_hmao.u_s1_checker.cur_g1x, u_hmao.u_s1_checker.cur_g2x);
    end
    if (u_hmao.u_s1_checker.sat_state == 4'b0100 /* SAT_PIPE1 */ &&
        u_hmao.u_s1_checker.step_idx == S21) begin
      $display("[SAT21-PIPE1 @%0t] cur_g1x=%h cur_g1y=%h cur_g2x=%h cur_g2y=%h cur_cx=%h cur_cy=%h  ax0..7=%h %h %h %h %h %h %h %h  ay0..7=%h %h %h %h %h %h %h %h",
        $time,
        u_hmao.u_s1_checker.cur_g1x, u_hmao.u_s1_checker.cur_g1y,
        u_hmao.u_s1_checker.cur_g2x, u_hmao.u_s1_checker.cur_g2y,
        u_hmao.u_s1_checker.cur_cx, u_hmao.u_s1_checker.cur_cy,
        u_hmao.u_s1_checker.ax0, u_hmao.u_s1_checker.ax1, u_hmao.u_s1_checker.ax2, u_hmao.u_s1_checker.ax3,
        u_hmao.u_s1_checker.ax4, u_hmao.u_s1_checker.ax5, u_hmao.u_s1_checker.ax6, u_hmao.u_s1_checker.ax7,
        u_hmao.u_s1_checker.ay0, u_hmao.u_s1_checker.ay1, u_hmao.u_s1_checker.ay2, u_hmao.u_s1_checker.ay3,
        u_hmao.u_s1_checker.ay4, u_hmao.u_s1_checker.ay5, u_hmao.u_s1_checker.ay6, u_hmao.u_s1_checker.ay7);
    end
    if (u_hmao.u_s1_checker.sat_state == 4'b0101 /* SAT_PIPE2 */ &&
        u_hmao.u_s1_checker.step_idx == S21) begin
      $display("[SAT21-PIPE2 @%0t] ax_p1[0..7]=%h %h %h %h %h %h %h %h  dc_x_p1=%h dc_y_p1=%h dim_w_p1=%h dim_l_p1=%h",
        $time,
        u_hmao.u_s1_checker.ax0_p1, u_hmao.u_s1_checker.ax1_p1, u_hmao.u_s1_checker.ax2_p1, u_hmao.u_s1_checker.ax3_p1,
        u_hmao.u_s1_checker.ax4_p1, u_hmao.u_s1_checker.ax5_p1, u_hmao.u_s1_checker.ax6_p1, u_hmao.u_s1_checker.ax7_p1,
        u_hmao.u_s1_checker.dc_x_p1, u_hmao.u_s1_checker.dc_y_p1,
        u_hmao.u_s1_checker.dim_w_p1, u_hmao.u_s1_checker.dim_l_p1);
    end
    if (u_hmao.u_s1_checker.sat_state == 4'b1001 /* SAT_PIPE3 */ &&
        u_hmao.u_s1_checker.step_idx == S21) begin
      $display("[SAT21-PIPE3 @%0t] dp0..7_p2=%h %h %h %h %h %h %h %h  pw0..7_p2=%h %h %h %h %h %h %h %h  pl0..7_p2=%h %h %h %h %h %h %h %h",
        $time,
        u_hmao.u_s1_checker.dp0_p2, u_hmao.u_s1_checker.dp1_p2, u_hmao.u_s1_checker.dp2_p2, u_hmao.u_s1_checker.dp3_p2,
        u_hmao.u_s1_checker.dp4_p2, u_hmao.u_s1_checker.dp5_p2, u_hmao.u_s1_checker.dp6_p2, u_hmao.u_s1_checker.dp7_p2,
        u_hmao.u_s1_checker.pw0_p2, u_hmao.u_s1_checker.pw1_p2, u_hmao.u_s1_checker.pw2_p2, u_hmao.u_s1_checker.pw3_p2,
        u_hmao.u_s1_checker.pw4_p2, u_hmao.u_s1_checker.pw5_p2, u_hmao.u_s1_checker.pw6_p2, u_hmao.u_s1_checker.pw7_p2,
        u_hmao.u_s1_checker.pl0_p2, u_hmao.u_s1_checker.pl1_p2, u_hmao.u_s1_checker.pl2_p2, u_hmao.u_s1_checker.pl3_p2,
        u_hmao.u_s1_checker.pl4_p2, u_hmao.u_s1_checker.pl5_p2, u_hmao.u_s1_checker.pl6_p2, u_hmao.u_s1_checker.pl7_p2);
    end
  end

  // ===========================================================================
  // STAGE 2 PROBE: u_s2_checker (fine check, only runs if Stage1 potential_coll=1)
  // ===========================================================================
  logic [3:0] s2_state_prev = 4'hF;
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s2_checker.sat_state !== s2_state_prev) begin
      s2_state_prev <= u_hmao.u_s2_checker.sat_state;
      case (u_hmao.u_s2_checker.sat_state)
        4'b0001: $display("[S2 @%0t] SAT_FETCH obs_idx=%0d", $time, u_hmao.u_s2_checker.obs_idx);
        4'b0010: $display("[S2 @%0t] SAT_PREFILTER obs_idx=%0d obs_confidence=%0d obs_pos_x=%0d obs_pos_y=%0d obs_in_bbox=%b",
          $time, u_hmao.u_s2_checker.obs_idx, u_hmao.u_s2_checker.obs_confidence,
          $signed(u_hmao.u_s2_checker.obs_pos_x), $signed(u_hmao.u_s2_checker.obs_pos_y),
          u_hmao.u_s2_checker.obs_in_bbox);
        4'b0111: $display("[S2 @%0t] SAT_DONE obs_idx=%0d violation_found=%b suspicious_count=%0d",
          $time, u_hmao.u_s2_checker.obs_idx, u_hmao.u_s2_checker.violation_found,
          u_hmao.u_s2_checker.suspicious_count);
        default: ;
      endcase
    end
  end
  always @(posedge hmao_clk) begin
    if (u_hmao.u_s2_checker.sat_state == 4'b0110 /* SAT_DECIDE */)
      $display("[S2DECIDE @%0t] step=%0d axis_sep=%b collision_this_step=%b dv=[%0d %0d %0d %0d %0d %0d %0d %0d] ro=[%0d %0d %0d %0d %0d %0d %0d %0d] cur_cx=%0d cur_cy=%0d",
        $time, u_hmao.u_s2_checker.step_idx, u_hmao.u_s2_checker.axis_separated,
        u_hmao.u_s2_checker.collision_this_step,
        $signed(u_hmao.u_s2_checker.dv0), $signed(u_hmao.u_s2_checker.dv1),
        $signed(u_hmao.u_s2_checker.dv2), $signed(u_hmao.u_s2_checker.dv3),
        $signed(u_hmao.u_s2_checker.dv4), $signed(u_hmao.u_s2_checker.dv5),
        $signed(u_hmao.u_s2_checker.dv6), $signed(u_hmao.u_s2_checker.dv7),
        $signed(u_hmao.u_s2_checker.ro0), $signed(u_hmao.u_s2_checker.ro1),
        $signed(u_hmao.u_s2_checker.ro2), $signed(u_hmao.u_s2_checker.ro3),
        $signed(u_hmao.u_s2_checker.ro4), $signed(u_hmao.u_s2_checker.ro5),
        $signed(u_hmao.u_s2_checker.ro6), $signed(u_hmao.u_s2_checker.ro7),
        $signed(u_hmao.u_s2_checker.cur_cx), $signed(u_hmao.u_s2_checker.cur_cy));
  end
  always @(posedge hmao_clk) begin
    if (u_pipe.s2_zono_valid) $display("[S2ZONO @%0t] s2_zono_valid pulsed", $time);
    if (u_pipe.s2_no_collision) $display("[S2RESULT @%0t] pipe.s2_no_collision=1", $time);
    if (u_pipe.s2_collision_confirmed) $display("[S2RESULT @%0t] pipe.s2_collision_confirmed=1", $time);
  end

  task automatic reset_dut();
    hmao_rst_n = 1'b0; irq_clear = 1'b0; hmao_start = 1'b0;
    repeat(20) @(posedge hmao_clk);
    hmao_rst_n = 1'b1;
    repeat(20) @(posedge hmao_clk);
  endtask

  task automatic run_hmao_engine(input int timeout_cy, output logic ok, output logic decision, output logic [7:0] fault_bits);
    ok = 1'b0; decision = 1'b0; fault_bits = 8'h0;
    @(posedge hmao_clk); hmao_start <= 1'b1;
    @(posedge hmao_clk); hmao_start <= 1'b0;
    for (int c = 0; c < timeout_cy; c++) begin
      @(posedge hmao_clk);
      if (hmao_complete) begin ok = 1'b1; break; end
    end
    @(posedge hmao_clk);
    if (ok) begin decision = hmao_decision; fault_bits = fault_out; end
  endtask

  initial begin
    logic hmao_ok, decision;
    logic [7:0] fault_bits;
    // CE_008: idx=260, scene-1077, real car, clearance -2.24m -- still failing
    // (GRANT instead of VETO) after BUG-FIX ZG-007/ZG-008. Real closest
    // approach at step 22/49 (dist 0.075m). Load the actual generated hex
    // files directly (same encoding as tb_hmao_collision_e2e_real_nuscenes.sv).
    reset_dut();
    $readmemh("sw/hmao_payloads/collision_e2e/CE_008_traj.hex", traj_mem);
    foreach (wm_mem[i]) wm_mem[i] = 32'h0;
    $readmemh("sw/hmao_payloads/collision_e2e/CE_008_wm.hex", wm_mem);

    $display("================================================================");
    $display("  SAT DEBUG PROBE -- CE_008 idx=260 scene-1077 car clearance=-2.24m");
    $display("================================================================");

    run_hmao_engine(2_000_000, hmao_ok, decision, fault_bits);
    $display("RESULT: Decision=%s Faults=0x%02h Latency=%0d cy",
              decision?"GRANT":"VETO", fault_bits, hmao_latency);
    $finish;
  end

endmodule
