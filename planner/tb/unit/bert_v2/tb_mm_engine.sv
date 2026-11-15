//==============================================================================
// tb_mm_engine — chay du 8 mode cua mm_engine tren 1 lop BERT that (vector hwspec),
// so TUNG BIT moi dau ra voi sw/hwspec/hwspec_exact.py.
//   +L=<0..3> lop ; +S=<thu muc mau, mac dinh s00> ; +NEG lam sai 1 phan tu mong doi.
// Trinh tu: Q,K,V (vao COL A = ln1q) -> moi dau h: QK (so SC + rowmax), nap P8 tu
// vector, PV (so ctx8 cot h) -> WO (XR = xin, so res1) -> nap COL A = ln2q, LUT GELU ->
// W1 (so gelu8) -> W2 (so res2).
//==============================================================================
`timescale 1ns / 1ps
module tb_mm_engine;
  import planning_pkg::*;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  // ── DUT + bo nho ─────────────────────────────────────────────────────────────
  logic start = 0, done;
  logic [2:0] mode = 0, head = 0;
  logic [63:0] key_valid;
  logic [15:0] cs_base, b_base;
  logic [17:0] uram_base;
  logic [31:0] mul3, c_ctx;
  logic gl_we = 0; logic [7:0] gl_addr = 0, gl_wd = 0;
  logic col_re, col_we; logic [11:0] col_raddr, col_waddr; logic [511:0] col_rd; logic [5:0] col_wb; logic [7:0] col_wd;
  logic u_en; logic [17:0] u_addr; logic [63:0] u_rd;
  logic k8_re, k8_we, v8_re, v8_we; logic [11:0] k8_raddr, k8_waddr, v8_raddr, v8_waddr;
  logic [63:0] k8_rd, v8_rd; logic [2:0] k8_wb, v8_wb; logic [7:0] k8_wd, v8_wd;
  logic sc_we; logic [11:0] sc_waddr; logic [31:0] sc_wd;
  logic signed [31:0] rowmax [64];
  logic xr_re, xr_we; logic [14:0] xr_raddr, xr_waddr; logic [31:0] xr_rd, xr_wd;
  logic pa_re, pb_re; logic [15:0] pa_addr, pb_addr; logic [31:0] pa_rd, pb_rd;

  mm_engine dut (.*);

  bv2_ram_bytew #(.NB(64), .D(2560)) u_col (.clk, .we(col_we), .waddr(col_waddr), .wb(col_wb), .wd(col_wd),
                                            .re(col_re), .raddr(col_raddr), .rd(col_rd));
  bv2_ram_bytew #(.NB(8), .D(4096)) u_k8 (.clk, .we(k8_we), .waddr(k8_waddr), .wb(k8_wb), .wd(k8_wd),
                                          .re(k8_re), .raddr(k8_raddr), .rd(k8_rd));
  bv2_ram_bytew #(.NB(8), .D(4096)) u_v8 (.clk, .we(v8_we), .waddr(v8_waddr), .wb(v8_wb), .wd(v8_wd),
                                          .re(v8_re), .raddr(v8_raddr), .rd(v8_rd));
  bv2_ram_tdp #(.W(32), .D(32768)) u_xr (.clk, .a_en(xr_re), .a_we(1'b0), .a_addr(xr_raddr), .a_wd('0), .a_rd(xr_rd),
                                         .b_en(xr_we), .b_we(xr_we), .b_addr(xr_waddr), .b_wd(xr_wd), .b_rd());
  bv2_ram_tdp #(.W(32), .D(65536)) u_pm (.clk, .a_en(pa_re), .a_we(1'b0), .a_addr(pa_addr), .a_wd('0), .a_rd(pa_rd),
                                         .b_en(pb_re), .b_we(1'b0), .b_addr(pb_addr), .b_wd('0), .b_rd(pb_rd));
  logic [31:0] sc_mem [4096];
  always_ff @(posedge clk) if (sc_we) sc_mem[sc_waddr] <= sc_wd;
  // URAM: doc tre 2
  logic [63:0] uram [196608];
  logic [63:0] u_q;
  logic [63:0] u_q2;   // URAM tre 3 (giong planning_top sau IMPL 04/10)
  always_ff @(posedge clk) begin if (u_en) u_q <= uram[u_addr]; u_q2 <= u_q; u_rd <= u_q2; end

  // ── vector ──────────────────────────────────────────────────────────────────
  string D;
  int L;
  bit neg;
  logic [7:0]  ln1q [64*512], q8 [64*512], k8 [64*512], v8 [64*512], ctx8 [64*512], ln2q [64*512];
  logic [7:0]  gelu8 [64*2048], p8 [8*64*64];
  logic [31:0] qk [8*64*64], xin [64*512], res1 [64*512], res2 [64*512], prm [65536];
  logic [0:0]  pad [64];
  int n_err = 0;

  task automatic chk(input string what, input int idx, input logic [31:0] got, input logic [31:0] exp);
    if (got !== exp) begin
      if (n_err < 20) $display("  %s[%0d]: got %08h mong %08h", what, idx, got, exp);
      n_err++;
    end
  endtask

  task automatic run_op(input logic [2:0] md, input logic [2:0] h);
    int cyc;
    mode <= md; head <= h;
    @(posedge clk); start <= 1; @(posedge clk); start <= 0;
    cyc = 0;
    while (!done) begin @(posedge clk); cyc++; if (cyc > 3000000) begin $display("HET GIO mode %0d", md); $finish; end end
    $display("  mode %0d dau %0d: %0d chu ky", md, h, cyc);
  endtask

  function automatic logic [31:0] scal(input int i);
    return prm[50688 + L*16 + i];
  endfunction

  // CHU Y: xsim 2023.2 doc sai bien vong lap tu dong (`for (int h ...)`) sau khi goi
  // task co cho thoi gian -> dung bien tinh khai bao o day cho moi vong lap co run_op.
  int head_i, row_i, col_j, hbase, eidx;
  logic signed [31:0] mx;
  logic [511:0] wtmp;
  initial begin
    int e0;
    if (!$value$plusargs("L=%d", L)) L = 0;
    if (!$value$plusargs("S=%s", D)) D = "s00";
    D = {"tb/unit/bert_v2/vec/", D, "/"};
    neg = $test$plusargs("NEG");
    $readmemh({D, "param.hex"}, prm);
    $readmemh({D, $sformatf("uram_%0d.hex", L)}, uram);
    $readmemh({D, "pad.hex"}, pad);
    $readmemh({D, $sformatf("L%0d_ln1q.hex", L)}, ln1q);
    $readmemh({D, $sformatf("L%0d_q8.hex", L)}, q8);
    $readmemh({D, $sformatf("L%0d_k8.hex", L)}, k8);
    $readmemh({D, $sformatf("L%0d_v8.hex", L)}, v8);
    $readmemh({D, $sformatf("L%0d_qk.hex", L)}, qk);
    $readmemh({D, $sformatf("L%0d_p8.hex", L)}, p8);
    $readmemh({D, $sformatf("L%0d_ctx8.hex", L)}, ctx8);
    $readmemh({D, $sformatf("L%0d_xin.hex", L)}, xin);
    $readmemh({D, $sformatf("L%0d_res1.hex", L)}, res1);
    $readmemh({D, $sformatf("L%0d_ln2q.hex", L)}, ln2q);
    $readmemh({D, $sformatf("L%0d_gelu8.hex", L)}, gelu8);
    $readmemh({D, $sformatf("L%0d_res2.hex", L)}, res2);
    if (neg) res2[1234] ^= 32'h1;
    for (int i = 0; i < 65536; i++) u_pm.mem[i] = prm[i];
    for (int t = 0; t < 64; t++) key_valid[t] = ~pad[t][0];
    for (int c = 0; c < 512; c++) begin
      logic [511:0] wv;
      for (int t = 0; t < 64; t++) wv[t*8 +: 8] = ln1q[t*512 + c];
      u_col.mem[c] = wv;
    end
    c_ctx = scal(5);
    repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    // ── Q, K, V ──
    cs_base = L*9216 + 0;    b_base = cs_base + 4608; uram_base = 0;     mul3 = scal(1); run_op(0, 0);
    cs_base = L*9216 + 512;  b_base = cs_base + 4608; uram_base = 16384; mul3 = scal(2); run_op(1, 0);
    cs_base = L*9216 + 1024; b_base = cs_base + 4608; uram_base = 32768; mul3 = scal(3); run_op(2, 0);
    e0 = n_err;
    for (int t = 0; t < 64; t++) for (int o = 0; o < 512; o++) begin
      chk("Q8", t*512+o, u_col.mem[512 + o][t*8 +: 8], q8[t*512+o]);
      chk("K8", t*512+o, u_k8.mem[o*8 + t/8][(t%8)*8 +: 8], k8[t*512+o]);
      chk("V8", t*512+o, u_v8.mem[t*64 + o/8][(o%8)*8 +: 8], v8[t*512+o]);
    end
    $display("Q/K/V: %0d loi", n_err - e0);

    // ── attention theo dau ──
    e0 = n_err;
    for (head_i = 0; head_i < 8; head_i++) begin
      run_op(6, 3'(head_i));
      hbase = head_i * 4096;
      for (row_i = 0; row_i < 64; row_i++) begin
        mx = 32'sh80000000;
        for (col_j = 0; col_j < 64; col_j++) begin
          eidx = hbase + row_i*64 + col_j;
          chk("SC", eidx, sc_mem[row_i*64 + col_j], qk[eidx]);
          if (!pad[col_j][0] && $signed(qk[eidx]) > mx) mx = qk[eidx];
        end
        chk("ROWMAX", head_i*64 + row_i, rowmax[row_i], mx);
      end
      for (col_j = 0; col_j < 64; col_j++) begin
        for (row_i = 0; row_i < 64; row_i++) wtmp[row_i*8 +: 8] = p8[hbase + row_i*64 + col_j];
        u_col.mem[1024 + col_j] = wtmp;
      end
      run_op(7, 3'(head_i));
    end
    for (int t = 0; t < 64; t++) for (int o = 0; o < 512; o++)
      chk("CTX8", t*512+o, u_col.mem[o][t*8 +: 8], ctx8[t*512+o]);
    $display("QK/PV: %0d loi", n_err - e0);

    // ── WO ──
    e0 = n_err;
    for (int i = 0; i < 32768; i++) u_xr.mem[i] = xin[i];
    cs_base = L*9216 + 1536; b_base = cs_base + 4608; uram_base = 49152; run_op(3, 0);
    for (int i = 0; i < 32768; i++) chk("RES1", i, u_xr.mem[i], res1[i]);
    $display("WO: %0d loi", n_err - e0);

    // ── W1 ──
    e0 = n_err;
    for (int c = 0; c < 512; c++) begin
      logic [511:0] wv;
      for (int t = 0; t < 64; t++) wv[t*8 +: 8] = ln2q[t*512 + c];
      u_col.mem[c] = wv;
    end
    for (int i = 0; i < 256; i++) begin
      gl_we <= 1; gl_addr <= i[7:0]; gl_wd <= prm[50752 + L*64 + i/4][(i%4)*8 +: 8]; @(posedge clk);
    end
    gl_we <= 0;
    cs_base = L*9216 + 2048; b_base = cs_base + 4608; uram_base = 65536; mul3 = scal(6); run_op(4, 0);
    for (int t = 0; t < 64; t++) for (int o = 0; o < 2048; o++)
      chk("GELU8", t*2048+o, u_col.mem[512 + o][t*8 +: 8], gelu8[t*2048+o]);
    $display("W1: %0d loi", n_err - e0);

    // ── W2 ──
    e0 = n_err;
    cs_base = L*9216 + 4096; b_base = cs_base + 4608; uram_base = 131072; run_op(5, 0);
    for (int i = 0; i < 32768; i++) chk("RES2", i, u_xr.mem[i], res2[i]);
    $display("W2: %0d loi", n_err - e0);

    if (n_err == 0) $display("==== TB_MM_ENGINE L%0d: DAT (khop tung bit) ====", L);
    else            $display("==== TB_MM_ENGINE L%0d: %0d LOI ====", L, n_err);
    $finish;
  end
endmodule
