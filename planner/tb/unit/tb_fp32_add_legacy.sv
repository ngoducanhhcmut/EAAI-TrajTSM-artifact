//==============================================================================
// tb_fp32_add_legacy — chung minh fp32_add_p #(LEGACY_ZERO=1) == fp32_add_f (planning_pkg)
// tung bit, tren vector fadd.hex (562.525 cap, gom +-0, triet tieu, hoa) + 10^6 cap ngau nhien.
//==============================================================================
`timescale 1ns / 1ps
module tb_fp32_add_legacy;
  import planning_pkg::*;
  logic clk = 0; always #2.5 clk = ~clk;
  logic [31:0] a, b, r;
  fp32_add_p #(.LEGACY_ZERO(1'b1)) dut (.clk, .a, .b, .r);
  logic [31:0] va [700000], vb [700000], ve [1700000];
  int n = 0, fd, k, e = 0;
  initial begin
    fd = $fopen("tb/unit/bert_v2/vec/fadd.hex", "r");
    while ($fscanf(fd, "%h %h %h", va[n], vb[n], ve[0]) == 3) n++;
    $fclose(fd);
    for (k = 0; k < 1000000 && n < 700000; k++) begin
      va[n] = $urandom; vb[n] = $urandom;
      if (va[n][30:23] == 0) va[n][22:0] = 0;     // khong denormal
      if (vb[n][30:23] == 0) vb[n][22:0] = 0;
      if (va[n][30:23] == 8'hFF || vb[n][30:23] == 8'hFF) continue;
      n++;
    end
    for (k = 0; k < n + 3; k++) begin
      if (k < n) begin a <= va[k]; b <= vb[k]; end
      @(posedge clk); #0.1;
      if (k >= 2 && (k - 2) < n && r !== fp32_add_f(va[k-2], vb[k-2])) begin
        if (e < 8) $display("  #%0d a=%08h b=%08h p=%08h f=%08h", k-2, va[k-2], vb[k-2], r, fp32_add_f(va[k-2], vb[k-2]));
        e++;
      end
    end
    $display("so sanh %0d cap: %0d khac", n, e);
    if (e == 0) $display("==== TB_FP32_ADD_LEGACY: DAT (fp32_add_p LEGACY == fp32_add_f) ====");
    else        $display("==== TB_FP32_ADD_LEGACY: %0d LOI ====", e);
    $finish;
  end
endmodule
