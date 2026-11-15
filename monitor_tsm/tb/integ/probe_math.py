"""Isolate reaction helper, oracle spec10.2/reaction_safe."""
import json,subprocess
from gen_sequences import HERE,ROOT,inputs,g,record
r=json.loads((ROOT/'vectors/system.ports.jsonl').read_text().splitlines()[0]);d=inputs(r['input']['inputs'])
tb='''`timescale 1ns/1ps
module tb_probe_math;
logic clk=0,rst=0,qv=0,qr,sv,ok;
logic [8199:0] world_out;
logic [703:0] bridge;
logic [95:0] pose;
always #5 clk=~clk;
m_tsmx_math dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_op(3'd0),
 .i_ego(256'hHEX),.i_world(8200'd0),.i_delay(32'd0),.i_plan(560'd0),.i_rear(32'h40000000),
 .o_req_ready(qr),.o_rsp_valid(sv),.o_ok(ok),.o_world(world_out),.o_bridge(bridge),.o_pose(pose));
initial begin
 #40;rst=1;#30;qv=1;#10;qv=0;
 wait(sv);if(ok!==EXPECT)$fatal(1,"math mismatch");$display("PASS math probe");$finish;
end
integer c=0;
always @(posedge clk)begin c=c+1;
 $display("MATH cycle=%0d state=%0d arstate=%0d",c,dut.reg_fsm_ctrl_current_state,dut.u_arith.reg_fsm_ctrl_current_state);
 if(c>1000)$fatal(1,"math hang");
end
endmodule
'''.replace('HEX',f'{record(g.pack_ego(d["ego"]),256):064x}').replace('EXPECT',"1'b"+str(int(g.reaction_safe(d['ego']))))
(HERE/'tb_probe_math.sv').write_text(tb)
files=[ROOT/'rtl/arith/m_tsmx_arith_div.sv',ROOT/'rtl/arith/m_tsmx_arith.sv',ROOT/'rtl/top/m_tsmx_math.sv',HERE/'tb_probe_math.sv']
with (HERE/'probe_math_compile.log').open('w')as f:
 p=subprocess.run(['iverilog','-g2012','-s','tb_probe_math','-o',str(HERE/'probe_math.vvp')]+list(map(str,files)),stdout=f,stderr=f)
assert p.returncode==0
with (HERE/'probe_math_sim.log').open('w')as f:
 try:
  p=subprocess.run(['vvp','-i',str(HERE/'probe_math.vvp')],stdout=f,stderr=f,timeout=15)
  print('math probe exit',p.returncode)
 except subprocess.TimeoutExpired:print('math probe timeout15s')
print((HERE/'probe_math_sim.log').read_text()[-1600:])
