# =============================================================================
# board_test_ddr.tcl — kiem tra DDR phia PS cua board qua JTAG (khong can bitstream, khong can firmware).
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat scripts\board_test_ddr.tcl
# Buoc 1: rst -system + psu_init (ZCU106) -> doc thanh ghi trang thai bo dieu khien DDR va PHY (bus APB,
#         khong cham bo nho): che do hoat dong DDRC + co hoan tat / co loi cua qua trinh training.
# Buoc 2: ghi roi doc lai tung word o nhieu vung DDR; dung ngay khi doc bi treo (AP timeout).
# Sau khi chay: neu buoc 2 bi treo thi TAT/BAT lai nguon board truoc khi lam viec khac.
# =============================================================================
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
# 07/10: chon psu_init khac bang bien moi truong PSU_INIT (vd. cau hinh DDR "Components" x16 cua project goc)
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
puts "psu_init: chay xong (khong bao loi)"
after 500

proc rd {a} { return [lindex [mrd -force -value $a 1] 0] }
puts "\n=== BUOC 1: thanh ghi trang thai DDR (DDRC 0xFD07_xxxx, DDR PHY 0xFD08_xxxx) ==="
set stat  [rd 0xFD070004]
set pgsr0 [rd 0xFD080030]
set mode  [expr {$stat & 0x7}]
set mname [dict get {0 "Khoi tao (chua san sang)" 1 "Binh thuong (Normal)" 2 "Power-down" 3 "Self-refresh"} [expr {$mode & 3}]]
puts [format "DDRC STAT   (0xFD070004) = 0x%08X -> che do hoat dong = %d (%s)" $stat $mode $mname]
puts [format "PHY  PGSR0  (0xFD080030) = 0x%08X" $pgsr0]
# Bo cuc PGSR0 (DDR PHY, Zynq UltraScale+): 0..15 co hoan tat, 18..30 co loi, 31 APLOCK (PLL khoa)
set done_names {0 IDONE 1 PLDONE 2 DCDONE 3 ZCDONE 4 DIDONE 5 WLDONE 6 QSGDONE 7 WLADONE 8 RDDONE 9 WDDONE 10 REDONE 11 WEDONE 12 CADONE 13 SRDDONE 14 VDONE 15 DQS2DQDONE}
set err_names  {18 DQS2DQERR 19 VERR 20 ZCERR 21 WLERR 22 QSGERR 23 WLAERR 24 RDERR 25 WDERR 26 REERR 27 WEERR 28 CAERR 30 SRDERR}
set d {}; foreach {b n} $done_names { if {($pgsr0 >> $b) & 1} { lappend d $n } }
set er {}; foreach {b n} $err_names { if {($pgsr0 >> $b) & 1} { lappend er $n } }
puts "  buoc training da xong : [expr {[llength $d] ? [join $d { }] : {(khong co)}}]"
puts "  co LOI training       : [expr {[llength $er] ? [join $er { }] : {(khong co)}}]"
if {$mode != 1 || [llength $er]} {
  set m_txt [expr {$mode != 1 ? "DDRC KHONG o che do binh thuong" : "DDRC o che do binh thuong"}]
  set e_txt [expr {[llength $er] ? "BAO LOI: [join $er { }]" : "khong bao loi"}]
  puts "=> KET LUAN BUOC 1: $m_txt; training $e_txt."
  puts "   PLL cua PHY: [expr {($pgsr0 >> 31) & 1 ? {da khoa (APLOCK=1)} : {CHUA khoa}}]"
} else {
  puts "=> KET LUAN BUOC 1: bo dieu khien bao DDR san sang, training khong bao loi."
}

puts "\n=== BUOC 2: ghi roi doc lai DDR (dung ngay khi doc bi treo) ==="
set n_ok 0; set n_bad 0
foreach base {0x00100000 0x10000000 0x40000000 0x70300000} {
  for {set i 0} {$i < 4} {incr i} {
    set a [expr {$base + 4*$i}]
    set v [expr {(0x5A000000 | ($i << 20) | (($base >> 20) & 0xFFFF)) & 0xFFFFFFFF}]
    if {[catch {mwr -force $a $v} e]} { puts [format "  GHI 0x%08X: LOI (%s)" $a $e]; set stop 1; break }
    if {[catch {set r [rd $a]} e]} { puts [format "  DOC 0x%08X: TREO / LOI (%s)" $a $e]; set stop 1; break }
    if {$r == $v} { incr n_ok } else { incr n_bad; puts [format "  0x%08X: ghi 0x%08X, doc lai 0x%08X  SAI" $a $v $r] }
  }
  if {[info exists stop]} break
}
puts "Ket qua: dung $n_ok word, sai $n_bad word[expr {[info exists stop] ? {, va bus bi treo khi truy cap DDR} : {}}]"
if {[info exists stop] || $n_bad} {
  puts "=> KET LUAN BUOC 2: DDR KHONG doc/ghi dung. (Nho tat/bat lai nguon board.)"
} else {
  puts "=> KET LUAN BUOC 2: DDR doc/ghi dung o cac dia chi da thu."
}
