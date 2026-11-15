# Export placement data of the VCU118 joint build that ran on the board 12/11/2026
# (bitstream md5 6d5125a84536140fa2c68946c768d4a8 = impl_1/system_wrapper.bit; routed dcp of the same run).
# Read-only: opens the checkpoint, writes TSV files to figdata/.
#   vivado -mode batch -notrace -source export_floorplan.tcl
set here [file normalize [file dirname [info script]]]
set out  $here/figdata
file mkdir $out
set_param tcl.collectionResultDisplayLimit 0
open_checkpoint $here/prj_joint/vcu118_joint.runs/impl_1/system_wrapper_routed.dcp

# occupied sites per block (unique sites; RPM grid coordinates are common to all site types)
set groups {
  planner   {system_i/plan_0/*}
  monitor   {system_i/tsmx_0/*}
  ddr4      {system_i/ddr4_0/*}
  interconnect {system_i/sc_ddr/* system_i/sc_mb/* system_i/axis_fifo/*}
  firmware  {system_i/microblaze_0/* system_i/microblaze_0_local_memory/* system_i/mdm_1/* system_i/uart_0/* system_i/timer_0/* system_i/gpio_0/* system_i/iic_0/*}
}
set fh [open $out/occupied_sites.tsv w]
puts $fh "group\tsite\ttype\trpm_x\trpm_y"
foreach {g pats} $groups {
  set ors {}
  foreach p $pats { lappend ors "NAME =~ $p" }
  set cells [get_cells -hier -quiet -filter "IS_PRIMITIVE && LOC != \"\" && ([join $ors { || }])"]
  set sites [get_sites -quiet -of_objects $cells]
  foreach s $sites {
    puts $fh "$g\t$s\t[get_property SITE_TYPE $s]\t[get_property RPM_X $s]\t[get_property RPM_Y $s]"
  }
  puts "group $g cells [llength $cells] sites [llength $sites]"
}
close $fh

# device outline: all fabric sites of the main types (for the grey background and SLR lines)
set fh [open $out/device_sites.tsv w]
puts $fh "type\trpm_x\trpm_y\tslr"
foreach slr [get_slrs] {
  set idx [get_property SLR_INDEX $slr]
  foreach s [get_sites -quiet -of_objects $slr -filter {SITE_TYPE =~ SLICE* || SITE_TYPE =~ DSP48* || SITE_TYPE =~ RAMB36 || SITE_TYPE == URAM288}] {
    puts $fh "[get_property SITE_TYPE $s]\t[get_property RPM_X $s]\t[get_property RPM_Y $s]\t$idx"
  }
}
close $fh
puts "DONE"
