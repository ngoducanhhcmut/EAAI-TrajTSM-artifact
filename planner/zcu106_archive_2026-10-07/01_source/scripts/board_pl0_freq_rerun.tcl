# =============================================================================
# board_pl0_freq_rerun.tcl — doi tan so clock PL0 (VLA-Traj + AXI-Lite/GPIO + HP0) roi chay lai demo R5.
# Dung SAU board_run_demo_zcu106.tcl (DDR da co trong so + ngan demo; khong nap lai).
#   set PL0_DIV=<2..63>   -> f(PL0) = IOPLL 1500 MHz / PL0_DIV   (15 = 100 MHz, 10 = 150 MHz)
#   C:\Vivado\Vivado\2023.2\bin\xsdb.bat C:/Users/TransformerDA/Downloads/vla_new_arch/scripts/board_pl0_freq_rerun.tcl
# Trinh tu: dung R5 -> ghi PL0_REF_CTRL (0xFF5E00C0) -> reset PL (Traj nap lai trong so tu DDR) -> kiem STATUS
#           -> nap lai + chay tsm_demo.elf. TSM (PL2 187,5 MHz) va watchdog (PL3) khong doi.
# =============================================================================
set ROOT [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set PSU  [file join $ROOT deliverables zcu106 psu_init_zcu106_ram_x16_8gb.tcl]
set ELF  [file join $ROOT vitis_ws_v2d tsm_demo Debug tsm_demo.elf]
set DIV  [expr {[info exists ::env(PL0_DIV)] ? $::env(PL0_DIV) : 15}]
if {$DIV < 2 || $DIV > 63} { puts "ERROR: PL0_DIV ngoai khoang"; exit 1 }
connect
after 1500
targets -set -nocase -filter {name =~ "*R5*#0*"}
catch {stop}
targets -set -nocase -filter {name =~ "*PSU*"}
source $PSU
set v [expr {0x01010000 | ($DIV << 8)}]
mwr -force 0xFF5E00C0 $v
after 50
puts [format "PL0_REF_CTRL = 0x%08X -> PL0 = %.1f MHz" [lindex [mrd -force -value 0xFF5E00C0 1] 0] [expr {1500.0 / $DIV}]]
if {[catch {psu_ps_pl_reset_config} e]} { puts "ERROR reset PL: $e"; exit 1 }
after 1500
set st [lindex [mrd -force -value 0xA0000004 1] 0]
puts [format "Traj STATUS = 0x%08X" $st]
if {($st & 0x500) != 0x500} { puts "ERROR: Traj khong nap xong trong so o tan so nay"; exit 2 }
targets -set -nocase -filter {name =~ "*R5*#0*"}
rst -processor
dow $ELF
con
puts "R5_RUNNING"
