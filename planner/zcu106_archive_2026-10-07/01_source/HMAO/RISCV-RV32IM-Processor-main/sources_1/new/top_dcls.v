// =============================================================================
// FILE        : top_dcls.v
// PROJECT     : HMAO Engine - RISCV DCLS Core Wrapper
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 2.2 (SLR1 ASIL-D)
//               Section 19.1 (RISCV post-HMAO WCET), Section 19.2
// SAFETY      : ASIL-D (ISO 26262) - One instance per DCLS core
// DESCRIPTION : Modified version of top.v adapted for DCLS integration.
//               Key changes from original top.v:
//               1. data_memory replaced with hmao_data_memory (MMIO support)
//               2. MMIO signals exposed as module ports for DCLS voter access
//               3. led/led_riscv_start outputs removed (not needed in ASIL-D)
//               4. riscv_start tied high externally (continuous firmware execution)
//               5. instruction_memory readmemh re-enabled
//               6. Active-HIGH reset retained (matches top.v convention)
//
//               MMIO Firmware Map (12-bit byte addresses):
//               0xF00 = HMAO_STATUS   (read)
//               0xF04 = HMAO_START    (write 1)
//               0xF08 = HMAO_DECISION (read)
//               0xF0C = HMAO_IRQ_CLEAR(write 1)
//               0xF10 = VIOL_LO       (read)
//               0xF14 = VIOL_HI       (read)
//               0xF18 = LATENCY       (read)
//               0xF34 = LAT_MARGIN    (read)
//               0xF38 = LONG_MARGIN   (read)
//               0xF3C = TIME_MARGIN   (read)
//               0xF40 = DMA_STATUS    (read) bit1=sig_valid, bit0=traj_done
//               0xF44 = IRQ_STATUS    (read) bit0=ext_irq
// =============================================================================

