"""Emit explicit immediate assertions, portable to Icarus and Verilator5."""
from pathlib import Path
HERE=Path(__file__).resolve().parent
checks=[
('reset_ready','!rst',"ready === 1'b0",'ready'),
('reset_valid','!rst',"valid === 1'b0",'valid'),
('reset_data','!rst',"data === 289'd0",'data'),
('invalid_zero','rst && !valid',"data === 289'd0",'data'),
('ready_known','rst','!$isunknown(ready)','ready'),
('valid_known','rst','!$isunknown(valid)','valid'),
('response_known','rst && valid','!$isunknown(data)','data'),
('no_ready_response','rst && valid',"ready === 1'b0",'ready'),
('stall_valid','rst && stalled',"valid === 1'b1",'valid'),
('stall_payload','rst && stalled','data === held','data'),
('crc_no_digest','rst && valid && !expected[288] && (op==0 || op==5)',"data[255:0] === 256'd0",'data'),
('sha_no_crc','rst && valid && !expected[288] && !(op==0 || op==5)',"data[287:256] === 32'd0",'data'),
('fault_zero','rst && valid && expected[288]',"data[287:0] === 288'd0",'data'),
('fault_exact','rst && valid','data[288] === expected[288]','data'),
('crc_exact','rst && valid && (op==0 || op==5)','data[287:256] === expected[287:256]','data')]
for i in range(8):
    h=255-32*i;l=h-31
    checks.append((f'sha_word_{i}','rst && valid && !(op==0 || op==5)',f'data[{h}:{l}] === expected[{h}:{l}]','data'))
