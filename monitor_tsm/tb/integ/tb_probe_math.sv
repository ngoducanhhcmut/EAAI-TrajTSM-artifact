`timescale 1ns/1ps
module tb_probe_math;
logic clk=0,rst=0,qv=0,qr,sv,ok;
logic [8199:0] world_out;
logic [703:0] bridge;
logic [95:0] pose;
always #5 clk=~clk;
m_tsmx_math dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_op(3'd0),
 .i_ego(256'h00000000000000000266d864007a65d9ffdcb15d0000000002e2c349008023cb),.i_world(8200'd0),.i_delay(32'd0),.i_plan(560'd0),.i_rear(32'h40000000),
 .o_req_ready(qr),.o_rsp_valid(sv),.o_ok(ok),.o_world(world_out),.o_bridge(bridge),.o_pose(pose));
initial begin
 #40;rst=1;#30;qv=1;#10;qv=0;
 wait(sv);if(ok!==1'b1)$fatal(1,"math mismatch");$display("PASS math probe");$finish;
end
integer c=0;
always @(posedge clk)begin c=c+1;
 $display("MATH cycle=%0d state=%0d arstate=%0d",c,dut.reg_fsm_ctrl_current_state,dut.u_ar.reg_fsm_ctrl_current_state);
 if(c>1000)$fatal(1,"math hang");
end
endmodule
