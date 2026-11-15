# Claude 04/11/2026: run the TSM-X software baseline on ZCU106 Cortex-A53 #0 and Cortex-R5F #0 (no bitstream,
# no UART). Each core writes struct ts_out (bench.c) to OCM; this script polls it and logs the raw words.
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_cpu_bench.tcl          (both cores)
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat run_cpu_bench.tcl a53      (one core: a53 | r5)
# Result: results/cpu_<time>.log  ->  python parse_cpu.py results/cpu_<time>.log
set HERE [file normalize [file dirname [info script]]]
set ROOT [file normalize [file join $HERE .. .. ..]]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
set WHICH [expr {[llength $argv] ? [lindex $argv 0] : "both"}]
file mkdir [file join $HERE results]
set LOGF [file join $HERE results "cpu_[clock format [clock seconds] -format %Y%m%d_%H%M%S].log"]
set LOG [open $LOGF w]
proc say {m} { global LOG; puts $m; puts $LOG $m; flush $LOG }
proc fail {m} { say "CPU_FAIL $m"; exit 1 }

if {[catch {connect} e]} { fail "JTAG connect: $e" }
after 2000
targets -set -nocase -filter {name =~ "*PSU*"}
rst -system
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
source $PSU
if {[catch {psu_init} e]} { fail "psu_init: $e" }
after 500
# clock registers for the record: APLL_CTRL, ACPU_CTRL, RPLL_CTRL, IOPLL_CTRL, CPU_R5_CTRL, TIMESTAMP_REF_CTRL
foreach {n a} {APLL_CTRL 0xFD1A0020 ACPU_CTRL 0xFD1A0060 RPLL_CTRL 0xFF5E0030 IOPLL_CTRL 0xFF5E0020 CPU_R5_CTRL 0xFF5E0090 TIMESTAMP_REF_CTRL 0xFF5E0128} {
  say [format "CLKREG %s 0x%08X" $n [mrd -force -value $a 1]]
}

proc run_core {tag filter elf base} {
  targets -set -nocase -filter {name =~ "*PSU*"}
  mwr -force [expr {$base + 144}] 0
  # Claude 08/11: after psu_init the APU L2 cache and ACPU0 are still held in reset (RST_FPD_APU=0x390F); the A53
  # BSP then hangs in invalidateCaches. Release L2 + core 0 only (bits 0, 8, 10).
  # Claude 08/11: disable the FPD/LPD/CSU system watchdogs (ZMR key 0xABC, WDEN=0) so a long run is not reset
  foreach wdt {0xFD4D0000 0xFF150000 0xFFCB0000} { catch {mwr -force $wdt 0x00ABC000} }
  if {$tag eq "A53"} { set r0 [mrd -force -value 0xFD1A0104 1]; mwr -force 0xFD1A0104 [expr {$r0 & ~0x501}]; say [format "RST_FPD_APU 0x%08X" [mrd -force -value 0xFD1A0104 1]] }
  targets -set -nocase -filter "name =~ \"$filter\""
  rst -processor
  after 300
  if {[catch {dow $elf} e]} { fail "$tag dow: $e" }
  set t0 [clock milliseconds]
  con
  targets -set -nocase -filter {name =~ "*PSU*"}
  while {[mrd -force -value [expr {$base + 144}] 1] != 0x75B0C0DE} {
    after 500
    if {[clock milliseconds] - $t0 > 900000} { fail "$tag timeout (no result after 900 s)" }
  }
  set words [mrd -force -value $base 37]
  say "CORE $tag wall_ms=[expr {[clock milliseconds] - $t0}] words=[join [lsort -command {apply {{a b} {return 0}}} [list]] ,][set _l {}; foreach w $words {lappend _l [format 0x%08X $w]}; join $_l ,]"
  targets -set -nocase -filter "name =~ \"$filter\""
  catch {stop}
}
if {$WHICH eq "both" || $WHICH eq "a53"} { run_core A53 "*A53*#0*" [file join $HERE tsmx_a53.elf] 0xFFFC0000 }
if {$WHICH eq "both" || $WHICH eq "r5"}  { run_core R5F "*R5*#0*"  [file join $HERE tsmx_r5.elf]  0xFFFD0000 }
say "CPU_DONE log=$LOGF"
close $LOG
exit 0
