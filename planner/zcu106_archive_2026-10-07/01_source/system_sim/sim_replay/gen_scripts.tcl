# sim_replay/gen_scripts.tcl — them RTL TSM (chi doc) + tb_tsm_replay vao project, sinh script xsim roi thoat.
set ROOT [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $ROOT sim_replay prj tsm_replay.xpr]
set fs [get_filesets sim_1]
set src [list $ROOT/rtl/include/planning_pkg.sv $ROOT/HMAO/hmao_pkg.sv $ROOT/HMAO/hmao_interfaces.sv \
  $ROOT/HMAO/hmao_fsm.sv $ROOT/HMAO/hmao_preproc.sv $ROOT/HMAO/hmao_adaptive_margin.sv \
  $ROOT/HMAO/hmao_zonotope_gen.sv $ROOT/HMAO/hmao_admm_solver.sv $ROOT/HMAO/hmao_collision_sat.sv \
  $ROOT/HMAO/hmao_axi_arbiter.sv $ROOT/HMAO/hmao_safety_modules.sv $ROOT/HMAO/hmao_engine_top.sv \
  $ROOT/HMAO/hmao_engine_top_bd_wrapper.sv $ROOT/HMAO/hmao_engine_top_bd_ref.v \
  $ROOT/rtl/src/cdc/hsync_chain.sv $ROOT/rtl/src/cdc/hmao_gpio_cdc_bridge.sv \
  $ROOT/HMAO/tsm_status_pack.v $ROOT/tb/system/tb_tsm_replay.sv]
add_files -fileset sim_1 -norecurse $src
foreach f [list traj.mem wm.mem expect.txt] { add_files -fileset sim_1 -norecurse $ROOT/sim_replay/data/$f }
set_property top tb_tsm_replay $fs
set_property top_lib xil_defaultlib $fs
set_property -name {xsim.simulate.runtime} -value {all} -objects $fs
set_property -name {xsim.elaborate.debug_level} -value {off} -objects $fs
update_compile_order -fileset sim_1
launch_simulation -scripts_only -simset sim_1 -mode behavioral
puts "SCRIPTS_OK"
close_project
