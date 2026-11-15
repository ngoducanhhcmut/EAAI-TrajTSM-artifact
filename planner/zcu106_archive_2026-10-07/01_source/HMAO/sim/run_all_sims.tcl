# =============================================================================
# FILE        : run_all_sims.tcl
# PROJECT     : HMAO Engine
# DESCRIPTION : Chạy tất cả simulation sets theo thứ tự và in kết quả tổng hợp.
#               PHẢI chạy SAU vivado_sim.tcl (project đã được tạo).
#
# CÁCH DÙNG:
#   Cách 1 – Batch mode (chạy toàn bộ, không GUI):
#     vivado -mode batch -source C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/vivado_sim.tcl \
#            -source C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/run_all_sims.tcl
#
#   Cách 2 – Trong Vivado TCL Console (sau khi đã source vivado_sim.tcl):
#     source {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim/run_all_sims.tcl}
#
#   Cách 3 – Chỉ chạy system sim:
#     run_sim sim_1  "System: tb_hmao_soc"
#
#   Cách 4 – Chỉ chạy một unit sim cụ thể:
#     run_sim sim_u8 "U8: collision_sat"
# =============================================================================

set SIM_DIR  {C:/Users/TransformerDA/Downloads/vla_new_arch/HMAO/sim}
set PROJ_DIR "$SIM_DIR/vivado_proj"
set PROJ_NAME {hmao_sim}

# Mở project nếu chưa mở (batch mode)
if {[catch {current_project}]} {
    puts "INFO: Mở project $PROJ_DIR/${PROJ_NAME}.xpr"
    open_project "$PROJ_DIR/${PROJ_NAME}.xpr"
}

# =============================================================================
# HELPER: Chạy một simulation set và trả về kết quả PASS/FAIL/UNKNOWN
# =============================================================================
set sim_results {}   ;# danh sách {name result log_snippet}

proc run_sim {simset_name display_name} {
    global PROJ_DIR PROJ_NAME SIM_DIR sim_results

    puts ""
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "  CHẠY: $display_name ($simset_name)"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Kiểm tra sim set tồn tại
    if {[get_filesets -quiet $simset_name] eq {}} {
        puts "  SKIP: sim set '$simset_name' không tồn tại"
        lappend sim_results [list $display_name SKIP ""]
        return
    }

    # Đặt sim set hiện tại
    current_fileset -simset [get_filesets $simset_name]

    # Đảm bảo imem_fw.hex có mặt cho system sim (sim_1)
    if {$simset_name eq "sim_1"} {
        set xsim_dir "$PROJ_DIR/${PROJ_NAME}.sim/sim_1/behav/xsim"
        file mkdir $xsim_dir
        if {![file exists "$xsim_dir/imem_fw.hex"]} {
            file copy -force "$SIM_DIR/imem_fw.hex" "$xsim_dir/imem_fw.hex"
            puts "  INFO: imem_fw.hex copied to xsim dir"
        }
    }

    # Chạy simulation
    set rc [catch {
        launch_simulation
        run -all
        close_sim
    } err_msg]

    # Đọc log để phân tích kết quả
    set sim_subdir [regsub {^sim_} $simset_name {}]
    if {$simset_name eq "sim_1"} {
        set log_file "$PROJ_DIR/${PROJ_NAME}.sim/sim_1/behav/xsim/simulate.log"
    } else {
        set log_file "$PROJ_DIR/${PROJ_NAME}.sim/${simset_name}/behav/xsim/simulate.log"
    }

    set result "UNKNOWN"
    set log_tail ""

    if {$rc != 0} {
        set result "ERROR"
        set log_tail $err_msg
        puts "  ✗ ERROR: $err_msg"
    } elseif {[file exists $log_file]} {
        set fh [open $log_file r]
        set log_content [read $fh]
        close $fh

        # Phân tích kết quả từ $display output của TB
        if {[regexp {FAIL\s*:\s*(\d+)} $log_content -> fail_n] && $fail_n > 0} {
            set result "FAIL"
        } elseif {[regexp {PASS\s*:\s*(\d+)} $log_content -> pass_n] && $pass_n > 0} {
            set result "PASS"
        } elseif {[string match *FATAL* $log_content] || [string match *ERROR* $log_content]} {
            set result "FAIL"
        } elseif {[string match *PASS* $log_content]} {
            set result "PASS"
        }

        # Lấy 10 dòng cuối của log
        set lines [split $log_content "\n"]
        set tail  [lrange $lines end-10 end]
        set log_tail [join $tail "\n"]

        puts "  Log tail:"
        foreach line [lrange $lines end-8 end] {
            puts "    | $line"
        }
    } else {
        puts "  WARN: Không tìm thấy log file: $log_file"
    }

    puts "  → Kết quả: \[${result}\] $display_name"
    lappend sim_results [list $display_name $result $log_tail]
}

