# =============================================================================
# FILE        : vivado_sim.tcl
# PROJECT     : HMAO Engine
# DESCRIPTION : Vivado project setup + system-level simulation (tb_hmao_soc)
#               Creates project với đầy đủ RTL + TB, cấu hình tất cả sim sets.
#
# CÁCH DÙNG:
#   Cách 1 – Batch mode (không cần mở GUI):
#     vivado -mode batch -source C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/vivado_sim.tcl
#
#   Cách 2 – Trong Vivado TCL Console (đã mở Vivado):
#     source {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/vivado_sim.tcl}
#
#   Cách 3 – Tools → Run Tcl Script... → chọn file này
#
# SAU KHI CHẠY:
#   - Project tạo tại: sim/vivado_proj/
#   - System sim:  Flow Navigator → Simulation → Run Simulation → sim_1
#   - Unit sims:   Simulation Settings → Simulation Set → chọn sim_uXX → Run
#
# LƯU Ý PHẦN:
#   Đổi biến PART thành part Vivado bạn đã cài (dùng lệnh: get_parts)
#   Với simulation-only, bất kỳ Xilinx part nào cũng được.
# =============================================================================

# ── CẤU HÌNH ĐƯỜNG DẪN ──────────────────────────────────────────────────────
set HMAO_DIR  {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO}
set RISCV_DIR "$HMAO_DIR/RISCV-RV32IM-Processor-main/sources_1/new"
set SIM_DIR   "$HMAO_DIR/sim"
set TB_DIR    "$HMAO_DIR/tb"
set PROJ_DIR  "$SIM_DIR/vivado_proj"
set PROJ_NAME {hmao_sim}

# Auto-detect part: ưu tiên Versal HX, fallback KintexUP, Zynq, rồi lấy part đầu tiên có sẵn
# (Simulation không yêu cầu đúng part phần cứng)
if {[llength [get_parts xcvh1782-vsva3340-2MP-e-S]] > 0} {
    set PART {xcvh1782-vsva3340-2MP-e-S}
} elseif {[llength [get_parts xcku9p-ffvb676-2-i]] > 0} {
    set PART {xcku9p-ffvb676-2-i}
} elseif {[llength [get_parts xc7z020clg484-1]] > 0} {
    set PART {xc7z020clg484-1}
} else {
    set PART [lindex [get_parts] 0]
}
puts "  Part được chọn: $PART"

# =============================================================================
# BƯỚC 1: TẠO PROJECT
# =============================================================================
puts "=== \[HMAO\] Tạo Vivado project: $PROJ_NAME ==="
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

set_property simulator_language  {Mixed}           [current_project]
set_property target_language     {Verilog}          [current_project]
set_property default_lib         {xil_defaultlib}   [current_project]

# Bật SystemVerilog assertion support
set_property -name {xsim.elaborate.xelab.more_options} \
             -value {-sv_root .} \
             -objects [get_filesets sim_1]

# =============================================================================
# BƯỚC 2: THÊM DESIGN SOURCES (RTL)
# =============================================================================
puts "=== \[HMAO\] Thêm RTL source files ==="

# --- Package + Interfaces (phải compile TRƯỚC các module khác) ---
set pkg_files [list \
    $HMAO_DIR/hmao_pkg.sv \
    $HMAO_DIR/hmao_interfaces.sv \
]

# --- Core HMAO modules ---
set hmao_files [list \
    $HMAO_DIR/hmao_fsm.sv \
    $HMAO_DIR/hmao_preproc.sv \
    $HMAO_DIR/hmao_zonotope_gen.sv \
    $HMAO_DIR/hmao_admm_solver.sv \
    $HMAO_DIR/hmao_collision_sat.sv \
    $HMAO_DIR/hmao_adaptive_margin.sv \
    $HMAO_DIR/hmao_axi_arbiter.sv \
    $HMAO_DIR/hmao_engine_top.sv \
    $HMAO_DIR/hmao_safety_modules.sv \
    $HMAO_DIR/riscv_dcls_wrapper.sv \
    $HMAO_DIR/hmao_soc_top.sv \
]

