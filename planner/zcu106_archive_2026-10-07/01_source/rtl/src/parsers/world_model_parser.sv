//==============================================================================
// File: world_model_parser.sv
// Description: World Model Parser — doc header/object/lane tu BRAM (do
//   weight_loader nap tu DDR), tao chuoi token bbox6_t cho khoi Traj.
//
// [B2, 01/10/2026] VIET LAI PHAN THAN. Ban truoc (xem .bak_B2) co 5 loi da do:
//   1. EGO thieu khung xe: phat {0,0,0,0,vx,vy}; mo hinh can {-L/2,-W/2,L/2,W/2,vx,vy}.
//   2. Object la MA TAM ("use center pos as bbox for now"): phat {x,y,l,w,vx,vy};
//      mo hinh can {x-l/2, y-w/2, x+l/2, y+w/2, vx, vy}.
//   3. Luon phat TARGET; mo hinh duoc huan luyen KHONG co TARGET
//      (eval/train_autoregressive_200ep.json: include_target_token_proxy=False).
//   4. Doc object o dia chi obj_idx*16; weight_loader GHI o obj_idx*12.
//   5. Doc object/lane lech 2 word: dia chi lay obj_word_cnt CU, va gia dinh BRAM
//      tre 1 chu ky. Thuc te hdr/obj/lane la dual_port_ram OREG=0: du lieu hop le
//      DUNG 2 CHU KY sau chu ky phat dia chi (dia chi qua NBA +1, doutb_int +1).
//   (Doc header da DUNG tu truoc — giu nguyen cach lam.)
//
//   Dac ta token = mo hinh Python sw/wm_spec_pack.py::rtl_parser_model
//   (da kiem: CLS/EGO/LANE/mask giong tung bit voi token huan luyen; object lech
//   toi da 3,8e-6 m do so hoc FP32 — xem VERIFICATION_HISTORY.md muc AF).
//
//   Chuoi token (khi EMIT_TARGET = 0, mac dinh):
//     [0] CLS = 0
//     [1] EGO = {-L/2, -W/2, L/2, W/2, ego_vx, ego_vy}   (L = 4.6 m, W = 2.0 m)
//     [2..] OBJ = {x - l/2, y - w/2, x + l/2, y + w/2, vx, vy}
//     [..] LANE = {wp_x[0], wp_y[0], wp_x[1], wp_y[1], 0, lane_type}
//   So object = min(num_objects, 64 - 3 - num_lanes) — giong phan mem.
//
//   Dinh dang BRAM (do weight_loader ghi):
//     hdr_bram : [0] num_objects, [1] num_lanes, [2] ego_vx, [3] ego_vy
//     obj_bram : obj k word i tai k*12 + i : x,y,vx,vy,l,w,type,id,pad x4
//     lane_bram: lane j word i tai j*32 + i: num_wp, lane_type, wp_x[10], wp_y[10], pad
//
// Spec: VLA_HMAO_SPEC_v15_5.txt §3.7, §4.2
//==============================================================================

