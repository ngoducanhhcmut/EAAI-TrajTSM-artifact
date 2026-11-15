open_checkpoint m_tsmx_engine_bb/post_synth.dcp
foreach p {u_tsmx_hash/i_data[5000] u_tsmx_hash/i_data[100] u_tsmx_sweep_0/i_world[5000] u_tsmx_sweep_1/i_world[5000] u_tsmx_sweep_0/i_world[8195]} {
  set pin [get_pins $p]
  set cells [get_cells -of [all_fanin -flat $pin] -filter {REF_NAME =~ LUT*}]
  set regs [all_fanin -flat -startpoints_only $pin]
  puts "CONE $p luts=[llength $cells] start=[llength $regs]"
  set k 0
  foreach r [get_cells -of $regs] { if {$k<12} {puts "   [get_property NAME $r]"}; incr k }
}
