# Claude 10/11/2026: VCU118 joint design. DDR4 C1, 250 MHz system clock, UART, IIC and reset come from the
# board interfaces (board part 2.4). Only the two TSM-X outputs are placed here (pins from the 2.4 board file).
set_property PACKAGE_PIN AT32 [get_ports brake_0]
set_property PACKAGE_PIN AV34 [get_ports heartbeat_0]
set_property IOSTANDARD LVCMOS12 [get_ports {brake_0 heartbeat_0}]
set_property DRIVE 8 [get_ports {brake_0 heartbeat_0}]
set_false_path -to [get_ports {brake_0 heartbeat_0}]
# The 100/150/300 MHz clocks come from one MMCM (clk_wiz_0), so their crossings are timed as synchronous;
# planner CDC (hmao_cdc_bridge) carries its own constraints from the v2d build if any are needed.
