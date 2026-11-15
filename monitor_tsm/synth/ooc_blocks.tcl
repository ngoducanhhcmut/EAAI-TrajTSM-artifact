# Claude 29/10: OOC synthesis of single TSM-X sub-blocks on ZCU106 (xczu7ev) at 187.5 MHz
set R [file normalize [file dirname [info script]]/../rtl]
set parts xczu7ev-ffvc1156-2-e
foreach {top files} {
  m_tsmx_geom   {arith/m_tsmx_arith_div.sv geom/m_tsmx_geom_adv.sv geom/m_tsmx_geom_swept.sv geom/m_tsmx_geom.sv}
  m_tsmx_mrmgen {arith/m_tsmx_arith_div.sv arith/m_tsmx_arith.sv mrmgen/m_tsmx_mrmgen.sv}
} {
  set out [file normalize [file dirname [info script]]]/$top
  file mkdir $out
  create_project -in_memory -part $parts
  foreach f $files { read_verilog -sv $R/$f }
  synth_design -top $top -mode out_of_context -flatten_hierarchy rebuilt
  create_clock -period 5.333 -name clk [get_ports -filter {NAME =~ *clk*}]
  report_utilization -file $out/util.rpt
  report_timing_summary -max_paths 5 -file $out/timing.rpt
  close_project
}
