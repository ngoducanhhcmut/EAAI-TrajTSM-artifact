// Project TSM-X; Author TSMX project; Version 0.1.
// Spec 5.3 ready/valid; 5.5.5 continuous rows; 9.2 packed ABI; 10.3 bounded progress.
`timescale 1ns/1ps
module tb_m_tsmx_mrmgen;
  reg clk=0,rst=0,req_valid=0,row_ready=0,rsp_ready=0;
  reg [175:0] req_data=0;
  wire ready,valid,row_valid;
  wire [49:0] data;
  wire [400:0] row;
  `include "vectors_meta.svh"
  reg [289:0] jobs[0:N-1];
  reg [400:0] rows[0:R-1];
  reg [400:0] exp_row=0,prev_rd=0;
  reg [49:0] exp_rsp=0,prev_data=0;
  reg prev_row=0,prev_rr=0,prev_valid=0,prev_sr=0;
  integer offset=0,count=0,pos=0,pending=0,seen_rsp=0;
  integer cycle=0,accepted_at=0,prev_accept=-1,blocked=0;
  integer latency_min=10000000,latency_max=0,ii_min=10000000,ii_max=0;
  integer gap_max=0,last_row_at=0,completed=0,total_rows=0;
  integer hits[0:31];
  integer mutant=-1,injected=0,start=0,limit=N,nostall=0,job_id=0;
  string names[0:31];
  m_tsmx_mrmgen dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_row_ready(row_ready),.i_rsp_ready(rsp_ready),.o_req_ready(ready),
    .o_row_valid(row_valid),.o_row_data(row),.o_rsp_valid(valid),.o_rsp_data(data)
  );

  // Mutants flip a sampled DUT output bit, identically in two-state and four-state simulators.
  // Each checker compares its own observed channel field; no force or X-dependent mutation.
  task check(input integer id,input reg active,input reg [400:0] actual,input reg [400:0] expected);
    reg [400:0] observed;
    begin
      if(active) begin
        hits[id]=hits[id]+1;observed=actual;
        if(mutant==id && !injected) begin
          observed=actual^401'd1;injected=1;
          $display("INJECT %0d %s sampled DUT output bit flip",id,names[id]);
        end
        assert(observed===expected) else begin
          $display("ASSERT_FAIL %0d %s job=%0d cycle=%0d actual=%h expected=%h",id,names[id],job_id,cycle,observed,expected);
          $fatal(1,"R-025 assertion failure");
        end
      end
    end
  endtask

  // Pre-edge sampling obeys the spec handshake; all expected payloads come from golden files.
  task tick;
    integer latency,ii,gap;
    begin
      if(pos<count) exp_row=rows[offset+pos]; else exp_row=0;
      check(0,!rst,ready,0);
      check(1,!rst,valid,0);
      check(2,!rst,row_valid,0);
      check(3,!rst,data,0);
      check(4,!rst,row,0);
      check(5,rst && !valid,data,0);
      check(6,rst && !row_valid,row,0);
      check(7,rst && row_valid,ready,0);
      check(8,rst && valid,ready,0);
      check(9,rst && prev_row && !prev_rr,row_valid,1);
      check(10,rst && prev_row && !prev_rr,row,prev_rd);
      check(11,rst && prev_valid && !prev_sr,valid,1);
      check(12,rst && prev_valid && !prev_sr,data,prev_data);
      check(13,rst && row_valid,row[400:393],exp_row[400:393]);
      check(14,rst && row_valid,row[392:361],exp_row[392:361]);
      check(15,rst && row_valid,row[360:353],exp_row[360:353]);
      check(16,rst && row_valid,row[352:289],0);
      check(17,rst && row_valid,row[288:257],exp_row[288:257]);
      check(18,rst && row_valid,row[256:193],exp_row[256:193]);
      check(19,rst && row_valid,row[192:129],exp_row[192:129]);
      check(20,rst && row_valid,row[128:97],exp_row[128:97]);
      check(21,rst && row_valid,row[96:65],exp_row[96:65]);
      check(22,rst && row_valid,row[64:33],exp_row[64:33]);
      check(23,rst && row_valid,row[32:1],exp_row[32:1]);
      check(24,rst && row_valid,row[0],exp_row[0]);
      check(25,rst && valid,data[49],exp_rsp[49]);
      check(26,rst && valid,data[48:41],exp_rsp[48:41]);
      check(27,rst && valid,data[40],exp_rsp[40]);
      check(28,rst && valid,data[39:8],exp_rsp[39:8]);
      check(29,rst && valid,data[7:0],exp_rsp[7:0]);
      check(30,rst && row_valid,row,exp_row);
      check(31,rst && valid,data,exp_rsp);
      if(rst && (row_valid || valid) && !pending) $fatal(1,"unsolicited response");
      if(rst && ready && req_valid) begin
        if(pending) $fatal(1,"multiple outstanding requests");
        pending=1;seen_rsp=0;accepted_at=cycle;blocked=0;last_row_at=cycle;pos=0;
        if(prev_accept>=0) begin
          ii=cycle-prev_accept;
          if(ii<ii_min) ii_min=ii;if(ii>ii_max) ii_max=ii;
        end
        prev_accept=cycle;
      end
      if(rst && pending && (row_valid && !row_ready)) blocked=blocked+1;
      if(rst && pending && cycle-accepted_at-blocked>163840) $fatal(1,"spec10.3 job budget exceeded");
      if(rst && row_valid && row_ready) begin
        if(pos>=count) $fatal(1,"extra row");
        $display("CAL_ROW index=%0d gap=%0d",pos,cycle-last_row_at);gap=cycle-last_row_at; if(gap>gap_max) gap_max=gap;
        last_row_at=cycle;pos=pos+1;total_rows=total_rows+1;
      end
      if(rst && valid && !seen_rsp) begin
        if(pos!=count) $fatal(1,"terminal before all rows");
        latency=cycle-accepted_at-blocked;
        if(latency<latency_min) latency_min=latency;
        if(latency>latency_max) latency_max=latency;
        $display("JOB %0d cycles=%0d rows=%0d",job_id,latency,count);
        seen_rsp=1;
      end
      if(rst && valid && rsp_ready) begin pending=0;completed=completed+1;end
      prev_row=row_valid;prev_rr=row_ready;prev_rd=row;
      prev_valid=valid;prev_sr=rsp_ready;prev_data=data;
      if(!rst) begin
        pending=0;seen_rsp=0;pos=0;prev_row=0;prev_valid=0;prev_accept=-1;
      end
      #4;clk=1;#1;cycle=cycle+1;#5;clk=0;#1;
    end
  endtask

  task reset_dut;
    begin rst=0;req_valid=0;row_ready=0;rsp_ready=0;#1;tick;tick;rst=1;tick;end
  endtask
  task load_job(input integer j);
    begin
      job_id=j;req_data=jobs[j][289:114];exp_rsp=jobs[j][113:64];
      offset=int'(jobs[j][63:32]);count=int'(jobs[j][31:0]);pos=0;
    end
  endtask
  initial begin
    for(integer j=0;j<32;j=j+1) hits[j]=0;
    names[0]="S5_3_B4_reset_ready";
    names[1]="S5_3_B4_reset_rsp_valid";
    names[2]="S5_3_B4_reset_row_valid";
    names[3]="S5_3_B4_reset_rsp_zero";
    names[4]="S5_3_B4_reset_row_zero";
    names[5]="S5_3_B4_invalid_rsp_zero";
    names[6]="S5_3_B4_invalid_row_zero";
    names[7]="S5_3_B4_row_blocks_req";
    names[8]="S5_3_B4_rsp_blocks_req";
    names[9]="S5_3_B4_row_stall_valid";
    names[10]="S5_3_B4_row_stall_data";
    names[11]="S5_3_B4_rsp_stall_valid";
    names[12]="S5_3_B4_rsp_stall_data";
    names[13]="S5_3_B4_row_candidate";
    names[14]="S5_3_B4_row_epoch";
    names[15]="S5_3_B4_row_index";
    names[16]="S5_3_B4_row_padding";
    names[17]="S5_3_B4_row_phase";
    names[18]="S5_3_B4_row_xlo";
    names[19]="S5_3_B4_row_xhi";
    names[20]="S5_3_B4_row_vlo";
    names[21]="S5_3_B4_row_vhi";
    names[22]="S5_3_B4_row_midpoint";
    names[23]="S5_3_B4_row_jerk";
    names[24]="S5_3_B4_row_last";
    names[25]="S5_3_B4_terminal_accept";
    names[26]="S5_3_B4_terminal_reason";
    names[27]="S5_3_B4_terminal_stop_valid";
    names[28]="S5_3_B4_terminal_stop";
    names[29]="S5_3_B4_terminal_row_count";
    names[30]="S5_3_B4_row_exact";
    names[31]="S5_3_B4_terminal_exact";
    if($value$plusargs("MUTANT=%d",mutant)) begin end
    if($value$plusargs("START=%d",start)) begin end
    if($value$plusargs("LIMIT=%d",limit)) begin end
    if($value$plusargs("NOSTALL=%d",nostall)) begin end
    rst=1; #1; rst=0; #1; $readmemh("jobs.mem",jobs);$readmemh("rows.mem",rows);
    reset_dut;
    // Abort at several arithmetic/control phases and drain long enough to catch stale work.
    for(integer abort_cycle=1;abort_cycle<60;abort_cycle=abort_cycle+13) begin
      load_job(0);req_valid=1;tick;req_valid=0;
      repeat(abort_cycle) tick;
      reset_dut;
      repeat(36) tick;
    end
    completed=0;total_rows=0;prev_accept=-1;
    for(integer j=start;j<N && j<start+limit;j=j+1) begin
      load_job(j);req_valid=1;row_ready=0;rsp_ready=0;
      while(!ready) tick;
      tick;req_valid=0;
      while(!valid) begin
        row_ready=(nostall!=0 || (cycle%7!=0 && cycle%7!=1));
        // Invalid request data changes throughout processing; accepted context must be isolated.
        req_data=~req_data;
        tick;
      end
      if(nostall==0) repeat(3) tick;
      rsp_ready=1;tick;rsp_ready=0;row_ready=0;
    end
    for(integer j=0;j<32;j=j+1) begin
      $display("ASSERT %0d %s spec5.3/5.5.5/9.2 hits=%0d",j,names[j],hits[j]);
      if(hits[j]==0 && nostall==0) $fatal(1,"assertion never exercised %0d",j);
    end
    if(mutant>=0) $fatal(1,"mutant survived");
    $display("LATENCY min=%0d max=%0d II min=%0d max=%0d row_gap_max=%0d nostall=%0d",latency_min,latency_max,ii_min,ii_max,gap_max,nostall);
    if(nostall==0) $display("assertion failures: 0, assertions never exercised: 0");
    else $display("MEASUREMENT no-stall: stall assertions may be inactive");
    $display("PASS mrmgen: golden=%0d/%0d rows=%0d assertions=32 cycles=%0d",completed,completed,total_rows,cycle);
    $finish;
  end
  initial begin #1000000000;$fatal(1,"watchdog timeout");end

  integer cal_cycle=0, cal_begin=0;
  reg cal_pending=0;
  always @(posedge clk) begin
    cal_cycle=cal_cycle+1;
    if (!rst) cal_pending=0;
    else begin
      if (dut.i_req_valid && dut.o_req_ready) begin cal_begin=cal_cycle; cal_pending=1; end
      if (dut.o_rsp_valid && cal_pending) begin
        $display("CAL job_cycles=%0d",cal_cycle-cal_begin); cal_pending=0;
      end
    end
  end

endmodule
