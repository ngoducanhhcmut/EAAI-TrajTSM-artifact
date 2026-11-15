`timescale 1ns/1ps

module tb_cdc_pulse_sync_adv;

  // ===========================================================================
  // 1. SIGNALS & PARAMETERS
  // ===========================================================================
  localparam int STAGES = 3;
  
  logic src_clk  = 0;
  logic dest_clk = 0;
  logic rst_n    = 0;
  logic src_pulse = 0;
  logic dest_level;

  real src_period  = 5.0;  // Default 200 MHz
  real dest_period = 7.5;  // Default 133 MHz

  // ===========================================================================
  // 2. CLOCK GENERATION WITH RANDOM PHASE OFFSET
  // ===========================================================================
  logic start_clks = 0;

  initial begin
    wait(start_clks);
    // Randomize initial phase shift for src_clk (0 to 1 period)
    #( $urandom_range(0, 1000) / 1000.0 * src_period );
    forever #(src_period / 2.0) src_clk = ~src_clk;
  end

  initial begin
    wait(start_clks);
    // Randomize initial phase shift for dest_clk (0 to 1 period)
    #( $urandom_range(0, 1000) / 1000.0 * dest_period );
    forever #(dest_period / 2.0) dest_clk = ~dest_clk;
  end

  // ===========================================================================
  // 3. DUT INSTANTIATION
  // ===========================================================================
  cdc_pulse_sync #(.STAGES(STAGES)) dut (
    .src_clk    (src_clk),
    .rst_n      (rst_n),
    .src_pulse  (src_pulse),
    .dest_clk   (dest_clk),
    .dest_level (dest_level)
  );

  // ===========================================================================
  // 4. SYSTEMVERILOG ASSERTIONS (SVA)
  // ===========================================================================
  // Yêu cầu: dest_level chỉ được phép rộng ĐÚNG 1 chu kỳ dest_clk
  property p_dest_pulse_width;
    @(posedge dest_clk) disable iff (!rst_n)
      dest_level |=> !dest_level;
  endproperty

  assert_pulse_width: assert property (p_dest_pulse_width) 
    else $error("SVA VIOLATION: dest_level is wider than 1 clock cycle!");

  // ===========================================================================
  // 5. SCOREBOARD & MONITORS
  // ===========================================================================
  int pulses_sent = 0;
  int pulses_recv = 0;
  logic enable_scoreboard = 0;

  // Monitor: Đếm số xung nhận được ở dest domain
  always_ff @(posedge dest_clk or negedge rst_n) begin
    if (!rst_n) begin
      pulses_recv <= 0;
    end else if (enable_scoreboard && dest_level) begin
      pulses_recv <= pulses_recv + 1;
    end
  end

  // ===========================================================================
  // 6. TASKS & HELPER FUNCTIONS
  // ===========================================================================
  task automatic apply_reset();
    rst_n = 0;
    src_pulse = 0;
    // Hold reset for random duration
    #( $urandom_range(20, 50) );
    rst_n = 1;
    // Wait for multi-stage sync to clear
    repeat(STAGES + 2) @(posedge dest_clk);
  endtask

  // Gửi 1 xung hợp lệ
  task automatic send_pulse();
    @(posedge src_clk);
    src_pulse <= 1'b1;
    @(posedge src_clk);
    src_pulse <= 1'b0;
    if (enable_scoreboard) pulses_sent++;
  endtask

  // Tính toán khoảng cách an toàn tối thiểu (Minimum Safe Spacing)
  // Để Toggle FF + CDC an toàn, 2 xung src phải cách nhau ít nhất:
  // (STAGES) * dest_period + một khoảng margin
  function int get_safe_spacing();
    real min_time = (STAGES + 1.5) * dest_period;
    int min_cycles = $ceil(min_time / src_period);
    return min_cycles;
  endfunction

  // Tạo traffic ngẫu nhiên
  task automatic run_random_traffic(int num_pulses);
    int safe_spacing = get_safe_spacing();
    $display("    [Traffic] Safe spacing calculated: %0d src_clk cycles", safe_spacing);
    
    for (int i = 0; i < num_pulses; i++) begin
      int spacing = $urandom_range(safe_spacing, safe_spacing + 10);
      send_pulse();
      repeat(spacing) @(posedge src_clk);
    end
    
    // Đợi tín hiệu lan truyền hết sang dest
    repeat(STAGES + 5) @(posedge dest_clk);
  endtask

  // ===========================================================================
  // 7. MAIN TEST SEQUENCE
  // ===========================================================================
  initial begin
    $display("==================================================");
    $display("   STARTING ADVANCED CDC PULSE SYNC TESTBENCH     ");
    $display("==================================================");

    start_clks = 1;

    // ------------------------------------------------------------------
    $display("\n[TEST 1] FAST TO SLOW (src=200MHz, dest=133MHz)");
    src_period  = 5.0;  
    dest_period = 7.5;
    apply_reset();
    
    enable_scoreboard = 1;
    pulses_sent = 0; pulses_recv = 0;
    
    run_random_traffic(500); // Gửi 500 xung ngẫu nhiên
    
    if (pulses_sent !== pulses_recv) 
      $error("TEST 1 FAIL: Sent %0d, Recv %0d", pulses_sent, pulses_recv);
    else 
      $display("  -> PASS: Sent %0d, Recv %0d", pulses_sent, pulses_recv);
    enable_scoreboard = 0;

    // ------------------------------------------------------------------
    $display("\n[TEST 2] SLOW TO FAST (src=100MHz, dest=250MHz)");
    src_period  = 10.0; 
    dest_period = 4.0;
    apply_reset();
    
    enable_scoreboard = 1;
    pulses_sent = 0; pulses_recv = 0;
    
    run_random_traffic(500); 
    
    if (pulses_sent !== pulses_recv) 
      $error("TEST 2 FAIL: Sent %0d, Recv %0d", pulses_sent, pulses_recv);
    else 
      $display("  -> PASS: Sent %0d, Recv %0d", pulses_sent, pulses_recv);
    enable_scoreboard = 0;

    // ------------------------------------------------------------------
    $display("\n[TEST 3] ASYNCHRONOUS RESET GLITCH STRESS");
    // Bắn xung liên tục và đập reset bất thình lình
    src_period = 5.0; dest_period = 7.5;
    apply_reset();
    
    fork
      begin // Driver
        for(int i=0; i<50; i++) begin
          send_pulse();
          repeat(get_safe_spacing()) @(posedge src_clk);
        end
      end
      begin // Naughty Resetter
        repeat(5) begin
          #( $urandom_range(50, 150) );
          rst_n = 0; // Đập reset ngẫu nhiên
          #( $urandom_range(5, 20) );
          rst_n = 1;
        end
      end
    join_any
    disable fork; // Dừng tiến trình còn lại
    
    // Check xem mạch có phục hồi sau reset không
    apply_reset();
    enable_scoreboard = 1;
    pulses_sent = 0; pulses_recv = 0;
    run_random_traffic(10);
    if (pulses_sent !== pulses_recv) 
      $error("TEST 3 FAIL: Circuit did not recover after async reset spam!");
    else 
      $display("  -> PASS: Circuit recovered beautifully.");
    enable_scoreboard = 0;

    // ------------------------------------------------------------------
    $display("\n[TEST 4] VIOLATING MINIMUM SPACING (Expected to drop pulses)");
    $display("    Sending pulses too fast to see if circuit handles it without X-states or glitches.");
    apply_reset();
    
    // Khởi tạo 1 xung, sau đó chỉ cách 1 chu kỳ src_clk đã bắn tiếp xung nữa
    // Với Toggle-FF, xung thứ 2 sẽ làm toggle lật ngược lại trước khi dest_clk lấy mẫu -> Xung bị drop.
    @(posedge src_clk); src_pulse = 1;
    @(posedge src_clk); src_pulse = 0; // Pulse 1
    @(posedge src_clk);                // Cách 1 chu kỳ
    @(posedge src_clk); src_pulse = 1;
    @(posedge src_clk); src_pulse = 0; // Pulse 2
    
    repeat(20) @(posedge dest_clk);
    $display("  -> SVA Assertions ensure no glitch occurs even when pulses are dropped.");

    // ------------------------------------------------------------------
    $display("\n==================================================");
    $display("             TESTBENCH FINISHED                   ");
    $display("   If no $error or SVA VIOLATION printed -> PASS! ");
    $display("==================================================");
    $finish;
  end

  // Watchdog Timer
  initial begin
    #1_000_000;
    $fatal("WATCHDOG TIMEOUT");
  end

endmodule