// ================================================================================
// Testbench: tb_dual_port_ram_advanced.sv
// Description: Comprehensive Verification cho Parameterized True Dual-Port BRAM
// Covers: Asynchronous Clocks, Collision Modes, OREG parameters, Corner Cases.
// ================================================================================
`timescale 1ns/1ps

// --------------------------------------------------------------------------------
// MODULE: RAM Test Suite (Module tự động test dựa trên parameters)
// --------------------------------------------------------------------------------
module ram_test_suite #(
    parameter string MODE_NAME = "WRITE_FIRST",
    parameter int    OREG_EN   = 1
)(
    input logic clk_a,
    input logic clk_b
);
    localparam int DW    = 32;
    localparam int DEPTH = 64;
    localparam int AW    = $clog2(DEPTH);

    // DUT I/O
    logic          rst_a_n = 0, rst_b_n = 0;
    logic          ena = 0, wea = 0;
    logic [AW-1:0] addra = '0;
    logic [DW-1:0] dina = '0, douta;

    logic          enb = 0, web = 0;
    logic [AW-1:0] addrb = '0;
    logic [DW-1:0] dinb = '0, doutb;

    // Instantiate DUT
    dual_port_ram #(
        .DATA_WIDTH       (DW),
        .DEPTH            (DEPTH),
        .REGISTERED_OUTPUT(OREG_EN),
        .COLLISION_MODE   (MODE_NAME)
    ) dut (
        .* // Auto-connect matching port names
    );

    int pass_cnt = 0;
    int fail_cnt = 0;
    int read_latency = OREG_EN ? 2 : 1;

    // Helper: In kết quả
    function void chk(string desc, logic cond);
        if (cond) begin 
            //$display("[PASS] [%s|OREG=%0d] %s", MODE_NAME, OREG_EN, desc); 
            pass_cnt++;
        end else begin 
            $display("[FAIL] [%s|OREG=%0d] %s", MODE_NAME, OREG_EN, desc); 
            fail_cnt++;
        end
    endfunction

    // ── Tasks điều khiển ────────────────────────────────────────────────────────
    task automatic write_a(input logic [AW-1:0] addr, input logic [DW-1:0] data);
        @(posedge clk_a); #1;
        ena = 1; wea = 1; addra = addr; dina = data;
        @(posedge clk_a); #1;
        ena = 0; wea = 0;
    endtask

    task automatic read_a(input logic [AW-1:0] addr, output logic [DW-1:0] data);
        @(posedge clk_a); #1;
        ena = 1; wea = 0; addra = addr;
        // Chờ số cycle tương ứng với read_latency
        repeat(read_latency) @(posedge clk_a); 
        #1;
        data = douta;
        ena = 0;
    endtask

    // ── Main Test Sequence ──────────────────────────────────────────────────────
    initial begin
        logic [DW-1:0] rdat;

        // Reset
        rst_a_n = 0; rst_b_n = 0;
        repeat(5) @(posedge clk_a);
        
        // TC1: Kiểm tra Reset (Chỉ có tác dụng nếu OREG_EN = 1)
        if (OREG_EN) begin
            chk("TC1: Output Register reset to 0", douta === '0 && doutb === '0);
        end
        rst_a_n = 1; rst_b_n = 1;
        repeat(2) @(posedge clk_a);

        // TC2: Kiểm tra Enable (ena=0 nhưng wea=1 -> KHÔNG ĐƯỢC GHI)
        write_a(6'd5, 32'hAAAA_AAAA); // Khởi tạo data
        @(posedge clk_a); #1;
        ena = 0; wea = 1; addra = 6'd5; dina = 32'hDEAD_DEAD; // Cố tình ghi trộm
        @(posedge clk_a); #1;
        wea = 0;
        read_a(6'd5, rdat);
        chk("TC2: Write ignored when ena=0", rdat === 32'hAAAA_AAAA);

        // TC3: Asynchronous Cross-Port Read/Write
        @(posedge clk_a); #1;
        ena = 1; wea = 1; addra = 6'd10; dina = 32'h1234_5678;
        @(posedge clk_a); #1;
        ena = 0; wea = 0;
        // Chờ domain clock B ổn định rồi đọc
        repeat(3) @(posedge clk_b);
        @(posedge clk_b); #1;
        enb = 1; web = 0; addrb = 6'd10;
        repeat(read_latency) @(posedge clk_b);
        #1; rdat = doutb; enb = 0;
        chk("TC3: Async Cross-Port Write A -> Read B", rdat === 32'h1234_5678);

        // TC4: Kiểm tra Same-Port Read-During-Write (Đúng chuẩn COLLISION_MODE)
        begin
            logic [DW-1:0] old_val = 32'h1111_1111;
            logic [DW-1:0] new_val = 32'h9999_9999;
            logic [DW-1:0] prev_dout_val;

            // B1: Ghi giá trị cũ
            write_a(6'd20, old_val);
            
            // B2: Đọc địa chỉ khác để mồi douta thành giá trị rác (Dành cho NO_CHANGE mode)
            read_a(6'd0, prev_dout_val); 

            // B3: Thực hiện Ghi đè (Read-During-Write)
            @(posedge clk_a); #1;
            ena = 1; wea = 1; addra = 6'd20; dina = new_val;
            
            // Lấy giá trị douta đẩy ra ngay sau latency
            repeat(read_latency) @(posedge clk_a);
            #1; rdat = douta;
            ena = 0; wea = 0;

            // Đánh giá dựa theo tham số của Instance này
            if (MODE_NAME == "WRITE_FIRST") begin
                chk("TC4: RDW (WRITE_FIRST) outputs NEW data", rdat === new_val);
            end else if (MODE_NAME == "READ_FIRST") begin
                chk("TC4: RDW (READ_FIRST) outputs OLD data", rdat === old_val);
            end else if (MODE_NAME == "NO_CHANGE") begin
                chk("TC4: RDW (NO_CHANGE) output remains unchanged", rdat === prev_dout_val);
            end
        end

        // Report
        if (fail_cnt > 0)
            $display(">>> [%s|OREG=%0d] FAILED %0d test(s). <<<", MODE_NAME, OREG_EN, fail_cnt);
        else
            $display(">>> [%s|OREG=%0d] PASSED ALL (%0d tests). <<<", MODE_NAME, OREG_EN, pass_cnt);
            
    end
endmodule


// --------------------------------------------------------------------------------
// TOP MODULE: Trình điều khiển chính, cấp Clock và gọi Test Suites
// --------------------------------------------------------------------------------
module tb_dual_port_ram_advanced;

    // ── 1. Tạo Asynchronous Clocks ──────────────────────────────────────────────
    // clk_a: 200 MHz (chu kỳ 5ns)
    // clk_b: 133 MHz (chu kỳ 7.5ns)
    logic clk_a = 0;
    logic clk_b = 0;
    
    always #2.5  clk_a = ~clk_a; 
    always #3.75 clk_b = ~clk_b;

    // ── 2. Khởi tạo các Test Suite với đủ mọi cấu hình ──────────────────────────
    // Suite 1: Chế độ WRITE_FIRST, Có thanh ghi ngõ ra (Latency = 2)
    ram_test_suite #(.MODE_NAME("WRITE_FIRST"), .OREG_EN(1)) suite_wf_reg (
        .clk_a(clk_a), .clk_b(clk_b)
    );

    // Suite 2: Chế độ READ_FIRST, Không thanh ghi ngõ ra (Latency = 1)
    ram_test_suite #(.MODE_NAME("READ_FIRST"), .OREG_EN(0)) suite_rf_noreg (
        .clk_a(clk_a), .clk_b(clk_b)
    );

    // Suite 3: Chế độ NO_CHANGE, Có thanh ghi ngõ ra (Latency = 2)
    ram_test_suite #(.MODE_NAME("NO_CHANGE"), .OREG_EN(1)) suite_nc_reg (
        .clk_a(clk_a), .clk_b(clk_b)
    );

    // ── 3. Watchdog & Finish ────────────────────────────────────────────────────
    initial begin
        $display("===============================================================");
        $display(" Bắt đầu chạy Comprehensive Verification cho Dual Port RAM...");
        $display("===============================================================");
        
        #50_000; // Timeout an toàn
        $display("===============================================================");
        $display(" Hoàn thành mô phỏng.");
        $display("===============================================================");
        $finish;
    end

endmodule
// ================================================================================