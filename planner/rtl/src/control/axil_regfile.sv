// ================================================================================
// VLA-HMAO TRAJECTORY PLANNING ACCELERATOR
// axil_regfile.sv — AXI-Lite CSR Register File Controller
// Spec: §17 (CSR address map), §15.1 (planning_top interface)
// ================================================================================
// Implements AXI-Lite slave interface for CSR read/write.
// Register map: §17 addresses 0x000–0x064.
// [C10 FIXED]: correct CSR addresses per §17.1, b_pending handshake, latched wr_addr

module axil_regfile
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,

  // ── AXI-Lite (PS ↔ PL) ───────────────────────────────────────────────
  // Write address channel
  input  logic [11:0]   axil_awaddr,
  input  logic          axil_awvalid,
  output logic          axil_awready,

  // Write data channel
  input  logic [31:0]   axil_wdata,
  input  logic  [3:0]   axil_wstrb,
  input  logic          axil_wvalid,
  output logic          axil_wready,

  // Write response channel
  output logic  [1:0]   axil_bresp,
  output logic          axil_bvalid,
  input  logic          axil_bready,

  // Read address channel
  input  logic [11:0]   axil_araddr,
  input  logic          axil_arvalid,
  output logic          axil_arready,

  // Read data channel
  output logic [31:0]   axil_rdata,
  output logic  [1:0]   axil_rresp,
  output logic          axil_rvalid,
  input  logic          axil_rready,

  // ── CSR outputs (to planning_top FSM) ──────────────────────────────────
  output logic          csr_start_trigger,  // 0x000[0] w1s
  output logic          csr_soft_reset,     // 0x000[1] w1s
  output logic          csr_irq_clear,      // 0x000[8] w1s  [C10 FIXED: was [2]]

  // 0x004 STATUS (read-only from PL perspective)
  input  logic [31:0]   status_in,

  // 0x008 WM_SEL
  output logic          csr_wm_sel,         // 0x008[0]

  // 0x010–0x02C WP0..WP3 (read-only)
  input  fp32_t         csr_wp_in [NUM_WAYPOINTS-1:0][2-1:0],  // [wp][0=x, 1=y]

  // 0x030 IRQ_STATUS
  input  logic [2:0]    csr_irq_flags,      // {nan_inf, wload_timeout, done}

  // 0x034 IRQ_ENABLE
  output logic [2:0]    csr_irq_en,         // {nan_inf, wload_timeout, done}

  // 0x040–0x05C CTX_SCALE/ZP interleaved (§17.1)
  output fp32_t         csr_ctx_scale [NUM_LAYERS-1:0],

  // CTX_ZP at 0x044,0x04C,0x054,0x05C (interleaved with scale)
  output logic  [7:0]   csr_ctx_zp [NUM_LAYERS-1:0],

  // 0x060–0x064 TARGET X,Y
  output fp32_t         csr_target_x,
  output fp32_t         csr_target_y
);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WRITE PATH: AXI write → CSR register update
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  logic [11:0] wr_addr;
  logic [31:0] wr_data;
  logic        aw_done;   // address phase captured
  logic        w_done;    // data phase captured
  logic        b_pending; // write response pending  [C10 FIXED]

  // Capture write address
  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n) begin
      wr_addr <= '0;
      aw_done <= 1'b0;
    end else begin
      if (axil_awvalid && axil_awready) begin
        wr_addr <= axil_awaddr;
        aw_done <= 1'b1;
      end else if (b_pending && axil_bready) begin
        aw_done <= 1'b0;
      end
    end

  // Capture write data
  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n) begin
      wr_data <= '0;
      w_done  <= 1'b0;
    end else begin
      if (axil_wvalid && axil_wready) begin
        wr_data <= axil_wdata;
        w_done  <= 1'b1;
      end else if (b_pending && axil_bready) begin
        w_done <= 1'b0;
      end
    end

  assign axil_awready = 1'b1;  // Always ready for address
  assign axil_wready  = 1'b1;  // Always ready for data

  // b_pending: set when both address and data phases complete; clear on bready
  // [C10 FIXED]: bvalid only asserts after write addr+data complete
  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n)
      b_pending <= 1'b0;
    else if ((aw_done || (axil_awvalid && axil_awready)) &&
             (w_done  || (axil_wvalid  && axil_wready)))
      b_pending <= 1'b1;
    else if (axil_bready)
      b_pending <= 1'b0;

  assign axil_bresp  = 2'b00;       // OKAY
  assign axil_bvalid = b_pending;   // [C10 FIXED]: only valid after addr+data

  // ── Write register decoder ─────────────────────────────────────────────
  // [C10 FIXED]: use captured wr_addr (not live axil_awaddr)
  // [C10 FIXED]: interleaved CTX_SCALE/ZP layout per §17.1
  // [C10 FIXED]: IRQ_CLEAR at CTRL[8], not [2]
  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n) begin
      csr_start_trigger <= '0;
      csr_soft_reset    <= '0;
      csr_irq_clear     <= '0;
      csr_wm_sel        <= '0;
      csr_irq_en        <= '0;
      for (int l = 0; l < NUM_LAYERS; l++) begin
        csr_ctx_scale[l] <= '0;
        csr_ctx_zp[l]    <= '0;
      end
      csr_target_x <= '0;
      csr_target_y <= '0;
    end else if (w_done && aw_done) begin
      // Use latched wr_addr and wr_data
      case (wr_addr[9:2])  // Byte address → word index
        8'h00: begin  // 0x000 CTRL
          if (wr_data[8:8] !== 1'bx)  // always write
            csr_irq_clear     <= wr_data[8];   // [C10 FIXED: was [2]]
          if (axil_wstrb[0]) begin
            csr_start_trigger <= wr_data[0];
            csr_soft_reset    <= wr_data[1];
          end
        end

        8'h02: begin  // 0x008 WM_SEL
          if (axil_wstrb[0])
            csr_wm_sel <= wr_data[0];
        end

        8'h0D: begin  // 0x034 IRQ_ENABLE
          if (axil_wstrb[0])
            csr_irq_en <= wr_data[2:0];
        end

        // Interleaved CTX_SCALE / CTX_ZP per §17.1
        // 0x040 CTX_SCALE_L0  word 0x10
        8'h10: if (axil_wstrb[3:0] == 4'hF) csr_ctx_scale[0] <= wr_data;
        // 0x044 CTX_ZP_L0     word 0x11
        8'h11: if (axil_wstrb[0]) csr_ctx_zp[0] <= wr_data[7:0];
        // 0x048 CTX_SCALE_L1  word 0x12
        8'h12: if (axil_wstrb[3:0] == 4'hF) csr_ctx_scale[1] <= wr_data;
        // 0x04C CTX_ZP_L1     word 0x13
        8'h13: if (axil_wstrb[0]) csr_ctx_zp[1] <= wr_data[7:0];
        // 0x050 CTX_SCALE_L2  word 0x14
        8'h14: if (axil_wstrb[3:0] == 4'hF) csr_ctx_scale[2] <= wr_data;
        // 0x054 CTX_ZP_L2     word 0x15
        8'h15: if (axil_wstrb[0]) csr_ctx_zp[2] <= wr_data[7:0];
        // 0x058 CTX_SCALE_L3  word 0x16
        8'h16: if (axil_wstrb[3:0] == 4'hF) csr_ctx_scale[3] <= wr_data;
        // 0x05C CTX_ZP_L3     word 0x17
        8'h17: if (axil_wstrb[0]) csr_ctx_zp[3] <= wr_data[7:0];

        // 0x060 TARGET_X      word 0x18
        8'h18: if (axil_wstrb[3:0] == 4'hF) csr_target_x <= wr_data;
        // 0x064 TARGET_Y      word 0x19
        8'h19: if (axil_wstrb[3:0] == 4'hF) csr_target_y <= wr_data;

        default: ; // No write for other addresses
      endcase
    end

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // READ PATH: CSR register → AXI read data
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  assign axil_arready = 1'b1;  // Always ready for read address

  // [C10 FIXED]: read decoder matches exact same addresses as write decoder
  // [C10 FIXED]: CTRL[8] readback for irq_clear
  always_ff @(posedge clk)
    if (axil_arvalid)
      case (axil_araddr[9:2])
        8'h00: axil_rdata <= {23'b0, csr_irq_clear, 6'b0, csr_soft_reset, csr_start_trigger}; // 0x000 CTRL [8]=irq_clear
        8'h01: axil_rdata <= status_in;                                                         // 0x004 STATUS
        8'h02: axil_rdata <= {31'b0, csr_wm_sel};                                              // 0x008 WM_SEL
        // 0x010–0x02C Waypoints (§17.1 WP0_X..WP3_Y)
        8'h04: axil_rdata <= csr_wp_in[0][0];   // 0x010 WP0_X
        8'h05: axil_rdata <= csr_wp_in[0][1];   // 0x014 WP0_Y
        8'h06: axil_rdata <= csr_wp_in[1][0];   // 0x018 WP1_X
        8'h07: axil_rdata <= csr_wp_in[1][1];   // 0x01C WP1_Y
        8'h08: axil_rdata <= csr_wp_in[2][0];   // 0x020 WP2_X
        8'h09: axil_rdata <= csr_wp_in[2][1];   // 0x024 WP2_Y
        8'h0A: axil_rdata <= csr_wp_in[3][0];   // 0x028 WP3_X
        8'h0B: axil_rdata <= csr_wp_in[3][1];   // 0x02C WP3_Y
        8'h0C: axil_rdata <= {29'b0, csr_irq_flags};  // 0x030 IRQ_STATUS
        8'h0D: axil_rdata <= {29'b0, csr_irq_en};     // 0x034 IRQ_ENABLE
        // Interleaved CTX_SCALE / CTX_ZP (§17.1)
        8'h10: axil_rdata <= csr_ctx_scale[0];          // 0x040 CTX_SCALE_L0
        8'h11: axil_rdata <= {24'b0, csr_ctx_zp[0]};   // 0x044 CTX_ZP_L0
        8'h12: axil_rdata <= csr_ctx_scale[1];          // 0x048 CTX_SCALE_L1
        8'h13: axil_rdata <= {24'b0, csr_ctx_zp[1]};   // 0x04C CTX_ZP_L1
        8'h14: axil_rdata <= csr_ctx_scale[2];          // 0x050 CTX_SCALE_L2
        8'h15: axil_rdata <= {24'b0, csr_ctx_zp[2]};   // 0x054 CTX_ZP_L2
        8'h16: axil_rdata <= csr_ctx_scale[3];          // 0x058 CTX_SCALE_L3
        8'h17: axil_rdata <= {24'b0, csr_ctx_zp[3]};   // 0x05C CTX_ZP_L3
        // TARGET X,Y
        8'h18: axil_rdata <= csr_target_x;              // 0x060 TARGET_X
        8'h19: axil_rdata <= csr_target_y;              // 0x064 TARGET_Y
        default: axil_rdata <= 32'hDEADBEEF;
      endcase

  assign axil_rresp  = 2'b00;  // OKAY
  assign axil_rvalid = 1'b1;   // Always valid (simplification)

endmodule
// ================================================================================
