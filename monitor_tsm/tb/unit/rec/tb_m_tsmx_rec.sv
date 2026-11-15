`timescale 1ns/1ps
// TSM-X / TSMX project / v0.1. Assertions: spec 5.3, 5.5.7/8/10, 7, 9.2.
// No standard bus exists on these ports. These are project valid/ready channels.
// MUTANT uses verification-only force on DUT-driven nets, never assertion operands.
module tb_m_tsmx_rec;
  reg clk=0, rst=0, req_valid=0, rsp_ready=0;
  reg [1055:0] req_data=0;
  wire ready, valid;
  wire [31:0] data;
  reg [31:0] expected=0, pending_exp=0;
  reg [1055:0] saved_req=0;
  reg pr,pv,pq,pc,take;
  reg [31:0] pd;
  integer hits[0:35];
  string assertion_name[0:35];
  string assertion_clause[0:35];
  integer mutant=-1, injected=0, cycles=0, requests=0, responses=0;
  integer wait_count;
  `include "vectors_meta.svh"
  reg [9:0] log_idx=0;
  reg log_req=0, log_consume=0;
  wire log_ready,log_valid;
  wire [1055:0] log_data;
  reg [1055:0] log_expected=0, ld;
  reg lv,lc,lt;
  reg [2156:0] vectors[0:N-1];
  reg [1:0] op;
  reg [1055:0] event_data;
  reg [31:0] event_lost;
  reg do_reset;
  reg [31:0] depth_case=4;
  reg [1055:0] depth_event;
  // The same TB also elaborates depths 1,3,64,1024 in the runner.
  parameter integer DEPTH=4;
  m_tsmx_rec #(.PARA_LOG_DEPTH(DEPTH)) dut (
    .i_clk_core(clk), .i_rst_n_core(rst), .i_req_valid(req_valid), .i_req_data(req_data),
    .i_rsp_ready(rsp_ready), .o_req_ready(ready), .o_rsp_valid(valid), .o_rsp_data(data),
    .i_log_idx(log_idx), .i_log_valid(log_req), .i_log_ready(log_consume),
    .o_log_ready(log_ready), .o_log_valid(log_valid), .o_log_data(log_data)
  );

  // Clocked immediate assertions sample before and after the acceptance edge.
  // One accepted request produces a response immediately after that edge: latency one cycle.
  task tick;
    begin
      pr=ready; pv=valid; pq=req_valid; pc=rsp_ready; pd=data;
      take=rst && pr && pq;
      if (take) begin
        saved_req=req_data; pending_exp=expected; requests=requests+1;
      end
      if (rst && pv && pc) responses=responses+1;
      lv=log_valid; lc=log_consume; ld=log_data; lt=rst && log_req && log_ready;
      #4; clk=1; #1; cycles=cycles+1;
      if (!rst) begin : S5_3_reset_ready
        hits[0]=hits[0]+1;
        if (mutant==0 && !injected) begin
          force ready = 'x;
          injected=1;
          $display("INJECT 0 S5_3_reset_ready: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 0 S5_3_reset_ready cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : S5_3_reset_valid
        hits[1]=hits[1]+1;
        if (mutant==1 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 1 S5_3_reset_valid: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 1 S5_3_reset_valid cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : S5_3_reset_data
        hits[2]=hits[2]+1;
        if (mutant==2 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 2 S5_3_reset_data: DUT output data stuck-X");
          #1;
        end
        assert (data === '0) else begin
          $display("ASSERT_FAIL 2 S5_3_reset_data cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !valid) begin : S5_3_invalid_zero
        hits[3]=hits[3]+1;
        if (mutant==3 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 3 S5_3_invalid_zero: DUT output data stuck-X");
          #1;
        end
        assert (data === '0) else begin
          $display("ASSERT_FAIL 3 S5_3_invalid_zero cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : S5_3_ready_known
        hits[4]=hits[4]+1;
        if (mutant==4 && !injected) begin
          force ready = 'x;
          injected=1;
          $display("INJECT 4 S5_3_ready_known: DUT output ready stuck-X");
          #1;
        end
        assert (!$isunknown(ready)) else begin
          $display("ASSERT_FAIL 4 S5_3_ready_known cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : S5_3_valid_known
        hits[5]=hits[5]+1;
        if (mutant==5 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 5 S5_3_valid_known: DUT output valid stuck-X");
          #1;
        end
        assert (!$isunknown(valid)) else begin
          $display("ASSERT_FAIL 5 S5_3_valid_known cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : S5_3_valid_data_known
        hits[6]=hits[6]+1;
        if (mutant==6 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 6 S5_3_valid_data_known: DUT output data stuck-X");
          #1;
        end
        assert (!$isunknown(data)) else begin
          $display("ASSERT_FAIL 6 S5_3_valid_data_known cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : S5_3_single_outstanding
        hits[7]=hits[7]+1;
        if (mutant==7 && !injected) begin
          force ready = 'x;
          injected=1;
          $display("INJECT 7 S5_3_single_outstanding: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 7 S5_3_single_outstanding cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && take) begin : S5_3_accept_completes_1cy
        hits[8]=hits[8]+1;
        if (mutant==8 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 8 S5_3_accept_completes_1cy: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 8 S5_3_accept_completes_1cy cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && take) begin : S5_3_atomic_response
        hits[9]=hits[9]+1;
        if (mutant==9 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 9 S5_3_atomic_response: DUT output data stuck-X");
          #1;
        end
        assert (data === expected) else begin
          $display("ASSERT_FAIL 9 S5_3_atomic_response cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : S5_3_stall_valid
        hits[10]=hits[10]+1;
        if (mutant==10 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 10 S5_3_stall_valid: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 10 S5_3_stall_valid cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : S5_3_stall_payload
        hits[11]=hits[11]+1;
        if (mutant==11 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 11 S5_3_stall_payload: DUT output data stuck-X");
          #1;
        end
        assert (data === pd) else begin
          $display("ASSERT_FAIL 11 S5_3_stall_payload cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : S5_3_stall_blocks_req
        hits[12]=hits[12]+1;
        if (mutant==12 && !injected) begin
          force ready = 'x;
          injected=1;
          $display("INJECT 12 S5_3_stall_blocks_req: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 12 S5_3_stall_blocks_req cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : S5_3_consume_valid
        hits[13]=hits[13]+1;
        if (mutant==13 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 13 S5_3_consume_valid: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 13 S5_3_consume_valid cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : S5_3_consume_payload
        hits[14]=hits[14]+1;
        if (mutant==14 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 14 S5_3_consume_payload: DUT output data stuck-X");
          #1;
        end
        assert (data === '0) else begin
          $display("ASSERT_FAIL 14 S5_3_consume_payload cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !pv && !take) begin : S5_3_no_unsolicited
        hits[15]=hits[15]+1;
        if (mutant==15 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 15 S5_3_no_unsolicited: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 15 S5_3_no_unsolicited cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pr && !pq) begin : S5_3_idle_ready
        hits[16]=hits[16]+1;
        if (mutant==16 && !injected) begin
          force ready = 'x;
          injected=1;
          $display("INJECT 16 S5_3_idle_ready: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 16 S5_3_idle_ready cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !pr && !pv) begin : S5_3_release_ready
        hits[17]=hits[17]+1;
        if (mutant==17 && !injected) begin
          force ready = 'x;
          injected=1;
          $display("INJECT 17 S5_3_release_ready: DUT output ready stuck-X");
          #1;
        end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 17 S5_3_release_ready cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid) begin : B10_lost_exact
        hits[18]=hits[18]+1;
        if (mutant==18 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 18 B10_lost_exact: DUT output data stuck-X");
          #1;
        end
        assert (data === pending_exp) else begin
          $display("ASSERT_FAIL 18 B10_lost_exact cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && valid && pending_exp==32'hffffffff) begin : B10_saturation
        hits[19]=hits[19]+1;
        if (mutant==19 && !injected) begin
          force data = 'x;
          injected=1;
          $display("INJECT 19 B10_saturation: DUT output data stuck-X");
          #1;
        end
        assert (data === 32'hffffffff) else begin
          $display("ASSERT_FAIL 19 B10_saturation cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : B10_reset_log_ready
        hits[20]=hits[20]+1;
        if (mutant==20 && !injected) begin
          force log_ready = 'x;
          injected=1;
          $display("INJECT 20 B10_reset_log_ready: DUT output log_ready stuck-X");
          #1;
        end
        assert (log_ready === 1'b0) else begin
          $display("ASSERT_FAIL 20 B10_reset_log_ready cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : B10_reset_log_valid
        hits[21]=hits[21]+1;
        if (mutant==21 && !injected) begin
          force log_valid = 'x;
          injected=1;
          $display("INJECT 21 B10_reset_log_valid: DUT output log_valid stuck-X");
          #1;
        end
        assert (log_valid === 1'b0) else begin
          $display("ASSERT_FAIL 21 B10_reset_log_valid cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : B10_reset_log_data
        hits[22]=hits[22]+1;
        if (mutant==22 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 22 B10_reset_log_data: DUT output log_data stuck-X");
          #1;
        end
        assert (log_data === '0) else begin
          $display("ASSERT_FAIL 22 B10_reset_log_data cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !log_valid) begin : B10_log_invalid_zero
        hits[23]=hits[23]+1;
        if (mutant==23 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 23 B10_log_invalid_zero: DUT output log_data stuck-X");
          #1;
        end
        assert (log_data === '0) else begin
          $display("ASSERT_FAIL 23 B10_log_invalid_zero cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : B10_log_ready_known
        hits[24]=hits[24]+1;
        if (mutant==24 && !injected) begin
          force log_ready = 'x;
          injected=1;
          $display("INJECT 24 B10_log_ready_known: DUT output log_ready stuck-X");
          #1;
        end
        assert (!$isunknown(log_ready)) else begin
          $display("ASSERT_FAIL 24 B10_log_ready_known cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : B10_log_valid_known
        hits[25]=hits[25]+1;
        if (mutant==25 && !injected) begin
          force log_valid = 'x;
          injected=1;
          $display("INJECT 25 B10_log_valid_known: DUT output log_valid stuck-X");
          #1;
        end
        assert (!$isunknown(log_valid)) else begin
          $display("ASSERT_FAIL 25 B10_log_valid_known cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && log_valid) begin : B10_log_data_known
        hits[26]=hits[26]+1;
        if (mutant==26 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 26 B10_log_data_known: DUT output log_data stuck-X");
          #1;
        end
        assert (!$isunknown(log_data)) else begin
          $display("ASSERT_FAIL 26 B10_log_data_known cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && log_valid) begin : B10_log_single
        hits[27]=hits[27]+1;
        if (mutant==27 && !injected) begin
          force log_ready = 'x;
          injected=1;
          $display("INJECT 27 B10_log_single: DUT output log_ready stuck-X");
          #1;
        end
        assert (log_ready === 1'b0) else begin
          $display("ASSERT_FAIL 27 B10_log_single cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lt) begin : B10_read_completes_1cy
        hits[28]=hits[28]+1;
        if (mutant==28 && !injected) begin
          force log_valid = 'x;
          injected=1;
          $display("INJECT 28 B10_read_completes_1cy: DUT output log_valid stuck-X");
          #1;
        end
        assert (log_valid === 1'b1) else begin
          $display("ASSERT_FAIL 28 B10_read_completes_1cy cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lt) begin : B10_prewrite_snapshot
        hits[29]=hits[29]+1;
        if (mutant==29 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 29 B10_prewrite_snapshot: DUT output log_data stuck-X");
          #1;
        end
        assert (log_data === log_expected) else begin
          $display("ASSERT_FAIL 29 B10_prewrite_snapshot cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lv && !lc) begin : B10_log_stall_valid
        hits[30]=hits[30]+1;
        if (mutant==30 && !injected) begin
          force log_valid = 'x;
          injected=1;
          $display("INJECT 30 B10_log_stall_valid: DUT output log_valid stuck-X");
          #1;
        end
        assert (log_valid === 1'b1) else begin
          $display("ASSERT_FAIL 30 B10_log_stall_valid cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lv && !lc) begin : B10_log_stall_data
        hits[31]=hits[31]+1;
        if (mutant==31 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 31 B10_log_stall_data: DUT output log_data stuck-X");
          #1;
        end
        assert (log_data === ld) else begin
          $display("ASSERT_FAIL 31 B10_log_stall_data cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lv && lc) begin : B10_log_consumed_valid
        hits[32]=hits[32]+1;
        if (mutant==32 && !injected) begin
          force log_valid = 'x;
          injected=1;
          $display("INJECT 32 B10_log_consumed_valid: DUT output log_valid stuck-X");
          #1;
        end
        assert (log_valid === 1'b0) else begin
          $display("ASSERT_FAIL 32 B10_log_consumed_valid cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lv && lc) begin : B10_log_consumed_data
        hits[33]=hits[33]+1;
        if (mutant==33 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 33 B10_log_consumed_data: DUT output log_data stuck-X");
          #1;
        end
        assert (log_data === '0) else begin
          $display("ASSERT_FAIL 33 B10_log_consumed_data cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && take && lv && !lc) begin : B10_write_while_log_stall
        hits[34]=hits[34]+1;
        if (mutant==34 && !injected) begin
          force valid = 'x;
          injected=1;
          $display("INJECT 34 B10_write_while_log_stall: DUT output valid stuck-X");
          #1;
        end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 34 B10_write_while_log_stall cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && lt && log_idx==1023 && DEPTH<1024) begin : B10_invalid_index
        hits[35]=hits[35]+1;
        if (mutant==35 && !injected) begin
          force log_data = 'x;
          injected=1;
          $display("INJECT 35 B10_invalid_index: DUT output log_data stuck-X");
          #1;
        end
        assert (log_data === '0) else begin
          $display("ASSERT_FAIL 35 B10_invalid_index cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
      #5; clk=0; #1;
    end
  endtask

  task reset_dut;
    begin
      rst=0;req_valid=0;rsp_ready=0;
      log_req=0;log_consume=0;
      #1;tick;tick;rst=1;tick;
    end
  endtask

  // Bounded waits make dead handshakes fail rather than hang a regression.
  task wait_ready;
    begin
      wait_count=0;
      while (!ready && wait_count<8) begin tick;wait_count=wait_count+1;end
      if (!ready) $fatal(1,"request timeout");
    end
  endtask
  task drain_write;
    begin
      req_valid=0;
      // Exercise long response stalls with a changing invalid input payload.
      repeat(3) begin req_data=~req_data;tick;end
      rsp_ready=1;tick;rsp_ready=0;tick;
    end
  endtask
  task drain_log;
    begin
      log_req=0;
      repeat(3) tick;
      log_consume=1;tick;log_consume=0;tick;
    end
  endtask
  initial begin
    for(integer j=0;j<36;j=j+1) hits[j]=0;
    assertion_name[0]="S5_3_reset_ready";assertion_clause[0]="spec 5.3";
    assertion_name[1]="S5_3_reset_valid";assertion_clause[1]="spec 5.3";
    assertion_name[2]="S5_3_reset_data";assertion_clause[2]="spec 5.3";
    assertion_name[3]="S5_3_invalid_zero";assertion_clause[3]="spec 5.3";
    assertion_name[4]="S5_3_ready_known";assertion_clause[4]="spec 5.3";
    assertion_name[5]="S5_3_valid_known";assertion_clause[5]="spec 5.3";
    assertion_name[6]="S5_3_valid_data_known";assertion_clause[6]="spec 5.3";
    assertion_name[7]="S5_3_single_outstanding";assertion_clause[7]="spec 5.3";
    assertion_name[8]="S5_3_accept_completes_1cy";assertion_clause[8]="spec 5.3";
    assertion_name[9]="S5_3_atomic_response";assertion_clause[9]="spec 5.3";
    assertion_name[10]="S5_3_stall_valid";assertion_clause[10]="spec 5.3";
    assertion_name[11]="S5_3_stall_payload";assertion_clause[11]="spec 5.3";
    assertion_name[12]="S5_3_stall_blocks_req";assertion_clause[12]="spec 5.3";
    assertion_name[13]="S5_3_consume_valid";assertion_clause[13]="spec 5.3";
    assertion_name[14]="S5_3_consume_payload";assertion_clause[14]="spec 5.3";
    assertion_name[15]="S5_3_no_unsolicited";assertion_clause[15]="spec 5.3";
    assertion_name[16]="S5_3_idle_ready";assertion_clause[16]="spec 5.3";
    assertion_name[17]="S5_3_release_ready";assertion_clause[17]="spec 5.3";
    assertion_name[18]="B10_lost_exact";assertion_clause[18]="spec 5.5.10/9.2";
    assertion_name[19]="B10_saturation";assertion_clause[19]="spec 5.5.10/9.2";
    assertion_name[20]="B10_reset_log_ready";assertion_clause[20]="spec 5.5.10/9.2";
    assertion_name[21]="B10_reset_log_valid";assertion_clause[21]="spec 5.5.10/9.2";
    assertion_name[22]="B10_reset_log_data";assertion_clause[22]="spec 5.5.10/9.2";
    assertion_name[23]="B10_log_invalid_zero";assertion_clause[23]="spec 5.5.10/9.2";
    assertion_name[24]="B10_log_ready_known";assertion_clause[24]="spec 5.5.10/9.2";
    assertion_name[25]="B10_log_valid_known";assertion_clause[25]="spec 5.5.10/9.2";
    assertion_name[26]="B10_log_data_known";assertion_clause[26]="spec 5.5.10/9.2";
    assertion_name[27]="B10_log_single";assertion_clause[27]="spec 5.5.10/9.2";
    assertion_name[28]="B10_read_completes_1cy";assertion_clause[28]="spec 5.5.10/9.2";
    assertion_name[29]="B10_prewrite_snapshot";assertion_clause[29]="spec 5.5.10/9.2";
    assertion_name[30]="B10_log_stall_valid";assertion_clause[30]="spec 5.5.10/9.2";
    assertion_name[31]="B10_log_stall_data";assertion_clause[31]="spec 5.5.10/9.2";
    assertion_name[32]="B10_log_consumed_valid";assertion_clause[32]="spec 5.5.10/9.2";
    assertion_name[33]="B10_log_consumed_data";assertion_clause[33]="spec 5.5.10/9.2";
    assertion_name[34]="B10_write_while_log_stall";assertion_clause[34]="spec 5.5.10/9.2";
    assertion_name[35]="B10_invalid_index";assertion_clause[35]="spec 5.5.10/9.2";
    if ($value$plusargs("MUTANT=%d",mutant)) begin end
    $readmemh("vectors.mem",vectors);
    reset_dut;
    if (DEPTH==4) begin
      for(integer j=0;j<N;j=j+1) begin
        {do_reset,op,event_data,event_lost,log_idx,log_expected}=vectors[j];
        if(do_reset) reset_dut;
        case(op)
          2'd0: begin
            wait_ready; req_data=event_data;expected=event_lost;req_valid=1;tick;
            drain_write;
          end
          2'd1: begin
            log_req=1;tick;drain_log;
          end
          2'd2: begin
            wait_ready;req_data=event_data;expected=event_lost;
            req_valid=1;log_req=1;tick;
            req_valid=0;log_req=0;
            // Writes must complete while the independent log response stays stalled.
            drain_write;drain_log;
          end
          2'd3: begin
            // Verification-only deposit avoids four billion writes for saturation.
            dut.reg_lost=event_lost;
            #1;
          end
          default: $fatal(1,"bad operation");
        endcase
      end
      // Hold an indexed snapshot and append a new event while it remains stalled.
      log_idx=0;log_req=1;tick;log_req=0;
      wait_ready;req_data={1'b1,3'd0,1052'd0};expected=0;req_valid=1;tick;
      drain_write;drain_log;
    end else begin
      // Independent non-power-of-two/depth boundary test, preserving oldest order.
      for(integer k=0;k<DEPTH+3;k=k+1) begin
        depth_event={1'b1,3'd1,7'd0,192'd0,64'(k),789'd0};
        wait_ready;req_data=depth_event;expected=(k<DEPTH)?0:k-DEPTH+1;
        req_valid=1;tick;drain_write;
      end
      for(integer k=0;k<DEPTH;k=k+1) begin
        log_idx=10'(k);log_expected={1'b1,3'd1,7'd0,192'd0,64'(k+3),789'd0};
        log_req=1;tick;drain_log;
      end
    end
    wait_ready;req_data=0;expected=0;
    req_data={1'b1,3'd0,1052'd0};expected=(DEPTH==4)?0:4;
    req_valid=1;tick;req_valid=0;
    reset_dut;
    // Spec5.3: hold the second request until ready after response drain.
    wait_ready;
    req_data={1'b1,3'd0,1052'd0};expected=0;
    req_valid=1;tick;
    req_data={1'b1,3'd0,1052'd0};expected=(DEPTH==1)?1:0;
    repeat(3) tick;
    rsp_ready=1;tick;rsp_ready=0;
    // Valid and the second payload remain unchanged until this acceptance.
    tick;drain_write;
    for(integer j=0;j<36;j=j+1) begin
      $display("ASSERT_HITS %0d %s %s hits=%0d",j,assertion_name[j],assertion_clause[j],hits[j]);
      if (DEPTH==4 && hits[j]==0) $fatal(1,"R-025 assertion never exercised: %0d",j);
    end
    if(mutant>=0) $fatal(1,"mutant survived: %0d",mutant);
    if(DEPTH==4) begin
      $display("PASS rec: golden=%0d/%0d rows=%0d assertions=36 requests=%0d responses=%0d cycles=%0d",GOLDEN,GOLDEN,N,requests,responses,cycles);
      $display("assertion failures: 0, assertions never exercised: 0");
    end else begin
      $display("PASS rec supplementary depth=%0d: %0d boundary writes, %0d indexed reads",DEPTH,DEPTH+3,DEPTH);
      $display("Supplementary assertion activity is a subset; full activity checked at depth=4.");
    end

    $finish;
  end
  initial begin #100000000; $fatal(1,"watchdog timeout");end
endmodule
