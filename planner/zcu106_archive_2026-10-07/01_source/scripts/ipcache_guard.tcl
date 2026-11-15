# =============================================================================
# ipcache_guard.tcl -- chan bay IP CACHE cua Vivado cho planning_top.
#
# BAY: planning_top la mot BD module reference tro THANG vao rtl/ cua repo, nhung
# khoa IP cache cua Vivado KHONG bam noi dung cac tep RTL do. Sua RTL xong,
# reset_run xong, Vivado VAN copy DCP cu tu cache va chi bao mot dong INFO:
#   INFO: [IP_Flow 19-4838] Using cached IP synthesis design ... cache-ID = ...
# Vi the moi ban build tu 18/09 den 29/09/2026 da chay tren netlist ngay 18/09.
# reset_run MOT MINH KHONG DU.
#
# Da thu va KHONG CHAY: set_property ip_cache_permissions {} [current_project]
#   -> thuoc tinh van doc ra 'read write', Vivado 2023.2 bo qua danh sach rong.
#
# Cach chay: so sanh MOC THOI GIAN. Dung cache khi va chi khi DCP moi hon moi tep
# RTL. Nho vay khong phai tong hop lai vo ich khi RTL khong doi (tiet kiem ~40 phut),
# ma cung khong bao gio chay tren netlist cu.
#
# Dung:
#   source scripts/ipcache_guard.tcl
#   ipcache_purge_if_stale $ROOT      ;# TRUOC launch_runs
#   ipcache_assert_fresh   $ROOT      ;# SAU wait_on_run synth_1
# =============================================================================

# Moc thoi gian moi nhat trong toan bo cay RTL (ke ca .svh/.vh).
proc ipcache_newest_rtl {root {subdirs {rtl}}} {
  set newest 0
  set newest_f ""
  foreach sd $subdirs {
  foreach pat {*.sv *.svh *.v *.vh} {
    foreach f [ipcache_find [file join $root $sd] $pat] {
      set m [file mtime $f]
      if {$m > $newest} { set newest $m ; set newest_f $f }
    }
  }
  }
  return [list $newest $newest_f]
}

proc ipcache_find {dir pat} {
  set out {}
  if {![file isdirectory $dir]} { return $out }
  foreach f [glob -nocomplain -directory $dir -- $pat] { lappend out $f }
  foreach d [glob -nocomplain -directory $dir -types d -- *] {
    foreach f [ipcache_find $d $pat] { lappend out $f }
  }
  return $out
}

proc ipcache_dcps {root {prefix system_planning_top}} {
  # Chu y 1: dung `glob <duong dan day du>` chu KHONG dung `glob -directory $d */*/x`
  #   -- dang sau da thu va tra ve rong tren Windows.
  # Chu y 2: duong dan that co BON cap sau `ip`, khong phai ba:
  #   ip / 2023.2 / 0 / 7 / 0740dd847b0bae92 / system_planning_top_0_0.dcp
  #   Viet thieu mot dau * la glob tra ve rong va guard bao "khong co entry cache"
  #   trong khi entry van nam do -> da mac loi nay mot lan.
  # Chu y 3: phai dung $prefix, KHONG duoc cung hoa "system_planning_top". Lan dau
  #   toi tong quat hoa ham nay thi chi doi duoc CHU KY ma khong doi THAN, nen khi
  #   kiem tra hmao no van di tim ten tep cua planning_top -> bao "khong co entry
  #   cache" trong khi entry hmao van nam do va van bi an. Da mac loi nay 30/09.
  return [glob -nocomplain \
    [file join $root hw_project planning_hw.cache ip * * * * ${prefix}*.dcp]]
}

