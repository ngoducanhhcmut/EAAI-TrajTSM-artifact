set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

# GRU decoder depends on sigmoid + tanh LUTs and scale LUT
# sigmoid_lut_init.hex and tanh_lut_init.hex must be accessible from cwd
sim_run tb_gru_waypoint_decoder_advance [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/gru/fp32_sigmoid_lut.sv \
    $root/rtl/src/gru/fp32_tanh_lut.sv \
    $root/rtl/src/gru/gru_scale_lutram.sv \
    $root/rtl/src/gru/gru_waypoint_decoder.sv \
    $root/tb/sv/tb_gru_waypoint_decoder_advance.sv \
]
