# Claude 30/10: OOC synthesis of ONE TSM-X sub-block (argv: top file...), ZCU106 xczu7ev @187.5 MHz
set R [file normalize [file dirname [info script]]/../rtl]
set top [lindex $argv 0]
set out [file normalize [file dirname [info script]]]/$top
file mkdir $out
create_project -in_memory -part xczu7ev-ffvc1156-2-e
foreach f [lrange $argv 1 end] { read_verilog -sv $R/$f }
synth_design -top $top -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 5.333 -name clk [get_ports -filter {NAME =~ *clk*}]
report_utilization -file $out/util.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
