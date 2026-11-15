# =============================================================================
# hw_tsm_only/build_tsm_only.tcl — bitstream CHI CO TSM (khong co VLA-Traj) de thu TSM tren board.
#   PS: mac dinh + HPM0 32b, HP1 128b, PL0 150 / PL2 187,5 / PL3 250 MHz (chi de rang buoc timing PL).
#   PL: hmao_engine_0 + hmao_gpio_cdc_bridge_0 + tsm_status_pack_0 + axi_gpio_0/1 + 2 SmartConnect,
#       dia chi giu nguyen: GPIO0 0xA001_0000, GPIO1 0xA002_0000, TSM doc DDR qua HP1.
#   RTL TSM hien hanh (da sua doc AXI + watchdog). Project moi -> khong dung IP cache cu.
#   vivado -mode batch -source hw_tsm_only/build_tsm_only.tcl
# =============================================================================
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PRJ  [file join $ROOT hw_tsm_only prj]
set OUT  [file join $ROOT deliverables tsm_only]
file mkdir $OUT
create_project tsm_only $PRJ -part xczu7ev-ffvc1156-2-e -force
set_property target_language Verilog [current_project]

set srcs [list \
  rtl/include/planning_pkg.sv HMAO/hmao_pkg.sv HMAO/hmao_interfaces.sv HMAO/hmao_axi_if.sv \
  rtl/src/cdc/hsync_chain.sv rtl/src/cdc/cdc_pulse_sync.sv rtl/src/cdc/hmao_cdc_bridge.sv \
  rtl/src/cdc/hmao_gpio_cdc_bridge.sv rtl/src/cdc/hmao_gpio_cdc_bridge_bd_ref.v \
  HMAO/hmao_fsm.sv HMAO/hmao_preproc.sv HMAO/hmao_adaptive_margin.sv HMAO/hmao_zonotope_gen.sv \
  HMAO/hmao_admm_solver.sv HMAO/hmao_collision_sat.sv HMAO/hmao_axi_arbiter.sv \
  HMAO/hmao_safety_modules.sv HMAO/hmao_engine_top.sv HMAO/hmao_engine_top_bd_wrapper.sv \
  HMAO/hmao_engine_top_bd_ref.v HMAO/tsm_status_pack.v]
foreach f $srcs { add_files -norecurse -fileset sources_1 [file join $ROOT $f] }
add_files -norecurse -fileset constrs_1 [list [file join $ROOT constrain hmao_bd_timing.xdc] \
  [file join $ROOT hw_tsm_only tsm_only_cdc.xdc]]
update_compile_order -fileset sources_1

