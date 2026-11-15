"""Generate explicit named SV assertions; oracle is gen_vectors.py, never RTL."""
# Project: TSM-X; Author: TSMX project; Version: 0.1.
from pathlib import Path
P=Path(__file__).resolve().parent
checks=[
('reset_ready','!rst',"ready === 1'b0",'ready'),
('reset_valid','!rst',"valid === 1'b0",'valid'),
('reset_data','!rst',"data === 8'd0",'data'),
('invalid_zero','!valid',"data === 8'd0",'data'),
('ready_known','rst','!$isunknown(ready)','ready'),
('valid_known','rst','!$isunknown(valid)','valid'),
('valid_data_known','rst && valid','!$isunknown(data)','data'),
('single_outstanding','rst && valid',"ready === 1'b0",'ready'),
('bounded_completion','rst && outstanding && cycles-start_cycle>=3',"valid === 1'b1",'valid'),
('atomic_status','rst && valid','data === pending_exp','data'),
('stall_valid','rst && pv && !pc',"valid === 1'b1",'valid'),
('stall_payload','rst && pv && !pc','data === pd','data'),
('stall_blocks_request','rst && pv && !pc',"ready === 1'b0",'ready'),
('consume_valid','rst && pv && pc',"valid === 1'b0",'valid'),
('consume_payload','rst && pv && pc',"data === 8'd0",'data'),
('no_unsolicited','rst && !outstanding && !take',"valid === 1'b0",'valid'),
('idle_ready','rst && pr && !pq',"ready === 1'b1",'ready'),
('reset_release_ready','rst && boot',"ready === 1'b1",'ready')]
for name,v in [('ok',0),('timeout',3),('binding',25),('replay',26),('context',27),('lease',28),('executor_expiry',29),('ack_timeout',30),('committed',31),('pending',32),('late_apply',33),('expiry',34)]:
    checks.append((name,f'rst && valid && pending_exp==8\'d{v}',f"data === 8'd{v}",'data'))
