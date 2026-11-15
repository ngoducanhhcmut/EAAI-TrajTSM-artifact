# Claude 04/11/2026: ZCU106 bitstream for TSM-X alone (P=G=2, PARA_DIRECT=0) at 100 MHz.
#   PS (ZCU106 preset not needed: psu_init_zcu106_ram_x16_8gb.tcl is loaded over JTAG) + HPM0 32 b
#   -> SmartConnect -> { tsmx_board_top/s_axi_shim 0xA000_0000, tsmx_board_top/s_axi_csr 0xA001_0000,
#                        axi_fifo_mm_s (AXI-Lite) 0xA002_0000 }
#   FIFO AXIS TX -> s_axis_rx (requests), m_axis_tx -> FIFO AXIS RX (commands).
#   vivado -mode batch -source journalQ1/tsmx_hw/board/build_tsmx_zcu106.tcl
set HW   [file normalize [file join [file dirname [info script]] ..]]
# Clock: env TSMX_MHZ (default 100). Non-default builds go to prj_<MHz>/out_<MHz>.
set MHZ 100
if {[info exists ::env(TSMX_MHZ)]} { set MHZ $::env(TSMX_MHZ) }
set SFX [expr {$MHZ == 100 ? "" : "_$MHZ"}]
set PRJ  [file join $HW board prj$SFX]
set OUT  [file join $HW board out$SFX]
file mkdir $OUT
set_param general.maxThreads 4
create_project tsmx_zcu106 $PRJ -part xczu7ev-ffvc1156-2-e -force
set_property target_language Verilog [current_project]

foreach x [split [string trim [read [open [file join $HW rtl filelist_top.f]]]] "\n"] {
  set x [string trim $x]
  if {$x eq "" || [string match "//*" $x]} continue
  add_files -norecurse -fileset sources_1 [file join $HW rtl $x]
}
add_files -norecurse -fileset sources_1 [list [file join $HW board rtl tsmx_board_shim.v] [file join $HW board rtl tsmx_board_top.v]]
update_compile_order -fileset sources_1

create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
set PS zynq_ultra_ps_e_0
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 1 CONFIG.PSU__MAXIGP0__DATA_WIDTH 32 \
  CONFIG.PSU__USE__M_AXI_GP1 0 CONFIG.PSU__USE__M_AXI_GP2 0 CONFIG.PSU__FPGA_PL0_ENABLE 1 \
  CONFIG.PSU__FPGA_PL1_ENABLE 0 CONFIG.PSU__FPGA_PL2_ENABLE 0 CONFIG.PSU__FPGA_PL3_ENABLE 0 \
  CONFIG.PSU__USE__IRQ0 0 CONFIG.PSU__NUM_FABRIC_RESETS 1] [get_bd_cells $PS]
set_property CONFIG.PSU__PSS_REF_CLK__FREQMHZ 33.333333 [get_bd_cells $PS]
set_property -dict [list CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL IOPLL CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $MHZ] [get_bd_cells $PS]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pl0
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 sc_axil
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 3] [get_bd_cells sc_axil]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.3 axis_fifo
set_property -dict [list CONFIG.C_DATA_INTERFACE_TYPE 0 CONFIG.C_USE_TX_CTRL 0 CONFIG.C_HAS_AXIS_TKEEP true \
  CONFIG.C_TX_FIFO_DEPTH 2048 CONFIG.C_TX_FIFO_PF_THRESHOLD 2000 CONFIG.C_TX_FIFO_PE_THRESHOLD 5 \
  CONFIG.C_RX_FIFO_DEPTH 512 CONFIG.C_RX_FIFO_PF_THRESHOLD 500 CONFIG.C_RX_FIFO_PE_THRESHOLD 5] [get_bd_cells axis_fifo]
create_bd_cell -type module -reference tsmx_board_top tsmx_0

connect_bd_net [get_bd_pins $PS/pl_clk0] [get_bd_pins $PS/maxihpm0_fpd_aclk] [get_bd_pins rst_pl0/slowest_sync_clk] \
  [get_bd_pins sc_axil/aclk] [get_bd_pins axis_fifo/s_axi_aclk] [get_bd_pins tsmx_0/clk]
connect_bd_net [get_bd_pins $PS/pl_resetn0] [get_bd_pins rst_pl0/ext_reset_in]
connect_bd_net [get_bd_pins rst_pl0/interconnect_aresetn] [get_bd_pins sc_axil/aresetn]
connect_bd_net [get_bd_pins rst_pl0/peripheral_aresetn] [get_bd_pins axis_fifo/s_axi_aresetn] [get_bd_pins tsmx_0/resetn]

connect_bd_intf_net [get_bd_intf_pins $PS/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_axil/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_axil/M00_AXI] [get_bd_intf_pins tsmx_0/s_axi_shim]
connect_bd_intf_net [get_bd_intf_pins sc_axil/M01_AXI] [get_bd_intf_pins tsmx_0/s_axi_csr]
connect_bd_intf_net [get_bd_intf_pins sc_axil/M02_AXI] [get_bd_intf_pins axis_fifo/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axis_fifo/AXI_STR_TXD] [get_bd_intf_pins tsmx_0/s_axis_rx]
connect_bd_intf_net [get_bd_intf_pins tsmx_0/m_axis_tx] [get_bd_intf_pins axis_fifo/AXI_STR_RXD]

# Explicit placement of each slave (HPM0_FPD aperture 0xA000_0000-0xAFFF_FFFF).
set AS [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]
foreach {seg off rng} {/axis_fifo/S_AXI/Mem0 0xA0020000 64K /tsmx_0/s_axi_csr/reg0 0xA0010000 64K /tsmx_0/s_axi_shim/reg0 0xA0000000 4K} {
  assign_bd_address -offset $off -range $rng -target_address_space $AS [get_bd_addr_segs $seg] -force
}
foreach s [get_bd_addr_segs -of [get_bd_addr_spaces]] { puts "###ADDR [get_property NAME $s] [get_property OFFSET $s] [get_property RANGE $s]" }
set f0 [get_property CONFIG.FREQ_HZ [get_bd_pins $PS/pl_clk0]]
puts "###FREQ pl_clk0=$f0"
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
add_files -norecurse [file join $PRJ tsmx_zcu106.gen sources_1 bd system hdl system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

# Congestion-driven flow: the core alone is ~85 % of the ZU7EV LUTs.
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "###ERROR synth"; exit 1 }
open_run synth_1
report_utilization -file [file join $OUT utilization_synth.rpt]
close_design

set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE AltSpreadLogic_high [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary -file [file join $OUT timing_summary.rpt]
report_utilization -file [file join $OUT utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $OUT utilization_hier.rpt]
report_route_status -file [file join $OUT route_status.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "###RESULT WNS=$wns WHS=$whs"
set bit [file join $PRJ tsmx_zcu106.runs impl_1 system_wrapper.bit]
if {[file exists $bit] && $wns >= 0 && $whs >= 0} {
  file copy -force $bit [file join $OUT system_wrapper_tsmx.bit]
  write_hw_platform -fixed -include_bit -force -file [file join $OUT system_wrapper_tsmx.xsa]
  puts "###BIT [file join $OUT system_wrapper_tsmx.bit]"
} else { puts "###ERROR no bitstream or timing not met"; exit 1 }
exit 0
