`timescale 1ns/1ps
module tb_probe_splice;
logic clk=0,rst=0,qv=0,qr,sv,sd;
logic [815:0] qd;
always #5 clk=~clk;
m_tsmx_splice dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_req_data(qd),
 .o_req_ready(qr),.o_rsp_valid(sv),.o_rsp_data(sd),.i_rsp_ready(1'b1));
initial begin
 qd=816'h00000000000000000266d864007a65d9ffdcb15d0000000002e2c349008023cb0000000000000000000000000266d864007a65d9ffdcb15d0000000002e2c349008023cb00000000000186a0000000000272e8950076ddfbffdcb15d0f000013880200000001;
 #40;rst=1;#30;qv=1;#10;qv=0;qd=0;
 wait(sv);if(sd!==1)$fatal(1,"splice mismatch");$display("PASS splice probe");$finish;
end
integer c=0;
always @(posedge clk)begin c=c+1;
 if(c%10==0)$display("PROBE cycle=%0d state=%0d corner=%0d",c,dut.reg_fsm_ctrl_current_state,dut.reg_corner);
 if(c>1000)$fatal(1,"splice hang");
end
endmodule
