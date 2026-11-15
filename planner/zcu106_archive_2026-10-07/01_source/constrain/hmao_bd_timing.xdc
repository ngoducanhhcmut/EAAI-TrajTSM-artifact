# ==============================================================================
# hmao_bd_timing.xdc
# BD-level timing constraints for ZCU104 (xczu7ev-ffvc1156-2-e)
# Clocks from PS PLL: clk_pl_0=185MHz, clk_pl_2=300MHz, clk_pl_3=250MHz
# ==============================================================================

# clk_pl_2 (HMAO main, 300 MHz) and clk_pl_3 (HMAO wdt, 250 MHz) are
# asynchronous: wdt_clk is an independent watchdog domain.
# CDC paths handled by hmao_cdc_bridge (hsync_chain synchronizers).
set_clock_groups -name cg_hmao_wdt -asynchronous \
    -group [get_clocks clk_pl_2] \
    -group [get_clocks clk_pl_3]

# -----------------------------------------------------------------------------
# v2d (05/10/2026): ket qua TSM (clk_pl_2) -> axi_gpio_1 (clk_pl_0, PS doc qua AXI-Lite).
# Du lieu tinh: chot khi hmao_complete len, giu toi lan hmao_start sau; PS chi doc sau
# ngat. tsm_status_pack chi la day noi. Gioi han do tre duong du lieu bang 1 chu ky
# clk_pl_0 thay vi dong timing giua hai clock co pha khong lien quan.
# -----------------------------------------------------------------------------
set_max_delay -datapath_only 6.666 \
  -from [get_cells -hierarchical -filter {NAME =~ "*hmao_engine_0/*" && IS_SEQUENTIAL}] \
  -to   [get_cells -hierarchical -filter {NAME =~ "*axi_gpio_1/*" && IS_SEQUENTIAL}]
