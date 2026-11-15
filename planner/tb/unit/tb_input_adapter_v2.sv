//==============================================================================
// tb_input_adapter_v2 — kiem input_adapter sau sua E2E 02/10:
//   khung chi chot (valid_out) khi exp_valid VA da nhan du exp_count token,
//   du token den thua (ho ngau nhien 0..40 chu ky). 20 khung lien tiep, N ngau nhien 2..64.
//   Kiem: valid_out khong len som; num_valid_tokens = N; noi dung token; attn_mask.
// +NEG: dat exp_count = N-1 -> phai bao LOI (khung chot thieu).
//==============================================================================
`timescale 1ns / 1ps
module tb_input_adapter_v2;
  import planning_pkg::*;
  logic clk = 0, rst_n = 0;
  always #2.5 clk = ~clk;
  logic clear_frame = 0, exp_valid = 0, token_valid = 0, token_ready, valid_out;
  logic [7:0] exp_count = 0, num_valid_tokens;
  bbox6_t token_in; token_type_t token_type;
  bbox6_t bbox_out [MAX_SEQ_LEN-1:0];
  fp32_t target_x, target_y; attn_mask_t attn_mask_out;
  input_adapter dut (.*);

  bbox6_t ref_t [64];
  int n_err = 0, fr, N, i, gap;
  bit neg;
  initial begin
    neg = $test$plusargs("NEG");
    token_type = token_type_t'(0);
    repeat (3) @(posedge clk); rst_n = 1;
    for (fr = 0; fr < 20; fr++) begin
      N = 2 + ($urandom % 63);
      @(posedge clk); clear_frame <= 1; exp_valid <= 0; @(posedge clk); clear_frame <= 0;
      for (i = 0; i < N; i++) begin
        gap = $urandom % 41;
        repeat (gap) begin
          @(posedge clk); #0.1;
          if (valid_out) begin if (n_err < 10) $display("  khung %0d: valid_out SOM sau %0d token", fr, i); n_err++; end
        end
        ref_t[i] = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom};
        token_in <= ref_t[i]; token_valid <= 1;
        @(posedge clk); while (!token_ready) @(posedge clk);
        token_valid <= 0;
      end
      exp_count <= 8'(neg ? N - 1 : N); exp_valid <= 1;
      repeat (5) @(posedge clk); #0.1;
      if (!valid_out) begin $display("  khung %0d: valid_out KHONG len", fr); n_err++; end
      if (num_valid_tokens != 8'(N)) begin if (n_err < 10) $display("  khung %0d: nvalid %0d mong %0d", fr, num_valid_tokens, N); n_err++; end
      for (i = 0; i < N; i++) if (bbox_out[i] !== ref_t[i]) begin if (n_err < 10) $display("  khung %0d tok %0d sai", fr, i); n_err++; end
      if (attn_mask_out !== attn_mask_t'((65'd1 << N) - 1)) begin $display("  khung %0d mask %h", fr, attn_mask_out); n_err++; end
    end
    if (n_err == 0) $display("==== TB_INPUT_ADAPTER_V2: DAT (20 khung) ====");
    else            $display("==== TB_INPUT_ADAPTER_V2: %0d LOI ====", n_err);
    $finish;
  end
endmodule
