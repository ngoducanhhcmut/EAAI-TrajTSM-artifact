# =============================================================================
# FILE        : run_unit_sim.tcl
# DESCRIPTION : Chạy một unit simulation cụ thể (tiện lợi hơn run_all_sims.tcl)
#               PHẢI chạy SAU vivado_sim.tcl.
#
# CÁCH DÙNG (trong Vivado TCL Console):
#   # Chạy U8 (collision_sat):
#   set UNIT 8 ; source {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/run_unit_sim.tcl}
#
#   # Chạy system sim (sim_1):
#   set UNIT sys ; source {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/run_unit_sim.tcl}
#
# HOẶC dùng lệnh trực tiếp trong TCL Console:
#   current_fileset -simset [get_filesets sim_u8]
#   launch_simulation
#   run -all
# =============================================================================

set SIM_DIR  {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim}

# Đọc biến UNIT từ caller (mặc định = sys nếu không đặt)
if {![info exists UNIT]} { set UNIT sys }

# Xác định simset name
if {$UNIT eq "sys" || $UNIT eq "1" || $UNIT eq "system"} {
    set simset_name "sim_1"
    set display     "System: tb_hmao_soc"
} else {
    set simset_name "sim_u${UNIT}"
    set display     "Unit U${UNIT}"
}

puts "=== \[HMAO\] Chạy $display ($simset_name) ==="

# Kiểm tra project đã mở
if {[catch {current_project} proj]} {
    error "Chưa mở project! Hãy source vivado_sim.tcl trước."
}

# Copy imem_fw.hex nếu là system sim
if {$simset_name eq "sim_1"} {
    set PROJ_DIR  "$SIM_DIR/vivado_proj"
    set PROJ_NAME "hmao_sim"
    set xsim_dir  "$PROJ_DIR/${PROJ_NAME}.sim/sim_1/behav/xsim"
    file mkdir $xsim_dir
    file copy -force "$SIM_DIR/imem_fw.hex" "$xsim_dir/imem_fw.hex"
    puts "  imem_fw.hex sẵn sàng"
}

# Chạy
current_fileset -simset [get_filesets $simset_name]
launch_simulation
run -all

puts "=== Xong. Xem waveform trong Vivado hoặc close_sim để đóng. ==="
puts "  Để đóng: close_sim"
puts "  Để xem thêm:  run 1us  (thêm 1us)  hoặc  run -all"
