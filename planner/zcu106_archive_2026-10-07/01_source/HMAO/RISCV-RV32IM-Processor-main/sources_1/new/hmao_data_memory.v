// =============================================================================
// FILE        : hmao_data_memory.v
// PROJECT     : HMAO Engine - RISCV DCLS Integration
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 19.1, Section 5.2
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : Replaces data_memory.v in the RISCV DCLS cores.
//               Extends the standard data_memory with an MMIO region at
//               byte address >= 0xF00 (word address >= 0x3C0).
//
//               MMIO Address Map (byte addresses in 12-bit space):
//               0xF00 HMAO_STATUS      [31:0]  R    current engine state
//               0xF04 HMAO_START       [0]     W    write 1 → single-pulse start
//               0xF08 HMAO_DECISION    [0]     R    0=VETO / 1=GRANT
//               0xF0C HMAO_IRQ_CLEAR   [0]     W    write 1 → clear HMAO_COMPLETE IRQ
//               0xF10 HMAO_VIOL_LO     [31:0]  R    violation flags [31:0]
//               0xF14 HMAO_VIOL_HI     [31:0]  R    violation flags [63:32]
//               0xF18 HMAO_LATENCY     [31:0]  R    cycle count of last run
//               0xF34 LAT_MARGIN       [15:0]  R    Q8.8 lateral margin
//               0xF38 LONG_MARGIN      [15:0]  R    Q8.8 longitudinal margin
//               0xF3C TIME_MARGIN      [15:0]  R    Q8.8 time margin
//               0xF40 DMA_STATUS       [1:0]   R    {sig_valid, traj_done}
//               0xF44 IRQ_STATUS       [0]     R    HMAO_COMPLETE pending
//
//               SRAM region: byte address < 0xF00 (same as original data_memory)
//               LATENCY: 2 cycles for both SRAM and MMIO (preserves cache timing).
// =============================================================================

