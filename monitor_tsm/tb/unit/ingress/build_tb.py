"""Emit explicit portable immediate assertions; clauses from spec5.3/5.5.3/7/9.2."""
from pathlib import Path
import json
H=Path(__file__).resolve().parent
checks=[
('reset_ready','!rst',"ready===1'b0",'ready',0),
('reset_valid','!rst',"valid===1'b0",'valid',0),
('reset_data','!rst',"data==='0",'data',0),
('invalid_zero','rst && !valid',"data==='0",'data',0),
('single_outstanding','rst && valid',"ready===1'b0",'ready',0),
('accept_blocks_req','rst && take',"ready===1'b0",'ready',0),
('bounded_progress','rst && pending && cycles-accepted==3',"valid===1'b1",'valid',0),
('stall_valid','rst && pv && !pc',"valid===1'b1",'valid',0),
('stall_data','rst && pv && !pc',"data===pd",'data',0),
('stall_blocks_req','rst && pv && !pc',"ready===1'b0",'ready',0),
('consume_valid','rst && pv && pc',"valid===1'b0",'valid',0),
('consume_data','rst && pv && pc',"data==='0",'data',0),
('no_unsolicited','rst && !pending && !pv && !take',"valid===1'b0",'valid',0),
('idle_ready','rst && pr && !pq',"ready===1'b1",'ready',0),
('reject_atomic','rst && valid && pending_exp[7:0]!=0',"data[339:8]===saved_req[1373:1042]",'data',8),
('full_response','rst && valid',"data===pending_exp",'data',0),
('seq_valid','rst && valid && pending_exp[7:0]==0',"data[339]===1'b1",'data',339),
('seq','rst && valid && pending_exp[7:0]==0',"data[338:307]===saved_req[752:721]",'data',307),
('time_valid','rst && valid && pending_exp[7:0]==0',"data[306]===1'b1",'data',306),
('last_time','rst && valid && pending_exp[7:0]==0',"data[305:274]===saved_req[1041:1010]",'data',274),
('sample_valid','rst && valid && pending_exp[7:0]==0',"data[273]===1'b1",'data',273),
('last_sample','rst && valid && pending_exp[7:0]==0',"data[272:241]===saved_req[720:689]",'data',241),
('sig_valid','rst && valid && pending_exp[7:0]==0',"data[240]===1'b1",'data',240),
('signature','rst && valid && pending_exp[7:0]==0',"data[239:104]===saved_req[400:265]",'data',104),
('freeze_epoch','rst && valid && pending_exp[7:0]==0',"data[103:72]===pending_exp[103:72]",'data',72),
('freeze_position','rst && valid && pending_exp[7:0]==0',"data[71:8]===pending_exp[71:8]",'data',8),
('reason','rst && valid',"data[7:0]===pending_exp[7:0]",'data',0),
]
text='''`timescale 1ns/1ps
// TSM-X / TSMX project / v0.1. Custom project channels, spec5.3/5.5.3/7/9.2.
// Mutants corrupt actual DUT output wires; oracle and assertion predicates are untouched.
module tb_m_tsmx_ingress;
  reg clk=0,rst=0,req_valid=0,rsp_ready=0;
  reg [1373:0] req_data=0,saved_req=0;
  wire raw_ready,raw_valid;
  wire [339:0] raw_data;
  reg flip_ready=0,flip_valid=0;
  reg [339:0] flip_data=0;
  wire ready=raw_ready ^ flip_ready;
  wire valid=raw_valid ^ flip_valid;
  wire [339:0] data=raw_data ^ flip_data;
  reg [339:0] expected=0,pending_exp=0,pd;
  reg pr,pv,pq,pc,take,pending=0;
  integer cycles=0,accepted=0,previous_accept=-1,last_response=0;
  integer latency_min=999,latency_max=0,ii_min=999,ii_max=0;
  integer jobs=0,completed=0,aborted=0,age=0;
  integer mutant=-1,injected=0;
  integer hits[0:26];
  `include "vectors_meta.svh"
  reg [1713:0] vectors[0:N-1];
  m_tsmx_ingress dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_rsp_ready(rsp_ready),.o_req_ready(raw_ready),.o_rsp_valid(raw_valid),.o_rsp_data(raw_data)
  );
  task tick;
    integer lat;
    begin
      pr=ready;pv=valid;pq=req_valid;pc=rsp_ready;pd=data;take=rst && pr && pq;
      if(take) begin
        if(pending) $fatal(1,"second outstanding request");
        saved_req=req_data;pending_exp=expected;pending=1;jobs++;
        accepted=cycles+1;
        if(previous_accept>=0) begin
          if(cycles+1-previous_accept<ii_min) ii_min=cycles+1-previous_accept;
          if(cycles+1-previous_accept>ii_max) ii_max=cycles+1-previous_accept;
        end
        previous_accept=cycles+1;
      end
      if(rst && pv && pc) begin pending=0;completed++;end
      if(!rst) begin
        if(pending) aborted++;
        pending=0;previous_accept=-1;
      end
      #4;clk=1;#1;cycles++;
      if(rst && valid && !pv) begin
        lat=cycles-accepted+1;
        if(lat<latency_min) latency_min=lat;
        if(lat>latency_max) latency_max=lat;
        $display("JOB %0d cycles=%0d latency=%0d",jobs,cycles,lat);
      end
'''
for n,(name,cond,expr,signal,bit) in enumerate(checks):
 clause='5.5.3/9.2' if n>=14 else '5.3/7'
 mutation=f'flip_data[{bit}]=1;' if signal=='data' else f'flip_{signal}=1;'
 text+=f'''      if({cond}) begin : A{n:02}_{name}
        hits[{n}]++;
        if(mutant=={n} && !injected) begin
          {mutation} injected=1;#1;
          $display("INJECT {n} {name} output bit inversion");
        end
        assert ({expr}) else begin
          $display("ASSERT_FAIL {n} {name} spec{clause} job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
'''
text+='''      if(rst && pending && !valid && cycles-accepted>8) $fatal(1,"bounded progress");
      #5;clk=0;#1;
    end
  endtask
  task reset_dut;
    begin rst=0;req_valid=0;rsp_ready=0;#1;tick;tick;rst=1;tick;end
  endtask
  task wait_ready;
    begin
      age=0;
      while(!ready && age<12) begin tick;age++;end
      if(!ready) $fatal(1,"request timeout");
    end
  endtask
  task wait_response;
    begin
      age=0;
      while(!valid && age<12) begin tick;age++;end
      if(!valid) $fatal(1,"response timeout");
    end
  endtask
  initial begin
    for(integer j=0;j<27;j++) hits[j]=0;
    if($value$plusargs("MUTANT=%d",mutant)) begin end
    $readmemh("vectors.mem",vectors);
    reset_dut;tick;
    for(integer j=0;j<N;j++) begin
      wait_ready;
      {req_data,expected}=vectors[j];req_valid=1;rsp_ready=0;tick;
      req_valid=0;req_data=~req_data;
      wait_response;
      // Changing unaccepted input and asserted valid must never alter this result.
      if(j%7==0) begin
        repeat(3) begin req_data=~req_data;req_valid=1;tick;end
        req_valid=0;
      end
      rsp_ready=1;tick;rsp_ready=0;
    end
    // Reset at every age: acceptance, arithmetic setup, return, and stalled response.
    for(integer phase=0;phase<5;phase++) begin
      wait_ready;{req_data,expected}=vectors[0];req_valid=1;tick;req_valid=0;
      repeat(phase) tick;
      reset_dut;repeat(10) tick;
    end
    for(integer j=0;j<27;j++) begin
      $display("ASSERT_HITS %0d hits=%0d",j,hits[j]);
      if(hits[j]==0) $fatal(1,"assertion never exercised %0d",j);
    end
    if(mutant>=0) $fatal(1,"mutant survived %0d",mutant);
    if(jobs!=completed+aborted) $fatal(1,"job conservation");
    $display("MEASURE latency=%0d..%0d cycles/job II=%0d..%0d cycles stalls included",latency_min,latency_max,ii_min,ii_max);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS ingress: golden=%0d/%0d edges=%0d/%0d extra=%0d/%0d assertions=27 jobs=%0d completed=%0d aborted=%0d cycles=%0d",GOLDEN,GOLDEN,EDGES,EDGES,EXTRA,EXTRA,jobs,completed,aborted,cycles);
    $finish;
  end
  initial begin #10000000;$fatal(1,"watchdog timeout");end
endmodule
'''
(H/'tb_m_tsmx_ingress.sv').write_text(text)
(H/'assertions.json').write_text(json.dumps([dict(id=i,name=c[0],clause='spec5.5.3/9.2' if i>=14 else 'spec5.3/7',mutant_signal=c[3],mutant_bit=c[4]) for i,c in enumerate(checks)],indent=2)+'\n')
