# =============================================================================
# run_u8_u9.tcl — Chạy U8 + U9 (collision_sat). Robust với mọi trạng thái project.
# source {C:/Users/TransformerDA/Downloads/HMAO/sim/run_u8_u9.tcl}
# =============================================================================

set HMAO_DIR {C:/Users/TransformerDA/Downloads/HMAO}
set TB_DIR   "$HMAO_DIR/tb"
set PROJ_DIR "$HMAO_DIR/sim/vivado_proj"

# --------------------------------------------------------------------------
# 1. Chọn part
# --------------------------------------------------------------------------
foreach p {xc7z020clg484-1 xc7z010iclg225-1L xc7a35tcpg236-1 xc7k70tfbg484-1} {
    if {[llength [get_parts $p]] > 0} { set PART $p; break }
}
if {![info exists PART]} { set PART [lindex [get_parts] 0] }
puts ">>> Part: $PART"

# --------------------------------------------------------------------------
# 2. Xử lý project: nếu hmao_sim đã mở thì dùng lại, không tạo mới
# --------------------------------------------------------------------------
set cur_proj ""
catch { set cur_proj [current_project] }

if {$cur_proj eq "hmao_sim"} {
    puts ">>> hmao_sim đang mở — dùng lại project hiện tại"
} else {
    # Đóng project đang mở (nếu có), rồi tạo mới
    catch { close_project }
    # Xóa thư mục cũ để tránh conflict
    catch { file delete -force $PROJ_DIR }
    create_project hmao_sim $PROJ_DIR -part $PART
    set_property default_lib         {xil_defaultlib} [current_project]
    set_property simulator_language  {Mixed}           [current_project]
    puts ">>> Project mới tạo tại $PROJ_DIR"
}

# --------------------------------------------------------------------------
# 3a. XÓA các file gây TraverseArray crash khỏi sources_1 (nếu còn từ lần trước)
#     - hmao_interfaces.sv: waypoint_t waypoints[N] = unpacked array of packed struct
#     - hmao_pkg.sv (full): struct typedefs (world_model_object_t 512-bit, zonotope_128b_t
#       128-bit) trigger VlogCompiler::transform TraverseArray crash even with no instances.
#       → Replace with hmao_pkg_csat.sv (only 3 parameters, no typedefs).
# --------------------------------------------------------------------------
set stale_list [list \
    $HMAO_DIR/hmao_interfaces.sv \
    $HMAO_DIR/hmao_pkg.sv \
]
foreach sf $stale_list {
    if {[get_files -quiet $sf] ne {}} {
        remove_files [get_files $sf]
        puts ">>> Removed stale: [file tail $sf]  (TraverseArray trigger)"
    }
}

# --------------------------------------------------------------------------
# 3b. Thêm RTL sạch (4 files cho collision_sat)
#     hmao_pkg_csat.sv = stripped package, chỉ 3 params, KHÔNG có struct/enum typedef
#     hmao_axi_if.sv   = chỉ chứa axi4_ro_if, không có hmao_pipe_if
# --------------------------------------------------------------------------
set rtl_needed [list \
    $HMAO_DIR/sim/hmao_pkg_csat.sv \
    $HMAO_DIR/hmao_axi_if.sv \
    $HMAO_DIR/hmao_collision_sat.sv \
]
foreach f $rtl_needed {
    if {[get_files -quiet $f] eq {}} {
        add_files -norecurse -fileset [get_filesets sources_1] $f
        set_property file_type {SystemVerilog} [get_files $f]
        puts ">>> Added: [file tail $f]"
    } else {
        puts ">>> Already in project: [file tail $f]"
    }
}

