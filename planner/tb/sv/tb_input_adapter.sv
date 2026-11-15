// =============================================================================
// tb_input_adapter.sv — Unit Testbench for input_adapter
// Tests token buffering, num_valid_tokens, attn_mask, and target_xy extraction
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_input_adapter;
  import planning_pkg::*;

  localparam int MAX_TOKS = 64;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  bbox6_t        token_in;
  token_type_t   token_type;
  logic          token_valid;
  logic          token_ready;

  bbox6_t        bbox_out [MAX_TOKS-1:0];
  logic  [7:0]   num_valid_tokens;
  fp32_t         target_x, target_y;
  attn_mask_t    attn_mask_out;
  logic          valid_out;

  input_adapter dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .token_in          (token_in),
    .token_type        (token_type),
    .token_valid       (token_valid),
    .token_ready       (token_ready),
    .bbox_out          (bbox_out),
    .num_valid_tokens  (num_valid_tokens),
    .target_x          (target_x),
    .target_y          (target_y),
    .attn_mask_out     (attn_mask_out),
    .valid_out         (valid_out)
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick(input int n = 1);
    repeat(n) @(posedge clk); #0.1;
  endtask

  task check_bit(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = %0b", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=%0b exp=%0b", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_int(input string name, input int got, input int exp);
    if (got === exp) begin
      $display("  PASS [%-30s] = %0d", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-30s] got=%0d exp=%0d", name, got, exp);
      fail_cnt++;
    end
  endtask

  function automatic logic [31:0] real_to_fp32(input real v);
    return $realtobits(v);
  endfunction

  task send_token_beat(
    input token_type_t ttype,
    input real x, y, vx, vy, l, w
  );
    // Wait for ready
    begin
      int timeout = 0;
      while (!token_ready && timeout < 200) begin
        @(posedge clk); #0.1;
        timeout++;
      end
    end
    token_in.x_min  = real_to_fp32(x);
    token_in.y_min  = real_to_fp32(y);
    token_in.x_max  = real_to_fp32(vx);  // bbox6: x_min,y_min,x_max,y_max,vx,vy
    token_in.y_max  = real_to_fp32(vy);
    token_in.vx     = real_to_fp32(l);
    token_in.vy     = real_to_fp32(w);
    token_type      = ttype;
    token_valid     = 1'b1;
    @(posedge clk); #0.1;
    token_valid     = 1'b0;
  endtask

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_input_adapter : input_adapter ===");

    token_in    = '0;
    token_type  = TT_CLS;
    token_valid = 0;
    rst_n = 0;
    tick(3);
    rst_n = 1;
    tick(2);

    // T1: After reset, valid_out = 0
    check_bit("after_reset_valid", valid_out, 1'b0);
    check_bit("after_reset_ready", token_ready, 1'b1); // should be ready

    // T2: Send minimal sequence: CLS + EGO + TARGET → valid_out after TARGET
    // CLS token (type 0)
    send_token_beat(TT_CLS,    0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    // EGO token (type 1)
    send_token_beat(TT_EGO,    1.0, 2.0, 0.5, 0.0, 4.0, 2.0);
    // TARGET token (type 4) — last in sequence
    send_token_beat(TT_TARGET, 10.0, 20.0, 0.0, 0.0, 0.0, 0.0);

    // Wait for valid_out
    begin
      int timeout = 0;
      while (!valid_out && timeout < 200) begin
        tick(1);
        timeout++;
      end
      if (valid_out) begin
        $display("  PASS [%-30s] valid after 3 tokens", "valid_after_3toks");
        pass_cnt++;
        check_int("num_valid_tokens_3", int'(num_valid_tokens), 3);
        // attn_mask: bits 0,1,2 should be 1
        check_bit("attn_mask_bit0", attn_mask_out[0], 1'b1);
        check_bit("attn_mask_bit1", attn_mask_out[1], 1'b1);
        check_bit("attn_mask_bit2", attn_mask_out[2], 1'b1);
        check_bit("attn_mask_bit3", attn_mask_out[3], 1'b0); // unused
        // Target coordinates should be 10.0, 20.0
        check_int("target_x_fp32", int'(target_x), int'(real_to_fp32(10.0)));
        check_int("target_y_fp32", int'(target_y), int'(real_to_fp32(20.0)));
      end else begin
        $error("  FAIL [%-30s] timed out", "valid_after_3toks");
        fail_cnt++;
      end
    end

    tick(5);

    // T3: Send more tokens (OBJECT × 4) then TARGET
    // Need reset to start fresh, or the DUT accumulates from previous frame
    // (depends on DUT spec — many adapters reset on TARGET or new CLS)
    // Just do a system reset and try again with 6 tokens
    rst_n = 0;
    tick(2);
    rst_n = 1;
    tick(2);

    send_token_beat(TT_CLS,    0.0,  0.0, 0.0, 0.0, 0.0, 0.0);
    send_token_beat(TT_EGO,    1.0,  2.0, 0.0, 0.0, 0.0, 0.0);
    send_token_beat(TT_OBJECT, 3.0,  4.0, 0.0, 0.0, 1.0, 1.0);
    send_token_beat(TT_OBJECT, 5.0,  6.0, 0.0, 0.0, 1.0, 1.0);
    send_token_beat(TT_LANE,   0.0, -2.0, 0.0, 0.0, 0.0, 0.0);
    send_token_beat(TT_TARGET, 8.0, 16.0, 0.0, 0.0, 0.0, 0.0);

    begin
      int timeout = 0;
      while (!valid_out && timeout < 200) begin
        tick(1);
        timeout++;
      end
      if (valid_out) begin
        $display("  PASS [%-30s] valid after 6 tokens", "valid_after_6toks");
        pass_cnt++;
        check_int("num_valid_tokens_6", int'(num_valid_tokens), 6);
        check_bit("attn_mask_bit5", attn_mask_out[5], 1'b1);
        check_bit("attn_mask_bit6", attn_mask_out[6], 1'b0);
      end else begin
        $error("  FAIL [%-30s] timed out", "valid_after_6toks");
        fail_cnt++;
      end
    end

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: input_adapter");
      $finish(0);
    end else
      $fatal(1, "FAIL: input_adapter — %0d test(s) failed", fail_cnt);
  end

  initial begin
    #100000;
    $fatal(1, "TIMEOUT: simulation exceeded 100 us");
  end

endmodule
`default_nettype wire
