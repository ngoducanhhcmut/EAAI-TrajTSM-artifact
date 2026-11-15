# Claude 10/11/2026: VCU118 (XCVU9P) joint bitstream: Traj planner + TSM-X (P=G=2) + MicroBlaze firmware.
#   vivado -mode batch -source journalQ1/tsmx_hw/vcu118/build_vcu118_joint.tcl            (full build, needs licence)
#   VCU118_STOP=bd   -> stop after validate_bd_design + wrapper (no licence needed; used for PC-side checking)
#   VCU118_DDR=083|062 -> DDR4 C1 board interface; MUST match the board revision label (default 083)
#
# Clocking: MIG ui_clk 300 MHz -> clk_wiz: 100 MHz (MicroBlaze, peripherals, TSM-X: the 100 MHz monitor clock of
#   the paper), 150 MHz (planner clk, the signed-off planner clock), 300 MHz (planner hmao_clk domain, as in v2d).
# Address map, MicroBlaze data space:
#   0x0000_0000 LMB 128 KB | 0x4000_0000 GPIO (bit0 = planner reset release) | 0x4060_0000 UART | 0x4080_0000 IIC | 0x41C0_0000 TIMER
#   0x44A0_0000 planner CSR 4 KB | 0x44A1_0000 TSM-X shim 4 KB | 0x44A2_0000 TSM-X CSR 64 KB | 0x44A3_0000 AXIS FIFO 64 KB
#   0x8000_0000 DDR4 C1 (2 GB window)
# Planner M_AXI space: DDR4 C1 at 0x0000_0000 (planning_pkg DDR4_* offsets are absolute from 0).
# MDM debug memory access (xsdb mwr/mrd/dow -data) uses the same map as MicroBlaze.
set HERE [file normalize [file dirname [info script]]]
set HW   [file normalize [file join $HERE ..]]
set ROOT [file normalize [file join $HW .. ..]]
set DDRIF ddr4_sdram_c1_083
if {[info exists ::env(VCU118_DDR)]} { set DDRIF ddr4_sdram_c1_$::env(VCU118_DDR) }
set STOP ""
if {[info exists ::env(VCU118_STOP)]} { set STOP $::env(VCU118_STOP) }
# 12/11: separate dirs per DDR variant (083 = default dirs, kept; 062 -> prj_joint_062/out_joint_062)
set SFX [expr {$DDRIF eq "ddr4_sdram_c1_083" ? "" : "_[string range $DDRIF end-2 end]"}]
set PRJ [file join $HERE prj_joint$SFX]
set OUT [file join $HERE out_joint$SFX]
file mkdir $OUT
set_param general.maxThreads 4
create_project vcu118_joint $PRJ -part xcvu9p-flga2104-2L-e -force
set_property board_part xilinx.com:vcu118:part0:2.4 [current_project]
set_property target_language Verilog [current_project]

# ---------------- sources ----------------
# Planner (same files as the v2d ZCU106 project, without the old HMAO monitor and its GPIO bridge).
set PL_FILES {
  rtl/include/planning_pkg.sv rtl/src/bert_v2/bert_v2.sv rtl/src/dma/bert_weight_loader.sv rtl/src/bert_v2/bv2_mem.sv
  rtl/src/memory/dual_port_ram.sv rtl/src/gru/fp32_sigmoid_lut.sv rtl/src/bert_v2/fp32_tables.svh rtl/src/bert_v2/fp32_special.sv
  rtl/src/gru/fp32_tanh_lut.sv rtl/src/bert_v2/fp32_units.sv rtl/src/gru/gru_scale_lutram.sv rtl/src/gru/gru_waypoint_decoder.sv
  rtl/src/cdc/hmao_cdc_bridge.sv rtl/src/cdc/hsync_chain.sv rtl/src/input/input_adapter.sv rtl/src/bert_v2/ln_engine.sv
  rtl/src/bert_v2/mac_array_tp.sv rtl/src/bert_v2/mm_engine.sv rtl/src/top/planning_top.sv rtl/src/bert_v2/projector_v2.sv
  rtl/src/bert_v2/softmax_u8.sv rtl/src/input/token_fifo.sv rtl/src/output/trajectory_sanity_checker.sv
  rtl/src/memory/uram_arbiter.sv rtl/src/dma/weight_loader.sv rtl/src/parsers/world_model_parser.sv
  rtl/src/top/planning_top_bd_ref.v rtl/src/top/planning_top_bd_wrapper.sv rtl/src/cdc/cdc_pulse_sync.sv rtl/src/output/nan_inf_detector.sv
  rtl/src/control/axil_regfile.sv rtl/src/control/pp_mux.sv rtl/src/control/axi_width_converter.sv
}
foreach f $PL_FILES { add_files -norecurse -fileset sources_1 [file join $ROOT $f] }
foreach f {sigmoid_lut_init.hex tanh_lut_init.hex} {
  if {[file exists [file join $ROOT $f]]} { add_files -norecurse -fileset sources_1 [file join $ROOT $f] }
}
set_property include_dirs [list [file join $ROOT rtl include] [file join $ROOT rtl src bert_v2]] [current_fileset]
# TSM-X core (frozen) + VCU118 board glue (shim_v2 = 1 us time base).
foreach x [split [string trim [read [set fh [open [file join $HW rtl filelist_top.f]]]]] "\n"] {
  set x [string trim $x]
  if {$x eq "" || [string match "//*" $x]} continue
  add_files -norecurse -fileset sources_1 [file join $HW rtl $x]
}
close $fh
add_files -norecurse -fileset sources_1 [list [file join $HW board rtl tsmx_board_shim_v2.v] [file join $HW board rtl tsmx_board_top_v2.v]]
update_compile_order -fileset sources_1

