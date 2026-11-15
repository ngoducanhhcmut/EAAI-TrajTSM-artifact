"""Emit portable immediate assertions and output-wire fault injection (v0.1)."""
from pathlib import Path
HERE=Path(__file__).resolve().parent
# Each tuple is a spec-derived assertion, activation, observed condition, mutated wire.
checks=[
 ('reset_ready','!rst',"ready === 1'b0",'ready'),
 ('reset_valid','!rst',"valid === 1'b0",'valid'),
 ('reset_data','!rst',"data === 1'b0",'data'),
 ('invalid_zero','rst && !raw_valid',"data === 1'b0",'data'),
 ('response_excludes_ready','rst && raw_valid',"ready === 1'b0",'ready'),
 ('response_has_context','rst && raw_valid',"valid && pending",'valid'),
 ('golden_exact','rst && raw_valid','data === pending_exp','data'),
 ('stall_valid','rst && pv && !pc',"valid === 1'b1",'valid'),
 ('stall_payload','rst && pv && !pc','data === pd','data'),
 ('stall_blocks_request','rst && pv && !pc',"ready === 1'b0",'ready'),
 ('consume_clears_valid','rst && pv && pc',"valid === 1'b0",'valid'),
 ('consume_clears_payload','rst && pv && pc',"data === 1'b0",'data'),
 ('idle_ready','rst && pr && !pq',"ready === 1'b1",'ready'),
 ('no_unsolicited','rst && !pending && !pv',"valid === 1'b0",'valid'),
 ('bounded_busy','rst && pending && !raw_valid','!ready && age<=12288','ready'),
 ('accept_blocks_replacement','rst && take',"ready === 1'b0",'ready'),
 ('contained_accept','rst && raw_valid && pending_exp',"data === 1'b1",'data'),
 ('rejected_clear','rst && raw_valid && !pending_exp',"data === 1'b0",'data'),
 ('release_no_stale','rst && released',"valid === 1'b0",'valid'),
 ('queued_request_cannot_replace','rst && pv && !pc && pq','data === pd','data'),
 ('busy_request_backpressure','rst && pending && !raw_valid && pq',"ready === 1'b0",'ready'),
 ('work_has_no_payload','rst && pending && !raw_valid',"data === 1'b0",'data'),
 ('response_count','rst && raw_valid','valid && requests==responses+1','valid'),
 ('reset_release_ready','rst && released',"ready === 1'b1",'ready'),
]
head='''`timescale 1ns/1ps
// Project TSM-X; author TSMX project; version0.1.
// Spec5.3/7/9.2/10.3 and REQ-TSMX-005; expected results from unmodified golden.
// Fault injection flips DUT-driven observation wires, never expected values.
module tb_m_tsmx_splice;
  reg clk=0,rst=0,req_valid=0,rsp_ready=0;
  reg [815:0] req_data=0;
  wire raw_ready,raw_valid,raw_data;
  reg flip_ready=0,flip_valid=0,flip_data=0;
  wire ready=raw_ready ^ flip_ready;
  wire valid=raw_valid ^ flip_valid;
  wire data=raw_data ^ flip_data;
  reg expected=0,pending_exp=0,pending=0;
  reg pr,pv,pq,pc,pd,take,released=0;
  integer hits[0:23];
  integer mutant=-1,injected=0,cycles=0,requests=0,responses=0,age=0;
  integer latency_min=99999,latency_max=0,last_accept=-1,ii_min=99999,ii_max=0;
  integer start_cycle,delay_cycles,lim,job_cycles,first=0,fast_start,fast_prev;
  `include "vectors_meta.svh"
  reg [816:0] vectors[0:N-1];
  m_tsmx_splice dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_rsp_ready(rsp_ready),.o_req_ready(raw_ready),.o_rsp_valid(raw_valid),
    .o_rsp_data(raw_data)
  );
  task tick;
    begin
      pr=raw_ready;pv=raw_valid;pq=req_valid;pc=rsp_ready;pd=raw_data;
      take=rst && pr && pq;
      if(!rst) begin pending=0;age=0;end
      if(rst && pv && pc) begin pending=0;responses=responses+1;end
      if(take) begin
        pending=1;pending_exp=expected;requests=requests+1;age=0;
        if(last_accept>=0) begin
          if(cycles-last_accept<ii_min) ii_min=cycles-last_accept;
          if(cycles-last_accept>ii_max) ii_max=cycles-last_accept;
        end
        last_accept=cycles;
      end
      if(pending) age=age+1;
      #4;clk=1;#1;cycles=cycles+1;
'''
body=''
for i,(name,ante,cons,wire) in enumerate(checks):
    body+=f'''      if ({ante}) begin : A{i:02}_{name}
        hits[{i}]=hits[{i}]+1;
        if(mutant=={i} && !injected) begin
          flip_{wire}=1;injected=1;#1;
          $display("INJECT {i} {name}: flipped DUT output {wire}");
        end
        assert ({cons}) else begin
          $display("ASSERT_FAIL {i} {name} cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
'''
tail='''      if(rst && raw_valid && !pv) begin
        if(age<latency_min) latency_min=age;
        if(age>latency_max) latency_max=age;
      end
      released=0;
      #5;clk=0;#1;
    end
  endtask
  task reset_dut;
    begin
      rst=0;req_valid=0;rsp_ready=0;tick;tick;
      // Reset aborts the scoreboard's old transaction as well as the DUT.
      responses=requests;rst=1;released=1;tick;
    end
  endtask
  task wait_ready;
    begin
      delay_cycles=0;
      while(!raw_ready && delay_cycles<12290) begin tick;delay_cycles=delay_cycles+1;end
      if(!raw_ready) $fatal(1,"ready timeout");
    end
  endtask
  task wait_response;
    begin
      delay_cycles=0;
      while(!raw_valid && delay_cycles<12288) begin tick;delay_cycles=delay_cycles+1;end
      assert(raw_valid) else $fatal(1,"spec10.3 bounded response");
    end
  endtask
  initial begin
    for(integer j=0;j<24;j=j+1) hits[j]=0;
    if($value$plusargs("MUTANT=%d",mutant)) begin end
    lim=N;if($value$plusargs("LIMIT=%d",lim)) begin end
    if($value$plusargs("START=%d",first)) begin end
    $readmemh("vectors.mem",vectors);
    reset_dut;tick;
    for(integer j=first;j<first+lim;j=j+1) begin
      wait_ready;
      req_data=vectors[j][816:1];expected=vectors[j][0];
      req_valid=1;rsp_ready=0;start_cycle=cycles;tick;
      // Hold a second request while the first is outstanding. Then change the
      // invalid bus to prove the accepted snapshot, keeping valid-low legal.
      repeat(2) tick;
      req_valid=0;req_data=~req_data;
      wait_response;job_cycles=cycles-start_cycle;
      $display("JOB %0d cycles=%0d accept=%b",j,job_cycles,data);
      repeat(2) tick;
      req_valid=1;tick;req_valid=0;
      rsp_ready=1;tick;rsp_ready=0;tick;
    end
    // Measure the public II with continuously offered same-job requests and
    // no consumer stalls, for both a complete corner sweep and a guard reject.
    for(integer kind=0;kind<2;kind=kind+1) begin
      fast_prev=-1;
      for(integer j=0;j<3;j=j+1) begin
        wait_ready;req_data=vectors[kind==0 ? 0 : GOLDEN][816:1];
        expected=vectors[kind==0 ? 0 : GOLDEN][0];req_valid=1;rsp_ready=1;
        fast_start=cycles;tick;wait_response;
        $display("UNSTALLED kind=%0d latency=%0d II=%0d",kind,cycles-fast_start,fast_prev<0 ? 0 : fast_start-fast_prev);
        fast_prev=fast_start;tick;
      end
      req_valid=0;rsp_ready=0;tick;
    end
    // Reset at different private divider phases, followed by a long stale drain.
    for(integer j=0;j<12;j=j+1) begin
      wait_ready;req_data=vectors[0][816:1];expected=vectors[0][0];
      req_valid=1;tick;req_valid=0;
      repeat(j+1) tick;
      reset_dut;repeat(25) tick;
    end
'''
for i,(name,*_) in enumerate(checks):
    tail+=f'    $display("ASSERT_HITS {i} {name} spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[{i}]);\n'
tail+='''    for(integer j=0;j<24;j=j+1) if(hits[j]==0) $fatal(1,"assertion never exercised %0d",j);
    if(mutant>=0) $fatal(1,"mutant survived");
    $display("LATENCY min=%0d max=%0d II min=%0d max=%0d (includes programmed stalls/idle)",latency_min,latency_max,ii_min,ii_max);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS splice: golden=%0d/%0d start=%0d assertions=24 cycles=%0d",lim,lim,first,cycles);
    $finish;
  end
  initial begin #1000000000;$fatal(1,"watchdog timeout");end
endmodule
'''
(HERE/'tb_m_tsmx_splice.sv').write_text(head+body+tail)
