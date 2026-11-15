//==============================================================================
// tb_world_model_parser.sv — cong kiem B2 (VERIFICATION_HISTORY.md muc AE.5/AF)
//
// - BRAM hdr/obj/lane la dual_port_ram REGISTERED_OUTPUT(0), GIONG planning_top.sv
//   -> do tre doc la do tre that.
// - Noi dung BRAM nap tu byte DDR golden (sw/gen_parser_tb_vectors.py), dung cach
//   weight_loader ghi (obj buoc 12, lane buoc 32).
// - token_ready NGAU NHIEN (~70% =1) de kiem parser chiu nghen phia sau.
// - So TUNG BIT moi token voi golden (mo hinh Python rtl_parser_model), so luong
//   token, token_last o dung token cuoi, attn_mask.
//==============================================================================
`timescale 1ns / 1ps

module tb_world_model_parser;
  import planning_pkg::*;

  localparam string VEC = "tb/unit/parser_vec/";

  logic clk = 1'b0, rst_n = 1'b0;
  always #2.5 clk = ~clk;

  logic  [1:0] hdr_rd_addr;  logic [31:0] hdr_rd_data;  logic hdr_rd_en;
  logic [11:0] obj_rd_addr;  logic [31:0] obj_rd_data;  logic obj_rd_en;
  logic  [9:0] lane_rd_addr; logic [31:0] lane_rd_data; logic lane_rd_en;

  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(4), .REGISTERED_OUTPUT(0)) u_hdr (
    .clk_a(clk), .rst_a_n(rst_n), .ena(1'b0), .wea(1'b0), .addra('0), .dina('0), .douta(),
    .clk_b(clk), .rst_b_n(rst_n), .enb(hdr_rd_en), .web(1'b0), .addrb(hdr_rd_addr),
    .dinb('0), .doutb(hdr_rd_data));
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(4096), .REGISTERED_OUTPUT(0)) u_obj (
    .clk_a(clk), .rst_a_n(rst_n), .ena(1'b0), .wea(1'b0), .addra('0), .dina('0), .douta(),
    .clk_b(clk), .rst_b_n(rst_n), .enb(obj_rd_en), .web(1'b0), .addrb(obj_rd_addr),
    .dinb('0), .doutb(obj_rd_data));
  dual_port_ram #(.DATA_WIDTH(32), .DEPTH(1024), .REGISTERED_OUTPUT(0)) u_lane (
    .clk_a(clk), .rst_a_n(rst_n), .ena(1'b0), .wea(1'b0), .addra('0), .dina('0), .douta(),
    .clk_b(clk), .rst_b_n(rst_n), .enb(lane_rd_en), .web(1'b0), .addrb(lane_rd_addr),
    .dinb('0), .doutb(lane_rd_data));

  logic        parse_start = 1'b0, parse_done, parse_busy;
  logic  [7:0] wm_num_objects = '0;
  logic  [4:0] wm_num_lanes = '0;
  bbox6_t      token_out;
  token_type_t token_type_out;
  logic        token_valid, token_ready = 1'b1, token_last;
  attn_mask_t  attn_mask_out;
  logic  [7:0] num_tokens_out;

  world_model_parser #(.EMIT_TARGET(1'b0)) dut (
    .clk, .rst_n, .parse_start, .parse_done, .parse_busy,
    .hdr_rd_addr, .hdr_rd_data, .hdr_rd_en,
    .obj_rd_addr, .obj_rd_data, .obj_rd_en,
    .lane_rd_addr, .lane_rd_data, .lane_rd_en,
    .wm_num_objects, .wm_num_lanes,
    .target_x(32'h41200000), .target_y(32'h41200000),   // 10.0 — khong duoc xuat hien
    .token_out, .token_type_out, .token_valid, .token_ready, .token_last,
    .attn_mask_out, .num_tokens_out);

  // token_ready ngau nhien (~70% = 1)
  always @(posedge clk) token_ready <= ($urandom % 10) < 7;

  // Thu token
  logic [31:0] got [0:63][0:5];
  int          n_got;
  int          last_at;
  always @(posedge clk) begin
    if (token_valid) begin
      if (n_got < 64) begin
        got[n_got][0] = token_out.x_min; got[n_got][1] = token_out.y_min;
        got[n_got][2] = token_out.x_max; got[n_got][3] = token_out.y_max;
        got[n_got][4] = token_out.vx;    got[n_got][5] = token_out.vy;
      end
      if (token_last) last_at = n_got;
      n_got++;
    end
  end

  int n_samples, total_fail, total_tok;
  int fd, n_obj, n_lane, n_tok;
  logic [31:0] exp_t [0:63][0:5];

  initial begin
    string line;
    int s;
    total_fail = 0; total_tok = 0;
    fd = $fopen({VEC, "meta.txt"}, "r");
    if (fd == 0) begin $display("KHONG MO DUOC meta.txt"); $finish; end
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    s = 0;
    while ($fscanf(fd, "%d %d %d", n_obj, n_lane, n_tok) == 3) begin
      int fe, nerr;
      // Nap BRAM va token mong doi
      $readmemh($sformatf("%ss%02d_hdr.hex",  VEC, s), u_hdr.mem);
      $readmemh($sformatf("%ss%02d_obj.hex",  VEC, s), u_obj.mem);
      $readmemh($sformatf("%ss%02d_lane.hex", VEC, s), u_lane.mem);
      fe = $fopen($sformatf("%ss%02d_exp.hex", VEC, s), "r");
      for (int t = 0; t < 64; t++)
        void'($fscanf(fe, "%h %h %h %h %h %h", exp_t[t][0], exp_t[t][1], exp_t[t][2],
                                                exp_t[t][3], exp_t[t][4], exp_t[t][5]));
      $fclose(fe);
      wm_num_objects = n_obj[7:0];
      wm_num_lanes   = n_lane[4:0];
      n_got = 0; last_at = -1;

      @(posedge clk); parse_start <= 1'b1;
      @(posedge clk); parse_start <= 1'b0;
      // Cho parse_done (khong dung fork/disable fork: xsim 2023.2 sap voi cau truc do)
      begin
        int to;
        to = 0;
        while (!parse_done && to < 200000) begin @(posedge clk); to++; end
        if (to >= 200000) $display("  s%02d: HET GIO", s);
      end
      repeat (3) @(posedge clk);

      nerr = 0;
      if (n_got != n_tok) begin
        nerr++; $display("  s%02d: so token %0d, mong %0d", s, n_got, n_tok);
      end
      for (int t = 0; t < n_tok && t < n_got; t++)
        for (int c = 0; c < 6; c++)
          if (got[t][c] !== exp_t[t][c]) begin
            if (nerr < 6) $display("  s%02d tok%0d truong%0d: %08h  mong %08h", s, t, c, got[t][c], exp_t[t][c]);
            nerr++;
          end
      if (last_at != n_tok - 1) begin
        nerr++; $display("  s%02d: token_last o token %0d, mong %0d", s, last_at, n_tok - 1);
      end
      if (attn_mask_out !== attn_mask_t'((64'd1 << n_tok) - 1)) begin
        nerr++; $display("  s%02d: attn_mask %h", s, attn_mask_out);
      end
      if (nerr == 0) $display("  s%02d: obj=%2d lane=%0d token=%2d  -> DUNG TUNG BIT", s, n_obj, n_lane, n_got);
      else           $display("  s%02d: obj=%2d lane=%0d token=%2d  -> %0d LOI", s, n_obj, n_lane, n_got, nerr);
      total_fail += (nerr != 0);
      total_tok  += n_tok;
      s++;
    end
    $fclose(fd);
    $display("\n==== TONG KET: %0d/%0d mau dung tung bit (%0d token) ====", s - total_fail, s, total_tok);
    $finish;
  end
endmodule
