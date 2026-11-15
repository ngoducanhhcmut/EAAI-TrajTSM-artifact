//==============================================================================
// tb_mac_array_tp — kiem mang MAC song song theo token.
// 40 nhom ngau nhien: K ngau nhien (1..80, va 512), act INT8/UINT8, w 9 bit, bong bong
// (in_v=0) ngau nhien, gia tri bien (-128/127/255, w=-256/255). Tham chieu tinh trong TB
// bang so nguyen. So 512 phan tu thoat moi nhom (gia tri, thu tu t/j).
// +NEG: lam sai tham chieu cua 1 phan tu -> phai bao LOI.
//==============================================================================
`timescale 1ns / 1ps
module tb_mac_array_tp;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;

  logic in_v = 0, in_first = 0, in_last = 0, in_act_u8 = 0;
  logic [511:0] in_act = '0;
  logic [7:0][8:0] in_w = '0;
  logic can_last, d_v;
  logic signed [31:0] d_acc;
  logic [5:0] d_t;
  logic [2:0] d_j;

  mac_array_tp dut (.*);

  localparam int NG = 40;
  longint ref_acc [NG][512];
  int     g_k [NG];
  int     n_err = 0, n_chk = 0, g_out = 0, e_out = 0;
  bit     neg;

  // ── bo thu thoat: phan tu e cua nhom g_out ──
  always @(posedge clk) if (d_v) begin
    int e;
    e = e_out;
    if (d_t !== 6'(e / 8) || d_j !== 3'(e % 8)) begin
      if (n_err < 10) $display("  nhom %0d e=%0d: chi so t=%0d j=%0d sai", g_out, e, d_t, d_j);
      n_err++;
    end
    if (longint'(d_acc) != ref_acc[g_out][e]) begin
      if (n_err < 10) $display("  nhom %0d (K=%0d) t=%0d j=%0d: got %0d mong %0d", g_out, g_k[g_out], e/8, e%8, d_acc, ref_acc[g_out][e]);
      n_err++;
    end
    n_chk++;
    e_out++;
    if (e_out == 512) begin e_out = 0; g_out++; end
  end

  function automatic int rnd_k();
    int r = $urandom % 10;
    if (r < 2) return 512;
    if (r == 2) return 1;
    return 1 + ($urandom % 80);
  endfunction

  // watchdog + tien do
  initial begin
    #5ms;
    $display("WATCHDOG: g_out=%0d e_out=%0d dcnt=%0d can_last=%0d", g_out, e_out, dut.dcnt, can_last);
    $display("==== TB_MAC_ARRAY_TP: TREO ====");
    $finish;
  end

  initial begin
    neg = $test$plusargs("NEG");
    repeat (4) @(posedge clk); rst_n = 1; @(posedge clk);
    for (int g = 0; g < NG; g++) begin
      int K;
      bit u8;
      K = rnd_k(); g_k[g] = K;
      u8 = (g % 3 == 2);
      for (int i = 0; i < 512; i++) ref_acc[g][i] = 0;
      for (int k = 0; k < K; k++) begin
        logic [511:0] a;
        logic [7:0][8:0] w;
        for (int t = 0; t < 64; t++) begin
          int r = $urandom % 16;
          a[t*8 +: 8] = (r == 0) ? 8'h80 : (r == 1) ? 8'h7F : (r == 2) ? 8'hFF : 8'($urandom);
        end
        for (int j = 0; j < 8; j++) begin
          int r = $urandom % 16;
          w[j] = (r == 0) ? 9'h100 : (r == 1) ? 9'h0FF : 9'($urandom);
        end
        for (int t = 0; t < 64; t++)
          for (int j = 0; j < 8; j++) begin
            longint av, wv;
            av = u8 ? longint'(a[t*8 +: 8]) : longint'($signed(a[t*8 +: 8]));
            wv = longint'($signed(w[j]));
            ref_acc[g][t*8 + j] += av * wv;
          end
        // bong bong ngau nhien
        while (($urandom % 5) == 0) begin
          in_v <= 0; in_first <= 0; in_last <= 0; @(posedge clk);
        end
        if (k == K - 1) begin
          in_v <= 0;
          #0.1;                                  // lay mau SAU vung NBA cua canh truoc
          while (!can_last) begin @(posedge clk); #0.1; end
        end
        in_v <= 1; in_first <= (k == 0); in_last <= (k == K - 1); in_act_u8 <= u8;
        in_act <= a; in_w <= w;
        @(posedge clk);
      end
      in_v <= 0; in_first <= 0; in_last <= 0;
      if (g % 10 == 0) $display("  da nap nhom %0d (K=%0d) t=%0t", g, K, $time);
    end
    if (neg) ref_acc[NG-1][77] += 1;
    while (g_out < NG) @(posedge clk);
    repeat (5) @(posedge clk);
    $display("Da kiem %0d phan tu thoat (%0d nhom)", n_chk, NG);
    if (n_err == 0 && n_chk == NG * 512) $display("==== TB_MAC_ARRAY_TP: DAT ====");
    else $display("==== TB_MAC_ARRAY_TP: %0d LOI ====", n_err);
    $finish;
  end
endmodule
