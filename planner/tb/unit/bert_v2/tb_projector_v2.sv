//==============================================================================
// tb_projector_v2 — kiem projector_v2 TUNG BIT voi hwspec (proj.hex), mau s00.
// Hang token dem (t >= nvalid) duoc NAP RAC co y de kiem viec ep = 0.
// +NEG: lam sai 1 phan tu mong doi.
//==============================================================================
`timescale 1ns / 1ps
module tb_projector_v2;
  import planning_pkg::*;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  logic start = 0, done;
  logic [7:0] nvalid;
  bbox6_t tok [MAX_SEQ_LEN-1:0];   // cung dai voi planning_top (ia_bbox_out)
  logic pa_re, pb_re, pe_re, xr_we; logic [15:0] pa_addr, pb_addr; logic [31:0] pa_rd, pb_rd;
  logic [13:0] pe_addr; logic [63:0] pe_rd; logic [14:0] xr_waddr; logic [31:0] xr_wd;

  projector_v2 dut (.*);

  bv2_ram_tdp #(.W(32), .D(65536)) u_pm (.clk, .a_en(pa_re), .a_we(1'b0), .a_addr(pa_addr), .a_wd('0), .a_rd(pa_rd),
                                         .b_en(pb_re), .b_we(1'b0), .b_addr(pb_addr), .b_wd('0), .b_rd(pb_rd));
  bv2_ram_tdp #(.W(64), .D(16384)) u_pe (.clk, .a_en(pe_re), .a_we(1'b0), .a_addr(pe_addr), .a_wd('0), .a_rd(pe_rd),
                                         .b_en(1'b0), .b_we(1'b0), .b_addr('0), .b_wd('0), .b_rd());
  logic [31:0] xm [32768];
  always_ff @(posedge clk) if (xr_we) xm[xr_waddr] <= xr_wd;

  string D = "tb/unit/bert_v2/vec/s00/";
  logic [31:0] prm [65536], tk [384], pexp [32768];
  logic [63:0] pem [16384];
  int n_err = 0, cyc, k_i, nv, fd;
  bit neg;

  initial begin
    neg = $test$plusargs("NEG");
    $readmemh({D, "param.hex"}, prm);  for (k_i = 0; k_i < 65536; k_i++) u_pm.mem[k_i] = prm[k_i];
    $readmemh({D, "posemb.hex"}, pem); for (k_i = 0; k_i < 16384; k_i++) u_pe.mem[k_i] = pem[k_i];
    $readmemh({D, "tok.hex"}, tk);
    $readmemh({D, "proj.hex"}, pexp);
    if (neg) pexp[20000] ^= 32'h1;
    fd = $fopen({D, "meta.txt"}, "r"); void'($fscanf(fd, "%d", nv)); $fclose(fd);
    nvalid = 8'(nv);
    for (k_i = 0; k_i < 64; k_i++) begin
      if (k_i < nv) tok[k_i] = {tk[k_i*6+0], tk[k_i*6+1], tk[k_i*6+2], tk[k_i*6+3], tk[k_i*6+4], tk[k_i*6+5]};
      else          tok[k_i] = {6{32'h4048F5C3}};      // rac (3.14) — phai bi ep = 0
    end
    repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
    @(posedge clk); start <= 1; @(posedge clk); start <= 0;
    cyc = 0;
    while (!done) begin @(posedge clk); cyc++; if (cyc > 100000) begin $display("HET GIO"); $finish; end end
    $display("projector: %0d chu ky, nvalid=%0d", cyc, nv);
    for (k_i = 0; k_i < 32768; k_i++) if (xm[k_i] !== pexp[k_i]) begin
      if (n_err < 20) $display("  XR[%0d] (t=%0d o=%0d): got %08h mong %08h", k_i, k_i/512, k_i%512, xm[k_i], pexp[k_i]);
      n_err++;
    end
    if (n_err == 0) $display("==== TB_PROJECTOR_V2: DAT (khop tung bit) ====");
    else            $display("==== TB_PROJECTOR_V2: %0d LOI ====", n_err);
    $finish;
  end
endmodule
