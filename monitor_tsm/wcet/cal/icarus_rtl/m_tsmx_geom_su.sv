/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-01
 * Version      : 0.6
 * Description  : B3 G1c state unit: one division-free outward envelope step
 *                (golden disp_lb/disp_ub/advance_lb) or the per-cell jerk inflation.
 *                One pipelined 62x34 multiplier with result tags; independent
 *                products issue back-to-back. Constant divisions use an exact
 *                reciprocal estimate plus one correction (no divider).
 * Assumptions  : Reset release is synchronized by the enclosing core wrapper.
 *                B3 cells are at most 100000 ticks (rows reject h>DT first), so the
 *                unit faults for w>100000; golden never reaches that branch.
 * Deviations   : HIE-02: functional leaf; the enclosing system top is structural.
 *                PAR-03: SI constants follow golden (T=1e6 ticks/s, 1 um, 1 um/s).
 *                v0.2 serial copy: legacy/m_tsmx_geom_su_v0.2_serial.sv.txt.
 *                v0.4 (01/11): datapath widths follow the START bounds (v<=2e7,
 *                |a|<=8e6, w<=1e5, j<2^32): P<2^41, A1<2^40, W2<2^34, VT<2^45,
 *                PT,N<2^62, A2<2^57 (mode 0) / <2^50 (mode 1), JW<2^82; every
 *                quotient (lin, velq, disp, infl) is <2^22. Outputs are zero-extended.
 *                v0.5 (01/11): each divisor D=2^k*D' divides by D' after N>>k
 *                (floor(floor(N/2^k)/D') = floor(N/D)); with N'<2^s and
 *                M=floor(2^s/D') the estimate q0=(N'*M)>>s is q or q-1, so M is
 *                at most 22 bits and the multiplier shrinks from 64x64 to 62x34.
 *                v0.6 (01/11): the operand adders of S5/S6/S10 (41-bit) and S10/I3
 *                (62-bit) are one shared adder each, selected by state.
 *                Same states and latencies; bit- and cycle-exact to v0.3
 *                (legacy/m_tsmx_geom_su_v0.3.sv.txt, lock-step tb/unit/geom_su/eq_v04).
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_geom_su (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_start,
  input wire i_mode,
  input wire i_up,
  input wire [63:0] i_x,
  input wire [31:0] i_v,
  input wire [31:0] i_a,
  input wire [31:0] i_w,
  input wire [31:0] i_j,
  output logic o_busy,
  output logic o_done,
  output logic o_fault,
  output logic [63:0] o_x,
  output logic [31:0] o_v,
  output logic [63:0] o_disp,
  output logic [63:0] o_lin,
  output logic [63:0] o_infl
);
  typedef enum logic [4:0] {
    ENUM_ST_IDLE=5'd0, ENUM_ST_START=5'd1,
    ENUM_ST_S0=5'd2, ENUM_ST_S1=5'd3, ENUM_ST_S2=5'd4, ENUM_ST_S3=5'd5, ENUM_ST_S4=5'd6,
    ENUM_ST_S5=5'd7, ENUM_ST_S6=5'd8, ENUM_ST_S7=5'd9, ENUM_ST_S8=5'd10, ENUM_ST_S9=5'd11,
    ENUM_ST_S10=5'd12, ENUM_ST_S11=5'd13, ENUM_ST_S12=5'd14,
    ENUM_ST_I1=5'd15, ENUM_ST_I2=5'd16, ENUM_ST_I3=5'd17, ENUM_ST_I4=5'd18, ENUM_ST_I5=5'd19,
    ENUM_ST_FIN=5'd20
  } ctrl_state_type_def;
  // Product tags.
  localparam logic [3:0] LPARA_T_P=4'd0, LPARA_T_A1=4'd1, LPARA_T_W2=4'd2, LPARA_T_VT=4'd3,
    LPARA_T_PT=4'd4, LPARA_T_LE=4'd5, LPARA_T_VE=4'd6, LPARA_T_A2=4'd7, LPARA_T_LC=4'd8,
    LPARA_T_VC=4'd9, LPARA_T_DE=4'd10, LPARA_T_DC=4'd11, LPARA_T_JW=4'd12;
  localparam int LPARA_NT=13;
  // Constant divisors D=2^k*D': floor(N/D) = q0 + (N' - q0*D' >= D'), N'=N>>k,
  // q0 = (N'*M) >> s, M = floor(2^s/D'), N' < 2^s.
  localparam logic [1:0] LPARA_D1E6=2'd0, LPARA_D2E6=2'd1, LPARA_D2E12=2'd2, LPARA_D5P18=2'd3;
  localparam logic [21:0] LPARA_M5P6=22'd2199023;   // s=35: 1e6=2^6*5^6, 2e6=2^7*5^6
  localparam logic [21:0] LPARA_M5P12=22'd2305843;  // s=49: 2e12=2^13*5^12
  localparam logic [21:0] LPARA_M5P18=22'd1208925;  // s=62: 8T^3/2^21=5^18
  localparam logic [41:0] LPARA_DV5P6=42'd15625, LPARA_DV5P12=42'd244140625,
    LPARA_DV5P18=42'd3814697265625;

  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
  logic reg_mode, reg_up, w_mode_nxt, w_up_nxt;
  logic [63:0] reg_x, w_x_nxt;
  logic [31:0] reg_v, reg_a, reg_w, reg_j, w_v_nxt, w_a_nxt, w_w_nxt, w_j_nxt;
  logic [95:0] reg_r [0:LPARA_NT-1];
  logic [LPARA_NT-1:0] reg_rv, w_rv_clr;
  // Reduced numerators keep only the remainder bits the correction reads (remainder < 2D').
  logic [14:0] reg_dnl, reg_dnv, w_dnl_nxt, w_dnv_nxt;
  logic [42:0] reg_dnd, w_dnd_nxt;
  // Quotients: lin<=2e6, velq<=8e5, disp<=2.02e6, infl<=5.4e5 (all < 2^22).
  logic [21:0] reg_q0l, reg_q0v, reg_q0d, w_q0l_nxt, w_q0v_nxt, w_q0d_nxt;
  logic [1:0] reg_dsel, w_dsel_nxt;
  logic reg_dskip, w_dskip_nxt;
  logic [21:0] reg_disp, reg_lin, reg_infl, reg_velq, w_disp_nxt, w_lin_nxt, w_infl_nxt;
  logic [21:0] w_velq_nxt;
  logic [63:0] reg_xo, w_xo_nxt;
  logic [31:0] reg_vo, w_vo_nxt;
  logic reg_fault, w_fault_nxt, reg_done, w_done_nxt;
  // Multiplier pipeline with tags: operands -> product -> output -> tagged result.
  logic w_mstart;
  logic [3:0] w_mtag;
  logic [61:0] w_ma, reg_ma;
  logic [33:0] w_mb, reg_mb;
  logic [3:0] reg_tag1, reg_tag2, reg_tag3;
  logic reg_val1, reg_val2, reg_val3;
  logic [95:0] reg_m2, reg_m3;
  // Combinational helpers.
  logic [31:0] w_am32;
  logic [22:0] w_am;
  logic [41:0] w_dd;
  logic [40:0] w_dn41;
  logic [39:0] w_dn40;
  logic [61:0] w_dn62;
  logic [40:0] w_add41, w_k41;
  logic [61:0] w_add62, w_k62;
  logic [32:0] w_vsum;
  logic [21:0] w_shift;
  logic [61:0] w_n;
  logic [64:0] w_xadd;
  logic w_nle0, w_stopped, w_neg;

  always @* begin : p_com_main
    w_neg = reg_a[31];
    // START checks the full |a|; once it passes |a| <= 8e6 < 2^23 (multiplier operand).
    w_am32 = w_neg ? 32'(~reg_a+1'b1) : reg_a;
    w_am = w_am32[22:0];
    case (reg_dsel)
      LPARA_D2E12: begin w_dd=LPARA_DV5P12; w_shift=reg_r[LPARA_T_DE][70:49]; end
      LPARA_D5P18: begin w_dd=LPARA_DV5P18; w_shift=reg_r[LPARA_T_DE][83:62]; end
      default:     begin w_dd=LPARA_DV5P6;  w_shift=reg_r[LPARA_T_DE][56:35]; end
    endcase
    // N = 2*v*w*T + a*w^2 (|N| < 2^62 for v<=20 m/s, w<=0.1 s).
    w_n = w_neg ? 62'(reg_r[LPARA_T_PT][61:0]-reg_r[LPARA_T_A2][56:0])
                : 62'(reg_r[LPARA_T_PT][61:0]+reg_r[LPARA_T_A2][56:0]);
    w_nle0 = w_neg ? (reg_r[LPARA_T_PT][61:0] <= 62'(reg_r[LPARA_T_A2][56:0])) : (w_n=='0);
    // Stopped within the cell: a<0 and v*T + a*w < 0.
    w_stopped = w_neg && (reg_r[LPARA_T_VT][44:0] < 45'(reg_r[LPARA_T_A1][39:0]));
    // Shared operand adders (each state uses at most one of each).
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_S5:  w_k41 = reg_up ? 41'd999999 : 41'd0;
      ENUM_ST_S6:  w_k41 = (reg_up != w_neg) ? 41'd999999 : 41'd0;
      default:     w_k41 = 41'd1999999;
    endcase
    w_add41 = 41'(((reg_fsm_ctrl_current_state==ENUM_ST_S6) ? {1'b0,reg_r[LPARA_T_A1][39:0]}
                                                            : reg_r[LPARA_T_P][40:0]) + w_k41);
    if (reg_fsm_ctrl_current_state==ENUM_ST_I3) w_k62 = 62'd3814697265624;
    else w_k62 = (reg_up && (!w_neg || !w_stopped)) ? 62'd1999999999999 : 62'd0;
    w_add62 = (reg_fsm_ctrl_current_state==ENUM_ST_I3)
      ? 62'({1'b0,reg_r[LPARA_T_JW][81:21]}+w_k62+{61'd0,reg_r[LPARA_T_JW][20:0]!='0})
      : 62'(w_n+w_k62);

    w_fsm_ctrl_nxt_state=reg_fsm_ctrl_current_state;
    w_mode_nxt=reg_mode; w_up_nxt=reg_up; w_x_nxt=reg_x; w_v_nxt=reg_v; w_a_nxt=reg_a;
    w_w_nxt=reg_w; w_j_nxt=reg_j; w_rv_clr='0;
    w_dnl_nxt=reg_dnl; w_dnv_nxt=reg_dnv; w_dnd_nxt=reg_dnd;
    w_q0l_nxt=reg_q0l; w_q0v_nxt=reg_q0v; w_q0d_nxt=reg_q0d; w_dsel_nxt=reg_dsel;
    w_dskip_nxt=reg_dskip; w_disp_nxt=reg_disp; w_lin_nxt=reg_lin; w_infl_nxt=reg_infl;
    w_velq_nxt=reg_velq; w_xo_nxt=reg_xo; w_vo_nxt=reg_vo; w_fault_nxt=reg_fault;
    w_done_nxt=reg_done;
    w_mstart=1'b0; w_mtag='0; w_ma='0; w_mb='0; w_vsum='0; w_xadd='0;
    w_dn41='0; w_dn40='0; w_dn62='0;

    case (reg_fsm_ctrl_current_state)
      ENUM_ST_IDLE: if (i_start) begin
        w_mode_nxt=i_mode; w_up_nxt=i_up; w_x_nxt=i_x; w_v_nxt=i_v; w_a_nxt=i_a;
        w_w_nxt=i_w; w_j_nxt=i_j; w_done_nxt=1'b0; w_fault_nxt=1'b0; w_rv_clr='1;
        w_disp_nxt='0; w_lin_nxt='0; w_infl_nxt='0; w_xo_nxt='0; w_vo_nxt='0;
        w_velq_nxt='0; w_dskip_nxt=1'b0;
        w_fsm_ctrl_nxt_state=ENUM_ST_START;
      end
      ENUM_ST_START: begin
        // Golden advance_lb motion_range and checked(x); B3 cell bound w<=1e5.
        if (reg_w>32'd100000 || (!reg_mode && (reg_v>32'd20000000
          || (w_neg && w_am32>32'd8000000) || (!w_neg && reg_a>32'd2000000)
          || reg_x==64'h8000000000000000))) begin
          w_fault_nxt=1'b1; w_fsm_ctrl_nxt_state=ENUM_ST_FIN;
        end else if (reg_mode) begin
          w_mstart=1'b1; w_mtag=LPARA_T_W2; w_ma={45'd0,reg_w[16:0]}; w_mb={17'd0,reg_w[16:0]};
          w_fsm_ctrl_nxt_state=ENUM_ST_I1;
        end else begin
          w_mstart=1'b1; w_mtag=LPARA_T_P; w_ma={37'd0,reg_v[24:0]}; w_mb={17'd0,reg_w[16:0]};
          w_fsm_ctrl_nxt_state=ENUM_ST_S1;
        end
      end
      ENUM_ST_S1: begin
        w_mstart=1'b1; w_mtag=LPARA_T_A1; w_ma={39'd0,w_am}; w_mb={17'd0,reg_w[16:0]};
        w_fsm_ctrl_nxt_state=ENUM_ST_S2;
      end
      ENUM_ST_S2: begin
        w_mstart=1'b1; w_mtag=LPARA_T_W2; w_ma={45'd0,reg_w[16:0]}; w_mb={17'd0,reg_w[16:0]};
        w_fsm_ctrl_nxt_state=ENUM_ST_S3;
      end
      ENUM_ST_S3: begin
        w_mstart=1'b1; w_mtag=LPARA_T_VT; w_ma={37'd0,reg_v[24:0]}; w_mb=34'd1000000;
        w_fsm_ctrl_nxt_state=ENUM_ST_S4;
      end
      ENUM_ST_S4: if (reg_rv[LPARA_T_P]) begin
        w_mstart=1'b1; w_mtag=LPARA_T_PT; w_ma={21'd0,reg_r[LPARA_T_P][40:0]}; w_mb=34'd2000000;
        w_fsm_ctrl_nxt_state=ENUM_ST_S5;
      end
      // lin = floor/ceil(v*w / T): T = 2^6*5^6.
      ENUM_ST_S5: begin
        w_dn41 = w_add41;
        w_dnl_nxt=w_dn41[20:6];
        w_mstart=1'b1; w_mtag=LPARA_T_LE; w_ma={27'd0,w_dn41[40:6]}; w_mb={12'd0,LPARA_M5P6};
        w_fsm_ctrl_nxt_state=ENUM_ST_S6;
      end
      // Velocity change |a|*w/T, outward: ceil when (up && a>=0) || (!up && a<0).
      ENUM_ST_S6: if (reg_rv[LPARA_T_A1]) begin
        w_dn40 = w_add41[39:0];
        w_dnv_nxt=w_dn40[20:6];
        w_mstart=1'b1; w_mtag=LPARA_T_VE; w_ma={28'd0,w_dn40[39:6]}; w_mb={12'd0,LPARA_M5P6};
        w_fsm_ctrl_nxt_state=ENUM_ST_S7;
      end
      ENUM_ST_S7: if (reg_rv[LPARA_T_W2]) begin
        w_mstart=1'b1; w_mtag=LPARA_T_A2; w_ma={39'd0,w_am}; w_mb=reg_r[LPARA_T_W2][33:0];
        w_fsm_ctrl_nxt_state=ENUM_ST_S8;
      end
      ENUM_ST_S8: if (reg_rv[LPARA_T_LE]) begin
        w_q0l_nxt=reg_r[LPARA_T_LE][56:35];
        w_mstart=1'b1; w_mtag=LPARA_T_LC; w_ma={40'd0,reg_r[LPARA_T_LE][56:35]};
        w_mb=LPARA_DV5P6[33:0]; w_fsm_ctrl_nxt_state=ENUM_ST_S9;
      end
      ENUM_ST_S9: if (reg_rv[LPARA_T_VE]) begin
        w_q0v_nxt=reg_r[LPARA_T_VE][56:35];
        w_mstart=1'b1; w_mtag=LPARA_T_VC; w_ma={40'd0,reg_r[LPARA_T_VE][56:35]};
        w_mb=LPARA_DV5P6[33:0]; w_fsm_ctrl_nxt_state=ENUM_ST_S10;
      end
      // Displacement bound: disp_lb / disp_ub (not stopped) / disp_ub (stopped).
      // 2e12 = 2^13*5^12 (N'=N>>13 < 2^49); stopped: 2e6 = 2^7*5^6 (N'=N>>7 < 2^34).
      ENUM_ST_S10: if (reg_rv[LPARA_T_A2] && reg_rv[LPARA_T_PT] && reg_rv[LPARA_T_VT]) begin
        w_dskip_nxt=1'b0; w_dsel_nxt=LPARA_D2E12; w_dn62=w_add62;
        if (!reg_up) begin
          if (w_nle0) w_dskip_nxt=1'b1;
        end else if (!w_neg || !w_stopped) begin
          if (w_nle0) w_dskip_nxt=1'b1;
        end else begin
          w_dn41=w_add41; w_dsel_nxt=LPARA_D2E6;
        end
        if (reg_up && w_neg && w_stopped) w_dnd_nxt={9'd0,w_dn41[40:7]};
        else w_dnd_nxt=w_dn62[55:13];
        if (!(w_nle0 && (!reg_up || !w_neg || !w_stopped))) begin
          w_mstart=1'b1; w_mtag=LPARA_T_DE;
          if (reg_up && w_neg && w_stopped) begin
            w_ma={28'd0,w_dn41[40:7]}; w_mb={12'd0,LPARA_M5P6};
          end else begin
            w_ma={13'd0,w_dn62[61:13]}; w_mb={12'd0,LPARA_M5P12};
          end
          w_fsm_ctrl_nxt_state=ENUM_ST_S11;
        end else w_fsm_ctrl_nxt_state=ENUM_ST_S12;
      end
      ENUM_ST_S11: if (reg_rv[LPARA_T_DE]) begin
        w_q0d_nxt=w_shift;
        w_mstart=1'b1; w_mtag=LPARA_T_DC; w_ma={20'd0,w_dd}; w_mb={12'd0,w_shift};
        w_fsm_ctrl_nxt_state=ENUM_ST_S12;
      end
      ENUM_ST_S12: if (reg_rv[LPARA_T_LC] && reg_rv[LPARA_T_VC]
        && (reg_dskip || reg_rv[LPARA_T_DC])) begin
        w_lin_nxt=22'(reg_q0l+{21'd0,15'(reg_dnl-reg_r[LPARA_T_LC][14:0])>=15'd15625});
        w_velq_nxt=22'(reg_q0v+{21'd0,15'(reg_dnv-reg_r[LPARA_T_VC][14:0])>=15'd15625});
        w_disp_nxt=reg_dskip ? 22'd0
          : 22'(reg_q0d+{21'd0,43'(reg_dnd-reg_r[LPARA_T_DC][42:0])>={1'b0,w_dd}});
        w_fsm_ctrl_nxt_state=ENUM_ST_FIN;
      end
      // Inflation: ceil(J*w^3 / 8T^3) + ceil(w^2 / 2T^2), 8T^3 = 2^21 * 5^18.
      ENUM_ST_I1: if (reg_rv[LPARA_T_W2]) begin
        w_mstart=1'b1; w_mtag=LPARA_T_A2; w_ma={28'd0,reg_r[LPARA_T_W2][33:0]};
        w_mb={17'd0,reg_w[16:0]};
        w_fsm_ctrl_nxt_state=ENUM_ST_I2;
      end
      ENUM_ST_I2: if (reg_rv[LPARA_T_A2]) begin
        w_mstart=1'b1; w_mtag=LPARA_T_JW; w_ma={12'd0,reg_r[LPARA_T_A2][49:0]};
        w_mb={2'd0,reg_j};
        w_fsm_ctrl_nxt_state=ENUM_ST_I3;
      end
      ENUM_ST_I3: if (reg_rv[LPARA_T_JW]) begin
        w_dn62=w_add62;
        w_dnd_nxt=w_dn62[42:0]; w_dsel_nxt=LPARA_D5P18;
        w_mstart=1'b1; w_mtag=LPARA_T_DE; w_ma=w_dn62; w_mb={12'd0,LPARA_M5P18};
        w_fsm_ctrl_nxt_state=ENUM_ST_I4;
      end
      ENUM_ST_I4: if (reg_rv[LPARA_T_DE]) begin
        w_q0d_nxt=w_shift;
        w_mstart=1'b1; w_mtag=LPARA_T_DC; w_ma={20'd0,w_dd}; w_mb={12'd0,w_shift};
        w_fsm_ctrl_nxt_state=ENUM_ST_I5;
      end
      ENUM_ST_I5: if (reg_rv[LPARA_T_DC]) begin
        w_infl_nxt=22'(reg_q0d+{21'd0,43'(reg_dnd-reg_r[LPARA_T_DC][42:0])>={1'b0,w_dd}}
          +{21'd0,reg_w!='0});
        w_fsm_ctrl_nxt_state=ENUM_ST_FIN;
      end
      ENUM_ST_FIN: begin
        if (!reg_fault && !reg_mode) begin
          // v' = max(0, v +/- q); x' = checked(x + disp).
          if (w_neg) begin
            w_vsum=33'({1'b0,reg_v}-{11'd0,reg_velq});
            w_vo_nxt=({10'd0,reg_velq} > reg_v) ? 32'd0 : w_vsum[31:0];
          end else begin
            w_vsum=33'({1'b0,reg_v}+{11'd0,reg_velq});
            w_vo_nxt=w_vsum[31:0];
            if (w_vsum[32]) w_fault_nxt=1'b1;
          end
          w_xadd={reg_x[63],reg_x}+{43'd0,reg_disp};
          w_xo_nxt=w_xadd[63:0];
          if (w_xadd[64]!=w_xadd[63] || w_xadd[63:0]==64'h8000000000000000) w_fault_nxt=1'b1;
        end
        w_done_nxt=1'b1; w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      end
      default: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
    endcase

    o_busy = (reg_fsm_ctrl_current_state!=ENUM_ST_IDLE);
    o_done = reg_done && (reg_fsm_ctrl_current_state==ENUM_ST_IDLE);
    o_fault = reg_fault;
    o_x = reg_xo; o_v = reg_vo; o_disp = {42'd0,reg_disp}; o_lin = {42'd0,reg_lin}; o_infl = {42'd0,reg_infl};
  end

  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_IDLE;
      reg_mode<=1'b0; reg_up<=1'b0; reg_x<='0; reg_v<='0; reg_a<='0; reg_w<='0; reg_j<='0;
      reg_dnl<='0; reg_dnv<='0; reg_dnd<='0; reg_q0l<='0; reg_q0v<='0; reg_q0d<='0;
      reg_dsel<='0; reg_dskip<=1'b0; reg_disp<='0; reg_lin<='0; reg_infl<='0; reg_velq<='0;
      reg_xo<='0; reg_vo<='0; reg_fault<=1'b0; reg_done<=1'b0;
    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
      reg_mode<=w_mode_nxt; reg_up<=w_up_nxt; reg_x<=w_x_nxt; reg_v<=w_v_nxt; reg_a<=w_a_nxt;
      reg_w<=w_w_nxt; reg_j<=w_j_nxt;
      reg_dnl<=w_dnl_nxt; reg_dnv<=w_dnv_nxt; reg_dnd<=w_dnd_nxt;
      reg_q0l<=w_q0l_nxt; reg_q0v<=w_q0v_nxt; reg_q0d<=w_q0d_nxt;
      reg_dsel<=w_dsel_nxt; reg_dskip<=w_dskip_nxt; reg_disp<=w_disp_nxt; reg_lin<=w_lin_nxt;
      reg_infl<=w_infl_nxt; reg_velq<=w_velq_nxt; reg_xo<=w_xo_nxt; reg_vo<=w_vo_nxt;
      reg_fault<=w_fault_nxt; reg_done<=w_done_nxt;
    end
  end

  // Tagged multiplier pipeline; a result becomes visible four cycles after issue.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_mul
    if (!i_rst_n_core) begin
      reg_ma<='0; reg_mb<='0; reg_m2<='0; reg_m3<='0;
      reg_tag1<='0; reg_tag2<='0; reg_tag3<='0; reg_val1<=1'b0; reg_val2<=1'b0; reg_val3<=1'b0;
      reg_rv<='0;
      for (int idx=0; idx<LPARA_NT; idx++) reg_r[idx]<='0;
    end else begin
      if (w_mstart) begin reg_ma<=w_ma; reg_mb<=w_mb; reg_tag1<=w_mtag; end
      reg_val1<=w_mstart;
      reg_m2<=reg_ma*reg_mb; reg_tag2<=reg_tag1; reg_val2<=reg_val1;
      reg_m3<=reg_m2; reg_tag3<=reg_tag2; reg_val3<=reg_val2;
      if (|w_rv_clr) reg_rv<='0;
      else if (reg_val3) begin
        reg_r[reg_tag3]<=reg_m3; reg_rv[reg_tag3]<=1'b1;
      end
    end
  end
endmodule
`default_nettype wire