# ---------------- block design ----------------
create_bd_design system
# DDR4 C1 + its board system clock and reset
create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0
apply_board_connection -board_interface $DDRIF -ip_intf ddr4_0/C0_DDR4 -diagram system
apply_bd_automation -rule xilinx.com:bd_rule:board -config {Board_Interface "default_250mhz_clk1"} [get_bd_intf_pins ddr4_0/C0_SYS_CLK]
apply_bd_automation -rule xilinx.com:bd_rule:board -config {Board_Interface "reset"} [get_bd_pins ddr4_0/sys_rst]
# 100/150/300 MHz from the MIG user clock
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list CONFIG.PRIM_SOURCE Global_buffer CONFIG.PRIM_IN_FREQ 300.000 \
  CONFIG.CLKOUT2_USED true CONFIG.CLKOUT3_USED true CONFIG.NUM_OUT_CLKS 3 \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 150.000 \
  CONFIG.CLKOUT3_REQUESTED_OUT_FREQ 300.000 CONFIG.USE_RESET true CONFIG.RESET_TYPE ACTIVE_HIGH] [get_bd_cells clk_wiz_0]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins clk_wiz_0/reset]
foreach r {rst_100 rst_150 rst_300 rst_ddr} { create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $r }
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_100/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins rst_150/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins rst_300/slowest_sync_clk]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins rst_ddr/slowest_sync_clk]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 ddr_rst_n
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION not] [get_bd_cells ddr_rst_n]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins ddr_rst_n/Op1]
foreach r {rst_100 rst_150 rst_300 rst_ddr} {
  connect_bd_net [get_bd_pins ddr_rst_n/Res] [get_bd_pins $r/ext_reset_in]
  connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins $r/dcm_locked]
}
connect_bd_net [get_bd_pins rst_ddr/peripheral_aresetn] [get_bd_pins ddr4_0/c0_ddr4_aresetn]

# MicroBlaze (no caches, 128 KB LMB, MDM with debug memory access) at 100 MHz
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0
apply_bd_automation -rule xilinx.com:bd_rule:microblaze -config { axi_intc {0} axi_periph {Enabled} cache {None} \
  clk {/clk_wiz_0/clk_out1 (100 MHz)} cores {1} debug_module {Debug Only} ecc {None} local_mem {128KB} preset {None}} \
  [get_bd_cells microblaze_0]
set_property -dict [list CONFIG.C_USE_BARREL 1 CONFIG.C_USE_HW_MUL 1 CONFIG.C_USE_DIV 1 CONFIG.C_USE_FPU 0] [get_bd_cells microblaze_0]
set MDM [lindex [get_bd_cells -filter {VLNV =~ "*:mdm:*"}] 0]
set_property CONFIG.C_DBG_MEM_ACCESS 1 [get_bd_cells $MDM]

