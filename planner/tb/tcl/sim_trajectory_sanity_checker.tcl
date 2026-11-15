set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

sim_run tb_trajectory_sanity_checker_adv [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/output/trajectory_sanity_checker.sv \
    $root/tb/sv/tb_trajectory_sanity_checker_adv.sv \
]
