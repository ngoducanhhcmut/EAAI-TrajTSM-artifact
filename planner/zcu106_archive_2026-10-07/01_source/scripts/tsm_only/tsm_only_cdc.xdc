# CDC cau GPIO -> TSM (lay tu constrain/hmao_gpio_cdc.xdc, bo phan cua VLA-Traj)
set_false_path \
  -from [get_cells -hierarchical -filter {NAME =~ "*hmao_gpio_cdc_bridge_0*start_toggle_reg" || NAME =~ "*hmao_gpio_cdc_bridge_0*irqclr_toggle_reg"}] \
  -to   [get_pins  -hierarchical -filter {NAME =~ "*hmao_gpio_cdc_bridge_0*u_start_sync*sync_r_reg[0]*/D" || NAME =~ "*hmao_gpio_cdc_bridge_0*u_irqclr_sync*sync_r_reg[0]*/D"}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ "*hmao_gpio_cdc_bridge_0*sync_r_reg*"}]