# Peripherals
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 uart_0
apply_board_connection -board_interface rs232_uart -ip_intf uart_0/UART -diagram system
set_property CONFIG.C_BAUDRATE 115200 [get_bd_cells uart_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 iic_0
apply_board_connection -board_interface iic_main -ip_intf iic_0/IIC -diagram system
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer:2.0 timer_0
# Planner release: the planner loads its weights once after reset, so it must stay in reset until xsdb has
# filled DDR. gpio_0 bit0 (default 0) drives aux_reset_in (active low) of rst_150 and rst_300.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 gpio_0
set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000] [get_bd_cells gpio_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.3 axis_fifo
set_property -dict [list CONFIG.C_DATA_INTERFACE_TYPE 0 CONFIG.C_USE_TX_CTRL 0 CONFIG.C_HAS_AXIS_TKEEP true \
  CONFIG.C_TX_FIFO_DEPTH 2048 CONFIG.C_TX_FIFO_PF_THRESHOLD 2000 CONFIG.C_TX_FIFO_PE_THRESHOLD 5 \
  CONFIG.C_RX_FIFO_DEPTH 512 CONFIG.C_RX_FIFO_PF_THRESHOLD 500 CONFIG.C_RX_FIFO_PE_THRESHOLD 5] [get_bd_cells axis_fifo]
create_bd_cell -type module -reference tsmx_board_top_v2 tsmx_0
create_bd_cell -type module -reference planning_top_bd_ref plan_0

# Interconnect: MicroBlaze DP + MDM M_AXI -> sc_mb -> {7 slaves, DDR}; planner M_AXI + sc_mb DDR port -> sc_ddr -> MIG
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 sc_mb
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 9 CONFIG.NUM_CLKS 2] [get_bd_cells sc_mb]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 sc_ddr
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 1 CONFIG.NUM_CLKS 3] [get_bd_cells sc_ddr]
# remove the automation's periph interconnect if one was created, then wire DP to sc_mb
set ic [get_bd_cells -quiet microblaze_0_axi_periph]
if {$ic ne ""} { delete_bd_objs $ic }
connect_bd_intf_net [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins sc_mb/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $MDM/M_AXI] [get_bd_intf_pins sc_mb/S01_AXI]
set i 0
foreach p {uart_0/S_AXI iic_0/S_AXI timer_0/S_AXI plan_0/S_AXIL tsmx_0/s_axi_shim tsmx_0/s_axi_csr axis_fifo/S_AXI} {
  connect_bd_intf_net [get_bd_intf_pins sc_mb/M0${i}_AXI] [get_bd_intf_pins $p]; incr i
}
connect_bd_intf_net [get_bd_intf_pins sc_mb/M07_AXI] [get_bd_intf_pins sc_ddr/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_mb/M08_AXI] [get_bd_intf_pins gpio_0/S_AXI]
connect_bd_net [get_bd_pins gpio_0/gpio_io_o] [get_bd_pins rst_150/aux_reset_in] [get_bd_pins rst_300/aux_reset_in]
connect_bd_intf_net [get_bd_intf_pins plan_0/M_AXI] [get_bd_intf_pins sc_ddr/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ddr/M00_AXI] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
connect_bd_intf_net [get_bd_intf_pins axis_fifo/AXI_STR_TXD] [get_bd_intf_pins tsmx_0/s_axis_rx]
connect_bd_intf_net [get_bd_intf_pins tsmx_0/m_axis_tx] [get_bd_intf_pins axis_fifo/AXI_STR_RXD]

