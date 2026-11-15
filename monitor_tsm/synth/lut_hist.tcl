# Claude 30/10: histogram of LUT cells by name stem in a post-synth checkpoint.
open_checkpoint [lindex $argv 0]
set h [dict create]
foreach c [get_cells -hier -filter {REF_NAME =~ LUT*}] {
  set n [get_property NAME $c]
  regsub -all {\[[0-9]+\]} $n {} n
  regsub -all {_i_[0-9]+.*$} $n {} n
  regsub -all {[0-9]+$} $n {} n
  dict incr h $n
}
set l {}
dict for {k v} $h { lappend l [list $v $k] }
set fp [open [lindex $argv 1] w]
foreach e [lsort -integer -decreasing -index 0 $l] { puts $fp $e }
close $fp
