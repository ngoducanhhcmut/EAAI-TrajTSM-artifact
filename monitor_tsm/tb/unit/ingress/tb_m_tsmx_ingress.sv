`timescale 1ns/1ps
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
      if(!rst) begin : A00_reset_ready
        hits[0]++;
        if(mutant==0 && !injected) begin
          flip_ready=1; injected=1;#1;
          $display("INJECT 0 reset_ready output bit inversion");
        end
        assert (ready===1'b0) else begin
          $display("ASSERT_FAIL 0 reset_ready spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(!rst) begin : A01_reset_valid
        hits[1]++;
        if(mutant==1 && !injected) begin
          flip_valid=1; injected=1;#1;
          $display("INJECT 1 reset_valid output bit inversion");
        end
        assert (valid===1'b0) else begin
          $display("ASSERT_FAIL 1 reset_valid spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(!rst) begin : A02_reset_data
        hits[2]++;
        if(mutant==2 && !injected) begin
          flip_data[0]=1; injected=1;#1;
          $display("INJECT 2 reset_data output bit inversion");
        end
        assert (data==='0) else begin
          $display("ASSERT_FAIL 2 reset_data spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && !valid) begin : A03_invalid_zero
        hits[3]++;
        if(mutant==3 && !injected) begin
          flip_data[0]=1; injected=1;#1;
          $display("INJECT 3 invalid_zero output bit inversion");
        end
        assert (data==='0) else begin
          $display("ASSERT_FAIL 3 invalid_zero spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid) begin : A04_single_outstanding
        hits[4]++;
        if(mutant==4 && !injected) begin
          flip_ready=1; injected=1;#1;
          $display("INJECT 4 single_outstanding output bit inversion");
        end
        assert (ready===1'b0) else begin
          $display("ASSERT_FAIL 4 single_outstanding spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && take) begin : A05_accept_blocks_req
        hits[5]++;
        if(mutant==5 && !injected) begin
          flip_ready=1; injected=1;#1;
          $display("INJECT 5 accept_blocks_req output bit inversion");
        end
        assert (ready===1'b0) else begin
          $display("ASSERT_FAIL 5 accept_blocks_req spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pending && cycles-accepted==3) begin : A06_bounded_progress
        hits[6]++;
        if(mutant==6 && !injected) begin
          flip_valid=1; injected=1;#1;
          $display("INJECT 6 bounded_progress output bit inversion");
        end
        assert (valid===1'b1) else begin
          $display("ASSERT_FAIL 6 bounded_progress spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pv && !pc) begin : A07_stall_valid
        hits[7]++;
        if(mutant==7 && !injected) begin
          flip_valid=1; injected=1;#1;
          $display("INJECT 7 stall_valid output bit inversion");
        end
        assert (valid===1'b1) else begin
          $display("ASSERT_FAIL 7 stall_valid spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pv && !pc) begin : A08_stall_data
        hits[8]++;
        if(mutant==8 && !injected) begin
          flip_data[0]=1; injected=1;#1;
          $display("INJECT 8 stall_data output bit inversion");
        end
        assert (data===pd) else begin
          $display("ASSERT_FAIL 8 stall_data spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pv && !pc) begin : A09_stall_blocks_req
        hits[9]++;
        if(mutant==9 && !injected) begin
          flip_ready=1; injected=1;#1;
          $display("INJECT 9 stall_blocks_req output bit inversion");
        end
        assert (ready===1'b0) else begin
          $display("ASSERT_FAIL 9 stall_blocks_req spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pv && pc) begin : A10_consume_valid
        hits[10]++;
        if(mutant==10 && !injected) begin
          flip_valid=1; injected=1;#1;
          $display("INJECT 10 consume_valid output bit inversion");
        end
        assert (valid===1'b0) else begin
          $display("ASSERT_FAIL 10 consume_valid spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pv && pc) begin : A11_consume_data
        hits[11]++;
        if(mutant==11 && !injected) begin
          flip_data[0]=1; injected=1;#1;
          $display("INJECT 11 consume_data output bit inversion");
        end
        assert (data==='0) else begin
          $display("ASSERT_FAIL 11 consume_data spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && !pending && !pv && !take) begin : A12_no_unsolicited
        hits[12]++;
        if(mutant==12 && !injected) begin
          flip_valid=1; injected=1;#1;
          $display("INJECT 12 no_unsolicited output bit inversion");
        end
        assert (valid===1'b0) else begin
          $display("ASSERT_FAIL 12 no_unsolicited spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pr && !pq) begin : A13_idle_ready
        hits[13]++;
        if(mutant==13 && !injected) begin
          flip_ready=1; injected=1;#1;
          $display("INJECT 13 idle_ready output bit inversion");
        end
        assert (ready===1'b1) else begin
          $display("ASSERT_FAIL 13 idle_ready spec5.3/7 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]!=0) begin : A14_reject_atomic
        hits[14]++;
        if(mutant==14 && !injected) begin
          flip_data[8]=1; injected=1;#1;
          $display("INJECT 14 reject_atomic output bit inversion");
        end
        assert (data[339:8]===saved_req[1373:1042]) else begin
          $display("ASSERT_FAIL 14 reject_atomic spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid) begin : A15_full_response
        hits[15]++;
        if(mutant==15 && !injected) begin
          flip_data[0]=1; injected=1;#1;
          $display("INJECT 15 full_response output bit inversion");
        end
        assert (data===pending_exp) else begin
          $display("ASSERT_FAIL 15 full_response spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A16_seq_valid
        hits[16]++;
        if(mutant==16 && !injected) begin
          flip_data[339]=1; injected=1;#1;
          $display("INJECT 16 seq_valid output bit inversion");
        end
        assert (data[339]===1'b1) else begin
          $display("ASSERT_FAIL 16 seq_valid spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A17_seq
        hits[17]++;
        if(mutant==17 && !injected) begin
          flip_data[307]=1; injected=1;#1;
          $display("INJECT 17 seq output bit inversion");
        end
        assert (data[338:307]===saved_req[752:721]) else begin
          $display("ASSERT_FAIL 17 seq spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A18_time_valid
        hits[18]++;
        if(mutant==18 && !injected) begin
          flip_data[306]=1; injected=1;#1;
          $display("INJECT 18 time_valid output bit inversion");
        end
        assert (data[306]===1'b1) else begin
          $display("ASSERT_FAIL 18 time_valid spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A19_last_time
        hits[19]++;
        if(mutant==19 && !injected) begin
          flip_data[274]=1; injected=1;#1;
          $display("INJECT 19 last_time output bit inversion");
        end
        assert (data[305:274]===saved_req[1041:1010]) else begin
          $display("ASSERT_FAIL 19 last_time spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A20_sample_valid
        hits[20]++;
        if(mutant==20 && !injected) begin
          flip_data[273]=1; injected=1;#1;
          $display("INJECT 20 sample_valid output bit inversion");
        end
        assert (data[273]===1'b1) else begin
          $display("ASSERT_FAIL 20 sample_valid spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A21_last_sample
        hits[21]++;
        if(mutant==21 && !injected) begin
          flip_data[241]=1; injected=1;#1;
          $display("INJECT 21 last_sample output bit inversion");
        end
        assert (data[272:241]===saved_req[720:689]) else begin
          $display("ASSERT_FAIL 21 last_sample spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A22_sig_valid
        hits[22]++;
        if(mutant==22 && !injected) begin
          flip_data[240]=1; injected=1;#1;
          $display("INJECT 22 sig_valid output bit inversion");
        end
        assert (data[240]===1'b1) else begin
          $display("ASSERT_FAIL 22 sig_valid spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A23_signature
        hits[23]++;
        if(mutant==23 && !injected) begin
          flip_data[104]=1; injected=1;#1;
          $display("INJECT 23 signature output bit inversion");
        end
        assert (data[239:104]===saved_req[400:265]) else begin
          $display("ASSERT_FAIL 23 signature spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A24_freeze_epoch
        hits[24]++;
        if(mutant==24 && !injected) begin
          flip_data[72]=1; injected=1;#1;
          $display("INJECT 24 freeze_epoch output bit inversion");
        end
        assert (data[103:72]===pending_exp[103:72]) else begin
          $display("ASSERT_FAIL 24 freeze_epoch spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid && pending_exp[7:0]==0) begin : A25_freeze_position
        hits[25]++;
        if(mutant==25 && !injected) begin
          flip_data[8]=1; injected=1;#1;
          $display("INJECT 25 freeze_position output bit inversion");
        end
        assert (data[71:8]===pending_exp[71:8]) else begin
          $display("ASSERT_FAIL 25 freeze_position spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && valid) begin : A26_reason
        hits[26]++;
        if(mutant==26 && !injected) begin
          flip_data[0]=1; injected=1;#1;
          $display("INJECT 26 reason output bit inversion");
        end
        assert (data[7:0]===pending_exp[7:0]) else begin
          $display("ASSERT_FAIL 26 reason spec5.5.3/9.2 job=%0d cycle=%0d actual=%h expected=%h",jobs,cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failure");
        end
      end
      if(rst && pending && !valid && cycles-accepted>8) $fatal(1,"bounded progress");
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
