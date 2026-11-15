// =============================================================================
// tb_token_fifo.sv — Vivado xsim testbench for token_fifo
// Mirrors tests from tb_token_fifo.cpp
// FWFT (First Word Fall Through) — khớp RTL hiện hành và tb_token_fifo_advanced:
//   token_o/token_valid_o là combinational từ fifo_ram[rd_ptr]/(rd_ptr!=wr_ptr).
//   Sau write tick:  valid_o = 1 NGAY (head đã hiện ra)
//   Drain: đọc token_o TRƯỚC khi tick handshake (tick làm rd_ptr advance)
// Usage: Vivado simulation, top = tb_token_fifo
// =============================================================================
`timescale 1ns/1ps

module tb_token_fifo;
  import planning_pkg::*;

  localparam int TB_N_TOKENS = 4;  // used in drain_4 block

  // ── DUT ports ─────────────────────────────────────────────────────────────
  logic          clk          = 1'b0;
  logic          rst_n;
  bbox6_t        x_token_data;
  token_type_t   x_token_type;
  logic          x_token_valid;
  logic          x_token_ready;
  bbox6_t        token_o;
  token_type_t   token_type_o;
  logic          token_valid_o;
  logic          token_ready_i;
  logic  [7:0]   fifo_occupancy;

  always #2.5 clk = ~clk;

  token_fifo dut (.*);

  // ── Helpers ───────────────────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task tick();
    @(posedge clk); #0.1;
  endtask

  task do_reset();
    rst_n         = 0;
    x_token_valid = 0;
    token_ready_i = 0;
    x_token_type  = TT_CLS;
    x_token_data  = '0;
    tick(); tick();
    rst_n = 1;
    tick();
  endtask

  task check(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  PASS [%-22s] = %0d", name, got);
      pass_cnt++;
    end else begin
      $error("  FAIL [%-22s] got=%0d exp=%0d", name, got, exp);
      fail_cnt++;
    end
  endtask

  // Encode a simple token: only x_min used for identification
  function automatic bbox6_t make_token(input logic [31:0] id);
    bbox6_t t;
    t = '0;
    t.x_min = id;
    return t;
  endfunction

  // Write one token (pulse x_token_valid for 1 cycle)
  task write_token(input logic [31:0] id, input token_type_t tt);
    x_token_data  = make_token(id);
    x_token_type  = tt;
    x_token_valid = 1;
    tick();
    x_token_valid = 0;
  endtask

  // ── Test sequence ─────────────────────────────────────────────────────────
  initial begin
    $display("=== tb_token_fifo : token_fifo ===");

    // T1: Reset state
    do_reset();
    check("reset_valid_o", token_valid_o, 1'b0);
    if (fifo_occupancy === 0)
      $display("  PASS [reset_occupancy  ] = 0");
    else begin
      $error("  FAIL [reset_occupancy  ] got=%0d exp=0", fifo_occupancy);
      fail_cnt++;
    end
    pass_cnt++;

    // T2: Write 1 token; FWFT — valid_o = 1 ngay sau write tick
    do_reset();
    write_token(32'hAABB_0001, TT_OBJECT);
    check("after_write_valid_o", token_valid_o, 1'b1); // FWFT: head visible now

    // T3: After 1 idle tick → valid_o=1, occupancy=1
    tick();  // idle
    check("after_idle_valid_o", token_valid_o, 1'b1);
    if (fifo_occupancy === 1)
      $display("  PASS [occupancy_1      ] = 1");
    else begin
      $error("  FAIL [occupancy_1      ] got=%0d exp=1", fifo_occupancy);
      fail_cnt++;
    end
    pass_cnt++;

    // T4: Read back token — FWFT protocol: đọc token_o TRƯỚC, tick sau
    if (token_o.x_min === 32'hAABB_0001) begin
      $display("  PASS [drain_check      ] x_min=0x%08h", token_o.x_min);
      pass_cnt++;
    end else begin
      $error("  FAIL [drain_check      ] got=0x%08h exp=0xAABB0001", token_o.x_min);
      fail_cnt++;
    end
    token_ready_i = 1;
    tick();  // consume: rd_ptr advances
    token_ready_i = 0;
    check("after_drain_valid_o", token_valid_o, 1'b0);

    // T5: Write 4 tokens and drain in order
    do_reset();
    begin : drain_4
    // N_TOKENS declared at module scope (localparam inside initial block
    // is not valid SV — moved to module scope as tb_n_tokens)
      logic [31:0] ids [TB_N_TOKENS];
      for (int i = 0; i < TB_N_TOKENS; i++) begin
        ids[i] = 32'hBEEF_0000 + i;
        write_token(ids[i], TT_LANE);
      end
      tick();  // idle: let valid_o stabilize after last write
      check("4tok_valid_o", token_valid_o, 1'b1);

      token_ready_i = 1;
      for (int i = 0; i < TB_N_TOKENS; i++) begin
        // FWFT: token_o đang hiện token i TRƯỚC handshake tick
        if (token_o.x_min === ids[i]) begin
          $display("  PASS [drain_tok%0d       ] x_min=0x%08h", i, token_o.x_min);
          pass_cnt++;
        end else begin
          $error("  FAIL [drain_tok%0d       ] got=0x%08h exp=0x%08h",
                 i, token_o.x_min, ids[i]);
          fail_cnt++;
        end
        tick();  // consume token i — rd_ptr advances
      end
      token_ready_i = 0;
      tick();
      check("4tok_empty", token_valid_o, 1'b0);
    end

    // T6: Simultaneous read + write (when not empty)
    do_reset();
    write_token(32'hCAFE_0001, TT_EGO);
    tick();  // idle: valid_o=1 now
    // Simultaneously: write new token AND drain current
    x_token_data  = make_token(32'hCAFE_0002);
    x_token_type  = TT_TARGET;
    x_token_valid = 1;
    token_ready_i = 1;
    tick();  // simult tick
    x_token_valid = 0;
    token_ready_i = 0;
    tick();  // idle: let valid_o update
    // After simult: occupancy should be 1 (wrote 1, read 1)
    // After idle tick: token_o should show 0x0002
    check("simult_valid_o", token_valid_o, 1'b1);
    tick();  // drain tick
    if (token_o.x_min === 32'hCAFE_0002) begin
      $display("  PASS [after_simult     ] x_min=0x%08h", token_o.x_min);
      pass_cnt++;
    end else begin
      $error("  FAIL [after_simult     ] got=0x%08h exp=0xCAFE0002", token_o.x_min);
      fail_cnt++;
    end

    // T7: x_token_ready asserted when not full
    do_reset();
    check("ready_when_empty", x_token_ready, 1'b1);

    $display("");
    $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("PASS: token_fifo");
      $finish(0);
    end else
      $fatal(1, "FAIL: token_fifo — %0d test(s) failed", fail_cnt);
  end

endmodule
