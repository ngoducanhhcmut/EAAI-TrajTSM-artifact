# =============================================================================
# _sim_helper.tcl — Shared simulation helper procs
# Rewritten: stream xvlog/xelab/xsim output LIVE to Vivado Tcl console.
#
# Usage:
#   source tb/tcl/_sim_helper.tcl
#   sim_run tb_planning_integration $rtl_sources "SIMULATION"
# =============================================================================

# ---------------------------------------------------------------------------
# sim_puts — puts với flush ngay lập tức để hiển thị trên console Vivado
# ---------------------------------------------------------------------------
proc sim_puts {msg} {
    puts $msg
    catch {flush stdout}
}

# ---------------------------------------------------------------------------
# run_live — chạy command và stream từng dòng output ra console
#
# Tham số:
#   label    : tên hiển thị cho bước này
#   cmd_list : list các token của command (không cần shell quoting)
#
# Trả về: 0 = OK, 1 = có ERROR/FATAL
# ---------------------------------------------------------------------------
proc run_live {label cmd_list} {
    sim_puts ""
    sim_puts "  \[>>>] $label"

    # Mở subprocess dưới dạng readable pipe — Tcl đọc từng dòng ngay khi có
    if {[catch {set fd [open [concat | $cmd_list] r]} err]} {
        sim_puts "  \[ERROR] Không thể khởi động process: $err"
        return 1
    }
    fconfigure $fd -buffering line -translation auto

    set err_cnt  0
    set warn_cnt 0
    set line_cnt 0

    while {[gets $fd line] >= 0} {
        sim_puts "    $line"
        incr line_cnt
        # Phát hiện lỗi trong output
        if {[regexp -nocase {^\s*(ERROR|FATAL)\s*[:\[]?} $line]} {
            incr err_cnt
        } elseif {[regexp -nocase {^\s*WARNING\s*[:\[]?} $line]} {
            incr warn_cnt
        }
    }

    # Đóng pipe — non-zero exit của subprocess sẽ throw exception
    set exit_err 0
    if {[catch {close $fd} cerr]} {
        # Lọc thông báo bình thường của Tcl khi subprocess exit ≠ 0
        if {![regexp -nocase {child process exited abnormally|child killed} $cerr]} {
            sim_puts "  \[WARN] close: $cerr"
        }
        set exit_err 1
    }

    set failed [expr {$err_cnt > 0 || $exit_err}]
    set status  [expr {$failed ? "FAILED" : "OK"}]
    sim_puts "  \[<<<] $label — $line_cnt dòng | $err_cnt lỗi | $warn_cnt cảnh báo → $status"
    return $failed
}

# ---------------------------------------------------------------------------
# sim_run — compile → elaborate → simulate với progress live
# ---------------------------------------------------------------------------
proc sim_run {top_module sources {defines "SIMULATION"}} {
    set root "c:/Users/TransformerDA/Downloads/vla_new_arch"
    set snap "snap_${top_module}"

    sim_puts ""
    sim_puts "=========================================================="
    sim_puts " SIM: $top_module"
    sim_puts " Module: $top_module | Snapshot: $snap"
    sim_puts " Defines: $defines"
    sim_puts "=========================================================="
    sim_puts " [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    sim_puts "=========================================================="

    # ── Bước 1/3: Compile ─────────────────────────────────────────────────────
    sim_puts "\n\[1/3\] COMPILE (xvlog) — đang phân tích SystemVerilog..."

    set xvlog_cmd [list xvlog -sv \
                        -i $root/rtl/include \
                        -d $defines \
                        --log xvlog_${top_module}.log]
    foreach f $sources {
        lappend xvlog_cmd $f
    }

    set t0 [clock milliseconds]
    set rc [run_live "xvlog" $xvlog_cmd]
    set dt [expr {([clock milliseconds] - $t0) / 1000.0}]
    sim_puts "\n  => Compile xong sau ${dt}s"

    if {$rc} {
        sim_puts "\n\[ABORT\] Compile thất bại — xem log: xvlog_${top_module}.log"
        return
    }

    # ── Bước 2/3: Elaborate ───────────────────────────────────────────────────
    sim_puts "\n\[2/3\] ELABORATE (xelab) — đang link và kiểm tra hierarchy..."

    set xelab_cmd [list xelab \
                        -debug typical \
                        $top_module \
                        -s $snap \
                        -d $defines \
                        -timescale 1ns/1ps \
                        --log xelab_${top_module}.log]

    set t0 [clock milliseconds]
    set rc [run_live "xelab" $xelab_cmd]
    set dt [expr {([clock milliseconds] - $t0) / 1000.0}]
    sim_puts "\n  => Elaborate xong sau ${dt}s"

    if {$rc} {
        sim_puts "\n\[ABORT\] Elaborate thất bại — xem log: xelab_${top_module}.log"
        return
    }

    # ── Bước 3/3: Simulate ────────────────────────────────────────────────────
    sim_puts "\n\[3/3\] SIMULATE (xsim) — đang chạy simulation..."
    sim_puts "  Lưu ý: output \$display xuất hiện theo từng đợt khi xsim flush."
    sim_puts "  Log đầy đủ lưu tại: xsim_${top_module}.log"
    sim_puts "  Global watchdog: 750ms sim-time (~150M cycles @ 200MHz)"
    sim_puts ""

    # --onfinish quit  : xsim tự exit sau $finish/$fatal (đóng pipe sạch)
    set xsim_cmd [list xsim $snap \
                       -R \
                       --onfinish quit \
                       --log xsim_${top_module}.log]

    set t0 [clock milliseconds]
    run_live "xsim" $xsim_cmd
    set dt [expr {([clock milliseconds] - $t0) / 1000.0}]

    sim_puts "\n  => Simulation xong sau ${dt}s"
    sim_puts ""
    sim_puts "--- Log files ---"
    sim_puts "  Compile  : xvlog_${top_module}.log"
    sim_puts "  Elaborate: xelab_${top_module}.log"
    sim_puts "  Simulate : xsim_${top_module}.log"
}
