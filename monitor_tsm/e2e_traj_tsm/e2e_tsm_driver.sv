// Project TSM-X; Author TSMX project; Version 0.1; 2026-10-29.
// Protocol requirements: project AXI4-Lite contract spec6.1 ASSUMPTION-011.
`timescale 1ns/1ps
module e2e_tsm_driver;
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
  `include "tsm_tasks.svh"
