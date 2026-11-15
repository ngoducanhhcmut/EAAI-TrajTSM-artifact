`timescale 1ns/1ps
// TSM-X / TSMX project / v0.2 (Claude 30/10: compact B4/B3 pair interface); oracle: spec5.3/5.5.11/7/9.2 and golden B13.
module tb_m_tsmx_health;
  parameter WORD_LIMIT=1024;
  string names[0:25];
  integer no_stall=0,job_ii=0;
  reg clk=0,rst=0,req_valid=0,rsp_ready=0;
  reg [33823:0] req_data=0;
  wire ready,valid,data;
  wire [175:0] b4q;
  wire [401:0] b4s,real_b4s;
  wire [8583:0] b3q;
  wire [80:0] b3s,real_b3s;
  wire b4qv,b4qr,b4sv,b4sr,b3qv,b3qr,b3sv,b3sr;
  wire real_b4qr,real_b4sv,real_b3qr,real_b3sv;
  reg stub=0;
  integer fault=0,delay_count=0,stage=0;
  reg fake_b4sv=0,fake_b3sv=0;
  reg [401:0] fake_b4s=0;
  reg [80:0] fake_b3s=0;
  reg [45457:0] bist_mem[0:0];
  `include "vectors_meta.svh"
  reg [33824:0] jobs[0:N-1];
  integer hits[0:25];
  integer mutant=-1,injected=0,cycles=0,accepted=0,completed=0;
  integer start_job=0,end_job=N,job,latency,last_accept=-1,min_lat=1000000,max_lat=0;
  integer min_ii=1000000,max_ii=0,launch=0,wait_cycles=0;
  reg expected=0,pending=0,take,pv,pc,pr,pd;
  reg pq4,pq3,ps4,ps3,t4,t3,c4,c3;
  reg [175:0] oldq4;
  reg [8583:0] oldq3;
  reg [33823:0] saved_req;
  m_tsmx_health #(.PARA_HEALTH_WORDS(WORD_LIMIT)) dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_rsp_ready(rsp_ready),.o_req_ready(ready),.o_rsp_valid(valid),.o_rsp_data(data),
    .o_b4_data(b4q),.o_b4_valid(b4qv),.i_b4_ready(b4qr),
    .i_b4_data(b4s),.i_b4_valid(b4sv),.o_b4_ready(b4sr),
    .o_b3_data(b3q),.o_b3_valid(b3qv),.i_b3_ready(b3qr),
    .i_b3_data(b3s),.i_b3_valid(b3sv),.o_b3_ready(b3sr)
  );
  m_tsmx_health_bist resources (
    .i_clk_core(clk),.i_rst_n_core(rst),
    .i_b4_data(b4q),.i_b4_valid(b4qv && !stub),.o_b4_ready(real_b4qr),
    .o_b4_data(real_b4s),.o_b4_valid(real_b4sv),.i_b4_ready(b4sr && !stub),
    .i_b3_data(b3q),.i_b3_valid(b3qv && !stub),.o_b3_ready(real_b3qr),
    .o_b3_data(real_b3s),.o_b3_valid(real_b3sv),.i_b3_ready(b3sr && !stub)
  );
  assign b4qr=stub ? delay_count==0 : real_b4qr;
  assign b3qr=stub ? delay_count==0 : real_b3qr;
  assign b4sv=stub ? fake_b4sv : real_b4sv;
  assign b3sv=stub ? fake_b3sv : real_b3sv;
  assign b4s=stub ? fake_b4s : real_b4s;
  assign b3s=stub ? fake_b3s : real_b3s;

  task fail_check(input integer id,input reg [54041:0] observed,input reg [54041:0] exp);
    begin
      $display("ASSERT_FAIL %0d cycle=%0d observed=%h expected=%h",id,cycles,observed,exp);
      $fatal(1,"R025 assertion failed");
    end
  endtask

  // Sampled DUT-output mutations flip a real output bit; no assertion predicate is changed.
  task check(input integer id,input reg [54041:0] actual,input reg [54041:0] exp);
    reg [54041:0] observed;
    begin
      hits[id]=hits[id]+1; observed=actual;
      if(mutant==id && !injected) begin
        observed=actual ^ 54042'd1; injected=1;
        $display("INJECT sampled DUT output mutant %0d",id);
      end
      case(id)
        0: begin : s_reset_ready
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        1: begin : s_reset_valid
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        2: begin : s_reset_health
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        3: begin : s_reset_b4_valid
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        4: begin : s_reset_b3_valid
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        5: begin : s_invalid_health_zero
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        6: begin : s_single_context
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        7: begin : s_health_bit_exact
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        8: begin : s_no_orphan_response
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        9: begin : s_hold_valid
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        10: begin : s_hold_health
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        11: begin : s_consume_clears
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        12: begin : s_consume_ready
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        13: begin : s_accept_busy
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        14: begin : s_b4_exact_request
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        15: begin : s_bist_enabled
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        16: begin : s_b4_stall_valid
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        17: begin : s_b4_stall_payload
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        18: begin : s_b3_exact_lane
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        19: begin : s_b3_actor_count
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        20: begin : s_b3_exact_trajectory
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        21: begin : s_b3_stall_valid
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        22: begin : s_b3_stall_payload
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        23: begin : s_b4_invalid_zero
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        24: begin : s_b3_invalid_zero
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        25: begin : s_response_accounting
          assert(observed===exp) else fail_check(id,observed,exp);
        end
        default: $fatal(1,"unknown assertion ID");
      endcase
    end
  endtask

  task tick;
    begin
      pr=ready;pv=valid;pc=rsp_ready;pd=data;take=rst && ready && req_valid;
      pq4=b4qv;pq3=b3qv;ps4=b4qr;ps3=b3qr;oldq4=b4q;oldq3=b3q;
      if(take) begin
        pending=1;saved_req=req_data;accepted=accepted+1;launch=cycles;
        if(last_accept>=0) begin
          job_ii=cycles-last_accept;
          if(cycles-last_accept<min_ii) min_ii=cycles-last_accept;
          if(cycles-last_accept>max_ii) max_ii=cycles-last_accept;
        end
        last_accept=cycles;
      end
      if(rst && pv && pc) begin pending=0;completed=completed+1;end
      t4=b4qv && b4qr;t3=b3qv && b3qr;c4=b4sv && b4sr;c3=b3sv && b3sr;
      #4;clk=1;#1;cycles=cycles+1;
      if(stub) begin
        if(delay_count>0) delay_count=delay_count-1;
        if(c4) begin fake_b4sv=0;delay_count=6;end
        if(c3) fake_b3sv=0;
        if(t4) begin
          // Compact pair answer: terminal record and the endpoint row it qualifies (row 31).
          fake_b4s={bist_mem[0][45457:45408],bist_mem[0][45407-31*352 -:352]};fake_b4sv=1;
          case(fault)
            1:fake_b4s[401]=0;
            2:fake_b4s[391:360]=1100001;
            3:fake_b4s[351]=~fake_b4s[351];
            4:fake_b4s[359:352]=0;
            5:fake_b4s[392]=0;
            default:begin end
          endcase
        end
        if(t3) begin
          fake_b3sv=1;fake_b3s=0;
          fake_b3s[80]=(stage==0);
          if((fault==6 && stage==0)||(fault==7 && stage==1)) fake_b3s[80]=~fake_b3s[80];
          stage=stage+1;
        end
      end
      if(!rst) begin
        check(0,ready,0);check(1,valid,0);check(2,data,0);
        check(3,b4qv,0);check(4,b3qv,0);
      end
      if(rst && !valid) check(5,data,0);
      if(rst && valid) begin
        check(6,ready,0);check(7,data,expected);check(8,pending,1);
      end
      if(rst && pv && !pc) begin check(9,valid,1);check(10,data,pd);end
      if(rst && pv && pc) begin check(11,valid,0);check(12,ready,1);end
      if(rst && take) check(13,ready,0);
      if(rst && b4qv) begin
        check(14,b4q,{64'd0,32'd1000000,32'd0,8'd0,32'd0,8'd128});
        check(15,saved_req[0],1);
      end
      if(rst && pq4 && !ps4) begin check(16,b4qv,1);check(17,b4q,oldq4);end
      if(rst && b3qv) begin
        check(18,b3q[383:0],{64'hffffffffffe488c0,64'd1800000,64'd0,
                            64'd950000,64'd50000,64'd500000});
        check(19,b3q[8583:8576],8'd1);
        check(20,b3q[8511:8320],{32'd0,32'd0,64'd4800000,32'd0,32'd0});
      end
      if(rst && pq3 && !ps3) begin check(21,b3qv,1);check(22,b3q,oldq3);end
      if(rst && !b4qv) check(23,b4q,0);
      if(rst && !b3qv) check(24,b3q,0);
      if(rst && !valid) check(25,completed<=accepted,1);
      #5;clk=0;#1;
    end
  endtask

  task reset_dut;
    begin
      rst=0;req_valid=0;rsp_ready=0;pending=0;
      tick;tick;rst=1;tick;
    end
  endtask
  task run_job(input reg [33823:0] payload,input reg exp,input integer stalls);
    begin
      expected=exp && payload[33822:33812]<=WORD_LIMIT;req_data=payload;req_valid=1;rsp_ready=0;
      while(!ready) tick;
      tick;req_valid=0;wait_cycles=0;
      while(!valid) begin tick;wait_cycles=wait_cycles+1;
        if(wait_cycles>65536) $fatal(1,"B13 over 65536 cycle budget");end
      latency=cycles-launch;
      if(latency<min_lat) min_lat=latency;
      if(latency>max_lat) max_lat=latency;
      $display("JOB %0d cycles=%0d II=%0d",job,latency,job_ii);
      if(stub || !no_stall) repeat(stalls) tick;
      rsp_ready=1;tick;rsp_ready=0;
    end
  endtask
  initial begin
    for(integer k=0;k<26;k=k+1) hits[k]=0;
    names[0]="reset_ready";
    names[1]="reset_valid";
    names[2]="reset_health";
    names[3]="reset_b4_valid";
    names[4]="reset_b3_valid";
    names[5]="invalid_health_zero";
    names[6]="single_context";
    names[7]="health_bit_exact";
    names[8]="no_orphan_response";
    names[9]="hold_valid";
    names[10]="hold_health";
    names[11]="consume_clears";
    names[12]="consume_ready";
    names[13]="accept_busy";
    names[14]="b4_exact_request";
    names[15]="bist_enabled";
    names[16]="b4_stall_valid";
    names[17]="b4_stall_payload";
    names[18]="b3_exact_lane";
    names[19]="b3_actor_count";
    names[20]="b3_exact_trajectory";
    names[21]="b3_stall_valid";
    names[22]="b3_stall_payload";
    names[23]="b4_invalid_zero";
    names[24]="b3_invalid_zero";
    names[25]="response_accounting";

    if($value$plusargs("MUTANT=%d",mutant)) begin end
    if($value$plusargs("START=%d",start_job)) begin end
    if($value$plusargs("END=%d",end_job)) begin end
    $readmemh("jobs.mem",jobs);$readmemh("bist.mem",bist_mem);
    if($value$plusargs("NO_STALL=%d",no_stall)) begin end
    reset_dut;
    // Stalled BIST requests and every golden BIST mismatch, spec5.5.11.
    stub=1;
    for(integer f=0;f<8;f=f+1) begin
      fault=f;stage=0;fake_b4sv=0;fake_b3sv=0;delay_count=8;
      req_data=0;req_data[33823]=1;req_data[8:7]=3;req_data[6:1]=1;req_data[0]=1;
      // Stalls also exercise B3 request hold before accepting the clear job.
      run_job(req_data,f==0,3);
    end
    stub=0;reset_dut;
    for(job=start_job;job<end_job;job=job+1)
      run_job(jobs[job][33824:1],jobs[job][0],job%4);
    // Reset aborts active BIST, clears private pipelines, and permits a fresh passing job.
    req_data=0;req_data[33823]=1;req_data[8:7]=3;req_data[6:1]=1;req_data[0]=1;
    expected=1;req_valid=1;tick;req_valid=0;repeat(35) tick;reset_dut;
    run_job(req_data,1,0);
    $display("MEASURE latency=%0d..%0d II=%0d..%0d",min_lat,max_lat,min_ii,max_ii);
    for(integer k=0;k<26;k=k+1) begin
      $display("ASSERT %0d %s spec5.3/5.5.11 hits=%0d",k,names[k],hits[k]);
      if(hits[k]==0) $fatal(1,"assertion never exercised %0d",k);
    end
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS health: golden=%0d/%0d assertions=26",end_job-start_job,end_job-start_job);
    $finish;
  end
endmodule
