`timescale 1ns/1ps
// TSM-X / TSMX project / version 0.2 (Claude 30/10): G1c state-unit unit test.
// Oracle: golden disp_lb/disp_ub/advance_lb and B3 inflation (gen_vectors.py).
module tb_m_tsmx_geom_su;
  reg clk=0, rst=0, start=0, mode=0, up=0;
  reg [63:0] x=0; reg [31:0] v=0, a=0, w=0, j=0;
  wire busy, done, fault; wire [63:0] xo, disp, lin, infl; wire [31:0] vo;
  `include "vectors_meta.svh"
  reg [483:0] vec [0:N-1];
  reg [483:0] cur;
  integer i, cyc=0, maxlat=0, lat, errors=0, nfault=0, asserts=0;
  m_tsmx_geom_su dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_start(start),.i_mode(mode),.i_up(up),
    .i_x(x),.i_v(v),.i_a(a),.i_w(w),.i_j(j),.o_busy(busy),.o_done(done),.o_fault(fault),
    .o_x(xo),.o_v(vo),.o_disp(disp),.o_lin(lin),.o_infl(infl));
  always #5 clk=~clk;
  always @(posedge clk) cyc<=cyc+1;
  // Protocol assertions: no done while busy, busy never with done.
  always @(posedge clk) if (rst) begin
    asserts=asserts+1;
    if (busy && done) begin $display("ASSERT_FAIL busy&&done"); $fatal(1); end
  end
  initial begin
    rst=1; #1; rst=0; #1; $readmemh("vectors.mem",vec);
    repeat(3) @(posedge clk); rst=1; @(posedge clk);
    for (i=0;i<N;i=i+1) begin
      cur=vec[i];
      {mode,up,x,v,a,w,j}=cur[482:289];
      @(negedge clk); start=1; @(negedge clk); start=0; lat=1;
      while (!done) begin @(negedge clk); lat=lat+1; if (lat>2000) $fatal(1,"timeout %0d",i); end
      $display("CAL_SU mode=%0d latency=%0d",mode,lat);
      if (lat>maxlat) maxlat=lat;
      if (fault!==cur[288] || (!cur[288] && (
          (!mode && (xo!==cur[287:224] || vo!==cur[223:192] || disp!==cur[191:128] || lin!==cur[127:64]))
          || (mode && infl!==cur[63:0])))) begin
        errors=errors+1;
        if (errors<6) $display("MISMATCH %0d mode=%0d up=%0d x=%0d v=%0d a=%0d w=%0d f=%0d/%0d xo=%0d/%0d vo=%0d/%0d disp=%0d/%0d lin=%0d/%0d infl=%0d/%0d",
          i,mode,up,$signed(x),v,$signed(a),w,fault,cur[288],$signed(xo),$signed(cur[287:224]),vo,cur[223:192],disp,cur[191:128],lin,cur[127:64],infl,cur[63:0]);
      end
      if (cur[288]) nfault=nfault+1;
    end
    if (errors!=0) $fatal(1,"FAIL geom_su errors=%0d",errors);
    $display("PASS geom_su: golden=%0d/%0d faults=%0d max_latency=%0d assertions=%0d",N-errors,N,nfault,maxlat,asserts);
    $finish;
  end

  integer cal_cycle=0, cal_begin=0;
  reg cal_pending=0;
  always @(posedge clk) begin
    cal_cycle=cal_cycle+1;
    if (!rst) cal_pending=0;
    else begin
      if (start) begin cal_begin=cal_cycle; cal_pending=1; end
      if (done && cal_pending) begin
        $display("CAL job_cycles=%0d",cal_cycle-cal_begin); cal_pending=0;
      end
    end
  end

endmodule
