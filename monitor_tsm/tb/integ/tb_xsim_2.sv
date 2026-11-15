// Project TSM-X; Author TSMX project; Version 0.1; 2026-10-29.
// Protocol requirements: project AXI4-Lite contract spec6.1 ASSUMPTION-011.
`timescale 1ns/1ps
module tb_m_tsmx_top;
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
  m_tsmx_top #(.PARA_DIRECT(1),.PARA_G(LANES),.PARA_P(LANES)) dut (
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
  always @(negedge i_clk_core) i_tx_ready=(cyc%7)!=0;
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
      if(good!==1'b1) begin
        $display("ASSERT_FAIL %0d %s job=%0d cycle=%0d",id,names[id],job,cyc);
        $fatal(1,"assertion failure");
      end
    end
  endtask
  always @(posedge i_clk_core) begin
    cyc=cyc+1;
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
          frames=frames+1;txword=0;
        end else txword=txword+1;
      end
    end else begin tx_stalled=0;rsp_stalled=0;b_stalled=0;r_stalled=0;txword=0;end
  end
  task automatic bus_read(input logic [15:0] addr,output logic [31:0] data);
    @(negedge i_clk_core);i_axi_araddr=addr;i_axi_arvalid=1;i_axi_rready=0;
    do @(posedge i_clk_core); while(!o_axi_arready);
    @(negedge i_clk_core);i_axi_arvalid=0;
    while(!o_axi_rvalid) @(negedge i_clk_core);
    data=o_axi_rdata;
    if($test$plusargs("TRACE"))$display("READ_SAMPLE addr=%h rd=%h rv=%b",addr,data,o_axi_rvalid);
    repeat(2) @(negedge i_clk_core);
    i_axi_rready=1;@(negedge i_clk_core);i_axi_rready=0;
  endtask
  task automatic bus_write(input logic [15:0] addr,input logic [31:0] data);
    @(negedge i_clk_core);i_axi_awaddr=addr;i_axi_awvalid=1;i_axi_bready=0;
    do @(posedge i_clk_core); while(!o_axi_awready);
    @(negedge i_clk_core);i_axi_awvalid=0;
    repeat(2) @(negedge i_clk_core);
    i_axi_wdata=data;i_axi_wstrb=4'hf;i_axi_wvalid=1;
    do @(posedge i_clk_core); while(!o_axi_wready);
    @(negedge i_clk_core);i_axi_wvalid=0;
    while(!o_axi_bvalid) @(negedge i_clk_core);
    repeat(2) @(negedge i_clk_core);
    i_axi_bready=1;@(negedge i_clk_core);i_axi_bready=0;
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
    sink=$value$plusargs("LIMIT=%d",limit);
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
    bus_read(16'hffff,rd);
    for(job=0;job<limit;job=job+1) begin
      {reset_job,req,expected_rsp,expected_cmd,expected_ing,expected_sup,expected_lost,expected_event}=vectors[job];
      if(reset_job) begin
        @(negedge i_clk_core);i_rst_n_core=0;
        repeat(3) @(negedge i_clk_core);i_rst_n_core=1;
        repeat(5) @(negedge i_clk_core);log_count=0;frames=0;
      end
      @(negedge i_clk_core);i_req_data=req;i_req_valid=1;
      i_time_us=req[44672:44641];
      i_ack_valid=req[33856];i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528];
      while(!o_req_ready) @(negedge i_clk_core);
      @(posedge i_clk_core);start_cyc=cyc;start_time=$time;
      @(negedge i_clk_core);i_req_valid=0;i_ack_valid=0;
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
      if(o_log_data!==expected_event)$fatal(1,"event mismatch job=%0d actual=%h expected=%h",job,o_log_data,expected_event);
      i_log_ready=1;@(negedge i_clk_core);i_log_ready=0;
      while(txword!=0 || o_tx_valid) @(negedge i_clk_core);
      bus_read(16'h28,rd);
      if(rd!=={24'd0,expected_rsp[36:29]})$fatal(1,"CSR reason");
      bus_read(16'h04,rd);
      expected_status=32'd0;
      expected_status[1]=expected_rsp[0];
      expected_status[2]=!expected_rsp[0] || expected_rsp[28:26]==3'd3 || expected_rsp[9];
      expected_status[5:3]=expected_rsp[28:26];
      expected_status[6]=expected_sup[1];expected_status[7]=expected_sup[0];
      expected_status[8]=expected_rsp[0];expected_status[17:16]=expected_rsp[11:10];
      if(rd!==expected_status)$fatal(1,"CSR status job=%0d actual=%h expected=%h",job,rd,expected_status);
      if(dut.u_tsmx_engine.reg_ing!==expected_ing
        || {dut.u_tsmx_engine.reg_mode,dut.u_tsmx_engine.reg_good,dut.u_tsmx_engine.reg_fault,
          dut.u_tsmx_engine.reg_pending_valid,dut.u_tsmx_engine.reg_backup_valid}!==expected_sup)$fatal(1,"retained state mismatch");
      bus_read(16'h24,rd);if(rd!==expected_lost)$fatal(1,"CSR lost");
      bus_read(16'h2c,rd);if(rd!==latency)$fatal(1,"CSR cycles actual=%0d expected=%0d",rd,latency);
      $display("JOB %0d PASS cycles=%0d",job,latency);
    end
    for(integer a=0;a<40;a=a+1)begin
      $display("ASSERT %0d %s hits=%0d",a,names[a],hit[a]);
      if(hit[a]==0)begin
        inactive=inactive+1;
        if(!$test$plusargs("ALLOW_INACTIVE"))$fatal(1,"assertion never exercised %0d",a);
      end
    end
    $display("assertion failures: 0, assertions never exercised: %0d",inactive);
    $display("PASS top jobs=%0d max_cycles=%0d",limit,max_latency);
    $finish;
  end
endmodule
