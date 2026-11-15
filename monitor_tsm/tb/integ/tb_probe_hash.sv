`timescale 1ns/1ps
module tb_probe_hash;
logic clk=0,rst=0,qv=0,qr,sv;logic [7:0] op;logic [10:0] len;
logic [8415:0] data;logic [288:0] result,expected;
logic [8723:0] jobs[0:399];integer n,c;
always #5 clk=~clk;
m_tsmx_hash dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_op(op),
.i_len(len),.i_data(data),.o_req_ready(qr),.o_rsp_valid(sv),.o_rsp_data(result));
initial begin
$readmemh("helper_hash.mem",jobs);repeat(4)@(negedge clk);rst=1;
for(n=0;n<400;n=n+1)begin
{op,len,data,expected}=jobs[n];while(!qr)@(negedge clk);
qv=1;@(negedge clk);qv=0;c=0;
while(!sv)begin @(negedge clk);c=c+1;if(c>5000)$fatal(1,"hash hang %0d",n);end
if(result!==expected)$fatal(1,"hash mismatch job=%0d op=%0d actual=%h expected=%h",n,op,result,expected);
@(negedge clk);
end
$display("PASS helper hash jobs=400");$finish;
end
endmodule
