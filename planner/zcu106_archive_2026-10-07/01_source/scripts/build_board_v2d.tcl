# =============================================================================
# build_board_v2d.tcl — ban build board v2d: TSM v2.1 + doc ket qua TSM tu PS.
#
#   vivado -mode batch -notrace -source scripts/build_board_v2d.tcl
#
# Thay doi so voi v2c (deliverables/v2):
#   1. RTL TSM v2.1: SAT hop-hop 4 truc, vat can di chuyen, danh sach nghi ngo (VH AK.15)
#      + sua tran lam tron cos/sin trong hmao_zonotope_gen (VH AK.16).
#   2. Bo dem TSM doi vao DDR_LOW: TRAJ 0x7030_0000, WORLD MODEL 0x7040_0000 (hmao_pkg.sv).
#   3. Them tsm_status_pack + axi_gpio_1 (chi vao, 0xA002_0000): PS doc GRANT/VETO, bit loi,
#      buoc/vat can vi pham. Truoc day chi co ngat hmao_complete toi PS.
# Ra: deliverables/v2d/system_wrapper_v2d.{bit,xsa} + reports/impl_v2d/*.
# =============================================================================
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set RPT  [file join $ROOT reports impl_v2d]
set DLV  [file join $ROOT deliverables v2d]
file mkdir $RPT $DLV
open_project [file join $ROOT hw_project planning_hw.xpr]

# ---------------------------------------------------------------- 1. BD
set pack_v [file join $ROOT HMAO tsm_status_pack.v]
if {[llength [get_files -quiet $pack_v]] == 0} { add_files -norecurse -fileset sources_1 $pack_v }
update_compile_order -fileset sources_1
open_bd_design [get_files system.bd]

if {[llength [get_bd_cells -quiet axi_gpio_1]] == 0} {
  create_bd_cell -type module -reference tsm_status_pack tsm_status_pack_0
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1
  set_property -dict [list CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_INPUTS {1} CONFIG.C_ALL_INPUTS_2 {1} \
                           CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32}] [get_bd_cells axi_gpio_1]
  set_property CONFIG.NUM_MI {3} [get_bd_cells smartconnect_axil]
  connect_bd_intf_net [get_bd_intf_pins smartconnect_axil/M02_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]
  connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]          [get_bd_pins axi_gpio_1/s_axi_aclk]
  connect_bd_net [get_bd_pins rst_pl_185m/peripheral_aresetn]      [get_bd_pins axi_gpio_1/s_axi_aresetn]
  connect_bd_net [get_bd_pins hmao_engine_0/hmao_decision_out]     [get_bd_pins tsm_status_pack_0/hmao_decision]
  connect_bd_net [get_bd_pins hmao_engine_0/hmao_complete]         [get_bd_pins tsm_status_pack_0/hmao_complete]
  connect_bd_net [get_bd_pins hmao_engine_0/hmao_violation_out]    [get_bd_pins tsm_status_pack_0/hmao_violation]
  connect_bd_net [get_bd_pins hmao_engine_0/fault_bits_out]        [get_bd_pins tsm_status_pack_0/fault_bits]
  connect_bd_net [get_bd_pins hmao_engine_0/fault_valid_out]       [get_bd_pins tsm_status_pack_0/fault_valid]
  connect_bd_net [get_bd_pins tsm_status_pack_0/gpio_status]       [get_bd_pins axi_gpio_1/gpio_io_i]
  connect_bd_net [get_bd_pins tsm_status_pack_0/gpio_detail]       [get_bd_pins axi_gpio_1/gpio2_io_i]
  assign_bd_address -target_address_space /zynq_ultra_ps_e_0/Data [get_bd_addr_segs axi_gpio_1/S_AXI/Reg] \
                    -offset 0xA0020000 -range 64K
}
foreach ip [get_ips -quiet -filter {NAME =~ "*hmao_engine*"}] { catch { update_module_reference $ip } }
validate_bd_design
save_bd_design
puts "=== BD v2d: [join [get_bd_cells] { }]"
foreach s [get_bd_addr_segs -of_objects [get_bd_addr_spaces /zynq_ultra_ps_e_0/Data]] {
  puts "    [get_property OFFSET $s] [get_property RANGE $s] $s"
}
make_wrapper -files [get_files system.bd] -top -force
generate_target all [get_files system.bd]

