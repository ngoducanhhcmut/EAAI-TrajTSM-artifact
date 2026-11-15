// Project TSM-X; author TSMX project; version0.1.
// Spec5.5.5 PARA_MAX_CELLS admission and golden zero-speed limit1 horizon.
`timescale 1ns/1ps
module tb_mrmgen_param;
  reg clk=0,rst=0,req_valid=0;
  reg [175:0] req_data=0;
  wire ready,valid,row_valid;
  wire [400:0] row;
  wire [49:0] data;
  integer count=0,cycles=0;
  m_tsmx_mrmgen #(.PARA_MAX_CELLS(32'd1)) dut (
    .i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),.i_req_data(req_data),
    .i_row_ready(1'b1),.i_rsp_ready(1'b0),.o_req_ready(ready),
    .o_rsp_valid(valid),.o_rsp_data(data),.o_row_valid(row_valid),.o_row_data(row)
  );
  task tick;
    begin
      if(rst && row_valid) begin
        assert(row===401'd0) else $fatal(1,"golden standstill row mismatch");
        count=count+1;
      end
      #4;clk=1;#1;cycles=cycles+1;#5;clk=0;#1;
    end
  endtask
  task run_case(input reg [7:0] lim,input reg [49:0] expected,input integer rows_expected);
    begin
      rst=0;req_valid=0;count=0;tick;rst=1;tick;
      assert(ready===1) else $fatal(1,"release ready");
      req_data={168'd0,lim};req_valid=1;tick;req_valid=0;
      while(!valid && cycles<1000) tick;
      assert(valid && data===expected && count==rows_expected)
        else $fatal(1,"parameter admission mismatch count=%d data=%h",count,data);
    end
  endtask
  initial begin
    run_case(8'd1,{1'b0,8'd16,1'b1,32'd100000,8'd1},1);
    run_case(8'd2,{1'b0,8'd14,1'b0,32'd0,8'd0},0);
    $display("PASS mrmgen parameter: PARA_MAX_CELLS=1 legal=1 rejected=1");$finish;
  end
endmodule
