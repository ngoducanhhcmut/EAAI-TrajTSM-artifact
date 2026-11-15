set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

sim_run tb_input_adapter_adv [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/input/token_fifo.sv \
    $root/rtl/src/input/input_adapter.sv \
    $root/tb/sv/tb_input_adapter_adv.sv \
]
