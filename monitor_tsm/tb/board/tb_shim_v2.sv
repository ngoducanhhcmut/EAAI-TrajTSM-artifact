// Claude 10/11/2026: unit check of tsmx_board_shim_v2 board time base (VCU118 joint run).
`timescale 1ns/1ps
module tb_shim_v2;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  logic [11:0] awaddr=0, araddr=0; logic awvalid=0, wvalid=0, bready=1, arvalid=0, rready=1;
  logic [31:0] wdata=0; logic [3:0] wstrb=4'hf;
  wire awready, wready, bvalid, arready, rvalid; wire [1:0] bresp, rresp; wire [31:0] rdata;
  wire core_rst_n, ack_valid, rsp_ready, log_valid, log_ready; wire [31:0] time_us, ack_seq; wire [9:0] log_idx;
  logic brake=0;
  tsmx_board_shim_v2 dut(.clk(clk),.rst_n(rst_n),
    .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),.s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .core_rst_n(core_rst_n),.time_us(time_us),.ack_seq(ack_seq),.ack_valid(ack_valid),.rsp_valid(1'b0),.rsp_data(38'd0),
    .rsp_ready(rsp_ready),.brake(brake),.heartbeat(1'b0),.int_irq(1'b0),.log_idx(log_idx),.log_valid(log_valid),
    .log_ready(log_ready),.log_ready_in(1'b0),.log_data(1056'd0),.log_valid_in(1'b0),.rx_valid(1'b0),.rx_ready(1'b0),.rx_last(1'b0));
  integer errors=0;
  task automatic wr(input [11:0] a, input [31:0] d);
    @(negedge clk); awaddr=a; awvalid=1; wdata=d; wvalid=1;
    fork
      begin do @(posedge clk); while(!awready); @(negedge clk); awvalid=0; end
      begin do @(posedge clk); while(!wready); @(negedge clk); wvalid=0; end
    join
    while(!bvalid) @(posedge clk);
    @(negedge clk);
  endtask
  task automatic rd(input [11:0] a, output [31:0] d);
    @(negedge clk); araddr=a; arvalid=1;
    do @(posedge clk); while(!arready); @(negedge clk); arvalid=0;
    while(!rvalid) @(posedge clk); d=rdata; @(negedge clk);
  endtask
  task automatic check(input string n, input logic c); if(!c) begin errors++; $display("FAIL %s",n); end endtask
  logic [31:0] v, c0, t0, t1;
  integer i, step_err=0, last_change=-1, cyc=0;
  always @(posedge clk) cyc<=cyc+1;
  logic [31:0] tq; logic chk_en=1; initial tq=0;
  always @(posedge clk) if(dut.time_auto && chk_en) begin
    if(time_us!=tq) begin
      if(time_us!=tq+1) step_err++;
      if(last_change>=0 && cyc-last_change!=100) step_err++;
      last_change=cyc;
    end
    tq<=time_us;
  end else begin tq<=time_us; last_change=-1; end
  initial begin
    repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
    rd(12'h028,v); check("ID", v==32'h75B0A1D4);
    wr(12'h004,32'd1000); rd(12'h004,v); check("TIME load (manual)", v==32'd1000);
    repeat(500) @(posedge clk); rd(12'h004,v); check("TIME holds when time_auto=0", v==32'd1000);
    wr(12'h000,32'h3); rd(12'h000,v); check("CTRL readback", v==32'h3);
    rd(12'h02C,c0);
    repeat(100000) @(posedge clk);                       // 1 ms at 100 MHz
    rd(12'h004,t0); check("TIME advanced ~1000 us", t0>=32'd1999 && t0<=32'd2001);
    chk_en=0; wr(12'h004,32'd50000); rd(12'h004,v); @(negedge clk); chk_en=1; check("TIME write reloads while auto", v==32'd50000);
    wr(12'h038,32'd0); rd(12'h038,v); check("BRAKE armed", v==32'd0);
    repeat(1234) @(posedge clk); @(negedge clk); brake=1; repeat(3) @(posedge clk); @(negedge clk); brake=0;
    repeat(300) @(posedge clk); @(negedge clk); brake=1;   // second rise must not overwrite
    rd(12'h038,v); check("BRAKE captured", v==32'd1);
    rd(12'h030,t1); check("BRAKE_T_US ~ 50012", t1>=32'd50011 && t1<=32'd50013);
    rd(12'h034,v); rd(12'h02C,c0); check("BRAKE_CYC before now", v<c0);
    check("1 us steps exactly every 100 clocks", step_err==0);
    begin : time_ack
      integer ack_cyc=-1, tchg=-1; logic [31:0] tprev;
      wr(12'h008,32'd77); tprev=time_us;
      fork
        begin wr(12'h03C,32'd90000); end
        begin repeat(40) begin @(posedge clk); if(ack_valid && ack_cyc<0) ack_cyc=cyc; if(time_us==32'd90000 && tchg<0) tchg=cyc; end end
      join
      check("TIME_ACK same clock", ack_cyc>=0 && ack_cyc==tchg && ack_seq==32'd77);
    end
    begin : hold
      integer n=0; wr(12'h000,32'h7); repeat(50) begin @(posedge clk); if(ack_valid) n++; end
      check("ACK_HOLD level", n==50); wr(12'h000,32'h3); repeat(3) @(posedge clk); check("ACK_HOLD release", !ack_valid);
    end
    wr(12'h000,32'h1); rd(12'h004,t0); repeat(1000) @(posedge clk); rd(12'h004,t1); check("auto off holds", t0==t1);
    $display("SHIM_V2 %s errors=%0d", errors==0 ? "PASS":"FAIL", errors); $finish;
  end
endmodule
