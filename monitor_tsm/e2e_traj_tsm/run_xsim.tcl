# vivado -mode batch -source run_xsim.tcl -tclargs [mutant]
# All generated compiler/simulation files stay inside this directory.
set here [file dirname [file normalize [info script]]]
cd $here
if {![file exists sources.f]} {error "Run gen_e2e_vectors.py first"}
set vr $::env(XILINX_VIVADO)
proc run_tool {name args} {
    set exe [auto_execok $name]
    if {$exe eq ""} {error "$name is missing; run in Vivado 2023.2 command prompt"}
    puts "RUN $name $args"
    if {[catch {exec {*}$exe {*}$args 2>@1} out]} {puts $out;error "$name failed"}
    puts $out
}
run_tool xvlog -sv -work xpm -i "$vr/data/ip/xpm/xpm_memory/hdl" "$vr/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv"
run_tool xvlog -sv -d SYNTHESIS -d ASSERT_ON -i ../../../rtl/include -i ../../../rtl/src/bert_v2 -i . -f sources.f
run_tool xelab -relax -debug typical -L xpm -L unisims_ver -L secureip tb_e2e_traj_tsm -s e2e_traj_tsm
set fd [open run_all.tcl w];puts $fd "run all\nquit";close $fd
set opts [list -tclbatch run_all.tcl -testplusarg PLANNER_VEC=../../../tb/e2e/vec/]
if {[llength $argv] && [lindex $argv 0] eq "mutant"} {
    lappend opts -testplusarg MUTANT_WAYPOINT
}
run_tool xsim e2e_traj_tsm {*}$opts
