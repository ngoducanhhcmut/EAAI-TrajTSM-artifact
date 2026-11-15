set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

sim_run tb_token_fifo_advanced [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/input/token_fifo.sv \
    $root/tb/sv/tb_token_fifo_advanced.sv \
]
