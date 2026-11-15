# =============================================================================
# board_ddr_phy_dump.tcl — doc thanh ghi tu kiem cua DDR controller/PHY sau psu_init, THEO TUNG LAN BYTE.
# Chi doc thanh ghi cau hinh (APB 0xFD07_xxxx / 0xFD08_xxxx), KHONG doc bo nho DDR -> khong treo board.
#   set PSU_INIT=<psu_init.tcl>
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_ddr_phy_dump.tcl
# Thanh ghi (Zynq UltraScale+ TRM, DDR_PHY): PGSR0 0xFD080030 (tong hop), DXn (n=0..8) co so 0xFD080700+n*0x100:
#   DXnGCR0 +0x00 (bit0 DXEN: lan duoc bat), DXnGSR0 +0xE0, DXnGSR1 +0xE4, DXnGSR2 +0xE8, DXnGSR3 +0xEC
#   (GSR2/GSR3 chua co loi training cua lan: RD/WD bit-deskew, read/write eye, VREF host/DRAM...).
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
set mstr [rd1 0xFD070000]
set dev [dict get {0 x4 1 x8 2 x16 3 x32} [expr {($mstr >> 30) & 3}]]
puts [format "DDRC MSTR  0xFD070000 = 0x%08X  (DDR4=%d, chip %s, rank bat=0x%X)" $mstr [expr {($mstr >> 4) & 1}] $dev [expr {($mstr >> 24) & 3}]]
puts [format "DDRC STAT  0xFD070004 = 0x%08X" [rd1 0xFD070004]]
puts [format "PHY  PGSR0 0xFD080030 = 0x%08X" [rd1 0xFD080030]]
puts [format "PHY  PGSR1 0xFD080034 = 0x%08X" [rd1 0xFD080034]]
puts "lan | DXEN | GSR0       GSR1       GSR2       GSR3"
for {set n 0} {$n <= 8} {incr n} {
  set b [expr {0xFD080700 + $n * 0x100}]
  set gcr0 [rd1 $b]
  puts [format " %d  |  %d   | 0x%08X 0x%08X 0x%08X 0x%08X" $n [expr {$gcr0 & 1}] \
    [rd1 [expr {$b + 0xE0}]] [rd1 [expr {$b + 0xE4}]] [rd1 [expr {$b + 0xE8}]] [rd1 [expr {$b + 0xEC}]]]
}
puts "DUMP_XONG"
