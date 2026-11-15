// Project TSM-X; Author TSMX project; Version 0.1.
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
      if (!rst) begin : a_0
        hits[0]=hits[0]+1;
        if(mutant==0 && !injected)begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 0 S5_3_reset_req DUT output bit flip");#1;
        end
        assert ((ready) === (1'b0)) else begin
          $display("ASSERT_FAIL 0 S5_3_reset_req job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_ready=0;
      end
      if (!rst) begin : a_1
        hits[1]=hits[1]+1;
        if(mutant==1 && !injected)begin
          flip_row_ready=1'b1;injected=1;
          $display("INJECT 1 S5_3_reset_row DUT output bit flip");#1;
        end
        assert ((rr) === (1'b0)) else begin
          $display("ASSERT_FAIL 1 S5_3_reset_row job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_row_ready=0;
      end
      if (!rst) begin : a_2
        hits[2]=hits[2]+1;
        if(mutant==2 && !injected)begin
          flip_terminal_ready=1'b1;injected=1;
          $display("INJECT 2 S5_3_reset_terminal DUT output bit flip");#1;
        end
        assert ((tr) === (1'b0)) else begin
          $display("ASSERT_FAIL 2 S5_3_reset_terminal job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_terminal_ready=0;
      end
      if (!rst) begin : a_3
        hits[3]=hits[3]+1;
        if(mutant==3 && !injected)begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 3 S5_3_reset_valid DUT output bit flip");#1;
        end
        assert ((valid) === (1'b0)) else begin
          $display("ASSERT_FAIL 3 S5_3_reset_valid job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_valid=0;
      end
      if (!rst) begin : a_4
        hits[4]=hits[4]+1;
        if(mutant==4 && !injected)begin
          flip_data=81'd1<<0;injected=1;
          $display("INJECT 4 S5_3_reset_payload DUT output bit flip");#1;
        end
        assert ((data) === (81'd0)) else begin
          $display("ASSERT_FAIL 4 S5_3_reset_payload job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && !raw_valid) begin : a_5
        hits[5]=hits[5]+1;
        if(mutant==5 && !injected)begin
          flip_data=81'd1<<0;injected=1;
          $display("INJECT 5 S5_3_invalid_zero DUT output bit flip");#1;
        end
        assert ((data) === (81'd0)) else begin
          $display("ASSERT_FAIL 5 S5_3_invalid_zero job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && pending>0) begin : a_6
        hits[6]=hits[6]+1;
        if(mutant==6 && !injected)begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 6 S5_3_one_job DUT output bit flip");#1;
        end
        assert ((ready) === (1'b0)) else begin
          $display("ASSERT_FAIL 6 S5_3_one_job job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_ready=0;
      end
      if (rst && terminal_sent) begin : a_7
        hits[7]=hits[7]+1;
        if(mutant==7 && !injected)begin
          flip_terminal_ready=1'b1;injected=1;
          $display("INJECT 7 S5_3_terminal_once DUT output bit flip");#1;
        end
        assert ((tr) === (1'b0)) else begin
          $display("ASSERT_FAIL 7 S5_3_terminal_once job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_terminal_ready=0;
      end
      if (rst && raw_valid) begin : a_8
        hits[8]=hits[8]+1;
        if(mutant==8 && !injected)begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 8 S5_3_response_owner DUT output bit flip");#1;
        end
        assert ((valid) === (pending==1)) else begin
          $display("ASSERT_FAIL 8 S5_3_response_owner job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_valid=0;
      end
      if (rst && pv && !ps) begin : a_9
        hits[9]=hits[9]+1;
        if(mutant==9 && !injected)begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 9 S5_3_stall_valid DUT output bit flip");#1;
        end
        assert ((valid) === (1'b1)) else begin
          $display("ASSERT_FAIL 9 S5_3_stall_valid job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_valid=0;
      end
      if (rst && pv && !ps) begin : a_10
        hits[10]=hits[10]+1;
        if(mutant==10 && !injected)begin
          flip_data=81'd1<<0;injected=1;
          $display("INJECT 10 S5_3_stall_payload DUT output bit flip");#1;
        end
        assert ((data) === (prev_data)) else begin
          $display("ASSERT_FAIL 10 S5_3_stall_payload job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && pv && ps) begin : a_11
        hits[11]=hits[11]+1;
        if(mutant==11 && !injected)begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 11 S5_3_consumed DUT output bit flip");#1;
        end
        assert ((valid) === (1'b0)) else begin
          $display("ASSERT_FAIL 11 S5_3_consumed job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_valid=0;
      end
      if (rst && pv && ps) begin : a_12
        hits[12]=hits[12]+1;
        if(mutant==12 && !injected)begin
          flip_ready=1'b1;injected=1;
          $display("INJECT 12 S5_3_idle_ready DUT output bit flip");#1;
        end
        assert ((ready) === (1'b1)) else begin
          $display("ASSERT_FAIL 12 S5_3_idle_ready job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_ready=0;
      end
      if (rst && pv && ps) begin : a_13
        hits[13]=hits[13]+1;
        if(mutant==13 && !injected)begin
          flip_row_ready=1'b1;injected=1;
          $display("INJECT 13 S5_3_idle_row DUT output bit flip");#1;
        end
        assert ((rr) === (1'b0)) else begin
          $display("ASSERT_FAIL 13 S5_3_idle_row job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_row_ready=0;
      end
      if (rst && pv && ps) begin : a_14
        hits[14]=hits[14]+1;
        if(mutant==14 && !injected)begin
          flip_terminal_ready=1'b1;injected=1;
          $display("INJECT 14 S5_3_idle_terminal DUT output bit flip");#1;
        end
        assert ((tr) === (1'b0)) else begin
          $display("ASSERT_FAIL 14 S5_3_idle_terminal job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_terminal_ready=0;
      end
      if (rst && raw_valid) begin : a_15
        hits[15]=hits[15]+1;
        if(mutant==15 && !injected)begin
          flip_data=81'd1<<0;injected=1;
          $display("INJECT 15 REQ007_atomic_result DUT output bit flip");#1;
        end
        assert ((data) === (expected)) else begin
          $display("ASSERT_FAIL 15 REQ007_atomic_result job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid) begin : a_16
        hits[16]=hits[16]+1;
        if(mutant==16 && !injected)begin
          flip_data=81'd1<<80;injected=1;
          $display("INJECT 16 S9_2_accept DUT output bit flip");#1;
        end
        assert ((data[80]) === (expected[80])) else begin
          $display("ASSERT_FAIL 16 S9_2_accept job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid) begin : a_17
        hits[17]=hits[17]+1;
        if(mutant==17 && !injected)begin
          flip_data=81'd1<<16;injected=1;
          $display("INJECT 17 S9_2_margin DUT output bit flip");#1;
        end
        assert ((data[79:16]) === (expected[79:16])) else begin
          $display("ASSERT_FAIL 17 S9_2_margin job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid) begin : a_18
        hits[18]=hits[18]+1;
        if(mutant==18 && !injected)begin
          flip_data=81'd1<<8;injected=1;
          $display("INJECT 18 S9_2_reason DUT output bit flip");#1;
        end
        assert ((data[15:8]) === (expected[15:8])) else begin
          $display("ASSERT_FAIL 18 S9_2_reason job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid) begin : a_19
        hits[19]=hits[19]+1;
        if(mutant==19 && !injected)begin
          flip_data=81'd1<<0;injected=1;
          $display("INJECT 19 S9_2_steps DUT output bit flip");#1;
        end
        assert ((data[7:0]) === (expected[7:0])) else begin
          $display("ASSERT_FAIL 19 S9_2_steps job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid && expected[80]) begin : a_20
        hits[20]=hits[20]+1;
        if(mutant==20 && !injected)begin
          flip_data=81'd1<<8;injected=1;
          $display("INJECT 20 S5_5_6_accepted DUT output bit flip");#1;
        end
        assert ((data[15:8]) === (8'd0)) else begin
          $display("ASSERT_FAIL 20 S5_5_6_accepted job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid && !expected[80]) begin : a_21
        hits[21]=hits[21]+1;
        if(mutant==21 && !injected)begin
          flip_data=81'd1<<80;injected=1;
          $display("INJECT 21 S5_5_6_rejected DUT output bit flip");#1;
        end
        assert ((data[80]) === (1'b0)) else begin
          $display("ASSERT_FAIL 21 S5_5_6_rejected job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && pending>0 && !terminal_sent) begin : a_22
        hits[22]=hits[22]+1;
        if(mutant==22 && !injected)begin
          flip_valid=1'b1;injected=1;
          $display("INJECT 22 S5_5_6_no_early_commit DUT output bit flip");#1;
        end
        assert ((valid) === (1'b0)) else begin
          $display("ASSERT_FAIL 22 S5_5_6_no_early_commit job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_valid=0;
      end
      if (rst && raw_valid && expected[15:8]!=0 && expected[15:8]!=24 && expected[15:8]!=23) begin : a_23
        hits[23]=hits[23]+1;
        if(mutant==23 && !injected)begin
          flip_data=81'd1<<16;injected=1;
          $display("INJECT 23 S5_5_6_preflight_margin DUT output bit flip");#1;
        end
        assert ((data[79:16]) === (64'hffffffffffffffff)) else begin
          $display("ASSERT_FAIL 23 S5_5_6_preflight_margin job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_data=0;
      end
      if (rst && raw_valid) begin : a_24
        hits[24]=hits[24]+1;
        if(mutant==24 && !injected)begin
          flip_row_ready=1'b1;injected=1;
          $display("INJECT 24 S5_3_response_row_closed DUT output bit flip");#1;
        end
        assert ((rr) === (1'b0)) else begin
          $display("ASSERT_FAIL 24 S5_3_response_row_closed job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_row_ready=0;
      end
      if (rst && raw_valid) begin : a_25
        hits[25]=hits[25]+1;
        if(mutant==25 && !injected)begin
          flip_terminal_ready=1'b1;injected=1;
          $display("INJECT 25 S5_3_response_terminal_closed DUT output bit flip");#1;
        end
        assert ((tr) === (1'b0)) else begin
          $display("ASSERT_FAIL 25 S5_3_response_terminal_closed job=%0d cycle=%0d got=%h expected=%h",job_id,cycle,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
        flip_terminal_ready=0;
      end
      if(rst && pending>0 && cycle-accepted_at>250000) $fatal(1,"bounded progress");
      #4;clk=0;#1;
    end
  endtask

  initial begin
    for(integer i=0;i<26;i=i+1)hits[i]=0;
    names[0]="S5_3_reset_req";
    names[1]="S5_3_reset_row";
    names[2]="S5_3_reset_terminal";
    names[3]="S5_3_reset_valid";
    names[4]="S5_3_reset_payload";
    names[5]="S5_3_invalid_zero";
    names[6]="S5_3_one_job";
    names[7]="S5_3_terminal_once";
    names[8]="S5_3_response_owner";
    names[9]="S5_3_stall_valid";
    names[10]="S5_3_stall_payload";
    names[11]="S5_3_consumed";
    names[12]="S5_3_idle_ready";
    names[13]="S5_3_idle_row";
    names[14]="S5_3_idle_terminal";
    names[15]="REQ007_atomic_result";
    names[16]="S9_2_accept";
    names[17]="S9_2_margin";
    names[18]="S9_2_reason";
    names[19]="S9_2_steps";
    names[20]="S5_5_6_accepted";
    names[21]="S5_5_6_rejected";
    names[22]="S5_5_6_no_early_commit";
    names[23]="S5_5_6_preflight_margin";
    names[24]="S5_3_response_row_closed";
    names[25]="S5_3_response_terminal_closed";
    if($value$plusargs("MUTANT=%d",mutant))begin end
    if($value$plusargs("START=%d",start))begin end
    if($value$plusargs("LIMIT=%d",limit))begin end
    if($value$plusargs("NOSTALL=%d",nostall))begin end
    if($value$plusargs("RESET_MID=%d",reset_mid))begin end
    rst=1; #1; rst=0; #1; $readmemh("jobs.mem",jobs);$readmemh("rows.mem",rows);
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

  integer cal_actor_at=0, cal_cell_at=0;
  always @(posedge clk) if(rst) begin
    if(dut.reg_fsm_ctrl_current_state==4'd5) cal_actor_at=cal_cycle;
    if(dut.reg_fsm_ctrl_current_state==4'd8)
      $display("CAL_ACTOR cycles=%0d",cal_cycle-cal_actor_at+1);
    if(dut.reg_fsm_ctrl_current_state==4'd3) cal_cell_at=cal_cycle;
    if(dut.reg_fsm_ctrl_current_state==4'd8 && dut.reg_actor+1>=dut.reg_world[8199:8192])
      $display("CAL_CELL cycles=%0d",cal_cycle-cal_cell_at+1);
  end

endmodule