# =============================================================================
# DANH SACH CAC IP LA "BD MODULE REFERENCE" -- tuc tro THANG vao RTL cua repo, nen
# deu mac cung bay: khoa IP cache khong bam noi dung tep RTL.
#
# PHAT HIEN 30/09 08:15: ban sua dau tien cua toi CHI bao ve planning_top. TSM
# (hmao) van an cache entry ngay 2026-08-04 12:16, trong khi HMAO/hmao_fsm.sv sua
# ngay 2026-08-05 20:51 va HMAO/hmao_zonotope_gen.sv ngay 2026-08-05 01:42 -- ca
# hai DEU nam trong danh sach nguon cua IP do (xac minh trong
# hw_project/planning_hw.runs/system_hmao_engine_0_2_synth_1/system_hmao_engine_0_2.tcl).
# => netlist TSM trong MOI ban build tu 05/08 den 30/09 deu CU.
#
# Moi phan tu: {ten_hien_thi  tien_to_cache  thu_muc_run  ten_dcp  thu_muc_RTL}
# =============================================================================
#
# Danh sach nay phai khop DU voi `ls hw_project/planning_hw.gen/sources_1/bd/mref/`
# (da kiem 30/09: dung 3 module-reference). Them mot mref moi vao BD thi PHAI them
# mot dong o day, neu khong no se am tham an cache cu.
# Cot 6 = ten thu muc mref TUONG MINH (khong suy ra tu ten IP -- ten mref
# "hmao_engine_top_bd_ref" khong khop tien to cache "system_hmao_engine").
set IPCACHE_IPS {
  {planning_top system_planning_top         system_planning_top_0_0_synth_1         system_planning_top_0_0.dcp         rtl         planning_top_bd_ref}
  {hmao_engine  system_hmao_engine          system_hmao_engine_0_2_synth_1          system_hmao_engine_0_2.dcp          HMAO        hmao_engine_top_bd_ref}
  {cdc_bridge   system_hmao_gpio_cdc_bridge system_hmao_gpio_cdc_bridge_0_0_synth_1 system_hmao_gpio_cdc_bridge_0_0.dcp rtl/src/cdc hmao_gpio_cdc_bridge_bd_ref}
  {status_pack  system_tsm_status_pack      system_tsm_status_pack_0_0_synth_1      system_tsm_status_pack_0_0.dcp      HMAO        tsm_status_pack}
}

# Xoa entry cache NEU no cu hon RTL. Tra ve 1 neu da xoa cai nao.
proc ipcache_purge_if_stale {root} {
  global IPCACHE_IPS
  set purged 0
  foreach ip $IPCACHE_IPS {
    lassign $ip nm prefix rundir dcpname srcdir
    lassign [ipcache_newest_rtl $root [list $srcdir]] rtl_t rtl_f
    puts "=== \[ipcache/$nm\] RTL moi nhat ($srcdir/): [clock format $rtl_t -format {%Y-%m-%d %H:%M}]  ([file tail $rtl_f])"

    set dcps [ipcache_dcps $root $prefix]
    if {[llength $dcps] == 0} {
      puts "=== \[ipcache/$nm\] khong co entry cache -> se tong hop tu RTL"
      continue
    }
    foreach dcp $dcps {
      set dcp_t [file mtime $dcp]
      puts "=== \[ipcache/$nm\] DCP trong cache: [clock format $dcp_t -format {%Y-%m-%d %H:%M}]"
      if {$dcp_t < $rtl_t} {
        puts "=== \[ipcache/$nm\] DCP CU HON RTL -> xoa [file dirname $dcp]"
        file delete -force [file dirname $dcp]
        set purged 1
      } else {
        puts "=== \[ipcache/$nm\] DCP moi hon RTL -> dung lai duoc, khong tong hop lai"
      }
    }
  }
  return $purged
}

