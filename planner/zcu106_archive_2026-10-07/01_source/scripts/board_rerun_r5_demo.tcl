# board_rerun_r5_demo.tcl — chay LAI firmware demo tren R5 ma khong nap lai bitstream/DDR
# (dung sau board_run_demo_zcu106.tcl, khi PuTTY mo muon). Kiem lai Traj STATUS truoc khi chay.
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set ELF  [file join $ROOT vitis_ws_v2d tsm_demo Debug tsm_demo.elf]
connect
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
set st [lindex [mrd -force -value 0xA0000004 1] 0]
puts [format "Traj STATUS (doc tu thanh ghi PL 0xA000_0004) = 0x%08X" $st]
if {($st & 0x500) != 0x500} { puts "ERROR: Traj chua nap xong trong so -> chay lai board_run_demo_zcu106.tcl"; exit 1 }
targets -set -nocase -filter {name =~ "*R5*#0*"}
catch {stop}
rst -processor
dow $ELF
con
puts "R5 demo chay lai; xem PuTTY COM7."
