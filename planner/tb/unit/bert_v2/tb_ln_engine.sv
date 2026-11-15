//==============================================================================
// tb_ln_engine — kiem ln_engine TUNG BIT voi hwspec (mau s00):
//   1. LN1 lop 0 : XR = L0_xin   -> COL A so voi L0_ln1q
//   2. LN2 lop 2 : XR = L2_res1  -> COL A so voi L2_ln2q
//   3. proj LN   : XR = proj     -> XR tai cho so voi proj_ln
//   4. final LN  : XR = L3_res2, ntok=1 -> cls so voi cls
// +NEG: lam sai 1 phan tu mong doi -> phai bao LOI.
//==============================================================================
`timescale 1ns / 1ps
module tb_ln_engine;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  logic start = 0, done;
  logic [1:0] dst; logic [6:0] ntok; logic [15:0] w_base, b_base; logic [31:0] inv_s;
  logic xr_re, xr_we; logic [14:0] xr_raddr, xr_waddr; logic [31:0] xr_rd, xr_wd;
  logic pa_re, pb_re; logic [15:0] pa_addr, pb_addr; logic [31:0] pa_rd, pb_rd;
  logic col_we; logic [11:0] col_waddr; logic [5:0] col_wb; logic [7:0] col_wd;
  logic cls_we; logic [8:0] cls_waddr; logic [31:0] cls_wd;

  ln_engine dut (.*);

  bv2_ram_tdp #(.W(32), .D(32768)) u_xr (.clk, .a_en(xr_re), .a_we(1'b0), .a_addr(xr_raddr), .a_wd('0), .a_rd(xr_rd),
                                         .b_en(xr_we), .b_we(xr_we), .b_addr(xr_waddr), .b_wd(xr_wd), .b_rd());
  bv2_ram_tdp #(.W(32), .D(65536)) u_pm (.clk, .a_en(pa_re), .a_we(1'b0), .a_addr(pa_addr), .a_wd('0), .a_rd(pa_rd),
                                         .b_en(pb_re), .b_we(1'b0), .b_addr(pb_addr), .b_wd('0), .b_rd(pb_rd));
  logic [7:0]  colm [512][64];
  logic [31:0] clsm [512];
  always_ff @(posedge clk) begin
    if (col_we) colm[col_waddr][col_wb] <= col_wd;
    if (cls_we) clsm[cls_waddr] <= cls_wd;
  end

  string D = "tb/unit/bert_v2/vec/s00/";
  logic [31:0] prm [65536], xa [32768], xexp [32768], clsx [512];
  logic [7:0]  qexp [32768];
  int n_err = 0, e0, cyc, k_i;
  bit neg;

  task automatic chk(input string what, input int idx, input logic [31:0] got, input logic [31:0] exp);
    if (got !== exp) begin
      if (n_err < 20) $display("  %s[%0d]: got %08h mong %08h", what, idx, got, exp);
      n_err++;
    end
  endtask

  task automatic run(input logic [1:0] d, input int nt, input int wb, input int bb, input logic [31:0] is);
    dst <= d; ntok <= 7'(nt); w_base <= 16'(wb); b_base <= 16'(bb); inv_s <= is;
    @(posedge clk); start <= 1; @(posedge clk); start <= 0;
    cyc = 0;
    while (!done) begin @(posedge clk); cyc++; if (cyc > 400000) begin $display("HET GIO"); $finish; end end
    $display("  LN dst=%0d ntok=%0d: %0d chu ky", d, nt, cyc);
  endtask

  initial begin
    neg = $test$plusargs("NEG");
    $readmemh({D, "param.hex"}, prm);
    for (k_i = 0; k_i < 65536; k_i++) u_pm.mem[k_i] = prm[k_i];
    repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    // 1. LN1 lop 0
    $readmemh({D, "L0_xin.hex"}, xa); $readmemh({D, "L0_ln1q.hex"}, qexp);
    if (neg) qexp[777] ^= 8'h1;
    for (k_i = 0; k_i < 32768; k_i++) u_xr.mem[k_i] = xa[k_i];
    e0 = n_err;
    run(0, 64, 36864 + 0*2048, 36864 + 0*2048 + 512, prm[50688 + 0*16]);
    for (k_i = 0; k_i < 32768; k_i++) chk("LN1q", k_i, {24'd0, colm[k_i % 512][k_i / 512]}, {24'd0, qexp[k_i]});
    $display("LN1 lop0: %0d loi", n_err - e0);

    // 2. LN2 lop 2
    $readmemh({D, "L2_res1.hex"}, xa); $readmemh({D, "L2_ln2q.hex"}, qexp);
    for (k_i = 0; k_i < 32768; k_i++) u_xr.mem[k_i] = xa[k_i];
    e0 = n_err;
    run(0, 64, 36864 + 2*2048 + 1024, 36864 + 2*2048 + 1536, prm[50688 + 2*16]);
    for (k_i = 0; k_i < 32768; k_i++) chk("LN2q", k_i, {24'd0, colm[k_i % 512][k_i / 512]}, {24'd0, qexp[k_i]});
    $display("LN2 lop2: %0d loi", n_err - e0);

    // 3. proj LN (XR tai cho)
    $readmemh({D, "proj.hex"}, xa); $readmemh({D, "proj_ln.hex"}, xexp);
    for (k_i = 0; k_i < 32768; k_i++) u_xr.mem[k_i] = xa[k_i];
    e0 = n_err;
    run(1, 64, 45056, 45568, 32'h3F800000);
    for (k_i = 0; k_i < 32768; k_i++) chk("PLN", k_i, u_xr.mem[k_i], xexp[k_i]);
    $display("proj LN: %0d loi", n_err - e0);

    // 4. final LN (CLS)
    $readmemh({D, "L3_res2.hex"}, xa); $readmemh({D, "cls.hex"}, clsx);
    for (k_i = 0; k_i < 32768; k_i++) u_xr.mem[k_i] = xa[k_i];
    e0 = n_err;
    run(2, 1, 46080, 46592, 32'h3F800000);
    for (k_i = 0; k_i < 512; k_i++) chk("CLS", k_i, clsm[k_i], clsx[k_i]);
    $display("final LN: %0d loi", n_err - e0);

    if (n_err == 0) $display("==== TB_LN_ENGINE: DAT (khop tung bit) ====");
    else            $display("==== TB_LN_ENGINE: %0d LOI ====", n_err);
    $finish;
  end
endmodule
