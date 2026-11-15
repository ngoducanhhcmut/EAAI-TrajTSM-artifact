// =============================================================================
// FILE        : hmao_collision_sat.sv
// PROJECT     : HMAO Engine (TSM — Trajectory Safety Monitor)
// SPEC REF    : HMAO_Engine_Full_Spec v12.0 - Section 7.4
// SAFETY      : ASIL-D (ISO 26262)
// DESCRIPTION : Bo kiem tra va cham theo dinh ly truc phan tach (SAT) giua
//               HOP XE EGO va HOP VAT CAN co huong, vat can chuyen dong.
//
// THIET KE v2 (04/10/2026) — thay ban "diem tam vs hop thang truc" (xem
// .bak_v1point; ly do va so lieu: VERIFICATION_HISTORY AK.15):
//   * Hop xe ego: tam = tam zonotope (truc banh sau, lay tu waypoint) + EGO_C
//     theo huong h; nua dai EL, nua rong EW (dau vao, Q8.8 = kich thuoc xe/2 +
//     bien an toan).  Huong h = (cos, sin) Q8.8 lay tu truong rem_x/rem_y cua
//     zonotope (hmao_zonotope_gen v2 ghi vao).
//   * Hop vat can: tam p(t) = p0 + v*t (van toc trong world model, byte 12/16),
//     nua dai l/2 theo huong u, nua rong w/2 theo u_perp.
//   * Hai hop chu nhat chi can 4 truc: h, h_perp, u, u_perp (SAT chinh xac).
//     Ban kinh chieu: rE(u) = EL|cosD| + EW|sinD| ...  voi cosD = h.u, sinD = h_perp.u.
//   * Chi xet buoc step_idx < MAX_CHECK_STEPS. Gap va cham o mot buoc -> ghi
//     vat can vao danh sach nghi ngo (MOT lan) va chuyen sang vat can ke tiep.
//   * LIST_MODE = 1 (tang 2): chi quet cac vat can trong list_in[0..list_cnt-1]
//     (chi so o nho world model do tang 1 ghi), khong quet 16 muc dau WM.
//   * Bo loc hop bao cu da bo (vat can chuyen dong co the di vao quy dao); chi
//     bo qua o co do tin cay = 0.  So chu ky moi (vat can, buoc) giu nguyen 5.
// =============================================================================

