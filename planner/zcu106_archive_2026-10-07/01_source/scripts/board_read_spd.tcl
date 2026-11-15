# =============================================================================
# board_read_spd.tcl — quet I2C1 cua PS (qua JTAG) tim EEPROM SPD cua thanh RAM DDR4 va doc thong tin RAM.
# Khong can bitstream, khong cham bo nho DDR.
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_read_spd.tcl
# I2C1 (Cadence, 0xFF030000) duoc psu_init ZCU106 noi ra MIO. Thu 2 bo chon kenh TCA9548 (0x74, 0x75), moi kenh 0..7,
# tim thiet bi o 0x50..0x57 (SPD DDR4). Neu thay: doc byte 0..15 (loai module, mat do, to chuc) va ma san pham (page 1).
# =============================================================================
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
if {[info exists ::env(PSU_INIT)] && $::env(PSU_INIT) ne ""} { set PSU $::env(PSU_INIT) }
connect
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
rst -system
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
source $PSU
if {[catch {psu_init} e]} { puts "psu_init LOI: $e"; exit 1 }
after 300

set I2C 0xFF030000
proc w {off v} { global I2C; mwr -force [expr {$I2C + $off}] $v }
proc r {off}   { global I2C; return [lindex [mrd -force -value [expr {$I2C + $off}] 1] 0] }
# CR: div_a=2 [15:14], div_b=14 [13:8], CLR_FIFO bit6, ACKEN bit3, NEA bit2, MS bit1, RW bit0  -> ~100 kHz
set CR_BASE [expr {(2 << 14) | (14 << 8) | (1 << 3) | (1 << 2) | (1 << 1)}]
proc clr_isr {} { w 0x10 [r 0x10] }
proc wait_done {} {
  for {set t 0} {$t < 200} {incr t} {
    set isr [r 0x10]
    if {$isr & 0x4} { clr_isr; return "NACK" }
    if {$isr & 0x1} { clr_isr; return "OK" }
    after 2
  }
  return "TIMEOUT"
}
# ghi danh sach byte toi slave
proc i2c_write {addr bytes} {
  global CR_BASE
  clr_isr
  w 0x00 [expr {$CR_BASE | (1 << 6)}]
  foreach b $bytes { w 0x0C $b }
  w 0x08 $addr
  return [wait_done]
}
# doc n byte (n <= 15)
proc i2c_read {addr n} {
  global CR_BASE
  clr_isr
  w 0x00 [expr {$CR_BASE | (1 << 6) | 1}]
  w 0x14 $n
  w 0x08 $addr
  set st [wait_done]
  if {$st ne "OK"} { return [list $st {}] }
  set out {}
  for {set i 0} {$i < $n} {incr i} { lappend out [expr {[r 0x0C] & 0xFF}] }
  return [list OK $out]
}
puts [format "RST_LPD_IOU2=0x%08X (psu_init da nha reset I2C)" [lindex [mrd -force -value 0xFF5E0238 1] 0]]

puts "=== Quet I2C1: bo chon kenh 0x74/0x75, kenh 0..7, SPD 0x50..0x57 ==="
set found {}
foreach mux {0x74 0x75} {
  set st [i2c_write $mux {0x00}]
  puts [format "bo chon kenh 0x%02X: %s" $mux $st]
  if {$st ne "OK"} continue
  for {set ch 0} {$ch < 8} {incr ch} {
    if {[i2c_write $mux [list [expr {1 << $ch}]]] ne "OK"} continue
    for {set a 0x50} {$a <= 0x57} {incr a} {
      if {[i2c_write $a {0x00}] eq "OK"} {
        lassign [i2c_read $a 15] st2 bytes
        puts [format "  THAY thiet bi 0x%02X o mux 0x%02X kenh %d, byte 0..14: %s" $a $mux $ch $bytes]
        lappend found [list $mux $ch $a $bytes]
      }
    }
  }
  i2c_write $mux {0x00}
}
if {![llength $found]} { puts "KHONG tim thay EEPROM SPD nao (0x50..0x57) sau cac bo chon kenh 0x74/0x75." ; exit 0 }

foreach f $found {
  lassign $f mux ch a b
  if {[llength $b] < 15} continue
  if {[lindex $b 2] != 0x0C} { puts [format "0x%02X (mux 0x%02X kenh %d): byte2=0x%02X — khong phai SPD DDR4" $a $mux $ch [lindex $b 2]]; continue }
  set mtype [dict get {1 RDIMM 2 UDIMM 3 SO-DIMM 4 LRDIMM} [expr {[lindex $b 3] & 0xF}] ]
  set dens  [dict get {0 256Mb 1 512Mb 2 1Gb 3 2Gb 4 4Gb 5 8Gb 6 16Gb 7 32Gb} [expr {[lindex $b 4] & 0xF}]]
  set bg    [expr {1 << (([lindex $b 4] >> 6) & 3)}]
  set rows  [expr {12 + (([lindex $b 5] >> 3) & 7)}]
  set cols  [expr {9 + ([lindex $b 5] & 7)}]
  set org   [lindex $b 12]
  set width [dict get {0 x4 1 x8 2 x16 3 x32} [expr {$org & 7}]]
  set ranks [expr {(($org >> 3) & 7) + 1}]
  set busw  [dict get {0 8 1 16 2 32 3 64} [expr {[lindex $b 13] & 7}]]
  puts [format "SPD DDR4 o 0x%02X (mux 0x%02X kenh %d): module %s | chip %s, %s, %d bank group | %d rank | bus %d bit | hang %d bit, cot %d bit" \
        $a $mux $ch $mtype $width $dens $bg $ranks $busw $rows $cols]
  # ma san pham: page 1 (chon trang bang ghi 0x37), byte 329..348 -> offset 73..92 trong trang 1
  i2c_write $mux [list [expr {1 << $ch}]]
  if {[i2c_write 0x37 {0x00}] eq "OK"} {
    set pn ""
    foreach off {73 88} n {15 5} {
      i2c_write $a [list $off]
      lassign [i2c_read $a $n] st3 pb
      foreach c $pb { if {$c >= 32 && $c < 127} { append pn [format %c $c] } }
    }
    puts "  ma san pham module: '$pn'"
    i2c_write 0x36 {0x00}
  }
}
puts "SPD_XONG"
