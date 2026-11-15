`timescale 1ns/1ps
// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// hmao_gpio_cdc_bridge.sv — PS AXI GPIO -> HMAO control CDC bridge
// ================================================================================
// ROOT CAUSE THIS FIXES (2026-08-04 real-board rebuild failure):
//   add_hmao_gpio_control.tcl replaced the xlconstant_0-tied-to-0 dead end on
//   hmao_engine_0/hmao_start and hmao_engine_0/irq_clear with axi_gpio_0, wired
//   with a PLAIN combinational net straight from axi_gpio_0 (clocked by
//   s_axi_aclk = clk_pl_0, 185 MHz) into hmao_engine_0's inputs (clocked by
//   clk_pl_2, 300 MHz) -- zero synchronization in between. This is not merely
//   a timing-closure problem: it is a genuine, unconstrained clock-domain
//   crossing with real metastability risk on silicon. Static timing analysis
//   correctly flagged it as catastrophic (WNS -1.167 ns, TNS -2034.76 ns,
//   6065 failing endpoints across the entire hmao_start fan-out -- every
//   register gated by "if (hmao_start)" downstream, e.g. global_timer,
//   u_s1_zonotope/gen_flat[], etc.) because no set_clock_groups/set_false_path
//   excluded this specific new path.
//
// WHAT THIS MODULE DOES:
//   axi_gpio_0's two output channels are LEVEL signals held by software for a
//   few clk_pl_0 AXI-Lite write cycles (not true single-cycle pulses) -- see
//   the firmware sequence documented in add_hmao_gpio_control.tcl. This
//   bridge:
//     1. Edge-detects each GPIO level in the clk_pl_0 domain -> clean 1-cycle
//        src pulse, regardless of how long software holds the level high.
//     2. Converts each src pulse to a toggle bit (level-encoded request --
//        immune to pulse width and clock-ratio effects), matching EXACTLY
//        the pattern already used and proven by hmao_cdc_bridge.sv for the
//        waypoint bus and by cdc_pulse_sync.sv elsewhere in this codebase.
//     3. Synchronizes the toggle bit into the HMAO clock domain via
//        hsync_chain (3-stage, ASYNC_REG-tagged).
//     4. Edge-detects the synchronized toggle -> clean 1-cycle pulse in the
//        HMAO domain, matching the semantics hmao_engine_top already expects
//        for hmao_start (a single-cycle pulse; hmao_engine_top internally
//        stretches it via hmao_start_sr for the WDT kick) and irq_clear.
//
// REQUIRED XDC (added separately, see constrain/hmao_gpio_cdc.xdc):
//   set_false_path from the toggle registers to the first synchronizer stage.
//   Without this, the same class of violation reappears even though the
//   circuit is now functionally correct -- STA has no way to know a
//   synchronizer's first stage is a deliberate, metastability-tolerant
//   capture point unless told so explicitly.
// ================================================================================

module hmao_gpio_cdc_bridge (
  // Source domain: clk_pl_0 (185 MHz) -- axi_gpio_0's registered outputs live here
  input  logic src_clk,
  input  logic src_rst_n,
  input  logic gpio_start_level,     // axi_gpio_0 channel 1 dout (PS-driven level)
  input  logic gpio_irqclr_level,    // axi_gpio_0 channel 2 dout (PS-driven level)

  // Destination domain: HMAO engine clock (clk_pl_2, 300 MHz today / 250 MHz if relaxed)
  input  logic dst_clk,
  input  logic dst_rst_n,
  output logic hmao_start_pulse,     // 1-cycle pulse @ dst_clk -> hmao_engine_0/hmao_start
  output logic irq_clear_pulse       // 1-cycle pulse @ dst_clk -> hmao_engine_0/irq_clear
);

  // ---------------------------------------------------------------------------
  // Stage 0 (src_clk domain): edge-detect the PS-driven GPIO level, then latch
  // a toggle bit on each rising edge. The toggle encoding means the request is
  // captured exactly once per GPIO pulse regardless of how many src_clk cycles
  // software happened to hold the level high for.
  // ---------------------------------------------------------------------------
  logic start_lvl_r, irqclr_lvl_r;
  logic start_toggle, irqclr_toggle;

  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      start_lvl_r   <= 1'b0;
      irqclr_lvl_r  <= 1'b0;
      start_toggle  <= 1'b0;
      irqclr_toggle <= 1'b0;
    end else begin
      start_lvl_r  <= gpio_start_level;
      irqclr_lvl_r <= gpio_irqclr_level;
      if (gpio_start_level  & ~start_lvl_r)  start_toggle  <= ~start_toggle;
      if (gpio_irqclr_level & ~irqclr_lvl_r) irqclr_toggle <= ~irqclr_toggle;
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 1 (dst_clk domain): 3-stage synchronizer per toggle bit.
  // ASYNC_REG applied directly on hsync_chain's internal sync_r registers
  // (declared inside hsync_chain.sv is not tagged there, so tag it here via
  // the instance -- Vivado accepts ASYNC_REG on the instantiated register
  // array through the hierarchical cell reference in XDC; see
  // constrain/hmao_gpio_cdc.xdc for the matching set_false_path).
  // ---------------------------------------------------------------------------
  logic start_sync, irqclr_sync;

  hsync_chain #(.WIDTH(1), .STAGES(3)) u_start_sync (
    .clk   (dst_clk),
    .rst_n (dst_rst_n),
    .d_in  (start_toggle),
    .d_out (start_sync)
  );

  hsync_chain #(.WIDTH(1), .STAGES(3)) u_irqclr_sync (
    .clk   (dst_clk),
    .rst_n (dst_rst_n),
    .d_in  (irqclr_toggle),
    .d_out (irqclr_sync)
  );

  // ---------------------------------------------------------------------------
  // Stage 2 (dst_clk domain): edge-detect the synchronized toggle -> 1-cycle
  // pulse. Any edge (rising or falling of the toggle bit) means one request
  // was captured -- XOR with the previous cycle's value catches both.
  // ---------------------------------------------------------------------------
  logic start_sync_prev, irqclr_sync_prev;

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      start_sync_prev  <= 1'b0;
      irqclr_sync_prev <= 1'b0;
    end else begin
      start_sync_prev  <= start_sync;
      irqclr_sync_prev <= irqclr_sync;
    end
  end

  assign hmao_start_pulse = start_sync  ^ start_sync_prev;
  assign irq_clear_pulse  = irqclr_sync ^ irqclr_sync_prev;

endmodule
// ================================================================================
