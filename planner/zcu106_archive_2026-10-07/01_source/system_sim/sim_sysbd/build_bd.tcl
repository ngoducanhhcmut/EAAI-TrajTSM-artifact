# =============================================================================
# sim_sysbd/build_bd.tcl — dung project mo phong muc he thong cho TSM (khong co PS).
#
# Muc dich: kiem tra TSM qua dung cac IP that cua BD tren board, thay cho mo hinh AXI tu viet:
#   TSM (RTL hoac netlist tong hop) --256b--> SmartConnect --128b--> AXI VIP slave (thay cong HP1/DDR)
#   AXI VIP master (thay R5) --AXI-Lite--> SmartConnect --> axi_gpio_0 (start/irq_clear)
#                                                       --> axi_gpio_1 (doc ket qua)
# BD "tsm_ifc" chi chua phan ket noi; TSM, cau CDC va tsm_status_pack nam trong testbench.
#
#   vivado -mode batch -notrace -source sim_sysbd/build_bd.tcl
# =============================================================================
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PRJ  [file join $ROOT sim_sysbd prj]
file delete -force $PRJ
create_project tsm_sysbd $PRJ -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]

create_bd_design tsm_ifc

# ---- clock / reset ports (nhu BD that: pl_clk0 cho GPIO, pl_clk2 cho TSM + HP1) ----
create_bd_port -dir I -type clk -freq_hz 100000000 clk0
create_bd_port -dir I -type clk -freq_hz 187500000 clk2
create_bd_port -dir I -type rst ext_rst_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports ext_rst_n]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst0
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst2
connect_bd_net [get_bd_ports clk0] [get_bd_pins rst0/slowest_sync_clk]
connect_bd_net [get_bd_ports clk2] [get_bd_pins rst2/slowest_sync_clk]
connect_bd_net [get_bd_ports ext_rst_n] [get_bd_pins rst0/ext_reset_in] [get_bd_pins rst2/ext_reset_in]
create_bd_port -dir O -type rst rst0_n
create_bd_port -dir O -type rst rst2_n
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_ports rst0_n]
connect_bd_net [get_bd_pins rst2/peripheral_aresetn] [get_bd_ports rst2_n]

# ---- duong doc cua TSM: cong ngoai 256 bit, cung thuoc tinh voi hmao_engine_top_bd_ref ----
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_HMAO
set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 256 CONFIG.ADDR_WIDTH 32 CONFIG.ID_WIDTH 4 \
  CONFIG.READ_WRITE_MODE READ_ONLY CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 0 CONFIG.HAS_CACHE 0 CONFIG.HAS_PROT 0 \
  CONFIG.HAS_QOS 0 CONFIG.HAS_REGION 0 CONFIG.HAS_SIZE 1 CONFIG.MAX_BURST_LENGTH 64 \
  CONFIG.SUPPORTS_NARROW_BURST 1 CONFIG.FREQ_HZ 187500000] [get_bd_intf_ports S_AXI_HMAO]
set_property CONFIG.ASSOCIATED_BUSIF S_AXI_HMAO [get_bd_ports clk2]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_hmao
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells smartconnect_hmao]
# Thay cong S_AXI_HP1_FPD: AXI4 128 bit, ID 6 bit, dia chi 49 bit
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 axi_vip_mem
set_property -dict [list CONFIG.INTERFACE_MODE SLAVE CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 128 \
  CONFIG.ADDR_WIDTH 49 CONFIG.ID_WIDTH 6 CONFIG.READ_WRITE_MODE READ_WRITE CONFIG.SUPPORTS_NARROW 1 \
  CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 CONFIG.HAS_QOS 1 \
  CONFIG.HAS_REGION 0 CONFIG.HAS_SIZE 1 CONFIG.HAS_BRESP 1 CONFIG.HAS_RRESP 1] [get_bd_cells axi_vip_mem]
