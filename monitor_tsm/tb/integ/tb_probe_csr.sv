`timescale 1ns/1ps
module tb_probe_csr;
logic  i_clk_core;
logic  i_rst_n_core;
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
logic  i_sts_valid;
logic [114:0] i_sts_data;
logic [3:0] o_config_data;
m_tsmx_csr dut (.i_clk_core(i_clk_core),.i_rst_n_core(i_rst_n_core),.i_axi_awaddr(i_axi_awaddr),.i_axi_awprot(i_axi_awprot),.i_axi_awvalid(i_axi_awvalid),.i_axi_wdata(i_axi_wdata),.i_axi_wstrb(i_axi_wstrb),.i_axi_wvalid(i_axi_wvalid),.i_axi_bready(i_axi_bready),.i_axi_araddr(i_axi_araddr),.i_axi_arprot(i_axi_arprot),.i_axi_arvalid(i_axi_arvalid),.i_axi_rready(i_axi_rready),.o_axi_awready(o_axi_awready),.o_axi_wready(o_axi_wready),.o_axi_bvalid(o_axi_bvalid),.o_axi_bresp(o_axi_bresp),.o_axi_arready(o_axi_arready),.o_axi_rvalid(o_axi_rvalid),.o_axi_rresp(o_axi_rresp),.o_axi_rdata(o_axi_rdata),.o_int_irq(o_int_irq),.i_sts_valid(i_sts_valid),.i_sts_data(i_sts_data),.o_config_data(o_config_data));
always #5 i_clk_core=~i_clk_core;
initial begin
i_clk_core='0;
i_rst_n_core='0;
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
i_sts_valid='0;
i_sts_data='0;
i_rst_n_core=1; #1; i_rst_n_core=0; #39; i_rst_n_core=1; #20;
i_axi_araddr=16'h30;i_axi_arvalid=1;
#10;i_axi_arvalid=0; #20;
if(o_axi_rvalid!==1 || o_axi_rdata!==32'd16)$fatal(1,"CSR probe");
$display("PASS CSR probe");$finish;
end
always @(posedge i_clk_core)$display("probe time=%0t rst=%b reg=%b nxt=%b ar=%b data=%h",$time,
i_rst_n_core,dut.reg_rvalid,dut.w_rvalid_nxt,o_axi_arready,o_axi_rdata);
endmodule
