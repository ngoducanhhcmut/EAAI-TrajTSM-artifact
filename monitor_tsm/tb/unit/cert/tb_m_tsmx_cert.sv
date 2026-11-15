`timescale 1ns/1ps
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
  integer hits[0:29];
  string names[0:29];

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
      if (!rst) begin : A_reset_ready
        hits[0]++;
        if(mutant==0 && !injected) begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 0 reset_ready");#0.001;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 0 reset_ready spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : A_reset_valid
        hits[1]++;
        if(mutant==1 && !injected) begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 1 reset_valid");#0.001;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 1 reset_valid spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : A_reset_data
        hits[2]++;
        if(mutant==2 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 2 reset_data");#0.001;
        end
        assert (data === 8'd0) else begin
          $display("ASSERT_FAIL 2 reset_data spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!valid) begin : A_invalid_zero
        hits[3]++;
        if(mutant==3 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 3 invalid_zero");#0.001;
        end
        assert (data === 8'd0) else begin
          $display("ASSERT_FAIL 3 invalid_zero spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !outstanding && pr) begin : A_ready_qualified
        hits[4]++;
        if(mutant==4 && !injected) begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 4 ready_qualified");#0.001;
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 4 ready_qualified spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : A_response_accounted
        hits[5]++;
        if(mutant==5 && !injected) begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 5 response_accounted");#0.001;
        end
        assert (valid === 1'b1 && outstanding) else begin
          $display("ASSERT_FAIL 5 response_accounted spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : A_status_encoding
        hits[6]++;
        if(mutant==6 && !injected) begin
          flip_data=8'h80;injected=1;
          $display("INJECT 6 status_encoding");#0.001;
        end
        assert (data <= 8'd34 && data != 8'd35) else begin
          $display("ASSERT_FAIL 6 status_encoding spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : A_single_outstanding
        hits[7]++;
        if(mutant==7 && !injected) begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 7 single_outstanding");#0.001;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 7 single_outstanding spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && outstanding && cycles-start_cycle>=3) begin : A_bounded_completion
        hits[8]++;
        if(mutant==8 && !injected) begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 8 bounded_completion");#0.001;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 8 bounded_completion spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : A_atomic_status
        hits[9]++;
        if(mutant==9 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 9 atomic_status");#0.001;
        end
        assert (data === pending_exp) else begin
          $display("ASSERT_FAIL 9 atomic_status spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : A_stall_valid
        hits[10]++;
        if(mutant==10 && !injected) begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 10 stall_valid");#0.001;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 10 stall_valid spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : A_stall_payload
        hits[11]++;
        if(mutant==11 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 11 stall_payload");#0.001;
        end
        assert (data === pd) else begin
          $display("ASSERT_FAIL 11 stall_payload spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : A_stall_blocks_request
        hits[12]++;
        if(mutant==12 && !injected) begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 12 stall_blocks_request");#0.001;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 12 stall_blocks_request spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : A_consume_valid
        hits[13]++;
        if(mutant==13 && !injected) begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 13 consume_valid");#0.001;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 13 consume_valid spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : A_consume_payload
        hits[14]++;
        if(mutant==14 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 14 consume_payload");#0.001;
        end
        assert (data === 8'd0) else begin
          $display("ASSERT_FAIL 14 consume_payload spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !outstanding && !take) begin : A_no_unsolicited
        hits[15]++;
        if(mutant==15 && !injected) begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 15 no_unsolicited");#0.001;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 15 no_unsolicited spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pr && !pq) begin : A_idle_ready
        hits[16]++;
        if(mutant==16 && !injected) begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 16 idle_ready");#0.001;
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 16 idle_ready spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && boot) begin : A_reset_release_ready
        hits[17]++;
        if(mutant==17 && !injected) begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 17 reset_release_ready");#0.001;
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 17 reset_release_ready spec5.3 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd0) begin : A_ok
        hits[18]++;
        if(mutant==18 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 18 ok");#0.001;
        end
        assert (data === 8'd0) else begin
          $display("ASSERT_FAIL 18 ok spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd3) begin : A_timeout
        hits[19]++;
        if(mutant==19 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 19 timeout");#0.001;
        end
        assert (data === 8'd3) else begin
          $display("ASSERT_FAIL 19 timeout spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd25) begin : A_binding
        hits[20]++;
        if(mutant==20 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 20 binding");#0.001;
        end
        assert (data === 8'd25) else begin
          $display("ASSERT_FAIL 20 binding spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd26) begin : A_replay
        hits[21]++;
        if(mutant==21 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 21 replay");#0.001;
        end
        assert (data === 8'd26) else begin
          $display("ASSERT_FAIL 21 replay spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd27) begin : A_context
        hits[22]++;
        if(mutant==22 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 22 context");#0.001;
        end
        assert (data === 8'd27) else begin
          $display("ASSERT_FAIL 22 context spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd28) begin : A_lease
        hits[23]++;
        if(mutant==23 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 23 lease");#0.001;
        end
        assert (data === 8'd28) else begin
          $display("ASSERT_FAIL 23 lease spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd29) begin : A_executor_expiry
        hits[24]++;
        if(mutant==24 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 24 executor_expiry");#0.001;
        end
        assert (data === 8'd29) else begin
          $display("ASSERT_FAIL 24 executor_expiry spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd30) begin : A_ack_timeout
        hits[25]++;
        if(mutant==25 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 25 ack_timeout");#0.001;
        end
        assert (data === 8'd30) else begin
          $display("ASSERT_FAIL 25 ack_timeout spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd31) begin : A_committed
        hits[26]++;
        if(mutant==26 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 26 committed");#0.001;
        end
        assert (data === 8'd31) else begin
          $display("ASSERT_FAIL 26 committed spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd32) begin : A_pending
        hits[27]++;
        if(mutant==27 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 27 pending");#0.001;
        end
        assert (data === 8'd32) else begin
          $display("ASSERT_FAIL 27 pending spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd33) begin : A_late_apply
        hits[28]++;
        if(mutant==28 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 28 late_apply");#0.001;
        end
        assert (data === 8'd33) else begin
          $display("ASSERT_FAIL 28 late_apply spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==8'd34) begin : A_expiry
        hits[29]++;
        if(mutant==29 && !injected) begin
          flip_data=8'h01;injected=1;
          $display("INJECT 29 expiry");#0.001;
        end
        assert (data === 8'd34) else begin
          $display("ASSERT_FAIL 29 expiry spec5.5.9/6.2 cycle=%0d got=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      boot=!rst;
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
    hits[0]=0;names[0]="reset_ready";
    hits[1]=0;names[1]="reset_valid";
    hits[2]=0;names[2]="reset_data";
    hits[3]=0;names[3]="invalid_zero";
    hits[4]=0;names[4]="ready_qualified";
    hits[5]=0;names[5]="response_accounted";
    hits[6]=0;names[6]="status_encoding";
    hits[7]=0;names[7]="single_outstanding";
    hits[8]=0;names[8]="bounded_completion";
    hits[9]=0;names[9]="atomic_status";
    hits[10]=0;names[10]="stall_valid";
    hits[11]=0;names[11]="stall_payload";
    hits[12]=0;names[12]="stall_blocks_request";
    hits[13]=0;names[13]="consume_valid";
    hits[14]=0;names[14]="consume_payload";
    hits[15]=0;names[15]="no_unsolicited";
    hits[16]=0;names[16]="idle_ready";
    hits[17]=0;names[17]="reset_release_ready";
    hits[18]=0;names[18]="ok";
    hits[19]=0;names[19]="timeout";
    hits[20]=0;names[20]="binding";
    hits[21]=0;names[21]="replay";
    hits[22]=0;names[22]="context";
    hits[23]=0;names[23]="lease";
    hits[24]=0;names[24]="executor_expiry";
    hits[25]=0;names[25]="ack_timeout";
    hits[26]=0;names[26]="committed";
    hits[27]=0;names[27]="pending";
    hits[28]=0;names[28]="late_apply";
    hits[29]=0;names[29]="expiry";
    if($value$plusargs("MUTANT=%d",mutant)) begin end
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
    $display("ASSERT 0 %s hits=%0d failures=0",names[0],hits[0]);
    if(hits[0]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 1 %s hits=%0d failures=0",names[1],hits[1]);
    if(hits[1]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 2 %s hits=%0d failures=0",names[2],hits[2]);
    if(hits[2]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 3 %s hits=%0d failures=0",names[3],hits[3]);
    if(hits[3]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 4 %s hits=%0d failures=0",names[4],hits[4]);
    if(hits[4]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 5 %s hits=%0d failures=0",names[5],hits[5]);
    if(hits[5]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 6 %s hits=%0d failures=0",names[6],hits[6]);
    if(hits[6]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 7 %s hits=%0d failures=0",names[7],hits[7]);
    if(hits[7]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 8 %s hits=%0d failures=0",names[8],hits[8]);
    if(hits[8]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 9 %s hits=%0d failures=0",names[9],hits[9]);
    if(hits[9]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 10 %s hits=%0d failures=0",names[10],hits[10]);
    if(hits[10]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 11 %s hits=%0d failures=0",names[11],hits[11]);
    if(hits[11]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 12 %s hits=%0d failures=0",names[12],hits[12]);
    if(hits[12]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 13 %s hits=%0d failures=0",names[13],hits[13]);
    if(hits[13]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 14 %s hits=%0d failures=0",names[14],hits[14]);
    if(hits[14]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 15 %s hits=%0d failures=0",names[15],hits[15]);
    if(hits[15]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 16 %s hits=%0d failures=0",names[16],hits[16]);
    if(hits[16]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 17 %s hits=%0d failures=0",names[17],hits[17]);
    if(hits[17]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 18 %s hits=%0d failures=0",names[18],hits[18]);
    if(hits[18]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 19 %s hits=%0d failures=0",names[19],hits[19]);
    if(hits[19]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 20 %s hits=%0d failures=0",names[20],hits[20]);
    if(hits[20]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 21 %s hits=%0d failures=0",names[21],hits[21]);
    if(hits[21]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 22 %s hits=%0d failures=0",names[22],hits[22]);
    if(hits[22]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 23 %s hits=%0d failures=0",names[23],hits[23]);
    if(hits[23]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 24 %s hits=%0d failures=0",names[24],hits[24]);
    if(hits[24]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 25 %s hits=%0d failures=0",names[25],hits[25]);
    if(hits[25]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 26 %s hits=%0d failures=0",names[26],hits[26]);
    if(hits[26]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 27 %s hits=%0d failures=0",names[27],hits[27]);
    if(hits[27]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 28 %s hits=%0d failures=0",names[28],hits[28]);
    if(hits[28]==0) $fatal(1,"assertion never exercised");
    $display("ASSERT 29 %s hits=%0d failures=0",names[29],hits[29]);
    if(hits[29]==0) $fatal(1,"assertion never exercised");
    if(mutant>=0) $fatal(1,"mutant survived");
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("cycles per job=%0d..%0d measured II=%0d..%0d (includes injected stalls)",latency_min,latency_max,ii_min,ii_max);
    $display("PASS cert: golden=%0d/%0d assertions=30/30",N,N);
    $finish;
  end
endmodule