`timescale 1ns/1ps
import hmao_pkg::*;

module hmao_collision_sat #(
  parameter int unsigned NUM_ZONOTOPES   = 50,
  parameter int unsigned NUM_GENERATORS  = 16,
  parameter int unsigned MAX_OBSTACLES   = 100,
  parameter int unsigned LIST_MODE       = 0,          // 1: chi quet danh sach nghi ngo
  parameter int unsigned STEP_DT_Q16     = 6554,       // do dai mot buoc (s) * 65536: 0,1 s
  parameter int unsigned MAX_CHECK_STEPS = NUM_ZONOTOPES
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,

  // Flat 1D vector — element k at [k*128+:128]
  // Field offsets: cx=+112, cy=+96, g1x=+80, g1y=+64, g2x=+48, g2y=+32,
  //                rem_x=+16 (= cos h, Q8.8), rem_y=+0 (= sin h, Q8.8)
  input  logic [NUM_ZONOTOPES*128-1:0] zonotopes_in,

  axi4_ro_if.master               axi_ro,

  // Giu cong cho tuong thich (khong con dung lam bo loc)
  input  logic [31:0]             bbox_xmin, bbox_xmax,
  input  logic [31:0]             bbox_ymin, bbox_ymax,

  // Kich thuoc hop xe ego (nua dai / nua rong, Q8.8, da gom bien an toan)
  input  logic [15:0]             ego_half_len,
  input  logic [15:0]             ego_half_wid,

  // LIST_MODE: danh sach chi so o world model (moi muc 16 bit, dung 7 bit thap)
  input  logic [MAX_SUSPICIOUS_OBS*16-1:0] list_in,
  input  logic [4:0]              list_cnt,

  output logic                    no_collision,
  output logic                    potential_coll,
  // Danh sach nghi ngo: CHI SO o world model (khong phai track_id)
  output logic [MAX_SUSPICIOUS_OBS*16-1:0] suspicious_ids,
  output logic [4:0]              suspicious_cnt,
  output logic [63:0]             violation_info,
  output logic                    overflow_err
);

  // Tam xe cach truc banh sau 1,38 m (Renault Zoe cua nuScenes): 1,38*256 = 353
  localparam logic signed [15:0] EGO_C_Q88 = 16'sd353;

  // ===========================================================================
  // STATE MACHINE
  // ===========================================================================
  typedef enum logic [3:0] {
    SAT_IDLE     = 4'b0000,
    SAT_FETCH    = 4'b0001,
    SAT_PREFILTER= 4'b0010,
    SAT_AXES     = 4'b0011,
    SAT_PIPE1    = 4'b0100,
    SAT_PIPE2    = 4'b0101,
    SAT_PIPE3    = 4'b1001,
    SAT_DECIDE   = 4'b0110,
    SAT_DONE     = 4'b0111,
    SAT_ERROR    = 4'b1000
  } sat_state_t;

  sat_state_t   sat_state;
  logic [6:0]   obs_idx;         // chi so vong lap (LIST_MODE: chi so trong danh sach)
  logic [6:0]   obs_slot;        // o world model dang xet
  logic [6:0]   step_idx;

  logic [31:0] obs_pos_x, obs_pos_y, obs_vel_x, obs_vel_y;
  logic [31:0] obs_dim_length, obs_dim_width;
  logic [31:0] obs_heading;
  logic [15:0] obs_track_id;
  logic [7:0]  obs_confidence;
  logic        obs_fetched;

  logic [4:0]   suspicious_count;
  logic [MAX_SUSPICIOUS_OBS*16-1:0] suspicious_buf;
  logic [6:0]   first_violation_step;
  logic [15:0]  first_violation_obs;
  logic         violation_found;

  // ===========================================================================
  // CHI SO VONG LAP -> O WORLD MODEL
  // ===========================================================================
  logic [6:0] list_slot;
  always_comb begin
    list_slot = '0;
    for (int k = 0; k < MAX_SUSPICIOUS_OBS; k++)
      if (obs_idx == k[6:0]) list_slot = list_in[k*16 +: 7];
  end
  logic [6:0] last_obs_idx;
  assign last_obs_idx = (LIST_MODE != 0) ? 7'(list_cnt - 5'd1) : 7'(MAX_OBSTACLES - 1);

  // ===========================================================================
  // ZONOTOPE MUX (case-mux theo step_idx)
  // ===========================================================================
  logic [15:0] zon_cx, zon_cy, zon_hc, zon_hs;
  always_comb begin
    zon_cx = zonotopes_in[127:112];
    zon_cy = zonotopes_in[111:96];
    zon_hc = zonotopes_in[31:16];
    zon_hs = zonotopes_in[15:0];
    for (int s = 0; s < NUM_ZONOTOPES; s++) begin
      if (step_idx == s[6:0]) begin
        zon_cx = zonotopes_in[s*128+112 +: 16];
        zon_cy = zonotopes_in[s*128+96  +: 16];
        zon_hc = zonotopes_in[s*128+16  +: 16];
        zon_hs = zonotopes_in[s*128     +: 16];
      end
    end
  end

  // ===========================================================================
  // DUONG ONG HINH HOC (AXES -> P1 -> P2 -> P3 -> DECIDE)
  // ===========================================================================
  // Thanh ghi chot o SAT_AXES
  logic signed [31:0] cur_cx, cur_cy, cur_hc, cur_hs;
  logic        [22:0] cur_t;            // t = step_idx * STEP_DT_Q16 (Q.16 giay)
  logic signed [31:0] cur_uc, cur_us, cur_lo, cur_wo, cur_el, cur_ew;
  logic signed [31:0] cur_px, cur_py, cur_vx, cur_vy;

  // P1
  logic signed [31:0] p1_ex, p1_ey, p1_ox, p1_oy, p1_cosd, p1_sind;
  logic signed [31:0] p1_hc, p1_hs, p1_uc, p1_us, p1_lo, p1_wo, p1_el, p1_ew;
  // P2
  logic signed [31:0] p2_dx, p2_dy, p2_c, p2_s;
  logic signed [31:0] p2_hc, p2_hs, p2_uc, p2_us, p2_lo, p2_wo, p2_el, p2_ew;
  // P3
  logic signed [31:0] p3_dh, p3_dhp, p3_du, p3_dup;
  logic signed [31:0] p3_reu, p3_reup, p3_rbh, p3_rbhp;
  logic signed [31:0] p3_lo, p3_wo, p3_el, p3_ew;

  function automatic logic signed [31:0] sx16(input logic [15:0] v);
    return {{16{v[15]}}, v};
  endfunction
  function automatic logic signed [31:0] abs32(input logic signed [31:0] v);
    return (v < 0) ? -v : v;
  endfunction
  // (a*b) >>> 8 voi a, b Q8.8 -> Q8.8 (tich 48 bit tranh tran)
  function automatic logic signed [31:0] mul88(input logic signed [31:0] a, input logic signed [31:0] b);
    logic signed [63:0] p;
    p = 64'(a) * 64'(b);
    return 32'(p >>> 8);
  endfunction

  // P1 to hop
  logic signed [63:0] vt_x, vt_y;
  assign vt_x = 64'(cur_vx) * $signed({41'b0, cur_t});
  assign vt_y = 64'(cur_vy) * $signed({41'b0, cur_t});

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      p1_ex <= '0; p1_ey <= '0; p1_ox <= '0; p1_oy <= '0; p1_cosd <= '0; p1_sind <= '0;
      p1_hc <= '0; p1_hs <= '0; p1_uc <= '0; p1_us <= '0; p1_lo <= '0; p1_wo <= '0; p1_el <= '0; p1_ew <= '0;
      p2_dx <= '0; p2_dy <= '0; p2_c <= '0; p2_s <= '0;
      p2_hc <= '0; p2_hs <= '0; p2_uc <= '0; p2_us <= '0; p2_lo <= '0; p2_wo <= '0; p2_el <= '0; p2_ew <= '0;
      p3_dh <= '0; p3_dhp <= '0; p3_du <= '0; p3_dup <= '0;
      p3_reu <= '0; p3_reup <= '0; p3_rbh <= '0; p3_rbhp <= '0;
      p3_lo <= '0; p3_wo <= '0; p3_el <= '0; p3_ew <= '0;
    end else begin
      // ---- P1: tam hop ego, vi tri vat can tai t, cos/sin goc lech ----
      p1_ex   <= cur_cx + mul88(EGO_C_Q88, cur_hc);
      p1_ey   <= cur_cy + mul88(EGO_C_Q88, cur_hs);
      p1_ox   <= cur_px + 32'(vt_x >>> 16);
      p1_oy   <= cur_py + 32'(vt_y >>> 16);
      p1_cosd <= mul88(cur_hc, cur_uc) + mul88(cur_hs, cur_us);   // h . u
      p1_sind <= mul88(cur_hc, cur_us) - mul88(cur_hs, cur_uc);   // h_perp . u
      p1_hc <= cur_hc; p1_hs <= cur_hs; p1_uc <= cur_uc; p1_us <= cur_us;
      p1_lo <= cur_lo; p1_wo <= cur_wo; p1_el <= cur_el; p1_ew <= cur_ew;
      // ---- P2: hieu tam, |cosD|, |sinD| ----
      p2_dx <= p1_ex - p1_ox;
      p2_dy <= p1_ey - p1_oy;
      p2_c  <= abs32(p1_cosd);
      p2_s  <= abs32(p1_sind);
      p2_hc <= p1_hc; p2_hs <= p1_hs; p2_uc <= p1_uc; p2_us <= p1_us;
      p2_lo <= p1_lo; p2_wo <= p1_wo; p2_el <= p1_el; p2_ew <= p1_ew;
      // ---- P3: hinh chieu khoang cach tam len 4 truc + ban kinh chieu ----
      p3_dh   <= abs32(mul88(p2_dx, p2_hc) + mul88(p2_dy, p2_hs));     // |d . h|
      p3_dhp  <= abs32(mul88(p2_dy, p2_hc) - mul88(p2_dx, p2_hs));     // |d . h_perp|
      p3_du   <= abs32(mul88(p2_dx, p2_uc) + mul88(p2_dy, p2_us));     // |d . u|
      p3_dup  <= abs32(mul88(p2_dy, p2_uc) - mul88(p2_dx, p2_us));     // |d . u_perp|
      p3_reu  <= mul88(p2_el, p2_c) + mul88(p2_ew, p2_s);              // rE tren u
      p3_reup <= mul88(p2_el, p2_s) + mul88(p2_ew, p2_c);              // rE tren u_perp
      p3_rbh  <= mul88(p2_lo, p2_c) + mul88(p2_wo, p2_s);              // rB tren h
      p3_rbhp <= mul88(p2_lo, p2_s) + mul88(p2_wo, p2_c);              // rB tren h_perp
      p3_lo <= p2_lo; p3_wo <= p2_wo; p3_el <= p2_el; p3_ew <= p2_ew;
    end
  end

  logic separated_this_step, collision_this_step, step_ok;
  assign separated_this_step = (p3_dh  > p3_el   + p3_rbh ) ||
                               (p3_dhp > p3_ew   + p3_rbhp) ||
                               (p3_du  > p3_reu  + p3_lo  ) ||
                               (p3_dup > p3_reup + p3_wo  );
  assign step_ok             = (step_idx < 7'(MAX_CHECK_STEPS));
  assign collision_this_step = ~separated_this_step && step_ok && (obs_confidence != 8'h0);

  // ===========================================================================
  // NAP WORLD MODEL QUA AXI (2 nhip 256 bit / vat can)
  //   Nhip 1 (byte 0..31):  pos_x[31:0], pos_y[63:32], vel_x[127:96], vel_y[159:128],
  //                         dim_length[223:192], dim_width[255:224]
  //   Nhip 2 (byte 32..63): heading {sin,cos}[63:32], track_id[79:64], confidence[95:88]
  // ===========================================================================
  logic ar_done;
  logic beat1_done;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_ro.arid    <= '0;
      axi_ro.arvalid <= 1'b0;
      axi_ro.araddr  <= '0;
      axi_ro.arlen   <= 8'd1;
      axi_ro.arsize  <= 3'b101;
      axi_ro.arburst <= 2'b01;
      axi_ro.aruser  <= HMAO_MASTER_ID;
      axi_ro.rready  <= 1'b0;
      obs_fetched    <= 1'b0;
      ar_done        <= 1'b0;
      beat1_done     <= 1'b0;
      obs_pos_x      <= '0;
      obs_pos_y      <= '0;
      obs_vel_x      <= '0;
      obs_vel_y      <= '0;
      obs_dim_length <= '0;
      obs_dim_width  <= '0;
      obs_heading    <= '0;
      obs_track_id   <= '0;
      obs_confidence <= '0;
    end else begin
      case (sat_state)
        SAT_FETCH: begin
          if (!ar_done && !obs_fetched) begin
            if (!axi_ro.arvalid) begin
              axi_ro.arvalid <= 1'b1;
              axi_ro.araddr  <= WORLD_MODEL_BASE + {obs_slot, 6'b0};
            end else if (axi_ro.arready) begin
              axi_ro.arvalid <= 1'b0;
              axi_ro.rready  <= 1'b1;
              ar_done        <= 1'b1;
            end
          end
          if (axi_ro.rvalid && axi_ro.rready) begin
            if (!beat1_done) begin
              obs_pos_x      <= axi_ro.rdata[31:0];
              obs_pos_y      <= axi_ro.rdata[63:32];
              obs_vel_x      <= axi_ro.rdata[127:96];
              obs_vel_y      <= axi_ro.rdata[159:128];
              obs_dim_length <= axi_ro.rdata[223:192];
              obs_dim_width  <= axi_ro.rdata[255:224];
              beat1_done     <= 1'b1;
              axi_ro.rready  <= 1'b0;
            end else begin
              obs_heading    <= axi_ro.rdata[63:32];
              obs_track_id   <= axi_ro.rdata[79:64];
              obs_confidence <= axi_ro.rdata[95:88];
              axi_ro.rready  <= 1'b0;
              obs_fetched    <= 1'b1;
            end
          end else if (beat1_done && !obs_fetched) begin
            axi_ro.rready <= 1'b1;
          end
        end
        default: begin
          obs_fetched    <= 1'b0;
          axi_ro.arvalid <= 1'b0;
          ar_done        <= 1'b0;
          beat1_done     <= 1'b0;
        end
      endcase
    end
  end

  // ===========================================================================
  // MAY TRANG THAI CHINH
  // ===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sat_state        <= SAT_IDLE;
      obs_idx          <= '0;
      obs_slot         <= '0;
      step_idx         <= '0;
      no_collision     <= 1'b0;
      potential_coll   <= 1'b0;
      suspicious_count <= '0;
      suspicious_cnt   <= '0;
      violation_found  <= 1'b0;
      overflow_err     <= 1'b0;
      suspicious_buf   <= '0;
      suspicious_ids   <= '0;
      violation_info   <= '0;
      first_violation_step <= '0;
      first_violation_obs  <= '0;
      cur_cx <= '0; cur_cy <= '0; cur_hc <= '0; cur_hs <= '0; cur_t <= '0;
      cur_uc <= '0; cur_us <= '0; cur_lo <= '0; cur_wo <= '0; cur_el <= '0; cur_ew <= '0;
      cur_px <= '0; cur_py <= '0; cur_vx <= '0; cur_vy <= '0;
    end else begin
      unique case (sat_state)

        SAT_IDLE: begin
          no_collision     <= 1'b0;
          potential_coll   <= 1'b0;
          if (start) begin
            suspicious_count <= '0;
            suspicious_buf   <= '0;
            violation_found  <= 1'b0;
            obs_idx          <= '0;
            step_idx         <= '0;
            obs_slot         <= (LIST_MODE != 0) ? list_in[6:0] : 7'd0;
            sat_state        <= ((LIST_MODE != 0) && (list_cnt == 5'd0)) ? SAT_DONE : SAT_FETCH;
          end
        end

        SAT_FETCH: begin
          if (obs_fetched) sat_state <= SAT_PREFILTER;
        end

        // Chi bo qua o trong (do tin cay = 0); khong con loc hop bao.
        SAT_PREFILTER: begin
          if (obs_confidence == 8'h0) begin
            if (obs_idx < last_obs_idx) begin
              obs_idx   <= obs_idx + 1'b1;
              obs_slot  <= (LIST_MODE != 0) ? list_slot_next(obs_idx) : obs_idx + 1'b1;
              sat_state <= SAT_FETCH;
            end else sat_state <= SAT_DONE;
          end else begin
            step_idx  <= '0;
            sat_state <= SAT_AXES;
          end
        end

        SAT_AXES: begin
          cur_cx <= sx16(zon_cx);  cur_cy <= sx16(zon_cy);
          cur_hc <= sx16(zon_hc);  cur_hs <= sx16(zon_hs);
          cur_t  <= 23'(step_idx * STEP_DT_Q16);
          cur_uc <= sx16(obs_heading[15:0]);  cur_us <= sx16(obs_heading[31:16]);
          cur_lo <= $signed(obs_dim_length) >>> 1;
          cur_wo <= $signed(obs_dim_width)  >>> 1;
          cur_el <= {16'b0, ego_half_len};
          cur_ew <= {16'b0, ego_half_wid};
          cur_px <= obs_pos_x;  cur_py <= obs_pos_y;
          cur_vx <= obs_vel_x;  cur_vy <= obs_vel_y;
          sat_state <= SAT_PIPE1;
        end

        SAT_PIPE1: sat_state <= SAT_PIPE2;
        SAT_PIPE2: sat_state <= SAT_PIPE3;
        SAT_PIPE3: sat_state <= SAT_DECIDE;

        SAT_DECIDE: begin
          if (collision_this_step) begin
            if (!violation_found) begin
              violation_found      <= 1'b1;
              first_violation_step <= step_idx;
              first_violation_obs  <= obs_track_id;
            end
            if (suspicious_count < 5'(MAX_SUSPICIOUS_OBS)) begin
              for (int k = 0; k < MAX_SUSPICIOUS_OBS; k++)
                if (suspicious_count[3:0] == k[3:0]) suspicious_buf[k*16 +: 16] <= {9'b0, obs_slot};
              suspicious_count <= suspicious_count + 1'b1;
            end
          end
          // Sang vat can ke tiep khi: da va cham (ghi mot lan), het buoc can xet, hoac het buoc
          if (collision_this_step || step_idx >= 7'(NUM_ZONOTOPES - 1) ||
              step_idx >= 7'(MAX_CHECK_STEPS - 1)) begin
            if (obs_idx < last_obs_idx) begin
              obs_idx   <= obs_idx + 1'b1;
              obs_slot  <= (LIST_MODE != 0) ? list_slot_next(obs_idx) : obs_idx + 1'b1;
              step_idx  <= '0;
              sat_state <= SAT_FETCH;
            end else sat_state <= SAT_DONE;
          end else begin
            step_idx  <= step_idx + 1'b1;
            sat_state <= SAT_AXES;
          end
        end

        SAT_DONE: begin
          no_collision   <= ~violation_found;
          potential_coll <=  violation_found;
          violation_info[63:56] <= 8'h01;  // VIOL_STAGE1
          violation_info[55:48] <= 8'h01;  // VIOL_LATERAL
          violation_info[47:32] <= first_violation_obs;
          violation_info[31:16] <= {9'b0, first_violation_step};
          violation_info[15:0]  <= {11'b0, suspicious_count};
          suspicious_ids <= suspicious_buf;
          suspicious_cnt <= suspicious_count;
          sat_state <= SAT_IDLE;
        end

        default: begin
          sat_state    <= SAT_ERROR;
          overflow_err <= 1'b1;
        end
      endcase
    end
  end

  // O world model cua muc danh sach ke tiep (LIST_MODE)
  function automatic logic [6:0] list_slot_next(input logic [6:0] cur);
    logic [6:0] r;
    r = '0;
    for (int k = 0; k < MAX_SUSPICIOUS_OBS; k++)
      if (cur + 7'd1 == k[6:0]) r = list_in[k*16 +: 7];
    return r;
  endfunction

  // ===========================================================================
  // FORMAL ASSERTIONS
  // ===========================================================================
  `ifdef FORMAL
    assert property (@(posedge clk) !(no_collision && potential_coll))
      else $error("SAT: no_collision and potential_coll both asserted");
  `endif

endmodule : hmao_collision_sat