# Unknown tests need deterministic 2-state-compatible fault injection: flip Boolean
# into non-Boolean? For known checks use concrete relation checks instead of X.
checks[4]=('ready_qualified','rst && !outstanding && pr',"ready === 1'b1",'ready')
checks[5]=('response_accounted','rst && valid',"valid === 1'b1 && outstanding",'valid')
checks[6]=('status_encoding','rst && valid','data <= 8\'d34 && data != 8\'d35','data')
n=len(checks)
s='''`timescale 1ns/1ps
// TSM-X / TSMX project / v0.1. REQ-TSMX-010/020, spec5.3/5.5.9/6.2/9.
// Output-wire XOR mutants change actual DUT outputs, never expected values.
module tb_m_tsmx_cert;
  reg clk=0,rst=0,req_valid=0,rsp_ready=0;
  reg [2903:0] req_data=0;
  wire raw_ready,raw_valid; wire [7:0] raw_data;
  reg flip_ready=0,flip_valid=0; reg [7:0] flip_data=0;
  wire ready=raw_ready ^ flip_ready, valid=raw_valid ^ flip_valid;
  wire [7:0] data=raw_data ^ flip_data;
  integer mutant=-1,injected=0,cycles=0,start_cycle=0,previous_start=-1;
  integer latency_min=1000,latency_max=0,ii_min=1000,ii_max=0;
  integer requests=0,responses=0,wait_count=0,latency,ii;
  reg pr,pv,pq,pc,take,boot=1,outstanding=0,seen=0;
  reg [7:0] pd,pending_exp=0,expected=0;
  `include "vectors_meta.svh"
  reg [2911:0] vectors[0:N-1];
'''+f'  integer hits[0:{n-1}];\n  string names[0:{n-1}];\n'+'''
  m_tsmx_cert dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_rsp_ready(rsp_ready),.o_req_ready(raw_ready),.o_rsp_valid(raw_valid),.o_rsp_data(raw_data)
  );
  task tick;
    begin
      pr=ready;pv=valid;pq=req_valid;pc=rsp_ready;pd=data;
      take=rst && pr && pq;
      if (take) begin
        if(outstanding) $fatal(1,"duplicate acceptance");
        outstanding=1;pending_exp=expected;start_cycle=cycles+1;seen=0;
        if(previous_start>=0) begin
          ii=cycles+1-previous_start;
          if(ii<ii_min) ii_min=ii;
          if(ii>ii_max) ii_max=ii;
        end
        previous_start=cycles+1;requests++;
      end
      if(rst && pv && pc) begin outstanding=0;responses++;end
      if(!rst) begin outstanding=0;seen=0;end
      #4;clk=1;#1;cycles++;
      if(rst && valid && !seen) begin
        latency=cycles-start_cycle+1;seen=1;
        if(latency<latency_min) latency_min=latency;
        if(latency>latency_max) latency_max=latency;
      end
'''
for i,(name,ante,cons,wire) in enumerate(checks):
    clause='5.3' if i<18 else '5.5.9/6.2'
    # status encoding mutant toggles high bit; other data mutants flip low bit.
    mask="8'h80" if i==6 else "8'h01"
    s+=f'''      if ({ante}) begin : A_{name}
        hits[{i}]++;
        if(mutant=={i} && !injected) begin
          flip_{wire}={mask if wire=='data' else "1'b1"};injected=1;
          $display("INJECT {i} {name}");#0.001;
        end
        assert ({cons}) else begin
          $display("ASSERT_FAIL {i} {name} spec{clause} cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
'''
s+='''      boot=!rst;
      #5;clk=0;#1;
    end
  endtask
  task reset_dut;
    begin
      rst=0;req_valid=0;rsp_ready=0;
      #1;tick;tick;rst=1;tick;
    end
  endtask
  task wait_ready;
    begin
      wait_count=0;
      while(!ready && wait_count<10) begin tick;wait_count++;end
      if(!ready) $fatal(1,"request timeout");
    end
  endtask
  task send_job(input integer idx,input integer stalls);
    begin
      wait_ready;req_data=vectors[idx][2911:8];expected=vectors[idx][7:0];
      req_valid=1;tick;req_valid=0;wait_count=0;
      while(!valid && wait_count<10) begin req_data=~req_data;tick;wait_count++;end
      if(!valid) $fatal(1,"response timeout job%0d",idx);
      if(data!==expected) $fatal(1,"bit exact mismatch job%0d got%h expected%h",idx,data,expected);
      repeat(stalls) begin req_data=~req_data;tick;end
      rsp_ready=1;tick;rsp_ready=0;
    end
  endtask
  initial begin
'''
for i,(name,*_) in enumerate(checks): s+=f'    hits[{i}]=0;names[{i}]="{name}";\n'
s+='''    if($value$plusargs("MUTANT=%d",mutant)) begin end
    $readmemh("vectors.mem",vectors);
    reset_dut;tick;$display("BOOT complete");
    // Reset in every elapsed pipeline phase; no old result may escape afterward.
    for(integer phase=0;phase<3;phase++) begin
      wait_ready;req_data=vectors[0][2911:8];expected=vectors[0][7:0];req_valid=1;
      tick;req_valid=0;repeat(phase) tick;
      reset_dut;repeat(6) tick;
    end
    // Reset while holding a response and with a waiting request producer.
    wait_ready;req_data=vectors[0][2911:8];expected=vectors[0][7:0];req_valid=1;tick;
    req_valid=0;repeat(4) tick;reset_dut;repeat(6) tick;
    // A producer waits behind a stalled response, then is accepted exactly once.
    wait_ready;req_data=vectors[0][2911:8];expected=vectors[0][7:0];req_valid=1;
    tick;req_valid=0;repeat(3) tick;
    req_data=vectors[1][2911:8];expected=vectors[1][7:0];req_valid=1;
    repeat(3) tick;
    rsp_ready=1;tick;rsp_ready=0;tick;req_valid=0;
    repeat(3) tick;rsp_ready=1;tick;rsp_ready=0;
    previous_start=-1;latency_min=1000;latency_max=0;ii_min=1000;ii_max=0;
    for(integer j=0;j<N;j++) begin
      send_job(j,j%4);
      if(j%1000==0) $display("PROGRESS cert job=%0d cycles=%0d",j,cycles);
    end
    repeat(3) tick;
'''
for i in range(n): s+=f'    $display("ASSERT {i} %s hits=%0d failures=0",names[{i}],hits[{i}]);\n    if(hits[{i}]==0) $fatal(1,"assertion never exercised");\n'
s+='''    if(mutant>=0) $fatal(1,"mutant survived");
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("cycles per job=%0d..%0d measured II=%0d..%0d (includes injected stalls)",latency_min,latency_max,ii_min,ii_max);
    $display("PASS cert: golden=%0d/%0d assertions=30/30",N,N);
    $finish;
  end
endmodule
'''
P.joinpath('tb_m_tsmx_cert.sv').write_text(s)