`timescale 1ns/1ps

module hmao_data_memory (
    input  wire        clk,
    input  wire        reset,

    // Standard data_memory interface (identical to original data_memory.v)
    input  wire        mem_read_req,
    input  wire        mem_write_req,
    input  wire [11:0] mem_addr,
    input  wire [31:0] mem_write_data,
    output reg  [31:0] mem_read_data,
    output reg         mem_read_valid,
    output reg         mem_write_back_valid,

    // =========================================================================
    // HMAO MMIO READ INPUTS (from HMAO engine / soc_top → RISCV reads these)
    // =========================================================================
    input  wire [31:0] hmao_status,         // HMAO_STATUS register
    input  wire        hmao_decision,       // HMAO_DECISION (0=VETO, 1=GRANT)
    input  wire [31:0] hmao_viol_lo,        // HMAO_VIOLATION_FLAGS[31:0]
    input  wire [31:0] hmao_viol_hi,        // HMAO_VIOLATION_FLAGS[63:32]
    input  wire [31:0] hmao_latency,        // HMAO_LATENCY_CYCLES
    input  wire [15:0] hmao_lat_margin,     // LATERAL_MARGIN (Q8.8)
    input  wire [15:0] hmao_long_margin,    // LONGITUDINAL_MARGIN (Q8.8)
    input  wire [15:0] hmao_time_margin,    // TIME_MARGIN (Q8.8)
    input  wire        ext_irq,             // HMAO_COMPLETE interrupt pending
    input  wire        dma_traj_done,       // DMA trajectory copy complete
    input  wire        dma_sig_valid,       // IOMMU signature verified

    // =========================================================================
    // HMAO MMIO WRITE OUTPUTS (RISCV writes → drive HMAO engine)
    // =========================================================================
    output reg         mmio_start,          // HMAO_START single-cycle pulse
    output reg         mmio_irq_clear       // HMAO_IRQ_CLEAR one-cycle pulse
);

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    parameter LATENCY_CYCLE = 2;            // Must match original data_memory.v

    // MMIO region: word_addr[9:6] == 4'b1111 → byte addr >= 0xF00
    // Within MMIO: word_addr[5:0] selects register (offset in units of 4 bytes)
    localparam MMIO_WORD_BASE = 10'h3C0;    // = 960, = 12'hF00 >> 2

    // MMIO register offsets (word_addr[5:0])
    localparam MMIO_STATUS    = 6'h00;      // 0xF00 R
    localparam MMIO_START     = 6'h01;      // 0xF04 W
    localparam MMIO_DECISION  = 6'h02;      // 0xF08 R
    localparam MMIO_IRQ_CLEAR = 6'h03;      // 0xF0C W
    localparam MMIO_VIOL_LO   = 6'h04;      // 0xF10 R
    localparam MMIO_VIOL_HI   = 6'h05;      // 0xF14 R
    localparam MMIO_LATENCY   = 6'h06;      // 0xF18 R
    // 0x07 reserved (0xF1C)
    // 0x08-0x0C reserved (GPS/CAM/FRICTION/ACTUATOR/WEATHER - written by QM/BOOM, not RISCV)
    localparam MMIO_LAT_MARG  = 6'h0D;      // 0xF34 R
    localparam MMIO_LONG_MARG = 6'h0E;      // 0xF38 R
    localparam MMIO_TIME_MARG = 6'h0F;      // 0xF3C R
    localparam MMIO_DMA_STAT  = 6'h10;      // 0xF40 R {sig_valid, traj_done}
    localparam MMIO_IRQ_STAT  = 6'h11;      // 0xF44 R {31'b0, ext_irq}

    // =========================================================================
    // SRAM (same 1024-word BRAM as original data_memory.v)
    // =========================================================================
    (* ram_style = "block" *)
    reg [31:0] dmem [0:1023];

    integer dmem_i;
    initial begin
        for (dmem_i = 0; dmem_i < 1024; dmem_i = dmem_i + 1)
            dmem[dmem_i] = 32'h0;  // Zero-initialized data memory (NOP RISCV run)
    end

    // =========================================================================
    // ADDRESS DECODE
    // =========================================================================
    wire [9:0] word_addr  = mem_addr[11:2];          // 10-bit word address
    wire       is_mmio    = (word_addr[9:6] == 4'b1111); // word >= 0x3C0
    wire [5:0] mmio_off   = word_addr[5:0];           // register select within MMIO

    // =========================================================================
    // MMIO READ DATA (combinational decode - sampled in latency pipeline)
    // =========================================================================
    reg [31:0] mmio_rdata;
    always @(*) begin
        case (mmio_off)
            MMIO_STATUS:    mmio_rdata = hmao_status;
            MMIO_START:     mmio_rdata = 32'd0;           // Write-only; read returns 0
            MMIO_DECISION:  mmio_rdata = {31'd0, hmao_decision};
            MMIO_IRQ_CLEAR: mmio_rdata = 32'd0;           // Write-only; read returns 0
            MMIO_VIOL_LO:   mmio_rdata = hmao_viol_lo;
            MMIO_VIOL_HI:   mmio_rdata = hmao_viol_hi;
            MMIO_LATENCY:   mmio_rdata = hmao_latency;
            MMIO_LAT_MARG:  mmio_rdata = {16'd0, hmao_lat_margin};
            MMIO_LONG_MARG: mmio_rdata = {16'd0, hmao_long_margin};
            MMIO_TIME_MARG: mmio_rdata = {16'd0, hmao_time_margin};
            MMIO_DMA_STAT:  mmio_rdata = {30'd0, dma_sig_valid, dma_traj_done};
            MMIO_IRQ_STAT:  mmio_rdata = {31'd0, ext_irq};
            default:        mmio_rdata = 32'hDEAD_C0DE;  // Debug sentinel
        endcase
    end

    // =========================================================================
    // LATENCY PIPELINE (2-cycle, identical to original data_memory.v)
    // Ensures data_cache timing is preserved for both SRAM and MMIO accesses.
    // =========================================================================
    reg [2:0] cycle_count;

    // Capture data at the cycle before valid (cycle LATENCY_CYCLE - 1)
    always @(posedge clk) begin
        // Write to SRAM (only if NOT mmio region)
        if (mem_write_req && !is_mmio && cycle_count == LATENCY_CYCLE - 1) begin
            dmem[word_addr] <= mem_write_data;
        end
        // Read from SRAM or MMIO
        if (mem_read_req && !mem_write_req && cycle_count == LATENCY_CYCLE - 1) begin
            if (is_mmio)
                mem_read_data <= mmio_rdata;
            else
                mem_read_data <= dmem[word_addr];
        end else if (!(mem_read_req && !mem_write_req && cycle_count == LATENCY_CYCLE - 1)) begin
            mem_read_data <= 32'd0;
        end
    end

    // =========================================================================
    // CONTROL LOGIC (identical structure to original data_memory.v)
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            cycle_count          <= 3'd0;
            mem_read_valid       <= 1'b0;
            mem_write_back_valid <= 1'b0;
            mmio_start           <= 1'b0;
            mmio_irq_clear       <= 1'b0;
        end else begin
            // Default: de-assert one-cycle pulses
            mem_read_valid       <= 1'b0;
            mem_write_back_valid <= 1'b0;
            mmio_start           <= 1'b0;
            mmio_irq_clear       <= 1'b0;

            if (mem_read_req && !mem_write_req) begin
                // READ operation
                if (cycle_count < LATENCY_CYCLE - 1) begin
                    cycle_count <= cycle_count + 3'd1;
                end else begin
                    mem_read_valid <= 1'b1;
                    cycle_count    <= 3'd0;
                end
            end else if (mem_write_req) begin
                // WRITE operation
                if (cycle_count < LATENCY_CYCLE - 1) begin
                    cycle_count <= cycle_count + 3'd1;
                end else begin
                    mem_write_back_valid <= 1'b1;
                    cycle_count          <= 3'd0;

                    // MMIO WRITE DECODE: generate one-cycle output pulses
                    if (is_mmio) begin
                        case (mmio_off)
                            MMIO_START:
                                mmio_start     <= mem_write_data[0];
                            MMIO_IRQ_CLEAR:
                                mmio_irq_clear <= mem_write_data[0];
                            // All other MMIO addresses are read-only from RISCV's perspective;
                            // writes are silently ignored (spec: GPS/CAM/etc. written by QM/BOOM)
                            default: ; // no-op
                        endcase
                    end
                    // SRAM write is already handled in the clocked block above
                end
            end else begin
                cycle_count <= 3'd0;
            end
        end
    end

endmodule
