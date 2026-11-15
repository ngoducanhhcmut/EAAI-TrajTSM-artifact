# Claude 12/11/2026: read-only identity/status record of the lab VCU118 after the joint run (no programming).
set hws $::env(VCU118_HW_SERVER)
set out [open [file join [file dirname [info script]] board_logs board_identity_[clock format [clock seconds] -format %Y%m%d_%H%M%S].txt] w]
proc say {m} { global out; puts $m; puts $out $m; flush $out }
say "time: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %z}]  hw_server: $hws"
open_hw_manager
connect_hw_server -url $hws
foreach t [get_hw_targets] { say "target: $t" }
open_hw_target [lindex [get_hw_targets *<JTAG_SERIAL>*] 0]
set d [lindex [get_hw_devices xcvu9p*] 0]
refresh_hw_device -update_hw_probes false $d
refresh_hw_device $d
set rp [report_property -all -return_string $d]
foreach l [split $rp "
"] { if {[regexp -nocase {^(PART|IDCODE_HEX|.*DNA|.*USERCODE|.*DONE|PROGRAM\.FILE|.*SERIAL|.*END_OF_STARTUP|.*BOOT_STATUS )} [string trim $l]]} { say [string trim $l] } }
close_hw_target
disconnect_hw_server
close $out
