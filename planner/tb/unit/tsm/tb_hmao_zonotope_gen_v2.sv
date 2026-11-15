// =============================================================================
// tb_hmao_zonotope_gen_v2.sv — kiem thu don vi hmao_zonotope_gen (TSM v2).
//
// Kiem tra cac truong ma bo kiem tra va cham v2 dung: tam (cx, cy) va cos/sin huong
// (rem_x, rem_y), doi chieu voi mo hinh tham chieu sw/eval_trainval/zono_ref.py.
// Lo hong ma test nay bit lai: test SAT v2 lay cos/sin tu mo hinh Python nen bo qua
// khoi nay; loi tran 32 bit khi lam tron cos ~ 1,0 (hc = -256) da lot qua (VH AK.16).
//
// Vector: tb/unit/tsm/vec/zg_traj.hex (moi ca 350 tu = 50 waypoint x 7 tu fp32) va
// zg_ncase.txt. Ket qua: reports/zono_v2/zg_out_<NZ>.txt (moi dong: ca buoc cx cy hc hs).
// NZ = 50 (tang 1) hoac 100 (tang 2) chon bang +define+ZG_NZ=...
// =============================================================================
`timescale 1ns/1ps
`ifndef ZG_NZ
  `define ZG_NZ 50
`endif
`ifndef ZG_VEC
  `define ZG_VEC "tb/unit/tsm/vec"
`endif
`ifndef ZG_OUT
  `define ZG_OUT "zg_out.txt"
`endif

module tb_hmao_zonotope_gen_v2;
  import hmao_pkg::*;

  localparam int NZ = `ZG_NZ;
  localparam int MAXC = 2000;

  logic clk = 1'b0, rst_n = 1'b0, start = 1'b0;
  always #2.667 clk = ~clk;

  waypoint_t               wps [0:TRAJ_WAYPOINTS-1];
  logic [NZ*128-1:0]       zon;
  logic                    zvalid, ovf, zerr;
  logic [31:0]             mem [0:MAXC*350-1];
  int                      ncase, fo;

  hmao_zonotope_gen #(
    .NUM_GENERATORS (NZ == 50 ? STAGE1_GENERATORS : STAGE2_GENERATORS),
    .NUM_TIMESTEPS  (NZ),
    .DELTA_T_US     (NZ == 50 ? 10 : 5)
  ) dut (
    .clk (clk), .rst_n (rst_n), .start (start),
    .waypoints_in (wps),
    .lateral_margin (16'd396), .long_margin (16'd528), .time_margin (16'd132),
    .zonotopes_out (zon), .valid_out (zvalid), .overflow_err (ovf), .zonotope_err (zerr)
  );

  initial begin
    int fd, timeout;
    fd = $fopen({`ZG_VEC, "/zg_ncase.txt"}, "r");
    void'($fscanf(fd, "%d", ncase)); $fclose(fd);
    $readmemh({`ZG_VEC, "/zg_traj.hex"}, mem);
    fo = $fopen(`ZG_OUT, "w");
    foreach (wps[i]) wps[i] = '0;
    repeat (5) @(posedge clk); rst_n = 1'b1; repeat (5) @(posedge clk);
    for (int c = 0; c < ncase; c++) begin
      for (int w = 0; w < TRAJ_WAYPOINTS; w++) begin
        wps[w].x         = mem[c*350 + w*7 + 0];
        wps[w].y         = mem[c*350 + w*7 + 1];
        wps[w].z         = mem[c*350 + w*7 + 2];
        wps[w].vx        = mem[c*350 + w*7 + 3];
        wps[w].vy        = mem[c*350 + w*7 + 4];
        wps[w].heading   = mem[c*350 + w*7 + 5];
        wps[w].timestamp = mem[c*350 + w*7 + 6];
      end
      repeat (4) @(posedge clk);
      start <= 1'b1; @(posedge clk); start <= 1'b0;
      timeout = 0;
      while (!zvalid && timeout < 2_000_000) begin @(posedge clk); timeout++; end
      if (!zvalid) begin $display("ZG_TIMEOUT ca %0d", c); $fwrite(fo, "TIMEOUT %0d\n", c); end
      else
        for (int k = 0; k < NZ; k++)
          $fwrite(fo, "%0d %0d %0d %0d %0d %0d %0d\n", c, k,
                  $signed(zon[k*128+112 +: 16]), $signed(zon[k*128+96 +: 16]),
                  $signed(zon[k*128+16 +: 16]),  $signed(zon[k*128 +: 16]), ovf | zerr);
      repeat (20) @(posedge clk);
    end
    $fclose(fo);
    $display("ZG_DONE NZ=%0d ncase=%0d", NZ, ncase);
    $finish;
  end
endmodule
