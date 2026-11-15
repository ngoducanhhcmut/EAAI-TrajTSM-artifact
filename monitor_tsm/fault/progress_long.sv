module progress;
initial forever begin
 #1000;
 $display("PROGRESS time=%0t active=%b cycle=%0d state=%h",$time,tb_fault.active,tb_fault.active_cycle,tb_fault.dut.u_tsmx_engine.reg_fsm_ctrl_current_state);
end
endmodule
