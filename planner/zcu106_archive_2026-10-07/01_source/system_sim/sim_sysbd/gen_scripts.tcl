# sim_sysbd/gen_scripts.tcl — them RTL TSM + testbench vao project mo phong, sinh script xsim
# (compile/elaborate/simulate) roi thoat; chay script bang tay de tranh launch_simulation bi treo.
#   MODE=rtl     : TSM tu RTL hien hanh (khong define mo phong nao -> dinh thoi nhu bitstream)
#   MODE=netlist : TSM la netlist tong hop dung trong bitstream (sim_sysbd/tsm_netlist_funcsim.v)
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set MODE [expr {[info exists ::env(MODE)] ? $::env(MODE) : "rtl"}]
open_project [file join $ROOT sim_sysbd prj tsm_sysbd.xpr]
set SS [expr {$MODE eq "netlist" ? "sim_2" : "sim_1"}]
if {[llength [get_filesets -quiet $SS]] == 0} { create_fileset -simset $SS }
set fs [get_filesets $SS]
if {[llength [get_files -quiet -of $fs *.sv]]} { remove_files -fileset $SS [get_files -of $fs -filter {FILE_TYPE == SystemVerilog || FILE_TYPE == Verilog}] -quiet }
set common [list \
  $ROOT/rtl/src/cdc/hsync_chain.sv $ROOT/rtl/src/cdc/hmao_gpio_cdc_bridge.sv \
  $ROOT/HMAO/tsm_status_pack.v $ROOT/tb/system/tb_tsm_sysbd.sv]
if {$MODE eq "netlist"} {
  set tsm [list $ROOT/sim_sysbd/tsm_netlist_funcsim.v]
  set_property verilog_define {TSM_NETLIST} $fs
} else {
  set tsm [list $ROOT/rtl/include/planning_pkg.sv $ROOT/HMAO/hmao_pkg.sv $ROOT/HMAO/hmao_interfaces.sv \
    $ROOT/HMAO/hmao_fsm.sv $ROOT/HMAO/hmao_preproc.sv $ROOT/HMAO/hmao_adaptive_margin.sv \
    $ROOT/HMAO/hmao_zonotope_gen.sv $ROOT/HMAO/hmao_admm_solver.sv $ROOT/HMAO/hmao_collision_sat.sv \
    $ROOT/HMAO/hmao_axi_arbiter.sv $ROOT/HMAO/hmao_safety_modules.sv $ROOT/HMAO/hmao_engine_top.sv \
    $ROOT/HMAO/hmao_engine_top_bd_wrapper.sv $ROOT/HMAO/hmao_engine_top_bd_ref.v]
  set_property verilog_define {} $fs
}
add_files -fileset $SS -norecurse [concat $tsm $common]
foreach f [list traj.mem wm.mem expect.txt] { add_files -fileset $SS -norecurse $ROOT/sim_sysbd/data/$f }
set_property top tb_tsm_sysbd $fs
set_property top_lib xil_defaultlib $fs
set_property -name {xsim.simulate.runtime} -value {all} -objects $fs
set_property -name {xsim.elaborate.debug_level} -value {off} -objects $fs
update_compile_order -fileset $SS
launch_simulation -scripts_only -simset $SS -mode behavioral
puts "SCRIPTS_OK $MODE"
close_project
