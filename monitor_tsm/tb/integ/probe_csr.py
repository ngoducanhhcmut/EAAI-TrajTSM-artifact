"""Read-only accepted CSR diagnostic: isolate four-state simulator reset behavior."""
from pathlib import Path
from build_rtl import CLOCK,AXI
from run import run,ROOT,HERE
import re
ports=CLOCK+AXI.split('  input wire [9:0]')[0]+'''  input wire i_sts_valid,
  input wire [114:0] i_sts_data,
  output logic [3:0] o_config_data'''
sigs=re.findall(r'(input wire|output logic)\s*(\[[^]]+\])?\s*([io]_\w+)',ports)
s='`timescale 1ns/1ps\nmodule tb_probe_csr;\n'
for d,w,n in sigs:s+=f'logic {w} {n};\n'
s+='m_tsmx_csr dut ('+','.join('.'+n+'('+n+')' for d,w,n in sigs)+');\n'
s+='always #5 i_clk_core=~i_clk_core;\ninitial begin\n'
for d,w,n in sigs:
    if d=='input wire':s+=n+"='0;\n"
s+='''i_rst_n_core=1; #1; i_rst_n_core=0; #39; i_rst_n_core=1; #20;
i_axi_araddr=16'h30;i_axi_arvalid=1;
#10;i_axi_arvalid=0; #20;
if(o_axi_rvalid!==1 || o_axi_rdata!==32'd16)$fatal(1,"CSR probe");
$display("PASS CSR probe");$finish;
end
always @(posedge i_clk_core)$display("probe time=%0t rst=%b reg=%b nxt=%b ar=%b data=%h",$time,
i_rst_n_core,dut.reg_rvalid,dut.w_rvalid_nxt,o_axi_arready,o_axi_rdata);
endmodule
'''
(HERE/'tb_probe_csr.sv').write_text(s)
import argparse
ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['iverilog','xsim'],default='iverilog');a=ap.parse_args()
if a.tool=='iverilog':
    rc=run(['iverilog','-g2012','-s','tb_probe_csr','-o',HERE/'probe_csr.vvp',
            ROOT/'rtl/csr/m_tsmx_csr.sv',HERE/'tb_probe_csr.sv'],'probe_icarus_compile.log')
    if rc:raise SystemExit(rc)
    rc=run(['vvp','-i',HERE/'probe_csr.vvp'],'probe_icarus_sim.log')
    log=HERE/'probe_icarus_sim.log'
else:
    b=Path('C:/Vivado/Vivado/2023.2/bin')
    rc=run([b/'xvlog.bat','--sv',ROOT/'rtl/csr/m_tsmx_csr.sv',HERE/'tb_probe_csr.sv'],'probe_xvlog.log')
    if rc:raise SystemExit(rc)
    rc=run([b/'xelab.bat','--snapshot','probe_csr','work.tb_probe_csr'],'probe_xelab.log')
    if rc:raise SystemExit(rc)
    rc=run([b/'xsim.bat','probe_csr','--runall'],'probe_xsim.log')
    log=HERE/'probe_xsim.log'
result=log.read_text();print(result[-1600:])
raise SystemExit(rc or int('PASS CSR probe' not in result or 'Fatal:' in result or 'FATAL:' in result))
