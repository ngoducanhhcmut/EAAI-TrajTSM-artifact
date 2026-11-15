# =============================================================================
# board_test_ddr_deep.tcl — kiem tra DDR PS ky hon (qua JTAG, khong can bitstream).
#   set PSU_INIT=<psu_init.tcl>   (mac dinh: deliverables/v2d/psu_init_v2d_components.tcl)
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_test_ddr_deep.tcl
# 1. Trang thai DDRC/PHY sau psu_init (training).
# 2. Trung lap dia chi (aliasing): ghi ma rieng o 0x10,0x20,...,0x4000_0000 roi doc lai — sai so hang/cot/bank
#    se lam cac dia chi de len nhau; in ra bit dia chi bi "nuot".
# 3. Du lieu: 256 word/vung (theo dia chi, dao bit, di bo bit) o nhieu vung; thong ke loi theo lan byte va bit.
# Doc treo (AP timeout) -> dung, can tat/bat nguon board.
# =============================================================================
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
if {[info exists ::env(PSU_INIT)] && $::env(PSU_INIT) ne ""} { set PSU $::env(PSU_INIT) }
puts "psu_init dung: $PSU"
connect
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
rst -system
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
source $PSU
if {[catch {psu_init} e]} { puts "psu_init LOI: $e"; exit 1 }
after 500
proc rd1 {a} { return [lindex [mrd -force -value $a 1] 0] }
set stat [rd1 0xFD070004]; set pgsr0 [rd1 0xFD080030]
puts [format "DDRC STAT=0x%08X (che do %d)  PHY PGSR0=0x%08X  loi training: %s" $stat [expr {$stat & 7}] $pgsr0 \
  [expr {($pgsr0 & 0x7FFC0000) ? "CO" : "khong"}]]

# ---------------------------------------------------------------- 2. aliasing
puts "\n=== TRUNG LAP DIA CHI ==="
set addrs {0x0}
for {set b 4} {$b <= 30} {incr b} { lappend addrs [expr {1 << $b}] }
set ok 1
foreach a $addrs {
  if {[catch {mwr -force $a [expr {0xA1000000 | ([lsearch $addrs $a] << 8) | 0x5}]} e]} { puts "GHI 0x[format %08X $a] LOI: $e"; set ok 0; break }
}
set alias {}
if {$ok} {
  foreach a $addrs {
    set exp [expr {0xA1000000 | ([lsearch $addrs $a] << 8) | 0x5}]
    if {[catch {set r [rd1 $a]} e]} { puts "DOC 0x[format %08X $a] TREO: $e"; set ok 0; break }
    if {$r != $exp} {
      set who [expr {($r >> 8) & 0xFF}]
      if {($r & 0xFF0000FF) == 0xA1000005 && $who < [llength $addrs]} {
        lappend alias [format "0x%08X bi ghi de boi 0x%08X" $a [lindex $addrs $who]]
      } else { lappend alias [format "0x%08X doc 0x%08X (mong 0x%08X)" $a $r $exp] }
    }
  }
  if {[llength $alias]} { puts "CO TRUNG LAP/SAI:"; foreach x $alias { puts "  $x" } } else { puts "Khong trung lap: 28 dia chi luy thua 2 tu 0x10 toi 0x4000_0000 doc dung" }
}

# ---------------------------------------------------------------- 3. du lieu
puts "\n=== DU LIEU (256 word / vung) ==="
set lane_err {0 0 0 0}; set bit_err [lrepeat 32 0]; set tot 0; set bad 0
foreach base {0x00100000 0x01000000 0x10000000 0x40000000 0x60000000 0x70300000 0x7E000000} {
  if {!$ok} break
  foreach pat {addr inv walk} {
    set vals {}
    for {set i 0} {$i < 256} {incr i} {
      set a [expr {$base + 4*$i}]
      switch $pat {
        addr { lappend vals [expr {$a & 0xFFFFFFFF}] }
        inv  { lappend vals [expr {(~$a) & 0xFFFFFFFF}] }
        walk { lappend vals [expr {(1 << ($i % 32)) ^ (($i & 32) ? 0xFFFFFFFF : 0)}] }
      }
    }
    if {[catch {mwr -force $base $vals} e]} { puts "GHI khoi 0x[format %08X $base] LOI: $e"; set ok 0; break }
    if {[catch {set got [mrd -force -value $base 256]} e]} { puts "DOC khoi 0x[format %08X $base] TREO: $e"; set ok 0; break }
    set nb 0
    for {set i 0} {$i < 256} {incr i} {
      incr tot
      set x [expr {([lindex $vals $i] ^ [lindex $got $i]) & 0xFFFFFFFF}]
      if {$x} {
        incr bad; incr nb
        for {set k 0} {$k < 4} {incr k} { if {($x >> (8*$k)) & 0xFF} { lset lane_err $k [expr {[lindex $lane_err $k] + 1}] } }
        for {set k 0} {$k < 32} {incr k} { if {($x >> $k) & 1} { lset bit_err $k [expr {[lindex $bit_err $k] + 1}] } }
        if {$nb <= 2} { puts [format "  0x%08X (%s, word %d, offset 0x%X): ghi 0x%08X doc 0x%08X" [expr {$base+4*$i}] $pat $i [expr {(4*$i) & 0x1F}] [lindex $vals $i] [lindex $got $i]] }
      }
    }
    puts [format "vung 0x%08X mau %-4s: %3d/256 sai" $base $pat $nb]
  }
}
puts "\nTong: $bad/$tot word sai"
puts "Loi theo lan byte (trong word 32 bit) [0..3]: $lane_err"
puts "Loi theo bit [0..31]: $bit_err"
puts [expr {$ok && $bad == 0 && ![llength $alias] ? "==== DDR: DAT ====" : "==== DDR: CO LOI ===="}]
