# Claude 10/11/2026: rerun implementation only (synth_1 kept), congestion-driven directives.
set HERE [file normalize [file dirname [info script]]]
set PRJ [file join $HERE prj_joint]; set OUT [file join $HERE out_joint]; file mkdir $OUT
set_param general.maxThreads 4
open_project [file join $PRJ vcu118_joint.xpr]
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "###ERROR synth_1 not complete"; exit 1 }
reset_run impl_1
# 11/11: routing congestion level 6-7 with default placement (SLR0 49 % LUT, SLR1 0.3 %): spread logic across SLRs
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE SSI_SpreadLogic_high [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "###ERROR impl"; exit 1 }
open_run impl_1
report_timing_summary -file [file join $OUT timing_summary.rpt]
report_utilization -file [file join $OUT utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $OUT utilization_hier.rpt]
report_power -file [file join $OUT power_estimate.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "###RESULT WNS=$wns WHS=$whs"
set bit [file join $PRJ vcu118_joint.runs impl_1 system_wrapper.bit]
if {[file exists $bit] && $wns >= 0 && $whs >= 0} {
  file copy -force $bit [file join $OUT system_wrapper_joint.bit]
  write_hw_platform -fixed -include_bit -force -file [file join $OUT system_wrapper_joint.xsa]
  puts "###BIT [file join $OUT system_wrapper_joint.bit]"
} else { puts "###ERROR no bitstream or timing not met" }
exit 0
