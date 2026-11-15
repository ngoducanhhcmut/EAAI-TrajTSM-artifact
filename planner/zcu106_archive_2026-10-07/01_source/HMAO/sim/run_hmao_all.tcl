# =============================================================================
# FILE        : run_hmao_all.tcl
# DESCRIPTION : One-shot: tạo Vivado project + chạy tất cả 15 sim sets.
#               Kết hợp vivado_sim.tcl + run_all_sims.tcl thành 1 file.
#
# CÁCH DÙNG:
#   vivado -mode batch -notrace -source scripts/run_hmao_all.tcl
#   (chạy từ thư mục vla_new_arch/)
# =============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]

puts "=========================================================="
puts "  HMAO Engine - Full Sim: Create Project + Run All Tests"
puts "=========================================================="

# Bước 1: Tạo project (kèm tất cả sim sets)
puts "\n--- Bước 1: Tạo Vivado project ---"
source [file join $SCRIPT_DIR vivado_sim.tcl]

# Bước 2: Chạy tất cả simulations
puts "\n--- Bước 2: Chạy tất cả simulations ---"
source [file join $SCRIPT_DIR run_all_sims.tcl]

puts "\nHOÀN TẤT."
