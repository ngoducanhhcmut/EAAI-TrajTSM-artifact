# =============================================================================
# sim_traj/build_bd.tcl — project mo phong muc he thong cho VLA-Traj (planning_top), khong co PS.
#   planning_top (RTL, ngoai BD) --M_AXI 128b--> SmartConnect that --> AXI VIP slave 128 bit (thay HP0/DDR)
#   AXI-Lite cua planning_top do testbench lai truc tiep (de thu AW/W lech nhau).
#   vivado -mode batch -notrace -source sim_traj/build_bd.tcl
# =============================================================================
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PRJ  [file join $ROOT sim_traj prj]
file delete -force $PRJ
create_project traj_sysbd $PRJ -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]
create_bd_design traj_ifc

create_bd_port -dir I -type clk -freq_hz 150000000 clk0
create_bd_port -dir I -type rst ext_rst_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports ext_rst_n]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst0
connect_bd_net [get_bd_ports clk0] [get_bd_pins rst0/slowest_sync_clk]
connect_bd_net [get_bd_ports ext_rst_n] [get_bd_pins rst0/ext_reset_in]
create_bd_port -dir O -type rst rst0_n
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_ports rst0_n]

# cong doc DDR cua planning_top: cung thuoc tinh voi planning_top_bd_ref.v (M_AXI)
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_TRAJ
set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 128 CONFIG.ADDR_WIDTH 32 CONFIG.ID_WIDTH 6 \
  CONFIG.READ_WRITE_MODE READ_ONLY CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 \
  CONFIG.HAS_QOS 1 CONFIG.HAS_REGION 0 CONFIG.MAX_BURST_LENGTH 256 CONFIG.NUM_READ_OUTSTANDING 4 \
  CONFIG.SUPPORTS_NARROW_BURST 0 CONFIG.FREQ_HZ 150000000] [get_bd_intf_ports S_AXI_TRAJ]
set_property CONFIG.ASSOCIATED_BUSIF S_AXI_TRAJ [get_bd_ports clk0]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_dma
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells smartconnect_dma]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 axi_vip_mem
set_property -dict [list CONFIG.INTERFACE_MODE SLAVE CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 128 \
  CONFIG.ADDR_WIDTH 49 CONFIG.ID_WIDTH 6 CONFIG.READ_WRITE_MODE READ_WRITE \
  CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 CONFIG.HAS_QOS 1 \
  CONFIG.HAS_REGION 0 CONFIG.HAS_SIZE 1 CONFIG.HAS_BRESP 1 CONFIG.HAS_RRESP 1] [get_bd_cells axi_vip_mem]
connect_bd_intf_net [get_bd_intf_ports S_AXI_TRAJ] [get_bd_intf_pins smartconnect_dma/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_dma/M00_AXI] [get_bd_intf_pins axi_vip_mem/S_AXI]
connect_bd_net [get_bd_ports clk0] [get_bd_pins smartconnect_dma/aclk] [get_bd_pins axi_vip_mem/aclk]
connect_bd_net [get_bd_pins rst0/interconnect_aresetn] [get_bd_pins smartconnect_dma/aresetn]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins axi_vip_mem/aresetn]

assign_bd_address
set_property offset 0x00000000 [get_bd_addr_segs {S_AXI_TRAJ/SEG_axi_vip_mem_Reg}]
set_property range 2G         [get_bd_addr_segs {S_AXI_TRAJ/SEG_axi_vip_mem_Reg}]
validate_bd_design
save_bd_design
make_wrapper -files [get_files traj_ifc.bd] -top
add_files -norecurse [file join $PRJ traj_sysbd.gen sources_1 bd traj_ifc hdl traj_ifc_wrapper.v]
generate_target simulation [get_files traj_ifc.bd]
export_ip_user_files -of_objects [get_files traj_ifc.bd] -no_script -sync -force -quiet

# RTL Traj (cung danh sach voi E2E 35/35, reports/unit/e2e_files_i.txt) + vo BD + testbench
set fs [get_filesets sim_1]
set srcs [list rtl/include/planning_pkg.sv]
foreach f [split [string trim [read [open [file join $ROOT reports unit e2e_files_i.txt]]]]] {
  if {$f ne "" && ![string match tb/* $f]} { lappend srcs $f }
}
lappend srcs rtl/src/top/planning_top_bd_wrapper.sv rtl/src/top/planning_top_bd_ref.v tb/system/tb_traj_sysbd.sv
foreach f $srcs { add_files -fileset sim_1 -norecurse [file join $ROOT $f] }
foreach f {rtl/src/gru/sigmoid_lut_init.hex rtl/src/gru/tanh_lut_init.hex} { add_files -fileset sim_1 -norecurse [file join $ROOT $f] }
set_property include_dirs [list [file join $ROOT rtl src bert_v2]] $fs
set_property top tb_traj_sysbd $fs
set_property top_lib xil_defaultlib $fs
set_property -name {xsim.simulate.runtime} -value {all} -objects $fs
set_property -name {xsim.elaborate.debug_level} -value {off} -objects $fs
update_compile_order -fileset sim_1
launch_simulation -scripts_only -simset sim_1 -mode behavioral
puts "BD_OK"
