// =============================================================================
// hmao_gpio_cdc_bridge_bd_ref.v
// Pure-Verilog shim for Vivado Block Design module reference.
//
// Vivado 2023.2 restriction: BD module-reference top file must be .v, not .sv
// (confirmed here: create_bd_cell -type module -reference on the raw .sv file
// fails with "[filemgmt 56-195] ... This type is not allowed as the top file
// in the reference"). This shim carries X_INTERFACE attributes for the two
// clock/reset pairs, then instantiates hmao_gpio_cdc_bridge (SystemVerilog).
// =============================================================================
`timescale 1ns/1ps

module hmao_gpio_cdc_bridge_bd_ref (
  // ── Source domain: clk_pl_0 (axi_gpio_0's domain) ──────────────────────────
  // NOTE: no hardcoded FREQ_HZ here on purpose. clk_pl_0's actual achieved
  // rate (166.666672 MHz per the PS IP's create_clock -period 6, discovered
  // 2026-08-04) does not match the 185 MHz value documented elsewhere in this
  // project. Asserting either number here would just create another stale
  // metadata mismatch the moment one of them changes; letting BD propagate
  // FREQ_HZ from the actually-connected net avoids that class of bug entirely.
  (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 src_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET src_rst_n" *)
  input  wire   src_clk,
  (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 src_rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire   src_rst_n,
  input  wire   gpio_start_level,
  input  wire   gpio_irqclr_level,

  // ── Destination domain: HMAO engine clock (clk_pl_2) ──────────────────────
  (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 dst_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET dst_rst_n" *)
  input  wire   dst_clk,
  (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 dst_rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire   dst_rst_n,
  output wire   hmao_start_pulse,
  output wire   irq_clear_pulse
);

  hmao_gpio_cdc_bridge u_bridge (
    .src_clk           (src_clk),
    .src_rst_n         (src_rst_n),
    .gpio_start_level  (gpio_start_level),
    .gpio_irqclr_level (gpio_irqclr_level),
    .dst_clk           (dst_clk),
    .dst_rst_n         (dst_rst_n),
    .hmao_start_pulse  (hmao_start_pulse),
    .irq_clear_pulse   (irq_clear_pulse)
  );

endmodule
