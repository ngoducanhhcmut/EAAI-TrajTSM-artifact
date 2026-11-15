`timescale 1ns/1ps
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
      if (!rst) begin : A00_reset_ready
        hits[0]=hits[0]+1;
        if(mutant==0 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 0 reset_ready: flipped DUT output ready");
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 0 reset_ready cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : A01_reset_valid
        hits[1]=hits[1]+1;
        if(mutant==1 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 1 reset_valid: flipped DUT output valid");
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 1 reset_valid cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : A02_reset_data
        hits[2]=hits[2]+1;
        if(mutant==2 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 2 reset_data: flipped DUT output data");
        end
        assert (data === 1'b0) else begin
          $display("ASSERT_FAIL 2 reset_data cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !raw_valid) begin : A03_invalid_zero
        hits[3]=hits[3]+1;
        if(mutant==3 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 3 invalid_zero: flipped DUT output data");
        end
        assert (data === 1'b0) else begin
          $display("ASSERT_FAIL 3 invalid_zero cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid) begin : A04_response_excludes_ready
        hits[4]=hits[4]+1;
        if(mutant==4 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 4 response_excludes_ready: flipped DUT output ready");
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 4 response_excludes_ready cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid) begin : A05_response_has_context
        hits[5]=hits[5]+1;
        if(mutant==5 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 5 response_has_context: flipped DUT output valid");
        end
        assert (valid && pending) else begin
          $display("ASSERT_FAIL 5 response_has_context cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid) begin : A06_golden_exact
        hits[6]=hits[6]+1;
        if(mutant==6 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 6 golden_exact: flipped DUT output data");
        end
        assert (data === pending_exp) else begin
          $display("ASSERT_FAIL 6 golden_exact cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : A07_stall_valid
        hits[7]=hits[7]+1;
        if(mutant==7 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 7 stall_valid: flipped DUT output valid");
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 7 stall_valid cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : A08_stall_payload
        hits[8]=hits[8]+1;
        if(mutant==8 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 8 stall_payload: flipped DUT output data");
        end
        assert (data === pd) else begin
          $display("ASSERT_FAIL 8 stall_payload cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : A09_stall_blocks_request
        hits[9]=hits[9]+1;
        if(mutant==9 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 9 stall_blocks_request: flipped DUT output ready");
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 9 stall_blocks_request cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : A10_consume_clears_valid
        hits[10]=hits[10]+1;
        if(mutant==10 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 10 consume_clears_valid: flipped DUT output valid");
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 10 consume_clears_valid cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : A11_consume_clears_payload
        hits[11]=hits[11]+1;
        if(mutant==11 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 11 consume_clears_payload: flipped DUT output data");
        end
        assert (data === 1'b0) else begin
          $display("ASSERT_FAIL 11 consume_clears_payload cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pr && !pq) begin : A12_idle_ready
        hits[12]=hits[12]+1;
        if(mutant==12 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 12 idle_ready: flipped DUT output ready");
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 12 idle_ready cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !pending && !pv) begin : A13_no_unsolicited
        hits[13]=hits[13]+1;
        if(mutant==13 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 13 no_unsolicited: flipped DUT output valid");
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 13 no_unsolicited cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pending && !raw_valid) begin : A14_bounded_busy
        hits[14]=hits[14]+1;
        if(mutant==14 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 14 bounded_busy: flipped DUT output ready");
        end
        assert (!ready && age<=12288) else begin
          $display("ASSERT_FAIL 14 bounded_busy cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && take) begin : A15_accept_blocks_replacement
        hits[15]=hits[15]+1;
        if(mutant==15 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 15 accept_blocks_replacement: flipped DUT output ready");
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 15 accept_blocks_replacement cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid && pending_exp) begin : A16_contained_accept
        hits[16]=hits[16]+1;
        if(mutant==16 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 16 contained_accept: flipped DUT output data");
        end
        assert (data === 1'b1) else begin
          $display("ASSERT_FAIL 16 contained_accept cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid && !pending_exp) begin : A17_rejected_clear
        hits[17]=hits[17]+1;
        if(mutant==17 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 17 rejected_clear: flipped DUT output data");
        end
        assert (data === 1'b0) else begin
          $display("ASSERT_FAIL 17 rejected_clear cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && released) begin : A18_release_no_stale
        hits[18]=hits[18]+1;
        if(mutant==18 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 18 release_no_stale: flipped DUT output valid");
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 18 release_no_stale cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc && pq) begin : A19_queued_request_cannot_replace
        hits[19]=hits[19]+1;
        if(mutant==19 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 19 queued_request_cannot_replace: flipped DUT output data");
        end
        assert (data === pd) else begin
          $display("ASSERT_FAIL 19 queued_request_cannot_replace cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pending && !raw_valid && pq) begin : A20_busy_request_backpressure
        hits[20]=hits[20]+1;
        if(mutant==20 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 20 busy_request_backpressure: flipped DUT output ready");
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 20 busy_request_backpressure cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pending && !raw_valid) begin : A21_work_has_no_payload
        hits[21]=hits[21]+1;
        if(mutant==21 && !injected) begin
          flip_data=1;injected=1;#1;
          $display("INJECT 21 work_has_no_payload: flipped DUT output data");
        end
        assert (data === 1'b0) else begin
          $display("ASSERT_FAIL 21 work_has_no_payload cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid) begin : A22_response_count
        hits[22]=hits[22]+1;
        if(mutant==22 && !injected) begin
          flip_valid=1;injected=1;#1;
          $display("INJECT 22 response_count: flipped DUT output valid");
        end
        assert (valid && requests==responses+1) else begin
          $display("ASSERT_FAIL 22 response_count cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && released) begin : A23_reset_release_ready
        hits[23]=hits[23]+1;
        if(mutant==23 && !injected) begin
          flip_ready=1;injected=1;#1;
          $display("INJECT 23 reset_release_ready: flipped DUT output ready");
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 23 reset_release_ready cycle=%0d age=%0d expected=%b actual=%b",cycles,age,pending_exp,data);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if(rst && raw_valid && !pv) begin
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
    $display("ASSERT_HITS 0 reset_ready spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[0]);
    $display("ASSERT_HITS 1 reset_valid spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[1]);
    $display("ASSERT_HITS 2 reset_data spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[2]);
    $display("ASSERT_HITS 3 invalid_zero spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[3]);
    $display("ASSERT_HITS 4 response_excludes_ready spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[4]);
    $display("ASSERT_HITS 5 response_has_context spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[5]);
    $display("ASSERT_HITS 6 golden_exact spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[6]);
    $display("ASSERT_HITS 7 stall_valid spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[7]);
    $display("ASSERT_HITS 8 stall_payload spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[8]);
    $display("ASSERT_HITS 9 stall_blocks_request spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[9]);
    $display("ASSERT_HITS 10 consume_clears_valid spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[10]);
    $display("ASSERT_HITS 11 consume_clears_payload spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[11]);
    $display("ASSERT_HITS 12 idle_ready spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[12]);
    $display("ASSERT_HITS 13 no_unsolicited spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[13]);
    $display("ASSERT_HITS 14 bounded_busy spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[14]);
    $display("ASSERT_HITS 15 accept_blocks_replacement spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[15]);
    $display("ASSERT_HITS 16 contained_accept spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[16]);
    $display("ASSERT_HITS 17 rejected_clear spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[17]);
    $display("ASSERT_HITS 18 release_no_stale spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[18]);
    $display("ASSERT_HITS 19 queued_request_cannot_replace spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[19]);
    $display("ASSERT_HITS 20 busy_request_backpressure spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[20]);
    $display("ASSERT_HITS 21 work_has_no_payload spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[21]);
    $display("ASSERT_HITS 22 response_count spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[22]);
    $display("ASSERT_HITS 23 reset_release_ready spec5.3/7/9.2/10.3/REQ-TSMX-005 hits=%0d",hits[23]);
    for(integer j=0;j<24;j=j+1) if(hits[j]==0) $fatal(1,"assertion never exercised %0d",j);
    if(mutant>=0) $fatal(1,"mutant survived");
    $display("LATENCY min=%0d max=%0d II min=%0d max=%0d (includes programmed stalls/idle)",latency_min,latency_max,ii_min,ii_max);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS splice: golden=%0d/%0d start=%0d assertions=24 cycles=%0d",lim,lim,first,cycles);
    $finish;
  end
  initial begin #1000000000;$fatal(1,"watchdog timeout");end
endmodule