`timescale 1ns / 1ps

module world_model_parser
  import planning_pkg::*;
#(
  // 0 = KHONG phat token TARGET (dung voi checkpoint hien tai).
  // 1 = phat TARGET tu CSR target_x/target_y (cho mo hinh huan luyen co TARGET).
  parameter bit EMIT_TARGET = 1'b0
)(
  input  logic        clk,
  input  logic        rst_n,

  //── Control ───────────────────────────────────────────────────────────────────
  input  logic        parse_start,     // pulse from planning_top (1cy after wm_fetch_done)
  output logic        parse_done,      // pulse: all tokens pushed to token_fifo
  output logic        parse_busy,

  //── Header BRAM read port (from weight_loader, 4 words) ──────────────────────
  output logic  [1:0] hdr_rd_addr,
  input  logic [31:0] hdr_rd_data,
  output logic        hdr_rd_en,

  //── Object BRAM read port (up to 200 objects × 12 words = 2400 words) ────────
  output logic [11:0] obj_rd_addr,
  input  logic [31:0] obj_rd_data,
  output logic        obj_rd_en,

  //── Lane BRAM read port (up to 20 lanes × 32 words = 640 words) ──────────────
  output logic  [9:0] lane_rd_addr,
  input  logic [31:0] lane_rd_data,
  output logic        lane_rd_en,

  //── num_objects / num_lanes (from weight_loader header extraction) ─────────────
  input  logic  [7:0] wm_num_objects,  // 0..200
  input  logic  [4:0] wm_num_lanes,    // 0..20

  //── CSR inputs for TARGET and EGO ────────────────────────────────────────────
  input  fp32_t       target_x,
  input  fp32_t       target_y,

  //── Token output stream (to token_fifo) ─────────────────────────────────────
  output bbox6_t      token_out,       // 24B = 6 × FP32
  output token_type_t token_type_out,
  output logic        token_valid,
  input  logic        token_ready,     // from token_fifo
  output logic        token_last,      // final token in sequence

  //── Attention mask output (bit k=1 → token k is valid) ──────────────────────
  output attn_mask_t  attn_mask_out,   // [MAX_SEQ_LEN-1:0]
  output logic  [7:0] num_tokens_out   // total tokens emitted
);

  //============================================================================
  // Hang so
  //============================================================================
  // Khung xe EGO o dang FP32 (mo hinh: EGO_LENGTH = 4.6, EGO_WIDTH = 2.0).
  // Mau bit da doi chieu voi numpy: float32(2.3) = 0x40133333, float32(1.0) = 0x3F800000.
  localparam fp32_t EGO_NEG_HALF_L = 32'hC0133333;  // -2.3
  localparam fp32_t EGO_NEG_HALF_W = 32'hBF800000;  // -1.0
  localparam fp32_t EGO_POS_HALF_L = 32'h40133333;  // +2.3
  localparam fp32_t EGO_POS_HALF_W = 32'h3F800000;  // +1.0
  localparam fp32_t FP32_HALF      = 32'h3F000000;  //  0.5

  // Do tre BRAM tu chu ky phat dia chi (NBA) den chu ky du lieu hop le.
  // hdr/obj/lane la dual_port_ram REGISTERED_OUTPUT(0) trong planning_top.sv.
  localparam int BRAM_LAT = 2;

  // Word can doc
  localparam int OBJ_NWORDS  = 6;   // x, y, vx, vy, l, w
  localparam int LANE_NREADS = 5;   // lane_type, wp_x[0], wp_x[1], wp_y[0], wp_y[1]

  //============================================================================
  // FSM
  //============================================================================
  typedef enum logic [3:0] {
    S_IDLE        = 4'd0,
    S_HEADER      = 4'd1,
    S_CLS_EMIT    = 4'd2,
    S_EGO_EMIT    = 4'd3,
    S_OBJ_READ    = 4'd4,
    S_OBJ_HALF    = 4'd5,   // hl = l*0.5, hw = w*0.5
    S_OBJ_BOX     = 4'd6,   // x+-hl, y+-hw
    S_OBJ_EMIT    = 4'd7,
    S_LANE_READ   = 4'd8,
    S_LANE_EMIT   = 4'd9,
    S_TARGET_EMIT = 4'd10,
    S_DONE        = 4'd11
  } state_t;

  state_t state;

  //============================================================================
  // Bo dem / thanh ghi
  //============================================================================
  logic [7:0]  obj_idx;
  logic [4:0]  lane_idx;
  logic [1:0]  hdr_cnt;
  logic        bram_latency;   // chi dung cho doc header (da dung tu truoc)

  // Duong ong doc 2 tang: chi so word di kem du lieu (xem B2 loi 5).
  logic [3:0]  rd_issue;       // so lan da phat dia chi trong dot doc hien tai
  logic        rp_v1, rp_v2;   // hop le tai tang 1 / tang 2
  logic [3:0]  rp_i1, rp_i2;   // chi so word tai tang 1 / tang 2

  fp32_t ego_vx_latch, ego_vy_latch;

  fp32_t obj_w [0:OBJ_NWORDS-1];     // x, y, vx, vy, l, w
  fp32_t obj_hl, obj_hw;
  // [TIMING 150 MHz, 02/10] Phep FP32 qua don vi CO DUONG ONG (3 tang), chung minh trung
  // tung bit voi fp32_mul_f / fp32_add_f (tb/unit/tb_fp32_mul_equiv, tb_fp32_add_legacy).
  // Dau vao giu on dinh tu thanh ghi; cho 4 chu ky moi lay ket qua (pw_cnt).
  logic [2:0] pw_cnt;
  fp32_t hl_p, hw_p, xmin_p, ymin_p, xmax_p, ymax_p;
  fp32_mul_p u_mhl (.clk, .a(obj_w[4]), .b(FP32_HALF), .r(hl_p));
  fp32_mul_p u_mhw (.clk, .a(obj_w[5]), .b(FP32_HALF), .r(hw_p));
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_axn (.clk, .a(obj_w[0]), .b({~obj_hl[31], obj_hl[30:0]}), .r(xmin_p));
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_ayn (.clk, .a(obj_w[1]), .b({~obj_hw[31], obj_hw[30:0]}), .r(ymin_p));
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_axx (.clk, .a(obj_w[0]), .b(obj_hl), .r(xmax_p));
  fp32_add_p #(.LEGACY_ZERO(1'b1)) u_ayx (.clk, .a(obj_w[1]), .b(obj_hw), .r(ymax_p));
  fp32_t obj_xmin, obj_ymin, obj_xmax, obj_ymax;
  fp32_t lane_w [0:LANE_NREADS-1];   // lane_type, wp_x0, wp_x1, wp_y0, wp_y1

  logic [7:0]             tok_seq_id;
  logic [MAX_SEQ_LEN-1:0] attn_mask_reg;
  logic [7:0]             num_tokens_r;
  logic [7:0]             obj_budget;
  logic [7:0]             eff_num_objects;

  assign attn_mask_out  = attn_mask_reg;
  assign num_tokens_out = num_tokens_r;
  // Giong phan mem: max_objects = MAX_SEQ_LEN - 3 - so_lane (dau 3 cho CLS/EGO/TARGET
  // DU khi khong phat TARGET — dung nhu nuscenes_loader.build_tokens_for_sample).
  assign obj_budget =
    (MAX_SEQ_LEN > (8'd3 + {3'd0, wm_num_lanes})) ?
      (MAX_SEQ_LEN - 8'd3 - {3'd0, wm_num_lanes}) : 8'd0;
  assign eff_num_objects = (wm_num_objects > obj_budget) ? obj_budget : wm_num_objects;

  // Word thu r cua lane (theo thu tu doc): 1, 2, 3, 12, 13
  function automatic logic [4:0] lane_word_of(input logic [3:0] r);
    case (r)
      4'd0:    return 5'd1;    // lane_type
      4'd1:    return 5'd2;    // wp_x[0]
      4'd2:    return 5'd3;    // wp_x[1]
      4'd3:    return 5'd12;   // wp_y[0]
      default: return 5'd13;   // wp_y[1]
    endcase
  endfunction

  // Dia chi object: obj_idx*12 + word (=(idx<<3)+(idx<<2)+word). Toi da 199*12+5 = 2393.
  function automatic logic [11:0] obj_addr(input logic [7:0] idx, input logic [3:0] w);
    return ({4'd0, idx} << 3) + ({4'd0, idx} << 2) + {8'd0, w};
  endfunction

  //============================================================================
  // Main FSM
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= S_IDLE;
      parse_done     <= 1'b0;
      parse_busy     <= 1'b0;
      token_valid    <= 1'b0;
      token_last     <= 1'b0;
      obj_idx        <= 8'd0;
      lane_idx       <= 5'd0;
      hdr_cnt        <= 2'd0;
      bram_latency   <= 1'b0;
      hdr_rd_en      <= 1'b0;
      obj_rd_en      <= 1'b0;
      lane_rd_en     <= 1'b0;
      hdr_rd_addr    <= 2'd0;
      obj_rd_addr    <= 12'd0;
      lane_rd_addr   <= 10'd0;
      rd_issue       <= 4'd0;
      rp_v1          <= 1'b0;
      rp_v2          <= 1'b0;
      rp_i1          <= 4'd0;
      rp_i2          <= 4'd0;
      tok_seq_id     <= 8'd0;
      num_tokens_r   <= 8'd0;
      attn_mask_reg  <= '0;
      token_out      <= '0;
      token_type_out <= TT_CLS;
      ego_vx_latch   <= '0;
      ego_vy_latch   <= '0;
      obj_hl <= '0; obj_hw <= '0; pw_cnt <= '0;
      obj_xmin <= '0; obj_ymin <= '0; obj_xmax <= '0; obj_ymax <= '0;
      for (int k = 0; k < OBJ_NWORDS;  k++) obj_w[k]  <= '0;
      for (int k = 0; k < LANE_NREADS; k++) lane_w[k] <= '0;
    end else begin
      // Mac dinh: xung mot chu ky
      parse_done  <= 1'b0;
      token_valid <= 1'b0;
      token_last  <= 1'b0;
      hdr_rd_en   <= 1'b0;
      obj_rd_en   <= 1'b0;
      lane_rd_en  <= 1'b0;

      // Duong ong doc: tang 1 -> tang 2 moi chu ky (tang 1 duoc dat ben duoi khi phat)
      rp_v2 <= rp_v1;
      rp_i2 <= rp_i1;
      rp_v1 <= 1'b0;

      case (state)
        //----------------------------------------------------------------------
        S_IDLE: begin
          if (parse_start) begin
            parse_busy    <= 1'b1;
            tok_seq_id    <= 8'd0;
            num_tokens_r  <= 8'd0;
            attn_mask_reg <= '0;
            obj_idx       <= 8'd0;
            lane_idx      <= 5'd0;
            hdr_cnt       <= 2'd0;
            hdr_rd_en     <= 1'b1;
            hdr_rd_addr   <= 2'd2;   // ego_vx
            bram_latency  <= 1'b0;
            state         <= S_HEADER;
          end
        end

        //----------------------------------------------------------------------
        // S_HEADER: doc ego_vx (word 2), ego_vy (word 3). Da kiem chu ky: dung.
        //   t0 (S_IDLE)  : phat dia chi 2
        //   t1           : phat dia chi 3
        //   t2           : du lieu = mem[2] -> ego_vx
        //   t3           : du lieu = mem[3] -> ego_vy
        S_HEADER: begin
          hdr_rd_en <= 1'b1;
          if (!bram_latency) begin
            hdr_rd_addr  <= 2'd3;
            bram_latency <= 1'b1;
          end else begin
            if (hdr_cnt == 2'd0) begin
              ego_vx_latch <= hdr_rd_data;
              hdr_cnt      <= 2'd1;
            end else begin
              ego_vy_latch <= hdr_rd_data;
              hdr_rd_en    <= 1'b0;
              state        <= S_CLS_EMIT;
            end
          end
        end

        //----------------------------------------------------------------------
        S_CLS_EMIT: begin
          if (token_ready) begin
            token_out      <= '0;
            token_type_out <= TT_CLS;
            token_valid    <= 1'b1;
            attn_mask_reg[tok_seq_id] <= 1'b1;
            tok_seq_id    <= tok_seq_id + 8'd1;
            num_tokens_r  <= num_tokens_r + 8'd1;
            state         <= S_EGO_EMIT;
          end
        end

        //----------------------------------------------------------------------
        // S_EGO_EMIT: {-L/2, -W/2, L/2, W/2, ego_vx, ego_vy}  [B2 loi 1]
        S_EGO_EMIT: begin
          if (token_ready) begin
            token_out.x_min <= EGO_NEG_HALF_L;
            token_out.y_min <= EGO_NEG_HALF_W;
            token_out.x_max <= EGO_POS_HALF_L;
            token_out.y_max <= EGO_POS_HALF_W;
            token_out.vx    <= ego_vx_latch;
            token_out.vy    <= ego_vy_latch;
            token_type_out  <= TT_EGO;
            token_valid     <= 1'b1;
            attn_mask_reg[tok_seq_id] <= 1'b1;
            tok_seq_id   <= tok_seq_id + 8'd1;
            num_tokens_r <= num_tokens_r + 8'd1;
            rd_issue     <= 4'd0;
            if (eff_num_objects != 8'd0) begin
              state <= S_OBJ_READ;
            end else if (wm_num_lanes != 5'd0) begin
              state <= S_LANE_READ;
            end else if (EMIT_TARGET) begin
              state <= S_TARGET_EMIT;
            end else begin
              token_last <= 1'b1;          // EGO la token cuoi
              state      <= S_DONE;
            end
          end
        end

        //----------------------------------------------------------------------
        // S_OBJ_READ: doc word 0..5 cua object obj_idx.  [B2 loi 4, 5]
        //   Moi chu ky phat mot dia chi (con thieu), kem chi so vao tang 1.
        //   Du lieu cua dia chi phat o chu ky c hop le o chu ky c+2, dung luc chi so
        //   cua no toi tang 2 -> chot obj_w[rp_i2].
        S_OBJ_READ: begin
          if (rd_issue < OBJ_NWORDS) begin
            obj_rd_en   <= 1'b1;
            obj_rd_addr <= obj_addr(obj_idx, rd_issue);
            rp_v1       <= 1'b1;
            rp_i1       <= rd_issue;
            rd_issue    <= rd_issue + 4'd1;
          end
          if (rp_v2) begin
            obj_w[rp_i2] <= obj_rd_data;
            if (rp_i2 == 4'(OBJ_NWORDS - 1)) state <= S_OBJ_HALF;
          end
        end

        //----------------------------------------------------------------------
        // Moi trang thai chi MOT phep FP32 tren duong to hop (xem AD.1 ve timing).
        S_OBJ_HALF: begin                              // hl = l*0.5, hw = w*0.5 (fp32_mul_p)
          if (pw_cnt == 3'd4) begin
            obj_hl <= hl_p;
            obj_hw <= hw_p;
            pw_cnt <= 3'd0;
            state  <= S_OBJ_BOX;
          end else pw_cnt <= pw_cnt + 3'd1;
        end

        S_OBJ_BOX: begin                               // x-+hl, y-+hw (fp32_add_p, sub = add(-b))
          if (pw_cnt == 3'd4) begin
            obj_xmin <= xmin_p;
            obj_ymin <= ymin_p;
            obj_xmax <= xmax_p;
            obj_ymax <= ymax_p;
            pw_cnt   <= 3'd0;
            state    <= S_OBJ_EMIT;
          end else pw_cnt <= pw_cnt + 3'd1;
        end

        //----------------------------------------------------------------------
        // S_OBJ_EMIT: {x-l/2, y-w/2, x+l/2, y+w/2, vx, vy}  [B2 loi 2]
        S_OBJ_EMIT: begin
          if (token_ready) begin
            token_out.x_min <= obj_xmin;
            token_out.y_min <= obj_ymin;
            token_out.x_max <= obj_xmax;
            token_out.y_max <= obj_ymax;
            token_out.vx    <= obj_w[2];
            token_out.vy    <= obj_w[3];
            token_type_out  <= TT_OBJECT;
            token_valid     <= 1'b1;
            attn_mask_reg[tok_seq_id] <= 1'b1;
            tok_seq_id   <= tok_seq_id + 8'd1;
            num_tokens_r <= num_tokens_r + 8'd1;
            obj_idx      <= obj_idx + 8'd1;
            rd_issue     <= 4'd0;
            if (obj_idx + 8'd1 < eff_num_objects) begin
              state <= S_OBJ_READ;
            end else if (wm_num_lanes != 5'd0) begin
              state <= S_LANE_READ;
            end else if (EMIT_TARGET) begin
              state <= S_TARGET_EMIT;
            end else begin
              token_last <= 1'b1;
              state      <= S_DONE;
            end
          end
        end

        //----------------------------------------------------------------------
        // S_LANE_READ: doc 5 word can dung cua lane lane_idx. Cung co che 2 tang.
        S_LANE_READ: begin
          if (rd_issue < LANE_NREADS) begin
            lane_rd_en   <= 1'b1;
            lane_rd_addr <= {lane_idx, lane_word_of(rd_issue)};   // lane_idx*32 + word
            rp_v1        <= 1'b1;
            rp_i1        <= rd_issue;
            rd_issue     <= rd_issue + 4'd1;
          end
          if (rp_v2) begin
            lane_w[rp_i2] <= lane_rd_data;
            if (rp_i2 == 4'(LANE_NREADS - 1)) state <= S_LANE_EMIT;
          end
        end

        //----------------------------------------------------------------------
        // S_LANE_EMIT: {wp_x[0], wp_y[0], wp_x[1], wp_y[1], 0, lane_type}
        S_LANE_EMIT: begin
          if (token_ready) begin
            token_out.x_min <= lane_w[1];   // wp_x[0]
            token_out.y_min <= lane_w[3];   // wp_y[0]
            token_out.x_max <= lane_w[2];   // wp_x[1]
            token_out.y_max <= lane_w[4];   // wp_y[1]
            token_out.vx    <= 32'd0;
            token_out.vy    <= lane_w[0];   // lane_type (FP32 0.0 / 1.0)
            token_type_out  <= TT_LANE;
            token_valid     <= 1'b1;
            attn_mask_reg[tok_seq_id] <= 1'b1;
            tok_seq_id   <= tok_seq_id + 8'd1;
            num_tokens_r <= num_tokens_r + 8'd1;
            lane_idx     <= lane_idx + 5'd1;
            rd_issue     <= 4'd0;
            if (lane_idx + 5'd1 < wm_num_lanes) begin
              state <= S_LANE_READ;
            end else if (EMIT_TARGET) begin
              state <= S_TARGET_EMIT;
            end else begin
              token_last <= 1'b1;
              state      <= S_DONE;
            end
          end
        end

        //----------------------------------------------------------------------
        // S_TARGET_EMIT: chi khi EMIT_TARGET = 1  [B2 loi 3]
        S_TARGET_EMIT: begin
          if (token_ready) begin
            token_out.x_min <= target_x;
            token_out.y_min <= target_y;
            token_out.x_max <= 32'd0;
            token_out.y_max <= 32'd0;
            token_out.vx    <= 32'd0;
            token_out.vy    <= 32'd0;
            token_type_out  <= TT_TARGET;
            token_valid     <= 1'b1;
            token_last      <= 1'b1;
            attn_mask_reg[tok_seq_id] <= 1'b1;
            tok_seq_id   <= tok_seq_id + 8'd1;
            num_tokens_r <= num_tokens_r + 8'd1;
            state <= S_DONE;
          end
        end

        //----------------------------------------------------------------------
        S_DONE: begin
          parse_done <= 1'b1;
          parse_busy <= 1'b0;
          state      <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule : world_model_parser

//==============================================================================
// End of File
//==============================================================================