`timescale 1ns/1ps

module top_dcls (
    input  wire        clk,
    input  wire        reset,       // Active-HIGH (synchronous within pipeline)
    input  wire        riscv_start, // Gate pipeline execution (tie to 1 in DCLS mode)
    output wire        riscv_done,  // ECALL reached (not used in DCLS firmware loop)

    // =========================================================================
    // HMAO MMIO READ INPUTS (from soc_top → RISCV reads HMAO register values)
    // Spec Ref: Section 5.2 register map, Section 19.2 WCET sequence
    // =========================================================================
    input  wire [31:0] hmao_status,
    input  wire        hmao_decision,
    input  wire [31:0] hmao_viol_lo,
    input  wire [31:0] hmao_viol_hi,
    input  wire [31:0] hmao_latency,
    input  wire [15:0] hmao_lat_margin,
    input  wire [15:0] hmao_long_margin,
    input  wire [15:0] hmao_time_margin,
    input  wire        ext_irq,         // HMAO_COMPLETE interrupt
    input  wire        dma_traj_done,   // DMA copy complete
    input  wire        dma_sig_valid,   // IOMMU signature OK

    // =========================================================================
    // HMAO MMIO WRITE OUTPUTS (RISCV drives HMAO engine)
    // Spec Ref: Section 3.4 HMAO_START, Section 4.3 IRQ clear
    // =========================================================================
    output wire        mmio_start,      // HMAO_START pulse (single-cycle)
    output wire        mmio_irq_clear   // HMAO_IRQ_CLEAR pulse (single-cycle)
);

    // =========================================================================
    // INTERNAL CACHE / MEMORY BUS WIRES (identical to original top.v)
    // =========================================================================

    // I-Cache interface
    wire        icache_read_req, icache_hit, icache_stall;
    wire [11:0] icache_addr;
    wire [31:0] icache_read_data;

    // D-Cache interface
    wire        dcache_read_req, dcache_write_req, dcache_hit, dcache_stall;
    wire [11:0] dcache_addr;
    wire [31:0] dcache_write_data, dcache_read_data;

    // Instruction memory bus
    wire        imem_read_req, imem_read_valid;
    wire [11:0] imem_addr;
    wire [63:0] imem_read_data;

    // Data memory bus (connects to hmao_data_memory)
    wire        dmem_read_req, dmem_write_req, dmem_read_valid, dmem_write_back_valid;
    wire [11:0] dmem_addr;
    wire [31:0] dmem_write_data, dmem_read_data;

    wire        flush_top;
    wire        mem_unsigned_top;
    wire [1:0]  mem_size_top;

    // =========================================================================
    // SYNCHRONOUS RESET (3-FF sync chain, identical to top.v)
    // =========================================================================
    reg [2:0] reset_sync = 3'b111;
    wire      sync_reset;

    always @(posedge clk) begin
        reset_sync <= {reset_sync[1:0], reset};
    end
    assign sync_reset = reset_sync[2];

    // =========================================================================
    // RISC-V PIPELINE
    // =========================================================================
    riscv_pipeline RISCV (
        .clk              (clk),
        .reset            (sync_reset),
        .riscv_start      (riscv_start),
        .riscv_done       (riscv_done),
        .icache_read_req  (icache_read_req),
        .icache_addr      (icache_addr),
        .icache_read_data (icache_read_data),
        .icache_hit       (icache_hit),
        .icache_stall     (icache_stall),
        .dcache_read_req  (dcache_read_req),
        .dcache_write_req (dcache_write_req),
        .dcache_addr      (dcache_addr),
        .dcache_write_data(dcache_write_data),
        .dcache_read_data (dcache_read_data),
        .dcache_hit       (dcache_hit),
        .dcache_stall     (dcache_stall),
        .flush_top        (flush_top),
        .mem_size_top     (mem_size_top),
        .mem_unsigned_top (mem_unsigned_top)
    );

    // =========================================================================
    // INSTRUCTION CACHE
    // =========================================================================
    instruction_cache IC (
        .clk              (clk),
        .reset            (sync_reset),
        .flush            (flush_top),
        .cpu_read_req     (icache_read_req),
        .cpu_addr         (icache_addr),
        .cpu_read_data    (icache_read_data),
        .icache_hit       (icache_hit),
        .icache_stall     (icache_stall),
        .mem_read_req     (imem_read_req),
        .mem_addr         (imem_addr),
        .mem_read_data    (imem_read_data),
        .mem_read_valid   (imem_read_valid)
    );

    // =========================================================================
    // DATA CACHE
    // =========================================================================
    data_cache DC (
        .clk                  (clk),
        .reset                (sync_reset),
        .cpu_read_req         (dcache_read_req),
        .cpu_write_req        (dcache_write_req),
        .cpu_addr             (dcache_addr),
        .cpu_write_data       (dcache_write_data),
        .mem_unsigned         (mem_unsigned_top),
        .mem_size             (mem_size_top),
        .cpu_read_data        (dcache_read_data),
        .dcache_hit           (dcache_hit),
        .dcache_stall         (dcache_stall),
        .mem_read_req         (dmem_read_req),
        .mem_write_req        (dmem_write_req),
        .mem_addr             (dmem_addr),
        .mem_write_data       (dmem_write_data),
        .mem_read_data        (dmem_read_data),
        .mem_read_valid       (dmem_read_valid),
        .mem_write_back_valid (dmem_write_back_valid)
    );

    // =========================================================================
    // INSTRUCTION MEMORY
    // =========================================================================
    instruction_memory IM (
        .clk            (clk),
        .reset          (sync_reset),
        .flush          (flush_top),
        .mem_read_req   (imem_read_req),
        .mem_addr       (imem_addr),
        .mem_read_data  (imem_read_data),
        .mem_read_valid (imem_read_valid)
    );

    // =========================================================================
    // DATA MEMORY WITH HMAO MMIO (replaces original data_memory)
    // Spec Ref: Section 5.2, Section 19.2
    // =========================================================================
    hmao_data_memory DM (
        .clk                  (clk),
        .reset                (sync_reset),

        // Standard data_cache ↔ memory bus
        .mem_read_req         (dmem_read_req),
        .mem_write_req        (dmem_write_req),
        .mem_addr             (dmem_addr),
        .mem_write_data       (dmem_write_data),
        .mem_read_data        (dmem_read_data),
        .mem_read_valid       (dmem_read_valid),
        .mem_write_back_valid (dmem_write_back_valid),

        // HMAO MMIO read inputs
        .hmao_status          (hmao_status),
        .hmao_decision        (hmao_decision),
        .hmao_viol_lo         (hmao_viol_lo),
        .hmao_viol_hi         (hmao_viol_hi),
        .hmao_latency         (hmao_latency),
        .hmao_lat_margin      (hmao_lat_margin),
        .hmao_long_margin     (hmao_long_margin),
        .hmao_time_margin     (hmao_time_margin),
        .ext_irq              (ext_irq),
        .dma_traj_done        (dma_traj_done),
        .dma_sig_valid        (dma_sig_valid),

        // HMAO MMIO write outputs
        .mmio_start           (mmio_start),
        .mmio_irq_clear       (mmio_irq_clear)
    );

endmodule
