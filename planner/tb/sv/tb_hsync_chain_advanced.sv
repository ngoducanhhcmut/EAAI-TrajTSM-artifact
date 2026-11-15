`timescale 1ns/1ps
// =============================================================================
// tb_hsync_chain_advanced.sv — Comprehensive Testbench for CDC Synchronizer
// Features: Parameterization coverage, Mid-cycle Async Reset, Strict Pulse Check,
//           and Asynchronous Data Injection (CDC Emulation).
// =============================================================================

module tb_hsync_chain_advanced;

  // ─── Clock Generation ───────────────────────────────────────────────────────
  logic clk = 1'b0;
  localparam CLK_PERIOD = 10;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ─── DUT 1: Default Parameters (WIDTH=1, STAGES=3) ──────────────────────────
  logic       rst_n_1;
  logic       d_in_1;
  logic       d_out_1;

  hsync_chain #(.WIDTH(1), .STAGES(3)) dut1 (
    .clk   (clk),
    .rst_n (rst_n_1),
    .d_in  (d_in_1),
    .d_out (d_out_1)
  );

  // ─── DUT 2: Custom Parameters (WIDTH=8, STAGES=2) ───────────────────────────
  logic       rst_n_2;
  logic [7:0] d_in_2;
  logic [7:0] d_out_2;

  hsync_chain #(.WIDTH(8), .STAGES(2)) dut2 (
    .clk   (clk),
    .rst_n (rst_n_2),
    .d_in  (d_in_2),
    .d_out (d_out_2)
  );

  // ─── Verification Helpers ───────────────────────────────────────────────────
  int pass_cnt = 0;
  int fail_cnt = 0;

  task check_1(input string name, input logic got, input logic exp);
    if (got === exp) begin
      $display("  [PASS] %-30s : DUT1 got %0h", name, got);
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-30s : DUT1 got %0h, expected %0h", name, got, exp);
      fail_cnt++;
    end
  endtask

  task check_2(input string name, input logic [7:0] got, input logic [7:0] exp);
    if (got === exp) begin
      $display("  [PASS] %-30s : DUT2 got %0h", name, got);
      pass_cnt++;
    end else begin
      $error("  [FAIL] %-30s : DUT2 got %0h, expected %0h", name, got, exp);
      fail_cnt++;
    end
  endtask

  // Sync tasks
  task wait_cycles(int cycles);
    repeat(cycles) @(posedge clk);
  endtask

  // ─── Test Sequences ─────────────────────────────────────────────────────────
  initial begin
    $display("==================================================================");
    $display("=== STARTING ADVANCED TESTBENCH FOR HSYNC_CHAIN ===");
    $display("==================================================================");

    // Khởi tạo giá trị
    rst_n_1 = 0; d_in_1 = 0;
    rst_n_2 = 0; d_in_2 = 8'h00;
    wait_cycles(2);
    rst_n_1 = 1; rst_n_2 = 1;
    wait_cycles(1);

    // -------------------------------------------------------------------------
    $display("\n---> TEST 1: Initial Reset State");
    // -------------------------------------------------------------------------
    check_1("DUT1 (W=1, S=3) After Reset", d_out_1, 1'b0);
    check_2("DUT2 (W=8, S=2) After Reset", d_out_2, 8'h00);

    // -------------------------------------------------------------------------
    $display("\n---> TEST 2: Mid-cycle Asynchronous Reset");
    // -------------------------------------------------------------------------
    // Bơm dữ liệu vào cho ngập pipeline
    d_in_1 = 1'b1;
    d_in_2 = 8'hAA;
    wait_cycles(4); 
    
    // Kiểm tra dữ liệu đã tới d_out chưa
    check_1("DUT1 Before Async Reset", d_out_1, 1'b1);
    check_2("DUT2 Before Async Reset", d_out_2, 8'hAA);

    // Kéo reset xuống ở GIỮA chu kỳ clock (không đợi posedge clk)
    #(CLK_PERIOD * 0.3); 
    rst_n_1 = 0; 
    rst_n_2 = 0;
    #(CLK_PERIOD * 0.1); // Đợi một chút xíu thời gian thực
    
    // Ngõ ra phải LẬP TỨC về 0 dù chưa tới cạnh clock
    check_1("DUT1 Immediate Async Reset", d_out_1, 1'b0);
    check_2("DUT2 Immediate Async Reset", d_out_2, 8'h00);

    // Nhả reset
    #(CLK_PERIOD * 0.6); // Đi hết chu kỳ hiện tại
    rst_n_1 = 1; rst_n_2 = 1;
    wait_cycles(1);

    // -------------------------------------------------------------------------
    $display("\n---> TEST 3: Strict 1-Cycle Pulse Check");
    // -------------------------------------------------------------------------
    // Tạo 1 xung đúng 1 chu kỳ clock
    @(posedge clk);
    #1; // Đẩy dữ liệu sau cạnh clock một chút để mô phỏng setup time
    d_in_1 = 1'b1; d_in_2 = 8'hFF;
    
    @(posedge clk);
    #1;
    d_in_1 = 1'b0; d_in_2 = 8'h00;

    // Theo dõi đầu ra từng chu kỳ
    // Với S=3 (DUT1), dữ liệu sẽ ra ở chu kỳ thứ 3 sau khi đẩy vào
    // Với S=2 (DUT2), dữ liệu sẽ ra ở chu kỳ thứ 2 sau khi đẩy vào
    
    // Cycle +1
    @(posedge clk); #1;
    check_1("DUT1 Pulse Cycle +1", d_out_1, 1'b0);
    check_2("DUT2 Pulse Cycle +1 (Out!)", d_out_2, 8'hFF); // S=2 nên ra luôn

    // Cycle +2
    @(posedge clk); #1;
    check_1("DUT1 Pulse Cycle +2 (Out!)", d_out_1, 1'b1); // S=3 nên ra ở đây
    check_2("DUT2 Pulse Cycle +2 (Clear)", d_out_2, 8'h00); // Đã đi qua mất

    // Cycle +3
    @(posedge clk); #1;
    check_1("DUT1 Pulse Cycle +3 (Clear)", d_out_1, 1'b0); // Đã đi qua mất

    // -------------------------------------------------------------------------
    $display("\n---> TEST 4: Asynchronous CDC Injection (Random timing)");
    // -------------------------------------------------------------------------
    // Trong thực tế, d_in đến từ domain khác, nó thay đổi không tuân theo clk này.
    rst_n_1 = 0; rst_n_2 = 0;
    wait_cycles(2);
    rst_n_1 = 1; rst_n_2 = 1;
    
    fork
      // Thread 1: Đổi dữ liệu liên tục ở các thời điểm ngẫu nhiên (không phải bội số của clk)
      begin
        for (int i=0; i<10; i++) begin
          #( $urandom_range(3, 17) ); // Delay ngẫu nhiên từ 3ns đến 17ns
          d_in_1 = ~d_in_1;
          d_in_2 = $urandom;
        end
      end
      
      // Thread 2: Pipeline Reference Model (Theo dõi chính xác những gì FF tóm được tại posedge clk)
      begin
        logic       ref_pipe_1 [3]; // STAGES=3
        logic [7:0] ref_pipe_2 [2]; // STAGES=2
        
        // Init mảng
        for(int i=0; i<3; i++) ref_pipe_1[i] = 0;
        for(int i=0; i<2; i++) ref_pipe_2[i] = 0;

        // Sampling tại posedge clk như phần cứng thực
        repeat(20) begin
          @(posedge clk);
          // Shift register cho DUT1 (S=3)
          ref_pipe_1[2] = ref_pipe_1[1];
          ref_pipe_1[1] = ref_pipe_1[0];
          ref_pipe_1[0] = d_in_1;
          
          // Shift register cho DUT2 (S=2)
          ref_pipe_2[1] = ref_pipe_2[0];
          ref_pipe_2[0] = d_in_2;

          // Kiểm tra ngõ ra phần cứng có khớp với Reference Model sau khi shift không
          #1; // Đợi phần cứng cập nhật d_out sau cạnh clock
          if (d_out_1 !== ref_pipe_1[2]) begin
            $error("  [FAIL] CDC DUT1 mismatch: got %0b, exp %0b", d_out_1, ref_pipe_1[2]);
            fail_cnt++;
          end
          if (d_out_2 !== ref_pipe_2[1]) begin
            $error("  [FAIL] CDC DUT2 mismatch: got %0h, exp %0h", d_out_2, ref_pipe_2[1]);
            fail_cnt++;
          end
        end
      end
    join

    $display("  [INFO] Asynchronous CDC Injection Test Completed.");

    // -------------------------------------------------------------------------
    $display("\n==================================================================");
    $display("=== FINAL RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    $display("==================================================================");
    if (fail_cnt == 0) begin
      $display(">>> SUCCESS: hsync_chain passed all rigorous checks! <<<");
      $finish(0);
    end else begin
      $fatal(1, ">>> FAILED: hsync_chain has %0d failing conditions! <<<", fail_cnt);
    end
  end

endmodule