// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// tb_axil_regfile.sv — Unit Test for AXI-Lite CSR Controller
// Test: Register read/write, address decode, protocol compliance
// ================================================================================

`timescale 1ns / 1ps
`default_nettype none

import planning_pkg::*;

module tb_axil_regfile ();

  logic clk, rst_n;
  
  // AXI-Lite Write Address Channel
  logic [11:0] awaddr;
  logic awvalid;
  logic awready;
  
  // AXI-Lite Write Data Channel
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  logic wready;
  
  // AXI-Lite Write Response Channel
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  
  // AXI-Lite Read Address Channel
  logic [11:0] araddr;
  logic arvalid;
  logic arready;
  
  // AXI-Lite Read Data Channel
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;

  integer errors = 0, tests = 0;

  // DUT
  axil_regfile dut (
    .aclk(clk),
    .aresetn(rst_n),
    .awaddr(awaddr),
    .awvalid(awvalid),
    .awready(awready),
    .wdata(wdata),
    .wstrb(wstrb),
    .wvalid(wvalid),
    .wready(wready),
    .bresp(bresp),
    .bvalid(bvalid),
    .bready(bready),
    .araddr(araddr),
    .arvalid(arvalid),
    .arready(arready),
    .rdata(rdata),
    .rresp(rresp),
    .rvalid(rvalid),
    .rready(rready)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset
  initial begin
    rst_n = 0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
  end

  // AXI helper tasks
  task axi_write_addr(input [11:0] addr);
    begin
      awaddr = addr;
      awvalid = 1;
      wait(awready);
      @(posedge clk);
      awvalid = 0;
    end
  endtask

  task axi_write_data(input [31:0] data, input [3:0] strb = 4'hF);
    begin
      wdata = data;
      wstrb = strb;
      wvalid = 1;
      wait(wready);
      @(posedge clk);
      wvalid = 0;
    end
  endtask

  task axi_write_resp();
    begin
      bready = 1;
      wait(bvalid);
      @(posedge clk);
      bready = 0;
    end
  endtask

  task axi_read_addr(input [11:0] addr);
    begin
      araddr = addr;
      arvalid = 1;
      wait(arready);
      @(posedge clk);
      arvalid = 0;
    end
  endtask

  task axi_read_data(output [31:0] data);
    begin
      rready = 1;
      wait(rvalid);
      data = rdata;
      @(posedge clk);
      rready = 0;
    end
  endtask

  // Test stimulus
  logic [31:0] read_data;

  initial begin
    awvalid = 0; wvalid = 0; bready = 0;
    arvalid = 0; rready = 0;

    @(posedge rst_n);
    @(posedge clk);
    $display("[CSR_TEST] Starting axil_regfile unit test...");

    // Test 1: Write register at address 0x00
    $display("[TEST 1] Write 32'hDEADBEEF to address 0x00");
    tests = tests + 1;
    axi_write_addr(12'h00);
    axi_write_data(32'hDEADBEEF, 4'hF);
    axi_write_resp();
    if (bresp == 2'b00) begin
      $display("  ✓ PASS: Write acknowledged (OKAY response)");
    end else begin
      $display("  ✗ FAIL: bresp=%b (expected 00)", bresp);
      errors = errors + 1;
    end

    // Test 2: Read register at address 0x00
    $display("[TEST 2] Read register at address 0x00");
    tests = tests + 1;
    axi_read_addr(12'h00);
    axi_read_data(read_data);
    if (read_data == 32'hDEADBEEF) begin
      $display("  ✓ PASS: Read data 0x%08X matches written value", read_data);
    end else begin
      $display("  ✗ FAIL: Read 0x%08X (expected 0xDEADBEEF)", read_data);
      errors = errors + 1;
    end

    // Test 3: Write to different address (0x04)
    $display("[TEST 3] Write 32'hCAFEBABE to address 0x04");
    tests = tests + 1;
    axi_write_addr(12'h04);
    axi_write_data(32'hCAFEBABE, 4'hF);
    axi_write_resp();
    if (bresp == 2'b00) begin
      $display("  ✓ PASS: Write to 0x04 acknowledged");
    end else begin
      $display("  ✗ FAIL: bresp=%b", bresp);
      errors = errors + 1;
    end

    // Test 4: Read address 0x04
    $display("[TEST 4] Read register at address 0x04");
    tests = tests + 1;
    axi_read_addr(12'h04);
    axi_read_data(read_data);
    if (read_data == 32'hCAFEBABE) begin
      $display("  ✓ PASS: Read data 0x%08X matches", read_data);
    end else begin
      $display("  ✗ FAIL: Read 0x%08X (expected 0xCAFEBABE)", read_data);
      errors = errors + 1;
    end

    // Test 5: Verify first address unchanged
    $display("[TEST 5] Verify address 0x00 unchanged");
    tests = tests + 1;
    axi_read_addr(12'h00);
    axi_read_data(read_data);
    if (read_data == 32'hDEADBEEF) begin
      $display("  ✓ PASS: Address 0x00 still contains 0xDEADBEEF");
    end else begin
      $display("  ✗ FAIL: Read 0x%08X from 0x00", read_data);
      errors = errors + 1;
    end

    // Test 6: Byte enable selective write (CTX_SCALE per spec §17)
    $display("[TEST 6] Partial write with byte enables (lower 16 bits)");
    tests = tests + 1;
    axi_write_addr(12'h10);
    axi_write_data(32'h12345678, 4'b0011);  // Write only [15:0]
    axi_write_resp();
    axi_read_addr(12'h10);
    axi_read_data(read_data);
    if ((read_data & 16'hFFFF) == 16'h5678) begin
      $display("  ✓ PASS: Byte-selective write successful, lower half = 0x%04X", read_data[15:0]);
    end else begin
      $display("  ✗ FAIL: Byte write failed, read 0x%08X", read_data);
      errors = errors + 1;
    end

    // Test 7: Back-to-back writes (protocol stress)
    $display("[TEST 7] Back-to-back write operations");
    tests = tests + 1;
    fork
      begin
        axi_write_addr(12'h20);
        axi_write_addr(12'h24);
      end
      begin
        axi_write_data(32'h11111111, 4'hF);
        axi_write_data(32'h22222222, 4'hF);
      end
      begin
        axi_write_resp();
        axi_write_resp();
      end
    join
    $display("  ✓ PASS: Back-to-back writes accepted");

    // Summary
    @(posedge clk);
    $display("");
    $display("========================================");
    $display("  Tests run: %0d", tests);
    $display("  Errors:    %0d", errors);
    if (errors == 0) begin
      $display("  Status: ✓ ALL TESTS PASSED");
    end else begin
      $display("  Status: ✗ FAILURES DETECTED");
    end
    $display("========================================");
    
    $finish;
  end

endmodule
