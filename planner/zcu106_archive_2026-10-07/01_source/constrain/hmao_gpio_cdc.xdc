# ==============================================================================
# hmao_gpio_cdc.xdc — loai tru CDC cho cau PS-GPIO -> HMAO va cau waypoint Traj -> TSM
#
# [IMPL 04/10/2026]
#  - BAN TRUOC (04/08) boc rang buoc trong `if {...}`: XDC KHONG ho tro `if`
#    (CRITICAL WARNING Designutils 20-1307) -> MOI rang buoc bi bo qua. Nay viet truc tiep.
#  - Cau waypoint la module hmao_cdc_bridge nhung INSTANCE ten `u_cdc` trong planning_top ->
#    mau ten phai theo instance (`*u_planning_top/u_cdc/...`). Mau '*hmao_cdc_bridge*' khong
#    khop gi (CRITICAL WARNING 17-55 o build reports/impl_v2b).
# Ly do: thanh ghi toggle (mien nguon) di bat dong bo vao tang dong bo dau tien (mien dich).
# ==============================================================================

# ── Cau GPIO -> HMAO (BD cell hmao_gpio_cdc_bridge_0): start / irq_clear ─────────
set_false_path \
  -from [get_cells -hierarchical -filter {NAME =~ "*hmao_gpio_cdc_bridge_0*start_toggle_reg" || NAME =~ "*hmao_gpio_cdc_bridge_0*irqclr_toggle_reg"}] \
  -to   [get_pins  -hierarchical -filter {NAME =~ "*hmao_gpio_cdc_bridge_0*u_start_sync*sync_r_reg[0]*/D" || NAME =~ "*hmao_gpio_cdc_bridge_0*u_irqclr_sync*sync_r_reg[0]*/D"}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ "*hmao_gpio_cdc_bridge_0*sync_r_reg*"}]

# ── Cau waypoint Traj -> TSM (planning_top/u_cdc): req_toggle -> tang dong bo dau ────
set_false_path \
  -from [get_cells -hierarchical -filter {NAME =~ "*u_planning_top/u_cdc/req_toggle_reg"}] \
  -to   [get_pins  -hierarchical -filter {NAME =~ "*u_planning_top/u_cdc/u_req_sync/sync_r_reg[0]*/D"}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ "*u_planning_top/u_cdc/u_req_sync/sync_r_reg*"}]

# Bus du lieu waypoint: *_cap (mien Traj) -> hmao_*_r (mien TSM), chi chot khi data_valid_pulse
# (sau 3 tang dong bo req_toggle) -> du lieu da on dinh >= 3 chu ky dich. Gioi han do tre duong
# du lieu = 1 chu ky nguon (6,666 ns @150 MHz), bo qua lech clock.
set_max_delay -datapath_only 6.666 \
  -from [get_cells -hierarchical -filter {NAME =~ "*u_planning_top/u_cdc/wp_x_cap_reg*" || NAME =~ "*u_planning_top/u_cdc/wp_y_cap_reg*" || NAME =~ "*u_planning_top/u_cdc/sanity_cap_reg*"}] \
  -to   [get_cells -hierarchical -filter {NAME =~ "*u_planning_top/u_cdc/hmao_wp_x_r_reg*" || NAME =~ "*u_planning_top/u_cdc/hmao_wp_y_r_reg*" || NAME =~ "*u_planning_top/u_cdc/hmao_sanity_r_reg*"}]
