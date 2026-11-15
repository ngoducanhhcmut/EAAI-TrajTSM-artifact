# Claude 02/11: r11 (P=G=2) OOC synthesis for VCU118 (XCVU9P-L2FLGA2104). Needs a Vivado Enterprise/device license.
set_param general.maxThreads 1
set R [file normalize [file dirname [info script]]/../rtl]
set out [file normalize [file dirname [info script]]]/m_tsmx_top_p2_vu9p
file mkdir $out
create_project -in_memory -part xcvu9p-flga2104-2L-e
read_verilog -sv $R/arb/m_tsmx_arb.sv
read_verilog -sv $R/arith/m_tsmx_arith.sv
read_verilog -sv $R/cert/m_tsmx_cert.sv
read_verilog -sv $R/csr/m_tsmx_csr.sv
read_verilog -sv $R/codec/m_tsmx_codec_core.sv
read_verilog -sv $R/codec/m_tsmx_codec.sv
read_verilog -sv $R/top/m_tsmx_hash.sv
read_verilog -sv $R/health/m_tsmx_health.sv
read_verilog -sv $R/geom/m_tsmx_geom_su.sv
read_verilog -sv $R/geom/m_tsmx_geom.sv
read_verilog -sv $R/mrmgen/m_tsmx_mrmgen.sv
read_verilog -sv $R/health/m_tsmx_health_bist.sv
read_verilog -sv $R/health/m_tsmx_health_lane.sv
read_verilog -sv $R/ingress/m_tsmx_ingress.sv
read_verilog -sv $R/top/m_tsmx_math.sv
read_verilog -sv $R/rec/m_tsmx_rec.sv
read_verilog -sv $R/sel/m_tsmx_sel.sv
read_verilog -sv $R/splice/m_tsmx_splice.sv
read_verilog -sv $R/supervisor/m_tsmx_supervisor.sv
read_verilog -sv $R/top/m_tsmx_sweep.sv
read_verilog -sv $R/top/m_tsmx_engine.sv
read_verilog -sv $R/top/m_tsmx_io.sv
read_verilog -sv $R/top/m_tsmx_rst.sv
read_verilog -sv $R/top/m_tsmx_top.sv
synth_design -top m_tsmx_top -mode out_of_context -flatten_hierarchy rebuilt -generic PARA_P=2 -generic PARA_G=2
create_clock -period 5.333 -name clk [get_ports -filter {NAME =~ *clk*}]
report_utilization -file $out/util.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $out/util_hier.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
