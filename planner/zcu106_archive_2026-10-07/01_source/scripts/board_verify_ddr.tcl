# Compare every byte while PL and R5 are still held before the demo starts.
# XSDB mrd -bin returns binary data; the count is in 32-bit words.
proc board_verify_ddr_binary {path base size} {
  if {$size <= 0 || ($size % 4) != 0 || ($base % 4) != 0} {
    error "DDR verification requires a nonempty, word-aligned payload: $path"
  }
  set fh [open $path rb]
  set expected [read $fh]
  close $fh
  if {[string length $expected] != $size} { error "payload size changed: $path" }
  for {set offset 0} {$offset < $size} {incr offset 65536} {
    set bytes [expr {min(65536, $size - $offset)}]
    set address [expr {$base + $offset}]
    set got [mrd -force -bin -size w [format 0x%08X $address] [expr {$bytes / 4}]]
    if {[string length $got] != $bytes} {
      error [format "DDR readback short at 0x%08X: %d/%d bytes" $address [string length $got] $bytes]
    }
    set want [string range $expected $offset [expr {$offset + $bytes - 1}]]
    if {![string equal $got $want]} {
      for {set i 0} {$i < $bytes} {incr i 4} {
        if {![string equal [string range $got $i [expr {$i+3}]] [string range $want $i [expr {$i+3}]]]} {
          binary scan [string range $want $i [expr {$i+3}]] H* exp_hex
          binary scan [string range $got $i [expr {$i+3}]] H* got_hex
          error [format "DDR mismatch %s at 0x%08X (bytes LE): expected %s, got %s" [file tail $path] [expr {$address+$i}] $exp_hex $got_hex]
        }
      }
    }
    set verified [expr {$offset + $bytes}]
    if {($verified % 1048576) == 0 || $verified == $size} {
      puts "    DDR verified [file tail $path]: $verified/$size bytes"
    }
  }
  puts "DDR FULL VERIFY OK [file tail $path] ($size bytes)"
}
