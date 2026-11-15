set_param general.maxThreads 1
set R [file normalize [file dirname [info script]]/../rtl]
set out [file normalize [file dirname [info script]]]/m_tsmx_mrmgen
file mkdir $out
create_project -in_memory -part xczu7ev-ffvc1156-2-e
read_verilog -sv $R/arith/m_tsmx_arith_div.sv
read_verilog -sv $R/arith/m_tsmx_arith.sv
read_verilog -sv $R/mrmgen/m_tsmx_mrmgen.sv
synth_design -top m_tsmx_mrmgen -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 5.333 -name clk [get_ports -filter {NAME =~ *clk*}]
report_utilization -file $out/util.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
write_checkpoint -force $out/post_synth.dcp