create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
# PS mac dinh + chi cac thiet lap phia PL can (cau hinh PS that do psu_init_zcu106.tcl nap qua JTAG).
set_property -dict [list   CONFIG.PSU__USE__M_AXI_GP0 1 CONFIG.PSU__MAXIGP0__DATA_WIDTH 32   CONFIG.PSU__USE__M_AXI_GP1 0 CONFIG.PSU__USE__M_AXI_GP2 0   CONFIG.PSU__USE__S_AXI_GP3 1 CONFIG.PSU__SAXIGP3__DATA_WIDTH 128   CONFIG.PSU__FPGA_PL0_ENABLE 1 CONFIG.PSU__FPGA_PL1_ENABLE 0   CONFIG.PSU__FPGA_PL2_ENABLE 1 CONFIG.PSU__FPGA_PL3_ENABLE 1   CONFIG.PSU__USE__IRQ0 0 CONFIG.PSU__NUM_FABRIC_RESETS 1] [get_bd_cells zynq_ultra_ps_e_0]
set_property CONFIG.PSU__PSS_REF_CLK__FREQMHZ 33.333333 [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL IOPLL CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 150 CONFIG.PSU__CRL_APB__PL2_REF_CTRL__SRCSEL RPLL CONFIG.PSU__CRL_APB__PL2_REF_CTRL__FREQMHZ 187.5 CONFIG.PSU__CRL_APB__PL3_REF_CTRL__SRCSEL RPLL CONFIG.PSU__CRL_APB__PL3_REF_CTRL__FREQMHZ 250] [get_bd_cells zynq_ultra_ps_e_0]
foreach k {PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ PSU__CRL_APB__PL2_REF_CTRL__ACT_FREQMHZ PSU__CRL_APB__PL3_REF_CTRL__ACT_FREQMHZ} {
  puts "###PS $k = [get_property CONFIG.$k [get_bd_cells zynq_ultra_ps_e_0]]"
}
foreach k {PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ PSU__CRL_APB__PL2_REF_CTRL__FREQMHZ PSU__CRL_APB__PL3_REF_CTRL__FREQMHZ PSU__USE__S_AXI_GP3 PSU__SAXIGP3__DATA_WIDTH PSU__USE__M_AXI_GP0} {
  puts "###PS $k = [get_property CONFIG.$k [get_bd_cells zynq_ultra_ps_e_0]]"
}

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pl_185m
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pl_300m
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_axil
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] [get_bd_cells smartconnect_axil]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_hmao
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells smartconnect_hmao]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
set_property -dict [list CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_ALL_OUTPUTS_2 1 CONFIG.C_GPIO_WIDTH 1 \
  CONFIG.C_GPIO2_WIDTH 1 CONFIG.C_IS_DUAL 1] [get_bd_cells axi_gpio_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1
set_property -dict [list CONFIG.C_ALL_INPUTS 1 CONFIG.C_ALL_INPUTS_2 1 CONFIG.C_GPIO_WIDTH 32 \
  CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_IS_DUAL 1] [get_bd_cells axi_gpio_1]
create_bd_cell -type module -reference hmao_engine_top_bd_ref hmao_engine_0
create_bd_cell -type module -reference hmao_gpio_cdc_bridge_bd_ref hmao_gpio_cdc_bridge_0
create_bd_cell -type module -reference tsm_status_pack tsm_status_pack_0

set PS zynq_ultra_ps_e_0
# clock
connect_bd_net [get_bd_pins $PS/pl_clk0] [get_bd_pins $PS/maxihpm0_fpd_aclk] [get_bd_pins rst_pl_185m/slowest_sync_clk] \
  [get_bd_pins smartconnect_axil/aclk] [get_bd_pins axi_gpio_0/s_axi_aclk] [get_bd_pins axi_gpio_1/s_axi_aclk] \
  [get_bd_pins hmao_gpio_cdc_bridge_0/src_clk]
connect_bd_net [get_bd_pins $PS/pl_clk2] [get_bd_pins $PS/saxihp1_fpd_aclk] [get_bd_pins rst_pl_300m/slowest_sync_clk] \
  [get_bd_pins smartconnect_hmao/aclk] [get_bd_pins hmao_engine_0/clk] [get_bd_pins hmao_gpio_cdc_bridge_0/dst_clk]
connect_bd_net [get_bd_pins $PS/pl_clk3] [get_bd_pins hmao_engine_0/wdt_clk]
# reset
connect_bd_net [get_bd_pins $PS/pl_resetn0] [get_bd_pins rst_pl_185m/ext_reset_in] [get_bd_pins rst_pl_300m/ext_reset_in]
connect_bd_net [get_bd_pins rst_pl_185m/interconnect_aresetn] [get_bd_pins smartconnect_axil/aresetn]
connect_bd_net [get_bd_pins rst_pl_185m/peripheral_aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn] \
  [get_bd_pins axi_gpio_1/s_axi_aresetn] [get_bd_pins hmao_gpio_cdc_bridge_0/src_rst_n]
connect_bd_net [get_bd_pins rst_pl_300m/interconnect_aresetn] [get_bd_pins smartconnect_hmao/aresetn]
connect_bd_net [get_bd_pins rst_pl_300m/peripheral_aresetn] [get_bd_pins hmao_engine_0/rst_n] \
  [get_bd_pins hmao_gpio_cdc_bridge_0/dst_rst_n]
# AXI
connect_bd_intf_net [get_bd_intf_pins $PS/M_AXI_HPM0_FPD] [get_bd_intf_pins smartconnect_axil/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_axil/M00_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_axil/M01_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]
connect_bd_intf_net [get_bd_intf_pins hmao_engine_0/M_AXI] [get_bd_intf_pins smartconnect_hmao/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_hmao/M00_AXI] [get_bd_intf_pins $PS/S_AXI_HP1_FPD]
# GPIO <-> CDC <-> TSM <-> pack
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o]  [get_bd_pins hmao_gpio_cdc_bridge_0/gpio_start_level]
connect_bd_net [get_bd_pins axi_gpio_0/gpio2_io_o] [get_bd_pins hmao_gpio_cdc_bridge_0/gpio_irqclr_level]
connect_bd_net [get_bd_pins hmao_gpio_cdc_bridge_0/hmao_start_pulse] [get_bd_pins hmao_engine_0/hmao_start]
connect_bd_net [get_bd_pins hmao_gpio_cdc_bridge_0/irq_clear_pulse]  [get_bd_pins hmao_engine_0/irq_clear]
connect_bd_net [get_bd_pins hmao_engine_0/hmao_decision_out]  [get_bd_pins tsm_status_pack_0/hmao_decision]
connect_bd_net [get_bd_pins hmao_engine_0/hmao_complete]      [get_bd_pins tsm_status_pack_0/hmao_complete]
connect_bd_net [get_bd_pins hmao_engine_0/hmao_violation_out] [get_bd_pins tsm_status_pack_0/hmao_violation]
connect_bd_net [get_bd_pins hmao_engine_0/fault_bits_out]     [get_bd_pins tsm_status_pack_0/fault_bits]
connect_bd_net [get_bd_pins hmao_engine_0/fault_valid_out]    [get_bd_pins tsm_status_pack_0/fault_valid]
connect_bd_net [get_bd_pins tsm_status_pack_0/gpio_status] [get_bd_pins axi_gpio_1/gpio_io_i]
connect_bd_net [get_bd_pins tsm_status_pack_0/gpio_detail] [get_bd_pins axi_gpio_1/gpio2_io_i]

