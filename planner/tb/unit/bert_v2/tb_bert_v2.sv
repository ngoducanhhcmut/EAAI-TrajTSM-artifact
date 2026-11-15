//==============================================================================
// tb_bert_v2 — tich hop BERT V2 day du, KHONG tiem du lieu giua chung:
//   PARAM nap qua cong DMA (pm_we) ; token + mat na ; pos_emb RAM (tre 2) ;
//   URAM (tre 2) nap lai trong so lop L truoc moi cmd_layer (gia lap DMA).
//   proj -> so XR voi proj_ln ; lop 0..3 -> so XR voi L{L}_res2 ; final -> so cls.
//   +S=sXX (mac dinh s00) ; +NEG lam sai 1 phan tu cls mong doi.
//==============================================================================
`timescale 1ns / 1ps
module tb_bert_v2;
  import planning_pkg::*;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  logic cmd_proj = 0, cmd_layer = 0, cmd_final = 0, busy, done;
  logic [1:0] lyr = 0;
  bbox6_t tok [MAX_SEQ_LEN-1:0];   // cung dai voi planning_top (ia_bbox_out)
  logic [7:0] nvalid;
  logic [63:0] key_valid;
  logic pm_we = 0; logic [15:0] pm_waddr = 0; logic [31:0] pm_wd = 0;
  logic pe_re; logic [13:0] pe_addr; logic [63:0] pe_rd;
  logic u_en; logic [17:0] u_addr; logic [63:0] u_rd;
  logic cls_we; logic [8:0] cls_waddr; logic [31:0] cls_wd;

  bert_v2 dut (.*);

  logic [63:0] pem [16384]; logic [63:0] pe_q;
  always_ff @(posedge clk) begin if (pe_re) pe_q <= pem[pe_addr]; pe_rd <= pe_q; end
  logic [63:0] uram [196608]; logic [63:0] u_q;
  logic [63:0] u_q2;   // URAM tre 3 (giong planning_top sau IMPL 04/10)
  always_ff @(posedge clk) begin if (u_en) u_q <= uram[u_addr]; u_q2 <= u_q; u_rd <= u_q2; end
  logic [31:0] clsm [512];
  always_ff @(posedge clk) if (cls_we) clsm[cls_waddr] <= cls_wd;

  string D, SN;
  logic [31:0] prm [65536], tk [384], xexp [32768], clsx [512];
  logic [0:0] pad [64];
  int n_err = 0, e0, cyc, k_i, nv, fd, lyr_i, tot_cyc = 0;
  bit neg;

  task automatic issue(input int which, input int l);
    @(posedge clk);
    lyr <= 2'(l);
    if (which == 0) cmd_proj <= 1; else if (which == 1) cmd_layer <= 1; else cmd_final <= 1;
    @(posedge clk); cmd_proj <= 0; cmd_layer <= 0; cmd_final <= 0;
    cyc = 0;
    while (!done) begin @(posedge clk); cyc++; if (cyc > 5000000) begin $display("HET GIO lenh %0d", which); $finish; end end
    tot_cyc += cyc;
  endtask

  task automatic cmp_xr(input string what);
    e0 = n_err;
    for (k_i = 0; k_i < 32768; k_i++) if (dut.u_xr.mem[k_i] !== xexp[k_i]) begin
      if (n_err < 20) $display("  %s XR[%0d]: got %08h mong %08h", what, k_i, dut.u_xr.mem[k_i], xexp[k_i]);
      n_err++;
    end
    $display("%s: %0d chu ky, %0d loi", what, cyc, n_err - e0);
  endtask

  initial begin
    neg = $test$plusargs("NEG");
    if (!$value$plusargs("S=%s", SN)) SN = "s00";
    D = {"tb/unit/bert_v2/vec/", SN, "/"};
    $readmemh({D, "param.hex"}, prm);
    $readmemh({D, "posemb.hex"}, pem);
    $readmemh({D, "tok.hex"}, tk);
    $readmemh({D, "pad.hex"}, pad);
    $readmemh({D, "cls.hex"}, clsx);
    if (neg) clsx[100] ^= 32'h1;
    fd = $fopen({D, "meta.txt"}, "r"); void'($fscanf(fd, "%d", nv)); $fclose(fd);
    nvalid = 8'(nv);
    for (k_i = 0; k_i < 64; k_i++) begin
      key_valid[k_i] = ~pad[k_i][0];
      tok[k_i] = (k_i < nv) ? {tk[k_i*6+0], tk[k_i*6+1], tk[k_i*6+2], tk[k_i*6+3], tk[k_i*6+4], tk[k_i*6+5]}
                            : {6{32'h4048F5C3}};
    end
    repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
    // PARAM qua cong DMA
    for (k_i = 0; k_i < 65536; k_i++) begin
      pm_we <= 1; pm_waddr <= 16'(k_i); pm_wd <= prm[k_i]; @(posedge clk);
    end
    pm_we <= 0;

    issue(0, 0);
    $readmemh({D, "proj_ln.hex"}, xexp); cmp_xr("PROJ+LN");
    for (lyr_i = 0; lyr_i < 4; lyr_i++) begin
      $readmemh({D, $sformatf("uram_%0d.hex", lyr_i)}, uram);
      issue(1, lyr_i);
      $readmemh({D, $sformatf("L%0d_res2.hex", lyr_i)}, xexp); cmp_xr($sformatf("LOP %0d", lyr_i));
    end
    issue(2, 0);
    e0 = n_err;
    for (k_i = 0; k_i < 512; k_i++) if (clsm[k_i] !== clsx[k_i]) begin
      if (n_err < 30) $display("  CLS[%0d]: got %08h mong %08h", k_i, clsm[k_i], clsx[k_i]);
      n_err++;
    end
    $display("FINAL LN -> CLS: %0d chu ky, %0d loi", cyc, n_err - e0);
    $display("Tong chu ky tinh BERT (khong ke nap trong so): %0d", tot_cyc);
    if (n_err == 0) $display("==== TB_BERT_V2 %s: DAT (CLS khop tung bit) ====", SN);
    else            $display("==== TB_BERT_V2 %s: %0d LOI ====", SN, n_err);
    $finish;
  end
endmodule
