// Claude 04/11/2026: system bench of the ZCU106 board top (tsmx_board_top = shim + TSM-X, PARA_DIRECT=0).
// An AXI4-Lite master replays exactly the xsdb sequence of board/run_tsmx_board.tcl; an AXI-Stream
// source/sink stands in for axi_fifo_mm_s (store-and-forward TX, always-ready RX).
// +FILE=<vectors.mem> +SEQ=<tag>_seq.mem +LIMIT=<n>
`timescale 1ns/1ps
module tb_board_top;
  localparam integer VW=48037, JOBS=4000;
  logic clk=0, resetn=0;
  always #5 clk=~clk;
  // AXI-Lite (shared signals per port)
  logic [15:0] c_awaddr,c_araddr; logic c_awvalid,c_wvalid,c_bready,c_arvalid,c_rready; logic [31:0] c_wdata;
  wire c_awready,c_wready,c_bvalid,c_arready,c_rvalid; wire [1:0] c_bresp,c_rresp; wire [31:0] c_rdata;
  logic [11:0] s_awaddr,s_araddr; logic s_awvalid,s_wvalid,s_bready,s_arvalid,s_rready; logic [31:0] s_wdata;
  wire s_awready,s_wready,s_bvalid,s_arready,s_rvalid; wire [1:0] s_bresp,s_rresp; wire [31:0] s_rdata;
  logic [31:0] rx_tdata; logic [3:0] rx_tkeep; logic rx_tlast,rx_tvalid; wire rx_tready;
  wire [31:0] tx_tdata; wire [3:0] tx_tkeep; wire tx_tlast,tx_tvalid; logic tx_tready=1;
  wire brake,heartbeat;
  tsmx_board_top dut(.clk(clk),.resetn(resetn),
    .s_axi_csr_awaddr(c_awaddr),.s_axi_csr_awprot(3'd0),.s_axi_csr_awvalid(c_awvalid),.s_axi_csr_awready(c_awready),
    .s_axi_csr_wdata(c_wdata),.s_axi_csr_wstrb(4'hf),.s_axi_csr_wvalid(c_wvalid),.s_axi_csr_wready(c_wready),
    .s_axi_csr_bresp(c_bresp),.s_axi_csr_bvalid(c_bvalid),.s_axi_csr_bready(c_bready),
    .s_axi_csr_araddr(c_araddr),.s_axi_csr_arprot(3'd0),.s_axi_csr_arvalid(c_arvalid),.s_axi_csr_arready(c_arready),
    .s_axi_csr_rdata(c_rdata),.s_axi_csr_rresp(c_rresp),.s_axi_csr_rvalid(c_rvalid),.s_axi_csr_rready(c_rready),
    .s_axi_shim_awaddr(s_awaddr),.s_axi_shim_awvalid(s_awvalid),.s_axi_shim_awready(s_awready),
    .s_axi_shim_wdata(s_wdata),.s_axi_shim_wstrb(4'hf),.s_axi_shim_wvalid(s_wvalid),.s_axi_shim_wready(s_wready),
    .s_axi_shim_bresp(s_bresp),.s_axi_shim_bvalid(s_bvalid),.s_axi_shim_bready(s_bready),
    .s_axi_shim_araddr(s_araddr),.s_axi_shim_arvalid(s_arvalid),.s_axi_shim_arready(s_arready),
    .s_axi_shim_rdata(s_rdata),.s_axi_shim_rresp(s_rresp),.s_axi_shim_rvalid(s_rvalid),.s_axi_shim_rready(s_rready),
    .s_axis_rx_tdata(rx_tdata),.s_axis_rx_tkeep(rx_tkeep),.s_axis_rx_tlast(rx_tlast),.s_axis_rx_tvalid(rx_tvalid),
    .s_axis_rx_tready(rx_tready),.m_axis_tx_tdata(tx_tdata),.m_axis_tx_tkeep(tx_tkeep),.m_axis_tx_tlast(tx_tlast),
    .m_axis_tx_tvalid(tx_tvalid),.m_axis_tx_tready(tx_tready),.brake(brake),.heartbeat(heartbeat));

  // ---- AXI-Lite master: AW and W launched together, ready accepted independently (like SmartConnect) ----
  task automatic cw(input [15:0] a, input [31:0] d);
    bit aw_done=0, w_done=0;
    @(negedge clk); c_awaddr=a; c_awvalid=1; c_wdata=d; c_wvalid=1; c_bready=1;
    while(!(aw_done && w_done)) begin
      @(posedge clk); if(c_awready) aw_done=1; if(c_wready) w_done=1;
      #1; if(aw_done) c_awvalid=0; if(w_done) c_wvalid=0;
    end
    while(!c_bvalid) @(posedge clk);
    if(c_bresp!=0) $fatal(1,"CSR write error addr=%h",a);
    @(negedge clk); c_bready=0;
  endtask
  task automatic cr(input [15:0] a, output [31:0] d);
    @(negedge clk); c_araddr=a; c_arvalid=1; c_rready=1;
    do @(posedge clk); while(!c_arready); #1 c_arvalid=0;
    while(!c_rvalid) @(posedge clk); d=c_rdata; @(negedge clk); c_rready=0;
  endtask
  task automatic sw(input [11:0] a, input [31:0] d);
    bit aw_done=0, w_done=0;
    @(negedge clk); s_awaddr=a; s_awvalid=1; s_wdata=d; s_wvalid=1; s_bready=1;
    while(!(aw_done && w_done)) begin
      @(posedge clk); if(s_awready) aw_done=1; if(s_wready) w_done=1;
      #1; if(aw_done) s_awvalid=0; if(w_done) s_wvalid=0;
    end
    while(!s_bvalid) @(posedge clk);
    if(s_bresp!=0) $fatal(1,"shim write error addr=%h",a);
    @(negedge clk); s_bready=0;
  endtask
  task automatic sr(input [11:0] a, output [31:0] d);
    @(negedge clk); s_araddr=a; s_arvalid=1; s_rready=1;
    do @(posedge clk); while(!s_arready); #1 s_arvalid=0;
    while(!s_rvalid) @(posedge clk); d=s_rdata; @(negedge clk); s_rready=0;
  endtask

  // ---- AXI-Stream FIFO stand-in ----
  task automatic send_frame(input logic [44672:0] f);
    logic [31:0] wd;
    for(int k=0;k<1399;k++) begin
      if(k==0) wd=32'd1; else if(k==1) wd=32'd5585;
      else if(k<1398) begin wd=f[44672-32*(k-2) -: 32]; wd={wd[7:0],wd[15:8],wd[23:16],wd[31:24]}; end
      else wd={24'd0,f[0],7'd0};
      @(negedge clk); rx_tdata=wd; rx_tvalid=1; rx_tkeep=(k==1398)?4'b0001:4'hf; rx_tlast=(k==1398);
      @(posedge clk); while(!rx_tready) @(posedge clk);
    end
    @(negedge clk); rx_tvalid=0; rx_tlast=0;
  endtask
  logic [1903:0] txbuf; integer txw=0, txframes=0; logic [1896:0] last_cmd;
  always @(posedge clk) if(tx_tvalid && tx_tready) begin
    if(txw>=2) for(int b=0;b<4;b++) if(4*(txw-2)+b<238) txbuf[1903-8*(4*(txw-2)+b) -:8]=tx_tdata[8*b +:8];
    if(txw==0 && tx_tdata!==32'd2) $fatal(1,"tx type");
    if(txw==1 && tx_tdata!==32'd238) $fatal(1,"tx length");
    if(tx_tlast) begin
      if(txw!=61 || tx_tkeep!==4'b0011) $fatal(1,"tx framing");
      last_cmd=txbuf[1903:7]; txframes=txframes+1; txw=0;
    end else txw=txw+1;
  end

  logic [VW-1:0] vec[0:JOBS-1]; logic [71:0] sq[0:JOBS-1];
  logic reset_job; logic [44672:0] req; logic [37:0] e_rsp; logic [1896:0] e_cmd; logic [331:0] e_ing;
  logic [7:0] e_sup; logic [31:0] e_lost; logic [1055:0] e_event;
  logic [31:0] v, lo, hi, st, cyc, ccyc, reason, status, lost, es; logic [1055:0] ev;
  integer limit=5, n, fd, j, k, log_count=0, frames_before, errors=0;
  string file="vectors.mem", seqf="seq.mem";
  task automatic bringup();
    cw(16'h00,32'h4); n=0; v=0;
    while(v!==32'd1) begin cr(16'h4c,v); n++; if(n>200000) $fatal(1,"CONFIG_VALID never set"); end
    cw(16'h00,32'h1); cr(16'h00,v); if(v!==1) $fatal(1,"CTRL.en");
  endtask
  task automatic core_reset();
    sw(12'h000,0); repeat(5) @(negedge clk); sw(12'h000,1); repeat(5) @(negedge clk);
  endtask
  initial begin
    void'($value$plusargs("FILE=%s",file)); void'($value$plusargs("SEQ=%s",seqf)); void'($value$plusargs("LIMIT=%d",limit));
    $readmemh(seqf,sq);
    fd=$fopen(file,"r"); for(j=0;j<limit;j++) if($fscanf(fd,"%h",vec[j])!=1) $fatal(1,"vector parse %0d",j);
    {c_awvalid,c_wvalid,c_bready,c_arvalid,c_rready,s_awvalid,s_wvalid,s_bready,s_arvalid,s_rready,rx_tvalid,rx_tlast}='0;
    rx_tdata=0; rx_tkeep=0;
    repeat(10) @(negedge clk); resetn=1; repeat(10) @(negedge clk);
    sr(12'h028,v); if(v!==32'h75B0A1D4) $fatal(1,"shim id %h",v);
    core_reset();
    for(j=0;j<limit;j++) begin
      {reset_job,req,e_rsp,e_cmd,e_ing,e_sup,e_lost,e_event}=vec[j];
      if(reset_job) begin core_reset(); log_count=0; bringup(); end
      sw(12'h004,req[44672:44641]); sw(12'h008,sq[j][31:0]);
      if(req[33856]) sw(12'h00C,1);
      frames_before=txframes;
      send_frame(req);
      do sr(12'h010,st); while(!st[0]);
      sr(12'h014,lo); sr(12'h018,hi);
      do sr(12'h010,st); while(!st[4]);
      sr(12'h01C,cyc); sw(12'h010,1);
      log_count++; sw(12'h020,(log_count>64)?63:log_count-1);
      do sr(12'h010,st); while(!st[5]);
      for(k=0;k<33;k++) begin sr(12'h100+4*k,v); ev[32*k +:32]=v; end
      repeat(100) @(negedge clk);
      cr(16'h28,reason); cr(16'h04,status); cr(16'h24,lost); cr(16'h2c,ccyc);
      es=0; es[1]=e_rsp[0]; es[2]=!e_rsp[0] || e_rsp[28:26]==3'd3 || e_rsp[9]; es[5:3]=e_rsp[28:26];
      es[6]=e_sup[1]; es[7]=e_sup[0]; es[8]=e_rsp[0]; es[17:16]=e_rsp[11:10];
      if({hi[5:0],lo}!==e_rsp) begin errors++; $display("ERR job=%0d rsp %h exp %h",j,{hi[5:0],lo},e_rsp); end
      if(ev!==e_event) begin errors++; $display("ERR job=%0d event",j); end
      if(txframes-frames_before!=sq[j][39:32]) begin errors++; $display("ERR job=%0d frames %0d exp %0d",j,txframes-frames_before,sq[j][39:32]); end
      if(txframes!=frames_before && last_cmd!==e_cmd) begin errors++; $display("ERR job=%0d cmd",j); end
      if(reason!=={24'd0,e_rsp[36:29]} || status!==es || lost!==e_lost) begin errors++; $display("ERR job=%0d csr reason=%h status=%h/%h lost=%h",j,reason,status,es,lost); end
      if(ccyc!==sq[j][71:40]) begin errors++; $display("ERR job=%0d csr_cycles %0d sim %0d",j,ccyc,sq[j][71:40]); end
      $display("BOARDSIM job=%0d rsp=%h cycles=%0d csr_cycles=%0d frames=%0d", j,{hi[5:0],lo},cyc,ccyc,txframes-frames_before);
    end
    if(errors) $fatal(1,"FAIL errors=%0d",errors);
    $display("PASS board_top jobs=%0d",limit);
    $finish;
  end
endmodule
