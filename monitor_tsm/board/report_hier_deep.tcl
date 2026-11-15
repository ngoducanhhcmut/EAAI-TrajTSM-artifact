# Claude 05/11/2026: per-block resource attribution from the routed 100 MHz checkpoint.
open_checkpoint prj/tsmx_zcu106.runs/impl_1/system_wrapper_routed.dcp
report_utilization -hierarchical -hierarchical_depth 9 -file out/utilization_hier_deep.rpt
close_design