# Sau khi synth xong: khang dinh netlist dang dung KHONG cu hon RTL, cho MOI IP.
# Tra ve 1 neu co bat ky IP nao khong chung minh duoc -> nguoi goi nen exit.
#
# CAN THAN: KHONG duoc so moc cua BAN COPY trong thu muc run. Khi Vivado an cache,
# no COPY DCP cu ra day va ban copy co moc MOI -> phep so do luon pass va guard
# thanh vo dung. Da mac loi nay. Phai so moc cua ENTRY GOC trong cache.
proc ipcache_assert_fresh {root} {
  global IPCACHE_IPS
  set bad 0
  foreach ip $IPCACHE_IPS {
    lassign $ip nm prefix rundir dcpname srcdir
    lassign [ipcache_newest_rtl $root [list $srcdir]] rtl_t rtl_f
    puts "=== \[ipcache/$nm\] RTL moi nhat : [clock format $rtl_t -format {%Y-%m-%d %H:%M}] ([file tail $rtl_f])"

    set run_dir [file join $root hw_project planning_hw.runs $rundir]
    set ooc     [file join $run_dir $dcpname]
    if {![file exists $ooc]} {
      # 07/10: IP lay tu cache thi Vivado khong chay OOC -> khong co DCP trong run. Chap nhan neu MOI entry
      # cache cua IP nay deu moi hon RTL; nguoc lai van loi.
      set dcps [ipcache_dcps $root $prefix]
      set ok_c [expr {[llength $dcps] > 0}]
      foreach dcp $dcps { if {[file mtime $dcp] < $rtl_t} { set ok_c 0 } }
      if {$ok_c} {
        puts "=== \[ipcache/$nm\] lay tu cache (khong chay OOC), moi entry moi hon RTL -> OK"
        continue
      }
      puts "ERROR: \[ipcache/$nm\] khong thay DCP sau khi synth (va cache khong hop le)."
      set bad 1 ; continue
    }

    set used_cache 0
    set log [file join $run_dir runme.log]
    if {[file exists $log]} {
      set fh [open $log r] ; set txt [read $fh] ; close $fh
      if {[string match "*Using cached IP synthesis design*" $txt]} { set used_cache 1 }
    }

    if {!$used_cache} {
      # 07/10: log khong noi "an cache" chua du — log/DCP co the la cua lan chay CU (run khong bi reset).
      if {[file mtime $ooc] < $rtl_t} {
        puts "ERROR: \[ipcache/$nm\] DCP trong thu muc run ([clock format [file mtime $ooc] -format {%Y-%m-%d %H:%M}]) CU HON RTL ([file tail $rtl_f]) -> run khong duoc tong hop lai."
        set bad 1 ; continue
      }
      puts "=== \[ipcache/$nm\] da tong hop that tu RTL (khong an cache, DCP [clock format [file mtime $ooc] -format {%m-%d %H:%M}] moi hon RTL) -> OK"
      continue
    }

    set dcps [ipcache_dcps $root $prefix]
    if {[llength $dcps] == 0} {
      puts "ERROR: \[ipcache/$nm\] runme.log noi da an cache nhung khong tim thay entry nao."
      set bad 1 ; continue
    }
    foreach dcp $dcps {
      set src_t [file mtime $dcp]
      puts "=== \[ipcache/$nm\] AN CACHE. Entry goc: [clock format $src_t -format {%Y-%m-%d %H:%M}]"
      if {$src_t < $rtl_t} {
        puts "ERROR: \[ipcache/$nm\] entry cache CU HON RTL ([file tail $rtl_f])."
        puts "       Ban build nay vo nghia. Xoa [file dirname $dcp] roi chay lai."
        set bad 1
      }
    }
  }
  if {$bad} { return 1 }
  puts "=== \[ipcache\] CHOT OK: netlist cua CA HAI khoi khop RTL hien tai ==="
  return 0
}

# Tu kiem: bang IPCACHE_IPS co phu HET cac module-reference trong BD khong?
# Tra ve 1 neu thieu -> nguoi goi phai exit, KHONG duoc build tiep.
# (Ly do: 30/09 toi da hai lan bo sot mot mref -- truoc la hmao, sau suyt la cdc_bridge.)
proc ipcache_check_coverage {root} {
  global IPCACHE_IPS
  set mref_dir [file join $root hw_project planning_hw.gen sources_1 bd mref]
  set bad 0
  foreach d [glob -nocomplain -type d -directory $mref_dir *] {
    set name [file tail $d]
    set hit 0
    foreach ip $IPCACHE_IPS {
      if {[lindex $ip 5] eq $name} { set hit 1 }
    }
    if {$hit} {
      puts "=== \[ipcache\] mref $name : co trong bang guard"
    } else {
      puts "ERROR: \[ipcache\] mref $name KHONG co trong IPCACHE_IPS -> se am tham an cache cu."
      set bad 1
    }
  }
  return $bad
}
