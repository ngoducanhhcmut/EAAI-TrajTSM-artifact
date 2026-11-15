set root c:/Users/TransformerDA/Downloads/vla_new_arch
cd $root
source tb/tcl/_sim_helper.tcl

# Note: tanh_lut_init.hex must be in the working directory (or specify full path)
# Copy or symlink hex file to current dir if needed:
#   file copy -force rtl/src/gru/tanh_lut_init.hex .

sim_run tb_fp32_tanh_lut_advanced [list \
    $root/rtl/include/planning_pkg.sv \
    $root/rtl/src/gru/fp32_tanh_lut.sv \
    $root/tb/sv/tb_fp32_tanh_lut_advanced.sv \
]
