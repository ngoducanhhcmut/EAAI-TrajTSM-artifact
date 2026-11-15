# Claude 11/11/2026: VCU118 joint floorplan, sourced before place_design (STEPS.PLACE_DESIGN.TCL.PRE).
# Unconstrained placement put 49 % of the LUTs in SLR0 and 32 % in SLR2 with SLR1 empty, so DDR4 C1 (banks 71/72,
# SLR2) <-> planner <-> TSM-X paths crossed two SLR boundaries: routed WNS -2.97 ns at 100 MHz, 80-92 % route delay.
# SLR2 (next to the DDR4 C1 I/O): MIG, DDR SmartConnect, planner (the DDR reader).
# SLR1: TSM-X, its AXIS FIFO, MicroBlaze subsystem and peripherals. Every path crosses at most one SLR boundary.
set pb2 [create_pblock pb_slr2_ddr_planner]
resize_pblock $pb2 -add SLR2
set c2 [get_cells -quiet {system_i/ddr4_0 system_i/sc_ddr system_i/plan_0}]
add_cells_to_pblock $pb2 $c2
set pb1 [create_pblock pb_slr1_tsmx_mb]
resize_pblock $pb1 -add SLR1
set c1 [get_cells -quiet {system_i/tsmx_0 system_i/axis_fifo system_i/microblaze_0 system_i/microblaze_0_local_memory
  system_i/mdm_1 system_i/sc_mb system_i/uart_0 system_i/iic_0 system_i/timer_0 system_i/gpio_0}]
add_cells_to_pblock $pb1 $c1
puts "###FLOORPLAN SLR2 cells=[llength $c2] ([join $c2 { }])  SLR1 cells=[llength $c1]"
