# Reject the previously delivered bitstream while newer TSM fixes await a build.
proc board_check_tsm_bit_freshness {root bit} {
  set built [file mtime $bit]
  foreach name {hmao_pkg.sv hmao_preproc.sv hmao_safety_modules.sv hmao_engine_top.sv hmao_zonotope_gen.sv} {
    set source [file join $root HMAO $name]
    if {![file exists $source]} { error "required RTL source missing: $source" }
    if {[file mtime $source] > $built} {
      error "TSM RTL is newer than bitstream ($name). Finish validation and rebuild before programming the board."
    }
  }
}
