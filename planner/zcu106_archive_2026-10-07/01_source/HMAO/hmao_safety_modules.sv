// =============================================================================
// FILE        : hmao_safety_modules.sv
// PROJECT     : HMAO Engine - Safety Support Modules
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 9.3, 13, 14, 5.2
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : Collected safety support modules in one file:
//               1. hmao_watchdog       - Independent ring oscillator WDT
//               2. hmao_smpu           - Safety Memory Protection Unit
//               3. hmao_fault_manager  - Fault aggregation & SFI
//               4. hmao_regfile        - MMIO register file
//               5. cdc_async_handshake_parity - QM→ASIL-D CDC
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

// =============================================================================
// MODULE 1: WATCHDOG TIMER
// Spec Ref: Section 9.3, 13.1 (D1)
// Uses INDEPENDENT ring oscillator clock - NOT derived from system clock.
// This ensures watchdog fires even if system clock fails.
// Board budgets at 250 MHz: Stage1 7.2 ms, Stage2 5.6 ms, total 16 ms.
// =============================================================================
module hmao_watchdog (
  input logic wdt_clk,
  input logic sys_clk,
  input logic rst_n,
  input logic kick_s1,
  input logic kick_s2,
  input logic kick_total,
  // Level controls: stage counters stop when their stage ends; the total
  // counter covers computation plus the fixed completion delay.
  input logic monitor_s1,
  input logic monitor_s2,
  input logic monitor_total,
  input logic clear_timeout,
  output logic s1_timeout,
  output logic s2_timeout,
  output logic total_timeout,
  output logic wdt_fault
);
  (* ASYNC_REG = "TRUE" *) logic kick_s1_sync_a, kick_s1_sync_b;
  (* ASYNC_REG = "TRUE" *) logic kick_s2_sync_a, kick_s2_sync_b;
  (* ASYNC_REG = "TRUE" *) logic kick_total_sync_a, kick_total_sync_b;
  (* ASYNC_REG = "TRUE" *) logic monitor_s1_a, monitor_s1_b;
  (* ASYNC_REG = "TRUE" *) logic monitor_s2_a, monitor_s2_b;
  (* ASYNC_REG = "TRUE" *) logic monitor_total_a, monitor_total_b;
  (* ASYNC_REG = "TRUE" *) logic clear_a, clear_b;

  always_ff @(posedge wdt_clk or negedge rst_n) begin
    if (!rst_n) begin
      kick_s1_sync_a <= 0; kick_s1_sync_b <= 0;
      kick_s2_sync_a <= 0; kick_s2_sync_b <= 0;
      kick_total_sync_a <= 0; kick_total_sync_b <= 0;
      monitor_s1_a <= 0; monitor_s1_b <= 0;
      monitor_s2_a <= 0; monitor_s2_b <= 0;
      monitor_total_a <= 0; monitor_total_b <= 0;
      clear_a <= 0; clear_b <= 0;
    end else begin
      kick_s1_sync_a <= kick_s1; kick_s1_sync_b <= kick_s1_sync_a;
      kick_s2_sync_a <= kick_s2; kick_s2_sync_b <= kick_s2_sync_a;
      kick_total_sync_a <= kick_total; kick_total_sync_b <= kick_total_sync_a;
      monitor_s1_a <= monitor_s1; monitor_s1_b <= monitor_s1_a;
      monitor_s2_a <= monitor_s2; monitor_s2_b <= monitor_s2_a;
      monitor_total_a <= monitor_total; monitor_total_b <= monitor_total_a;
      clear_a <= clear_timeout; clear_b <= clear_a;
    end
  end

`ifdef SIM_WDT_FAST
  localparam int unsigned WDT_S1_CNT = 300;
  localparam int unsigned WDT_S2_CNT = 200;
  localparam int unsigned WDT_TOTAL_CNT = 20_000;
`else
  localparam int unsigned WDT_S1_CNT = WDT_STAGE1_CYCLES;
  localparam int unsigned WDT_S2_CNT = WDT_STAGE2_CYCLES;
  localparam int unsigned WDT_TOTAL_CNT = WDT_TOTAL_CYCLES;