# --- RISCV processor (Verilog-2001, tất cả .v trong thư mục) ---
# Bao gồm cả top_dcls.v và hmao_data_memory.v (custom)
# top.v / data_memory.v không được instantiate nên không ảnh hưởng
# Windows: use [glob -nocomplain ...] để tránh lỗi khi không có file
set riscv_files [glob -nocomplain [file join $RISCV_DIR "*.v"]]
if {[llength $riscv_files] == 0} {
    puts "  WARNING: No RISCV .v files found at $RISCV_DIR — skipping RISCV core"
}

# Thêm vào fileset sources_1
add_files -norecurse -fileset [get_filesets sources_1] $pkg_files
add_files -norecurse -fileset [get_filesets sources_1] $hmao_files
if {[llength $riscv_files] > 0} {
    add_files -norecurse -fileset [get_filesets sources_1] $riscv_files
}

# Đánh dấu tất cả .sv là SystemVerilog
set_property file_type {SystemVerilog} \
    [get_files -of_objects [get_filesets sources_1] -filter {FILE_EXT == .sv}]

# Đặt compile order thủ công: pkg → interfaces → phần còn lại
set_property source_mgmt_mode DisplayOnly [current_project]
reorder_files -fileset sources_1 -before [get_files $HMAO_DIR/hmao_fsm.sv] \
    [list $HMAO_DIR/hmao_pkg.sv $HMAO_DIR/hmao_interfaces.sv]

puts "  RTL files: [llength [get_files -of_objects [get_filesets sources_1]]] files"

# =============================================================================
# BƯỚC 3: SIM SET SYSTEM-LEVEL → sim_1 (tb_hmao_soc)
# =============================================================================
puts "=== \[HMAO\] Cấu hình sim_1: tb_hmao_soc (System-level, TC001-TC004) ==="

add_files -fileset sim_1 -norecurse $TB_DIR/tb_hmao_soc.sv
set_property file_type {SystemVerilog} \
    [get_files -fileset sim_1 $TB_DIR/tb_hmao_soc.sv]

set_property top         {tb_hmao_soc}    [get_filesets sim_1]
set_property top_lib     {xil_defaultlib} [get_filesets sim_1]

# Chạy đến khi $finish (không giới hạn thời gian)
set_property -name {xsim.simulate.runtime}          -value {0}     -objects [get_filesets sim_1]
# Bắt tất cả signals vào waveform
set_property -name {xsim.simulate.log_all_signals}  -value {true}  -objects [get_filesets sim_1]
# Thêm define SIMULATION để TB biết đang chạy sim
set_property -name {xsim.compile.xvlog.more_options} \
             -value {-d SIMULATION -d XSIM} -objects [get_filesets sim_1]
# Tự động mở waveform sau khi elaborate
set_property -name {xsim.simulate.wdb} -value {} -objects [get_filesets sim_1]

# =============================================================================
# BƯỚC 4: SIM SETS CHO UNIT TESTBENCHES (sim_u1 → sim_u14)
# =============================================================================
puts "=== \[HMAO\] Tạo unit simulation sets ==="

# Hàm helper tạo sim set cho một unit TB
proc create_unit_simset {simset_name top_module tb_file} {
    global TB_DIR

    create_fileset -simset $simset_name

    add_files -fileset $simset_name -norecurse $TB_DIR/$tb_file
    set_property file_type {SystemVerilog} \
        [get_files -fileset $simset_name $TB_DIR/$tb_file]

    set_property top         $top_module     [get_filesets $simset_name]
    set_property top_lib     {xil_defaultlib} [get_filesets $simset_name]

    # Chạy đến $finish
    set_property -name {xsim.simulate.runtime} \
                 -value {0} -objects [get_filesets $simset_name]
    set_property -name {xsim.simulate.log_all_signals} \
                 -value {true} -objects [get_filesets $simset_name]
    set_property -name {xsim.compile.xvlog.more_options} \
                 -value {-d SIMULATION -d XSIM} -objects [get_filesets $simset_name]

    puts "  Created: $simset_name → $top_module"
}

