  // Board-equivalent transport; direct semantic request pins remain tied low.
  always #5 i_clk_core=~i_clk_core;
  always @(posedge i_clk_core) cyc=cyc+1;
  integer command_count=0, packet_errors=0;
  logic [31:0] pending_seq=0;
  always @(posedge i_clk_core) begin
    if(i_rst_n_core && o_tx_valid && i_tx_ready) begin
      if(txword==0) begin
        if(o_tx_data!==32'd2 || o_tx_keep!==4'hf || o_tx_last) $fatal(1,"TX header");
        txbuf='0;
      end else if(txword==1) begin
        if(o_tx_data!==32'd238 || o_tx_keep!==4'hf || o_tx_last) $fatal(1,"TX length");
      end else begin
        if(o_tx_keep !== (txword==61 ? 4'h3:4'hf) || o_tx_last !== (txword==61))
          $fatal(1,"TX framing");
        for(integer b=0;b<4;b++)
          if(4*(txword-2)+b<238) txbuf[1903-8*(4*(txword-2)+b) -:8]=o_tx_data[8*b +:8];
      end
      if(o_tx_last) begin
        if(txbuf[1903:7]!==expected_cmd || txbuf[6:0]!==0)
          $fatal(1,"TSM_COMMAND_MISMATCH job=%0d",job);
        if(txbuf[1903:1901]==0) pending_seq=txbuf[1881:1850];
        command_count++;txword=0;
      end else txword++;
    end
  end
  task boot;
    i_clk_core=0;i_rst_n_core=0;i_req_valid=0;i_req_data=0;i_rsp_ready=0;
    i_time_us=0;i_ack_valid=0;i_ack_seq=0;
    i_axi_awaddr=0;i_axi_awprot=0;i_axi_awvalid=0;i_axi_wdata=0;i_axi_wstrb=15;
    i_axi_wvalid=0;i_axi_bready=0;i_axi_araddr=0;i_axi_arprot=0;i_axi_arvalid=0;i_axi_rready=0;
    i_log_idx=0;i_log_valid=0;i_log_ready=0;
    i_rx_valid=0;i_rx_data=0;i_rx_keep=0;i_rx_last=0;i_tx_ready=1;
    repeat(4) @(negedge i_clk_core);i_rst_n_core=1;
    repeat(5) @(negedge i_clk_core);
    bus_write(16'h00,4);
    rd=0;
    for(integer n=0;n<200000 && rd!==1;n++) bus_read(16'h4c,rd);
    if(rd!==1) $fatal(1,"BIST/configuration timeout");
    bus_write(16'h00,1);
    bus_read(16'h00,rd);if(rd!==1) $fatal(1,"TSM enable");
  endtask
  task send_frame(input logic [44672:0] f);
    logic [44679:0] bytes_be;
    logic [31:0] w;
    bytes_be={f,7'd0};
    for(integer k=0;k<1399;k++) begin
      @(negedge i_clk_core);
      i_rx_keep=(k==1398 ? 4'h1:4'hf);i_rx_last=(k==1398);
      if(k==0) w=1;
      else if(k==1) w=5585;
      else begin
        w=0;
        for(integer b=0;b<4;b++)
          if(4*(k-2)+b<5585) w[8*b +:8]=bytes_be[44679-8*(4*(k-2)+b) -:8];
      end
      i_rx_data=w;i_rx_valid=1;
      do @(posedge i_clk_core); while(!o_rx_ready);
    end
    @(negedge i_clk_core);i_rx_valid=0;i_rx_last=0;i_rx_keep=0;i_rx_data=0;
  endtask
  task run_job(input integer idx,input logic [48036:0] vector_bits,input logic [44672:0] firmware_req);
    integer cc_before, elapsed_cycles, wait_cycles;
    logic [31:0] status_exp;
    job=idx;
    {reset_job,req,expected_rsp,expected_cmd,expected_ing,expected_sup,expected_lost,expected_event}=vector_bits;
    // The outer reset flag is allowed only at sequence start; boot already did it.
    if(reset_job !== (idx==0)) $fatal(1,"unexpected history reset");
    wait_cycles=0;
    while(!dut.u_tsmx_engine.o_req_ready) begin
      @(negedge i_clk_core);wait_cycles++;
      if(wait_cycles>2000000) $fatal(1,"TSM idle timeout");
    end
    @(negedge i_clk_core);i_time_us=firmware_req[44672:44641];
    i_ack_seq=pending_seq;i_ack_valid=firmware_req[33856];
    @(negedge i_clk_core);i_ack_valid=0;
    cc_before=command_count;
    send_frame(firmware_req);
    start_cyc=cyc;wait_cycles=0;
    while(!o_rsp_valid) begin
      @(negedge i_clk_core);wait_cycles++;
      if(wait_cycles>1875010) $fatal(1,"TSM response timeout job=%0d",job);
    end
    elapsed_cycles=cyc-start_cyc;
    if(o_rsp_data!==expected_rsp) $fatal(1,"TSM_RESPONSE_MISMATCH job=%0d got=%h expected=%h",job,o_rsp_data,expected_rsp);
    if(!expected_rsp[0] && o_heartbeat!==0) $fatal(1,"heartbeat mismatch");
    if((!expected_rsp[37] || expected_rsp[9]) && o_brake!==1) $fatal(1,"brake mismatch");
    // Inspect retained records as the integration bench does, never drive them.
    if(dut.u_tsmx_engine.reg_ing!==expected_ing ||
       {dut.u_tsmx_engine.reg_mode,dut.u_tsmx_engine.reg_good,dut.u_tsmx_engine.reg_fault,
        dut.u_tsmx_engine.reg_pending_valid,dut.u_tsmx_engine.reg_backup_valid}!==expected_sup)
      $fatal(1,"TSM retained state mismatch job=%0d",job);
    // The TX monitor obtains the next ACK sequence from the actual command.
    repeat(3) @(negedge i_clk_core);i_rsp_ready=1;
    @(negedge i_clk_core);i_rsp_ready=0;
    i_log_idx=(idx>=64 ? 63:idx);i_log_valid=1;
    while(!o_log_ready) @(negedge i_clk_core);
    @(negedge i_clk_core);i_log_valid=0;
    while(!o_log_valid) @(negedge i_clk_core);
    if(o_log_data!==expected_event) $fatal(1,"TSM_EVENT_MISMATCH job=%0d",job);
    i_log_ready=1;@(negedge i_clk_core);i_log_ready=0;
    while(command_count==cc_before) @(negedge i_clk_core);
    bus_read(16'h28,rd);if(rd!=={24'd0,expected_rsp[36:29]}) $fatal(1,"CSR reason");
    status_exp=0;status_exp[1]=expected_rsp[0];
    status_exp[2]=!expected_rsp[0] || expected_rsp[28:26]==3 || expected_rsp[9];
    status_exp[5:3]=expected_rsp[28:26];status_exp[6]=expected_sup[1];status_exp[7]=expected_sup[0];
    status_exp[8]=expected_rsp[0];status_exp[17:16]=expected_rsp[11:10];
    bus_read(16'h04,rd);if(rd!==status_exp) $fatal(1,"CSR status");
    bus_read(16'h24,rd);if(rd!==expected_lost) $fatal(1,"CSR lost");
    bus_read(16'h2c,rd);
    // Stream latency includes parser/dispatch; CSR counts engine cycles only.
    if(rd==0 || rd>1875000 || elapsed_cycles<rd || elapsed_cycles-rd>16)
      $fatal(1,"CSR cycle count inconsistency job=%0d csr=%0d stream=%0d",job,rd,elapsed_cycles);
    $display("TSM_PASS job=%0d time_us=%0d engine_cycles=%0d stream_cycles=%0d",job,i_time_us,rd,elapsed_cycles);
  endtask
endmodule
