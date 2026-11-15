`timescale 1ns/1ps
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
      if (!rst) begin : S_reset_ready
        hits[0]=hits[0]+1;
        if (mutant==0 && !injected) begin
          force ready='x;
          injected=1;
          $display("INJECT 0 reset_ready: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 0 reset_ready spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : S_reset_valid
        hits[1]=hits[1]+1;
        if (mutant==1 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 1 reset_valid: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 1 reset_valid spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : S_reset_data
        hits[2]=hits[2]+1;
        if (mutant==2 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 2 reset_data: DUT output data stuck-X");
          #1;
        end
        assert (data === 289'd0) else begin
          $display("ASSERT_FAIL 2 reset_data spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !valid) begin : S_invalid_zero
        hits[3]=hits[3]+1;
        if (mutant==3 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 3 invalid_zero: DUT output data stuck-X");
          #1;
        end
        assert (data === 289'd0) else begin
          $display("ASSERT_FAIL 3 invalid_zero spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : S_ready_known
        hits[4]=hits[4]+1;
        if (mutant==4 && !injected) begin
          force ready='x;
          injected=1;
          $display("INJECT 4 ready_known: DUT output ready stuck-X");
          #1;
        end
        assert (!$isunknown(ready)) else begin
          $display("ASSERT_FAIL 4 ready_known spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : S_valid_known
        hits[5]=hits[5]+1;
        if (mutant==5 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 5 valid_known: DUT output valid stuck-X");
          #1;
        end
        assert (!$isunknown(valid)) else begin
          $display("ASSERT_FAIL 5 valid_known spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : S_response_known
        hits[6]=hits[6]+1;
        if (mutant==6 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 6 response_known: DUT output data stuck-X");
          #1;
        end
        assert (!$isunknown(data)) else begin
          $display("ASSERT_FAIL 6 response_known spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : S_no_ready_response
        hits[7]=hits[7]+1;
        if (mutant==7 && !injected) begin
          force ready='x;
          injected=1;
          $display("INJECT 7 no_ready_response: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 7 no_ready_response spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && stalled) begin : S_stall_valid
        hits[8]=hits[8]+1;
        if (mutant==8 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 8 stall_valid: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 8 stall_valid spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && stalled) begin : S_stall_payload
        hits[9]=hits[9]+1;
        if (mutant==9 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 9 stall_payload: DUT output data stuck-X");
          #1;
        end
        assert (data === held) else begin
          $display("ASSERT_FAIL 9 stall_payload spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !expected[288] && (op==0 || op==5)) begin : S_crc_no_digest
        hits[10]=hits[10]+1;
        if (mutant==10 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 10 crc_no_digest: DUT output data stuck-X");
          #1;
        end
        assert (data[255:0] === 256'd0) else begin
          $display("ASSERT_FAIL 10 crc_no_digest spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !expected[288] && !(op==0 || op==5)) begin : S_sha_no_crc
        hits[11]=hits[11]+1;
        if (mutant==11 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 11 sha_no_crc: DUT output data stuck-X");
          #1;
        end
        assert (data[287:256] === 32'd0) else begin
          $display("ASSERT_FAIL 11 sha_no_crc spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && expected[288]) begin : S_fault_zero
        hits[12]=hits[12]+1;
        if (mutant==12 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 12 fault_zero: DUT output data stuck-X");
          #1;
        end
        assert (data[287:0] === 288'd0) else begin
          $display("ASSERT_FAIL 12 fault_zero spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : S_fault_exact
        hits[13]=hits[13]+1;
        if (mutant==13 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 13 fault_exact: DUT output data stuck-X");
          #1;
        end
        assert (data[288] === expected[288]) else begin
          $display("ASSERT_FAIL 13 fault_exact spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && (op==0 || op==5)) begin : S_crc_exact
        hits[14]=hits[14]+1;
        if (mutant==14 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 14 crc_exact: DUT output data stuck-X");
          #1;
        end
        assert (data[287:256] === expected[287:256]) else begin
          $display("ASSERT_FAIL 14 crc_exact spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_0
        hits[15]=hits[15]+1;
        if (mutant==15 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 15 sha_word_0: DUT output data stuck-X");
          #1;
        end
        assert (data[255:224] === expected[255:224]) else begin
          $display("ASSERT_FAIL 15 sha_word_0 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_1
        hits[16]=hits[16]+1;
        if (mutant==16 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 16 sha_word_1: DUT output data stuck-X");
          #1;
        end
        assert (data[223:192] === expected[223:192]) else begin
          $display("ASSERT_FAIL 16 sha_word_1 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_2
        hits[17]=hits[17]+1;
        if (mutant==17 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 17 sha_word_2: DUT output data stuck-X");
          #1;
        end
        assert (data[191:160] === expected[191:160]) else begin
          $display("ASSERT_FAIL 17 sha_word_2 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_3
        hits[18]=hits[18]+1;
        if (mutant==18 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 18 sha_word_3: DUT output data stuck-X");
          #1;
        end
        assert (data[159:128] === expected[159:128]) else begin
          $display("ASSERT_FAIL 18 sha_word_3 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_4
        hits[19]=hits[19]+1;
        if (mutant==19 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 19 sha_word_4: DUT output data stuck-X");
          #1;
        end
        assert (data[127:96] === expected[127:96]) else begin
          $display("ASSERT_FAIL 19 sha_word_4 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_5
        hits[20]=hits[20]+1;
        if (mutant==20 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 20 sha_word_5: DUT output data stuck-X");
          #1;
        end
        assert (data[95:64] === expected[95:64]) else begin
          $display("ASSERT_FAIL 20 sha_word_5 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_6
        hits[21]=hits[21]+1;
        if (mutant==21 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 21 sha_word_6: DUT output data stuck-X");
          #1;
        end
        assert (data[63:32] === expected[63:32]) else begin
          $display("ASSERT_FAIL 21 sha_word_6 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && !(op==0 || op==5)) begin : S_sha_word_7
        hits[22]=hits[22]+1;
        if (mutant==22 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 22 sha_word_7: DUT output data stuck-X");
          #1;
        end
        assert (data[31:0] === expected[31:0]) else begin
          $display("ASSERT_FAIL 22 sha_word_7 spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pending && age==bound+pauses+4) begin : S_bounded_response
        hits[23]=hits[23]+1;
        if (mutant==23 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 23 bounded_response: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 23 bounded_response spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pending && !last_seen && !expected[288]) begin : S_no_early_response
        hits[24]=hits[24]+1;
        if (mutant==24 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 24 no_early_response: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 24 no_early_response spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pending && last_seen) begin : S_last_blocks_input
        hits[25]=hits[25]+1;
        if (mutant==25 && !injected) begin
          force ready='x;
          injected=1;
          $display("INJECT 25 last_blocks_input: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 25 last_blocks_input spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !pending) begin : S_response_has_job
        hits[26]=hits[26]+1;
        if (mutant==26 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 26 response_has_job: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 26 response_has_job spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : S_whole_response
        hits[27]=hits[27]+1;
        if (mutant==27 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 27 whole_response: DUT output data stuck-X");
          #1;
        end
        assert (data === expected) else begin
          $display("ASSERT_FAIL 27 whole_response spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && expected[288]) begin : S_crc_fault_zero
        hits[28]=hits[28]+1;
        if (mutant==28 && !injected) begin
          force data='x;
          injected=1;
          $display("INJECT 28 crc_fault_zero: DUT output data stuck-X");
          #1;
        end
        assert (data[287:256] === 32'd0) else begin
          $display("ASSERT_FAIL 28 crc_fault_zero spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst && cancel_test) begin : S_reset_inflight
        hits[29]=hits[29]+1;
        if (mutant==29 && !injected) begin
          force valid='x;
          injected=1;
          $display("INJECT 29 reset_inflight: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0 && ready === 1'b0 && data === 289'd0) else begin
          $display("ASSERT_FAIL 29 reset_inflight spec5.3/5.5.2/7/10.3 job=%0d cycle=%0d actual=%h expected=%h",current_job,cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      stalled=rst && pv && !rsp_ready;
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
    $display("ASSERT 0 reset_ready spec5.3/5.5.2/7/10.3 hits=%0d",hits[0]);
    $display("ASSERT 1 reset_valid spec5.3/5.5.2/7/10.3 hits=%0d",hits[1]);
    $display("ASSERT 2 reset_data spec5.3/5.5.2/7/10.3 hits=%0d",hits[2]);
    $display("ASSERT 3 invalid_zero spec5.3/5.5.2/7/10.3 hits=%0d",hits[3]);
    $display("ASSERT 4 ready_known spec5.3/5.5.2/7/10.3 hits=%0d",hits[4]);
    $display("ASSERT 5 valid_known spec5.3/5.5.2/7/10.3 hits=%0d",hits[5]);
    $display("ASSERT 6 response_known spec5.3/5.5.2/7/10.3 hits=%0d",hits[6]);
    $display("ASSERT 7 no_ready_response spec5.3/5.5.2/7/10.3 hits=%0d",hits[7]);
    $display("ASSERT 8 stall_valid spec5.3/5.5.2/7/10.3 hits=%0d",hits[8]);
    $display("ASSERT 9 stall_payload spec5.3/5.5.2/7/10.3 hits=%0d",hits[9]);
    $display("ASSERT 10 crc_no_digest spec5.3/5.5.2/7/10.3 hits=%0d",hits[10]);
    $display("ASSERT 11 sha_no_crc spec5.3/5.5.2/7/10.3 hits=%0d",hits[11]);
    $display("ASSERT 12 fault_zero spec5.3/5.5.2/7/10.3 hits=%0d",hits[12]);
    $display("ASSERT 13 fault_exact spec5.3/5.5.2/7/10.3 hits=%0d",hits[13]);
    $display("ASSERT 14 crc_exact spec5.3/5.5.2/7/10.3 hits=%0d",hits[14]);
    $display("ASSERT 15 sha_word_0 spec5.3/5.5.2/7/10.3 hits=%0d",hits[15]);
    $display("ASSERT 16 sha_word_1 spec5.3/5.5.2/7/10.3 hits=%0d",hits[16]);
    $display("ASSERT 17 sha_word_2 spec5.3/5.5.2/7/10.3 hits=%0d",hits[17]);
    $display("ASSERT 18 sha_word_3 spec5.3/5.5.2/7/10.3 hits=%0d",hits[18]);
    $display("ASSERT 19 sha_word_4 spec5.3/5.5.2/7/10.3 hits=%0d",hits[19]);
    $display("ASSERT 20 sha_word_5 spec5.3/5.5.2/7/10.3 hits=%0d",hits[20]);
    $display("ASSERT 21 sha_word_6 spec5.3/5.5.2/7/10.3 hits=%0d",hits[21]);
    $display("ASSERT 22 sha_word_7 spec5.3/5.5.2/7/10.3 hits=%0d",hits[22]);
    $display("ASSERT 23 bounded_response spec5.3/5.5.2/7/10.3 hits=%0d",hits[23]);
    $display("ASSERT 24 no_early_response spec5.3/5.5.2/7/10.3 hits=%0d",hits[24]);
    $display("ASSERT 25 last_blocks_input spec5.3/5.5.2/7/10.3 hits=%0d",hits[25]);
    $display("ASSERT 26 response_has_job spec5.3/5.5.2/7/10.3 hits=%0d",hits[26]);
    $display("ASSERT 27 whole_response spec5.3/5.5.2/7/10.3 hits=%0d",hits[27]);
    $display("ASSERT 28 crc_fault_zero spec5.3/5.5.2/7/10.3 hits=%0d",hits[28]);
    $display("ASSERT 29 reset_inflight spec5.3/5.5.2/7/10.3 hits=%0d",hits[29]);
    for (integer j=0;j<30;j=j+1) if (hits[j]==0) $fatal(1,"R-025 never exercised %0d",j);
    if (mutant>=0) $fatal(1,"mutant survived");
    for (integer j=0;j<7;j=j+1) $display("LATENCY op=%0d max=%0d",j,max_latency[j]);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS codec: golden=%0d/%0d assertions=30 cycles=%0d",passed,N,cycles);
    $finish;
  end
endmodule
