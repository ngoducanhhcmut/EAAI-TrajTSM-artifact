`timescale 1ns/1ps
// TSM-X geom_su v0.4 width narrowing (Claude 01/11): lock-step equivalence against v0.3.
// Random, boundary-biased stimulus inside and outside the START bounds; every output and the
// cycle of o_done must match.
module tb_eq;
  reg clk=0, rst=0, start=0, mode=0, up=0;
  reg [63:0] x=0; reg [31:0] v=0, a=0, w=0, j=0;
  wire b0,d0,f0,b1,d1,f1; wire [63:0] x0,x1,s0,s1,l0,l1,i0,i1; wire [31:0] v0,v1;
  m_tsmx_geom_su_v03 u_ref(.i_clk_core(clk),.i_rst_n_core(rst),.i_start(start),.i_mode(mode),.i_up(up),
    .i_x(x),.i_v(v),.i_a(a),.i_w(w),.i_j(j),.o_busy(b0),.o_done(d0),.o_fault(f0),
    .o_x(x0),.o_v(v0),.o_disp(s0),.o_lin(l0),.o_infl(i0));
  m_tsmx_geom_su u_dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_start(start),.i_mode(mode),.i_up(up),
    .i_x(x),.i_v(v),.i_a(a),.i_w(w),.i_j(j),.o_busy(b1),.o_done(d1),.o_fault(f1),
    .o_x(x1),.o_v(v1),.o_disp(s1),.o_lin(l1),.o_infl(i1));
  always #5 clk=~clk;
  integer n, errors=0, nfault=0, ndone=0, lat;
  integer N=2000000;
  function automatic [31:0] pick32(input [31:0] lo, input [31:0] hi);
    reg [31:0] r; r=$urandom;
    case (r[2:0])
      0: pick32=lo; 1: pick32=hi; 2: pick32=hi+1; 3: pick32=(r[3] ? hi-1 : lo+1);
      default: pick32=lo+($urandom % (hi-lo+1));
    endcase
  endfunction
  // Compare every cycle: the two units must be cycle-identical.
  always @(negedge clk) if (rst) begin
    if (b0!==b1 || d0!==d1 || f0!==f1 || x0!==x1 || v0!==v1 || s0!==s1 || l0!==l1 || i0!==i1) begin
      errors=errors+1;
      if (errors<6) $display("MISMATCH n=%0d mode=%0d up=%0d x=%h v=%0d a=%0d w=%0d j=%0d | b%0d/%0d d%0d/%0d f%0d/%0d x=%h/%h v=%0d/%0d disp=%0d/%0d lin=%0d/%0d infl=%0d/%0d",
        n,mode,up,x,v,$signed(a),w,j,b0,b1,d0,d1,f0,f1,x0,x1,v0,v1,s0,s1,l0,l1,i0,i1);
    end
  end
  initial begin
    if ($value$plusargs("N=%d",N)) ;
    repeat(3) @(posedge clk); rst=1; @(negedge clk);
    for (n=0;n<N;n=n+1) begin
      mode=($urandom%5)==0; up=$urandom;
      v=pick32(0,20000000); w=pick32(0,100000);
      case ($urandom%4)
        0: a=pick32(0,2000000);
        1: a=-pick32(0,8000000);
        2: a=$urandom;
        default: a=(($urandom%2) ? pick32(0,2000000) : -pick32(0,8000000));
      endcase
      j=($urandom%3==0) ? 32'hffffffff : $urandom;
      case ($urandom%6)
        0: x=64'h8000000000000000; 1: x=64'h7fffffffffffffff-($urandom%3000000);
        2: x=64'h8000000000000000+($urandom%3000000); 3: x={$urandom,$urandom};
        default: x=$signed($urandom);
      endcase
      start=1; @(negedge clk); start=0; lat=1;
      while (!d1) begin @(negedge clk); lat=lat+1; if (lat>200) $fatal(1,"timeout %0d",n); end
      ndone=ndone+1; if (f1) nfault=nfault+1;
      @(negedge clk);
    end
    if (errors!=0) $fatal(1,"FAIL geom_su v0.4 vs v0.3 errors=%0d",errors);
    $display("PASS geom_su v0.4==v0.3 lock-step vectors=%0d faults=%0d",ndone,nfault);
    $finish;
  end
endmodule
