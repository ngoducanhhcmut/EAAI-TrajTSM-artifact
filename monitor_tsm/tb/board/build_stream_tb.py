"""Claude 04/11: board-equivalent integration bench for TSM-X.

Derives tb_tsmx_stream.sv from tb/integ/tb_m_tsmx_top.sv (unchanged checks) but:
  * PARA_DIRECT=0: requests enter through the 32-bit rx stream exactly as the board
    AXI-Stream FIFO will send them (header 1, 5585, 1396 payload words, final word
    keep=0001 carrying frame bit 0 in bus bit 7);
  * ACK is a single-cycle pulse issued (like the board shim) just before the frame;
  * prints BOARDVEC lines (time_us, ack, ack_seq, CSR cycles) used to build the
    firmware vector file, instead of asserting the DIRECT-mode cycle count.
"""
from pathlib import Path
HERE = Path(__file__).resolve().parent
src = (HERE.parent / 'integ' / 'tb_m_tsmx_top.sv').read_text(encoding='utf-8')

def sub(old, new, count=1):
    global src
    assert src.count(old) == count, (old[:60], src.count(old))
    src = src.replace(old, new)

sub('m_tsmx_top #(.PARA_DIRECT(1),', 'm_tsmx_top #(.PARA_DIRECT(0),')

old_inject = """      @(negedge i_clk_core);i_req_data=req;i_req_valid=1;
      i_time_us=req[44672:44641];
      i_ack_valid=req[33856];i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528];
      while(!o_req_ready) @(negedge i_clk_core);
      @(posedge i_clk_core);start_cyc=cyc;start_time=$time;
      @(negedge i_clk_core);i_req_valid=0;i_ack_valid=0;
"""
new_inject = """      @(negedge i_clk_core);
      // r3: the board (xsdb, ms per access) only pulses ACK with the engine idle; wait for it here.
      idle_wait=0;
      while(!dut.u_tsmx_engine.o_req_ready) begin @(negedge i_clk_core); idle_wait=idle_wait+1; end
      if(idle_wait!=0) $display("IDLEWAIT job=%0d cycles=%0d",job,idle_wait);
      i_time_us=req[44672:44641];
      i_ack_valid=req[33856];i_ack_seq=dut.u_tsmx_engine.reg_pending_plan[559:528];
      $display("BOARDVEC job=%0d reset=%0d time=%h ack=%0d seq=%h",job,reset_job,i_time_us,i_ack_valid,i_ack_seq);
      @(negedge i_clk_core);i_ack_valid=0;
      send_frame(req);
      start_cyc=cyc;start_time=$time-10;
"""
sub(old_inject, new_inject)

# The DIRECT-mode cycle count starts at the parallel accept; with the stream the
# start point differs, so report the CSR value instead of asserting equality.
sub('bus_read(16\'h2c,rd);if(rd!==latency)$fatal(1,"CSR cycles actual=%0d expected=%0d",rd,latency);',
    'bus_read(16\'h2c,rd);$display("BOARDCYC job=%0d csr_cycles=%0d tb_latency=%0d",job,rd,latency);')

# PARA_DIRECT=0 admission needs the real bring-up: BIST while disabled, CONFIG_VALID, then EN.
# The CSR is reset with the core, so repeat after every job reset (after the smoke, which
# deliberately invalidates the configuration with a bad write).
sub('    $display("PASS top CSR/AXI smoke");', '    $display("PASS top CSR/AXI smoke");bringup();')
sub('        repeat(5) @(negedge i_clk_core);log_count=0;frames=0;',
    '        repeat(5) @(negedge i_clk_core);log_count=0;frames=0;bringup();')
sub("          frames=frames+1;txword=0;","          frames=frames+1;txword=0;$display(\"BOARDCMD job=%0d frames=%0d\",job,frames);")
task = """  integer idle_wait=0;
  // Claude 04/11: board-equivalent stream sender (AXI-Stream FIFO store-and-forward, no gaps).
  task automatic send_frame(input logic [44672:0] f);
    integer k;
    logic [31:0] w;
    for(k=0;k<1399;k=k+1) begin
      if(k==0) begin w=32'd1; i_rx_keep=4'hf; i_rx_last=0; end
      else if(k==1) begin w=32'd5585; i_rx_keep=4'hf; i_rx_last=0; end
      else if(k<1398) begin
        w=f[44672-32*(k-2) -: 32]; w={w[7:0],w[15:8],w[23:16],w[31:24]};
        i_rx_keep=4'hf; i_rx_last=0;
      end else begin w={24'd0,f[0],7'd0}; i_rx_keep=4'b0001; i_rx_last=1; end
      i_rx_data=w; i_rx_valid=1;
      @(posedge i_clk_core); while(!o_rx_ready) @(posedge i_clk_core);
      #1;
    end
    i_rx_valid=0; i_rx_last=0; i_rx_keep=0; i_rx_data=0;
    @(negedge i_clk_core);
  endtask
  // Claude 04/11: firmware bring-up sequence (CTRL.bist_start -> CONFIG_VALID -> CTRL.en).
  task automatic bringup();
    logic [31:0] v;
    integer n;
    bus_write(16'h00,32'h4);
    n=0; v=0;
    while(v!==32'd1) begin
      bus_read(16'h4c,v); n=n+1;
      if(n>200000) $fatal(1,"bring-up: CONFIG_VALID never set");
    end
    bus_write(16'h00,32'h1);
    bus_read(16'h00,v); if(v!==32'd1) $fatal(1,"bring-up: CTRL.en not set (%h)",v);
    $display("BOARDUP polls=%0d cyc=%0d",n,cyc);
  endtask
"""
anchor = '  initial begin'
assert anchor in src
src = src.replace(anchor, task + anchor, 1)
src = src.replace('module tb_m_tsmx_top', 'module tb_tsmx_stream', 1)
(HERE / 'tb_tsmx_stream.sv').write_text(src, encoding='utf-8')
print('wrote', HERE / 'tb_tsmx_stream.sv')
