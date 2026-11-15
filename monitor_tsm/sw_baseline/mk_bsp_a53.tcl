# Claude 04/11/2026: standalone BSP for psu_cortexa53_0 from the TSM-X board XSA (xsct, Vitis 2023.2).
#   C:/Vivado/Vitis/2023.2/bin/xsct.bat mk_bsp_a53.tcl
set HERE [file normalize [file dirname [info script]]]
set XSA  [file normalize [file join $HERE .. board out system_wrapper_tsmx.xsa]]
set WS   [file join $HERE ws]
file mkdir $WS
setws $WS
platform create -name a53plat -hw $XSA -proc psu_cortexa53_0 -os standalone -out $WS -no-boot-bsp
platform write
platform generate
puts "###BSP_DONE"
