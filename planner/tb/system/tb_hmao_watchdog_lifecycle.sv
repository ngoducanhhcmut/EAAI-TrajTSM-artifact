`timescale 1ns/1ps
import hmao_pkg::*;

// Production thresholds, board clocks, no SIM_WDT_FAST. Counter forcing only
// approaches a threshold; RTL performs the final increment and timeout CDC.
module tb_hmao_watchdog_lifecycle;
  logic sys_clk = 0, wdt_clk = 0;
  always #2.667 sys_clk = ~sys_clk;
  always #2 wdt_clk = ~wdt_clk;
  logic rst_n = 0;
  logic kick_s1 = 0, kick_s2 = 0, kick_total = 0;
  logic monitor_s1 = 0, monitor_s2 = 0, monitor_total = 0;
  logic clear_timeout = 0;
  wire s1_timeout, s2_timeout, total_timeout, wdt_fault;
  int checks = 0;
  hmao_watchdog dut (.*);

  task automatic check(input bit good, input string message);
    if (!good) $fatal(1, "FAIL: %s", message);
    checks++;
    $display("PASS: %s", message);
  endtask

  task automatic settle;
    repeat (20) @(negedge sys_clk);
  endtask

  // Match engine start: five-cycle kick overlaps a sixteen-cycle clear.
  task automatic start_run;
    @(negedge sys_clk);
    monitor_total = 1;
    clear_timeout = 1;
    kick_s1 = 1; kick_s2 = 1; kick_total = 1;
    repeat (5) @(negedge sys_clk);
    kick_s1 = 0; kick_s2 = 0; kick_total = 0;
    repeat (11) @(negedge sys_clk);
    clear_timeout = 0;
    settle();
    check(dut.wdt_armed && dut.cnt_total > 0,
          "start kick remains armed despite overlapping clear");
    check(!wdt_fault, "start clears every prior timeout through CDC");
  endtask

  task automatic acknowledge;
    @(negedge sys_clk);
    monitor_s1 = 0; monitor_s2 = 0; monitor_total = 0;
    clear_timeout = 1;
    repeat (16) @(negedge sys_clk);
    clear_timeout = 0;
    settle();
    check(!wdt_fault && !dut.wdt_armed, "ack clears faults and disarms idle watchdog");
  endtask

  initial begin
    settle(); rst_n = 1; settle();
    check(!wdt_fault && dut.cnt_s1 == 0 && dut.cnt_s2 == 0 && dut.cnt_total == 0,
          "idle after reset does not count");
    monitor_s1 = 1;
    start_run();
    check(dut.cnt_s1 > 0 && dut.cnt_s2 == 0, "only active stage counts");
    monitor_s1 = 0;
    settle();
    check(dut.cnt_s1 == 0 && dut.cnt_total > 0 && !wdt_fault,
          "decision stops stage watchdog while completion padding remains protected");
    acknowledge();
    settle();
    check(dut.cnt_total == 0 && !wdt_fault, "idle after completion remains clean");

    monitor_s1 = 1; start_run();
    @(negedge wdt_clk);
    force dut.cnt_s1 = WDT_STAGE1_CYCLES - 1;
    @(negedge wdt_clk); release dut.cnt_s1;
    settle();
    check(s1_timeout && wdt_fault && !s2_timeout && !total_timeout,
          "real stage1 timeout still fires");
    monitor_s1 = 0; settle();
    check(s1_timeout, "real timeout stays latched until explicit clear");
    // Restart directly from a stale raw fault, matching the new start cleanup.
    start_run();
    acknowledge();

    monitor_s2 = 1; start_run();
    @(negedge wdt_clk);
    force dut.cnt_s2 = WDT_STAGE2_CYCLES - 1;
    @(negedge wdt_clk); release dut.cnt_s2;
    settle();
    check(s2_timeout && wdt_fault && !s1_timeout && !total_timeout,
          "real stage2 timeout still fires");
    acknowledge();

    start_run();
    @(negedge wdt_clk);
    force dut.cnt_total = WDT_TOTAL_CYCLES - 1;
    @(negedge wdt_clk); release dut.cnt_total;
    settle();
    check(total_timeout && wdt_fault && !s1_timeout && !s2_timeout,
          "total timeout covers a stalled job even with both stages disabled");
    acknowledge();
    $display("WATCHDOG LIFECYCLE: %0d PASS, 0 FAIL", checks);
    $finish;
  end
  initial begin #100_000; $fatal(1, "testbench timeout"); end
endmodule
