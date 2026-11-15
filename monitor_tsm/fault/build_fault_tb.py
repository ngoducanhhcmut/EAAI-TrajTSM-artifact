"""Build portable single-job bench and a syntax-only ROM lowering in fault/."""
import json, re
from pathlib import Path
from gen_faults import HERE, ROOT, dump, sha

def main():
    src=ROOT/'rtl/top/m_tsmx_engine.sv'; text=src.read_text(); entries=0
    def rom(m):
        nonlocal entries
        name,body=m.groups(); vals=[int(x) for x in re.findall(r"10'd(\d+)",body)]
        assert len(vals)==512
        packed=sum(v<<(10*i) for i,v in enumerate(vals))
        assert all((packed>>(10*i))&1023==v for i,v in enumerate(vals))
        entries+=len(vals)
        return f"localparam logic [5119:0] {name} = 5120'h{packed:01280x};"
    text=re.sub(r"localparam logic \[9:0\] (LPARA_MOD_[ABC]) \[0:511\] = '\{([^}]+)\};",rom,text)
    text=re.sub(r'(LPARA_MOD_[ABC])\[w_v\[(\d+):(\d+)\]\]',r'\1[10*w_v[\2:\3] +:10]',text)
    assert entries==1536
    (HERE/'m_tsmx_engine.sv').write_text(text)
    dump('rom_lowering.json',dict(source_sha256=sha(src),copy_sha256=sha(HERE/'m_tsmx_engine.sv'),entries_checked=entries))
    arith=ROOT/'rtl/arith/m_tsmx_arith.sv'
    atext=arith.read_text()
    old='w_fsm_ctrl_nxt_state=reg_pvalid ? ENUM_ST_W_D0 : ENUM_ST_W_NEXT;'
    assert atext.count(old)==1
    replacement="for(integer fault_compat_bit=0;fault_compat_bit<5;fault_compat_bit=fault_compat_bit+1) w_fsm_ctrl_nxt_state[fault_compat_bit]=reg_pvalid ? ((5'(ENUM_ST_W_D0)>>fault_compat_bit)&1'b1) : ((5'(ENUM_ST_W_NEXT)>>fault_compat_bit)&1'b1);"
    (HERE/'m_tsmx_arith.sv').write_text(atext.replace(old,replacement))
    original=(ROOT/'tb/integ/tb_m_tsmx_top.sv').read_text()
    signals=original[original.index('  logic  i_clk_core;'):original.index('  logic [VW-1:0] vectors')]
    inst=original[original.index('  m_tsmx_top #'):original.index('  always #5')]
    faults=json.loads((HERE/'faults.json').read_text())
    cases=[]
    for f in faults:
        target=f['path']+('' if f['scalar'] else f"[{f['bit']}]")
        cases.append(f'''      {f['id']}: begin
        before_bit={target}; {target}=~before_bit;
        after_bit={target}; #1;
        probe_ok=(before_bit===1'b0 || before_bit===1'b1)
          && after_bit===~before_bit && {target}===~before_bit;
      end''')
    init='\n'.join(f"    {n}='0;" for n in re.findall(r'logic\s*(?:\[[^\]]+\])?\s+(i_\w+);',signals))
    tb='''`timescale 1ns/1ps
module tb_fault;
  parameter integer LANES=2;
'''+signals+inst+'''
  logic [48036:0] vector_word;
  logic reset_job;
  logic [44672:0] req;
  logic [37:0] expected_rsp,seen_rsp;
  logic [1896:0] expected_cmd,seen_cmd;
  logic [1055:0] expected_event,seen_event;
  logic [331:0] expected_ing;
  logic [7:0] expected_sup;
  logic [31:0] expected_lost,csr_reason,csr_status,expected_status;
  logic [1903:0] txbuf;
  integer fault_id=-1,fault_cycle=1,active_cycle=0,latency=0;
  integer fd,rc,txword=0,frames=0,evt=0,elapsed=0;
  logic active=0,injected=0,probe_ok=0,before_bit,after_bit;
  logic deadline_seen=0,framing_bad=0;
  logic [15:0] fallback_mask=0;
  string vector_file="job0.mem";
  always #5 i_clk_core=~i_clk_core;
  always @(posedge i_clk_core) begin
    if(active) begin
      active_cycle=active_cycle+1;
      #1;
      if(dut.u_tsmx_engine.reg_deadline) deadline_seen=1;
      if(dut.u_tsmx_engine.reg_fsm_ctrl_current_state[40]) fallback_mask=16'hffff;
      if(fault_id>=0 && active_cycle==fault_cycle && !injected) begin
        case(fault_id)
'''+ '\n'.join(cases)+'''
          default: $fatal(1,"invalid fault ID");
        endcase
        injected=1;
        $display("PROBE id=%0d cycle=%0d before=%b after=%b ok=%b",fault_id,active_cycle,before_bit,after_bit,probe_ok);
      end
    end
  end
  always @(negedge i_clk_core) begin
    if(i_rst_n_core && o_tx_valid && i_tx_ready) begin
      if(txword==0) begin txbuf='0; if(o_tx_data!==32'd2) framing_bad=1; end
      else if(txword==1) begin if(o_tx_data!==32'd238) framing_bad=1; end
      else for(integer b=0;b<4;b=b+1)
        if(4*(txword-2)+b<238) txbuf[1903-8*(4*(txword-2)+b) -:8]=o_tx_data[8*b +:8];
      if(o_tx_last) begin
        if(txword!=61 || o_tx_keep!==4'b0011 || txbuf[6:0]!==7'd0) framing_bad=1;
        seen_cmd=txbuf[1903:7];frames=frames+1;txword=0;
      end else txword=txword+1;
    end
  end
  task automatic bus_read(input logic [15:0] addr,output logic [31:0] data);
    @(negedge i_clk_core);i_axi_araddr=addr;i_axi_arvalid=1;i_axi_rready=1;
    do @(posedge i_clk_core); while(!o_axi_arready);
    @(negedge i_clk_core);i_axi_arvalid=0;
    while(!o_axi_rvalid) @(negedge i_clk_core);
    data=o_axi_rdata;
    @(negedge i_clk_core);i_axi_rready=0;
  endtask
  task automatic report(input integer hang);
    $display("RESULT hang=%0d injected=%0d probe=%0d cycles=%0d deadline=%0d frames=%0d event=%0d framing=%0d fallback=%h",hang,injected,probe_ok,latency,deadline_seen,frames,evt,framing_bad,fallback_mask);
    $display("RSP %h %h",seen_rsp,expected_rsp);
    $display("CMD %h %h",seen_cmd,expected_cmd);
    $display("EVENT %h %h",seen_event,expected_event);
    $display("ING %h %h",dut.u_tsmx_engine.reg_ing,expected_ing);
    $display("SUP %h %h",{dut.u_tsmx_engine.reg_mode,dut.u_tsmx_engine.reg_good,dut.u_tsmx_engine.reg_fault,dut.u_tsmx_engine.reg_pending_valid,dut.u_tsmx_engine.reg_backup_valid},expected_sup);
    $display("LOST %h %h",dut.u_tsmx_engine.reg_lost,expected_lost);
    $display("REASON %h %h",csr_reason,{24'd0,expected_rsp[36:29]});
    $display("STATUS %h %h",csr_status,expected_status);
    $display("HEALTH healthy=%b fault=%b",dut.u_tsmx_engine.reg_healthy,dut.u_tsmx_engine.reg_fault);
    $finish;
  endtask
  initial begin
'''+init+'''
    seen_cmd='0;seen_event='0;seen_rsp='0;csr_reason='0;csr_status='0;
    rc=$value$plusargs("FAULT_ID=%d",fault_id);
    rc=$value$plusargs("FAULT_CYCLE=%d",fault_cycle);
    rc=$value$plusargs("FILE=%s",vector_file);
    fd=$fopen(vector_file,"r"); if(!fd)$fatal(1,"missing vector");
    rc=$fscanf(fd,"%h",vector_word);$fclose(fd);if(rc!=1)$fatal(1,"bad vector");
    {reset_job,req,expected_rsp,expected_cmd,expected_ing,expected_sup,expected_lost,expected_event}=vector_word;
    if(!reset_job)$fatal(1,"must start at reset");
    expected_status='0;expected_status[1]=expected_rsp[0];
    expected_status[2]=!expected_rsp[0] || expected_rsp[28:26]==3'd3 || expected_rsp[9];
    expected_status[5:3]=expected_rsp[28:26];expected_status[6]=expected_sup[1];expected_status[7]=expected_sup[0];
    expected_status[8]=expected_rsp[0];expected_status[17:16]=expected_rsp[11:10];
    i_tx_ready=1;
    repeat(4) @(negedge i_clk_core);i_rst_n_core=1;
    repeat(5) @(negedge i_clk_core);
    @(negedge i_clk_core);i_req_data=req;i_req_valid=1;i_time_us=req[44672:44641];
    i_ack_valid=req[33856];i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528];
    while(!o_req_ready) @(negedge i_clk_core);
    @(posedge i_clk_core); #2;active=1;
    @(negedge i_clk_core);i_req_valid=0;i_ack_valid=0;
    while(!o_rsp_valid) begin
      @(negedge i_clk_core);
      if(active_cycle>1875010) begin latency=active_cycle;report(1);end
    end
    latency=active_cycle;seen_rsp=o_rsp_data;active=0;
    repeat(3) @(negedge i_clk_core);i_rsp_ready=1;
    @(negedge i_clk_core);i_rsp_ready=0;
    i_log_idx=0;i_log_valid=1;i_log_ready=0;
    while(!o_log_ready) @(negedge i_clk_core);
    @(negedge i_clk_core);i_log_valid=0;
    while(!o_log_valid) @(negedge i_clk_core);
    seen_event=o_log_data;evt=1;i_log_ready=1;
    @(negedge i_clk_core);i_log_ready=0;
    while(frames==0 || txword!=0 || o_tx_valid) @(negedge i_clk_core);
    bus_read(16'h28,csr_reason);bus_read(16'h04,csr_status);
    report(0);
  end
  initial begin
    // Also bounds recorder/transport/CSR waits after a completed response.
    repeat(1876000) @(posedge i_clk_core);
    latency=active_cycle;report(1);
  end
endmodule
'''
    (HERE/'tb_fault.sv').write_text(tb)
    sources=sorted((ROOT/'rtl').rglob('*.sv'))
    sources=[HERE/'m_tsmx_engine.sv' if s==src else s for s in sources]
    sources=[HERE/'m_tsmx_arith.sv' if s==arith else s for s in sources]
    dump('sources.json',[str(s.relative_to(ROOT)).replace('\\','/') for s in sources])
    print('Built bench with',len(cases),'fault cases; ROM entries checked',entries)

if __name__=='__main__': main()
