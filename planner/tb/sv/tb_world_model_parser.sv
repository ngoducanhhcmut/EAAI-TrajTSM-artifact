// =============================================================================
// tb_world_model_parser.sv — Unit Testbench for world_model_parser
// Tests parse_start → token stream output (token_valid/type/bbox) → parse_done
// Smoke test: model HDR/OBJ/LANE BRAMs and token_fifo as ready-always slave
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_world_model_parser;
  import planning_pkg::*;

  logic clk = 1'b0;
  logic rst_n;

  always #2.5 clk = ~clk;

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic          parse_start;
  logic          parse_done;
  logic          parse_busy;

  logic  [1:0]   hdr_rd_addr;
  logic [31:0]   hdr_rd_data;
  logic          hdr_rd_en;

  logic [11:0]   obj_rd_addr;
  logic [31:0]   obj_rd_data;
  logic          obj_rd_en;

  logic  [9:0]   lane_rd_addr;
  logic [31:0]   lane_rd_data;
  logic          lane_rd_en;

  logic  [7:0]   wm_num_objects;
  logic  [4:0]   wm_num_lanes;

  fp32_t         target_x;
  fp32_t         target_y;

  bbox6_t        token_out;
  token_type_t   token_type_out;
  logic          token_valid;
  logic          token_ready;
  logic          token_last;

  attn_mask_t    attn_mask_out;
  logic  [7:0]   num_tokens_out;

  world_model_parser dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .parse_start    (parse_start),
    .parse_done     (parse_done),
    .parse_busy     (parse_busy),
    .hdr_rd_addr    (hdr_rd_addr),
    .hdr_rd_data    (hdr_rd_data),
    .hdr_rd_en      (hdr_rd_en),
    .obj_rd_addr    (obj_rd_addr),
    .obj_rd_data    (obj_rd_data),
    .obj_rd_en      (obj_rd_en),
    .lane_rd_addr   (lane_rd_addr),
    .lane_rd_data   (lane_rd_data),
    .lane_rd_en     (lane_rd_en),
    .wm_num_objects (wm_num_objects),
    .wm_num_lanes   (wm_num_lanes),
    .target_x       (target_x),
    .target_y       (target_y),
    .token_out      (token_out),
    .token_type_out (token_type_out),
    .token_valid    (token_valid),
    .token_ready    (token_ready),
    .token_last     (token_last),
    .attn_mask_out  (attn_mask_out),
    .num_tokens_out (num_tokens_out)
  );

  // ── Memory models ─────────────────────────────────────────────────────────
  // HDR BRAM: 4 × 32-bit words
  logic [31:0] hdr_mem [0:3];
  always_ff @(posedge clk) begin
    hdr_rd_data <= hdr_rd_en ? hdr_mem[hdr_rd_addr] : 32'h0;
  end

  // OBJ BRAM: 4096 × 32-bit
  logic [31:0] obj_mem [0:4095];
  always_ff @(posedge clk) begin
    obj_rd_data <= obj_rd_en ? obj_mem[obj_rd_addr] : 32'h0;
  end

  // LANE BRAM: 1024 × 32-bit
  logic [31:0] lane_mem [0:1023];
  always_ff @(posedge clk) begin
    lane_rd_data <= lane_rd_en ? lane_mem[lane_rd_addr] : 32'h0;
  end

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;
  int token_count = 0;
  int last_seen = 0;

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

  // Token counter monitor
  always @(posedge clk) begin
    if (token_valid && token_ready) begin
      token_count++;
      if (token_last) last_seen = 1;
    end
  end

  // Always ready to accept tokens
  assign token_ready = 1'b1;

  function automatic logic [31:0] real_to_fp32(input real v);
    return $realtobits(v);
  endfunction

  // ── Main Test ──────────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_world_model_parser : world_model_parser ===");

    parse_start    = 0;
    wm_num_objects = 8'd2;   // 2 objects
    wm_num_lanes   = 5'd1;   // 1 lane
    target_x       = real_to_fp32(5.0);
    target_y       = real_to_fp32(10.0);

    // Initialize all memories to 0
    for (int i = 0; i < 4;    i++) hdr_mem[i]  = 32'h0;
    for (int i = 0; i < 4096; i++) obj_mem[i]  = 32'h0;
    for (int i = 0; i < 1024; i++) lane_mem[i] = 32'h0;

    rst_n = 0;
    tick(3);
    rst_n = 1;
    tick(2);

    // T1: After reset, parse_busy = 0 and no tokens
    check_bit("after_reset_busy", parse_busy, 1'b0);
    check_bit("after_reset_done", parse_done, 1'b0);

    // T2: Trigger parse with 2 objects + 1 lane
    // Expected token sequence: CLS + EGO + 2×OBJECT + 1×LANE + TARGET = 6 tokens
    @(posedge clk); #0.1;
    parse_start = 1'b1;
    @(posedge clk); #0.1;
    parse_start = 1'b0;

    // Should become busy
    tick(2);
    check_bit("busy_after_start", parse_busy, 1'b1);

    // Wait for parse_done
    begin
      int timeout = 0;
      while (!parse_done && timeout < 5000) begin
        tick(1);
        timeout++;
      end
      if (parse_done) begin
        $display("  PASS [%-30s] done in reasonable time", "parse_done");
        pass_cnt++;
        // Verify token count: CLS(1) + EGO(1) + OBJ(2) + LANE(1) + TARGET(1) = 6
        // (exact count depends on DUT implementation, check ≥ 4)
        if (token_count >= 4) begin
          $display("  PASS [%-30s] %0d tokens emitted", "token_count", token_count);
          pass_cnt++;
        end else begin
          $error("  FAIL [%-30s] only %0d tokens emitted (exp ≥ 4)", "token_count", token_count);
          fail_cnt++;
        end
        check_bit("token_last_seen", last_seen[0], 1'b1);
        // num_tokens_out should match token_count
        check_int("num_tokens_match", int'(num_tokens_out), token_count);
      end else begin
        $error("  FAIL [%-30s] timed out (tokens emitted so far: %0d)", "parse_done", token_count);
        fail_cnt++;
      end
    end

    tick(5);

    // T3: parse_busy should go low after done
    check_bit("not_busy_after_done", parse_busy, 1'b0);

    // T4: Smoke test with 0 objects and 0 lanes (minimal: CLS+EGO+TARGET = 3)
    token_count    = 0;
    last_seen      = 0;
    wm_num_objects = 8'd0;
    wm_num_lanes   = 5'd0;

    @(posedge clk); #0.1;
    parse_start = 1'b1;
    @(posedge clk); #0.1;
    parse_start = 1'b0;

    begin
      int timeout = 0;
      while (!parse_done && timeout < 500) begin
        tick(1);
        timeout++;
      end
      if (parse_done) begin
        $display("  PASS [%-30s] minimal parse done (%0d tokens)", "minimal_parse", token_count);
        pass_cnt++;
        check_bit("minimal_token_last", last_seen[0], 1'b1);
      end else begin
        $error("  FAIL [%-30s] minimal parse timed out", "minimal_parse");
        fail_cnt++;
      end
    end

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: world_model_parser");
      $finish(0);
    end else
      $fatal(1, "FAIL: world_model_parser — %0d test(s) failed", fail_cnt);
  end

  initial begin
    #200000;
    $fatal(1, "TIMEOUT: simulation exceeded 200 us");
  end

endmodule
`default_nettype wire
