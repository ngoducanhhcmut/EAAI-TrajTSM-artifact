// Project TSM-X; Author TSMX project; Version 0.1; 2026-10-29.
// Protocol requirements: project AXI4-Lite contract spec6.1 ASSUMPTION-011.
`timescale 1ns/1ps
// Claude 10/11/2026: tb_tsmx_chain = tb_tsmx_stream + timing-chain measurement (RTL unchanged).
//  +TICK      : i_time_us advances 1 us every 100 core cycles (100 MHz) and keeps running between jobs
//  +EXEC_ACK  : executor model ACKs (exact pending seq) ACKDLY us after max(command delivered, apply)
//  +ACK_HOLD  : with EXEC_ACK, the executor holds ACK (exact seq) every cycle from ACKDLY us after delivery until the
//               pending plan leaves (commit at apply, expiry or timeout); spec 6.2: apply beyond 40 ms needs this
//  +TXSTALL=N : executor stall: i_tx_ready held low N cycles after each response
//  +CONTEND=K : K extra copies of the job-0 frame sent back-to-back while job 0 is deciding (then stop)
//  +SOFT      : response/command/event/CSR mismatches are counted, not fatal (protocol checks stay fatal)
module tb_tsmx_chain;
  parameter integer LANES=2;
  `include "vector_count.svh"
  logic  i_clk_core;
  logic  i_rst_n_core;
  logic  i_req_valid;
  logic [44672:0] i_req_data;
  logic  i_rsp_ready;
  logic  o_req_ready;
  logic  o_rsp_valid;
  logic [37:0] o_rsp_data;
  logic [31:0] i_time_us;
  logic  i_ack_valid;
  logic [31:0] i_ack_seq;
  logic  o_brake;
  logic  o_heartbeat;
  logic [15:0] i_axi_awaddr;
  logic [2:0] i_axi_awprot;
  logic  i_axi_awvalid;
  logic [31:0] i_axi_wdata;
  logic [3:0] i_axi_wstrb;
  logic  i_axi_wvalid;
  logic  i_axi_bready;
  logic [15:0] i_axi_araddr;
  logic [2:0] i_axi_arprot;
  logic  i_axi_arvalid;
  logic  i_axi_rready;
  logic  o_axi_awready;
  logic  o_axi_wready;
  logic  o_axi_bvalid;
  logic [1:0] o_axi_bresp;
  logic  o_axi_arready;
  logic  o_axi_rvalid;
  logic [1:0] o_axi_rresp;
  logic [31:0] o_axi_rdata;
  logic  o_int_irq;
  logic [9:0] i_log_idx;
  logic  i_log_valid;
  logic  i_log_ready;
  logic  o_log_ready;
  logic [1055:0] o_log_data;
  logic  o_log_valid;
  logic  i_rx_valid;
  logic [31:0] i_rx_data;
  logic [3:0] i_rx_keep;
  logic  i_rx_last;
  logic  o_rx_ready;
  logic  o_tx_valid;
  logic [31:0] o_tx_data;
  logic [3:0] o_tx_keep;
  logic  o_tx_last;
  logic  i_tx_ready;
  logic [VW-1:0] vectors[0:JOBS-1];
  logic [37:0] expected_rsp;
  logic [1896:0] expected_cmd;
  logic [1055:0] expected_event;
  logic [331:0] expected_ing;
  logic [7:0] expected_sup;
  logic [31:0] expected_lost;
  logic [44672:0] req;
  logic reset_job;
  logic [37:0] seen_rsp;
  logic [1896:0] seen_cmd;
  logic [1903:0] txbuf;
  logic [31:0] rd;
  logic [31:0] expected_status;
  integer cyc=0,job=0,start_cyc=0,latency=0,max_latency=0;
  time start_time;
  integer txword=0,frames=0,log_count=0,mutant=-1,limit=JOBS;
  integer worst_rows=77;
  integer hit[0:39];
  integer sink;
  integer vector_fd,scan_count,inactive=0;
  logic [31:0] held_tx;
  logic [3:0] held_keep;
  logic held_last,tx_stalled=0;
  logic [1:0] held_bresp,held_rresp;
  logic [31:0] held_rdata;
  logic b_stalled=0,r_stalled=0;
  logic [37:0] held_rsp;
  logic rsp_stalled=0;
  logic [31:0] obs_tx_data;
  logic [37:0] obs_rsp_data;
  logic obs_hb,obs_brake;
  logic [2:0] obs_mode;
  integer obs_cycles;
  string names[0:39];
  string vector_file="vectors.mem";
  integer max_rows=0,stream_hits=0;
  logic [15:0] fallback_mask=0,tail_mask=0;
  m_tsmx_top #(.PARA_DIRECT(0),.PARA_G(LANES),.PARA_P(LANES)) dut (
    .i_clk_core(i_clk_core),
    .i_rst_n_core(i_rst_n_core),
    .i_req_valid(i_req_valid),
    .i_req_data(i_req_data),
    .i_rsp_ready(i_rsp_ready),
    .o_req_ready(o_req_ready),
    .o_rsp_valid(o_rsp_valid),
    .o_rsp_data(o_rsp_data),
    .i_time_us(i_time_us),
    .i_ack_valid(i_ack_valid),
    .i_ack_seq(i_ack_seq),
    .o_brake(o_brake),
    .o_heartbeat(o_heartbeat),
    .i_axi_awaddr(i_axi_awaddr),
    .i_axi_awprot(i_axi_awprot),
    .i_axi_awvalid(i_axi_awvalid),
    .i_axi_wdata(i_axi_wdata),
    .i_axi_wstrb(i_axi_wstrb),
    .i_axi_wvalid(i_axi_wvalid),
    .i_axi_bready(i_axi_bready),
    .i_axi_araddr(i_axi_araddr),
    .i_axi_arprot(i_axi_arprot),
    .i_axi_arvalid(i_axi_arvalid),
    .i_axi_rready(i_axi_rready),
    .o_axi_awready(o_axi_awready),
    .o_axi_wready(o_axi_wready),
    .o_axi_bvalid(o_axi_bvalid),
    .o_axi_bresp(o_axi_bresp),
    .o_axi_arready(o_axi_arready),
    .o_axi_rvalid(o_axi_rvalid),
    .o_axi_rresp(o_axi_rresp),
    .o_axi_rdata(o_axi_rdata),
    .o_int_irq(o_int_irq),
    .i_log_idx(i_log_idx),
    .i_log_valid(i_log_valid),
    .i_log_ready(i_log_ready),
    .o_log_ready(o_log_ready),
    .o_log_data(o_log_data),
    .o_log_valid(o_log_valid),
    .i_rx_valid(i_rx_valid),
    .i_rx_data(i_rx_data),
    .i_rx_keep(i_rx_keep),
    .i_rx_last(i_rx_last),
    .o_rx_ready(o_rx_ready),
    .o_tx_valid(o_tx_valid),
    .o_tx_data(o_tx_data),
    .o_tx_keep(o_tx_keep),
    .o_tx_last(o_tx_last),
    .i_tx_ready(i_tx_ready)
  );
  always #5 i_clk_core=~i_clk_core;
  always @(negedge i_clk_core) i_tx_ready=((cyc%7)!=0) && (stall_left==0);
  always_comb begin
    obs_tx_data=o_tx_data;obs_rsp_data=o_rsp_data;
    obs_hb=o_heartbeat;obs_brake=o_brake;obs_mode=o_rsp_data[28:26];
    obs_cycles=latency;
    case(mutant)
      12: if(tx_stalled) obs_tx_data=o_tx_data^32'd1;
      13: if(rsp_stalled) obs_rsp_data=o_rsp_data^38'd1;
      14: if(!o_rsp_valid) obs_rsp_data=38'd1;
      15: if(!o_tx_valid) obs_tx_data=32'd1;
      16: obs_hb=1'b1;
      17: obs_brake=1'b0;
      18: obs_mode=3'd7;
      19: obs_cycles=1875001;
      default:begin end
    endcase
  end
  // Interface observation mutants alter a sampled output wire, never an oracle or RTL source.
  task automatic ck(input integer id,input logic active,input logic good);
    if(active) begin
      hit[id]=hit[id]+1;
      if(good!==1'b1 && softm && id<=11) begin softfail=softfail+1; $display("SOFT_MISMATCH %0d %s job=%0d",id,names[id],job); end
      else if(good!==1'b1) begin
        $display("ASSERT_FAIL %0d %s job=%0d cycle=%0d",id,names[id],job,cyc);
        $fatal(1,"assertion failure");
      end
    end
  endtask
  integer xerr_checks=0; // Claude 30/10 FIX-002 settled-bound checks
  // ---- chain measurement state ----
  logic ack_hold=0,ack_holding=0; logic tick_mode=0,exec_ack=0,softm=0; integer ack_dly=1000,txstall=0,contend=0,softfail=0;
  integer tickcnt=0; logic tick_run=0;
  integer rx_first=0,rx_last=0,rsp_cyc=0,tx_first=-1,tx_last=-1,stall_left=0;
  logic prev_rsp=0,prev_brake=0; integer cross40=-1;
  logic ack_armed=0; integer ack_cyc=-1; logic [31:0] ack_at;
  function automatic integer f_sdiff(input logic [31:0] a,input logic [31:0] b); f_sdiff=$signed(a-b); endfunction
  always @(negedge i_clk_core) if(tick_mode && tick_run) begin
    if(tickcnt==99) begin tickcnt=0; i_time_us=i_time_us+32'd1; end else tickcnt=tickcnt+1;
  end
  always @(posedge i_clk_core) begin
    if(o_rsp_valid && !prev_rsp) begin rsp_cyc=cyc; if(txstall>0) stall_left=txstall; end
    prev_rsp=o_rsp_valid;
    if(o_tx_valid && tx_first<0) tx_first=cyc;
    if(o_tx_valid && i_tx_ready && o_tx_last) begin
      tx_last=cyc;
      $display("CHAIN_TX job=%0d delivered_cyc=%0d rsp_to_delivered=%0d time_us=%0d pending=%0b",
        job,cyc,cyc-rsp_cyc,i_time_us,dut.u_tsmx_engine.reg_pending_valid);
      if(exec_ack && dut.u_tsmx_engine.reg_pending_valid) begin
        ack_armed=1;
        ack_at=dut.u_tsmx_engine.reg_pending_plan[239:208];
        if(f_sdiff(i_time_us,ack_at)>0 || ack_hold) ack_at=i_time_us; // hold model: from delivery
        ack_at=ack_at+ack_dly;
      end
    end
    if(stall_left>0) stall_left=stall_left-1;
    if(dut.u_tsmx_engine.reg_pending_valid && !dut.u_tsmx_engine.w_ackage[31]
       && dut.u_tsmx_engine.w_ackage>=32'd40000 && cross40<0) cross40=cyc;
    if(dut.u_tsmx_engine.w_timer && dut.u_tsmx_engine.w_timer_code!=8'd32)
      $display("TIMER job=%0d cyc=%0d time_us=%0d code=%0d issued=%0d age_us=%0d apply=%0d cyc_after_40ms_cross=%0d cyc_after_ack=%0d brake=%0b tx_stalled=%0b",
        job,cyc,i_time_us,dut.u_tsmx_engine.w_timer_code,dut.u_tsmx_engine.reg_issued,
        dut.u_tsmx_engine.w_ackage,dut.u_tsmx_engine.reg_pending_plan[239:208],
        cross40<0 ? -1:cyc-cross40, ack_cyc<0 ? -1:cyc-ack_cyc, o_brake, o_tx_valid && !i_tx_ready);
    if(o_brake && !prev_brake)
      $display("BRAKE_RISE job=%0d cyc=%0d time_us=%0d cyc_after_40ms_cross=%0d",job,cyc,i_time_us,cross40<0 ? -1:cyc-cross40);
    prev_brake=o_brake;
    if(!dut.u_tsmx_engine.reg_pending_valid) cross40=-1;
  end
  // Executor ACK pulse: one cycle, exact pending seq, driven at negedge like the reference bench.
  always @(negedge i_clk_core) begin
    if(exec_ack) begin
      i_ack_valid=0;
      if(ack_holding && dut.u_tsmx_engine.reg_pending_valid) begin
        i_ack_valid=1; i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528];
      end
      if(ack_armed && dut.u_tsmx_engine.reg_pending_valid && f_sdiff(i_time_us,ack_at)>=0) begin
        i_ack_valid=1; i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528]; ack_armed=0; ack_cyc=cyc+1;
        ack_holding=ack_hold;
        $display("EXEC_ACK job=%0d cyc=%0d time_us=%0d seq=%0d hold=%0b",job,cyc,i_time_us,i_ack_seq,ack_hold);
      end
      if(!dut.u_tsmx_engine.reg_pending_valid) begin ack_armed=0; ack_holding=0; end
    end
  end
  always @(posedge i_clk_core) begin
    cyc=cyc+1;
    if(i_req_valid && o_req_ready)begin
      max_rows=0;stream_hits=0;fallback_mask=0;tail_mask=0;
    end
    for(integer lane=0;lane<LANES;lane=lane+1)begin
      if(dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_req_valid[lane]
         && dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_req_ready[lane])begin
        if(dut.u_tsmx_engine.reg_fsm_ctrl_current_state[40])
          fallback_mask[dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_req_data[lane*176+40 +:8]]=1;
        if(dut.u_tsmx_engine.reg_fsm_ctrl_current_state[52])
          tail_mask[dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_req_data[lane*176+40 +:8]]=1;
      end
      if(dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_resp_valid[lane]
         && dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_resp_ready[lane]
         && dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_resp_data[lane*50 +:8]>max_rows)
        max_rows=dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_resp_data[lane*50 +:8];
      if(dut.u_tsmx_engine.u_tsmx_sweep_0.w_geom_row_valid[lane]
         && dut.u_tsmx_engine.u_tsmx_sweep_0.w_geom_row_ready[lane]
         && !dut.u_tsmx_engine.u_tsmx_sweep_0.w_mrm_resp_valid[lane])
        stream_hits=stream_hits+1;
    end
    if($test$plusargs("TRACE") && (cyc%100==0 || cyc<40 || (cyc>3880 && cyc<4100)))
      $display("TRACE cycle=%0d state=%0d sweep=%0d hash=%0d",cyc,
        dut.u_tsmx_engine.reg_fsm_ctrl_current_state,
        dut.u_tsmx_engine.u_tsmx_sweep_0.reg_fsm_ctrl_current_state,
        dut.u_tsmx_engine.u_tsmx_hash.reg_fsm_ctrl_current_state);
    if($test$plusargs("TRACE") && cyc<30)
      $display("BUS addr=%h arv=%b arr=%b rv=%b rd=%h rr=%b",i_axi_araddr,
        i_axi_arvalid,o_axi_arready,o_axi_rvalid,o_axi_rdata,i_axi_rready);
    if(i_rst_n_core) begin
      ck(12,tx_stalled,{obs_tx_data,o_tx_keep,o_tx_last,o_tx_valid}===
        {held_tx,held_keep,held_last,1'b1});
      ck(13,rsp_stalled,{obs_rsp_data,o_rsp_valid}==={held_rsp,1'b1});
      ck(14,!o_rsp_valid,obs_rsp_data===38'd0);
      ck(15,!o_tx_valid,{obs_tx_data,o_tx_keep,o_tx_last}===37'd0);
      ck(16,o_rsp_valid && !o_rsp_data[0],obs_hb===1'b0);
      ck(17,o_rsp_valid && !o_rsp_data[37],obs_brake===1'b1);
      ck(18,1'b1,$onehot(dut.u_tsmx_engine.reg_fsm_ctrl_current_state)
        && (!o_rsp_valid || obs_mode<=3'd5));
      ck(19,o_rsp_valid,obs_cycles<=1875000);
      ck(20,b_stalled,{o_axi_bvalid,o_axi_bresp}==={1'b1,held_bresp});
      ck(21,r_stalled,{o_axi_rvalid,o_axi_rresp,o_axi_rdata}==={1'b1,held_rresp,held_rdata});
      ck(22,o_axi_bvalid,o_axi_bresp==2'd0 || o_axi_bresp==2'd2);
      ck(23,o_axi_rvalid,o_axi_rresp==2'd0 || o_axi_rresp==2'd2);
      ck(24,i_axi_awvalid && o_axi_awready, !$isunknown(i_axi_awaddr));
      ck(25,i_axi_wvalid && o_axi_wready, (^ {i_axi_wstrb,i_axi_wdata})!==1'bx);
      ck(26,i_axi_arvalid && o_axi_arready, !$isunknown(i_axi_araddr));
      ck(27,o_axi_bvalid, !$isunknown(o_axi_bresp));
      ck(28,o_axi_rvalid, (^ {o_axi_rresp,o_axi_rdata})!==1'bx);
      ck(29,o_axi_awready, !$isunknown(o_axi_awready));
      ck(30,o_axi_wready, !$isunknown(o_axi_wready));
      ck(31,o_axi_arready, !$isunknown(o_axi_arready));
      ck(32,o_axi_bvalid && !i_axi_bready,!o_axi_awready && !o_axi_wready);
      ck(33,o_axi_rvalid && !i_axi_rready,!o_axi_arready);
      ck(34,o_axi_rvalid && o_axi_rresp==0 && i_axi_araddr==16'h28,o_axi_rdata[31:8]==24'd0);
      ck(35,o_axi_rvalid && o_axi_rresp==2,o_axi_rdata===32'd0);
      ck(36,o_axi_rvalid && i_axi_araddr==16'h4,o_axi_rdata[31:18]==14'd0);
      ck(37,i_axi_awvalid && o_axi_awready,i_axi_awprot===3'd0);
      ck(38,i_axi_arvalid && o_axi_arready,i_axi_arprot===3'd0);
      ck(39,o_axi_rvalid && i_axi_araddr==16'h30,o_axi_rdata===32'd16);
      tx_stalled=o_tx_valid && !i_tx_ready;
      held_tx=o_tx_data;held_keep=o_tx_keep;held_last=o_tx_last;
      rsp_stalled=o_rsp_valid && !i_rsp_ready;held_rsp=o_rsp_data;
      b_stalled=o_axi_bvalid && !i_axi_bready;held_bresp=o_axi_bresp;
      r_stalled=o_axi_rvalid && !i_axi_rready;held_rresp=o_axi_rresp;held_rdata=o_axi_rdata;
      if(o_tx_valid && i_tx_ready) begin
        if(txword==0) begin if(o_tx_data!==32'd2) $fatal(1,"tx type"); txbuf='0; end
        else if(txword==1) begin if(o_tx_data!==32'd238) $fatal(1,"tx length"); end
        else begin
          for(integer b=0;b<4;b=b+1)
            if(4*(txword-2)+b<238) txbuf[1903-8*(4*(txword-2)+b) -:8]=o_tx_data[8*b +:8];
        end
        if(o_tx_last) begin
          if(txword!=61 || o_tx_keep!==4'b0011 || txbuf[6:0]!==7'd0) $fatal(1,"tx framing");
          seen_cmd=txbuf[1903:7];
          case(mutant)
            8:seen_cmd[1800]=~seen_cmd[1800];
            9:seen_cmd[100]=~seen_cmd[100];
            10:seen_cmd[1890]=~seen_cmd[1890];
            11:seen_cmd[0]=~seen_cmd[0];
            default:begin end
          endcase
          ck(9,1,seen_cmd[1778:2]===expected_cmd[1778:2]);
          ck(10,1,seen_cmd[1896:1883]===expected_cmd[1896:1883]);
          ck(11,1,seen_cmd[1:0]===expected_cmd[1:0]);
          ck(8,1,seen_cmd===expected_cmd);
          if(seen_cmd[1896:1894]<=3'd1 && !seen_cmd[1218]) $fatal(1,"command without certificate");
          frames=frames+1;txword=0;$display("BOARDCMD job=%0d frames=%0d",job,frames);
        end else txword=txword+1;
      end
    end else begin tx_stalled=0;rsp_stalled=0;b_stalled=0;r_stalled=0;txword=0;end
  end
  task automatic soft_or_fatal(input string m,input logic [1055:0] a=0,input logic [1055:0] b=0,input logic [1055:0] c=0);
    if(softm) begin softfail=softfail+1; $display("SOFT_MISMATCH %s job=%0d",m,job); end else $fatal(1,"%s job=%0d",m,job);
  endtask
  task automatic bus_read(input logic [15:0] addr,output logic [31:0] data,
                          input logic [1:0] resp=2'd0);
    @(negedge i_clk_core);i_axi_araddr=addr;i_axi_arvalid=1;i_axi_rready=0;
    do @(posedge i_clk_core); while(!o_axi_arready);
    @(negedge i_clk_core);i_axi_arvalid=0;
    while(!o_axi_rvalid) @(negedge i_clk_core);
    data=o_axi_rdata;
    if(o_axi_rresp!==resp)$fatal(1,"AXI read response addr=%h actual=%h expected=%h",addr,o_axi_rresp,resp);
    if($test$plusargs("TRACE"))$display("READ_SAMPLE addr=%h rd=%h rv=%b",addr,data,o_axi_rvalid);
    repeat(2) @(negedge i_clk_core);
    i_axi_rready=1;@(negedge i_clk_core);i_axi_rready=0;
  endtask
  task automatic bus_write(input logic [15:0] addr,input logic [31:0] data,
                           input logic [1:0] resp=2'd0,input logic [3:0] strb=4'hf);
    @(negedge i_clk_core);i_axi_awaddr=addr;i_axi_awvalid=1;i_axi_bready=0;
    do @(posedge i_clk_core); while(!o_axi_awready);
    @(negedge i_clk_core);i_axi_awvalid=0;
    repeat(2) @(negedge i_clk_core);
    i_axi_wdata=data;i_axi_wstrb=strb;i_axi_wvalid=1;
    do @(posedge i_clk_core); while(!o_axi_wready);
    @(negedge i_clk_core);i_axi_wvalid=0;
    while(!o_axi_bvalid) @(negedge i_clk_core);
    if(o_axi_bresp!==resp)$fatal(1,"AXI write response addr=%h actual=%h expected=%h",addr,o_axi_bresp,resp);
    repeat(2) @(negedge i_clk_core);
    i_axi_bready=1;@(negedge i_clk_core);i_axi_bready=0;
  endtask
  integer idle_wait=0;
  // Claude 04/11: board-equivalent stream sender (AXI-Stream FIFO store-and-forward, no gaps).
  task automatic send_frame(input logic [44672:0] f);
    integer k;
    logic [31:0] w;
    for(k=0;k<1399;k=k+1) begin
      if(k==0) begin w=32'd1; i_rx_keep=4'hf; i_rx_last=0; end
      else if(k==1) begin w=32'd5585; i_rx_keep=4'hf; i_rx_last=0; end
      else if(k<1398) begin
        w=f[44672-32*(k-2) -: 32]; w={w[7:0],w[15:8],w[23:16],w[31:24]};
        i_rx_keep=4'hf; i_rx_last=0;
      end else begin w={24'd0,f[0],7'd0}; i_rx_keep=4'b0001; i_rx_last=1; end
      i_rx_data=w; i_rx_valid=1;
      @(posedge i_clk_core); while(!o_rx_ready) @(posedge i_clk_core);
      #1;
    end
    i_rx_valid=0; i_rx_last=0; i_rx_keep=0; i_rx_data=0;
    @(negedge i_clk_core);
  endtask
  // Claude 04/11: firmware bring-up sequence (CTRL.bist_start -> CONFIG_VALID -> CTRL.en).
  task automatic bringup();
    logic [31:0] v;
    integer n;
    bus_write(16'h00,32'h4);
    n=0; v=0;
    while(v!==32'd1) begin
      bus_read(16'h4c,v); n=n+1;
      if(n>200000) $fatal(1,"bring-up: CONFIG_VALID never set");
    end
    bus_write(16'h00,32'h1);
    bus_read(16'h00,v); if(v!==32'd1) $fatal(1,"bring-up: CTRL.en not set (%h)",v);
    $display("BOARDUP polls=%0d cyc=%0d",n,cyc);
  endtask
  initial begin
    i_clk_core='0;
    i_rst_n_core='0;
    i_req_valid='0;
    i_req_data='0;
    i_rsp_ready='0;
    i_time_us='0;
    i_ack_valid='0;
    i_ack_seq='0;
    i_axi_awaddr='0;
    i_axi_awprot='0;
    i_axi_awvalid='0;
    i_axi_wdata='0;
    i_axi_wstrb='0;
    i_axi_wvalid='0;
    i_axi_bready='0;
    i_axi_araddr='0;
    i_axi_arprot='0;
    i_axi_arvalid='0;
    i_axi_rready='0;
    i_log_idx='0;
    i_log_valid='0;
    i_log_ready='0;
    i_rx_valid='0;
    i_rx_data='0;
    i_rx_keep='0;
    i_rx_last='0;
    i_tx_ready='0;
    names[0]="TOP_FULL:spec5.3/6.1/10.1/15"; hit[0]=0;
    names[1]="TOP_ACCEPT:spec5.3/6.1/10.1/15"; hit[1]=0;
    names[2]="TOP_REASON:spec5.3/6.1/10.1/15"; hit[2]=0;
    names[3]="TOP_MODE:spec5.3/6.1/10.1/15"; hit[3]=0;
    names[4]="TOP_CANDIDATE:spec5.3/6.1/10.1/15"; hit[4]=0;
    names[5]="TOP_LABEL:spec5.3/6.1/10.1/15"; hit[5]=0;
    names[6]="TOP_BRAKE_FLAG:spec5.3/6.1/10.1/15"; hit[6]=0;
    names[7]="TOP_COMMIT_HB:spec5.3/6.1/10.1/15"; hit[7]=0;
    names[8]="CMD_FULL:spec5.3/6.1/10.1/15"; hit[8]=0;
    names[9]="CMD_RECORDS:spec5.3/6.1/10.1/15"; hit[9]=0;
    names[10]="CMD_AUTHORITY:spec5.3/6.1/10.1/15"; hit[10]=0;
    names[11]="CMD_OVERRIDE:spec5.3/6.1/10.1/15"; hit[11]=0;
    names[12]="TX_STABLE:spec5.3/6.1/10.1/15"; hit[12]=0;
    names[13]="RSP_STABLE:spec5.3/6.1/10.1/15"; hit[13]=0;
    names[14]="NO_STALE_RSP:spec5.3/6.1/10.1/15"; hit[14]=0;
    names[15]="NO_STALE_TX:spec5.3/6.1/10.1/15"; hit[15]=0;
    names[16]="HB_FAULT_LOW:spec5.3/6.1/10.1/15"; hit[16]=0;
    names[17]="FAULT_BRAKE:spec5.3/6.1/10.1/15"; hit[17]=0;
    names[18]="ONEHOT_FSM_MODE:spec5.3/6.1/10.1/15"; hit[18]=0;
    names[19]="DEADLINE_BOUND:spec5.3/6.1/10.1/15"; hit[19]=0;
    names[20]="AXI_B_HOLD:spec5.3/6.1/10.1/15"; hit[20]=0;
    names[21]="AXI_R_HOLD:spec5.3/6.1/10.1/15"; hit[21]=0;
    names[22]="AXI_B_CODE:spec5.3/6.1/10.1/15"; hit[22]=0;
    names[23]="AXI_R_CODE:spec5.3/6.1/10.1/15"; hit[23]=0;
    names[24]="AXI_AW_KNOWN:spec5.3/6.1/10.1/15"; hit[24]=0;
    names[25]="AXI_W_KNOWN:spec5.3/6.1/10.1/15"; hit[25]=0;
    names[26]="AXI_AR_KNOWN:spec5.3/6.1/10.1/15"; hit[26]=0;
    names[27]="AXI_B_KNOWN:spec5.3/6.1/10.1/15"; hit[27]=0;
    names[28]="AXI_R_KNOWN:spec5.3/6.1/10.1/15"; hit[28]=0;
    names[29]="AXI_AWREADY_KNOWN:spec5.3/6.1/10.1/15"; hit[29]=0;
    names[30]="AXI_WREADY_KNOWN:spec5.3/6.1/10.1/15"; hit[30]=0;
    names[31]="AXI_ARREADY_KNOWN:spec5.3/6.1/10.1/15"; hit[31]=0;
    names[32]="AXI_B_BACKPRESSURE:spec5.3/6.1/10.1/15"; hit[32]=0;
    names[33]="AXI_R_BACKPRESSURE:spec5.3/6.1/10.1/15"; hit[33]=0;
    names[34]="AXI_REASON_RESERVED:spec5.3/6.1/10.1/15"; hit[34]=0;
    names[35]="AXI_ERROR_ZERO:spec5.3/6.1/10.1/15"; hit[35]=0;
    names[36]="AXI_STATUS_RESERVED:spec5.3/6.1/10.1/15"; hit[36]=0;
    names[37]="AXI_AWPROT:spec5.3/6.1/10.1/15"; hit[37]=0;
    names[38]="AXI_ARPROT:spec5.3/6.1/10.1/15"; hit[38]=0;
    names[39]="AXI_PROFILE_COUNT:spec5.3/6.1/10.1/15"; hit[39]=0;
    sink=$value$plusargs("MUTANT=%d",mutant);
    tick_mode=$test$plusargs("TICK"); ack_hold=$test$plusargs("ACK_HOLD"); exec_ack=$test$plusargs("EXEC_ACK"); softm=$test$plusargs("SOFT");
    sink=$value$plusargs("ACKDLY=%d",ack_dly); sink=$value$plusargs("TXSTALL=%d",txstall); sink=$value$plusargs("CONTEND=%d",contend);
    $display("CHAIN_CFG tick=%0b exec_ack=%0b ackdly_us=%0d txstall_cyc=%0d contend=%0d soft=%0b",tick_mode,exec_ack,ack_dly,txstall,contend,softm);
    sink=$value$plusargs("LIMIT=%d",limit);
    // A8 (02/11): an accelerating worst case needs a longer MRM tail (93 rows at +2 m/s^2 vs 77)
    sink=$value$plusargs("WORST_ROWS=%d",worst_rows);
    sink=$value$plusargs("FILE=%s",vector_file);
    if(limit<1 || limit>JOBS)$fatal(1,"invalid limit");
    vector_fd=$fopen(vector_file,"r");if(!vector_fd)$fatal(1,"vector file missing");
    for(integer idx=0;idx<limit;idx=idx+1)begin
      scan_count=$fscanf(vector_fd,"%h",vectors[idx]);
      if(scan_count!=1)$fatal(1,"vector parse row %0d",idx);
    end
    $fclose(vector_fd);
    i_tx_ready=1;
    repeat(4) @(negedge i_clk_core); i_rst_n_core=1;
    repeat(5) @(negedge i_clk_core);
    bus_write(16'h08,32'hff);
    bus_read(16'h30,rd);if(rd!==32'd16) $fatal(1,"CSR profile actual=%h",rd);
    bus_read(16'h08,rd);if(rd!==32'hff)$fatal(1,"CSR IRQ mask");
    bus_write(16'h08,32'd0,2'd0,4'd0);
    bus_read(16'h08,rd);if(rd!==32'hff)$fatal(1,"CSR zero strobes");
    bus_read(16'h34,rd);if(rd!==32'd128)$fatal(1,"CSR profile limit");
    bus_read(16'h38,rd);if(rd!==32'hffff)$fatal(1,"CSR profile mask");
    bus_read(16'h3c,rd);if(rd!==32'd150000)$fatal(1,"CSR freshness");
    bus_read(16'h44,rd);if(rd!==32'd40000)$fatal(1,"CSR ACK limit");
    bus_read(16'hffff,rd,2'd2);
    bus_read(16'h01,rd,2'd2);
    bus_write(16'h04,32'd0,2'd2);
    bus_write(16'h08,32'd0,2'd0,4'h1);
    bus_read(16'h08,rd);if(rd!==32'd0)$fatal(1,"CSR byte mask");
    bus_write(16'h08,32'hff);
    $display("PASS top CSR/AXI smoke");bringup();
    for(job=0;job<limit;job=job+1) begin
      {reset_job,req,expected_rsp,expected_cmd,expected_ing,expected_sup,expected_lost,expected_event}=vectors[job];
      if(reset_job) begin
        @(negedge i_clk_core);i_rst_n_core=0;
        repeat(3) @(negedge i_clk_core);i_rst_n_core=1;
        repeat(5) @(negedge i_clk_core);log_count=0;frames=0;bringup();
      end
      @(negedge i_clk_core);
      // r3: the board (xsdb, ms per access) only pulses ACK with the engine idle; wait for it here.
      idle_wait=0;
      while(!dut.u_tsmx_engine.o_req_ready) begin @(negedge i_clk_core); idle_wait=idle_wait+1; end
      if(idle_wait!=0) $display("IDLEWAIT job=%0d cycles=%0d",job,idle_wait);
      if(tick_mode && tick_run && f_sdiff(req[44672:44641],i_time_us)>=0) begin
        while(i_time_us!==req[44672:44641]) @(negedge i_clk_core);   // real 1 us time base up to the job time
      end else begin
        if(tick_mode && tick_run) $display("TIMEJUMP job=%0d from=%0d to=%0d",job,i_time_us,req[44672:44641]);
        i_time_us=req[44672:44641]; tickcnt=0;
      end
      tick_run=tick_mode;
      if(!exec_ack) begin i_ack_valid=req[33856];i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528]; end
      $display("BOARDVEC job=%0d reset=%0d time=%h ack=%0d seq=%h",job,reset_job,i_time_us,i_ack_valid,i_ack_seq);
      if(!exec_ack) begin @(negedge i_clk_core);i_ack_valid=0; end else @(negedge i_clk_core);
      tx_first=-1; rx_first=cyc;
      if(contend>0 && job==0) begin
        fork
          send_frame(req);
          begin : contender
            integer q,t0; @(negedge i_clk_core); wait(!i_rx_valid);
            for(q=0;q<contend;q=q+1) begin t0=cyc; send_frame(req);
              $display("CONTEND frame=%0d accepted_last_cyc=%0d send_cycles=%0d engine_busy=%0b",q+1,cyc,cyc-t0,!dut.u_tsmx_engine.o_req_ready); end
          end
        join_any
      end else send_frame(req);
      rx_last=cyc;
      start_cyc=cyc;start_time=$time-10;
      while(!o_rsp_valid) begin
        @(negedge i_clk_core);
        if(cyc-start_cyc>1875010) $fatal(1,"decision hang job=%0d state=%0d",job,dut.u_tsmx_engine.reg_fsm_ctrl_current_state);
      end
      latency=($time-5-start_time)/10+1;
      if(latency>max_latency)max_latency=latency;
      seen_rsp=o_rsp_data;
      case(mutant)
        1:seen_rsp[37]=~seen_rsp[37];
        2:seen_rsp[29]=~seen_rsp[29];
        3:seen_rsp[26]=~seen_rsp[26];
        4:seen_rsp[18]=~seen_rsp[18];
        5:seen_rsp[10]=~seen_rsp[10];
        6:seen_rsp[9]=~seen_rsp[9];
        7:seen_rsp[0]=~seen_rsp[0];
        default:begin end
      endcase
      if(seen_rsp!==expected_rsp) $display("RSP job=%0d actual=%h expected=%h reason=%0d",job,seen_rsp,expected_rsp,seen_rsp[36:29]);
      ck(1,1,seen_rsp[37]===expected_rsp[37]);
      ck(2,1,seen_rsp[36:29]===expected_rsp[36:29]);ck(3,1,seen_rsp[28:26]===expected_rsp[28:26]);
      ck(4,1,seen_rsp[25:18]===expected_rsp[25:18]);ck(5,1,seen_rsp[17:10]===expected_rsp[17:10]);
      ck(6,1,seen_rsp[9]===expected_rsp[9]);ck(7,1,seen_rsp[8:0]===expected_rsp[8:0]);
      if(mutant==0)seen_rsp=seen_rsp^38'd1;
      ck(0,1,seen_rsp===expected_rsp);
      repeat(3) @(negedge i_clk_core);i_rsp_ready=1;
      @(negedge i_clk_core);i_rsp_ready=0;
      // Read actual recorder output through the top, indexed oldest first.
      log_count=log_count+1;i_log_idx=(log_count>64) ? 63:log_count-1;
      i_log_valid=1;i_log_ready=0;
      while(!o_log_ready) @(negedge i_clk_core);
      @(negedge i_clk_core);i_log_valid=0;
      while(!o_log_valid) @(negedge i_clk_core);
      if(o_log_data!==expected_event)soft_or_fatal("event mismatch job=%0d actual=%h expected=%h",job,o_log_data,expected_event);
      i_log_ready=1;@(negedge i_clk_core);i_log_ready=0;
      while(txword!=0 || o_tx_valid) @(negedge i_clk_core);
      bus_read(16'h28,rd);
      if(rd!=={24'd0,expected_rsp[36:29]})soft_or_fatal("CSR reason");
      bus_read(16'h04,rd);
      expected_status=32'd0;
      expected_status[1]=expected_rsp[0];
      expected_status[2]=!expected_rsp[0] || expected_rsp[28:26]==3'd3 || expected_rsp[9];
      expected_status[5:3]=expected_rsp[28:26];
      // CSR_UPDATE pending/backup map to STATUS[6]/[7], opposite packed pair order.
      expected_status[6]=expected_sup[1];expected_status[7]=expected_sup[0];
      expected_status[8]=expected_rsp[0];expected_status[17:16]=expected_rsp[11:10];
      if(rd!==expected_status)soft_or_fatal("CSR status job=%0d actual=%h expected=%h",job,rd,expected_status);
      if(dut.u_tsmx_engine.reg_ing!==expected_ing
        || {dut.u_tsmx_engine.reg_mode,dut.u_tsmx_engine.reg_good,dut.u_tsmx_engine.reg_fault,
          dut.u_tsmx_engine.reg_pending_valid,dut.u_tsmx_engine.reg_backup_valid}!==expected_sup)soft_or_fatal("retained state mismatch");
      bus_read(16'h24,rd);if(rd!==expected_lost)soft_or_fatal("CSR lost");
      bus_read(16'h2c,rd);$display("BOARDCYC job=%0d csr_cycles=%0d tb_latency=%0d",job,rd,latency);
      $display("JOB %0d PASS cycles=%0d xerr_checks=%0d",job,latency,xerr_checks);
      $display("CHAIN job=%0d rx_xfer=%0d decide=%0d host_to_rsp=%0d rsp_to_tx_first=%0d rsp_to_tx_delivered=%0d rsp=%h exp_mode=%0d exp_reason=%0d softfail=%0d",
        job,rx_last-rx_first,latency,rsp_cyc-rx_first,tx_first<0 ? -1:tx_first-rsp_cyc,tx_last<rsp_cyc ? -1:tx_last-rsp_cyc,
        seen_rsp,expected_rsp[28:26],expected_rsp[36:29],softfail);
      if(contend>0) begin : drain
        integer extra,waitc; extra=0; waitc=0;
        // keep consuming the queued copies' responses so staging drains; nothing may be lost
        while(extra<contend && waitc<8000000) begin
          @(negedge i_clk_core); waitc=waitc+1;
          if(o_rsp_valid && !i_rsp_ready) begin
            $display("CONTEND_RSP n=%0d cyc=%0d rsp=%h rx_ready=%0b",extra+1,cyc,o_rsp_data,o_rx_ready);
            i_rsp_ready=1; extra=extra+1;
          end else i_rsp_ready=0;
        end
        i_rsp_ready=0;
        $display("CONTEND_DONE extra_rsp=%0d of %0d softfail=%0d",extra,contend,softfail); $finish;
      end
      $display("TIMING job=%0d fallback=%h tail=%h max_rows=%0d stream_hits=%0d objects=%0d",
        job,fallback_mask,tail_mask,max_rows,stream_hits,req[42446:42439]);
      // Claude 30/10: P=G in {2,4,8} are budget-checked lane counts (sweep schedule is lane-generic).
      if($test$plusargs("WORST") && (!(LANES==8 || LANES==4 || LANES==2) || fallback_mask!==16'hffff
          || tail_mask!==16'hffff || req[42446:42439]!=32 || max_rows!=worst_rows || stream_hits==0
          || latency>1168034))$fatal(1,"worst-case coverage/budget");
    end
    for(integer a=0;a<40;a=a+1)begin
      $display("ASSERT %0d %s hits=%0d",a,names[a],hit[a]);
      if(hit[a]==0)begin
        inactive=inactive+1;
        if(!$test$plusargs("ALLOW_INACTIVE"))$fatal(1,"assertion never exercised %0d",a);
      end
    end
    $display("assertion failures: 0, assertions never exercised: %0d",inactive);
    $display("PASS top jobs=%0d max_cycles=%0d softfail=%0d",limit,max_latency,softfail);
    $finish;
  end
  // Claude 30/10 FIX-002 check: the pipelined replay bound must be settled when math answers.
  always @(posedge i_clk_core) begin
    if(dut.u_tsmx_engine.reg_fsm_ctrl_current_state==76'h1000000000000000
       && dut.u_tsmx_engine.w_math_resp_valid) begin : b_xerr
      logic [31:0] n,m,v;
      n=dut.u_tsmx_engine.reg_xph/32'd20000; m=n*(n-32'd1)+32'd99; v=n+m/32'd100+32'd11;
      if(v<=32'd640) v=32'd640;
      if(dut.u_tsmx_engine.reg_xerr!==v || dut.u_tsmx_engine.w_xerr!==v)
        $fatal(1,"FIX-002 replay bound not settled: %0d vs %0d",dut.u_tsmx_engine.reg_xerr,v);
      xerr_checks=xerr_checks+1;
    end
  end
endmodule
