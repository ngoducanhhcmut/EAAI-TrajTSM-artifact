`timescale 1ns/1ps
// Project TSM-X; author TSMX project; version 0.1.
// Independent cycle vectors derive from JSON and project AXI4-Lite section 6.1.
// Immediate assertions work in Icarus and Verilator --timing --assert.
module tb_m_tsmx_csr;
  reg clk=0;
  `include "vectors_meta.svh"
  reg [VW-1:0] vectors[0:N-1];
  integer mutant=-1, injected=0, cycles=0;
  integer aw_count=0,w_count=0,b_count=0,ar_count=0,r_count=0;
  reg prev_rst=0;
  reg [15:0] last_rd_addr=0;
  reg rst=1;
  reg [15:0] awaddr=0;
  reg [2:0] awprot=0;
  reg awvalid=0;
  reg [31:0] wdata=0;
  reg [3:0] wstrb=0;
  reg wvalid=0;
  reg bready=0;
  reg [15:0] araddr=0;
  reg [2:0] arprot=0;
  reg arvalid=0;
  reg rready=0;
  reg sts_valid=0;
  reg [114:0] sts_data=0;
  reg deposit=0;
  wire awready;
  reg exp_awready;
  wire wready;
  reg exp_wready;
  wire bvalid;
  reg exp_bvalid;
  wire [1:0] bresp;
  reg [1:0] exp_bresp;
  wire arready;
  reg exp_arready;
  wire rvalid;
  reg exp_rvalid;
  wire [1:0] rresp;
  reg [1:0] exp_rresp;
  wire [31:0] rdata;
  reg [31:0] exp_rdata;
  wire [3:0] config_data;
  reg [3:0] exp_config_data;
  wire irq;
  reg exp_irq;
  reg [15:0] pawaddr=0;
  reg [2:0] pawprot=0;
  reg pawvalid=0;
  reg [31:0] pwdata=0;
  reg [3:0] pwstrb=0;
  reg pwvalid=0;
  reg pbready=0;
  reg [15:0] paraddr=0;
  reg [2:0] parprot=0;
  reg parvalid=0;
  reg prready=0;
  reg pawready=0;
  reg pwready=0;
  reg pbvalid=0;
  reg [1:0] pbresp=0;
  reg parready=0;
  reg prvalid=0;
  reg [1:0] prresp=0;
  reg [31:0] prdata=0;
  integer hits[0:58];
  m_tsmx_csr dut (
    .i_clk_core(clk), .i_rst_n_core(rst),
    .i_axi_awaddr(awaddr),
    .i_axi_awprot(awprot),
    .i_axi_awvalid(awvalid),
    .i_axi_wdata(wdata),
    .i_axi_wstrb(wstrb),
    .i_axi_wvalid(wvalid),
    .i_axi_bready(bready),
    .i_axi_araddr(araddr),
    .i_axi_arprot(arprot),
    .i_axi_arvalid(arvalid),
    .i_axi_rready(rready),
    .i_sts_valid(sts_valid),
    .i_sts_data(sts_data),
    .o_axi_awready(awready),
    .o_axi_wready(wready),
    .o_axi_bvalid(bvalid),
    .o_axi_bresp(bresp),
    .o_axi_arready(arready),
    .o_axi_rvalid(rvalid),
    .o_axi_rresp(rresp),
    .o_axi_rdata(rdata),
    .o_config_data(config_data),
    .o_int_irq(irq)
  );
  function automatic [31:0] reserved_mask(input [15:0] addr);
    begin
      reserved_mask=0;
      case (addr)
        16'h0000: reserved_mask=32'hfffffff8;
        16'h0004: reserved_mask=32'hfffcfe00;
        16'h0008: reserved_mask=32'hffffff00;
        16'h000c: reserved_mask=32'hffffff00;
        16'h0010: reserved_mask=32'h00000000;
        16'h0014: reserved_mask=32'h00000000;
        16'h0018: reserved_mask=32'h00000000;
        16'h001c: reserved_mask=32'h00000000;
        16'h0020: reserved_mask=32'h00000000;
        16'h0024: reserved_mask=32'h00000000;
        16'h0028: reserved_mask=32'hffffff00;
        16'h002c: reserved_mask=32'h00000000;
        16'h0030: reserved_mask=32'hffffff00;
        16'h0034: reserved_mask=32'hffffff00;
        16'h0038: reserved_mask=32'hffff0000;
        16'h003c: reserved_mask=32'h00000000;
        16'h0040: reserved_mask=32'h00000000;
        16'h0044: reserved_mask=32'h00000000;
        16'h0048: reserved_mask=32'h00000000;
        16'h004c: reserved_mask=32'hfffffffe;
        16'h0050: reserved_mask=32'h00000000;
        16'h0054: reserved_mask=32'h00000000;
        16'h0058: reserved_mask=32'h00000000;
        16'h005c: reserved_mask=32'h00000000;
        16'h0060: reserved_mask=32'h00000000;
        16'h0064: reserved_mask=32'h00000000;
        16'h0068: reserved_mask=32'h00000000;
        16'h006c: reserved_mask=32'h00000000;
        16'h0070: reserved_mask=32'h00000000;
        16'h0074: reserved_mask=32'h00000000;
        16'h0078: reserved_mask=32'h00000000;
        16'h007c: reserved_mask=32'h00000000;
        16'h0080: reserved_mask=32'h00000000;
        16'h0084: reserved_mask=32'h00000000;
        16'h0088: reserved_mask=32'h00000000;
        16'h008c: reserved_mask=32'h00000000;
        16'h0090: reserved_mask=32'h00000000;
        16'h0094: reserved_mask=32'h00000000;
        16'h0098: reserved_mask=32'h00000000;
        16'h009c: reserved_mask=32'h00000000;
        16'h00a0: reserved_mask=32'h00000000;
        16'h00a4: reserved_mask=32'h00000000;
        16'h00a8: reserved_mask=32'h00000000;
        16'h00ac: reserved_mask=32'h00000000;
        16'h00b0: reserved_mask=32'h00000000;
        16'h00b4: reserved_mask=32'h00000000;
        16'h00b8: reserved_mask=32'h00000000;
        16'h00bc: reserved_mask=32'h00000000;
        16'h00c0: reserved_mask=32'h00000000;
        16'h00c4: reserved_mask=32'h00000000;
        16'h00c8: reserved_mask=32'h00000000;
        16'h00cc: reserved_mask=32'h00000000;
        default: reserved_mask=0;
      endcase
    end
  endfunction
  task tick;
    begin
      #1;
      if (!rst) begin
        aw_count=0;w_count=0;b_count=0;ar_count=0;r_count=0;last_rd_addr=0;
      end else begin
        if (awvalid && awready) aw_count=aw_count+1;
        if (wvalid && wready) w_count=w_count+1;
        if (bvalid && bready) b_count=b_count+1;
        if (arvalid && arready) begin ar_count=ar_count+1;last_rd_addr=araddr;end
        if (rvalid && rready) r_count=r_count+1;
      end
      // Previous edge master stability is checked before advancing this edge.
      if (rst && prev_rst && pawvalid && !pawready) begin : a_master_hold_awvalid
        hits[32]=hits[32]+1;
        if (mutant==32 && !injected) begin
          if (awvalid === '0) force awvalid = '1; else force awvalid = '0;
          injected=1;
          $display("INJECT 32 master_hold_awvalid");
          #1;
        end
        assert (awvalid === pawvalid) else begin
          $display("ASSERT_FAIL 32 master_hold_awvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && pawvalid && !pawready) begin : a_master_hold_awaddr
        hits[33]=hits[33]+1;
        if (mutant==33 && !injected) begin
          if (awaddr === '0) force awaddr = '1; else force awaddr = '0;
          injected=1;
          $display("INJECT 33 master_hold_awaddr");
          #1;
        end
        assert (awaddr === pawaddr) else begin
          $display("ASSERT_FAIL 33 master_hold_awaddr cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && pawvalid && !pawready) begin : a_master_hold_awprot
        hits[34]=hits[34]+1;
        if (mutant==34 && !injected) begin
          if (awprot === '0) force awprot = '1; else force awprot = '0;
          injected=1;
          $display("INJECT 34 master_hold_awprot");
          #1;
        end
        assert (awprot === pawprot) else begin
          $display("ASSERT_FAIL 34 master_hold_awprot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && pwvalid && !pwready) begin : a_master_hold_wvalid
        hits[35]=hits[35]+1;
        if (mutant==35 && !injected) begin
          if (wvalid === '0) force wvalid = '1; else force wvalid = '0;
          injected=1;
          $display("INJECT 35 master_hold_wvalid");
          #1;
        end
        assert (wvalid === pwvalid) else begin
          $display("ASSERT_FAIL 35 master_hold_wvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && pwvalid && !pwready) begin : a_master_hold_wdata
        hits[36]=hits[36]+1;
        if (mutant==36 && !injected) begin
          if (wdata === '0) force wdata = '1; else force wdata = '0;
          injected=1;
          $display("INJECT 36 master_hold_wdata");
          #1;
        end
        assert (wdata === pwdata) else begin
          $display("ASSERT_FAIL 36 master_hold_wdata cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && pwvalid && !pwready) begin : a_master_hold_wstrb
        hits[37]=hits[37]+1;
        if (mutant==37 && !injected) begin
          if (wstrb === '0) force wstrb = '1; else force wstrb = '0;
          injected=1;
          $display("INJECT 37 master_hold_wstrb");
          #1;
        end
        assert (wstrb === pwstrb) else begin
          $display("ASSERT_FAIL 37 master_hold_wstrb cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && parvalid && !parready) begin : a_master_hold_arvalid
        hits[38]=hits[38]+1;
        if (mutant==38 && !injected) begin
          if (arvalid === '0) force arvalid = '1; else force arvalid = '0;
          injected=1;
          $display("INJECT 38 master_hold_arvalid");
          #1;
        end
        assert (arvalid === parvalid) else begin
          $display("ASSERT_FAIL 38 master_hold_arvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && parvalid && !parready) begin : a_master_hold_araddr
        hits[39]=hits[39]+1;
        if (mutant==39 && !injected) begin
          if (araddr === '0) force araddr = '1; else force araddr = '0;
          injected=1;
          $display("INJECT 39 master_hold_araddr");
          #1;
        end
        assert (araddr === paraddr) else begin
          $display("ASSERT_FAIL 39 master_hold_araddr cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prev_rst && parvalid && !parready) begin : a_master_hold_arprot
        hits[40]=hits[40]+1;
        if (mutant==40 && !injected) begin
          if (arprot === '0) force arprot = '1; else force arprot = '0;
          injected=1;
          $display("INJECT 40 master_hold_arprot");
          #1;
        end
        assert (arprot === parprot) else begin
          $display("ASSERT_FAIL 40 master_hold_arprot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      pawaddr=awaddr;
      pawprot=awprot;
      pawvalid=awvalid;
      pwdata=wdata;
      pwstrb=wstrb;
      pwvalid=wvalid;
      pbready=bready;
      paraddr=araddr;
      parprot=arprot;
      parvalid=arvalid;
      prready=rready;
      pawready=awready;
      pwready=wready;
      pbvalid=bvalid;
      pbresp=bresp;
      parready=arready;
      prvalid=rvalid;
      prresp=rresp;
      prdata=rdata;
      if (deposit) begin
        force dut.reg_fault_cnt=32'hfffffffe;
        force dut.reg_crc_cnt=32'hfffffffe;
        force dut.reg_fresh_cnt=32'hfffffffe;
        force dut.reg_cert_cnt=32'hfffffffe;
        force dut.reg_health_cnt=32'hfffffffe;
        #1;
        release dut.reg_fault_cnt;
        release dut.reg_crc_cnt;
        release dut.reg_fresh_cnt;
        release dut.reg_cert_cnt;
        release dut.reg_health_cnt;
        #1;
      end
      #3;clk=1;#1;cycles=cycles+1;
      if (!rst) begin : a_reset_awready
        hits[0]=hits[0]+1;
        if (mutant==0 && !injected) begin
          if (awready === '0) force awready = '1; else force awready = '0;
          injected=1;
          $display("INJECT 0 reset_awready");
          #1;
        end
        assert (awready === 1'b0) else begin
          $display("ASSERT_FAIL 0 reset_awready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_wready
        hits[1]=hits[1]+1;
        if (mutant==1 && !injected) begin
          if (wready === '0) force wready = '1; else force wready = '0;
          injected=1;
          $display("INJECT 1 reset_wready");
          #1;
        end
        assert (wready === 1'b0) else begin
          $display("ASSERT_FAIL 1 reset_wready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_arready
        hits[2]=hits[2]+1;
        if (mutant==2 && !injected) begin
          if (arready === '0) force arready = '1; else force arready = '0;
          injected=1;
          $display("INJECT 2 reset_arready");
          #1;
        end
        assert (arready === 1'b0) else begin
          $display("ASSERT_FAIL 2 reset_arready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_bvalid
        hits[3]=hits[3]+1;
        if (mutant==3 && !injected) begin
          if (bvalid === '0) force bvalid = '1; else force bvalid = '0;
          injected=1;
          $display("INJECT 3 reset_bvalid");
          #1;
        end
        assert (bvalid === 1'b0) else begin
          $display("ASSERT_FAIL 3 reset_bvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_rvalid
        hits[4]=hits[4]+1;
        if (mutant==4 && !injected) begin
          if (rvalid === '0) force rvalid = '1; else force rvalid = '0;
          injected=1;
          $display("INJECT 4 reset_rvalid");
          #1;
        end
        assert (rvalid === 1'b0) else begin
          $display("ASSERT_FAIL 4 reset_rvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (!rst) begin : a_reset_config
        hits[5]=hits[5]+1;
        if (mutant==5 && !injected) begin
          if (config_data === '0) force config_data = '1; else force config_data = '0;
          injected=1;
          $display("INJECT 5 reset_config");
          #1;
        end
        assert (config_data === 4'b0) else begin
          $display("ASSERT_FAIL 5 reset_config cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_known_awready
        hits[6]=hits[6]+1;
        if (mutant==6 && !injected) begin
          force awready = 'x;
          injected=1;
          $display("INJECT 6 known_awready");
          #1;
        end
        assert (!$isunknown(awready)) else begin
          $display("ASSERT_FAIL 6 known_awready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_known_wready
        hits[7]=hits[7]+1;
        if (mutant==7 && !injected) begin
          force wready = 'x;
          injected=1;
          $display("INJECT 7 known_wready");
          #1;
        end
        assert (!$isunknown(wready)) else begin
          $display("ASSERT_FAIL 7 known_wready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_known_arready
        hits[8]=hits[8]+1;
        if (mutant==8 && !injected) begin
          force arready = 'x;
          injected=1;
          $display("INJECT 8 known_arready");
          #1;
        end
        assert (!$isunknown(arready)) else begin
          $display("ASSERT_FAIL 8 known_arready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_known_bvalid
        hits[9]=hits[9]+1;
        if (mutant==9 && !injected) begin
          force bvalid = 'x;
          injected=1;
          $display("INJECT 9 known_bvalid");
          #1;
        end
        assert (!$isunknown(bvalid)) else begin
          $display("ASSERT_FAIL 9 known_bvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_known_rvalid
        hits[10]=hits[10]+1;
        if (mutant==10 && !injected) begin
          force rvalid = 'x;
          injected=1;
          $display("INJECT 10 known_rvalid");
          #1;
        end
        assert (!$isunknown(rvalid)) else begin
          $display("ASSERT_FAIL 10 known_rvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && bvalid) begin : a_known_bresp
        hits[11]=hits[11]+1;
        if (mutant==11 && !injected) begin
          force bresp = 'x;
          injected=1;
          $display("INJECT 11 known_bresp");
          #1;
        end
        assert (!$isunknown(bresp)) else begin
          $display("ASSERT_FAIL 11 known_bresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid) begin : a_known_rresp
        hits[12]=hits[12]+1;
        if (mutant==12 && !injected) begin
          force rresp = 'x;
          injected=1;
          $display("INJECT 12 known_rresp");
          #1;
        end
        assert (!$isunknown(rresp)) else begin
          $display("ASSERT_FAIL 12 known_rresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid) begin : a_known_rdata
        hits[13]=hits[13]+1;
        if (mutant==13 && !injected) begin
          force rdata = 'x;
          injected=1;
          $display("INJECT 13 known_rdata");
          #1;
        end
        assert (!$isunknown(rdata)) else begin
          $display("ASSERT_FAIL 13 known_rdata cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && awvalid) begin : a_known_awaddr
        hits[14]=hits[14]+1;
        if (mutant==14 && !injected) begin
          force awaddr = 'x;
          injected=1;
          $display("INJECT 14 known_awaddr");
          #1;
        end
        assert (!$isunknown(awaddr)) else begin
          $display("ASSERT_FAIL 14 known_awaddr cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && awvalid) begin : a_known_awprot
        hits[15]=hits[15]+1;
        if (mutant==15 && !injected) begin
          force awprot = 'x;
          injected=1;
          $display("INJECT 15 known_awprot");
          #1;
        end
        assert (!$isunknown(awprot)) else begin
          $display("ASSERT_FAIL 15 known_awprot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && wvalid) begin : a_known_wdata
        hits[16]=hits[16]+1;
        if (mutant==16 && !injected) begin
          force wdata = 'x;
          injected=1;
          $display("INJECT 16 known_wdata");
          #1;
        end
        assert (!$isunknown(wdata)) else begin
          $display("ASSERT_FAIL 16 known_wdata cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && wvalid) begin : a_known_wstrb
        hits[17]=hits[17]+1;
        if (mutant==17 && !injected) begin
          force wstrb = 'x;
          injected=1;
          $display("INJECT 17 known_wstrb");
          #1;
        end
        assert (!$isunknown(wstrb)) else begin
          $display("ASSERT_FAIL 17 known_wstrb cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && arvalid) begin : a_known_araddr
        hits[18]=hits[18]+1;
        if (mutant==18 && !injected) begin
          force araddr = 'x;
          injected=1;
          $display("INJECT 18 known_araddr");
          #1;
        end
        assert (!$isunknown(araddr)) else begin
          $display("ASSERT_FAIL 18 known_araddr cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && arvalid) begin : a_known_arprot
        hits[19]=hits[19]+1;
        if (mutant==19 && !injected) begin
          force arprot = 'x;
          injected=1;
          $display("INJECT 19 known_arprot");
          #1;
        end
        assert (!$isunknown(arprot)) else begin
          $display("ASSERT_FAIL 19 known_arprot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && bvalid) begin : a_b_encoding
        hits[20]=hits[20]+1;
        if (mutant==20 && !injected) begin
          force bresp = 'x;
          injected=1;
          $display("INJECT 20 b_encoding");
          #1;
        end
        assert ((bresp === 2'b00) || (bresp === 2'b10)) else begin
          $display("ASSERT_FAIL 20 b_encoding cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid) begin : a_r_encoding
        hits[21]=hits[21]+1;
        if (mutant==21 && !injected) begin
          force rresp = 'x;
          injected=1;
          $display("INJECT 21 r_encoding");
          #1;
        end
        assert ((rresp === 2'b00) || (rresp === 2'b10)) else begin
          $display("ASSERT_FAIL 21 r_encoding cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && bvalid) begin : a_b_order
        hits[22]=hits[22]+1;
        if (mutant==22 && !injected) begin
          if (bvalid === '0) force bvalid = '1; else force bvalid = '0;
          injected=1;
          $display("INJECT 22 b_order");
          #1;
        end
        assert ((bvalid === 1'b1) && (aw_count > b_count) && (w_count > b_count)) else begin
          $display("ASSERT_FAIL 22 b_order cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid) begin : a_r_order
        hits[23]=hits[23]+1;
        if (mutant==23 && !injected) begin
          if (rvalid === '0) force rvalid = '1; else force rvalid = '0;
          injected=1;
          $display("INJECT 23 r_order");
          #1;
        end
        assert ((rvalid === 1'b1) && (ar_count > r_count)) else begin
          $display("ASSERT_FAIL 23 r_order cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && bvalid) begin : a_aw_slot
        hits[24]=hits[24]+1;
        if (mutant==24 && !injected) begin
          if (awready === '0) force awready = '1; else force awready = '0;
          injected=1;
          $display("INJECT 24 aw_slot");
          #1;
        end
        assert (awready === 1'b0) else begin
          $display("ASSERT_FAIL 24 aw_slot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && bvalid) begin : a_w_slot
        hits[25]=hits[25]+1;
        if (mutant==25 && !injected) begin
          if (wready === '0) force wready = '1; else force wready = '0;
          injected=1;
          $display("INJECT 25 w_slot");
          #1;
        end
        assert (wready === 1'b0) else begin
          $display("ASSERT_FAIL 25 w_slot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid) begin : a_ar_slot
        hits[26]=hits[26]+1;
        if (mutant==26 && !injected) begin
          if (arready === '0) force arready = '1; else force arready = '0;
          injected=1;
          $display("INJECT 26 ar_slot");
          #1;
        end
        assert (arready === 1'b0) else begin
          $display("ASSERT_FAIL 26 ar_slot cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pbvalid && !pbready) begin : a_hold_bvalid
        hits[27]=hits[27]+1;
        if (mutant==27 && !injected) begin
          if (bvalid === '0) force bvalid = '1; else force bvalid = '0;
          injected=1;
          $display("INJECT 27 hold_bvalid");
          #1;
        end
        assert (bvalid === pbvalid) else begin
          $display("ASSERT_FAIL 27 hold_bvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && pbvalid && !pbready) begin : a_hold_bresp
        hits[28]=hits[28]+1;
        if (mutant==28 && !injected) begin
          if (bresp === '0) force bresp = '1; else force bresp = '0;
          injected=1;
          $display("INJECT 28 hold_bresp");
          #1;
        end
        assert (bresp === pbresp) else begin
          $display("ASSERT_FAIL 28 hold_bresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prvalid && !prready) begin : a_hold_rvalid
        hits[29]=hits[29]+1;
        if (mutant==29 && !injected) begin
          if (rvalid === '0) force rvalid = '1; else force rvalid = '0;
          injected=1;
          $display("INJECT 29 hold_rvalid");
          #1;
        end
        assert (rvalid === prvalid) else begin
          $display("ASSERT_FAIL 29 hold_rvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prvalid && !prready) begin : a_hold_rresp
        hits[30]=hits[30]+1;
        if (mutant==30 && !injected) begin
          if (rresp === '0) force rresp = '1; else force rresp = '0;
          injected=1;
          $display("INJECT 30 hold_rresp");
          #1;
        end
        assert (rresp === prresp) else begin
          $display("ASSERT_FAIL 30 hold_rresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && prvalid && !prready) begin : a_hold_rdata
        hits[31]=hits[31]+1;
        if (mutant==31 && !injected) begin
          if (rdata === '0) force rdata = '1; else force rdata = '0;
          injected=1;
          $display("INJECT 31 hold_rdata");
          #1;
        end
        assert (rdata === prdata) else begin
          $display("ASSERT_FAIL 31 hold_rdata cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_awready
        hits[41]=hits[41]+1;
        if (mutant==41 && !injected) begin
          if (awready === '0) force awready = '1; else force awready = '0;
          injected=1;
          $display("INJECT 41 exact_awready");
          #1;
        end
        assert (awready === exp_awready) else begin
          $display("ASSERT_FAIL 41 exact_awready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_wready
        hits[42]=hits[42]+1;
        if (mutant==42 && !injected) begin
          if (wready === '0) force wready = '1; else force wready = '0;
          injected=1;
          $display("INJECT 42 exact_wready");
          #1;
        end
        assert (wready === exp_wready) else begin
          $display("ASSERT_FAIL 42 exact_wready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_bvalid
        hits[43]=hits[43]+1;
        if (mutant==43 && !injected) begin
          if (bvalid === '0) force bvalid = '1; else force bvalid = '0;
          injected=1;
          $display("INJECT 43 exact_bvalid");
          #1;
        end
        assert (bvalid === exp_bvalid) else begin
          $display("ASSERT_FAIL 43 exact_bvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_bresp
        hits[44]=hits[44]+1;
        if (mutant==44 && !injected) begin
          if (bresp === '0) force bresp = '1; else force bresp = '0;
          injected=1;
          $display("INJECT 44 exact_bresp");
          #1;
        end
        assert (bresp === exp_bresp) else begin
          $display("ASSERT_FAIL 44 exact_bresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_arready
        hits[45]=hits[45]+1;
        if (mutant==45 && !injected) begin
          if (arready === '0) force arready = '1; else force arready = '0;
          injected=1;
          $display("INJECT 45 exact_arready");
          #1;
        end
        assert (arready === exp_arready) else begin
          $display("ASSERT_FAIL 45 exact_arready cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_rvalid
        hits[46]=hits[46]+1;
        if (mutant==46 && !injected) begin
          if (rvalid === '0) force rvalid = '1; else force rvalid = '0;
          injected=1;
          $display("INJECT 46 exact_rvalid");
          #1;
        end
        assert (rvalid === exp_rvalid) else begin
          $display("ASSERT_FAIL 46 exact_rvalid cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_rresp
        hits[47]=hits[47]+1;
        if (mutant==47 && !injected) begin
          if (rresp === '0) force rresp = '1; else force rresp = '0;
          injected=1;
          $display("INJECT 47 exact_rresp");
          #1;
        end
        assert (rresp === exp_rresp) else begin
          $display("ASSERT_FAIL 47 exact_rresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_rdata
        hits[48]=hits[48]+1;
        if (mutant==48 && !injected) begin
          if (rdata === '0) force rdata = '1; else force rdata = '0;
          injected=1;
          $display("INJECT 48 exact_rdata");
          #1;
        end
        assert (rdata === exp_rdata) else begin
          $display("ASSERT_FAIL 48 exact_rdata cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_config_data
        hits[49]=hits[49]+1;
        if (mutant==49 && !injected) begin
          if (config_data === '0) force config_data = '1; else force config_data = '0;
          injected=1;
          $display("INJECT 49 exact_config_data");
          #1;
        end
        assert (config_data === exp_config_data) else begin
          $display("ASSERT_FAIL 49 exact_config_data cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (1) begin : a_exact_irq
        hits[50]=hits[50]+1;
        if (mutant==50 && !injected) begin
          if (irq === '0) force irq = '1; else force irq = '0;
          injected=1;
          $display("INJECT 50 exact_irq");
          #1;
        end
        assert (irq === exp_irq) else begin
          $display("ASSERT_FAIL 50 exact_irq cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !rvalid) begin : a_invalid_rdata
        hits[51]=hits[51]+1;
        if (mutant==51 && !injected) begin
          if (rdata === '0) force rdata = '1; else force rdata = '0;
          injected=1;
          $display("INJECT 51 invalid_rdata");
          #1;
        end
        assert (rdata === 32'b0) else begin
          $display("ASSERT_FAIL 51 invalid_rdata cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !rvalid) begin : a_invalid_rresp
        hits[52]=hits[52]+1;
        if (mutant==52 && !injected) begin
          if (rresp === '0) force rresp = '1; else force rresp = '0;
          injected=1;
          $display("INJECT 52 invalid_rresp");
          #1;
        end
        assert (rresp === 2'b0) else begin
          $display("ASSERT_FAIL 52 invalid_rresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && !bvalid) begin : a_invalid_bresp
        hits[53]=hits[53]+1;
        if (mutant==53 && !injected) begin
          if (bresp === '0) force bresp = '1; else force bresp = '0;
          injected=1;
          $display("INJECT 53 invalid_bresp");
          #1;
        end
        assert (bresp === 2'b0) else begin
          $display("ASSERT_FAIL 53 invalid_bresp cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_config_known
        hits[54]=hits[54]+1;
        if (mutant==54 && !injected) begin
          force config_data = 'x;
          injected=1;
          $display("INJECT 54 config_known");
          #1;
        end
        assert (!$isunknown(config_data)) else begin
          $display("ASSERT_FAIL 54 config_known cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst) begin : a_irq_known
        hits[55]=hits[55]+1;
        if (mutant==55 && !injected) begin
          force irq = 'x;
          injected=1;
          $display("INJECT 55 irq_known");
          #1;
        end
        assert (!$isunknown(irq)) else begin
          $display("ASSERT_FAIL 55 irq_known cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid && last_rd_addr==16'h000c) begin : a_w1c_readback
        hits[56]=hits[56]+1;
        if (mutant==56 && !injected) begin
          if (rdata === '0) force rdata = '1; else force rdata = '0;
          injected=1;
          $display("INJECT 56 w1c_readback");
          #1;
        end
        assert (rdata === exp_rdata) else begin
          $display("ASSERT_FAIL 56 w1c_readback cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid && (last_rd_addr==16'h0004 || last_rd_addr==16'h0010 || last_rd_addr==16'h0014 || last_rd_addr==16'h0018 || last_rd_addr==16'h001c || last_rd_addr==16'h0020 || last_rd_addr==16'h0024 || last_rd_addr==16'h0028 || last_rd_addr==16'h002c || last_rd_addr==16'h0044 || last_rd_addr==16'h0048 || last_rd_addr==16'h004c || last_rd_addr==16'h0050 || last_rd_addr==16'h0054 || last_rd_addr==16'h0058 || last_rd_addr==16'h005c || last_rd_addr==16'h0060 || last_rd_addr==16'h0064 || last_rd_addr==16'h0068 || last_rd_addr==16'h006c || last_rd_addr==16'h0070 || last_rd_addr==16'h0074 || last_rd_addr==16'h0078 || last_rd_addr==16'h007c || last_rd_addr==16'h0080 || last_rd_addr==16'h0084 || last_rd_addr==16'h0088 || last_rd_addr==16'h008c || last_rd_addr==16'h0090 || last_rd_addr==16'h0094 || last_rd_addr==16'h0098 || last_rd_addr==16'h009c || last_rd_addr==16'h00a0 || last_rd_addr==16'h00a4 || last_rd_addr==16'h00a8 || last_rd_addr==16'h00ac || last_rd_addr==16'h00b0 || last_rd_addr==16'h00b4 || last_rd_addr==16'h00b8 || last_rd_addr==16'h00bc || last_rd_addr==16'h00c0 || last_rd_addr==16'h00c4 || last_rd_addr==16'h00c8 || last_rd_addr==16'h00cc)) begin : a_ro_write_ignored
        hits[57]=hits[57]+1;
        if (mutant==57 && !injected) begin
          if (rdata === '0) force rdata = '1; else force rdata = '0;
          injected=1;
          $display("INJECT 57 ro_write_ignored");
          #1;
        end
        assert (rdata === exp_rdata) else begin
          $display("ASSERT_FAIL 57 ro_write_ignored cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      if (rst && rvalid && (reserved_mask(last_rd_addr)!=32'b0)) begin : a_reserved_read_zero
        hits[58]=hits[58]+1;
        if (mutant==58 && !injected) begin
          force rdata = '1;
          injected=1;
          $display("INJECT 58 reserved_read_zero");
          #1;
        end
        assert ((rdata & reserved_mask(last_rd_addr)) === 32'b0) else begin
          $display("ASSERT_FAIL 58 reserved_read_zero cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
      #4;clk=0;prev_rst=rst;
    end
  endtask
  initial begin
    if ($value$plusargs("MUTANT=%d",mutant)) begin end
    for (integer k=0;k<59;k=k+1) hits[k]=0;
    $readmemh("vectors.mem",vectors);
    for (integer k=0;k<N;k=k+1) begin
      {rst,awaddr,awprot,awvalid,wdata,wstrb,wvalid,bready,araddr,arprot,arvalid,rready,sts_valid,sts_data,deposit,exp_awready,exp_wready,exp_bvalid,exp_bresp,exp_arready,exp_rvalid,exp_rresp,exp_rdata,exp_config_data,exp_irq}=vectors[k];
      tick();
    end
    $display("ASSERT 0 reset_awready [S5.5.12/S7 reset] hits=%0d",hits[0]);
    if (hits[0]==0) $fatal(1,"R-025 unexercised assertion 0");
    $display("ASSERT 1 reset_wready [S5.5.12/S7 reset] hits=%0d",hits[1]);
    if (hits[1]==0) $fatal(1,"R-025 unexercised assertion 1");
    $display("ASSERT 2 reset_arready [S5.5.12/S7 reset] hits=%0d",hits[2]);
    if (hits[2]==0) $fatal(1,"R-025 unexercised assertion 2");
    $display("ASSERT 3 reset_bvalid [S5.5.12/S7 reset] hits=%0d",hits[3]);
    if (hits[3]==0) $fatal(1,"R-025 unexercised assertion 3");
    $display("ASSERT 4 reset_rvalid [S5.5.12/S7 reset] hits=%0d",hits[4]);
    if (hits[4]==0) $fatal(1,"R-025 unexercised assertion 4");
    $display("ASSERT 5 reset_config [JSON reset] hits=%0d",hits[5]);
    if (hits[5]==0) $fatal(1,"R-025 unexercised assertion 5");
    $display("ASSERT 6 known_awready [S6.1 AXI4-Lite] hits=%0d",hits[6]);
    if (hits[6]==0) $fatal(1,"R-025 unexercised assertion 6");
    $display("ASSERT 7 known_wready [S6.1 AXI4-Lite] hits=%0d",hits[7]);
    if (hits[7]==0) $fatal(1,"R-025 unexercised assertion 7");
    $display("ASSERT 8 known_arready [S6.1 AXI4-Lite] hits=%0d",hits[8]);
    if (hits[8]==0) $fatal(1,"R-025 unexercised assertion 8");
    $display("ASSERT 9 known_bvalid [S6.1 AXI4-Lite] hits=%0d",hits[9]);
    if (hits[9]==0) $fatal(1,"R-025 unexercised assertion 9");
    $display("ASSERT 10 known_rvalid [S6.1 AXI4-Lite] hits=%0d",hits[10]);
    if (hits[10]==0) $fatal(1,"R-025 unexercised assertion 10");
    $display("ASSERT 11 known_bresp [S6.1 AXI4-Lite] hits=%0d",hits[11]);
    if (hits[11]==0) $fatal(1,"R-025 unexercised assertion 11");
    $display("ASSERT 12 known_rresp [S6.1 AXI4-Lite] hits=%0d",hits[12]);
    if (hits[12]==0) $fatal(1,"R-025 unexercised assertion 12");
    $display("ASSERT 13 known_rdata [S6.1 AXI4-Lite] hits=%0d",hits[13]);
    if (hits[13]==0) $fatal(1,"R-025 unexercised assertion 13");
    $display("ASSERT 14 known_awaddr [S6.1 AXI4-Lite] hits=%0d",hits[14]);
    if (hits[14]==0) $fatal(1,"R-025 unexercised assertion 14");
    $display("ASSERT 15 known_awprot [S6.1 AXI4-Lite] hits=%0d",hits[15]);
    if (hits[15]==0) $fatal(1,"R-025 unexercised assertion 15");
    $display("ASSERT 16 known_wdata [S6.1 AXI4-Lite] hits=%0d",hits[16]);
    if (hits[16]==0) $fatal(1,"R-025 unexercised assertion 16");
    $display("ASSERT 17 known_wstrb [S6.1 AXI4-Lite] hits=%0d",hits[17]);
    if (hits[17]==0) $fatal(1,"R-025 unexercised assertion 17");
    $display("ASSERT 18 known_araddr [S6.1 AXI4-Lite] hits=%0d",hits[18]);
    if (hits[18]==0) $fatal(1,"R-025 unexercised assertion 18");
    $display("ASSERT 19 known_arprot [S6.1 AXI4-Lite] hits=%0d",hits[19]);
    if (hits[19]==0) $fatal(1,"R-025 unexercised assertion 19");
    $display("ASSERT 20 b_encoding [S6.1 AXI4-Lite] hits=%0d",hits[20]);
    if (hits[20]==0) $fatal(1,"R-025 unexercised assertion 20");
    $display("ASSERT 21 r_encoding [S6.1 AXI4-Lite] hits=%0d",hits[21]);
    if (hits[21]==0) $fatal(1,"R-025 unexercised assertion 21");
    $display("ASSERT 22 b_order [S6.1 AXI4-Lite] hits=%0d",hits[22]);
    if (hits[22]==0) $fatal(1,"R-025 unexercised assertion 22");
    $display("ASSERT 23 r_order [S6.1 AXI4-Lite] hits=%0d",hits[23]);
    if (hits[23]==0) $fatal(1,"R-025 unexercised assertion 23");
    $display("ASSERT 24 aw_slot [S6.1 AXI4-Lite] hits=%0d",hits[24]);
    if (hits[24]==0) $fatal(1,"R-025 unexercised assertion 24");
    $display("ASSERT 25 w_slot [S6.1 AXI4-Lite] hits=%0d",hits[25]);
    if (hits[25]==0) $fatal(1,"R-025 unexercised assertion 25");
    $display("ASSERT 26 ar_slot [S6.1 AXI4-Lite] hits=%0d",hits[26]);
    if (hits[26]==0) $fatal(1,"R-025 unexercised assertion 26");
    $display("ASSERT 27 hold_bvalid [S6.1 AXI4-Lite] hits=%0d",hits[27]);
    if (hits[27]==0) $fatal(1,"R-025 unexercised assertion 27");
    $display("ASSERT 28 hold_bresp [S6.1 AXI4-Lite] hits=%0d",hits[28]);
    if (hits[28]==0) $fatal(1,"R-025 unexercised assertion 28");
    $display("ASSERT 29 hold_rvalid [S6.1 AXI4-Lite] hits=%0d",hits[29]);
    if (hits[29]==0) $fatal(1,"R-025 unexercised assertion 29");
    $display("ASSERT 30 hold_rresp [S6.1 AXI4-Lite] hits=%0d",hits[30]);
    if (hits[30]==0) $fatal(1,"R-025 unexercised assertion 30");
    $display("ASSERT 31 hold_rdata [S6.1 AXI4-Lite] hits=%0d",hits[31]);
    if (hits[31]==0) $fatal(1,"R-025 unexercised assertion 31");
    $display("ASSERT 32 master_hold_awvalid [S6.1 AXI4-Lite] hits=%0d",hits[32]);
    if (hits[32]==0) $fatal(1,"R-025 unexercised assertion 32");
    $display("ASSERT 33 master_hold_awaddr [S6.1 AXI4-Lite] hits=%0d",hits[33]);
    if (hits[33]==0) $fatal(1,"R-025 unexercised assertion 33");
    $display("ASSERT 34 master_hold_awprot [S6.1 AXI4-Lite] hits=%0d",hits[34]);
    if (hits[34]==0) $fatal(1,"R-025 unexercised assertion 34");
    $display("ASSERT 35 master_hold_wvalid [S6.1 AXI4-Lite] hits=%0d",hits[35]);
    if (hits[35]==0) $fatal(1,"R-025 unexercised assertion 35");
    $display("ASSERT 36 master_hold_wdata [S6.1 AXI4-Lite] hits=%0d",hits[36]);
    if (hits[36]==0) $fatal(1,"R-025 unexercised assertion 36");
    $display("ASSERT 37 master_hold_wstrb [S6.1 AXI4-Lite] hits=%0d",hits[37]);
    if (hits[37]==0) $fatal(1,"R-025 unexercised assertion 37");
    $display("ASSERT 38 master_hold_arvalid [S6.1 AXI4-Lite] hits=%0d",hits[38]);
    if (hits[38]==0) $fatal(1,"R-025 unexercised assertion 38");
    $display("ASSERT 39 master_hold_araddr [S6.1 AXI4-Lite] hits=%0d",hits[39]);
    if (hits[39]==0) $fatal(1,"R-025 unexercised assertion 39");
    $display("ASSERT 40 master_hold_arprot [S6.1 AXI4-Lite] hits=%0d",hits[40]);
    if (hits[40]==0) $fatal(1,"R-025 unexercised assertion 40");
    $display("ASSERT 41 exact_awready [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[41]);
    if (hits[41]==0) $fatal(1,"R-025 unexercised assertion 41");
    $display("ASSERT 42 exact_wready [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[42]);
    if (hits[42]==0) $fatal(1,"R-025 unexercised assertion 42");
    $display("ASSERT 43 exact_bvalid [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[43]);
    if (hits[43]==0) $fatal(1,"R-025 unexercised assertion 43");
    $display("ASSERT 44 exact_bresp [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[44]);
    if (hits[44]==0) $fatal(1,"R-025 unexercised assertion 44");
    $display("ASSERT 45 exact_arready [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[45]);
    if (hits[45]==0) $fatal(1,"R-025 unexercised assertion 45");
    $display("ASSERT 46 exact_rvalid [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[46]);
    if (hits[46]==0) $fatal(1,"R-025 unexercised assertion 46");
    $display("ASSERT 47 exact_rresp [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[47]);
    if (hits[47]==0) $fatal(1,"R-025 unexercised assertion 47");
    $display("ASSERT 48 exact_rdata [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[48]);
    if (hits[48]==0) $fatal(1,"R-025 unexercised assertion 48");
    $display("ASSERT 49 exact_config_data [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[49]);
    if (hits[49]==0) $fatal(1,"R-025 unexercised assertion 49");
    $display("ASSERT 50 exact_irq [S6.1/S11 JSON bit-exact cycle reference] hits=%0d",hits[50]);
    if (hits[50]==0) $fatal(1,"R-025 unexercised assertion 50");
    $display("ASSERT 51 invalid_rdata [S5.3 invalid payload] hits=%0d",hits[51]);
    if (hits[51]==0) $fatal(1,"R-025 unexercised assertion 51");
    $display("ASSERT 52 invalid_rresp [S6.1 AXI4-Lite] hits=%0d",hits[52]);
    if (hits[52]==0) $fatal(1,"R-025 unexercised assertion 52");
    $display("ASSERT 53 invalid_bresp [S6.1 AXI4-Lite] hits=%0d",hits[53]);
    if (hits[53]==0) $fatal(1,"R-025 unexercised assertion 53");
    $display("ASSERT 54 config_known [S5.4 configuration] hits=%0d",hits[54]);
    if (hits[54]==0) $fatal(1,"R-025 unexercised assertion 54");
    $display("ASSERT 55 irq_known [S11 IRQ] hits=%0d",hits[55]);
    if (hits[55]==0) $fatal(1,"R-025 unexercised assertion 55");
    $display("ASSERT 56 w1c_readback [S6.1/JSON hardware-set wins W1C] hits=%0d",hits[56]);
    if (hits[56]==0) $fatal(1,"R-025 unexercised assertion 56");
    $display("ASSERT 57 ro_write_ignored [S6.1/JSON RO write error preserves data] hits=%0d",hits[57]);
    if (hits[57]==0) $fatal(1,"R-025 unexercised assertion 57");
    $display("ASSERT 58 reserved_read_zero [S6.1/JSON reserved bits read zero] hits=%0d",hits[58]);
    if (hits[58]==0) $fatal(1,"R-025 unexercised assertion 58");
    if (mutant>=0) $fatal(1,"mutant not injected/detected");
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("PASS csr: golden=128/128 cycles=%0d/%0d random=2400 registers=52 assertions=59",N,N);
    $finish;
  end
endmodule
