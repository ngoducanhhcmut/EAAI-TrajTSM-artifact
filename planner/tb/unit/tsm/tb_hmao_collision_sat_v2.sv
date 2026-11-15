// =============================================================================
// tb_hmao_collision_sat_v2.sv — kiem thu don vi hmao_collision_sat v2 (hop ego vs hop vat can,
// vat can chuyen dong, SAT 4 truc, che do danh sach) so voi mo hinh tham chieu KHOP TUNG BIT
// (sw/eval_trainval/sat_v2_ref.py). Ba cau hinh DUT chay song song:
//   s1    : NZ=50,  MAX_OBS=100, LIST_MODE=0, DT=6554, CHK=50
//   s2    : NZ=100, MAX_OBS=16,  LIST_MODE=1, DT=3277, CHK=100
//   s1c20 : NZ=50,  MAX_OBS=100, LIST_MODE=0, DT=6554, CHK=20
// Moi ca so: potential/no_collision, suspicious_cnt, 16 muc suspicious_ids, buoc + track_id
// cua vi pham dau tien (violation_info[31:16], [47:32]).
//   python sw/eval_trainval/sat_v2_ref.py   (sinh tb/unit/tsm/vec/*)
// =============================================================================
`timescale 1ns/1ps
import hmao_pkg::*;

module sat_runner #(
  parameter string       TAG     = "s1",
  parameter int unsigned NZ      = 50,
  parameter int unsigned MAX_OBS = 100,
  parameter int unsigned LMODE   = 0,
  parameter int unsigned DTQ     = 6554,
  parameter int unsigned CHK     = 50,
  parameter int unsigned NCASE   = 200
) (
  input  logic clk,
  input  logic rst_n,
  output logic done,
  output int   n_pass,
  output int   n_fail
);
  localparam string VD = "tb/unit/tsm/vec/";

  logic [63:0]  zmem [0:NCASE*NZ-1];
  logic [31:0]  wmem [0:NCASE*100*16-1];
  logic [31:0]  pmem [0:NCASE*19-1];
  logic [31:0]  emem [0:NCASE*20-1];

  logic                        start;
  logic [NZ*128-1:0]           zin;
  logic [15:0]                 el, ew;
  logic [MAX_SUSPICIOUS_OBS*16-1:0] lst;
  logic [4:0]                  lcnt;
  logic                        no_coll, pot, ovf;
  logic [MAX_SUSPICIOUS_OBS*16-1:0] sids;
  logic [4:0]                  scnt;
  logic [63:0]                 vinfo;
  int                          cbase;      // chi so ca hien tai * 100 * 16

  axi4_ro_if #(.ADDR_W(32), .DATA_W(256)) axi_if(.aclk(clk), .aresetn(rst_n));

  hmao_collision_sat #(
    .NUM_ZONOTOPES(NZ), .NUM_GENERATORS(16), .MAX_OBSTACLES(MAX_OBS),
    .LIST_MODE(LMODE), .STEP_DT_Q16(DTQ), .MAX_CHECK_STEPS(CHK)
  ) u_dut (
    .clk(clk), .rst_n(rst_n), .start(start), .zonotopes_in(zin), .axi_ro(axi_if),
    .bbox_xmin('0), .bbox_xmax('0), .bbox_ymin('0), .bbox_ymax('0),
    .ego_half_len(el), .ego_half_wid(ew), .list_in(lst), .list_cnt(lcnt),
    .no_collision(no_coll), .potential_coll(pot), .suspicious_ids(sids), .suspicious_cnt(scnt),
    .violation_info(vinfo), .overflow_err(ovf)
  );

  // ---- AXI slave: 2 nhip / vat can, du lieu lay tu wmem theo dia chi ----
  typedef enum logic [1:0] {SL_IDLE, SL_AR, SL_B1, SL_B2} sl_t;
  sl_t sl; int slot;
  function automatic logic [255:0] beat(input int s, input int b);
    logic [255:0] r;
    for (int k = 0; k < 8; k++) r[k*32 +: 32] = wmem[cbase + s*16 + b*8 + k];
    return r;
  endfunction
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_if.arready <= 1'b0; axi_if.rvalid <= 1'b0; axi_if.rdata <= '0; axi_if.rlast <= 1'b0;
      axi_if.rresp <= '0; axi_if.rid <= '0; sl <= SL_IDLE; slot <= 0;
    end else begin
      case (sl)
        SL_IDLE: begin
          axi_if.arready <= 1'b0; axi_if.rvalid <= 1'b0; axi_if.rlast <= 1'b0;
          if (axi_if.arvalid) begin slot <= (axi_if.araddr - WORLD_MODEL_BASE) >> 6; sl <= SL_AR; end
        end
        SL_AR: begin axi_if.arready <= 1'b1; sl <= SL_B1; end
        SL_B1: begin
          axi_if.arready <= 1'b0; axi_if.rvalid <= 1'b1; axi_if.rlast <= 1'b0; axi_if.rdata <= beat(slot, 0);
          if (axi_if.rready) sl <= SL_B2;
        end
        SL_B2: begin
          axi_if.rvalid <= 1'b1; axi_if.rlast <= 1'b1; axi_if.rdata <= beat(slot, 1);
          if (axi_if.rready) begin axi_if.rvalid <= 1'b0; axi_if.rlast <= 1'b0; sl <= SL_IDLE; end
        end
      endcase
    end
  end

  int tmo, ci, e;
  logic ok;
  initial begin
    $readmemh({VD, TAG, "_zono.hex"}, zmem);
    $readmemh({VD, TAG, "_wm.hex"},   wmem);
    $readmemh({VD, TAG, "_par.hex"},  pmem);
    $readmemh({VD, TAG, "_exp.hex"},  emem);
    done = 0; n_pass = 0; n_fail = 0; start = 0; cbase = 0;
    @(posedge rst_n); repeat (5) @(posedge clk);
    for (ci = 0; ci < NCASE; ci++) begin
      cbase = ci * 100 * 16;
      for (int s = 0; s < NZ; s++) zin[s*128 +: 128] = {zmem[ci*NZ + s][63:32], 64'h0, zmem[ci*NZ + s][31:0]};
      el = pmem[ci*19 + 0][15:0]; ew = pmem[ci*19 + 1][15:0]; lcnt = pmem[ci*19 + 2][4:0];
      for (int k = 0; k < 16; k++) lst[k*16 +: 16] = pmem[ci*19 + 3 + k][15:0];
      @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;
      tmo = 0;
      // no_collision / potential_coll la xung 1 chu ky: doc NGAY khi thoat vong (gia tri truoc NBA
      // cua canh hien tai = gia tri SAT_DONE vua dat), khong cho them.
      while (!no_coll && !pot && tmo < 400000) begin @(posedge clk); tmo++; end
      e = ci * 20;
      ok = (pot == emem[e][0]) && (no_coll == !emem[e][0]) && (scnt == emem[e+1][4:0]) && (tmo < 400000);
      for (int k = 0; k < 16; k++) ok &= (sids[k*16 +: 16] == emem[e+2+k][15:0]);
      if (emem[e][0]) ok &= (vinfo[31:16] == emem[e+18][15:0]) && (vinfo[47:32] == emem[e+19][15:0]);
      if (ok) n_pass++;
      else begin
        n_fail++;
        if (n_fail <= 5)
          $display("[%s] ca %0d SAI: pot %0d/%0d cnt %0d/%0d buoc %0d/%0d obs %0d/%0d tmo %0d", TAG, ci,
                   pot, emem[e][0], scnt, emem[e+1], vinfo[31:16], emem[e+18], vinfo[47:32], emem[e+19], tmo);
      end
      repeat (3) @(posedge clk);
    end
    $display("[%s] %0d/%0d ca khop mo hinh tham chieu", TAG, n_pass, NCASE);
    done = 1;
  end
endmodule

module tb_hmao_collision_sat_v2;
  logic clk = 0, rst_n = 0;
  always #2.667 clk = ~clk;                 // 187,5 MHz
  initial begin repeat (10) @(posedge clk); rst_n = 1; end
  logic d1, d2, d3; int p1, f1, p2, f2, p3, f3;
  sat_runner #(.TAG("s1"),    .NZ(50),  .MAX_OBS(100), .LMODE(0), .DTQ(6554), .CHK(50))  r1 (clk, rst_n, d1, p1, f1);
  sat_runner #(.TAG("s2"),    .NZ(100), .MAX_OBS(16),  .LMODE(1), .DTQ(3277), .CHK(100)) r2 (clk, rst_n, d2, p2, f2);
  sat_runner #(.TAG("s1c20"), .NZ(50),  .MAX_OBS(100), .LMODE(0), .DTQ(6554), .CHK(20))  r3 (clk, rst_n, d3, p3, f3);
  initial begin
    wait (d1 && d2 && d3);
    $display("TONG KET SAT v2: %0d/%0d ca dung tung bit (khong dat %0d)", p1 + p2 + p3, p1 + p2 + p3 + f1 + f2 + f3,
             f1 + f2 + f3);
    if (f1 + f2 + f3 == 0) $display("==== TB_HMAO_COLLISION_SAT_V2: DAT ====");
    else                   $display("==== TB_HMAO_COLLISION_SAT_V2: KHONG DAT ====");
    $finish;
  end
endmodule
