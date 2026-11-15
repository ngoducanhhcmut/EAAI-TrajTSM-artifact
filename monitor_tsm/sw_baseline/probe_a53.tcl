# Claude 08/11: diagnose the A53 run (state, PC, exception level, result struct) after 20 s
set HERE [file normalize [file dirname [info script]]]
set ROOT [file normalize [file join $HERE .. .. ..]]
set f [open [file join $HERE results probe_a53.txt] w]
connect; after 2000
targets -set -nocase -filter {name =~ "*PSU*"}
rst -system; after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
source [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
psu_init; after 500
mwr -force 0xFFFC0090 0
for {set k 0} {$k < 37} {incr k} { mwr -force [expr {0xFFFC0000 + 4*$k}] 0 }
set r0 [mrd -force -value 0xFD1A0104 1]
mwr -force 0xFD1A0104 [expr {$r0 & ~0x501}]
puts $f [format "RST_FPD_APU 0x%08X -> 0x%08X" $r0 [mrd -force -value 0xFD1A0104 1]]
targets -set -nocase -filter {name =~ "*A53*#0*"}
rst -processor; after 300
puts $f "dow: [catch {dow [file join $HERE tsmx_a53.elf]} e] $e"
con; after 90000
catch {stop}; after 300
puts $f "state: [state]"
catch {puts $f [rrd pc]}
catch {puts $f [rrd cpsr]}
catch {puts $f [bt]} 
targets -set -nocase -filter {name =~ "*PSU*"}
puts $f "out: [mrd -force -value 0xFFFC0000 37]"
close $f
