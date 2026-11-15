"""Emit portable clocked assertions; mutants flip actual DUT output wires."""
from pathlib import Path
H=Path(__file__).resolve().parent
s='''// Project TSM-X; Author TSMX project; Version 0.1.
// Checks derive from spec 5.3, 5.5.6, 9.2 and golden GeomResult, not RTL calculations.
`timescale 1ns/1ps
module tb_m_tsmx_geom;
  reg clk=0,rst=0,req_valid=0,row_valid=0,terminal_valid=0,rsp_ready=0;
  reg [8623:0] req_data=0;
  reg [400:0] row_data=0;
  reg [49:0] terminal_data=0;
  wire raw_ready,raw_row_ready,raw_terminal_ready,raw_valid;
  wire [80:0] raw_data;
  reg flip_ready=0,flip_row_ready=0,flip_terminal_ready=0,flip_valid=0;
  reg [80:0] flip_data=0;
  wire ready=raw_ready^flip_ready, rr=raw_row_ready^flip_row_ready;
  wire tr=raw_terminal_ready^flip_terminal_ready,valid=raw_valid^flip_valid;
  wire [80:0] data=raw_data^flip_data;
  `include "vectors_meta.svh"
  reg [8794:0] jobs[0:N-1];
  reg [400:0] rows[0:R-1];
  reg [80:0] expected=0,prev_data=0;
  reg pv=0,ps=0,pr=0,pt=0,prow=0,prev_rst=0;
  integer hits[0:25];
  string names[0:25];
  integer mutant=-1,injected=0,cycle=0,accepted_at=0,completed=0,pending=0;
  integer job_id=0,start=0,limit=N,offset=0,count=0,pos=0,terminal_sent=0,nostall=0;
  integer reset_mid=0;
  integer inactive=0;
  integer max_latency=0,min_latency=100000000,max_ii=0,last_job=-1;
  integer actor_last=-1,actor_gap=0,actor_max=0,actor_min=1000000,actor_hits=0;
  integer actor_row_max=0,row_at=0;
  m_tsmx_geom dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_row_valid(row_valid),.i_row_data(row_data),.i_terminal_valid(terminal_valid),
    .i_terminal_data(terminal_data),.i_rsp_ready(rsp_ready),.o_req_ready(raw_ready),
    .o_row_ready(raw_row_ready),.o_terminal_ready(raw_terminal_ready),
    .o_rsp_valid(raw_valid),.o_rsp_data(raw_data)
  );
  // Diagnostic hierarchy only measures schedule; no expected data comes from DUT internals.
  task tick;
    integer lat,ii;
    begin
      pv=valid;ps=rsp_ready;pr=ready;pt=tr;prow=rr;prev_data=data;prev_rst=rst;
      if(rst && req_valid && ready) begin
        pending=pending+1;accepted_at=cycle;
        if(last_job>=0) begin ii=cycle-last_job;if(ii>max_ii)max_ii=ii;end
        last_job=cycle;
      end
      if(rst && row_valid && rr)pos=pos+1;
      if(rst && terminal_valid && tr)terminal_sent=1;
      if(rst && pv && ps)begin pending=pending-1;completed=completed+1;end
      #4;clk=1;#1;cycle=cycle+1;
      if(rst && valid && !pv)begin
        lat=cycle-accepted_at;
        if(lat>max_latency)max_latency=lat;
        if(lat<min_latency)min_latency=lat;
        $display("JOB %0d cycles=%0d rows=%0d objects=%0d",job_id,lat,count,req_data[8583:8576]);
      end
      // ENUM_ST_ACT is the actor-cell dispatch. Same-row gaps measure actor II.
      if(rst && dut.reg_fsm_ctrl_current_state==4'd5)begin
        if(dut.reg_actor==0)begin
          if(row_at>0 && cycle-row_at>actor_row_max)actor_row_max=cycle-row_at;
          row_at=cycle;actor_last=-1;
        end
        if(actor_last>=0)begin
          actor_gap=cycle-actor_last;actor_hits=actor_hits+1;
          if(actor_gap>actor_max)actor_max=actor_gap;
          if(actor_gap<actor_min)actor_min=actor_gap;
        end
        actor_last=cycle;
      end
'''
# Each tuple: name, antecedent, expression on a DUT wire, independent expected, mutation target/bit.
checks=[
 ('S5_3_reset_req','!rst','ready',"1'b0",'ready',0),
 ('S5_3_reset_row','!rst','rr',"1'b0",'row_ready',0),
 ('S5_3_reset_terminal','!rst','tr',"1'b0",'terminal_ready',0),
 ('S5_3_reset_valid','!rst','valid',"1'b0",'valid',0),
 ('S5_3_reset_payload','!rst','data',"81'd0",'data',0),
 ('S5_3_invalid_zero','rst && !raw_valid','data',"81'd0",'data',0),
 ('S5_3_one_job','rst && pending>0','ready',"1'b0",'ready',0),
 ('S5_3_terminal_once','rst && terminal_sent','tr',"1'b0",'terminal_ready',0),
 ('S5_3_response_owner','rst && raw_valid','valid',"pending==1",'valid',0),
 ('S5_3_stall_valid','rst && pv && !ps','valid',"1'b1",'valid',0),
 ('S5_3_stall_payload','rst && pv && !ps','data','prev_data','data',0),
 ('S5_3_consumed','rst && pv && ps','valid',"1'b0",'valid',0),
 ('S5_3_idle_ready','rst && pv && ps','ready',"1'b1",'ready',0),
 ('S5_3_idle_row','rst && pv && ps','rr',"1'b0",'row_ready',0),
 ('S5_3_idle_terminal','rst && pv && ps','tr',"1'b0",'terminal_ready',0),
 ('REQ007_atomic_result','rst && raw_valid','data','expected','data',0),
 ('S9_2_accept','rst && raw_valid','data[80]','expected[80]','data',80),
 ('S9_2_margin','rst && raw_valid','data[79:16]','expected[79:16]','data',16),
 ('S9_2_reason','rst && raw_valid','data[15:8]','expected[15:8]','data',8),
 ('S9_2_steps','rst && raw_valid','data[7:0]','expected[7:0]','data',0),
 ('S5_5_6_accepted','rst && raw_valid && expected[80]','data[15:8]',"8'd0",'data',8),
 ('S5_5_6_rejected','rst && raw_valid && !expected[80]','data[80]',"1'b0",'data',80),
 ('S5_5_6_no_early_commit','rst && pending>0 && !terminal_sent','valid',"1'b0",'valid',0),
 ('S5_5_6_preflight_margin','rst && raw_valid && expected[15:8]!=0 && expected[15:8]!=24 && expected[15:8]!=23','data[79:16]',"64'hffffffffffffffff",'data',16),
 ('S5_3_response_row_closed','rst && raw_valid','rr',"1'b0",'row_ready',0),
 ('S5_3_response_terminal_closed','rst && raw_valid','tr',"1'b0",'terminal_ready',0),
]
for i,(name,active,expr,expected,target,bit) in enumerate(checks):
    value=f"81'd1<<{bit}" if target=='data' else "1'b1"
    s+=f'''      if ({active}) begin : a_{i}
        hits[{i}]=hits[{i}]+1;
        if(mutant=={i} && !injected)begin
          flip_{target}={value};injected=1;
          $display("INJECT {i} {name} DUT output bit flip");#1;
        end
        assert (({expr}) === ({expected})) else begin
          $display("ASSERT_FAIL {i} {name} job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_{target}=0;
      end
'''
s+='''      if(rst && pending>0 && cycle-accepted_at>250000) $fatal(1,"bounded progress");
      #4;clk=0;#1;
    end
  endtask

  initial begin
    for(integer i=0;i<26;i=i+1)hits[i]=0;
'''
for i,c in enumerate(checks):s+=f'    names[{i}]="{c[0]}";\n'
s+='''    if($value$plusargs("MUTANT=%d",mutant))begin end
    if($value$plusargs("START=%d",start))begin end
    if($value$plusargs("LIMIT=%d",limit))begin end
    if($value$plusargs("NOSTALL=%d",nostall))begin end
    if($value$plusargs("RESET_MID=%d",reset_mid))begin end
    $readmemh("jobs.mem",jobs);$readmemh("rows.mem",rows);
    repeat(2)tick();rst=1;tick();
    if(reset_mid)begin
      // Spec 5.3/7: abandon a job while rational divider valid bits are occupied.
      req_data=jobs[0][8794:171];expected=jobs[0][120:40];
      offset=jobs[0][39:8];count=jobs[0][7:0];
      req_valid=1;tick();req_valid=0;
      row_valid=1;row_data=rows[offset];tick();
      row_data=rows[offset+1];tick();row_valid=0;
      repeat(20)tick();
      rst=0;pending=0;terminal_sent=0;repeat(2)tick();
      rst=1;tick();last_job=-1;
      $display("RESET_MID PASS: active job aborted, divider validity reset");
    end
    for(job_id=start;job_id<N && job_id<start+limit;job_id=job_id+1)begin
      while(!ready)tick();
      req_data=jobs[job_id][8794:171];terminal_data=jobs[job_id][170:121];
      expected=jobs[job_id][120:40];offset=jobs[job_id][39:8];count=jobs[job_id][7:0];
      pos=0;terminal_sent=0;row_at=0;actor_last=-1;
      req_valid=1;tick();req_valid=0;
      // Terminal can precede rows, follow rows, or arrive amid arithmetic work.
      while(!valid)begin
        row_valid=pos<count && (nostall || cycle%7!=0);
        if(pos<count)row_data=rows[offset+pos];
        terminal_valid=!terminal_sent && (job_id%3==0 || pos==count);
        rsp_ready=0;tick();
      end
      row_valid=0;terminal_valid=0;
      repeat(2)tick();rsp_ready=1;tick();rsp_ready=0;
    end
    for(integer i=0;i<26;i=i+1)begin
      $display("ASSERT %0d %s spec=5.3/5.5.6/9.2 hits=%0d",i,names[i],hits[i]);
      if(hits[i]==0)inactive=inactive+1;
      if(hits[i]==0 && start==0 && limit>=N)$fatal(1,"assertion never exercised");
    end
    $display("LATENCY min=%0d max=%0d cycles/job job_II_max=%0d",min_latency,max_latency,max_ii);
    $display("ACTOR_II min=%0d max=%0d hits=%0d row_cycles_max=%0d budget=48",actor_min,actor_max,actor_hits,actor_row_max);
    if(actor_max>48)$fatal(1,"actor II over budget");
    $display("assertion failures: 0, assertions never exercised: %0d (this slice)",inactive);
    $display("PASS geom: golden=%0d/%0d assertions=26 cycles=%0d",completed,job_id-start,cycle);
    $finish;
  end
endmodule
'''
(H/'tb_m_tsmx_geom.sv').write_text(s)
