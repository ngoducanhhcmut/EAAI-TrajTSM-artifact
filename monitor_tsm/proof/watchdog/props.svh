`ifdef FORMAL
  // ---- Claude 05/11/2026: deadline (watchdog) properties, proven by k-induction ----
  // Assumption: one reset at time 0, then reset stays released and the clock runs (no glitch / no clock loss).
  // All submodule outputs (incl. CSR config / CSR reset) are unconstrained: see gen.py.
  reg f_init = 1'b1;
  reg f_prev_active = 1'b0;
  reg [31:0] f_prev_count = 32'd0;
  always @(posedge i_clk_core) begin
    f_init <= 1'b0;
    f_prev_active <= reg_active;
    f_prev_count <= reg_count;
  end
  always @(*) begin
    if (f_init) assume(!i_rst_n_core);
    else assume(i_rst_n_core);
  end
  always @(posedge i_clk_core) if (!f_init) begin
    // W1: while a request is active its cycle counter stays in [1, 1874999]
    W1: assert(!reg_active || (reg_count >= 32'd1 && reg_count <= 32'd1874999));
    // W2: an active request cannot be overwritten by a new admission (FSM not in IDLE/BOOT)
    //     (idle-side service states TLOG/TLOGW/BIST/BISTW are entered from IDLE only without an admission)
    W2: assert(!reg_active || (reg_fsm_ctrl_current_state != ENUM_ST_IDLE
                               && reg_fsm_ctrl_current_state != ENUM_ST_BOOT
                               && reg_fsm_ctrl_current_state != ENUM_ST_TLOG
                               && reg_fsm_ctrl_current_state != ENUM_ST_TLOGW
                               && reg_fsm_ctrl_current_state != ENUM_ST_BIST
                               && reg_fsm_ctrl_current_state != ENUM_ST_BISTW));
    // W3: no stale response is pending while a request is active
    W3: assert(!reg_active || !reg_resp_valid);
    // W5: after a deadline the brake output stays asserted
    W5: assert(!reg_deadline || o_brake);
    // W9: the latched deadline response is a REJECT with the deadline reason and brake bit (keeps o_brake high)
    W9: assert(!reg_deadline || (reg_final_rsp[9] && !reg_final_rsp[37] && reg_final_rsp[36:29] == 8'd7));
    // W6: deadline and active are exclusive
    W6: assert(!(reg_deadline && reg_active));
    if (f_prev_active) begin
      // W4: the counter advances by exactly one per active cycle (no stall by host/executor/recorder)
      if (reg_active) W4: assert(reg_count == f_prev_count + 32'd1);
      // W7: whenever activity ends, a response is presented (normal result or deadline REJECT)
      else W7: assert(reg_resp_valid);
    end
    // W8: a deadline response is a REJECT (accept bit 0) with reason 7
    if (reg_deadline && reg_resp_valid) W8: assert(reg_resp_data[37] == 1'b0 && reg_resp_data[36:29] == 8'd7);
  end
`endif
