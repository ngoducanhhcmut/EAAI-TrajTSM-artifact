set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

sim_run tb_axi_width_conv_adv [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/control/axi_width_converter.sv \
    $root/tb/sv/tb_axi_width_conv_adv.sv \
]
