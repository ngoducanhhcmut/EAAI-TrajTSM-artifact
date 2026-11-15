//==============================================================================
// tb_fp32_units — so TUNG BIT fp32_add_p / mul_p / i2f_p / f2i_p voi sw/hwspec/fp.py
// Vector: sw/hwspec/gen_fp_vectors.py -> tb/unit/bert_v2/vec/*.hex
// Moi chu ky day 1 vector; so ket qua sau LAT chu ky.
// +NEG : kiem am — dao 1 bit ket qua mong doi o vector 1000 cua moi loai, phai bao LOI.
//==============================================================================
`timescale 1ns / 1ps

module tb_fp32_units;
  localparam string V = "tb/unit/bert_v2/vec/";
  localparam int MAXN = 600000;

  logic clk = 0;
  always #2.5 clk = ~clk;

  logic [31:0] a, b;
  logic [31:0] r_add, r_mul, r_i2f;
  logic signed [15:0] r_s8, r_u8;

  fp32_add_p u_add (.clk, .a, .b, .r(r_add));
  fp32_mul_p u_mul (.clk, .a, .b, .r(r_mul));
  fp32_i2f_p u_i2f (.clk, .x(a), .r(r_i2f));
  fp32_f2i_p #(.LO(-128), .HI(127)) u_s8 (.clk, .x(a), .r(r_s8));
  fp32_f2i_p #(.LO(0),    .HI(255)) u_u8 (.clk, .x(a), .r(r_u8));

  logic [31:0] va [MAXN], vb [MAXN], vr [MAXN];
  bit neg;

  task automatic run(input string file, input int ncol, input int sel, input int lat,
                     output int nvec, output int nerr);
    int fd, k, rc;
    nvec = 0; nerr = 0;
    fd = $fopen({V, file}, "r");
    if (fd == 0) begin $display("KHONG MO DUOC %s", file); $finish; end
    while (1) begin
      if (ncol == 3) rc = $fscanf(fd, "%h %h %h", va[nvec], vb[nvec], vr[nvec]);
      else begin rc = $fscanf(fd, "%h %h", va[nvec], vr[nvec]); vb[nvec] = 0; end
      if (rc != ncol) break;
      nvec++;
    end
    $fclose(fd);
    if (neg && nvec > 1000) vr[1000] = vr[1000] ^ 32'h1;
    for (k = 0; k < nvec + lat; k++) begin
      if (k < nvec) begin a <= va[k]; b <= vb[k]; end
      @(posedge clk);
      #0.1;
      if (k >= lat - 1) begin
        logic [31:0] got;
        int j;
        j = k - lat + 1;    // a nap o canh k-lat... (xem chu thich ben duoi)
        case (sel)
          0: got = r_add;
          1: got = r_mul;
          2: got = r_i2f;
          3: got = {16'd0, r_s8};
          default: got = {16'd0, r_u8};
        endcase
        // Dau vao gan bang <= truoc canh k -> tang 1 lay mau o canh k -> ra sau canh k+lat-1.
        // Sau canh thu k (k >= lat) dau ra ung voi vector k-lat+1.
        if (j < nvec && got !== vr[j]) begin
          if (nerr < 8) $display("  %s #%0d: a=%08h b=%08h got=%08h mong=%08h", file, j, va[j], vb[j], got, vr[j]);
          nerr++;
        end
      end
    end
  endtask

  initial begin
    int n, e, tot;
    neg = $test$plusargs("NEG");
    tot = 0;
    @(posedge clk);
    run("fadd.hex",   3, 0, 3, n, e); $display("fadd   : %0d vector, %0d LOI", n, e); tot += e;
    run("fmul.hex",   3, 1, 3, n, e); $display("fmul   : %0d vector, %0d LOI", n, e); tot += e;
    run("i2f.hex",    2, 2, 2, n, e); $display("i2f    : %0d vector, %0d LOI", n, e); tot += e;
    run("f2i_s8.hex", 2, 3, 2, n, e); $display("f2i_s8 : %0d vector, %0d LOI", n, e); tot += e;
    run("f2i_u8.hex", 2, 4, 2, n, e); $display("f2i_u8 : %0d vector, %0d LOI", n, e); tot += e;
    if (tot == 0) $display("==== TB_FP32_UNITS: DAT (khop tung bit) ====");
    else          $display("==== TB_FP32_UNITS: %0d LOI ====", tot);
    $finish;
  end
endmodule