# U1–U14: tương ứng với lint_units.sh
create_unit_simset sim_u1  {tb_preproc_batch_u1}         {tb_preproc_batch_u1.sv}
create_unit_simset sim_u2  {tb_preproc_batch_u2}         {tb_preproc_batch_u2.sv}
create_unit_simset sim_u3  {tb_hmao_adaptive_margin_U3}  {tb_hmao_adaptive_margin_U3.sv}
create_unit_simset sim_u4  {tb_hmao_zonotope_gen_u4}     {tb_hmao_zonotope_gen_u4.sv}
create_unit_simset sim_u5  {tb_hmao_zonotope_gen_u5}     {tb_hmao_zonotope_gen_u5.sv}
create_unit_simset sim_u6  {tb_hmao_admm_u6}             {tb_hmao_admm_u6.sv}
create_unit_simset sim_u7  {tb_hmao_admm_u7}             {tb_hmao_admm_u7.sv}
create_unit_simset sim_u8  {tb_hmao_collision_sat_u8}    {tb_hmao_collision_sat_u8.sv}
create_unit_simset sim_u9  {tb_hmao_collision_sat_u9}    {tb_hmao_collision_sat_u9.sv}
create_unit_simset sim_u10 {tb_u10_hmao_fsm}             {tb_u10_hmao_fsm.sv}
create_unit_simset sim_u11 {tb_u11_hmao_fsm}             {tb_u11_hmao_fsm.sv}
create_unit_simset sim_u12 {tb_u12_wdt}                  {tb_u12_wdt.sv}
create_unit_simset sim_u13 {tb_hmao_u13}                 {tb_hmao_u13.sv}
create_unit_simset sim_u14 {tb_hmao_axi_arbiter_u14}     {tb_hmao_axi_arbiter_u14.sv}

# =============================================================================
# BƯỚC 5: XỬ LÝ imem_fw.hex
# File này được đọc bởi instruction_memory.v qua $readmemh("imem_fw.hex", imem)
# xsim chạy trong: <proj>/<proj>.sim/sim_1/behav/xsim/
# Ta tạo sẵn thư mục và copy file vào đó.
# =============================================================================
puts "=== \[HMAO\] Chuẩn bị imem_fw.hex cho xsim ==="

set xsim_behav_dir "$PROJ_DIR/${PROJ_NAME}.sim/sim_1/behav/xsim"
file mkdir $xsim_behav_dir
file copy -force "$SIM_DIR/imem_fw.hex" "$xsim_behav_dir/imem_fw.hex"
puts "  imem_fw.hex → $xsim_behav_dir"

# LƯU Ý: Nếu Vivado xóa thư mục này khi compile lại,
# hãy copy thủ công trước khi Run Simulation:
#   file copy -force {C:/Users/TransformerDA/Downloads/HMAO/sim/imem_fw.hex} \
#             {<proj_dir>/hmao_sim.sim/sim_1/behav/xsim/imem_fw.hex}

# =============================================================================
# BƯỚC 6: HOÀN TẤT
# =============================================================================
puts ""
puts "╔══════════════════════════════════════════════════════════════════╗"
puts "║           HMAO Vivado Project Setup HOÀN TẤT                   ║"
puts "╠══════════════════════════════════════════════════════════════════╣"
puts "║  Project:    $PROJ_DIR"
puts "║  Part:       $PART"
puts "╠══════════════════════════════════════════════════════════════════╣"
puts "║  SYSTEM SIM (sim_1) → tb_hmao_soc                              ║"
puts "║    TC001: Safe trajectory  → expect GRANT                      ║"
puts "║    TC002: Collision        → expect VETO (FNR=0%)              ║"
puts "║    TC003: Poor GPS quality → conservative margin               ║"
puts "║    TC004: CRC mismatch     → VETO + fault flag                 ║"
puts "╠══════════════════════════════════════════════════════════════════╣"
puts "║  UNIT SIMS: sim_u1 ... sim_u14                                 ║"
puts "╠══════════════════════════════════════════════════════════════════╣"
puts "║  CHẠY SYSTEM SIM:                                              ║"
puts "║    launch_simulation                     ;# trong GUI           ║"
puts "║    source sim/run_all_sims.tcl           ;# batch mode          ║"
puts "║                                                                 ║"
puts "║  CHẠY UNIT SIM CỤ THỂ (ví dụ U8):                             ║"
puts "║    current_fileset -simset \[get_filesets sim_u8\]"
puts "║    launch_simulation                                            ║"
puts "╚══════════════════════════════════════════════════════════════════╝"
puts ""
puts "  → Tiếp theo: source {$SIM_DIR/run_all_sims.tcl}    (batch)"
puts "  → Hoặc: Flow Navigator → Simulation → Run Simulation (GUI)"
