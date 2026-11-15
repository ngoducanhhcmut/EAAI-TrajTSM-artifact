# board_run_tsm_multi_zcu106.tcl — TSM tren 17 ca nuScenes + tiem loi, 3 vong, do tre bang IOU_SCNTRS (bitstream chi-TSM, OCM).
# Bitstream: deliverables/tsm_only (RTL TSM da sua doc AXI + watchdog). Khong co VLA-Traj, khong nap weight.
# Mong doi UART: GPIO1 before start=0x00000000, Decision VETO, Fault=0x00, ~8 ms.
# Requires the board in JTAG boot mode, powered, with JTAG and UART connected.
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set BIT  [file join $ROOT deliverables tsm_only_ocm system_wrapper_tsm_only_ocm.bit]
set ELF  [file join $ROOT vitis_ws_v2d tsm_only tsm_multicase.elf]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
foreach f [list $BIT $ELF $PSU] {
  if {![file exists $f]} { puts "ERROR: required file missing: $f"; exit 1 }
}
proc fail {msg} { puts "ERROR: $msg"; exit 1 }
source [file join $ROOT scripts board_check_bit_freshness.tcl]
if {[catch {board_check_tsm_bit_freshness $ROOT $BIT} err]} { fail $err }
if {[catch {connect} err]} { fail "JTAG connect failed: $err" }
after 2000
puts "JTAG targets: [targets]"
if {[string trim [targets -filter {name =~ "*PSU*"}]] eq ""} {
  fail "PSU JTAG target unavailable; check board power, SW6 JTAG boot and cable"
}
targets -set -nocase -filter {name =~ "*PSU*"}
puts "--- reset and initialize ZCU106 PS/DDR"
rst -system
after 1500
targets -set -nocase -filter {name =~ "*PSU*"}
source $PSU
if {[catch {psu_init} err]} { fail "ZCU106 psu_init failed: $err" }
after 1000
puts "--- program existing PL bitstream"
if {[catch {fpga -file $BIT} err]} { fail "FPGA programming failed: $err" }
after 500
targets -set -nocase -filter {name =~ "*PSU*"}
mwr 0xFFCA0038 0x1FF
after 200
puts "--- load and run one-case R5 firmware"
set r5 [targets -filter {name =~ "*R5*#0*"}]
if {[string trim $r5] eq ""} { fail "Cortex-R5 #0 unavailable" }
targets -set -nocase -filter {name =~ "*R5*#0*"}
rst -processor
if {[catch {dow $ELF} err]} { fail "R5 ELF download failed: $err" }
targets -set -nocase -filter {name =~ "*PSU*"}
if {[catch {psu_ps_pl_isolation_removal} err]} { fail "PS-PL isolation removal failed: $err" }
if {[catch {psu_ps_pl_reset_config} err]} { fail "PL reset release failed: $err" }
after 500
targets -set -nocase -filter {name =~ "*R5*#0*"}
con
puts "R5 multi-case TSM running; read the UART terminal at 115200 8N1."
