# Claude 12/11/2026: wipe research data from the lab VCU118 after the joint run.
# 1) MicroBlaze writes zeros over every DDR4 region the run used; 2) spot-check reads return 0;
# 3) program the lab's own bitstream (replaces our design, clears on-chip BRAM/URAM/LMB).
set HERE [file normalize [file dirname [info script]]]
set Z    $::env(ZEROFILE)
set LAB  $::env(LABBIT)
set LOG [open [file join $HERE board_logs wipe_[clock format [clock seconds] -format %Y%m%d_%H%M%S].log] w]
proc say {m} { global LOG; puts $m; puts $LOG $m; flush $LOG }
connect -url tcp:$::env(VCU118_HW_SERVER)
after 500
targets -set -nocase -filter {name =~ "*MicroBlaze*#0*"}
catch {stop}
set zsize [file size $Z]
# region list: base, bytes (multiples of the zero file size are written chunk by chunk)
foreach {base bytes} {0x80000000 0x01940000 0x90000000 0x01211000} {
  set t0 [clock milliseconds]
  for {set off 0} {$off < $bytes} {incr off $zsize} {
    if {[catch {dow -data $Z [expr {$base + $off}]} e]} { say "ERROR dow at [format 0x%08X [expr {$base + $off}]]: $e"; exit 1 }
  }
  set bad 0
  foreach probe {0 0x1000 0x600000 0x640000 0x17D4000 0x1900000 0x1210000} {
    if {$probe >= $bytes} continue
    set v [lindex [mrd -value [expr {$base + $probe}] 4] 0]
    if {$v != 0} { incr bad }
  }
  set last [lindex [mrd -value [expr {$base + $bytes - 4}] 1] 0]
  if {$last != 0} { incr bad }
  say [format "ZERO base=0x%08X bytes=%d ms=%d nonzero_probes=%d" $base $bytes [expr {[clock milliseconds] - $t0}] $bad]
  if {$bad} { say "ERROR region not zero"; exit 1 }
}
targets -set -nocase -filter {name =~ "xcvu9p*"}
say "program lab bitstream [file tail $LAB]"
if {[catch {fpga -file $LAB} e]} { say "ERROR fpga: $e"; exit 1 }
after 2000
say "targets after programming:\n[targets]"
say WIPE_DONE
close $LOG
exit 0
