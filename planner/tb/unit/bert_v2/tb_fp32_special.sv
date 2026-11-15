//==============================================================================
// tb_fp32_special — so TUNG BIT fp32_exp_neg_p / fp32_nr_seq(rsqrt, recip) voi fp.py
// +NEG: dao 1 bit ket qua mong doi o vector 500 cua moi loai -> phai bao LOI.
//==============================================================================
`timescale 1ns / 1ps
module tb_fp32_special;
  localparam string V = "tb/unit/bert_v2/vec/";
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  logic [31:0] x, r_exp;
  fp32_exp_neg_p u_exp (.clk, .x, .r(r_exp));

  logic st_rs = 0, st_rc = 0, dn_rs, dn_rc;
  logic [31:0] v_rs, v_rc, r_rs, r_rc;
  fp32_nr_seq #(.MODE(1'b0)) u_rs (.clk, .rst_n, .start(st_rs), .v(v_rs), .done(dn_rs), .r(r_rs));
  fp32_nr_seq #(.MODE(1'b1)) u_rc (.clk, .rst_n, .start(st_rc), .v(v_rc), .done(dn_rc), .r(r_rc));

  logic [31:0] va [400000], vr [400000];
  bit neg;
  int tot = 0;

  function automatic int load(input string fn);
    int fd, n;
    n = 0;
    fd = $fopen({V, fn}, "r");
    if (fd == 0) begin $display("KHONG MO DUOC %s", fn); $finish; end
    while ($fscanf(fd, "%h %h", va[n], vr[n]) == 2) n++;
    $fclose(fd);
    if (neg && n > 500) vr[500] ^= 32'h1;
    return n;
  endfunction

  initial begin
    int n, e;
    neg = $test$plusargs("NEG");
    repeat (3) @(posedge clk); rst_n = 1;
    // ── exp: duong ong LAT=6 ──
    n = load("exp.hex"); e = 0;
    for (int k = 0; k < n + 6; k++) begin
      if (k < n) x <= va[k];
      @(posedge clk); #0.1;
      if (k >= 5 && (k - 5) < n && r_exp !== vr[k - 5]) begin
        if (e < 8) $display("  exp #%0d x=%08h got=%08h mong=%08h", k - 5, va[k - 5], r_exp, vr[k - 5]);
        e++;
      end
    end
    $display("exp    : %0d vector, %0d LOI", n, e); tot += e;
    // ── rsqrt / recip: tuan tu ──
    for (int md = 0; md < 2; md++) begin
      n = load(md == 0 ? "rsqrt.hex" : "recip.hex"); e = 0;
      for (int k = 0; k < n; k++) begin
        logic [31:0] got;
        int to;
        @(posedge clk);
        if (md == 0) begin v_rs <= va[k]; st_rs <= 1; end else begin v_rc <= va[k]; st_rc <= 1; end
        @(posedge clk); st_rs <= 0; st_rc <= 0;
        to = 0;
        while (!(md == 0 ? dn_rs : dn_rc) && to < 200) begin @(posedge clk); to++; end
        #0.1;
        got = (md == 0) ? r_rs : r_rc;
        if (to >= 200 || got !== vr[k]) begin
          if (e < 8) $display("  %s #%0d v=%08h got=%08h mong=%08h to=%0d", md ? "recip" : "rsqrt", k, va[k], got, vr[k], to);
          e++;
        end
      end
      $display("%s  : %0d vector, %0d LOI", md ? "recip" : "rsqrt", n, e); tot += e;
    end
    if (tot == 0) $display("==== TB_FP32_SPECIAL: DAT (khop tung bit) ====");
    else          $display("==== TB_FP32_SPECIAL: %0d LOI ====", tot);
    $finish;
  end
endmodule
