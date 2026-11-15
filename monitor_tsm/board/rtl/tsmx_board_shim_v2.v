// Claude 10/11/2026: tsmx_board_shim_v2 = tsmx_board_shim (04/11, unchanged otherwise) + board time base.
//   Added for the VCU118 joint run: the design requires the time input to be sampled at least once per us
//   (spec 6.2); firmware writes of TIME_US in 100 ms steps (ZCU106 run) do not meet that. CTRL.bit1 makes
//   TIME_US advance by 1 every US_DIV core clocks (US_DIV=100 at the 100 MHz core clock); a TIME_US write
//   still loads the counter. Board glue only: m_tsmx_top is untouched.
//   New read-only registers: 0x02C FREE_CYC (free-running core-clock counter, firmware timestamps),
//   0x030 BRAKE_T_US / 0x034 BRAKE_CYC (TIME_US and FREE_CYC at the first brake 0->1 after BRAKE_ARM),
//   0x038 BRAKE_ARM (W: any write re-arms the brake-rise capture; R: bit0 captured).
//   CTRL.bit2 ACK_HOLD: i_ack_valid held high (with ACK_SEQ) while set: an executor that acknowledges a plan
//                    whose apply lies beyond 40 ms must keep the acknowledgement present (spec 6.2).
//   0x03C TIME_ACK  (W: loads TIME_US and pulses ACK (ACK_SEQ) in the same clock, as the reference benches
//                    present time and acknowledgement together; R: TIME_US).
// Claude 04/11/2026: ZCU106 board shim for TSM-X (PARA_DIRECT=0).
// Firmware owns time_us, ACK and per-job reset so a board run replays the
// board-equivalent simulation (tb/board/tb_tsmx_stream.sv) transaction by transaction.
//
// AXI4-Lite register map (byte offsets, 32-bit):
//   0x000 CTRL      W/R  bit0 core_run (0 = hold TSM-X core in reset)
//   0x004 TIME_US   W/R  drives i_time_us
//   0x008 ACK_SEQ   W/R  drives i_ack_seq
//   0x00C ACK_PULSE W    any write: i_ack_valid high for exactly one clock
//   0x010 RSP_STAT  R    bit0 o_rsp_valid, bit1 o_brake, bit2 o_heartbeat, bit3 o_int_irq,
//                        bit4 cycles_valid, bit5 log_done, bit6 o_rx_ready
//                   W    any write: i_rsp_ready high for exactly one clock (consume response)
//   0x014 RSP_LO    R    o_rsp_data[31:0]
//   0x018 RSP_HI    R    o_rsp_data[37:32]
//   0x01C CYCLES    R    clocks from rx last-beat accept to first o_rsp_valid (cleared at next frame start)
//   0x020 LOG_GO    W    bits9:0 = log index; starts one recorder read; RSP_STAT.bit5 when done
//   0x024 HB_EDGES  R    heartbeat edge counter
//   0x028 ID        R    0x75B0A1D4 (design id)
//   0x100..0x180 LOG_DATA R  33 words, word k = o_log_data[32k+31:32k] (bits above 1055 read 0)
`timescale 1ns/1ps
`default_nettype none
module tsmx_board_shim_v2 #(parameter integer US_DIV = 100) (
  input  wire        clk,
  input  wire        rst_n,
  // AXI4-Lite slave
  input  wire [11:0] s_axi_awaddr,
  input  wire        s_axi_awvalid,
  output reg         s_axi_awready,
  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,
  input  wire        s_axi_wvalid,
  output reg         s_axi_wready,
  output reg  [1:0]  s_axi_bresp,
  output reg         s_axi_bvalid,
  input  wire        s_axi_bready,
  input  wire [11:0] s_axi_araddr,
  input  wire        s_axi_arvalid,
  output reg         s_axi_arready,
  output reg  [31:0] s_axi_rdata,
  output reg  [1:0]  s_axi_rresp,
  output reg         s_axi_rvalid,
  input  wire        s_axi_rready,
  // TSM-X side
  output wire        core_rst_n,
  output reg  [31:0] time_us,
  output reg  [31:0] ack_seq,
  output reg         ack_valid,
  input  wire        rsp_valid,
  input  wire [37:0] rsp_data,
  output reg         rsp_ready,
  input  wire        brake,
  input  wire        heartbeat,
  input  wire        int_irq,
  output reg  [9:0]  log_idx,
  output reg         log_valid,
  output reg         log_ready,
  input  wire        log_ready_in,
  input  wire [1055:0] log_data,
  input  wire        log_valid_in,
  // rx stream observation (frame boundary for the latency counter)
  input  wire        rx_valid,
  input  wire        rx_ready,
  input  wire        rx_last
);
  reg        core_run;
  reg        time_auto, ack_hold;
  reg [15:0] us_cnt;
  reg [31:0] free_cyc, brake_t_us, brake_cyc;
  reg        brake_q, brake_cap;
  reg        arm_req;
  reg [31:0] cycles;
  reg        counting, cycles_valid;
  reg [1:0]  log_state;
  reg        log_done;
  reg [1055:0] log_buf;
  reg [31:0] hb_edges;
  reg        hb_q;
  assign core_rst_n = rst_n & core_run;

  // ---------------- AXI4-Lite write: AW and W accepted independently ----------------
  reg        aw_have, w_have;
  reg [11:0] aw_q;
  reg [31:0] w_q;
  wire       do_write = aw_have && w_have && !s_axi_bvalid;
  always @(posedge clk) begin
    if (!rst_n) begin
      s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_bvalid <= 1'b0; s_axi_bresp <= 2'b00;
      aw_have <= 1'b0; w_have <= 1'b0; aw_q <= 12'd0; w_q <= 32'd0;
    end else begin
      s_axi_awready <= !aw_have && !s_axi_awready && s_axi_awvalid;
      s_axi_wready  <= !w_have  && !s_axi_wready  && s_axi_wvalid;
      if (s_axi_awvalid && s_axi_awready) begin aw_have <= 1'b1; aw_q <= s_axi_awaddr; end
      if (s_axi_wvalid  && s_axi_wready)  begin w_have  <= 1'b1; w_q  <= s_axi_wdata;  end
      if (do_write) begin aw_have <= 1'b0; w_have <= 1'b0; s_axi_bvalid <= 1'b1; s_axi_bresp <= 2'b00; end
      else if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
    end
  end

  // ---------------- registers driven by writes ----------------
  always @(posedge clk) begin
    if (!rst_n) begin
      core_run <= 1'b0; time_auto <= 1'b0; ack_hold <= 1'b0; us_cnt <= 16'd0; arm_req <= 1'b0; time_us <= 32'd0; ack_seq <= 32'd0; ack_valid <= 1'b0; rsp_ready <= 1'b0;
      log_idx <= 10'd0; log_valid <= 1'b0; log_ready <= 1'b0; log_state <= 2'd0; log_done <= 1'b0;
      log_buf <= 1056'd0;
    end else begin
      ack_valid <= ack_hold; rsp_ready <= 1'b0; log_ready <= 1'b0; arm_req <= 1'b0;
      if (time_auto && !(do_write && (aw_q[11:2] == 10'h001 || aw_q[11:2] == 10'h00F))) begin
        if (us_cnt == US_DIV - 1) begin us_cnt <= 16'd0; time_us <= time_us + 32'd1; end
        else us_cnt <= us_cnt + 16'd1;
      end
      if (do_write) case (aw_q[11:2])
        10'h000: begin core_run <= w_q[0]; time_auto <= w_q[1]; ack_hold <= w_q[2]; end
        10'h001: begin time_us <= w_q; us_cnt <= 16'd0; end
        10'h002: ack_seq  <= w_q;
        10'h003: ack_valid <= 1'b1;
        10'h004: rsp_ready <= 1'b1;
        10'h00E: arm_req <= 1'b1;
        10'h00F: begin time_us <= w_q; us_cnt <= 16'd0; ack_valid <= 1'b1; end
        10'h008: if (log_state == 2'd0) begin log_idx <= w_q[9:0]; log_valid <= 1'b1; log_done <= 1'b0; log_state <= 2'd1; end
        default: ;
      endcase
      // Recorder read, same handshake order as tb/integ/tb_m_tsmx_top.sv
      case (log_state)
        2'd1: if (log_valid && log_ready_in) begin log_valid <= 1'b0; log_state <= 2'd2; end
        2'd2: if (log_valid_in) begin log_buf <= log_data; log_ready <= 1'b1; log_state <= 2'd3; end
        2'd3: begin log_done <= 1'b1; log_state <= 2'd0; end
        default: ;
      endcase
    end
  end

  // ---------------- latency counter and heartbeat edges ----------------
  always @(posedge clk) begin
    if (!rst_n) begin
      cycles <= 32'd0; counting <= 1'b0; cycles_valid <= 1'b0; hb_edges <= 32'd0; hb_q <= 1'b0;
      free_cyc <= 32'd0; brake_q <= 1'b0; brake_cap <= 1'b0; brake_t_us <= 32'd0; brake_cyc <= 32'd0;
    end else begin
      hb_q <= heartbeat;
      free_cyc <= free_cyc + 32'd1;
      brake_q <= brake;
      if (arm_req) brake_cap <= 1'b0;
      else if (brake && !brake_q && !brake_cap) begin brake_cap <= 1'b1; brake_t_us <= time_us; brake_cyc <= free_cyc; end
      if (heartbeat != hb_q) hb_edges <= hb_edges + 32'd1;
      if (rx_valid && rx_ready && rx_last) begin cycles <= 32'd1; counting <= 1'b1; cycles_valid <= 1'b0; end
      else if (counting) begin
        if (rsp_valid) begin counting <= 1'b0; cycles_valid <= 1'b1; end
        else cycles <= cycles + 32'd1;
      end
    end
  end

  // ---------------- AXI4-Lite read ----------------
  wire [9:0] ra = s_axi_araddr[11:2];
  reg  [31:0] rmux;
  integer k;
  always @(*) begin
    rmux = 32'd0;
    case (ra)
      10'h000: rmux = {29'd0, ack_hold, time_auto, core_run};
      10'h00B: rmux = free_cyc;
      10'h00C: rmux = brake_t_us;
      10'h00D: rmux = brake_cyc;
      10'h00E: rmux = {31'd0, brake_cap};
      10'h00F: rmux = time_us;
      10'h001: rmux = time_us;
      10'h002: rmux = ack_seq;
      10'h004: rmux = {25'd0, rx_ready, log_done, cycles_valid, int_irq, heartbeat, brake, rsp_valid};
      10'h005: rmux = rsp_data[31:0];
      10'h006: rmux = {26'd0, rsp_data[37:32]};
      10'h007: rmux = cycles;
      10'h009: rmux = hb_edges;
      10'h00A: rmux = 32'h75B0A1D4;
      default: begin
        for (k = 0; k < 33; k = k + 1)
          if (ra == 10'h040 + k) rmux = log_buf[32*k +: 32];
      end
    endcase
  end
  always @(posedge clk) begin
    if (!rst_n) begin
      s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0; s_axi_rdata <= 32'd0; s_axi_rresp <= 2'b00;
    end else begin
      s_axi_arready <= !s_axi_arready && !s_axi_rvalid && s_axi_arvalid;
      if (s_axi_arvalid && s_axi_arready) begin s_axi_rvalid <= 1'b1; s_axi_rdata <= rmux; s_axi_rresp <= 2'b00; end
      else if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
    end
  end
endmodule
`default_nettype wire
