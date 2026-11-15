# Claude 30/10: engine glue only (children are black boxes) to locate glue area.
set_param general.maxThreads 1
set R [file normalize [file dirname [info script]]/../rtl]
set S [file normalize [file dirname [info script]]/bb_stubs]
set out [file normalize [file dirname [info script]]]/m_tsmx_engine_bb
file mkdir $out
create_project -in_memory -part xczu7ev-ffvc1156-2-e
foreach f [glob $S/*.sv] { read_verilog -sv $f }
read_verilog -sv $R/top/m_tsmx_engine.sv
synth_design -top m_tsmx_engine -mode out_of_context -flatten_hierarchy rebuilt -generic PARA_P=2 -generic PARA_G=2
create_clock -period 5.333 -name clk [get_ports -filter {NAME =~ *clk*}]
report_utilization -file $out/util.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
write_checkpoint -force $out/post_synth.dcp