# ---------------------------------------------------------------- 2. synth + impl + bitstream
# BAY IP CACHE (VH AK.18): khoa cache cua module reference KHONG bam noi dung RTL -> lan build v2d dau
# lay netlist TSM v1 ngay 04/10 tu cache. Bat buoc xoa entry cu hon RTL truoc va kiem lai sau tong hop.
source [file join $ROOT scripts ipcache_guard.tcl]
if {[ipcache_check_coverage $ROOT]} { puts "ERROR: bang guard IP cache khong du"; exit 1 }
ipcache_purge_if_stale $ROOT
# 07/10: reset CA BON lan tong hop module-reference. Vivado khong biet RTL cua module-reference da doi,
# neu chi reset hmao thi Traj (planning_top) dung lai netlist cu trong thu muc run (da xay ra 07/10 02:15).
foreach r {impl_1 synth_1 system_hmao_engine_0_2_synth_1 system_planning_top_0_0_synth_1
           system_hmao_gpio_cdc_bridge_0_0_synth_1 system_tsm_status_pack_0_0_synth_1} {
  if {[llength [get_runs -quiet $r]]} { reset_run $r }
}
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: synth that bai"; exit 1 }
puts "=== synth xong [clock format [clock seconds] -format %H:%M]"
if {[ipcache_assert_fresh $ROOT]} { puts "ERROR: netlist IP cu hon RTL"; exit 1 }
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
puts "=== impl xong [clock format [clock seconds] -format %H:%M] progress [get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "ERROR: implementation/bitstream did not complete"; exit 1
}

open_run impl_1
report_route_status    -file [file join $RPT route_status.rpt]
report_timing_summary  -file [file join $RPT timing_summary.rpt] -max_paths 20
report_utilization     -file [file join $RPT utilization.rpt] -hierarchical -hierarchical_depth 3
report_power           -file [file join $RPT power.rpt]
report_drc             -file [file join $RPT drc.rpt]
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
set bad [llength [get_nets -quiet -hier -filter {ROUTE_STATUS == UNROUTED || ROUTE_STATUS == PARTIAL || ROUTE_STATUS == CONFLICTS}]]
foreach clk {clk_pl_0 clk_pl_2 clk_pl_3} {
  set p [get_timing_paths -quiet -delay_type max -group $clk]
  if {[llength $p]} { puts "###CLK $clk WNS=[get_property SLACK $p]" }
}
puts "###RESULT### WNS=$wns WHS=$whs net_loi=$bad"

set bit [file join $ROOT hw_project planning_hw.runs impl_1 system_wrapper.bit]
if {[file exists $bit] && $wns >= 0 && $whs >= 0 && $bad == 0} {
  file copy -force $bit [file join $DLV system_wrapper_v2d.bit]
  write_hw_platform -fixed -include_bit -force -file [file join $DLV system_wrapper_v2d.xsa]
  # Keep the platform copy identical, so Vitis cannot silently program an old PL.
  set platform_hw [file join $ROOT vitis_ws_v2d v2d_plat hw]
  if {[file isdirectory $platform_hw]} {
    file copy -force $bit [file join $platform_hw system_wrapper_v2d.bit]
    file copy -force [file join $DLV system_wrapper_v2d.xsa] [file join $platform_hw system_wrapper_v2d.xsa]
  }
  puts "###DELIVERED $DLV"
} else {
  puts "###NOT_DELIVERED (timing/route chua dat hoac thieu bitstream)"
  exit 1
}
exit 0
