//==============================================================================
// tb_softmax_u8 — kiem softmax_u8 TUNG BIT voi hwspec: 8 dau lop 0 va 8 dau lop 3 (mau s00).
// SC = qk[h] (INT32), rowmax tinh trong TB (chi khoa hop le), so P8 voi p8[h].
// +NEG: lam sai 1 phan tu mong doi.
//==============================================================================
`timescale 1ns / 1ps
module tb_softmax_u8;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  logic start = 0, done;
  logic [31:0] c_qk;
  logic [63:0] key_valid;
  logic signed [31:0] rowmax [64];
  logic sc_re; logic [11:0] sc_raddr; logic [31:0] sc_rd;
  logic col_we; logic [11:0] col_waddr; logic [5:0] col_wb; logic [7:0] col_wd;

  softmax_u8 dut (.*);

  bv2_ram_tdp #(.W(32), .D(4096)) u_sc (.clk, .a_en(sc_re), .a_we(1'b0), .a_addr(sc_raddr), .a_wd('0), .a_rd(sc_rd),
                                        .b_en(1'b0), .b_we(1'b0), .b_addr('0), .b_wd('0), .b_rd());
  logic [7:0] pm [64][64];       // [j][i]
  always_ff @(posedge clk) if (col_we) pm[col_waddr - 12'd1024][col_wb] <= col_wd;

  string D = "tb/unit/bert_v2/vec/s00/";
  logic [31:0] qk [32768], prm [65536];
  logic [7:0]  p8 [32768];
  logic [0:0]  pad [64];
  int n_err = 0, e0, cyc, li, hd, ri, kj, base;
  logic signed [31:0] mx;
  bit neg;

  initial begin
    neg = $test$plusargs("NEG");
    $readmemh({D, "param.hex"}, prm);
    $readmemh({D, "pad.hex"}, pad);
    for (kj = 0; kj < 64; kj++) key_valid[kj] = ~pad[kj][0];
    repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
    for (li = 0; li < 4; li += 3) begin
      $readmemh({D, $sformatf("L%0d_qk.hex", li)}, qk);
      $readmemh({D, $sformatf("L%0d_p8.hex", li)}, p8);
      if (neg && li == 3) p8[5000] ^= 8'h1;
      c_qk = prm[50688 + li*16 + 4];
      e0 = n_err;
      for (hd = 0; hd < 8; hd++) begin
        base = hd * 4096;
        for (kj = 0; kj < 4096; kj++) u_sc.mem[kj] = qk[base + kj];
        for (ri = 0; ri < 64; ri++) begin
          mx = 32'sh80000000;
          for (kj = 0; kj < 64; kj++) if (key_valid[kj] && $signed(qk[base + ri*64 + kj]) > mx) mx = qk[base + ri*64 + kj];
          rowmax[ri] = mx;
        end
        @(posedge clk); start <= 1; @(posedge clk); start <= 0;
        cyc = 0;
        while (!done) begin @(posedge clk); cyc++; if (cyc > 100000) begin $display("HET GIO"); $finish; end end
        for (ri = 0; ri < 64; ri++) for (kj = 0; kj < 64; kj++)
          if (pm[kj][ri] !== p8[base + ri*64 + kj]) begin
            if (n_err < 20) $display("  L%0d h%0d P8[%0d][%0d]: got %0d mong %0d", li, hd, ri, kj, pm[kj][ri], p8[base + ri*64 + kj]);
            n_err++;
          end
      end
      $display("lop %0d: 8 dau, %0d loi, %0d chu ky/dau", li, n_err - e0, cyc);
    end
    if (n_err == 0) $display("==== TB_SOFTMAX_U8: DAT (khop tung bit) ====");
    else            $display("==== TB_SOFTMAX_U8: %0d LOI ====", n_err);
    $finish;
  end
endmodule
