//==============================================================================
// fp32_special.sv — exp_neg (duong ong), rsqrt / recip (tuan tu Newton) cho BERT V2
// Chuan tung bit: sw/hwspec/fp.py (exp_neg, rsqrt, recip).
//==============================================================================
`timescale 1ns / 1ps

// exp(x), x <= 0.  LAT = 6.
//   t = fmul(x, LOG2E)            (3)
//   T = floor(t*1024) chinh xac   (1)  ; under = t < -126
//   k = T & 1023, n = T >>> 10 ; doc EXP2_MANT_T[k] (1)
//   r = 2^(k/1024) * 2^n  = {0, 127+n, mant}  (chinh xac — bang fmul cua fp.py) (1)
module fp32_exp_neg_p (
  input  logic        clk,
  input  logic [31:0] x,
  output logic [31:0] r
);
  `include "fp32_tables.svh"
  localparam logic [31:0] LOG2E = 32'h3FB8AA3B;   // F32(1.4426950408889634)

  logic [31:0] t;
  fp32_mul_p u_m (.clk, .a(x), .b(LOG2E), .r(t));

  // floor(t*1024) cho t <= 0 (t = -0 hoac 0 -> 0). |t| < 126 khi khong under.
  logic               s4_under;
  logic signed [17:0] s4_T;
  always_ff @(posedge clk) begin
    logic [7:0]  e;
    logic [23:0] m;
    logic [47:0] w;          // |t|*1024 = m * 2^(e-150+10) = w * 2^-24 voi w = m << (e-116)
    logic [23:0] ip;
    logic        fr;
    int          sh;
    e  = t[30:23];
    m  = {1'b1, t[22:0]};
    s4_under <= t[31] && (t[30:0] > 32'h42FC0000);     // t < -126.0
    sh = int'(e) - 116;
    if (e == 8'd0) begin
      ip = '0; fr = 1'b0;                              // t = +-0
    end else if (sh < 0) begin
      ip = '0; fr = 1'b1;                              // 0 < |t*1024| < 1
    end else begin
      w  = {24'd0, m} << sh;                           // sh <= 24 khi |t| < 128
      ip = w[47:24]; fr = |w[23:0];
    end
    // t <= 0: floor(t*1024) = -(ip + fr)
    s4_T <= -$signed({1'b0, 17'(ip)}) - $signed({17'd0, fr});
  end

  logic        s5_under;
  logic [22:0] s5_mant;
  logic signed [8:0] s5_n;
  always_ff @(posedge clk) begin
    s5_under <= s4_under;
    s5_mant  <= EXP2_MANT_T[s4_T[9:0]];
    s5_n     <= 9'(s4_T >>> 10);
  end

  always_ff @(posedge clk) begin
    logic signed [9:0] ex;
    ex = 10'sd127 + 10'(s5_n);
    if (s5_under) r <= 32'd0;
    else          r <= {1'b0, ex[7:0], s5_mant};        // n >= -126 (vi t >= -126)
  end
endmodule : fp32_exp_neg_p


// rsqrt (MODE=0) / recip (MODE=1) tuan tu. start 1 chu ky; done 1 chu ky kem r.
// Dung 1 fp32_mul_p + 1 fp32_add_p (LAT 3). Moi buoc cho du LAT -> ~30 chu ky.
module fp32_nr_seq #(
  parameter bit MODE = 1'b0
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [31:0] v,
  output logic        done,
  output logic [31:0] r
);
  `include "fp32_tables.svh"
  localparam logic [31:0] HALF = 32'h3F000000, ONE_HALF = 32'h3FC00000, TWO = 32'h40000000;

  logic [31:0] ma, mb, mr, aa, ab, ar;
  fp32_mul_p u_m (.clk, .a(ma), .b(mb), .r(mr));
  fp32_add_p u_a (.clk, .a(aa), .b(ab), .r(ar));

  typedef enum logic [3:0] {S_IDLE, S_SEED, S_H, S_T1, S_T2, S_T3, S_Y, S_FIN} st_t;
  st_t st;
  logic [2:0]  wait_c;
  logic        it;          // vong Newton 0/1
  logic [31:0] vv, y, h, t;

  // ham: so mu 2^p (p trong [-126,127]) -> FP32
  function automatic logic [31:0] pow2(input logic signed [9:0] p);
    logic [9:0] e;
    e = 10'(p + 10'sd127);
    return {1'b0, e[7:0], 23'd0};
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE; done <= 1'b0; r <= '0; wait_c <= '0; it <= 1'b0;
      ma <= '0; mb <= '0; aa <= '0; ab <= '0; vv <= '0; y <= '0; h <= '0; t <= '0;
    end else begin
      done <= 1'b0;
      if (wait_c != 0) wait_c <= wait_c - 3'd1;
      case (st)
        S_IDLE: if (start) begin
          logic signed [9:0] E;
          logic              odd;
          logic [5:0]        k;
          E   = $signed({2'b0, v[30:23]}) - 10'sd127;
          odd = E[0];
          k   = v[22:17];
          vv  <= v;
          it  <= 1'b0;
          if (MODE == 1'b0) begin
            ma <= RSQRT_SEED_T[{odd, k}];
            mb <= pow2(-((E - $signed({9'd0, odd})) >>> 1));
          end else begin
            ma <= RECIP_SEED_T[k];
            mb <= pow2(-E);
          end
          wait_c <= 3'd3; st <= S_SEED;
        end
        S_SEED: if (wait_c == 0) begin              // y = seed * 2^p
          y <= mr;
          if (MODE == 1'b0) begin ma <= vv; mb <= HALF; wait_c <= 3'd3; st <= S_H; end
          else begin ma <= vv; mb <= mr; wait_c <= 3'd3; st <= S_T2; end   // t = s*y
        end
        S_H: if (wait_c == 0) begin                 // h = v*0.5 ; t = y*y
          h <= mr; ma <= y; mb <= y; wait_c <= 3'd3; st <= S_T1;
        end
        S_T1: if (wait_c == 0) begin                // t = h*t
          ma <= h; mb <= mr; wait_c <= 3'd3; st <= S_T2;
        end
        S_T2: if (wait_c == 0) begin                // t = C - t
          aa <= (MODE == 1'b0) ? ONE_HALF : TWO;
          ab <= {~mr[31], mr[30:0]};
          wait_c <= 3'd3; st <= S_T3;
        end
        S_T3: if (wait_c == 0) begin                // y = y*t
          ma <= y; mb <= ar; wait_c <= 3'd3; st <= S_Y;
        end
        S_Y: if (wait_c == 0) begin
          y <= mr;
          if (!it) begin
            it <= 1'b1;
            if (MODE == 1'b0) begin ma <= mr; mb <= mr; wait_c <= 3'd3; st <= S_T1; end
            else begin ma <= vv; mb <= mr; wait_c <= 3'd3; st <= S_T2; end
          end else begin
            st <= S_FIN;
          end
        end
        S_FIN: begin r <= y; done <= 1'b1; st <= S_IDLE; end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule : fp32_nr_seq