# Clocks / resets
set C100 [get_bd_pins clk_wiz_0/clk_out1]
foreach p {sc_mb/aclk gpio_0/s_axi_aclk uart_0/s_axi_aclk iic_0/s_axi_aclk timer_0/s_axi_aclk axis_fifo/s_axi_aclk tsmx_0/clk sc_ddr/aclk} {
  catch {connect_bd_net $C100 [get_bd_pins $p]}
}
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins plan_0/clk] [get_bd_pins sc_mb/aclk1] [get_bd_pins sc_ddr/aclk1]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins plan_0/hmao_clk]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins sc_ddr/aclk2]
connect_bd_net [get_bd_pins rst_100/interconnect_aresetn] [get_bd_pins sc_mb/aresetn] [get_bd_pins sc_ddr/aresetn]
foreach p {gpio_0/s_axi_aresetn uart_0/s_axi_aresetn iic_0/s_axi_aresetn timer_0/s_axi_aresetn axis_fifo/s_axi_aresetn tsmx_0/resetn} {
  catch {connect_bd_net [get_bd_pins rst_100/peripheral_aresetn] [get_bd_pins $p]}
}
catch {connect_bd_net $C100 [get_bd_pins $MDM/M_AXI_ACLK]}
catch {connect_bd_net [get_bd_pins rst_100/peripheral_aresetn] [get_bd_pins $MDM/M_AXI_ARESETN]}
# DDR4 C1 preset: AXI address width 31 (2 GB). MicroBlaze/MDM see it at 0x8000_0000, the planner at 0x0;
# bit 31 is not decoded by the MIG, so both views reach the same physical bytes (BD 41-1354 overlap warning
# between the planner DDR segment and the MicroBlaze LMB is expected: different address spaces).
connect_bd_net [get_bd_pins rst_150/peripheral_aresetn] [get_bd_pins plan_0/rst_n]
connect_bd_net [get_bd_pins rst_300/peripheral_aresetn] [get_bd_pins plan_0/hmao_rst_n]
# brake / heartbeat -> LEDs would need the led_8bits board interface; exported as ports for the XDC instead
make_bd_pins_external [get_bd_pins tsmx_0/brake] [get_bd_pins tsmx_0/heartbeat]

# Addresses
set AS_MB  [get_bd_addr_spaces microblaze_0/Data]
set AS_DBG [get_bd_addr_spaces $MDM/Data]
set AS_PL  [get_bd_addr_spaces plan_0/M_AXI]
foreach AS [list $AS_MB $AS_DBG] {
  foreach {seg off rng} {
    /gpio_0/S_AXI/Reg 0x40000000 64K /uart_0/S_AXI/Reg 0x40600000 64K /iic_0/S_AXI/Reg 0x40800000 64K /timer_0/S_AXI/Reg 0x41C00000 64K
    /plan_0/S_AXIL/reg0 0x44A00000 4K /tsmx_0/s_axi_shim/reg0 0x44A10000 4K /tsmx_0/s_axi_csr/reg0 0x44A20000 64K
    /axis_fifo/S_AXI/Mem0 0x44A30000 64K /ddr4_0/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK 0x80000000 2G} {
    assign_bd_address -offset $off -range $rng -target_address_space $AS [get_bd_addr_segs $seg] -force
  }
}
assign_bd_address -offset 0x00000000 -range 2G -target_address_space $AS_PL \
  [get_bd_addr_segs /ddr4_0/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK] -force
foreach s [get_bd_addr_segs -of [get_bd_addr_spaces]] { puts "###ADDR [get_property NAME $s] [get_property OFFSET $s] [get_property RANGE $s]" }
foreach p {clk_out1 clk_out2 clk_out3} { puts "###FREQ $p=[get_property CONFIG.FREQ_HZ [get_bd_pins clk_wiz_0/$p]]" }
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
add_files -norecurse [file join $PRJ vcu118_joint.gen sources_1 bd system hdl system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1
add_files -fileset constrs_1 -norecurse [file join $HERE vcu118_joint.xdc]
puts "###BD_OK"
if {$STOP eq "bd"} { exit 0 }

# ---------------- implementation (requires the XCVU9P licence) ----------------
# 10/11: OOC IP runs one at a time - TSM-X synthesis alone peaks ~16 GB (4 parallel runs ran out of memory)
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "###ERROR synth"; exit 1 }
# 11/11: SLR floorplan + directives that closed timing (impl_only_fp.tcl: WNS +0.006, WHS +0.010 ns)
set_property STEPS.PLACE_DESIGN.TCL.PRE [file join $HERE vcu118_floorplan.tcl] [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary -file [file join $OUT timing_summary.rpt]
report_utilization -file [file join $OUT utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $OUT utilization_hier.rpt]
report_power -file [file join $OUT power_estimate.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "###RESULT WNS=$wns WHS=$whs"
set bit [file join $PRJ vcu118_joint.runs impl_1 system_wrapper.bit]
if {[file exists $bit] && $wns >= 0 && $whs >= 0} {
  file copy -force $bit [file join $OUT system_wrapper_joint.bit]
  write_hw_platform -fixed -include_bit -force -file [file join $OUT system_wrapper_joint.xsa]
  puts "###BIT [file join $OUT system_wrapper_joint.bit]"
} else { puts "###ERROR no bitstream or timing not met"; exit 1 }
exit 0