connect_bd_intf_net [get_bd_intf_ports S_AXI_HMAO] [get_bd_intf_pins smartconnect_hmao/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_hmao/M00_AXI] [get_bd_intf_pins axi_vip_mem/S_AXI]
connect_bd_net [get_bd_ports clk2] [get_bd_pins smartconnect_hmao/aclk] [get_bd_pins axi_vip_mem/aclk]
connect_bd_net [get_bd_pins rst2/peripheral_aresetn] [get_bd_pins smartconnect_hmao/aresetn] [get_bd_pins axi_vip_mem/aresetn]

# ---- duong dieu khien cua "R5" ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 axi_vip_cpu
set_property -dict [list CONFIG.INTERFACE_MODE MASTER CONFIG.PROTOCOL AXI4LITE CONFIG.DATA_WIDTH 32 \
  CONFIG.ADDR_WIDTH 32] [get_bd_cells axi_vip_cpu]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_axil
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] [get_bd_cells smartconnect_axil]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
set_property -dict [list CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_ALL_OUTPUTS_2 1 CONFIG.C_GPIO_WIDTH 1 \
  CONFIG.C_GPIO2_WIDTH 1 CONFIG.C_IS_DUAL 1] [get_bd_cells axi_gpio_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1
set_property -dict [list CONFIG.C_ALL_INPUTS 1 CONFIG.C_ALL_INPUTS_2 1 CONFIG.C_GPIO_WIDTH 32 \
  CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_IS_DUAL 1] [get_bd_cells axi_gpio_1]
connect_bd_intf_net [get_bd_intf_pins axi_vip_cpu/M_AXI] [get_bd_intf_pins smartconnect_axil/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_axil/M00_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_axil/M01_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]
connect_bd_net [get_bd_ports clk0] [get_bd_pins axi_vip_cpu/aclk] [get_bd_pins smartconnect_axil/aclk] \
  [get_bd_pins axi_gpio_0/s_axi_aclk] [get_bd_pins axi_gpio_1/s_axi_aclk]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins axi_vip_cpu/aresetn] \
  [get_bd_pins smartconnect_axil/aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn] [get_bd_pins axi_gpio_1/s_axi_aresetn]

create_bd_port -dir O gpio_start
create_bd_port -dir O gpio_irqclr
create_bd_port -dir I -from 31 -to 0 gpio_status
create_bd_port -dir I -from 31 -to 0 gpio_detail
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o]  [get_bd_ports gpio_start]
connect_bd_net [get_bd_pins axi_gpio_0/gpio2_io_o] [get_bd_ports gpio_irqclr]
connect_bd_net [get_bd_ports gpio_status] [get_bd_pins axi_gpio_1/gpio_io_i]
connect_bd_net [get_bd_ports gpio_detail] [get_bd_pins axi_gpio_1/gpio2_io_i]

# ---- dia chi nhu tren board ----
assign_bd_address
set_property offset 0x00000000 [get_bd_addr_segs {S_AXI_HMAO/SEG_axi_vip_mem_Reg}]
set_property range 2G         [get_bd_addr_segs {S_AXI_HMAO/SEG_axi_vip_mem_Reg}]
set_property offset 0xA0010000 [get_bd_addr_segs {axi_vip_cpu/Master_AXI/SEG_axi_gpio_0_Reg}]
set_property range 64K         [get_bd_addr_segs {axi_vip_cpu/Master_AXI/SEG_axi_gpio_0_Reg}]
set_property offset 0xA0020000 [get_bd_addr_segs {axi_vip_cpu/Master_AXI/SEG_axi_gpio_1_Reg}]
set_property range 64K         [get_bd_addr_segs {axi_vip_cpu/Master_AXI/SEG_axi_gpio_1_Reg}]
validate_bd_design
save_bd_design
make_wrapper -files [get_files tsm_ifc.bd] -top
add_files -norecurse [file join $PRJ tsm_sysbd.gen sources_1 bd tsm_ifc hdl tsm_ifc_wrapper.v]
generate_target simulation [get_files tsm_ifc.bd]
export_ip_user_files -of_objects [get_files tsm_ifc.bd] -no_script -sync -force -quiet
puts "BD_OK"
foreach s [get_bd_addr_segs -of [get_bd_addr_spaces]] { puts "ADDR [get_property NAME $s] [get_property OFFSET $s] [get_property RANGE $s]" }
