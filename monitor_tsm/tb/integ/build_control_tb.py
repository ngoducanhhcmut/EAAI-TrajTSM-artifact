"""Timer snapshot probes and physical stalled-egress deadline test, spec6.2/10.3.

Snapshot probes initialize only I1-owned cached state; they do not claim admission.
The deadline test uses three real top requests and no internal-state initialization.
"""
import json,re
from gen_sequences import HERE,ROOT,g,record,request
from build_rtl import CLOCK,DIRECT,AXI,STREAM,expand_names

def main():
    ports=CLOCK+DIRECT+AXI+',\n'+STREAM
    sigs=re.findall(r'(input wire|output logic)\s*(\[[^]]+\])?\s*([io]_\w+)',ports)
    e=g.Ego(0,0,1000000,0,50000000,0)
    p=g.Plan(7,e,0,0,0,1000000,0)
    c=g.certify(p,100000)
    tests=[]
    for ack in (False,True):
        for t in (39999,40000,40001,99999,100000,100001):
            code=g.b9_cert(p,c,t,True,0,ack,p.seq)
            tests.append((p,c,t,0,ack,7,code,'boundary'))
    tests.append((p,c,39999,20000,False,7,'pending','no_tick'))
    tests.append((p,c,40000,20000,False,7,'ack_timeout','aligned_tick'))
    tests.append((p,c,39999,0,True,99,'pending','wrong_ack_before_timeout'))
    tests.append((p,c,40000,0,True,99,'ack_timeout','wrong_ack_at_timeout'))
    pp=g.Plan(8,e,0,50000,50000,1000000,0);cc=g.certify(pp,100000)
    for t in (39999,40000,40001):
        tests.append((pp,cc,t,0,True,8,g.b9_cert(pp,cc,t,True,0,True,8),'early_ack_not_retained'))
    s='''// Project TSM-X; Author TSMX project; Version0.1; spec6.2/10.3.
`timescale 1ns/1ps
module tb_tsmx_control;
  parameter integer LANES=2;
'''
    for d,w,n in sigs:s+=f'  logic {w} {n};\n'
    s+='  integer probes=0;\n  time start_time;\n  integer clocks;\n'
    s+='  m_tsmx_top #(.PARA_DIRECT(1),.PARA_G(LANES),.PARA_P(LANES)) dut (\n'
    s+=',\n'.join(f'    .{n}({n})' for d,w,n in sigs)+'\n  );\n'
    s+='''  always #5 i_clk_core=~i_clk_core;
  task automatic reset_core;
    @(negedge i_clk_core);i_rst_n_core=0;i_req_valid=0;i_ack_valid=0;i_time_us=0;
    repeat(4)@(negedge i_clk_core);i_rst_n_core=1;
    repeat(5)@(negedge i_clk_core);
  endtask
  task automatic request_one;
    @(negedge i_clk_core);i_req_valid=1;
    while(o_req_ready!==1'b1)@(negedge i_clk_core);
    @(posedge i_clk_core);start_time=$time;
    @(negedge i_clk_core);i_req_valid=0;
  endtask
  task automatic await_reply;
    while(o_rsp_valid!==1'b1)@(negedge i_clk_core);
    clocks=($time-5-start_time)/10+1;
    @(negedge i_clk_core);
  endtask
  initial begin
'''
    for d,w,n in sigs:
        if d=='input wire':s+=f"    {n}='0;\n"
    s+='''    if(!$test$plusargs("DEADLINE_ONLY"))begin
'''
    physical_replacements=[]
    for idx,(pl,ce,t,tick,ack,ackseq,code,name) in enumerate(tests):
        ppv=record(g.pack_plan(pl),560);ccv=record(g.pack_certificate(ce),1217)
        shouldpending=code=='pending';shouldbackup=code=='committed'
        seed=f'''    // Snapshot probe {idx}: {name}, golden b9_cert={code}.
    dut.u_tsmx_engine.reg_pp=560'h{ppv:0140x};
    dut.u_tsmx_engine.reg_pc=1217'h{ccv:0305x};
    dut.u_tsmx_engine.reg_pv=1'b1;dut.u_tsmx_engine.reg_issued=32'd0;
    dut.u_tsmx_engine.reg_tick=32'd{tick};dut.u_tsmx_engine.reg_tick_valid=1'b1;'''
        setup=dict(now=0,ego=e,pkt=g.packet(pl),cert=ce)
        _,oracle=g.tsmx_cycle(g.Supervisor(),setup);assert oracle['accept']
        replacement=f'''    // Physical admission precedes timer probe {idx}.
    i_req_data=44673'h{request(setup):011169x};i_rsp_ready=1;i_tx_ready=1;
    request_one();
    while(o_rsp_valid!==1'b1)@(negedge i_clk_core);
    if(o_rsp_data[37]!==1'b1)$fatal(1,"timer setup rejected {idx}");
    @(negedge i_clk_core);'''
        if tick:
            replacement+=f'\n    i_time_us=32\'d{tick};@(negedge i_clk_core);'
        physical_replacements.append((seed,replacement))
        s+=f'''    reset_core();
    // Snapshot probe {idx}: {name}, golden b9_cert={code}.
    dut.u_tsmx_engine.reg_pp=560'h{ppv:0140x};
    dut.u_tsmx_engine.reg_pc=1217'h{ccv:0305x};
    dut.u_tsmx_engine.reg_pv=1'b1;dut.u_tsmx_engine.reg_issued=32'd0;
    dut.u_tsmx_engine.reg_tick=32'd{tick};dut.u_tsmx_engine.reg_tick_valid=1'b1;
    i_time_us=32'd{t};i_ack_valid=1'b{int(ack)};i_ack_seq=32'd{ackseq};
    @(negedge i_clk_core);
    if(dut.u_tsmx_engine.reg_pv!==1'b{int(shouldpending)}
      || dut.u_tsmx_engine.reg_bv!==1'b{int(shouldbackup)})
      $fatal(1,"timer probe {idx} {name} expected {code}");
    if(dut.u_tsmx_engine.reg_timer_valid!==1'b{int(not shouldpending)})
      $fatal(1,"timer status validity {idx}");
'''
        if not shouldpending:
            s+=f'''    if(dut.u_tsmx_engine.reg_timer_code!==8'd{g.REASONS.index(code)})
      $fatal(1,"timer priority/status {idx}: expected {code}");
'''
        s+=f'''
    probes=probes+1;
    $display("TIMER {idx} {name} PASS");
'''
        if name=='early_ack_not_retained':
            s+='''    i_ack_valid=0;i_time_us=32'd60000;
    @(negedge i_clk_core);
    if(dut.u_tsmx_engine.reg_pv!==1'b0 || dut.u_tsmx_engine.reg_timer_code!==8'd30)
      $fatal(1,"early ACK persisted into apply epoch");
'''
    s+='''    $display("PASS cached timer probes=%0d",probes);
    end
    if($test$plusargs("TIMERS_ONLY"))$finish;
    reset_core();i_rsp_ready=1;i_tx_ready=0;
'''
    raw=int((HERE/'smoke.mem').read_text().splitlines()[0],16)
    q=(raw>>3363)&((1<<44673)-1)
    s+=f"    i_req_data=44673'h{q:011169x};i_time_us=32'd1000;\n"
    s+='''    request_one();await_reply();
    request_one();await_reply();
    request_one();
    while(o_rsp_valid!==1'b1)begin
      @(negedge i_clk_core);
      if($time-start_time>18750100)$fatal(1,"deadline response missing");
    end
    clocks=($time-5-start_time)/10+1;
    if(clocks!=1875000 || o_rsp_data[37]!==1'b0 || o_rsp_data[36:29]!==8'd7
       || o_brake!==1'b1)$fatal(1,"deadline result cycles=%0d response=%h brake=%b",clocks,o_rsp_data,o_brake);
    $display("PASS physical deadline clocks=%0d brake=1",clocks);
    $finish;
  end
endmodule
'''
    (HERE/'tb_tsmx_control.sv').write_text(expand_names(s))
    physical=s.replace('module tb_tsmx_control;','module tb_tsmx_control_phy;')
    for old,new in physical_replacements:
        assert old in physical
        physical=physical.replace(old,new)
    (HERE/'tb_tsmx_control_phy.sv').write_text(expand_names(physical))
    (HERE/'timer_probes.json').write_text(json.dumps([dict(id=i,now=t,tick=tick,ack=ack,seq=seq,expected=code,name=name) for i,(_,_,t,tick,ack,seq,code,name) in enumerate(tests)],indent=2))
if __name__=='__main__':main()