# --------------------------------------------------------------------------
# 4. Tạo sim_u8 (xóa nếu đã tồn tại)
#    Trước khi xóa: switch sang sim_u9 để tránh "cannot delete active fileset"
# --------------------------------------------------------------------------
if {[get_filesets -quiet sim_u8] ne {}} {
    puts ">>> Xóa sim_u8 cũ..."
    catch { current_fileset -simset [get_filesets sim_u9] }
    delete_fileset sim_u8
}
create_fileset -simset sim_u8
set f8 $TB_DIR/tb_hmao_collision_sat_u8.sv
add_files -fileset sim_u8 -norecurse $f8
set_property file_type {SystemVerilog}          [get_files -of_objects [get_filesets sim_u8] $f8]
set_property top     {tb_hmao_collision_sat_u8} [get_filesets sim_u8]
set_property top_lib {xil_defaultlib}           [get_filesets sim_u8]
set_property -name {xsim.simulate.runtime}           -value {0}    -objects [get_filesets sim_u8]
set_property -name {xsim.simulate.log_all_signals}   -value {true} -objects [get_filesets sim_u8]
set_property -name {xsim.compile.xvlog.more_options} -value {-d SIMULATION -d XSIM} -objects [get_filesets sim_u8]
# Set sim_u8 làm active → sau đó mới xóa sim_u9 được
current_fileset -simset [get_filesets sim_u8]
puts ">>> sim_u8 ready"

# --------------------------------------------------------------------------
# 5. Tạo sim_u9 (xóa nếu đã tồn tại)
#    sim_u8 đã là active → delete sim_u9 an toàn
# --------------------------------------------------------------------------
if {[get_filesets -quiet sim_u9] ne {}} {
    puts ">>> Xóa sim_u9 cũ..."
    delete_fileset sim_u9
}
create_fileset -simset sim_u9
set f9 $TB_DIR/tb_hmao_collision_sat_u9.sv
add_files -fileset sim_u9 -norecurse $f9
set_property file_type {SystemVerilog}          [get_files -of_objects [get_filesets sim_u9] $f9]
set_property top     {tb_hmao_collision_sat_u9} [get_filesets sim_u9]
set_property top_lib {xil_defaultlib}           [get_filesets sim_u9]
set_property -name {xsim.simulate.runtime}           -value {0}    -objects [get_filesets sim_u9]
set_property -name {xsim.simulate.log_all_signals}   -value {true} -objects [get_filesets sim_u9]
set_property -name {xsim.compile.xvlog.more_options} -value {-d SIMULATION -d XSIM} -objects [get_filesets sim_u9]
puts ">>> sim_u9 ready"

# --------------------------------------------------------------------------
# 5b. XÓA TOÀN BỘ hmao_sim.sim để force clean compile, tránh TraverseArray crash
#
#     ROOT CAUSE của crash: xelab --incr load CẢ OLD compiled .rlx units
#     từ lần compile TRƯỚC (khi zonotopes_in còn là packed-array-of-struct).
#     delete_fileset chỉ xóa metadata Vivado, KHÔNG xóa thư mục sim trên disk.
#     Kết quả: xelab deserialize old .rlx qua boost::binary_iarchive, gọi
#     TraverseArray trên old packed-array-of-struct type → crash.
#
#     Fix: xóa hmao_sim.sim hoàn toàn → mọi compile đều sạch từ đầu.
# --------------------------------------------------------------------------
puts ">>> Xóa hmao_sim.sim để force clean compile (prevent TraverseArray crash)..."
catch { file delete -force "$PROJ_DIR/hmao_sim.sim" }
puts ">>> xsim cache cleared — xvlog sẽ compile sạch, xelab không có old .rlx"

# --------------------------------------------------------------------------
# 6. Chạy U8
# --------------------------------------------------------------------------
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "  CHẠY U8: tb_hmao_collision_sat_u8"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
current_fileset -simset [get_filesets sim_u8]
if {[catch { launch_simulation; run -all; close_sim } e8]} {
    puts "  U8 ERROR: $e8"
} else {
    puts "  U8 DONE"
}

# --------------------------------------------------------------------------
# 7. Chạy U9
# --------------------------------------------------------------------------
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "  CHẠY U9: tb_hmao_collision_sat_u9"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
current_fileset -simset [get_filesets sim_u9]
if {[catch { launch_simulation; run -all; close_sim } e9]} {
    puts "  U9 ERROR: $e9"
} else {
    puts "  U9 DONE"
}

puts ""
puts ">>> Logs:"
puts "    $PROJ_DIR/hmao_sim.sim/sim_u8/behav/xsim/simulate.log"
puts "    $PROJ_DIR/hmao_sim.sim/sim_u9/behav/xsim/simulate.log"
