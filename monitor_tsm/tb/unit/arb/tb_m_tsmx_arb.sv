`timescale 1ns/1ps
// Project TSM-X; author TSMX project; version0.1.
// REQ-TSMX-024; spec5.3,5.5.13,6.2,9.2. Custom valid/ready, no standard bus.
// Mutations flip actual DUT observation wires; assertion operands are unchanged.
module tb_m_tsmx_arb;
  logic clk=0, rst=0, req_valid=0, rsp_ready=0, ov=0;
  logic [3862:0] req_data='0;
  wire raw_ready,raw_valid,raw_brake;
  wire [1996:0] raw_data;
  wire ready,valid,brake;
  wire [1996:0] data;
  logic flip_ready=0,flip_valid=0,flip_brake=0;
  logic [1996:0] flip_data='0;
  assign ready=raw_ready ^ flip_ready;
  assign valid=raw_valid ^ flip_valid;
  assign brake=raw_brake ^ flip_brake;
  assign data=raw_data ^ flip_data;
  `include "vectors_meta.svh"
  logic [5861:0] vectors[0:N-1];
  logic [1996:0] expected,pending_exp,pd;
  logic pr,pv,pc,take,model_brake=1,revoked=0,expected_brake;
  integer cycles=0,requests=0,responses=0,mutant=-1,injected=0;
  integer accepted_cycle=0,last_accept=0,min_ii=999999,max_ii=0,ii;
  integer min_latency=999999,max_latency=0,latency;
  integer hits[0:36-1];
  m_tsmx_arb dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),
    .i_req_data(req_data),.i_rsp_ready(rsp_ready),.i_override(ov),
    .o_req_ready(raw_ready),.o_rsp_valid(raw_valid),.o_rsp_data(raw_data),.o_brake(raw_brake));
  task tick;
    begin
      pr=raw_ready; pv=raw_valid; pc=rsp_ready; pd=raw_data;
      take=rst && pr && req_valid;
      if (take) begin
        pending_exp=expected; requests++;
        accepted_cycle=cycles+1;
        if (last_accept!=0) begin
          ii=accepted_cycle-last_accept;
          if (ii<min_ii) min_ii=ii;
          if (ii>max_ii) max_ii=ii;
        end
        last_accept=accepted_cycle;
      end
      if (rst && pv && pc) responses++;
      if (!rst) begin model_brake=1; revoked=0; end
      else begin
        if (take) begin model_brake=expected_brake; revoked=0; end
        if (ov) begin model_brake=1; revoked=1; end
      end
      #4; clk=1; #1; cycles++;
      if(take && raw_valid) begin
        latency=cycles-accepted_cycle+1;
        if(latency<min_latency) min_latency=latency;
        if(latency>max_latency) max_latency=latency;
      end
      if (!rst) begin : a_reset_ready
        // spec5.3
        hits[0]++;
        if(mutant==0 && !injected) begin flip_ready=1'b1; injected=1; #1; end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 0 reset_ready cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_valid
        // spec5.3
        hits[1]++;
        if(mutant==1 && !injected) begin flip_valid=1'b1; injected=1; #1; end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 1 reset_valid cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_payload
        // spec5.3
        hits[2]++;
        if(mutant==2 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data === 1997'd0) else begin
          $display("ASSERT_FAIL 2 reset_payload cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_brake
        // spec5.5.13
        hits[3]++;
        if(mutant==3 && !injected) begin flip_brake=1'b1; injected=1; #1; end
        assert (brake === 1'b1) else begin
          $display("ASSERT_FAIL 3 reset_brake cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !raw_valid) begin : a_invalid_zero
        // spec5.3
        hits[4]++;
        if(mutant==4 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data === 1997'd0) else begin
          $display("ASSERT_FAIL 4 invalid_zero cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && raw_valid) begin : a_no_overlap
        // spec5.3
        hits[5]++;
        if(mutant==5 && !injected) begin flip_ready=1'b1; injected=1; #1; end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 5 no_overlap cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_latency_one
        // spec5.3
        hits[6]++;
        if(mutant==6 && !injected) begin flip_valid=1'b1; injected=1; #1; end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 6 latency_one cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_whole_command
        // spec5.5.13/9.2
        hits[7]++;
        if(mutant==7 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data === pending_exp) else begin
          $display("ASSERT_FAIL 7 whole_command cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : a_hold_valid
        // spec5.3
        hits[8]++;
        if(mutant==8 && !injected) begin flip_valid=1'b1; injected=1; #1; end
        assert (valid === 1'b1) else begin
          $display("ASSERT_FAIL 8 hold_valid cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc) begin : a_hold_payload
        // spec5.3
        hits[9]++;
        if(mutant==9 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data === pd) else begin
          $display("ASSERT_FAIL 9 hold_payload cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : a_consume_valid
        // spec5.3
        hits[10]++;
        if(mutant==10 && !injected) begin flip_valid=1'b1; injected=1; #1; end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 10 consume_valid cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && pc) begin : a_consume_zero
        // spec5.3
        hits[11]++;
        if(mutant==11 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data === 1997'd0) else begin
          $display("ASSERT_FAIL 11 consume_zero cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !raw_valid) begin : a_idle_ready
        // spec5.3
        hits[12]++;
        if(mutant==12 && !injected) begin flip_ready=1'b1; injected=1; #1; end
        assert (ready === 1'b1) else begin
          $display("ASSERT_FAIL 12 idle_ready cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !pv && !take) begin : a_idle_no_spurious_response
        // spec5.3
        hits[13]++;
        if(mutant==13 && !injected) begin flip_valid=1'b1; injected=1; #1; end
        assert (valid === 1'b0) else begin
          $display("ASSERT_FAIL 13 idle_no_spurious_response cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_accepted_busy
        // spec5.3
        hits[14]++;
        if(mutant==14 && !injected) begin flip_ready=1'b1; injected=1; #1; end
        assert (ready === 1'b0) else begin
          $display("ASSERT_FAIL 14 accepted_busy cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_brake_model
        // spec5.5.13/6.2
        hits[15]++;
        if(mutant==15 && !injected) begin flip_brake=1'b1; injected=1; #1; end
        assert (brake === (!rst || ov || model_brake)) else begin
          $display("ASSERT_FAIL 15 brake_model cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (ov) begin : a_override_immediate
        // spec6.2
        hits[16]++;
        if(mutant==16 && !injected) begin flip_brake=1'b1; injected=1; #1; end
        assert (brake === 1'b1) else begin
          $display("ASSERT_FAIL 16 override_immediate cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && revoked && !ov) begin : a_sticky_revocation
        // spec6.2
        hits[17]++;
        if(mutant==17 && !injected) begin flip_brake=1'b1; injected=1; #1; end
        assert (brake === 1'b1) else begin
          $display("ASSERT_FAIL 17 sticky_revocation cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pv && !pc && ov) begin : a_override_frame_stable
        // spec6.2
        hits[18]++;
        if(mutant==18 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data === pd) else begin
          $display("ASSERT_FAIL 18 override_frame_stable cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_reserved_zero
        // spec9.2
        hits[19]++;
        if(mutant==19 && !injected) begin flip_data[1996]=1'b1; injected=1; #1; end
        assert (data[1996:1897] === 100'd0) else begin
          $display("ASSERT_FAIL 19 reserved_zero cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_source
        // spec9.2/5.5.13
        hits[20]++;
        if(mutant==20 && !injected) begin flip_data[1894]=1'b1; injected=1; #1; end
        assert (data[1896:1894] === pending_exp[1896:1894]) else begin
          $display("ASSERT_FAIL 20 field_source cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_mode
        // spec9.2/5.5.13
        hits[21]++;
        if(mutant==21 && !injected) begin flip_data[1891]=1'b1; injected=1; #1; end
        assert (data[1893:1891] === pending_exp[1893:1891]) else begin
          $display("ASSERT_FAIL 21 field_mode cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_label
        // spec9.2/5.5.13
        hits[22]++;
        if(mutant==22 && !injected) begin flip_data[1883]=1'b1; injected=1; #1; end
        assert (data[1890:1883] === pending_exp[1890:1883]) else begin
          $display("ASSERT_FAIL 22 field_label cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_candidate
        // spec9.2/5.5.13
        hits[23]++;
        if(mutant==23 && !injected) begin flip_data[1875]=1'b1; injected=1; #1; end
        assert (data[1882:1875] === pending_exp[1882:1875]) else begin
          $display("ASSERT_FAIL 23 field_candidate cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_seq
        // spec9.2/5.5.13
        hits[24]++;
        if(mutant==24 && !injected) begin flip_data[1843]=1'b1; injected=1; #1; end
        assert (data[1874:1843] === pending_exp[1874:1843]) else begin
          $display("ASSERT_FAIL 24 field_seq cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_apply
        // spec9.2/5.5.13
        hits[25]++;
        if(mutant==25 && !injected) begin flip_data[1811]=1'b1; injected=1; #1; end
        assert (data[1842:1811] === pending_exp[1842:1811]) else begin
          $display("ASSERT_FAIL 25 field_apply cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_expiry
        // spec9.2/5.5.13
        hits[26]++;
        if(mutant==26 && !injected) begin flip_data[1779]=1'b1; injected=1; #1; end
        assert (data[1810:1779] === pending_exp[1810:1779]) else begin
          $display("ASSERT_FAIL 26 field_expiry cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_plan
        // spec9.2/5.5.13
        hits[27]++;
        if(mutant==27 && !injected) begin flip_data[1219]=1'b1; injected=1; #1; end
        assert (data[1778:1219] === pending_exp[1778:1219]) else begin
          $display("ASSERT_FAIL 27 field_plan cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_certificate
        // spec9.2/5.5.13
        hits[28]++;
        if(mutant==28 && !injected) begin flip_data[2]=1'b1; injected=1; #1; end
        assert (data[1218:2] === pending_exp[1218:2]) else begin
          $display("ASSERT_FAIL 28 field_certificate cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_parking
        // spec9.2/5.5.13
        hits[29]++;
        if(mutant==29 && !injected) begin flip_data[1]=1'b1; injected=1; #1; end
        assert (data[1:1] === pending_exp[1:1]) else begin
          $display("ASSERT_FAIL 29 field_parking cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take) begin : a_field_override
        // spec9.2/5.5.13
        hits[30]++;
        if(mutant==30 && !injected) begin flip_data[0]=1'b1; injected=1; #1; end
        assert (data[0:0] === pending_exp[0:0]) else begin
          $display("ASSERT_FAIL 30 field_override cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take && pending_exp[1896:1894]==3) begin : a_L3_fixed15
        // specREQ-TSMX-024
        hits[31]++;
        if(mutant==31 && !injected) begin flip_data[1875]=1'b1; injected=1; #1; end
        assert (data[1882:1875] === 8'd15) else begin
          $display("ASSERT_FAIL 31 L3_fixed15 cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take && pending_exp[1896:1894]==0) begin : a_nominal_record
        // spec5.5.13
        hits[32]++;
        if(mutant==32 && !injected) begin flip_data[1219]=1'b1; injected=1; #1; end
        assert (data[1778:1219] === pending_exp[1778:1219]) else begin
          $display("ASSERT_FAIL 32 nominal_record cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take && pending_exp[1896:1894]==1) begin : a_backup_epoch
        // spec5.5.13
        hits[33]++;
        if(mutant==33 && !injected) begin flip_data[1811]=1'b1; injected=1; #1; end
        assert (data[1842:1811] === pending_exp[1842:1811]) else begin
          $display("ASSERT_FAIL 33 backup_epoch cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take && pending_exp[1896:1894]==2) begin : a_fallback_candidate
        // spec5.5.13
        hits[34]++;
        if(mutant==34 && !injected) begin flip_data[1875]=1'b1; injected=1; #1; end
        assert (data[1882:1875] === pending_exp[1882:1875]) else begin
          $display("ASSERT_FAIL 34 fallback_candidate cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (take && pending_exp[1896:1894]==4) begin : a_parking_hold
        // spec5.5.13
        hits[35]++;
        if(mutant==35 && !injected) begin flip_data[1]=1'b1; injected=1; #1; end
        assert (data[1:1] === pending_exp[1:1]) else begin
          $display("ASSERT_FAIL 35 parking_hold cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end
      #4; clk=0; #1;
    end
  endtask
  initial begin
    for(integer i=0;i<36;i++) hits[i]=0;
    if($value$plusargs("MUTANT=%d",mutant)) begin end
    $readmemh("vectors.mem",vectors);
    expected='0; expected_brake=1;
    tick(); tick(); rst=1; tick();
    for(integer i=0;i<N;i++) begin
      if(!raw_ready) $fatal(1,"unexpected busy");
      {req_data,expected,ov,expected_brake}=vectors[i];
      req_valid=1; rsp_ready=0; tick(); req_valid=0;
      // Bounded stalls and noisy inactive input cannot change a held frame.
      for(integer j=0;j<(i%4);j++) begin
        req_data=~req_data; tick();
      end
      // Timer/watchdog overrides a stalled response at subcycle granularity.
      if(i%19==0 || i==EXPIRY_STALL) begin
        if(i==EXPIRY_STALL) begin
          if(raw_brake!==1'b0) $fatal(1,"nominal command was not authorized");
          $display("DIRECTED B9 expiry_at_executor while command stalled: now=100000");
        end
        ov=1; #1;
        if(raw_brake!==1'b1) $fatal(1,"asynchronous override missed");
        tick(); ov=0; tick();
      end
      rsp_ready=1; tick(); rsp_ready=0; ov=0;
    end
    // Queued producer keeps valid/data stable through response stalls and consumption.
    {req_data,expected,ov,expected_brake}=vectors[0];
    req_valid=1; tick();
    tick(); tick(); rsp_ready=1; tick();
    // The held second request is now accepted; it did not replace the first on consume.
    rsp_ready=0; tick(); req_valid=0;
    rsp_ready=1; tick(); rsp_ready=0;
    // Reset aborts an accepted/stalled job without a stale response after release.
    {req_data,expected,ov,expected_brake}=vectors[0];
    req_valid=1; tick(); req_valid=0; rst=0; tick(); rst=1; tick(); tick();
    if(raw_valid) $fatal(1,"stale response after reset");
    if(requests!=responses+1) $fatal(1,"request accounting");
    if(hits[0]==0) $fatal(1,"unexercised assertion 0");
    $display("ASSERT 0 reset_ready spec5.3 hits=%0d",hits[0]);
    if(hits[1]==0) $fatal(1,"unexercised assertion 1");
    $display("ASSERT 1 reset_valid spec5.3 hits=%0d",hits[1]);
    if(hits[2]==0) $fatal(1,"unexercised assertion 2");
    $display("ASSERT 2 reset_payload spec5.3 hits=%0d",hits[2]);
    if(hits[3]==0) $fatal(1,"unexercised assertion 3");
    $display("ASSERT 3 reset_brake spec5.5.13 hits=%0d",hits[3]);
    if(hits[4]==0) $fatal(1,"unexercised assertion 4");
    $display("ASSERT 4 invalid_zero spec5.3 hits=%0d",hits[4]);
    if(hits[5]==0) $fatal(1,"unexercised assertion 5");
    $display("ASSERT 5 no_overlap spec5.3 hits=%0d",hits[5]);
    if(hits[6]==0) $fatal(1,"unexercised assertion 6");
    $display("ASSERT 6 latency_one spec5.3 hits=%0d",hits[6]);
    if(hits[7]==0) $fatal(1,"unexercised assertion 7");
    $display("ASSERT 7 whole_command spec5.5.13/9.2 hits=%0d",hits[7]);
    if(hits[8]==0) $fatal(1,"unexercised assertion 8");
    $display("ASSERT 8 hold_valid spec5.3 hits=%0d",hits[8]);
    if(hits[9]==0) $fatal(1,"unexercised assertion 9");
    $display("ASSERT 9 hold_payload spec5.3 hits=%0d",hits[9]);
    if(hits[10]==0) $fatal(1,"unexercised assertion 10");
    $display("ASSERT 10 consume_valid spec5.3 hits=%0d",hits[10]);
    if(hits[11]==0) $fatal(1,"unexercised assertion 11");
    $display("ASSERT 11 consume_zero spec5.3 hits=%0d",hits[11]);
    if(hits[12]==0) $fatal(1,"unexercised assertion 12");
    $display("ASSERT 12 idle_ready spec5.3 hits=%0d",hits[12]);
    if(hits[13]==0) $fatal(1,"unexercised assertion 13");
    $display("ASSERT 13 idle_no_spurious_response spec5.3 hits=%0d",hits[13]);
    if(hits[14]==0) $fatal(1,"unexercised assertion 14");
    $display("ASSERT 14 accepted_busy spec5.3 hits=%0d",hits[14]);
    if(hits[15]==0) $fatal(1,"unexercised assertion 15");
    $display("ASSERT 15 brake_model spec5.5.13/6.2 hits=%0d",hits[15]);
    if(hits[16]==0) $fatal(1,"unexercised assertion 16");
    $display("ASSERT 16 override_immediate spec6.2 hits=%0d",hits[16]);
    if(hits[17]==0) $fatal(1,"unexercised assertion 17");
    $display("ASSERT 17 sticky_revocation spec6.2 hits=%0d",hits[17]);
    if(hits[18]==0) $fatal(1,"unexercised assertion 18");
    $display("ASSERT 18 override_frame_stable spec6.2 hits=%0d",hits[18]);
    if(hits[19]==0) $fatal(1,"unexercised assertion 19");
    $display("ASSERT 19 reserved_zero spec9.2 hits=%0d",hits[19]);
    if(hits[20]==0) $fatal(1,"unexercised assertion 20");
    $display("ASSERT 20 field_source spec9.2/5.5.13 hits=%0d",hits[20]);
    if(hits[21]==0) $fatal(1,"unexercised assertion 21");
    $display("ASSERT 21 field_mode spec9.2/5.5.13 hits=%0d",hits[21]);
    if(hits[22]==0) $fatal(1,"unexercised assertion 22");
    $display("ASSERT 22 field_label spec9.2/5.5.13 hits=%0d",hits[22]);
    if(hits[23]==0) $fatal(1,"unexercised assertion 23");
    $display("ASSERT 23 field_candidate spec9.2/5.5.13 hits=%0d",hits[23]);
    if(hits[24]==0) $fatal(1,"unexercised assertion 24");
    $display("ASSERT 24 field_seq spec9.2/5.5.13 hits=%0d",hits[24]);
    if(hits[25]==0) $fatal(1,"unexercised assertion 25");
    $display("ASSERT 25 field_apply spec9.2/5.5.13 hits=%0d",hits[25]);
    if(hits[26]==0) $fatal(1,"unexercised assertion 26");
    $display("ASSERT 26 field_expiry spec9.2/5.5.13 hits=%0d",hits[26]);
    if(hits[27]==0) $fatal(1,"unexercised assertion 27");
    $display("ASSERT 27 field_plan spec9.2/5.5.13 hits=%0d",hits[27]);
    if(hits[28]==0) $fatal(1,"unexercised assertion 28");
    $display("ASSERT 28 field_certificate spec9.2/5.5.13 hits=%0d",hits[28]);
    if(hits[29]==0) $fatal(1,"unexercised assertion 29");
    $display("ASSERT 29 field_parking spec9.2/5.5.13 hits=%0d",hits[29]);
    if(hits[30]==0) $fatal(1,"unexercised assertion 30");
    $display("ASSERT 30 field_override spec9.2/5.5.13 hits=%0d",hits[30]);
    if(hits[31]==0) $fatal(1,"unexercised assertion 31");
    $display("ASSERT 31 L3_fixed15 specREQ-TSMX-024 hits=%0d",hits[31]);
    if(hits[32]==0) $fatal(1,"unexercised assertion 32");
    $display("ASSERT 32 nominal_record spec5.5.13 hits=%0d",hits[32]);
    if(hits[33]==0) $fatal(1,"unexercised assertion 33");
    $display("ASSERT 33 backup_epoch spec5.5.13 hits=%0d",hits[33]);
    if(hits[34]==0) $fatal(1,"unexercised assertion 34");
    $display("ASSERT 34 fallback_candidate spec5.5.13 hits=%0d",hits[34]);
    if(hits[35]==0) $fatal(1,"unexercised assertion 35");
    $display("ASSERT 35 parking_hold spec5.5.13 hits=%0d",hits[35]);
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("MEASURED cycles/job=%0d..%0d II=%0d..%0d (includes stalls) jobs=%0d cycles=%0d",min_latency,max_latency,min_ii,max_ii,requests,cycles);
    $display("PASS arb: golden=%0d/%0d edges=%0d/%0d extra=%0d/%0d all=%0d/%0d assertions=36",GOLDEN,GOLDEN,EDGES,EDGES,N-GOLDEN-EDGES,N-GOLDEN-EDGES,N,N);
    $finish;
  end
endmodule