assign_bd_address
# dat GPIO1 truoc (assign_bd_address co the da xep GPIO1 vao 0xA001_0000)
set_property offset 0xA0020000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_gpio_1_Reg}]
set_property range 64K         [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_gpio_1_Reg}]
set_property offset 0xA0010000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_gpio_0_Reg}]
set_property range 64K         [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_gpio_0_Reg}]
foreach s [get_bd_addr_segs -of [get_bd_addr_spaces]] { puts "###ADDR [get_property NAME $s] [get_property OFFSET $s] [get_property RANGE $s]" }
# khop FREQ_HZ khai bao cua module-reference voi tan so PS that tao (187,498 / 249,997 MHz)
set f0 [get_property CONFIG.FREQ_HZ [get_bd_pins $PS/pl_clk0]]
set f2 [get_property CONFIG.FREQ_HZ [get_bd_pins $PS/pl_clk2]]
set f3 [get_property CONFIG.FREQ_HZ [get_bd_pins $PS/pl_clk3]]
foreach {obj f} [list [get_bd_pins hmao_engine_0/clk] $f2 [get_bd_intf_pins hmao_engine_0/M_AXI] $f2                       [get_bd_pins hmao_engine_0/wdt_clk] $f3] {
  if {[catch {set_property CONFIG.FREQ_HZ $f $obj} e]} { puts "###WARN FREQ_HZ $obj: $e" }
}
foreach {pin f} [list hmao_gpio_cdc_bridge_0/src_clk $f0 hmao_gpio_cdc_bridge_0/dst_clk $f2] {
  catch {set_property CONFIG.FREQ_HZ $f [get_bd_pins $pin]}
}
puts "###FREQ pl_clk0=$f0 pl_clk2=$f2 pl_clk3=$f3"
if {$f2 != 187500000 || $f3 != 250000000} { puts "###ERROR PS clock khong dung 187,5/250 MHz"; exit 1 }
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
add_files -norecurse [file join $PRJ tsm_only.gen sources_1 bd system hdl system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "###ERROR synth"; exit 1 }
open_run synth_1
puts "###FIX preproc burst_inflight regs: [llength [get_cells -quiet -hier -filter {NAME =~ *u_preproc/burst_inflight_reg*}]]"
puts "###FIX wdt_run_active regs: [llength [get_cells -quiet -hier -filter {NAME =~ *u_hmao/wdt_run_active_reg*}]]"
close_design

set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1
open_run impl_1
report_timing_summary -file [file join $OUT timing_summary.rpt]
report_utilization -file [file join $OUT utilization.rpt]
report_route_status -file [file join $OUT route_status.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
foreach clk {clk_pl_0 clk_pl_2 clk_pl_3} {
  set p [get_timing_paths -quiet -max_paths 1 -setup -to [get_clocks -quiet $clk]]
  if {[llength $p]} { puts "###CLK $clk WNS=[get_property SLACK $p]" }
}
puts "###RESULT WNS=$wns WHS=$whs"
set bit [file join $PRJ tsm_only.runs impl_1 system_wrapper.bit]
if {[file exists $bit]} {
  file copy -force $bit [file join $OUT system_wrapper_tsm_only.bit]
  puts "###BIT [file join $OUT system_wrapper_tsm_only.bit]"
} else { puts "###ERROR no bitstream"; exit 1 }
exit 0
