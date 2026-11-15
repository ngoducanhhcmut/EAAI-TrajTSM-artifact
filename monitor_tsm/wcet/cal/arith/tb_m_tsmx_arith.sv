`timescale 1ns/1ps
// TSM-X / TSMX project / version 0.1.
// Oracle: golden helpers; project protocol spec5.3, arithmetic spec5.5.1/9.2.
// Portable immediate assertions; mutation is a verification-only output wire fault.
module tb_m_tsmx_arith;
  reg clk=0,rst=0,req_valid=0,rsp_ready=0;
  reg [1927:0] req_data=0;
  wire raw_ready,raw_valid;
  wire [640:0] raw_data;
  wire [642:0] observed;
  reg [642:0] injection=0;
  reg [640:0] expected=0;
  reg pending=0;
  integer hits[0:25];
  string names[0:25];
  integer mutant=-1,injected=0,cycles=0,requests=0,responses=0,age=0;
  integer op=0,limit=0,run_n,wait_count,checked=0,start_n=0;
  integer latency_min[0:8],latency_max[0:8];
  reg first_seen=0;
  reg pr,pv,pc,take;
  reg [640:0] pd;
  `include "vectors_meta.svh"
  reg [2568:0] vectors[0:N-1];
  assign observed={raw_ready,raw_valid,raw_data} ^ injection;
  m_tsmx_arith dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_rsp_ready(rsp_ready),.o_req_ready(raw_ready),.o_rsp_valid(raw_valid),.o_rsp_data(raw_data)
  );

  // Every mutant changes a DUT-driven observed bit covered by this assertion's mask.
  // The same assertion evaluates the unmodified predicate and the injected output.
  task check;
    input integer id;
    input antecedent;
    input invariant;
    input [642:0] mask,wanted;
    reg found;
    begin
      if (antecedent) begin
        hits[id]=hits[id]+1;
        if (mutant==id && !injected) begin
          found=0;
          for (integer bit_idx=0;bit_idx<643;bit_idx=bit_idx+1) begin
            if (mask[bit_idx] && !found) begin
              injection[bit_idx]=1'b1;found=1;
            end
          end
          injected=1;
          $display("INJECT %0d %s output bit fault",id,names[id]);
          #1;
        end
        assert (invariant && ((observed & mask)===(wanted & mask))) else begin
          $display("ASSERT_FAIL %0d %s cycle=%0d op=%0d vector=%0d age=%0d",id,names[id],cycles,op,checked,age);
          $display("actual=%h expected=%h",observed,wanted);
          $fatal(1,"R-025 assertion failed");
        end
      end
    end
  endtask

  task tick;
    begin
      pr=raw_ready;pv=raw_valid;pc=rsp_ready;pd=raw_data;
      take=rst && pr && req_valid;
      if (rst && pv && pc) begin pending=0;responses=responses+1;end
      if (take) begin
        assert (!pending) else $fatal(1,"scoreboard overwrite");
        pending=1;requests=requests+1;age=1;first_seen=0;op=req_data[1927:1920];
        case(op)
          // v0.2 sequential arithmetic (Claude 30/10): measured bounds, see R2b_REPORT.md.
          0,5,8:limit=2;
          default:limit=20000;
        endcase
      end else if (pending) age=age+1;
      #4;clk=1;#1;cycles=cycles+1;
      check(0,!rst,1,643'b1<<642,0);
      check(1,!rst,1,643'b1<<641,0);
      check(2,!rst,1,{2'b0,{641{1'b1}}},0);
      check(3,rst && !raw_valid,1,{2'b0,{641{1'b1}}},0);
      check(4,rst && pending && !raw_valid,1,643'b1<<642,0);
      check(5,rst && raw_valid,pending,643'b1<<641,643'b1<<641);
      check(6,rst && pv && !pc,1,643'b1<<641,643'b1<<641);
      check(7,rst && pv && !pc,1,{3'b0,{160{1'b1}},480'd0},{2'b0,pd});
      check(8,rst && pv && !pc,1,{163'd0,{160{1'b1}},320'd0},{2'b0,pd});
      check(9,rst && pv && !pc,1,{323'd0,{160{1'b1}},160'd0},{2'b0,pd});
      check(10,rst && pv && !pc,1,{{483{1'b0}},{160{1'b1}}},{2'b0,pd});
      check(11,rst && raw_valid,1,643'b1<<640,{2'b0,expected});
      check(12,rst && raw_valid,1,{3'b0,{160{1'b1}},480'd0},{2'b0,expected});
      check(13,rst && raw_valid,1,{163'd0,{160{1'b1}},320'd0},{2'b0,expected});
      check(14,rst && raw_valid,1,{323'd0,{160{1'b1}},160'd0},{2'b0,expected});
      check(15,rst && raw_valid,1,{{483{1'b0}},{160{1'b1}}},{2'b0,expected});
      check(16,rst && raw_valid && op!=3 && op!=6 && op!=7,1,{163'd0,{480{1'b1}}},0);
      check(17,rst && raw_valid && (op==3 || op==7),1,{323'd0,{320{1'b1}}},0);
      check(18,rst && raw_valid && expected[640],1,{3'b0,{640{1'b1}}},0);
      check(19,rst && raw_valid,(first_seen || age<=limit),643'b1<<641,643'b1<<641);
      check(20,rst && pv && pc,1,643'b1<<642,643'b1<<642);
      check(21,rst && pv && pc,1,643'b1<<641,0);
      check(22,rst && pv && !pc,1,643'b1<<640,{2'b0,pd});
      check(23,rst && !pending && !pv && !take,1,{2'b0,{641{1'b1}}},0);
      check(24,!rst,1,643'b1<<642,0);
      check(25,rst && raw_valid,1,643'b1<<642,0);
      if (rst && pending && !first_seen && age>limit) $fatal(1,"bounded progress op=%0d age=%0d",op,age);
      if (rst && raw_valid && !first_seen) begin
        first_seen=1;
        if (op<9) begin
        if (age<latency_min[op]) latency_min[op]=age;
        if (age>latency_max[op]) latency_max[op]=age;
        end
      end
      #5;clk=0;
    end
  endtask

  // Spec5.3/7: abort a job after setup/issue, then observe a complete pipeline drain.
  task abort_job;
    input [1927:0] payload;
    begin
      req_data=payload;expected=0;req_valid=1;tick;req_valid=0;tick;tick;
      rst=0;pending=0;tick;rst=1;tick;
      repeat(20)tick;
    end
  endtask

  initial begin
    names[0]="S5.3 reset_ready";names[1]="S5.3 reset_valid";names[2]="S5.3 reset_payload";
    names[3]="S5.3 invalid_zero";names[4]="S5.3 busy_ready";names[5]="S5.3 response_owned";
    names[6]="S5.3 stall_valid";names[7]="S5.3 stall_q0";names[8]="S5.3 stall_q1";
    names[9]="S5.3 stall_q2";names[10]="S5.3 stall_q3";names[11]="S5.5.1 fault_exact";
    names[12]="S9.2 q0_exact";names[13]="S9.2 q1_exact";names[14]="S9.2 q2_exact";
    names[15]="S9.2 q3_exact";names[16]="S9.2 scalar_padding";names[17]="S9.2 pose_padding";
    names[18]="S5.5.1 fault_no_pose";names[19]="S10.3 bounded_completion";
    names[20]="S5.3 consume_ready";names[21]="S5.3 consume_valid_clear";
    names[22]="S5.3 stall_fault";names[23]="S5.3 idle_payload";
    names[24]="S7 reset_abort";names[25]="S5.3 one_outstanding";
    for(integer i=0;i<26;i=i+1)hits[i]=0;
    for(integer i=0;i<9;i=i+1)begin latency_min[i]=1000;latency_max[i]=0;end
    if ($value$plusargs("MUTANT=%d",mutant)) begin end
    if ($value$plusargs("START=%d",start_n)) begin end
    run_n=N-start_n;
    if ($value$plusargs("LIMIT=%d",run_n)) begin end
    $display("START arith N=%0d",N);
    $readmemh("vectors.mem",vectors);
    $display("LOADED arith");
    tick;tick;rst=1;tick;tick;
    for(integer i=start_n;i<start_n+run_n;i=i+1)begin
      checked=i;
      req_data=vectors[i][2568:641];expected=vectors[i][640:0];req_valid=1;
      wait_count=0;
      while(!raw_ready)begin tick;wait_count=wait_count+1;if(wait_count>20000)$fatal(1,"ready timeout");end
      tick;req_valid=0;req_data='1;
      wait_count=0;
      while(!raw_valid)begin tick;wait_count=wait_count+1;if(wait_count>20000)$fatal(1,"response timeout");end
      // Backpressure on every row, including all fault and wide ramp responses.
      tick;tick;rsp_ready=1;tick;rsp_ready=0;
      if(i%5000==0)begin $display("PROGRESS %0d/%0d",i,start_n+run_n);$fflush();end
    end
    // Reset while a real request occupies the leaf; no response may survive it.
    req_data=vectors[start_n+run_n-1][2568:641];expected=vectors[start_n+run_n-1][640:0];req_valid=1;
    tick;req_valid=0;rst=0;pending=0;tick;rst=1;tick;tick;
    abort_job({8'd1,160'd7,160'd3,1600'd0});
    abort_job({8'd3,160'd0,160'd10000000,160'(-160'd8000000),160'd100000,160'd0,1120'd0});
    abort_job({8'd4,160'd1000000,160'd10000000,160'(-160'd8000000),160'd0,160'd0,160'd100000,960'd0});
    abort_job({8'd7,160'd0,160'd0,160'(-160'd8000000),160'(-160'd8000000),160'(-160'd8000000),160'd100000,160'd0,800'd0});
    for(integer i=0;i<26;i=i+1)begin
      $display("ASSERT %0d %s hits=%0d",i,names[i],hits[i]);
      if(hits[i]==0 && run_n==N)$fatal(1,"assertion never exercised");
    end
    for(integer i=0;i<9;i=i+1)$display("LATENCY op=%0d min=%0d max=%0d",i,latency_min[i],latency_max[i]);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS arith: golden=%0d/%0d assertions=26 mutants=external requests=%0d responses=%0d",run_n,run_n,requests,responses);
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

endmodule
