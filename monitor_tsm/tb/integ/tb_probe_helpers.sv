`timescale 1ns/1ps
module tb_probe_helpers;
logic clk=0,rst=0,qv=0,qr,sv,ok;
logic [2:0] op; logic [255:0] ego;logic [8199:0] world,ow,ew;
logic [31:0] delay,rear;logic [559:0] plan;logic eok;
logic [703:0] bridge,eb;logic [95:0] pose,ep;
logic [18083:0] jobs[0:399];integer n,c;
always #5 clk=~clk;
m_tsmx_math dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_op(op),
.i_ego(ego),.i_world(world),.i_delay(delay),.i_plan(plan),.i_rear(rear),
.o_req_ready(qr),.o_rsp_valid(sv),.o_ok(ok),.o_world(ow),.o_bridge(bridge),.o_pose(pose));
initial begin
$readmemh("helper_math.mem",jobs);repeat(4)@(negedge clk);rst=1;
for(n=0;n<400;n=n+1)begin
{op,ego,world,delay,plan,rear,eok,ew,eb,ep}=jobs[n];
while(!qr)@(negedge clk);qv=1;@(negedge clk);qv=0;c=0;
while(!sv)begin @(negedge clk);c=c+1;if(c>100000)$fatal(1,"helper hang %0d",n);end
if(ok!==eok || ((op==1 || op==4) && ow!==ew) || (op==2 && bridge!==eb)
 || (op==3 && pose!==ep))$fatal(1,"helper mismatch job=%0d op=%0d pose=%h expected=%h",n,op,pose,ep);
@(negedge clk);
end
$display("PASS helper math jobs=400");$finish;
end
endmodule
