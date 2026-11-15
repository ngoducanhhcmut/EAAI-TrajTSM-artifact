module input_adapter
  import planning_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          clear_frame,
  // [E2E 02/10] Khung xong khi parser da xong (exp_valid) VA da nhan du exp_count token.
  // Truoc day dung idle-timeout 8 chu ky -> parser V2 phat ~11 chu ky/object nen khung bi
  // chot sau 2 token (CLS, EGO) — do bang tb_planning_top_e2e +CHK: nvalid=2, mong 30.
  input  logic          exp_valid,
  input  logic [7:0]    exp_count,
  input  bbox6_t        token_in,
  input  token_type_t   token_type,
  input  logic          token_valid,
  output logic          token_ready,
  output bbox6_t        bbox_out [MAX_SEQ_LEN-1:0],
  output logic [7:0]    num_valid_tokens,
  output fp32_t         target_x, target_y,
  output attn_mask_t    attn_mask_out,
  output logic          valid_out
);

  bbox6_t                 token_buffer [MAX_SEQ_LEN-1:0];
  logic [7:0]             token_write_idx;
  logic [MAX_SEQ_LEN-1:0] mask_buffer;
  logic [31:0]            target_x_reg, target_y_reg;
  logic [7:0]             num_tokens_cnt;
  logic                   frame_complete;
  logic [2:0]             idle_timeout;

  // [IMPL 150 MHz, 04/10] ghi token_buffer qua 1 tang thanh ghi (ghi muon 1 chu ky). Truoc day
  // CE cua 64x192 FF di thang tu con tro token_fifo (-0,664 ns). Khung chi chot (frame_complete)
  // som nhat 1 chu ky sau lan nhan cuoi -> bo dem da ghi xong cung luc.
  logic        bw_v;
  logic [5:0]  bw_idx;
  bbox6_t      bw_tok;
  always_ff @(posedge clk) begin
    bw_v   <= token_valid && token_ready && (token_write_idx < MAX_SEQ_LEN) && !clear_frame;
    bw_idx <= token_write_idx[5:0];
    bw_tok <= token_in;
    if (bw_v) token_buffer[bw_idx] <= bw_tok;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      token_write_idx <= '0;
      num_tokens_cnt  <= '0;
      mask_buffer     <= '0;
      target_x_reg    <= '0;
      target_y_reg    <= '0;
      idle_timeout    <= '0;
      frame_complete  <= 1'b0;
    end else if (clear_frame) begin
      token_write_idx <= '0;
      num_tokens_cnt  <= '0;
      mask_buffer     <= '0;
      target_x_reg    <= '0;
      target_y_reg    <= '0;
      idle_timeout    <= '0;
      frame_complete  <= 1'b0;
    end else begin
      if (token_valid && token_ready) begin
        if (token_write_idx < MAX_SEQ_LEN) begin
          num_tokens_cnt                <= token_write_idx + 8'd1;
          mask_buffer[token_write_idx]  <= 1'b1;
          if (token_type == TT_TARGET) begin
            target_x_reg <= token_in.x_min;
            target_y_reg <= token_in.y_min;
          end
          token_write_idx <= token_write_idx + 8'd1;
        end
        idle_timeout <= '0;
      end
      if (!frame_complete && exp_valid && (exp_count != 8'd0) &&
          (num_tokens_cnt == exp_count) && !(token_valid && token_ready))
        frame_complete <= 1'b1;
    end
  end

  assign token_ready      = (token_write_idx < MAX_SEQ_LEN) && ~frame_complete;
  assign valid_out        = frame_complete;
  assign num_valid_tokens = num_tokens_cnt;
  assign attn_mask_out    = mask_buffer;
  assign target_x         = target_x_reg;
  assign target_y         = target_y_reg;

  genvar i;
  generate
    for (i = 0; i < MAX_SEQ_LEN; i++) begin : gen_token_out
      assign bbox_out[i] = token_buffer[i];
    end
  endgenerate

endmodule
