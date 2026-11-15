/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Fully pipelined radix-2 directed division, sixteen bits per stage.
 * Assumptions  : Positive denominator; minimum-negative numerator is a sentinel.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_arith_div #(
  // Parameter Description: numerator width, divisible by sixteen.
  // Parameter values: 96, 128, 160; default is 160.
  // Parameter unit: bit
  parameter logic [31:0] PARA_W = 32'd160,
  localparam logic [31:0] LPARA_STEP = 32'd16,
  localparam logic [31:0] LPARA_STAGES = PARA_W >> 32'd4
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_valid,
  input wire [PARA_W-1:0] i_num,
  input wire [PARA_W-1:0] i_den,
  input wire i_up,
  output logic o_valid,
  output logic o_fault,
  output logic [PARA_W-1:0] o_data
);
  logic [PARA_W-1:0] reg_num [0:LPARA_STAGES];
  logic [PARA_W-1:0] reg_den [0:LPARA_STAGES];
  logic [PARA_W-1:0] reg_quot [0:LPARA_STAGES];
  logic [PARA_W:0] reg_rem [0:LPARA_STAGES];
  logic [LPARA_STAGES:0] reg_valid, reg_fault, reg_neg, reg_up;
  logic [PARA_W-1:0] w_mag, w_result;
  logic w_adjust;

  // The input register is stage zero; bubbles invalidate the associated payload.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_input
    if (!i_rst_n_core) begin
      reg_num[0] <= '0;
      reg_den[0] <= '0;
      reg_quot[0] <= '0;
      reg_rem[0] <= '0;
      reg_valid[0] <= 1'b0;
      reg_fault[0] <= 1'b0;
      reg_neg[0] <= 1'b0;
      reg_up[0] <= 1'b0;
    end else begin
      reg_num[0] <= '0;
      reg_den[0] <= '0;
      if (i_valid) begin
        reg_num[0] <= i_num[PARA_W-1] ? PARA_W'(~i_num + 1'b1) : i_num;
        reg_den[0] <= i_den;
      end
      reg_quot[0] <= '0;
      reg_rem[0] <= '0;
      reg_valid[0] <= i_valid;
      reg_fault[0] <= (i_den == '0) || i_den[PARA_W-1] ||
        (i_num == {1'b1, {(PARA_W-1){1'b0}}});
      reg_neg[0] <= i_num[PARA_W-1];
      reg_up[0] <= i_up;
    end
  end

  // Each explicit pipeline stage performs sixteen restoring division steps.
  for (genvar gen_idx = 0; gen_idx < LPARA_STAGES; gen_idx++) begin : gen_stage
    logic [PARA_W-1:0] w_num, w_quot;
    logic [PARA_W:0] w_rem;
    // Bubbles skip the subtract chain and cannot create a visible quotient.
    always @* begin : p_com_step
      w_num = reg_num[gen_idx];
      w_quot = reg_quot[gen_idx];
      w_rem = reg_rem[gen_idx];
      if (reg_valid[gen_idx]) begin
      for (int idx = 0; idx < LPARA_STEP; idx++) begin
        w_rem = {w_rem[PARA_W-1:0], w_num[PARA_W-1]};
        w_num = PARA_W'(w_num << 1'b1);
        w_quot = PARA_W'(w_quot << 1'b1);
        if (w_rem >= {1'b0, reg_den[gen_idx]}) begin
          w_rem = (PARA_W+1)'(w_rem - {1'b0, reg_den[gen_idx]});
          w_quot[0] = 1'b1;
        end
      end
      end
    end
    // Valid, sign, rounding and fault travel with every independent quotient.
    always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_stage
      if (!i_rst_n_core) begin
        reg_num[gen_idx+1] <= '0;
        reg_den[gen_idx+1] <= '0;
        reg_quot[gen_idx+1] <= '0;
        reg_rem[gen_idx+1] <= '0;
        reg_valid[gen_idx+1] <= 1'b0;
        reg_fault[gen_idx+1] <= 1'b0;
        reg_neg[gen_idx+1] <= 1'b0;
        reg_up[gen_idx+1] <= 1'b0;
      end else begin
        reg_num[gen_idx+1] <= w_num;
        reg_den[gen_idx+1] <= reg_den[gen_idx];
        reg_quot[gen_idx+1] <= w_quot;
        reg_rem[gen_idx+1] <= w_rem;
        reg_valid[gen_idx+1] <= reg_valid[gen_idx];
        reg_fault[gen_idx+1] <= reg_fault[gen_idx];
        reg_neg[gen_idx+1] <= reg_neg[gen_idx];
        reg_up[gen_idx+1] <= reg_up[gen_idx];
      end
    end
  end

  // Floor moves negative inexact results away from zero; ceil moves positive ones.
  always @* begin : p_com_output
    w_adjust = (reg_rem[LPARA_STAGES] != '0) &&
      (reg_neg[LPARA_STAGES] != reg_up[LPARA_STAGES]);
    w_mag = PARA_W'(reg_quot[LPARA_STAGES] + {{(PARA_W-1){1'b0}}, w_adjust});
    w_result = reg_neg[LPARA_STAGES] ? PARA_W'(~w_mag + 1'b1) : w_mag;
    o_valid = reg_valid[LPARA_STAGES] && i_rst_n_core;
    o_fault = o_valid && (reg_fault[LPARA_STAGES] || w_mag[PARA_W-1]);
    o_data = '0;
    if (o_valid && !o_fault) o_data = w_result;
  end
endmodule
`default_nettype wire
