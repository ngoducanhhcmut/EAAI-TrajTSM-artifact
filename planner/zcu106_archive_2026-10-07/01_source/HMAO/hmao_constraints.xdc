# =============================================================================
# FILE        : hmao_constraints.xdc
# PROJECT     : HMAO Engine
# SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 11.1, 17.4
# PLATFORM    : Xilinx Versal HX FPGA - SLR1 (ASIL-D Domain)
# =============================================================================

# -----------------------------------------------------------------------------
# PRIMARY CLOCK: hmao_clk = 400 MHz
# Spec: "LOCKED, BACKBONE routing"
# -----------------------------------------------------------------------------
create_clock -period 2.500 -name hmao_clk [get_ports hmao_clk]

# Clock uncertainty (skew + jitter, Spec Ref: Section 11.1)
set_clock_uncertainty -setup 0.050 [get_clocks hmao_clk]
set_clock_uncertainty -hold  0.020 [get_clocks hmao_clk]

# -----------------------------------------------------------------------------
# QM CLOCK (BOOM domain)
# -----------------------------------------------------------------------------
create_clock -period 2.500 -name qm_clk [get_ports qm_clk]

# -----------------------------------------------------------------------------
# WATCHDOG RING OSCILLATOR (independent, NOT correlated with hmao_clk)
# -----------------------------------------------------------------------------
create_clock -period 3.000 -name wdt_ring_osc [get_ports wdt_ring_osc_clk]
set_clock_groups -asynchronous -group [get_clocks hmao_clk] \
                               -group [get_clocks wdt_ring_osc]
set_clock_groups -asynchronous -group [get_clocks qm_clk] \
                               -group [get_clocks wdt_ring_osc]

# -----------------------------------------------------------------------------
# SETUP / HOLD MARGINS (Spec Ref: Section 11.1)
# WNS > +0.150ns (setup margin, derated)
# Hold > +0.050ns
# -----------------------------------------------------------------------------
set_multicycle_path 1 -setup -from [get_clocks hmao_clk] -to [get_clocks hmao_clk]

# -----------------------------------------------------------------------------
# LOGIC LEVEL CONSTRAINT (Spec Ref: Section 11.1)
# "Tối đa 12 tầng LUT (ngăn critical path tại phép nhân ma trận Zonotope)"
# -----------------------------------------------------------------------------
# Note: This constraint is expressed in Vivado as max_delay with datapath_only
# or set via phys_opt_design. Cannot directly constrain LUT levels via XDC.
# Use set_property MAX_FANOUT and KEEP on critical paths instead.

# -----------------------------------------------------------------------------
# FLOORPLAN: Co-locate HMAO in SLR1 (Spec Ref: Section 2.2)
# -----------------------------------------------------------------------------
# Create pblock for SLR1 ASIL-D domain
create_pblock pblock_safety_slr1
add_cells_to_pblock [get_pblock pblock_safety_slr1] [get_cells u_hmao_engine]
add_cells_to_pblock [get_pblock pblock_safety_slr1] [get_cells u_riscv_dcls]
add_cells_to_pblock [get_pblock pblock_safety_slr1] [get_cells u_smpu]
add_cells_to_pblock [get_pblock pblock_safety_slr1] [get_cells u_fault_mgr]

# Restrict to SLR1 resources
# Note: Exact site ranges depend on specific Versal HX device
# Placeholder: adjust CLOCKREGION for target part
resize_pblock [get_pblock pblock_safety_slr1] -add {CLOCKREGION_X0Y5:CLOCKREGION_X3Y9}

# -----------------------------------------------------------------------------
# DONT_TOUCH: Prevent optimization of safety-critical cells
# Spec Ref: Section 17.4
# -----------------------------------------------------------------------------
set_property DONT_TOUCH true [get_cells u_hmao_engine]
set_property DONT_TOUCH true [get_cells u_riscv_dcls/u_core_A]
set_property DONT_TOUCH true [get_cells u_riscv_dcls/u_core_B]
set_property DONT_TOUCH true [get_cells u_voter]

# -----------------------------------------------------------------------------
# CDC: False paths between async clock domains
# (Handled by 2-FF synchronizers in design)
# -----------------------------------------------------------------------------
set_false_path -from [get_clocks qm_clk] -to [get_clocks hmao_clk]
set_false_path -from [get_clocks hmao_clk] -to [get_clocks qm_clk]

# Only the synchronized outputs are on real timing paths
set_max_delay -datapath_only 5.0 \
  -from [get_cells u_cdc_uvec/req_sync_a_reg] \
  -to   [get_cells u_cdc_uvec/req_sync_b_reg]

# -----------------------------------------------------------------------------
# OUTPUT DELAY (AXI to NoC, assume 2ns board/routing delay)
# -----------------------------------------------------------------------------
set_output_delay -clock hmao_clk -max 1.0 [get_ports hmao_ar*]
set_output_delay -clock hmao_clk -min 0.0 [get_ports hmao_ar*]
set_input_delay  -clock hmao_clk -max 1.5 [get_ports hmao_r*]
set_input_delay  -clock hmao_clk -min 0.0 [get_ports hmao_r*]
