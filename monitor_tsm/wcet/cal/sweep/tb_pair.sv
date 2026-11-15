`timescale 1ns/1ps
module tb_pair;
reg clk=0,rst=0,req=0;
reg [8199:0] world=0;
wire ready,valid;
wire [15:0] mask;
integer cyc=0,beginc=0,basec=0;
m_tsmx_sweep #(.PARA_G(2),.PARA_P(2)) dut(
.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req),
.i_pose({64'd0,32'd10000000,32'd2000000}),.i_epoch(32'd0),.i_world(world),
.i_lane({64'hffffffffffe488c0,64'd1800000,64'd0,64'd950000,64'd50000,64'd500000}),
.i_kind(2'd0),.i_bridge(704'd0),.o_req_ready(ready),.o_rsp_valid(valid),.o_rsp_data(mask));
always #5 clk=~clk;
always @(posedge clk) begin
cyc=cyc+1;
if(rst && ready && req) beginc=cyc;
if(rst && dut.reg_base==2) begin
$display("CAL_PAIR candidates=0,1 rows_max=93 objects=32 cycles=%0d",cyc-beginc);
$finish;
end
end
initial begin
rst=1;#1;rst=0;
world[8199:8192]=32;
for(integer k=0;k<32;k=k+1)
world[8191-256*k -:256]={64'd1000000000,32'd0,32'd0,64'd4800000,32'd0,32'd0};
repeat(4) @(negedge clk);rst=1;
while(!ready) @(negedge clk);
req=1;@(negedge clk);req=0;
end
initial begin #20000000; $fatal(1,"pair timeout"); end
endmodule
