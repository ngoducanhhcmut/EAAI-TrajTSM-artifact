# board_run_traj_zcu106.tcl — PHUONG AN DU PHONG: chi chay VLA-Traj tren PL (khong dung TSM).
# Bitstream: deliverables/v2d (build 07/10: TSM + Traj da sua). Firmware traj_demo.elf khong cham TSM.
# + watchdog, da sua trong RTL nhung chua build; firmware traj_demo.elf khong cham vao TSM).
# Doc lai toan bo DDR (mrd -bin, chua thu tren board): dat bien moi truong TRAJ_VERIFY_FULL=1 de bat.
# Run: C:/Vivado/Vivado/2023.2/bin/xsdb.bat scripts/board_run_traj_zcu106.tcl

set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set BIT  [file join $ROOT deliverables v2d system_wrapper_v2d.bit]
set ELF  [file join $ROOT vitis_ws_v2d traj_demo traj_demo.elf]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
set PAY  [file join $ROOT sw payloads v2]
set MAN  [file join $PAY ddr_preload_v2.tsv]
set BANK [file join $ROOT sw board demo_bank.bin]

set FULLV [expr {[info exists ::env(TRAJ_VERIFY_FULL)] && $::env(TRAJ_VERIFY_FULL)}]
proc fail {msg} {
  puts "ERROR: $msg"
  exit 1
}

proc first_word_le {path} {
  set fh [open $path rb]
  set bytes [read $fh 4]
  close $fh
  if {[string length $bytes] != 4} { return "" }
  binary scan $bytes cucucucu b0 b1 b2 b3
  return [expr {($b3 << 24) | ($b2 << 16) | ($b1 << 8) | $b0}]
}

foreach f [list $BIT $ELF $PSU $MAN $BANK] {
  if {![file exists $f]} { fail "required file missing: $f" }
}
# (khong kiem tra do moi bitstream: ban nay co chu dich dung bitstream cu, KHONG chay TSM)
source [file join $ROOT scripts board_verify_ddr.tcl]

# Parse manifest and verify exact byte counts and non-overlapping DDR regions.
set entries {}
set fh [open $MAN r]
set line_no 0
while {[gets $fh line] >= 0} {
  incr line_no
  set line [string trim $line]
  if {$line eq "" || [string match "#*" $line]} { continue }
  set fields [split $line "\t"]
  if {[llength $fields] != 3} {
    close $fh
    fail "manifest line $line_no must contain filename, address and size"
  }
  lassign $fields name addr size
  set payload [file join $PAY $name]
  if {![file exists $payload]} { close $fh; fail "payload missing: $payload" }
  if {[file size $payload] != $size} {
    close $fh
    fail "$name size [file size $payload] != manifest size $size"
  }
  lappend entries [list [expr {$addr}] $payload $size]
}
close $fh
if {![llength $entries]} { fail "manifest contains no payloads" }
set sorted [lsort -integer -index 0 $entries]
set prev_end 0
foreach e $sorted {
  lassign $e addr payload size
  if {$addr < $prev_end} { fail "overlapping DDR payload at $payload" }
  set prev_end [expr {$addr + $size}]
}
puts "Preflight OK: [llength $entries] model payloads, demo bank [file size $BANK] bytes"
puts "Bitstream: $BIT ([file size $BIT] bytes)"
puts "R5 ELF:    $ELF ([file size $ELF] bytes)"

if {[catch {connect} err]} { fail "JTAG connect failed: $err" }
after 2000
puts "JTAG targets: [targets]"
set psu_target [targets -filter {name =~ "*PSU*"}]
if {[string trim $psu_target] eq ""} {
  fail "PSU JTAG target unavailable after scan; check power, SW6 JTAG boot and cable"
}
targets -set -nocase -filter {name =~ "*PSU*"}

puts "--- system reset and ZCU106 PS/DDR initialization"
rst -system
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
source $PSU
if {[catch {psu_init} err]} { fail "ZCU106 psu_init failed: $err" }
after 1000

puts "--- program existing PL bitstream"
if {[catch {fpga -file $BIT} err]} { fail "FPGA programming failed: $err" }
after 500

# Enable PS access to PL AXI after configuration. Keep PL reset asserted until
# the R5 ELF and all DDR payloads have been installed.
targets -set -nocase -filter {name =~ "*PSU*"}
mwr 0xFFCA0038 0x1FF
after 200

puts "--- load and halt R5 application"
set r5_target [targets -filter {name =~ "*R5*#0*"}]
if {[string trim $r5_target] eq ""} { fail "Cortex-R5 #0 JTAG target unavailable" }
targets -set -nocase -filter {name =~ "*R5*#0*"}
rst -processor
if {[catch {dow $ELF} err]} { fail "R5 ELF download failed: $err" }

puts "--- preload model payloads and verify DDR readback"
targets -set -nocase -filter {name =~ "*PSU*"}
set n 0
foreach e $entries {
  lassign $e addr payload size
  incr n
  set expected [first_word_le $payload]
  puts [format {  [%02d/%02d] %s -> 0x%08X (%d bytes)} $n [llength $entries] [file tail $payload] $addr $size]
  if {[catch {dow -data $payload [format 0x%08X $addr]} err]} {
    fail "DDR write failed for [file tail $payload] at [format 0x%08X $addr]: $err"
  }
  if {[catch {set got [mrd -force -value [format 0x%08X $addr] 1]} err]} {
    fail "DDR readback failed for [file tail $payload]: $err"
  }
  set got [expr {[lindex $got 0] & 0xFFFFFFFF}]
  if {$got != $expected} {
    fail [format "DDR mismatch for %s: wrote 0x%08X, read 0x%08X" [file tail $payload] $expected $got]
  }
  if {$FULLV && [catch {board_verify_ddr_binary $payload $addr $size} err]} { fail $err }
}
set bank_expected [first_word_le $BANK]
if {[catch {dow -data $BANK 0x60000000} err]} { fail "demo-bank DDR write failed: $err" }
if {[catch {set bank_got [mrd -force -value 0x60000000 1]} err]} { fail "demo-bank DDR readback failed: $err" }
set bank_got [expr {[lindex $bank_got 0] & 0xFFFFFFFF}]
if {$bank_got != $bank_expected} {
  fail [format "demo-bank mismatch: wrote 0x%08X, read 0x%08X" $bank_expected $bank_got]
}
if {$FULLV && [catch {board_verify_ddr_binary $BANK 0x60000000 [file size $BANK]} err]} { fail $err }
puts "DDR FULL readback OK for all model payloads and demo bank."

puts "--- remove PS-PL isolation and release PL reset"
targets -set -nocase -filter {name =~ "*PSU*"}
if {[catch {psu_ps_pl_isolation_removal} err]} { fail "PS-PL isolation removal failed: $err" }
if {[catch {psu_ps_pl_reset_config} err]} { fail "PL reset release failed: $err" }
after 500
if {[catch {set status [mrd -force -value 0xA0000004 1]} err]} {
  fail "cannot read Traj STATUS at 0xA0000004: $err"
}
set status [expr {[lindex $status 0] & 0xFFFFFFFF}]
puts [format "Traj STATUS = 0x%08X" $status]
if {$status == 0xFFFFFFFF || ($status & 0x500) != 0x500} {
  fail "Traj STATUS bits 8 and 10 are not both set; firmware will not be started"
}

puts "--- start Cortex-R5 VLA-Traj demo; watch the UART terminal"
targets -set -nocase -filter {name =~ "*R5*#0*"}
con
puts "R5 is running. Stop with Ctrl+C in XSDB after checking UART output."
