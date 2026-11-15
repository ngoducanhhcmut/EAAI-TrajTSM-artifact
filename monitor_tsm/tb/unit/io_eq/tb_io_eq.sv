`timescale 1ns/1ps
module tb_io_eq;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic rx_valid, rx_last, core_ready, cmd_valid, tx_ready;
  logic [31:0] rx_data, time_us; logic [3:0] rx_keep; logic [1896:0] cmd_data;
  logic a_req_ready,b_req_ready,a_cv,b_cv,a_cmdr,b_cmdr,a_rxr,b_rxr,a_tv,b_tv,a_tl,b_tl;
  logic [44672:0] a_cd,b_cd; logic [7:0] a_cr,b_cr; logic [31:0] a_td,b_td; logic [3:0] a_tk,b_tk;
  m_tsmx_io u_new(.i_clk_core(clk),.i_rst_n_core(rst_n),.i_req_valid(1'b0),.i_req_data('0),
    .o_req_ready(a_req_ready),.o_core_valid(a_cv),.o_core_data(a_cd),.o_core_reason(a_cr),
    .i_core_ready(core_ready),.i_time_us(time_us),.i_cmd_valid(cmd_valid),.i_cmd_data(cmd_data),
    .o_cmd_ready(a_cmdr),.i_rx_valid(rx_valid),.i_rx_data(rx_data),.i_rx_keep(rx_keep),
    .i_rx_last(rx_last),.o_rx_ready(a_rxr),.o_tx_valid(a_tv),.o_tx_data(a_td),.o_tx_keep(a_tk),
    .o_tx_last(a_tl),.i_tx_ready(tx_ready));
  m_tsmx_io_old u_old(.i_clk_core(clk),.i_rst_n_core(rst_n),.i_req_valid(1'b0),.i_req_data('0),
    .o_req_ready(b_req_ready),.o_core_valid(b_cv),.o_core_data(b_cd),.o_core_reason(b_cr),
    .i_core_ready(core_ready),.i_time_us(time_us),.i_cmd_valid(cmd_valid),.i_cmd_data(cmd_data),
    .o_cmd_ready(b_cmdr),.i_rx_valid(rx_valid),.i_rx_data(rx_data),.i_rx_keep(rx_keep),
    .i_rx_last(rx_last),.o_rx_ready(b_rxr),.o_tx_valid(b_tv),.o_tx_data(b_td),.o_tx_keep(b_tk),
    .o_tx_last(b_tl),.i_tx_ready(tx_ready));
  int cyc=0, frames=0, err=0, w=0, stall=0, hold=0, tmo=0;
  always @(posedge clk) begin
    cyc<=cyc+1;
    if(rst_n) begin
      if({a_req_ready,a_cv,a_cd,a_cr,a_cmdr,a_rxr,a_tv,a_td,a_tk,a_tl}!==
         {b_req_ready,b_cv,b_cd,b_cr,b_cmdr,b_rxr,b_tv,b_td,b_tk,b_tl}) begin
        err<=err+1; if(err<5) $display("MISMATCH cyc=%0d",cyc);
      end
      if(a_cv && core_ready) frames<=frames+1;
      if(a_cv && core_ready && a_cr==8'd3) tmo<=tmo+1;
    end
  end
  // Mostly well-formed frames (header 1, 5585, 1397 payload words), with random faults and gaps.
  always @(negedge clk) begin
    rst_n <= (cyc>3);
    if(hold>0) hold=hold-1; else if(($urandom%200000)==0) hold=30000;
    core_ready <= hold==0 && ($urandom%4)!=0; tx_ready <= ($urandom%3)!=0;
    cmd_valid <= ($urandom%50)==0; cmd_data <= {$urandom,$urandom,$urandom} ^ {1897{$urandom%2==1}};
    time_us <= $urandom;
    if(stall>0) stall=stall-1; else if(($urandom%60000)==0) stall=17000+($urandom%200);
    rx_valid <= stall==0 && ($urandom%8)!=0;
    if(rx_valid && a_rxr) w = (w==1398) ? 0 : w+1;
    rx_data <= (w==0)?32'd1:(w==1)?32'd5585:{$urandom};
    rx_keep <= (w==1398)?4'b0001:4'hf;
    rx_last <= (w==1398);
    if(($urandom%3000)==0) rx_data <= $urandom;
    if(($urandom%5000)==0) rx_last <= 1'b1;
    if(w==1398) rx_data[6:0] <= ($urandom%4==0) ? 7'h11 : 7'd0;
    if(cyc>3000000) begin $display("IO_EQ frames=%0d timeouts=%0d mismatches=%0d %s",frames,tmo,err,err==0?"PASS":"FAIL"); $finish; end
  end
endmodule
