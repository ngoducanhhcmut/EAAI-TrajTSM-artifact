# =============================================================================
# gen_psu_init_zcu106_sodimm.tcl — sinh psu_init cho board ZCU106 cua lab, DDR khop SPD cua thanh RAM dang gan:
#   Micron MTA4ATF51264HZ-2G6E1: DDR4 SO-DIMM 4 GB, 1 rank, 4 chip x16 8Gb, bus 64 bit, 16 bit hang, 10 bit cot.
#   (doc bang scripts/board_read_spd.tcl, I2C1 mux 0x75 kenh 3, dia chi 0x51)
# Preset ZCU106 goc gia dinh thanh RAM chip x8 4Gb -> DDR loi VREF / doc sai / treo.
# Ra: deliverables/zcu106/psu_init_zcu106_sodimm_x16_8gb.tcl (MIO/clock = preset ZCU106, chi DDR doi).
#   vivado -mode batch -notrace -source scripts/gen_psu_init_zcu106_sodimm.tcl
# =============================================================================
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PRJ  [file join $ROOT hw_psu_zcu106_sodimm]
file delete -force $PRJ
create_project psu_zcu106_sodimm $PRJ -part xczu7ev-ffvc1156-2-e
set_property board_part xilinx.com:zcu106:part0:2.6 [current_project]
create_bd_design ps
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
puts "### preset: COMPONENTS=[get_property CONFIG.PSU__DDRC__COMPONENTS $ps] WIDTH=[get_property CONFIG.PSU__DDRC__DRAM_WIDTH $ps] CAP=[get_property CONFIG.PSU__DDRC__DEVICE_CAPACITY $ps]"
# DDR theo SPD; toc do giu DDR4-2133 nhu preset (module ho tro toi 2666 -> du bien)
set_property -dict [list \
  CONFIG.PSU__DDRC__COMPONENTS {UDIMM} \
  CONFIG.PSU__DDRC__DRAM_WIDTH {16 Bits} \
  CONFIG.PSU__DDRC__DEVICE_CAPACITY {8192 MBits} \
  CONFIG.PSU__DDRC__SPEED_BIN {DDR4_2133P} \
  CONFIG.PSU__DDRC__BUS_WIDTH {64 Bit} \
  CONFIG.PSU__DDRC__RANK_ADDR_COUNT {0} \
  CONFIG.PSU__DDRC__BG_ADDR_COUNT {1} \
  CONFIG.PSU__DDRC__ROW_ADDR_COUNT {16} \
  CONFIG.PSU__DDRC__ECC {Disabled}] $ps
foreach k {COMPONENTS DRAM_WIDTH DEVICE_CAPACITY SPEED_BIN BUS_WIDTH RANK_ADDR_COUNT BG_ADDR_COUNT ROW_ADDR_COUNT COL_ADDR_COUNT \
           CL CWL T_RCD T_RP T_RAS_MIN T_RC T_FAW T_RFC} {
  if {![catch {get_property CONFIG.PSU__DDRC__$k $ps} v]} { puts "### DDRC $k = $v" }
}
puts "### DDR_CTRL_FREQ = [get_property CONFIG.PSU__CRF_APB__DDR_CTRL__FREQMHZ $ps]"
# noi cac chan aclk cua cong AXI phia PS vao pl_clk0 (chi de BD hop le; khong anh huong psu_init)
foreach pin [get_bd_pins -quiet -of $ps -filter {DIR == I && NAME =~ "*aclk*"}] {
  catch {connect_bd_net [get_bd_pins $ps/pl_clk0] $pin}
}
validate_bd_design
save_bd_design
generate_target all [get_files ps.bd]
set f [glob -nocomplain [file join $PRJ psu_zcu106_sodimm.gen sources_1 bd ps ip ps_zynq_ultra_ps_e_0_0 psu_init.tcl]]
if {$f eq ""} { set f [lindex [glob -nocomplain -directory $PRJ -types f */*/*/*/*/*/psu_init.tcl] 0] }
if {$f eq "" || ![file exists $f]} { puts "###ERROR khong thay psu_init.tcl"; exit 1 }
set out [file join $ROOT deliverables zcu106 psu_init_zcu106_sodimm_x16_8gb.tcl]
file copy -force $f $out
puts "###PSU_INIT $out"
exit 0
