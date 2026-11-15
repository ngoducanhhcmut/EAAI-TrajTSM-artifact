set_param general.maxThreads 1
set R [file normalize [file dirname [info script]]/../rtl]
set out [file normalize [file dirname [info script]]]/m_tsmx_geom
file mkdir $out
create_project -in_memory -part xczu7ev-ffvc1156-2-e
read_verilog -sv $R/geom/m_tsmx_geom_su.sv
read_verilog -sv $R/geom/m_tsmx_geom.sv
synth_design -top m_tsmx_geom -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 5.333 -name clk [get_ports -filter {NAME =~ *clk*}]
report_utilization -file $out/util.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
write_checkpoint -force $out/post_synth.dcp
