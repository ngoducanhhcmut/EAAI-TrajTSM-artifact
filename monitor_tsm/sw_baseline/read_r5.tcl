# Claude 08/11: read the R5F result struct left in OCM by the finished run (lmap is missing in xsdb Tcl)
set HERE [file normalize [file dirname [info script]]]
set LOGF [file join $HERE results "cpu_r5_read_[clock format [clock seconds] -format %Y%m%d_%H%M%S].log"]
set f [open $LOGF w]
connect; after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
set words [mrd -force -value 0xFFFD0000 37]
set l {}; foreach w $words { lappend l [format 0x%08X $w] }
puts $f "CORE R5F wall_ms=0 words=[join $l ,]"
close $f
