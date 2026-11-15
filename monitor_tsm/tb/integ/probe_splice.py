"""Isolate first system fixture's accepted B2 request without changing any leaf."""
import json,subprocess
from gen_sequences import HERE,ROOT,inputs,g,record
r=json.loads((ROOT/'vectors/system.ports.jsonl').read_text().splitlines()[0])
d=inputs(r['input']['inputs']);v=(record(g.pack_ego(d['ego']),256)<<560)|record(g.pack_plan(d['pkt'].plan),560)
tb='''`timescale 1ns/1ps
module tb_probe_splice;
logic clk=0,rst=0,qv=0,qr,sv,sd;
logic [815:0] qd;
always #5 clk=~clk;
m_tsmx_splice dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_req_data(qd),
 .o_req_ready(qr),.o_rsp_valid(sv),.o_rsp_data(sd),.i_rsp_ready(1'b1));
initial begin
 qd=816'hHEX;
 #40;rst=1;#30;qv=1;#10;qv=0;qd=0;
 wait(sv);if(sd!==1)$fatal(1,"splice mismatch");$display("PASS splice probe");$finish;
end
integer c=0;
always @(posedge clk)begin c=c+1;
 if(c%10==0)$display("PROBE cycle=%0d state=%0d corner=%0d",c,dut.reg_fsm_ctrl_current_state,dut.reg_corner);
 if(c>1000)$fatal(1,"splice hang");
end
endmodule
'''.replace('HEX',f'{v:0204x}')
(HERE/'tb_probe_splice.sv').write_text(tb)
files=[ROOT/'rtl/arith/m_tsmx_arith_div.sv',ROOT/'rtl/arith/m_tsmx_arith.sv',ROOT/'rtl/splice/m_tsmx_splice.sv',HERE/'tb_probe_splice.sv']
with (HERE/'probe_splice_compile.log').open('w')as f:
 p=subprocess.run(['iverilog','-g2012','-s','tb_probe_splice','-o',str(HERE/'probe_splice.vvp')]+list(map(str,files)),stdout=f,stderr=f)
assert p.returncode==0
with (HERE/'probe_splice_sim.log').open('w')as f:
 try:
  p=subprocess.run(['vvp','-i',str(HERE/'probe_splice.vvp')],stdout=f,stderr=f,timeout=30)
  print('splice probe exit',p.returncode)
 except subprocess.TimeoutExpired:print('splice probe timeout30s')
print((HERE/'probe_splice_sim.log').read_text()[-1800:])