# =============================================================================
# CHẠY TẤT CẢ SIMULATIONS
# =============================================================================

# ── System-level simulation ─────────────────────────────────────────────────
run_sim sim_1  "System | tb_hmao_soc (TC001-TC004)"

# ── Unit simulations ─────────────────────────────────────────────────────────
run_sim sim_u1  "U1  | preproc_batch1    (TP_001-TP_006)"
run_sim sim_u2  "U2  | preproc_batch2    (TP_007-TP_012)"
run_sim sim_u3  "U3  | adaptive_margin   (TAM_001-TAM_004)"
run_sim sim_u4  "U4  | zonotope_gen1     (TZ_001-TZ_004)"
run_sim sim_u5  "U5  | zonotope_gen2     (TZ_005-TZ_007)"
run_sim sim_u6  "U6  | admm_u6           (TADM_001-TADM_004)"
run_sim sim_u7  "U7  | admm_u7           (TADM_005-TADM_008)"
run_sim sim_u8  "U8  | collision_sat_u8  (TSAT_001-TSAT_004)"
run_sim sim_u9  "U9  | collision_sat_u9  (TSAT_005-TSAT_008)"
run_sim sim_u10 "U10 | fsm_u10           (TF_001-TF_004)"
run_sim sim_u11 "U11 | fsm_u11           (TF_005-TF_008)"
run_sim sim_u12 "U12 | wdt               (TWDT_001-TWDT_003)"
run_sim sim_u13 "U13 | hmao_engine       (system integration)"
run_sim sim_u14 "U14 | axi_arbiter       (TAXI_001-TAXI_004)"

# =============================================================================
# BÁO CÁO TỔNG HỢP
# =============================================================================
puts ""
puts "╔══════════════════════════════════════════════════════════════════╗"
puts "║              HMAO ENGINE - KẾT QUẢ SIMULATION                  ║"
puts "╠══════════════════════════════════════════════════════════════════╣"

set total_pass 0
set total_fail 0
set total_error 0
set total_skip 0

foreach entry $sim_results {
    lassign $entry name result _
    set icon "  "
    switch $result {
        PASS    { set icon "✓ "; incr total_pass  }
        FAIL    { set icon "✗ "; incr total_fail  }
        ERROR   { set icon "E "; incr total_error }
        SKIP    { set icon "- "; incr total_skip  }
        default { set icon "? " }
    }
    puts "║  $icon \[$result\]   $name"
}

puts "╠══════════════════════════════════════════════════════════════════╣"
set total [expr {$total_pass + $total_fail + $total_error}]
puts "║  TỔNG HỢP: PASS=$total_pass  FAIL=$total_fail  ERROR=$total_error  SKIP=$total_skip  (/$total)"
if {$total_fail == 0 && $total_error == 0} {
    puts "║  ✓ TẤT CẢ PASSED — Sẵn sàng synthesis!"
} else {
    puts "║  ✗ CÓ LỖI — Kiểm tra log từng sim set bên trên"
}
puts "╚══════════════════════════════════════════════════════════════════╝"

# Xuất báo cáo ra file
set report_file "$SIM_DIR/vivado_sim_report.txt"
set fh [open $report_file w]
puts $fh "HMAO Engine Vivado Simulation Report"
puts $fh "Generated: [clock format [clock seconds]]"
puts $fh "======================================"
foreach entry $sim_results {
    lassign $entry name result log
    puts $fh "\[$result\] $name"
}
puts $fh "======================================"
puts $fh "PASS=$total_pass  FAIL=$total_fail  ERROR=$total_error"
close $fh
puts ""
puts "  Báo cáo đã lưu: $report_file"
