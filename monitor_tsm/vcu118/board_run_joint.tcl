# Claude 10/11/2026: VCU118 joint run, board day.  Run from the vcu118 folder:
#   C:/Vivado/Vivado/2023.2/bin/xsdb.bat board_run_joint.tcl
# Start the UART capture first (python board_capture.py) - the firmware prints everything on the USB-UART.
# Steps: program bitstream -> halt MicroBlaze -> load DDR images (ddr_load.tsv, MicroBlaze address 0x8000_0000+phys)
#        -> read back the first/last word of every image -> download joint_fw.elf -> run.
set HERE [file normalize [file dirname [info script]]]
# VCU118_DDR=062 selects the bitstream built for MT40A256M16LY-062E DDR4 (default 083 = MT40A256M16GE-083E)
set BITDIR out_joint
if {[info exists ::env(VCU118_DDR)] && $::env(VCU118_DDR) eq "062"} { set BITDIR out_joint_062 }
set BIT  [file join $HERE $BITDIR system_wrapper_joint.bit]
set ELF  [file join $HERE fw mb joint_fw.elf]
set DAT  [file join $HERE fw joint_data]
set LOGF [file join $HERE board_logs xsdb_[clock format [clock seconds] -format %Y%m%d_%H%M%S].log]
file mkdir [file join $HERE board_logs]
set LOG [open $LOGF w]
proc say {m} { global LOG; puts $m; puts $LOG $m; flush $LOG }
proc fail {m} { say "ERROR: $m"; exit 1 }
foreach f [list $BIT $ELF [file join $DAT ddr_load.tsv]] { if {![file exists $f]} { fail "missing $f" } }

# Lab remote board (README_Remote_VCU118): hw_server <LAB_BOARD_IP>:3122, JTAG serial <JTAG_SERIAL>, 15 MHz.
# Override with env VCU118_HW_SERVER=host:port (e.g. localhost:3121 for a local board).
set HWS "<LAB_BOARD_IP>:3122"
if {[info exists ::env(VCU118_HW_SERVER)]} { set HWS $::env(VCU118_HW_SERVER) }
if {[catch {connect -url tcp:$HWS} e]} { fail "cannot reach hw_server $HWS (Tailscale up? Vivado/xsdb version vs host 2026.1?): $e" }
after 500
say "hw_server $HWS targets:\n[targets]"
if {[catch {targets -set -nocase -filter {jtag_cable_serial =~ "*<JTAG_SERIAL>*" && name =~ "xcvu9p*"}} e]} {
  if {[catch {targets -set -nocase -filter {name =~ "xcvu9p*"}} e2]} { fail "no xcvu9p JTAG target: $e2" }
}
catch {jtag frequency 15000000}
say "program [file tail $BIT]"
if {[catch {fpga -file $BIT} e]} { fail "fpga: $e" }
after 3000   ;# MIG calibration
if {[catch {targets -set -nocase -filter {name =~ "*MicroBlaze*#0*"}} e]} {
  if {[catch {targets -set -nocase -filter {name =~ "*MicroBlaze*"}} e2]} { fail "no MicroBlaze target: $e2" }
}
catch {stop}
rst -processor
after 200

proc first_last {path} {
  set fh [open $path rb]; set a [read $fh 4]; seek $fh -4 end; set b [read $fh 4]; close $fh
  binary scan $a iu x; binary scan $b iu y
  return [list [expr {$x & 0xFFFFFFFF}] [expr {$y & 0xFFFFFFFF}]]
}
set fh [open [file join $DAT ddr_load.tsv] r]
set t0 [clock milliseconds]
while {[gets $fh line] >= 0} {
  if {$line eq "" || [string index $line 0] eq "#"} continue
  lassign [split $line "\t"] name phys size
  set path [file join $DAT $name]
  if {[file size $path] != $size} { fail "$name size [file size $path] != $size" }
  set addr [expr {0x80000000 + $phys}]
  set t1 [clock milliseconds]
  if {[catch {dow -data $path $addr} e]} { fail "dow -data $name: $e" }
  lassign [first_last $path] w0 w1
  set r0 [lindex [mrd -value $addr 1] 0]
  set r1 [lindex [mrd -value [expr {$addr + $size - 4}] 1] 0]
  set ok [expr {$r0 == $w0 && $r1 == $w1}]
  say [format "DDRLOAD %-30s mb=0x%08X bytes=%d ms=%d first=%08X/%08X last=%08X/%08X %s" $name $addr $size \
       [expr {[clock milliseconds] - $t1}] $r0 $w0 $r1 $w1 [expr {$ok ? "OK" : "MISMATCH"}]]
  if {!$ok} { fail "DDR readback mismatch for $name" }
}
close $fh
say "DDR images loaded in [expr {([clock milliseconds] - $t0) / 1000.0}] s"
if {[catch {dow $ELF} e]} { fail "dow elf: $e" }
con
say "firmware running; results arrive on the UART (board_capture.py). xsdb log: $LOGF"
after 2000
close $LOG
exit 0