checks += [
('progress','rst && pending && age>bound+pauses+4',"valid === 1'b1",'valid'),
('no_early_response','rst && pending && !last_seen && !expected[288]',"valid === 1'b0",'valid'),
('last_blocks_input','rst && pending && last_seen',"ready === 1'b0",'ready'),
('response_has_job','rst && !pending',"valid === 1'b0",'valid'),
('whole_response','rst && valid','data === expected','data'),
('crc_fault_zero','rst && valid && expected[288]',"data[287:256] === 32'd0",'data'),
('reset_inflight','!rst && cancel_test',"valid === 1'b0 && ready === 1'b0 && data === 289'd0",'valid')]
# Progress is exercised at its guaranteed completion deadline by a delayed consumer check.
checks[23]=('bounded_response','rst && pending && age==bound+pauses+4',"valid === 1'b1",'valid')
s='''`timescale 1ns/1ps
// Project TSM-X; author TSMX project; version0.1. Oracle: S1b spec5.5.2/9.2.
// All assertions cite project valid/ready spec5.3, reset7 or codec5.5.2/10.3.
// Mutants alter actual DUT outputs with verification-only force, as in accepted sel TB.
module tb_m_tsmx_codec;
  reg clk=0,rst=0,req_valid=0,rsp_ready=0;
  reg [44:0] req_data=0;
  wire ready,valid;
  wire [288:0] data;
  `include "vectors_meta.svh"
  reg [360:0] jobs[0:N-1];
  reg [44:0] beats[0:B-1];
  reg [288:0] expected=0,held=0;
  reg pending=0,last_seen=0,stalled=0,cancel_test=0;
  reg [7:0] op=0;
  reg pr,pv;
  integer age=0,pauses=0,bound=0,cycles=0,mutant=-1,injected=0,current_job=-1,no_gaps=0;
  integer hits[0:29];
  integer cursor=0,nb=0,len=0,passed=0,waited=0,stall_cycles=0;
  integer max_latency[0:6];
  m_tsmx_codec dut(.i_clk_core(clk),.i_rst_n_core(rst),
    .i_req_valid(req_valid),.i_req_data(req_data),.i_rsp_ready(rsp_ready),
    .o_req_ready(ready),.o_rsp_valid(valid),.o_rsp_data(data));
  task tick;
    begin
      #1;
      pr=ready;pv=valid;
'''
for i,(name,ante,cons,net) in enumerate(checks):
    s+=f'''      if ({ante}) begin : S_{name}
        hits[{i}]=hits[{i}]+1;
        if (mutant=={i} && !injected) begin
          force {net}='x;
          injected=1;
          $display("INJECT {i} {name}: DUT output {net} stuck-X");
          #1;
        end
        assert ({cons}) else begin
          $display("ASSERT_FAIL {i} {name} spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
'''
s+='''      stalled=rst && pv && !rsp_ready;
      held=data;
      if (rst && pending) begin
        age=age+1;
        if (!last_seen && !req_valid && pr) pauses=pauses+1;
      end
      if (rst && req_valid && pr) begin
        if (!pending) begin pending=1;age=0;pauses=0;last_seen=0;end
        if (req_data[35]) last_seen=1;
      end
      if (rst && valid && rsp_ready) pending=0;
      #3;clk=1;#1;clk=0;#1;
      cycles=cycles+1;
      if (!rst) begin pending=0;last_seen=0;stalled=0;end
    end
  endtask
  task reset_dut;
    begin
      rst=0;req_valid=0;rsp_ready=0;tick;tick;
      rst=1;tick;
    end
  endtask
  initial begin
    for (integer j=0;j<30;j=j+1) hits[j]=0;
    for (integer j=0;j<7;j=j+1) max_latency[j]=0;
    if ($value$plusargs("MUTANT=%d",mutant)) begin end
    if ($test$plusargs("NOGAPS")) no_gaps=1;
    $readmemh("jobs.mem",jobs);
    $readmemh("beats.mem",beats);
    reset_dut;
    // Cancel a partial SHA job with reset, then reset a complete stalled response.
    op=6;bound=100;
    req_valid=1;req_data={8'd6,1'b1,1'b0,3'd4,32'h61626364};tick;
    cancel_test=1;reset_dut;cancel_test=0;
    // Reset with the compressor active and the final padding queued.
    op=6;bound=152;
    for (integer k=0;k<16;k=k+1) begin
      req_data={8'd6,(k==0),(k==15),3'd4,32'd0};req_valid=1;tick;
    end
    req_valid=0;repeat (8) tick;
    cancel_test=1;reset_dut;cancel_test=0;
    for (integer j=0;j<N;j=j+1) begin
      current_job=j;
      nb=jobs[j][360:329];len=jobs[j][328:297];op=jobs[j][296:289];
      expected=jobs[j][288:0];
      if (op==0 || op==5) bound=(len+3)/4;
      else bound=16+68*((len+9+63)/64);
      if (bound<2) bound=2;
      waited=0;
      while (!ready) begin tick;waited=waited+1;if (waited>5) $fatal(1,"ready timeout");end
      for (integer k=0;k<nb;k=k+1) begin
        // Reproducible producer gaps; hold each offered beat until accepted.
        if (!no_gaps && (j+k)%37==0) begin req_valid=0;tick;end
        req_data=beats[cursor];cursor=cursor+1;req_valid=1;
        waited=0;
        do begin
          tick;waited=waited+1;
          if (waited>140) $fatal(1,"input stall timeout job=%0d",j);
        end while (!pr);
        if (valid && expected[288]) begin cursor=cursor+nb-k-1;k=nb;end
      end
      req_valid=0;
      waited=0;
      while (!valid) begin
        tick;waited=waited+1;
        if (waited>bound+200) $fatal(1,"completion timeout job=%0d",j);
      end
      if (!expected[288]) begin
        if (age+1-pauses>max_latency[op]) max_latency[op]=age+1-pauses;
        if (age+1-pauses>bound) $fatal(1,"latency exceeds spec job=%0d age=%0d bound=%0d",j,age+1-pauses,bound);
      end
      // Hold response through its full deadline to exercise bounded-completion assertion.
      if (j<12 || mutant>=0) begin
        while (age<bound+pauses+5) tick;
      end
      repeat (3) tick;
      if (j==1) begin cancel_test=1;reset_dut;cancel_test=0;end
      else begin rsp_ready=1;tick;rsp_ready=0;end
      passed=passed+1;
      if (j%1000==0) begin $display("PROGRESS codec %0d/%0d cycles=%0d",j,N,cycles);$fflush();end
    end
    cancel_test=1;reset_dut;cancel_test=0;
'''
for i,(name,*_) in enumerate(checks):
    s+=f'    $display("ASSERT {i} {name} spec5.3/5.5.2/7/10.3 hits=%0d",hits[{i}]);\n'
s+='''    for (integer j=0;j<30;j=j+1) if (hits[j]==0) $fatal(1,"R-025 never exercised %0d",j);
    if (mutant>=0) $fatal(1,"mutant survived");
    for (integer j=0;j<7;j=j+1) $display("LATENCY op=%0d max=%0d",j,max_latency[j]);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS codec: golden=%0d/%0d assertions=30 cycles=%0d",passed,N,cycles);
    $finish;
  end
endmodule
'''
(HERE/'tb_m_tsmx_codec.sv').write_text(s)