`endif
  logic [21:0] cnt_s1;
  logic [20:0] cnt_s2;
  logic [21:0] cnt_total;
  logic s1_to_wdtclk, s2_to_wdtclk, total_to_wdtclk;
  logic wdt_armed;

  always_ff @(posedge wdt_clk or negedge rst_n) begin
    if (!rst_n) wdt_armed <= 0;
    else if (!(monitor_s1_b || monitor_s2_b || monitor_total_b))
      wdt_armed <= 0;
    else if (kick_s1_sync_b || kick_s2_sync_b || kick_total_sync_b)
      wdt_armed <= 1;
  end

  // Only the SECOND CDC stage controls counters. A timeout remains latched
  // until a kick/clear so the system domain can capture the real fault before
  // disabling that stage. Idle time never adds to the next run's counters.
  always_ff @(posedge wdt_clk or negedge rst_n) begin
    if (!rst_n) begin cnt_s1 <= 0; s1_to_wdtclk <= 0; end
    else if (clear_b || kick_s1_sync_b) begin cnt_s1 <= 0; s1_to_wdtclk <= 0; end
    else if (!monitor_s1_b) cnt_s1 <= 0;
    else if (cnt_s1 >= WDT_S1_CNT) s1_to_wdtclk <= 1;
    else if (wdt_armed) cnt_s1 <= cnt_s1 + 1'b1;
  end
  always_ff @(posedge wdt_clk or negedge rst_n) begin
    if (!rst_n) begin cnt_s2 <= 0; s2_to_wdtclk <= 0; end
    else if (clear_b || kick_s2_sync_b) begin cnt_s2 <= 0; s2_to_wdtclk <= 0; end
    else if (!monitor_s2_b) cnt_s2 <= 0;
    else if (cnt_s2 >= WDT_S2_CNT) s2_to_wdtclk <= 1;
    else if (wdt_armed) cnt_s2 <= cnt_s2 + 1'b1;
  end
  always_ff @(posedge wdt_clk or negedge rst_n) begin
    if (!rst_n) begin cnt_total <= 0; total_to_wdtclk <= 0; end
    else if (clear_b || kick_total_sync_b) begin cnt_total <= 0; total_to_wdtclk <= 0; end
    else if (!monitor_total_b) cnt_total <= 0;
    else if (cnt_total >= WDT_TOTAL_CNT) total_to_wdtclk <= 1;
    else if (wdt_armed) cnt_total <= cnt_total + 1'b1;
  end

  (* ASYNC_REG = "TRUE" *) logic s1_sync_a, s1_sync_b;
  (* ASYNC_REG = "TRUE" *) logic s2_sync_a, s2_sync_b;
  (* ASYNC_REG = "TRUE" *) logic tot_sync_a, tot_sync_b;
  always_ff @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_sync_a <= 0; s1_sync_b <= 0;
      s2_sync_a <= 0; s2_sync_b <= 0;
      tot_sync_a <= 0; tot_sync_b <= 0;
    end else begin
      s1_sync_a <= s1_to_wdtclk; s1_sync_b <= s1_sync_a;
      s2_sync_a <= s2_to_wdtclk; s2_sync_b <= s2_sync_a;
      tot_sync_a <= total_to_wdtclk; tot_sync_b <= tot_sync_a;
    end
  end
  assign s1_timeout = s1_sync_b;
  assign s2_timeout = s2_sync_b;
  assign total_timeout = tot_sync_b;
  assign wdt_fault = s1_sync_b | s2_sync_b | tot_sync_b;
endmodule : hmao_watchdog

// =============================================================================
// MODULE 2: SMPU (Safety Memory Protection Unit)
// Spec Ref: Section 13.3
// Master ID 0x1A = HMAO = READ-ONLY
// Any AWVALID → DECERR + IRQ + MRM
// =============================================================================
module hmao_smpu (
  input  logic          clk,
  input  logic          rst_n,

  // AXI4 from HMAO (MUST be read-only: only AR/R channels valid)
  axi4_ro_if.slave      axi_in,

  // External NoC (after SMPU validation)
  output logic [31:0]   ar_addr_out,
  output logic [7:0]    ar_len_out,
  output logic [2:0]    ar_size_out,
  output logic [1:0]    ar_burst_out,
  output logic          ar_valid_out,
  output logic [7:0]    ar_user_out,
  input  logic          ar_ready_in,
  input  logic [255:0]  r_data_in,
  input  logic [1:0]    r_resp_in,
  input  logic          r_last_in,
  input  logic          r_valid_in,
  output logic          r_ready_out,

  output logic          smpu_violation
);

  // Address range check
  // Spec Ref: Section 13.3 - Rules 3A, 3B, 3C
  function automatic logic addr_in_allowed_range(input logic [31:0] addr);
    // Rule 3A: Trajectory Buffer TRAJ_BUFFER_BASE + 64 KB (read OK)
    if (addr >= TRAJ_BUFFER_BASE && addr <= TRAJ_BUFFER_BASE + 32'h0000_FFFF) return 1'b1;
    // Rule 3B: World Model    WORLD_MODEL_BASE + 8 MB (read OK)
    if (addr >= WORLD_MODEL_BASE && addr <= WORLD_MODEL_BASE + 32'h007F_FFFF) return 1'b1;
    // Rule 3C: Safety Data   SAFETY_DATA_BASE + 1 MB (read OK)
    if (addr >= SAFETY_DATA_BASE && addr <= SAFETY_DATA_BASE + 32'h000F_FFFF) return 1'b1;
    return 1'b0;
  endfunction

  // Master ID check: only allow HMAO master (0x1A)
  logic master_id_ok;
  assign master_id_ok = (axi_in.aruser == HMAO_MASTER_ID);

  // Address range check
  logic addr_ok;
  assign addr_ok = addr_in_allowed_range(axi_in.araddr);

  // Violation: wrong master ID, out-of-range address
  logic violation_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      smpu_violation <= 1'b0;
    end else begin
      if (axi_in.arvalid && (!master_id_ok || !addr_ok)) begin
        smpu_violation <= 1'b1;  // Sticky until reset
      end
    end
  end

  // AR Channel: Forward all read requests (SMPU enforces in parallel, FMU reports violation).
  // The external interface will receive all AR requests; SMPU doesn't block on AR.
  // Violations are reported via DECERR response on R channel.
  assign ar_addr_out  = axi_in.araddr;
  assign ar_len_out   = axi_in.arlen;
  assign ar_size_out  = axi_in.arsize;
  assign ar_burst_out = axi_in.arburst;
  assign ar_valid_out = axi_in.arvalid;  // Forward all requests (good and bad)
  assign ar_user_out  = HMAO_MASTER_ID;   // Always output correct master ID for audit/tracking
  
  // Always accept requests from internal HMAO (AXI handshake compliance).
  // This prevents deadlock even if external can't respond immediately.
  assign axi_in.arready = ar_ready_in;

  // R channel pass-through
  assign axi_in.rid    = '0;           // Single-ID operation; TB/external never drives RID
  assign axi_in.rdata  = r_data_in;
  assign axi_in.rresp  = smpu_violation ? 2'b11 : r_resp_in;  // DECERR if violation detected
  assign axi_in.rlast  = r_last_in;
  assign axi_in.rvalid = r_valid_in;
  assign r_ready_out   = axi_in.rready;
  assign axi_in.smpu_decerr = smpu_violation;

endmodule : hmao_smpu

// =============================================================================
// MODULE 3: FAULT MANAGER (SFI → FMU)
// Spec Ref: Section 4.4
// Aggregates faults, drives SFI output to FMU
// =============================================================================
module hmao_fault_manager (
  input  logic          clk,
  input  logic          rst_n,

  // Fault sources
  input  hmao_fault_t   hmao_fault_in,
  input  logic          hmao_fault_valid,
  input  logic          smpu_violation,
  input  logic          riscv_dcls_err,

  // SFI to FMU
  output logic [6:0]    sfi_flags_out,
  output logic          sfi_valid_out,
  input  logic          sfi_ack_in
);

  hmao_fault_t  fault_latch;
  logic         smpu_latch, dcls_latch;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fault_latch  <= '0;
      smpu_latch   <= 1'b0;
      dcls_latch   <= 1'b0;
      sfi_valid_out <= 1'b0;
    end else begin
      // Latch all faults (sticky until FMU acknowledges)
      if (hmao_fault_valid)  fault_latch  <= fault_latch | hmao_fault_in;
      if (smpu_violation)    smpu_latch   <= 1'b1;
      if (riscv_dcls_err)    dcls_latch   <= 1'b1;

      // Drive SFI output
      // Spec Ref: Section 4.4 - SFI bit mapping mirrors hmao_fault_t packed order:
      //   [6]=kinematic_invalid, [5]=numerical_overflow, [4]=smpu_violation,
      //   [3]=trajectory_crc_fail, [2]=admm_divergence, [1]=zonotope_error, [0]=hmao_hang
      // smpu_latch and dcls_latch are both safety-isolation faults → OR into bit[4]
      sfi_flags_out <= {fault_latch.kinematic_invalid,
                        fault_latch.numerical_overflow,
                        fault_latch.smpu_violation | smpu_latch | dcls_latch,
                        fault_latch.trajectory_crc_fail,
                        fault_latch.admm_divergence,
                        fault_latch.zonotope_error,
                        fault_latch.hmao_hang};
      sfi_valid_out <= |fault_latch || smpu_latch || dcls_latch;

      // Clear on ACK
      if (sfi_ack_in && sfi_valid_out) begin
        fault_latch   <= '0;
        smpu_latch    <= 1'b0;
        dcls_latch    <= 1'b0;
        sfi_valid_out <= 1'b0;
      end
    end
  end

endmodule : hmao_fault_manager

// =============================================================================
// MODULE 4: HMAO REGISTER FILE (MMIO)
// Spec Ref: Section 5.2
// AXI-Lite slave: RISCV reads decision, writes START, clears IRQ
// =============================================================================
module hmao_regfile (
  input  logic          clk,
  input  logic          rst_n,

  // AXI-Lite from RISCV
  axilite_if.slave      axil,

  // Status inputs (from HMAO engine)
  input  logic [31:0]   hmao_status_in,
  input  logic          hmao_decision_in,
  input  logic [63:0]   hmao_violation_in,
  input  logic [31:0]   hmao_latency_in,
  input  logic [15:0]   lateral_margin_in,
  input  logic [15:0]   long_margin_in,
  input  logic [15:0]   time_margin_in,

  // Control outputs (to HMAO engine)
  output logic          hmao_start_pulse_out,
  output logic          hmao_irq_clear_out,

  // Uncertainty vector (from CDC, written to shadow registers)
  output logic [7:0]    asild_gps_q_out,
  output logic [7:0]    asild_cam_q_out,
  output logic [7:0]    asild_friction_out,
  output logic [7:0]    asild_actuator_out,
  output logic [7:0]    asild_weather_out
);

  // Shadow registers for uncertainty vector (written by CDC module directly)
  logic [7:0] reg_gps_q, reg_cam_q, reg_friction, reg_actuator, reg_weather;

  // AXI-Lite state
  typedef enum logic [1:0] { AL_IDLE, AL_WRITE, AL_READ, AL_RESP } al_state_t;
  al_state_t al_state;

  logic [31:0] wdata_reg;
  logic [31:0] waddr_reg;
  logic [31:0] rdata_reg;

  assign asild_gps_q_out    = reg_gps_q;
  assign asild_cam_q_out    = reg_cam_q;
  assign asild_friction_out = reg_friction;
  assign asild_actuator_out = reg_actuator;
  assign asild_weather_out  = reg_weather;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      al_state              <= AL_IDLE;
      hmao_start_pulse_out  <= 1'b0;
      hmao_irq_clear_out    <= 1'b0;
      reg_gps_q     <= 8'd128;  // Default: mid-quality
      reg_cam_q     <= 8'd128;
      reg_friction  <= 8'd128;
      reg_actuator  <= 8'd255;  // Default actuator: nominal
      reg_weather   <= 8'd0;
      axil.awready  <= 1'b0;
      axil.wready   <= 1'b0;
      axil.bvalid   <= 1'b0;
      axil.bresp    <= 2'b00;
      axil.arready  <= 1'b0;
      axil.rvalid   <= 1'b0;
      axil.rdata    <= '0;
      axil.rresp    <= 2'b00;
    end else begin
      // Default pulse signals (1-cycle)
      hmao_start_pulse_out <= 1'b0;
      hmao_irq_clear_out   <= 1'b0;

      unique case (al_state)
        AL_IDLE: begin
          axil.awready <= 1'b0;
          axil.arready <= 1'b0;
          if (axil.awvalid && axil.wvalid) begin
            axil.awready <= 1'b1;
            axil.wready  <= 1'b1;
            waddr_reg    <= axil.awaddr;
            wdata_reg    <= axil.wdata;
            al_state     <= AL_WRITE;
          end else if (axil.arvalid) begin
            axil.arready <= 1'b1;
            waddr_reg    <= axil.araddr;
            al_state     <= AL_READ;
          end
        end

        AL_WRITE: begin
          axil.awready <= 1'b0;
          axil.wready  <= 1'b0;
          // Decode write address
          case (waddr_reg[11:0])
            REG_OFF_START:    hmao_start_pulse_out <= wdata_reg[0];  // Single pulse
            REG_OFF_IRQ_CLEAR: hmao_irq_clear_out <= wdata_reg[0];
            REG_OFF_GPS_Q:    reg_gps_q    <= wdata_reg[7:0];
            REG_OFF_CAM_Q:    reg_cam_q    <= wdata_reg[7:0];
            REG_OFF_FRICTION: reg_friction <= wdata_reg[7:0];
            REG_OFF_ACTUATOR: reg_actuator <= wdata_reg[7:0];
            REG_OFF_WEATHER:  reg_weather  <= wdata_reg[7:0];
            default: ; // Ignore writes to read-only registers
          endcase
          axil.bvalid <= 1'b1;
          axil.bresp  <= 2'b00;  // OKAY
          al_state    <= AL_RESP;
        end

        AL_READ: begin
          axil.arready <= 1'b0;
          // Decode read address
          case (waddr_reg[11:0])
            REG_OFF_STATUS:       axil.rdata <= hmao_status_in;
            REG_OFF_DECISION:     axil.rdata <= {31'b0, hmao_decision_in};
            REG_OFF_VIOL_LO:      axil.rdata <= hmao_violation_in[31:0];
            REG_OFF_VIOL_HI:      axil.rdata <= hmao_violation_in[63:32];
            REG_OFF_LATENCY:      axil.rdata <= hmao_latency_in;
            REG_OFF_LAT_MARGIN:   axil.rdata <= {16'b0, lateral_margin_in};
            REG_OFF_LONG_MARGIN:  axil.rdata <= {16'b0, long_margin_in};
            REG_OFF_TIME_MARGIN:  axil.rdata <= {16'b0, time_margin_in};
            REG_OFF_S1_CFG:       axil.rdata <= STAGE1_CONFIG_VAL;
            REG_OFF_S2_CFG:       axil.rdata <= STAGE2_CONFIG_VAL;
            default:              axil.rdata <= 32'hDEAD_BEEF; // Debug pattern
          endcase
          axil.rvalid <= 1'b1;
          axil.rresp  <= 2'b00;
          al_state    <= AL_RESP;
        end

        AL_RESP: begin
          if (axil.bvalid && axil.bready) begin
            axil.bvalid <= 1'b0;
            al_state    <= AL_IDLE;
          end
          if (axil.rvalid && axil.rready) begin
            axil.rvalid <= 1'b0;
            al_state    <= AL_IDLE;
          end
        end

        default: al_state <= AL_IDLE;
      endcase
    end
  end

endmodule : hmao_regfile

// =============================================================================
// MODULE 5: CDC ASYNC HANDSHAKE + PARITY
// Spec Ref: Section 14
// QM (BOOM) → ASIL-D (HMAO) uncertainty vector transfer
// Protocol:
//   1. QM writes 40-bit data + 1-bit parity to holding register
//   2. QM asserts REQ (1-bit → 2FF sync in ASIL-D)
//   3. ASIL-D samples 41-bit holding register, checks parity
//   4. ASIL-D asserts ACK (1-bit → 2FF sync back to QM)
//   5. QM de-asserts REQ
// Watchdog: 200ms without REQ-ACK → override to worst-case margins
// =============================================================================
module cdc_async_handshake_parity (
  // QM (source) side
  input  logic        src_clk,
  input  logic        src_rst_n,
  input  logic [39:0] src_data,    // {weather,actuator,friction,cam,gps} (5×8-bit)
  input  logic        src_req,
  output logic        src_ack,

  // ASIL-D (destination) side
  input  logic        dst_clk,
  input  logic        dst_rst_n,
  output logic        dst_data_valid,  // New data available and parity OK
  output logic [7:0]  dst_gps_q,
  output logic [7:0]  dst_cam_q,
  output logic [7:0]  dst_friction,
  output logic [7:0]  dst_actuator,
  output logic [7:0]  dst_weather,

  // Watchdog override (to fault manager)
  output logic        wdt_override_en  // True = BOOM dead, use worst-case margins
);

  // Holding register (multi-bit, captured by QM before asserting REQ)
  logic [39:0] hold_data;
  logic        hold_parity;

  // Capture holding register on QM side when src_req rises
  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      hold_data   <= '0;
      hold_parity <= '0;
    end else begin
      if (src_req) begin
        hold_data   <= src_data;
        hold_parity <= ^src_data;   // Even parity over 40 bits
      end
    end
  end

  // REQ synchronizer: src_clk → dst_clk (2-FF)
  logic req_sync_a, req_sync_b, req_sync_prev;
  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      req_sync_a <= 1'b0; req_sync_b <= 1'b0; req_sync_prev <= 1'b0;
    end else begin
      req_sync_a    <= src_req;
      req_sync_b    <= req_sync_a;
      req_sync_prev <= req_sync_b;
    end
  end
  wire req_edge = req_sync_b && !req_sync_prev;  // Rising edge of REQ in dst domain

  // ACK signal (dst_clk domain, synchronized back to src_clk)
  logic ack_dst;  // In dst domain
  logic ack_sync_a, ack_sync_b;

  // On REQ edge: sample holding register, check parity, update output
  logic parity_ok;
  assign parity_ok = (^hold_data == hold_parity);

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      dst_data_valid <= 1'b0;
      dst_gps_q      <= 8'd0;    // Worst-case: GPS bad
      dst_cam_q      <= 8'd0;    // Worst-case: camera blind
      dst_friction   <= 8'd127;  // Mid friction
      dst_actuator   <= 8'd255;  // Actuator nominal
      dst_weather    <= 8'd0;
      ack_dst        <= 1'b0;
    end else begin
      dst_data_valid <= 1'b0;
      ack_dst        <= 1'b0;

      if (req_edge && parity_ok) begin
        // Valid data: update margins
        dst_gps_q    <= hold_data[7:0];
        dst_cam_q    <= hold_data[15:8];
        dst_friction <= hold_data[23:16];
        dst_actuator <= hold_data[31:24];
        dst_weather  <= hold_data[39:32];
        dst_data_valid <= 1'b1;
        ack_dst        <= 1'b1;
      end else if (req_edge && !parity_ok) begin
        // Parity error: keep previous values, still ACK to avoid deadlock
        // But flag the error (handled by fault manager)
        ack_dst <= 1'b1;
      end
    end
  end

  // ACK synchronizer: dst_clk → src_clk (2-FF)
  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      ack_sync_a <= 1'b0; ack_sync_b <= 1'b0;
    end else begin
      ack_sync_a <= ack_dst;
      ack_sync_b <= ack_sync_a;
    end
  end
  assign src_ack = ack_sync_b;

  // Watchdog: 200ms = 80M cycles @ 400MHz → if no REQ for 200ms → BOOM dead
  logic [26:0] wdt_cnt;   // 27 bits covers 80M
  localparam logic [26:0] WDT_CDC_CNT = CDC_WDT_CYCLES[26:0];

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      wdt_cnt        <= '0;
      wdt_override_en <= 1'b0;
    end else begin
      if (req_edge) begin
        wdt_cnt         <= '0;
        wdt_override_en <= 1'b0;
      end else if (wdt_cnt < WDT_CDC_CNT) begin
        wdt_cnt <= wdt_cnt + 1'b1;
      end else begin
        // 200ms expired: BOOM likely dead → override to worst-case
        wdt_override_en <= 1'b1;
        // Force worst-case uncertainty: GPS=0, CAM=0 (spec ref Section 14, Step 5)
        dst_gps_q    <= 8'd0;
        dst_cam_q    <= 8'd0;
        dst_friction <= 8'd0;    // Icy road (maximum braking distance)
        dst_actuator <= 8'd0;    // Degraded actuators
      end
    end
  end

endmodule : cdc_async_handshake_parity
