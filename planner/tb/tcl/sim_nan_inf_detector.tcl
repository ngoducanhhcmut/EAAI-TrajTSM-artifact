set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

sim_run tb_nan_inf_detector_adv [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/output/nan_inf_detector.sv \
    $root/tb/sv/tb_nan_inf_detector_adv.sv \
]
