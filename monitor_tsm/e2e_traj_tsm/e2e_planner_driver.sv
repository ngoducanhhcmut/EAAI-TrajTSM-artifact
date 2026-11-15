//==============================================================================
// tb_planning_top_e2e — kiem TOAN KHOI TRAJ tu DDR toi waypoint, KHONG tiem du lieu.
//   DDR mo hinh (AXI4 doc, burst) nap payload V2 (sw/payloads/v2) + world model mau.
//   CSR AXI-lite nhu firmware: cho boot -> WM_SEL -> START -> cho ngat -> doc WP.
//   Nhieu khung hinh lien tiep (khong reset): +S0=<mau dau> +NS=<so mau>.
//   So: CLS (cls_buf) TUNG BIT voi hwspec ; waypoint voi GRU tuong duong RTL (dung sai
//   1 mm, bao lech lon nhat) va voi GT (ADE). Bao so chu ky tung pha.
//==============================================================================
`timescale 1ns / 1ps
module e2e_planner_driver;
  import planning_pkg::*;
  localparam real TCK = 20.0/3.0;      // 150 MHz
  logic clk = 0, rst_n = 0;
  always #(TCK/2) clk = ~clk;

  // ── DUT ─────────────────────────────────────────────────────────────────────
  logic [11:0] axil_awaddr = 0, axil_araddr = 0;
  logic axil_awvalid = 0, axil_wvalid = 0, axil_bready = 1, axil_arvalid = 0, axil_rready = 1;
  logic [31:0] axil_wdata = 0; logic [3:0] axil_wstrb = 4'hF;
  logic axil_awready, axil_wready, axil_bvalid, axil_arready, axil_rvalid;
  logic [1:0] axil_bresp, axil_rresp; logic [31:0] axil_rdata;
  logic [5:0] m_axi_arid, m_axi_rid; logic [31:0] m_axi_araddr; logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize, m_axi_arprot; logic [1:0] m_axi_arburst, m_axi_arlock, m_axi_rresp;
  logic [3:0] m_axi_arcache, m_axi_arqos; logic m_axi_arvalid, m_axi_arready, m_axi_rlast, m_axi_rvalid, m_axi_rready;
  logic [127:0] m_axi_rdata;
  fp32_t waypoint_x [NUM_WAYPOINTS-1:0], waypoint_y [NUM_WAYPOINTS-1:0];
  logic waypoints_valid, waypoints_sanity_pass, done_irq, wload_timeout_err;

  planning_top dut (.*, .hmao_clk(clk), .hmao_rst_n(rst_n));

  // ── DDR ─────────────────────────────────────────────────────────────────────
  string V;
  logic [127:0] r_bw [393216], r_pe [8192], r_pa [4096], r_pb [8192], r_pc [2048];
  logic [127:0] r_gb [512], r_gw [49152], r_go [512], r_gs [384], r_gp [384], r_wm [1024];
  int n_bad_addr = 0;

  function automatic logic [127:0] ddr_rd(input logic [31:0] a);
    logic [31:0] o;
    if (a < 32'h0060_0000)                                  return r_bw[(a - 32'h0)       >> 4];
    if (a >= 32'h0060_0000 && a < 32'h0062_0000)            return r_pe[(a - 32'h0060_0000) >> 4];
    if (a >= 32'h0064_0000 && a < 32'h0064_4000)            return r_wm[(a - 32'h0064_0000) >> 4];
    if (a >= 32'h0064_4000 && a < 32'h00E4_0000)            return 128'd0;     // phan con lai buffer WM
    if (a >= 32'h017D_2000 && a < 32'h017D_4000)            return r_gb[(a - 32'h017D_2000) >> 4];
    if (a >= 32'h017D_4000 && a < 32'h0189_4000)            return r_gw[(a - 32'h017D_4000) >> 4];
    if (a >= 32'h0189_4000 && a < 32'h0189_6000)            return r_go[(a - 32'h0189_4000) >> 4];
    if (a >= 32'h018A_0000 && a < 32'h018A_1800)            return r_gs[(a - 32'h018A_0000) >> 4];
    if (a >= 32'h018A_8000 && a < 32'h018A_9800)            return r_gp[(a - 32'h018A_8000) >> 4];
    if (a >= 32'h0190_0000 && a < 32'h0191_0000)            return r_pa[(a - 32'h0190_0000) >> 4];
    if (a >= 32'h0191_0000 && a < 32'h0193_0000)            return r_pb[(a - 32'h0191_0000) >> 4];
    if (a >= 32'h0193_0000 && a < 32'h0193_8000)            return r_pc[(a - 32'h0193_0000) >> 4];
    n_bad_addr++;
    if (n_bad_addr < 10) $display("  [DDR] doc dia chi ngoai vung: %08h", a);
    return 128'd0;
  endfunction

  // AXI4 doc: 1 giao dich treo, tre 6 chu ky, burst INCR
  logic        rd_busy = 0;
  logic [31:0] rd_addr;
  logic [8:0]  rd_left;
  logic [3:0]  rd_lat;
  assign m_axi_arready = !rd_busy;
  assign m_axi_rid = 6'd0; assign m_axi_rresp = 2'b00;
  always_ff @(posedge clk) begin
    if (!rst_n) begin rd_busy <= 0; m_axi_rvalid <= 0; m_axi_rlast <= 0; end
    else begin
      if (!rd_busy && m_axi_arvalid) begin
        rd_busy <= 1; rd_addr <= m_axi_araddr; rd_left <= {1'b0, m_axi_arlen} + 9'd1; rd_lat <= 4'd6;
        m_axi_rvalid <= 0;
      end else if (rd_busy) begin
        if (rd_lat != 0) rd_lat <= rd_lat - 4'd1;
        else if (!m_axi_rvalid || m_axi_rready) begin
          if (rd_left != 0) begin
            m_axi_rvalid <= 1; m_axi_rdata <= ddr_rd(rd_addr); m_axi_rlast <= (rd_left == 9'd1);
            rd_addr <= rd_addr + 32'd16; rd_left <= rd_left - 9'd1;
          end else begin
            m_axi_rvalid <= 0; m_axi_rlast <= 0; rd_busy <= 0;
          end
        end
      end
    end
  end

  // ── AXI-lite (task tinh — tranh loi xsim voi task automatic co output) ───────
  logic [31:0] rd_val;
  task axil_write(input logic [11:0] a, input logic [31:0] d);
    @(posedge clk);
    axil_awaddr <= a; axil_awvalid <= 1; axil_wdata <= d; axil_wvalid <= 1;
    @(posedge clk);
    while (!(axil_awready && axil_wready)) @(posedge clk);
    @(posedge clk); axil_awvalid <= 0; axil_wvalid <= 0;
    while (!axil_bvalid) @(posedge clk);
    @(posedge clk);
  endtask
  task axil_read(input logic [11:0] a);
    @(posedge clk);
    axil_araddr <= a; axil_arvalid <= 1;
    @(posedge clk);
    while (!axil_arready) @(posedge clk);
    @(posedge clk); axil_arvalid <= 0;
    while (!axil_rvalid) @(posedge clk);
    rd_val = axil_rdata;
    @(posedge clk);
  endtask


  logic [31:0] cls_exp[512], wp_exp[8], observed_wp[8], recorded_wp[280];
  string vector_dir;
  integer boot_polls, frame_cycles;
  bit booted=0;
  function automatic real f2r(input logic [31:0] b);
    integer e;
    real m;
    // Explicit IEEE binary32 conversion: no shortreal promotion in Verilator.
    if (b[30:23]==255) $fatal(1,"nonfinite planner waypoint");
    e=int'(b[30:23]);
    m=(e==0) ? real'(b[22:0])/8388608.0 : 1.0+real'(b[22:0])/8388608.0;
    return (b[31] ? -m:m) * (2.0 ** ((e==0 ? 1:e)-127));
  endfunction
  task boot;
    if (!$value$plusargs("VECTORS=%s",vector_dir)) vector_dir="./";
    $readmemh({vector_dir,"recorded_wp.mem"},recorded_wp);
    if (!$value$plusargs("PLANNER_VEC=%s",V)) V="../../../tb/e2e/vec/";
    $readmemh({V,"ddr_bert_weights.hex"},r_bw);
    $readmemh({V,"ddr_pos_emb.hex"},r_pe);
    $readmemh({V,"ddr_param_a.hex"},r_pa);
    $readmemh({V,"ddr_param_b.hex"},r_pb);
    $readmemh({V,"ddr_param_c.hex"},r_pc);
    $readmemh({V,"ddr_gru_bias.hex"},r_gb);
    $readmemh({V,"ddr_gru_weights.hex"},r_gw);
    $readmemh({V,"ddr_gru_wout_staging.hex"},r_go);
    $readmemh({V,"ddr_gru_scale_zp.hex"},r_gs);
    $readmemh({V,"ddr_gru_wp_proj.hex"},r_gp);
    for(integer k=0;k<1024;k++) r_wm[k]='0;
    repeat(20) @(negedge clk); rst_n=1;
    boot_polls=0;
    do begin
      repeat(2000) @(posedge clk); axil_read(12'h004); boot_polls++;
    end while (!(rd_val[8] && rd_val[10]) && boot_polls<2000);
    if (!(rd_val[8] && rd_val[10])) $fatal(1,"planner boot timeout");
    axil_write(12'h034,1); axil_write(12'h008,0); booted=1;
  endtask
  task run_frame(input integer frame_index);
    string sn;
    real delta;
    if (!booted) $fatal(1,"planner not booted");
    sn=$sformatf("s%02d",frame_index);
    for(integer k=0;k<1024;k++) r_wm[k]='0;
    $readmemh({V,sn,"_wm.hex"},r_wm);
    $readmemh({V,sn,"_cls.hex"},cls_exp);
    $readmemh({V,sn,"_wp.hex"},wp_exp);
    axil_write(12'h000,1);
    frame_cycles=0;
    while (!done_irq && frame_cycles<30000000) begin @(posedge clk); frame_cycles++; end
    if (!done_irq || wload_timeout_err) $fatal(1,"planner frame timeout %0d",frame_index);
    repeat(5) @(posedge clk);
    axil_write(12'h000,32'h100);
    for(integer k=0;k<512;k++)
      if(dut.u_cls_buf.mem[k] !== cls_exp[k]) $fatal(1,"CLS frame=%0d word=%0d",frame_index,k);
    for(integer k=0;k<8;k++) begin
      axil_read(12'h010+12'(k*4)); observed_wp[k]=rd_val;
      delta=f2r(rd_val)-f2r(wp_exp[k]);
      if ((delta>0.000021) || (delta < -0.000021))
        $fatal(1,"waypoint frame=%0d word=%0d delta=%f",frame_index,k,delta);
      if (rd_val !== recorded_wp[frame_index*8+k])
        $fatal(1,"PLANNER_DETERMINISM_MISMATCH frame=%0d word=%0d actual=%h expected=%h",
               frame_index,k,rd_val,recorded_wp[frame_index*8+k]);
    end
    if(n_bad_addr!=0) $fatal(1,"planner invalid DDR address");
    $display("PLANNER_PASS frame=%0d cycles=%0d",frame_index,frame_cycles);
  endtask
endmodule
