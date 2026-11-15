"""Generate R7's repetitive, explicit next-state/register plumbing."""
from pathlib import Path
P=Path(__file__).resolve().parents[3]/'rtl/geom'
header='''/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : Streaming B3 geometry, deferred validation and private arithmetic.
 * Assumptions  : Reset release is synchronized by the enclosing core wrapper.
 *                Row storage is resetless and guarded by the reset row count.
 * Deviations   : HIE-02: functional leaf; the enclosing system top is structural.
 *                PAR-03: SI coefficients and ABI bit positions follow golden exactly.
 */
`timescale 1ns/1ps
`default_nettype none
'''
states=['BOOT','IDLE','ROW','INFL','IWAIT','ACT','ISSUE','AWAIT','STEP','FIN','RESP']
regs={'tag':40,'world':8200,'lane':384,'count':8,'term':50,'term_valid':1,'bad_row':1,'bad_tag':1,
      'cell':8,'actor':8,'fail':8,'steps':8,'margin':64,'resp':81,'inflate':64,'part':32,
      'remain':32,'ahead':1,'pose':256,'vel':128,'oa':32}
arrays={'rows':(352,'PARA_MAX_CELLS+1'),'obj':(256,'PARA_MAX_OBJ'),'motion':(192,'PARA_MAX_OBJ')}
s=header+'''module m_tsmx_geom #(
  // Parameter Description: allocated actors; ABI remains thirty-two slots.
  // Parameter values: 1..32; default is 32.
  // Parameter unit: count
  parameter logic [31:0] PARA_MAX_OBJ = 32'd32,
  // Parameter Description: allocated cells; stream count is checked against this limit.
  // Parameter values: 1..128; default is 128.
  // Parameter unit: count
  parameter logic [31:0] PARA_MAX_CELLS = 32'd128
) (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [8623:0] i_req_data,
  input wire i_row_valid,
  input wire [400:0] i_row_data,
  input wire i_terminal_valid,
  input wire [49:0] i_terminal_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_row_ready,
  output logic o_terminal_ready,
  output logic o_rsp_valid,
  output logic [80:0] o_rsp_data
);
  typedef enum logic [3:0] {
'''+',\n'.join(f"    ENUM_ST_{n} = 4'd{i}" for i,n in enumerate(states))+'''
  } ctrl_state_type_def;
  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;
'''
for n,w in regs.items():s+=f'  logic [{w-1}:0] reg_{n}, w_{n}_nxt;\n'
for n,(w,size) in arrays.items():s+=f'  logic [{w-1}:0] reg_{n} [0:{size}-1];\n  logic [{w-1}:0] w_{n}_nxt [0:{size}-1];\n'
s+='''  logic [351:0] w_row, w_next;
  logic [31:0] w_h, w_event, w_elapsed, w_accel;
  logic [63:0] w_gap, w_piece_margin;
  logic [255:0] w_object;
  logic [95:0] w_inum_0, w_inum_1, w_iq_0, w_iq_1;
  logic w_iv_0, w_iv_1, w_if_0, w_if_1;
  logic [4:0] w_ready, w_valid;
  logic [1927:0] w_req [0:4];
  logic [640:0] w_rsp [0:4];
  logic w_issue, w_consume, w_all, w_row_ok, w_lane_ok, w_lane_fit;
  logic w_obj_ok, w_speed_ok;
  logic [7:0] w_pre_reason;
  logic [63:0] w_lo, w_hi, w_y, w_half, w_error, w_reserve;
  logic [63:0] w_positive, w_speed_product, w_speed_limit;

  // Unsigned bit patterns implement explicit two's-complement comparisons.
  function automatic logic f_lt(input logic [63:0] w_a, w_b);
    f_lt = (w_a[63] != w_b[63]) ? w_a[63] : w_a < w_b;
  endfunction
  function automatic logic f_range(input logic [63:0] w_a, w_l, w_u);
    f_range = !f_lt(w_a,w_l) && !f_lt(w_u,w_a);
  endfunction
  function automatic logic [159:0] f_s64(input logic [63:0] w_a);
    f_s64 = {{96{w_a[63]}},w_a};
  endfunction
  function automatic logic [159:0] f_s32(input logic [31:0] w_a);
    f_s32 = {{128{w_a[31]}},w_a};
  endfunction
  function automatic logic f_row(input logic [351:0] w_r);
    f_row = w_r[351:288] == '0 && w_r[287:256] <= 32'd25600000
      && f_range(w_r[255:192],64'(-64'd10070000000),64'd10070000000)
      && f_range(w_r[191:128],w_r[255:192],64'd10070000000)
      && w_r[127:96] <= w_r[95:64] && w_r[95:64] <= 32'd20000000
      && f_range({{32{w_r[63]}},w_r[63:32]},64'(-64'd8000000),64'd0)
      && w_r[31:0] <= 32'd8000000;
  endfunction
'''
s+='''
  // Decode only initialized slots; counts bound every variable array index.
  always_comb begin : p_com_decode
    w_row = '0;
    w_next = '0;
    w_object = '0;
    if (reg_cell < PARA_MAX_CELLS && {1'b0,reg_cell}+9'd1 < {1'b0,reg_count}) begin
      w_row = reg_rows[reg_cell];
      w_next = reg_rows[reg_cell+8'd1];
    end
    if (reg_actor < PARA_MAX_OBJ) w_object = reg_obj[reg_actor];
    w_h = 32'(w_next[287:256]-w_row[287:256]);
    w_elapsed = 32'(w_row[287:256]-reg_rows[0][287:256]);
    w_event = 32'(w_object[63:32]-w_elapsed);
    w_accel = w_object[127:96];
    if (w_elapsed >= w_object[63:32]) w_accel = w_object[31:0];
    {w_lo,w_hi,w_y,w_half,w_error,w_reserve} = reg_lane;
    w_lane_ok = f_range(w_lo,64'(-64'd10000000000),64'd10000000000)
      && f_range(w_hi,w_lo,64'd10000000000)
      && f_range(w_y,64'(-64'd10000000000),64'd10000000000)
      && w_half > 64'd0 && w_half <= 64'd10000000
      && w_error <= 64'd1000000 && w_reserve <= 64'd10000000;
    w_lane_fit = !f_lt(64'(w_y-w_half-w_error),w_lo)
      && !f_lt(w_hi,64'(w_y+w_half+w_error));
    w_obj_ok = 1'b1;
    w_speed_ok = 1'b1;
    w_positive = '0;
    w_speed_product = '0;
    w_speed_limit = '0;
    for (int idx=0; idx<PARA_MAX_OBJ; idx++) begin
      if (idx < reg_world[8199:8192]) begin
        if (!(f_range(reg_obj[idx][255:192],64'(-64'd10000000000),64'd10000000000)
          && reg_obj[idx][191:160] <= 32'd20000000
          && f_range({{32{reg_obj[idx][159]}},reg_obj[idx][159:128]},
            64'(-64'd8000000),64'd2000000)
          && f_range({{32{reg_obj[idx][31]}},reg_obj[idx][31:0]},
            64'(-64'd8000000),64'd2000000)
          && reg_obj[idx][63:32] <= 32'd12800000
          && reg_obj[idx][127:64] > 64'd0 && reg_obj[idx][127:64] <= 64'd20000000))
          w_obj_ok = 1'b0;
        w_positive = '0;
        if (!reg_obj[idx][159]) w_positive = {32'd0,reg_obj[idx][159:128]};
        if (!reg_obj[idx][31] && {32'd0,reg_obj[idx][31:0]} > w_positive)
          w_positive = {32'd0,reg_obj[idx][31:0]};
        if (reg_count > 8'd0 && reg_count <= 8'(PARA_MAX_CELLS+1)) begin
          w_speed_product = 64'(w_positive * 64'(reg_rows[reg_count-8'd1][287:256]
            -reg_rows[0][287:256]));
          w_speed_limit = 64'((64'd20000000-{32'd0,reg_obj[idx][191:160]})*64'd1000000);
          if (w_speed_product > w_speed_limit) w_speed_ok = 1'b0;
        end
      end
    end
    w_pre_reason = 8'd0;
    casez ({!reg_term[49] || reg_count<8'd2 || reg_term[7:0]!=reg_count || reg_bad_tag,
      reg_bad_row,!w_lane_ok,reg_world[8199:8192]>8'(PARA_MAX_OBJ),!w_lane_fit,
      !w_obj_ok,reg_count<8'd2 || reg_rows[reg_count-8'd1][287:256]<=reg_rows[0][287:256]
      || 32'(reg_rows[reg_count-8'd1][287:256]-reg_rows[0][287:256])>32'd12800000,
      !w_speed_ok})
      8'b1???????: w_pre_reason=8'd17;
      8'b01??????: w_pre_reason=8'd4;
      8'b001?????: w_pre_reason=8'd18;
      8'b0001????: w_pre_reason=8'd19;
      8'b00001???: w_pre_reason=8'd20;
      8'b000001??: w_pre_reason=8'd21;
      8'b0000001?: w_pre_reason=8'd16;
      8'b00000001: w_pre_reason=8'd22;
      default: w_pre_reason=8'd0;
    endcase
    w_inum_0 = 96'(96'(w_row[31:0])*96'(w_h)*96'(w_h)*96'(w_h));
    w_inum_1 = 96'(96'(w_h)*96'(w_h));
    w_gap = reg_ahead ? 64'(reg_pose[255:192]-reg_pose[63:0]-w_object[127:64])
      : 64'(reg_pose[127:64]-reg_pose[191:128]-w_object[127:64]);
    w_piece_margin = 64'(w_rsp[0][543:480]-w_reserve);
    w_all = &w_valid;
    w_issue = reg_fsm_ctrl_current_state==ENUM_ST_ISSUE && (&w_ready);
    w_consume = reg_fsm_ctrl_current_state==ENUM_ST_AWAIT && w_all;
    w_row_ok = f_row(i_row_data[352:1]);
  end

  // Public channels have one job owner; response stalls cannot alter the payload.
  always_comb begin : p_com_outputs
    o_req_ready = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
    o_row_ready = i_rst_n_core && reg_fsm_ctrl_current_state!=ENUM_ST_IDLE
      && reg_fsm_ctrl_current_state!=ENUM_ST_BOOT
      && reg_fsm_ctrl_current_state!=ENUM_ST_RESP && reg_count<8'(PARA_MAX_CELLS+1);
    o_terminal_ready = i_rst_n_core && !reg_term_valid
      && reg_fsm_ctrl_current_state!=ENUM_ST_IDLE
      && reg_fsm_ctrl_current_state!=ENUM_ST_BOOT
      && reg_fsm_ctrl_current_state!=ENUM_ST_RESP;
    o_rsp_valid = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_RESP;
    o_rsp_data = o_rsp_valid ? reg_resp : 81'd0;
  end

  // Five private primitives run one swept test and four outward advances together.
  always_comb begin : p_com_arith
    for (int idx=0; idx<5; idx++) w_req[idx]='0;
    w_req[0][1927:1920]=8'd4;
    w_req[0][1919:1760]=f_s64(w_gap);
    w_req[0][1759:1600]=f_s32(reg_ahead ? reg_vel[127:96] : reg_vel[63:32]);
    w_req[0][1599:1440]=f_s32(reg_ahead ? reg_oa : w_row[63:32]);
    w_req[0][1439:1280]=f_s32(reg_ahead ? reg_vel[31:0] : reg_vel[95:64]);
    w_req[0][1279:1120]=f_s32(reg_ahead ? w_row[63:32] : reg_oa);
    w_req[0][1119:960]={128'd0,reg_part};
    for (int idx=1; idx<5; idx++) begin
      w_req[idx][1927:1920]=8'd3;
      w_req[idx][1919:1760]=f_s64(reg_pose[255-(idx-1)*64 -:64]);
      w_req[idx][1759:1600]=f_s32(reg_vel[127-(idx-1)*32 -:32]);
      w_req[idx][1599:1440]=f_s32(idx<3 ? reg_oa : w_row[63:32]);
      w_req[idx][1439:1280]={128'd0,reg_part};
      w_req[idx][1279:1120]=160'((idx==2)||(idx==4));
    end
  end

  // Next-state datapath retains provisional failure while all later rows are validated.
  always_comb begin : p_com_ctrl
    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;
'''
for n in regs:s+=f'    w_{n}_nxt = reg_{n};\n'
for n,(_,size) in arrays.items():
    # Explicit element zero establishes the default for the checker's loop heuristic.
    s+=f'    w_{n}_nxt[0]=reg_{n}[0];\n'
    s+=f'    for (int idx=1; idx<{size}; idx++) w_{n}_nxt[idx]=reg_{n}[idx];\n'
s+='''    if (i_row_valid && o_row_ready) begin
      w_rows_nxt[reg_count] = i_row_data[352:1];
      w_count_nxt = 8'(reg_count+8'd1);
      w_bad_row_nxt = reg_bad_row || !w_row_ok;
      w_bad_tag_nxt = reg_bad_tag || i_row_data[400:361]!=reg_tag
        || i_row_data[360:353]!=reg_count;
    end
    if (i_terminal_valid && o_terminal_ready) begin
      w_term_nxt=i_terminal_data;
      w_term_valid_nxt=1'b1;
    end
    case (reg_fsm_ctrl_current_state)
      ENUM_ST_BOOT: w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      ENUM_ST_IDLE: if (i_req_valid) begin
        w_tag_nxt=i_req_data[8623:8584];
        w_world_nxt=i_req_data[8583:384];
        w_lane_nxt=i_req_data[383:0];
        w_count_nxt='0; w_term_valid_nxt=1'b0; w_bad_row_nxt=1'b0;
        w_bad_tag_nxt=1'b0; w_cell_nxt='0; w_actor_nxt='0; w_fail_nxt='0;
        w_steps_nxt='0; w_margin_nxt=64'd10000000000; w_resp_nxt='0;
        for (int idx=0; idx<PARA_MAX_OBJ; idx++) begin
          w_obj_nxt[idx]=i_req_data[8575-idx*256 -:256];
          w_motion_nxt[idx]={i_req_data[8575-idx*256 -:64],
            i_req_data[8575-idx*256 -:64],i_req_data[8511-idx*256 -:32],
            i_req_data[8511-idx*256 -:32]};
        end
        w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
      end
      ENUM_ST_ROW: begin
        if (reg_term_valid && reg_count==reg_term[7:0]
          && (reg_fail!=8'd0 || reg_bad_row || w_pre_reason!=8'd0
            || {1'b0,reg_cell}+9'd1>={1'b0,reg_count}))
          w_fsm_ctrl_nxt_state=ENUM_ST_FIN;
        else if (reg_fail==8'd0 && !reg_bad_row
          && {1'b0,reg_cell}+9'd1<{1'b0,reg_count}) begin
          casez ({w_h==32'd0 || w_h>32'd100000,
            reg_world[8199:8192]==8'd0 || reg_world[8199:8192]>8'(PARA_MAX_OBJ),
            !w_obj_ok})
            3'b1??: begin
              w_fail_nxt=8'd23; w_steps_nxt=reg_cell;
            end
            3'b01?,3'b001: begin
              w_cell_nxt=8'(reg_cell+8'd1);
            end
            default: w_fsm_ctrl_nxt_state=ENUM_ST_INFL;
          endcase
        end
      end
      ENUM_ST_INFL: w_fsm_ctrl_nxt_state=ENUM_ST_IWAIT;
      ENUM_ST_IWAIT: if (w_iv_0 && w_iv_1) begin
        w_inflate_nxt=64'(w_iq_0+w_iq_1);
        w_actor_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_ACT;
      end
      ENUM_ST_ACT: begin
        w_pose_nxt={reg_motion[reg_actor][191:64],
          64'(w_row[255:192]-reg_inflate),64'(w_row[191:128]+reg_inflate)};
        w_vel_nxt={reg_motion[reg_actor][63:0],w_row[127:64]};
        w_ahead_nxt=!f_lt(reg_motion[reg_actor][191:128],w_row[191:128]);
        w_part_nxt=w_h;
        w_remain_nxt='0;
        if (w_event>32'd0 && w_event<w_h && w_object[63:32]>w_elapsed) begin
          w_part_nxt=w_event; w_remain_nxt=32'(w_h-w_event);
        end
        w_oa_nxt=w_object[159:128];
        if (w_elapsed>=w_object[63:32]) w_oa_nxt=w_object[31:0];
        w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
      end
      ENUM_ST_ISSUE: if (&w_ready) w_fsm_ctrl_nxt_state=ENUM_ST_AWAIT;
      ENUM_ST_AWAIT: if (w_all) begin
        if (f_lt(w_piece_margin,reg_margin)) w_margin_nxt=w_piece_margin;
        casez ({w_rsp[0][640] || w_rsp[1][640] || w_rsp[2][640]
          || w_rsp[3][640] || w_rsp[4][640],w_piece_margin[63]})
          2'b1?: begin
            w_fail_nxt=8'd4; w_steps_nxt=reg_cell;
            w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
          end
          2'b01: begin
            w_fail_nxt=8'd24; w_margin_nxt=w_piece_margin;
            w_steps_nxt=8'(reg_cell+8'd1); w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
          end
          default: begin
            for (int idx=1; idx<5; idx++) begin
              w_pose_nxt[255-(idx-1)*64 -:64]=w_rsp[idx][543:480];
              w_vel_nxt[127-(idx-1)*32 -:32]=w_rsp[idx][351:320];
            end
            if (w_rsp[2][351:320]>32'd20000000) w_vel_nxt[95:64]=32'd20000000;
            if (reg_remain!=32'd0) begin
              w_part_nxt=reg_remain; w_remain_nxt='0; w_oa_nxt=w_object[31:0];
              w_fsm_ctrl_nxt_state=ENUM_ST_ISSUE;
            end else w_fsm_ctrl_nxt_state=ENUM_ST_STEP;
          end
        endcase
      end
      ENUM_ST_STEP: begin
        w_motion_nxt[reg_actor]={reg_pose[255:128],reg_vel[127:64]};
        if ({1'b0,reg_actor}+9'd1<{1'b0,reg_world[8199:8192]}) begin
          w_actor_nxt=8'(reg_actor+8'd1); w_fsm_ctrl_nxt_state=ENUM_ST_ACT;
        end else begin
          w_cell_nxt=8'(reg_cell+8'd1); w_fsm_ctrl_nxt_state=ENUM_ST_ROW;
        end
      end
      ENUM_ST_FIN: begin
        casez ({w_pre_reason!=8'd0,reg_fail!=8'd0})
          2'b1?: w_resp_nxt={1'b0,64'hffffffffffffffff,w_pre_reason,8'd0};
          2'b01: w_resp_nxt={1'b0,reg_fail==8'd24 ? reg_margin : 64'hffffffffffffffff,
            reg_fail,reg_steps};
          default: w_resp_nxt={1'b1,reg_margin,8'd0,8'(reg_count-8'd1)};
        endcase
        w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
      end
      ENUM_ST_RESP: if (i_rsp_ready) w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
      default: w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
    endcase
  end

  // Control is asynchronously invalidated; payload RAM is guarded by count and job state.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_ctrl
    if (!i_rst_n_core) begin
      reg_fsm_ctrl_current_state<=ENUM_ST_BOOT;
'''
for n in regs:s+=f"      reg_{n}<='0;\n"
s+='''    end else begin
      reg_fsm_ctrl_current_state<=w_fsm_ctrl_nxt_state;
'''
for n in regs:s+=f'      reg_{n}<=w_{n}_nxt;\n'
s+='    end\n  end\n\n  // Valid counts suppress all reads before the owning request initializes each slot.\n'
s+='  always_ff @(posedge i_clk_core) begin : p_ff_payload\n'
for n,(_,size) in arrays.items():s+=f'    for (int idx=0; idx<{size}; idx++) reg_{n}[idx]<=w_{n}_nxt[idx];\n'
s+='  end\n\n  // Independent divider pipelines preserve outward rounding without behavioral division.\n'
for i,den in enumerate([8000000000000000000,2000000000000]):
    s+=f'''  m_tsmx_arith_div #(.PARA_W(32'd96)) u_arith_div_{i} (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_valid(reg_fsm_ctrl_current_state==ENUM_ST_INFL),
    .i_num(w_inum_{i}), .i_den(96'd{den}), .i_up(1'b1),
    .o_valid(w_iv_{i}), .o_fault(w_if_{i}), .o_data(w_iq_{i})
  );
'''
s+='''  // Swept wraps the accepted divider with private rational candidate scheduling.
    m_tsmx_geom_swept u_geom_swept (
      .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
      .i_req_valid(w_issue), .i_req_data(w_req[0]), .i_rsp_ready(w_consume),
      .o_req_ready(w_ready[0]), .o_rsp_valid(w_valid[0]), .o_rsp_data(w_rsp[0])
    );
  // Four interval advances share two II1 pipelines and complete before the swept result.
  m_tsmx_geom_adv u_geom_adv (
    .i_clk_core(i_clk_core), .i_rst_n_core(i_rst_n_core),
    .i_valid(w_issue), .i_ready(w_consume), .i_pose(reg_pose), .i_vel(reg_vel),
    .i_oa(reg_oa), .i_ea(w_row[63:32]), .i_h(reg_part),
    .o_ready(w_adv_ready), .o_valid(w_adv_valid), .o_fault(w_adv_fault),
    .o_pose(w_adv_pose), .o_vel(w_adv_vel)
  );
  // Preserve the shared primitive's slot ABI at the local join.
  for (genvar gen_idx=1; gen_idx<5; gen_idx++) begin : gen_join
    // Local results retain the accepted arithmetic slot layout at the join.
    assign w_ready[gen_idx]=w_adv_ready;
    assign w_valid[gen_idx]=w_adv_valid;
    assign w_rsp[gen_idx]={w_adv_fault,
      {{96{w_adv_pose[255-(gen_idx-1)*64]}},w_adv_pose[255-(gen_idx-1)*64 -:64]},
      {{128{w_adv_vel[127-(gen_idx-1)*32]}},w_adv_vel[127-(gen_idx-1)*32 -:32]},320'd0};
  end
endmodule
`default_nettype wire
'''
s=s.replace('  logic [4:0] w_ready, w_valid;', '''  logic [4:0] w_ready, w_valid;
  logic w_adv_ready, w_adv_valid, w_adv_fault;
  logic [255:0] w_adv_pose;
  logic [127:0] w_adv_vel;''')
s=s.replace('w_next','w_nxt').replace('w_error','w_err')
# Like accepted arithmetic, group function callers to avoid Icarus sensitivity churn.
import re
s=re.sub(r'  end\n\n  // Public channels[^\n]*\n  always_comb begin : p_com_outputs',
         '    // Public channel mapping.',s)
s=re.sub(r'  end\n\n  // Five private[^\n]*\n  always_comb begin : p_com_arith',
         '    // Private arithmetic requests.',s)
s=re.sub(r'  end\n\n  // Next-state[^\n]*\n  always_comb begin : p_com_ctrl',
         '    // Provisional next-state computation.',s)
s=s.replace('    for (int idx=0; idx<5; idx++) w_req[idx]',
            "    w_req[0]='0;\n    for (int idx=1; idx<5; idx++) w_req[idx]")
a=s.index('    // Private arithmetic requests.')
b=s.index('    // Provisional next-state computation.')
request_body=s[a:b]
s=s[:a]+s[b:]
start=s.index("    w_row = '0;")
stop=s.index('    if (reg_actor < PARA_MAX_OBJ)',start)
s=s[:start]+"    w_object = '0;\n"+s[stop:]
where=s.index('  // Decode only initialized slots;')
s=s[:where]+'''  // Stable row reads keep operand data independent of ready/valid evaluation.
  assign w_row = (reg_cell < PARA_MAX_CELLS
    && {1'b0,reg_cell}+9'd1 < {1'b0,reg_count}) ? reg_rows[reg_cell] : 352'd0;
  assign w_nxt = (reg_cell < PARA_MAX_CELLS
    && {1'b0,reg_cell}+9'd1 < {1'b0,reg_count}) ? reg_rows[reg_cell+8'd1] : 352'd0;

'''+s[where:]
where=s.index('  // Control is asynchronously invalidated;')
s=s[:where]+'  // Stable operand decode does not depend on primitive ready.\n  always_comb begin : p_com_arith\n'+request_body+'  end\n\n'+s[where:]
s=s.replace("  assign w_nxt =", "  // The following endpoint supplies cell duration without changing the current row.\n  assign w_nxt =")
(P/'m_tsmx_geom.sv').write_text(s)

# Local wrapper exposes exactly the outward state updates B3 needs, using accepted dividers.
regs2={'busy':1,'done':1,'fault':1,'issue':3,'recv':3,'pose':256,'vel':128,'oa':32,'ea':32,'h':32}
t=header.replace('Row storage is resetless and guarded by the reset row count.',
                 'Control and quotient state are reset together.').replace(
                 'Streaming B3 geometry, deferred validation and private arithmetic.',
                 'Four outward interval advances through two private II1 dividers.')+'''module m_tsmx_geom_adv (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_valid,
  input wire i_ready,
  input wire [255:0] i_pose,
  input wire [127:0] i_vel,
  input wire [31:0] i_oa,
  input wire [31:0] i_ea,
  input wire [31:0] i_h,
  output logic o_ready,
  output logic o_valid,
  output logic o_fault,
  output logic [255:0] o_pose,
  output logic [127:0] o_vel
);
'''
for n,w in regs2.items():t+=f'  logic [{w-1}:0] reg_{n}, w_{n}_nxt;\n'
t+='''  logic [95:0] w_num_0,w_den_0,w_num_1,w_den_1,w_q_0,w_q_1,w_a,w_v,w_am;
  logic [63:0] w_x;
  logic w_en,w_up,w_valid_0,w_valid_1,w_fault_0,w_fault_1;

  // Decode four ordered jobs: actor lower/upper, ego lower/upper.
  always_comb begin : p_com_math
    o_ready=i_rst_n_core && !reg_busy;
    o_valid=i_rst_n_core && reg_done;
    o_fault=reg_fault;
    o_pose=reg_pose;
    o_vel=reg_vel;
    w_en=reg_busy && reg_issue<3'd4;
    w_up=reg_issue[0];
    w_a='0; w_v='0; w_x='0;
    if (reg_issue<3'd4) begin
      w_a=reg_issue<3'd2 ? {{64{reg_oa[31]}},reg_oa} : {{64{reg_ea[31]}},reg_ea};
      w_v={64'd0,reg_vel[127-reg_issue*32 -:32]};
    end
    w_am=w_a[95] ? 96'(~w_a+96'd1) : w_a;
    w_num_0=96'(96'd2000000*w_v*96'(reg_h)+w_a*96'(reg_h)*96'(reg_h));
    w_den_0=96'd2000000000000;
    if (w_a[95] && 96'(reg_h)*w_am>=w_v*96'd1000000) begin
      w_num_0=96'(w_v*w_v); w_den_0=96'(96'd2*w_am);
    end
    w_num_1=96'(w_v*96'd1000000+w_a*96'(reg_h));
    w_den_1=96'd1000000;
    w_busy_nxt=reg_busy;w_done_nxt=reg_done;w_fault_nxt=reg_fault;
    w_issue_nxt=reg_issue;w_recv_nxt=reg_recv;w_pose_nxt=reg_pose;w_vel_nxt=reg_vel;
    w_oa_nxt=reg_oa;w_ea_nxt=reg_ea;w_h_nxt=reg_h;
    if (i_valid && o_ready) begin
      w_busy_nxt=1'b1;w_done_nxt=1'b0;w_fault_nxt=1'b0;
      w_issue_nxt='0;w_recv_nxt='0;w_pose_nxt=i_pose;w_vel_nxt=i_vel;
      w_oa_nxt=i_oa;w_ea_nxt=i_ea;w_h_nxt=i_h;
    end
    if (w_en) w_issue_nxt=3'(reg_issue+3'd1);
    if (w_valid_0 && w_valid_1 && reg_recv<3'd4) begin
      w_x=reg_pose[255-reg_recv*64 -:64];
      w_pose_nxt[255-reg_recv*64 -:64]=64'(w_x+w_q_0[63:0]);
      w_vel_nxt[127-reg_recv*32 -:32]=w_q_1[95] ? 32'd0 : w_q_1[31:0];
      w_fault_nxt=reg_fault || w_fault_0 || w_fault_1;
      w_recv_nxt=3'(reg_recv+3'd1);
      if (reg_recv==3'd3) w_done_nxt=1'b1;
    end
    if (reg_done && i_ready)begin w_busy_nxt=1'b0;w_done_nxt=1'b0;end
  end

  // All wrapper state is reset, so no quotient from an abandoned job can survive reset.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_state
    if (!i_rst_n_core) begin
'''
for n in regs2:t+=f"      reg_{n}<='0;\n"
t+='    end else begin\n'
for n in regs2:t+=f'      reg_{n}<=w_{n}_nxt;\n'
t+='    end\n  end\n\n  // Numerator and velocity quotients share the same direction and ordered slot.\n'
for i in range(2):t+=f'''  m_tsmx_arith_div #(.PARA_W(32'd96)) u_arith_div_{i} (
    .i_clk_core(i_clk_core),.i_rst_n_core(i_rst_n_core),.i_valid(w_en),
    .i_num(w_num_{i}),.i_den(w_den_{i}),.i_up(w_up),
    .o_valid(w_valid_{i}),.o_fault(w_fault_{i}),.o_data(w_q_{i})
  );
'''
t+='endmodule\n`default_nettype wire\n'
(P/'m_tsmx_geom_adv.sv').write_text(t)

regs3={'busy':1,'done':1,'fault':1,'issue':3,'recv':3,'q':384,'min':64}
t=header.replace('Row storage is resetless and guarded by the reset row count.',
                 'Control and quotient state are reset together.').replace(
                 'Streaming B3 geometry, deferred validation and private arithmetic.',
                 'Exact swept quadratic minimum using private accepted II1 dividers.')+'''module m_tsmx_geom_swept (
  input wire i_clk_core,
  input wire i_rst_n_core,
  input wire i_req_valid,
  input wire [1927:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [640:0] o_rsp_data
);
'''
for n,w in regs3.items():t+=f'  logic [{w-1}:0] reg_{n}, w_{n}_nxt;\n'
t+='''  logic [63:0] w_gap,w_va,w_aa,w_vb,w_ab,w_h,w_ea,w_eb,w_ua,w_ub,w_tn,w_td;
  logic [127:0] w_num_0,w_num_1,w_den_0,w_den_1,w_q_0,w_q_1;
  logic [255:0] w_disp_0,w_disp_1;
  logic [63:0] w_result;
  logic w_en,w_point,w_active_a,w_active_b,w_valid_0,w_valid_1,w_fault_0,w_fault_1;

  // Seven candidate slots cover endpoints, both stops and three active-acceleration phases.
  function automatic logic [63:0] f_abs(input logic [63:0] w_a);
    f_abs=w_a[63] ? 64'(~w_a+64'd1) : w_a;
  endfunction
  function automatic logic f_lt(input logic [63:0] w_a,w_b);
    f_lt=w_a[63]!=w_b[63] ? w_a[63] : w_a<w_b;
  endfunction
  function automatic logic [255:0] f_disp(input logic [63:0] w_v,w_a,w_n,w_d);
    logic [127:0] w_num,w_den,w_acc;
    begin
      w_acc={{64{w_a[63]}},w_a};
      w_num=128'(128'd2000000*128'(w_v)*128'(w_n)*128'(w_d)
        +w_acc*128'(w_n)*128'(w_n));
      w_den=128'(128'd2000000000000*128'(w_d)*128'(w_d));
      if (w_a[63] && 128'(w_n)*128'(f_abs(w_a))
        >=128'(w_v)*128'd1000000*128'(w_d)) begin
        w_num=128'(128'(w_v)*128'(w_v));
        w_den=128'(128'd2*128'(f_abs(w_a)));
      end
      f_disp={w_num,w_den};
    end
  endfunction

  // Rational-time candidates are issued consecutively; invalid slots issue harmless zero work.
  always_comb begin : p_com_math
    {w_gap,w_va,w_aa,w_vb,w_ab,w_h}=reg_q;
    o_req_ready=i_rst_n_core && !reg_busy;
    o_rsp_valid=i_rst_n_core && reg_done;
    o_rsp_data='0;
    if (o_rsp_valid) o_rsp_data={reg_fault,{{96{reg_min[63]}},reg_min},480'd0};
    w_en=reg_busy && reg_issue<3'd7;
    w_point=1'b0;w_tn='0;w_td=64'd1;
    w_ea=w_aa;w_eb=w_ab;w_ua=w_va;w_ub=w_vb;
    w_active_a=1'b0;w_active_b=1'b0;
    case (reg_issue)
      3'd0: w_point=1'b1;
      3'd1: begin w_tn=w_h;w_point=1'b1;end
      3'd2: begin
        w_tn=64'(w_va*64'd1000000);w_td=f_abs(w_aa);
        w_point=w_aa[63] && w_tn>64'd0 && 128'(w_tn)<128'(w_h)*128'(w_td);
      end
      3'd3: begin
        w_tn=64'(w_vb*64'd1000000);w_td=f_abs(w_ab);
        w_point=w_ab[63] && w_tn>64'd0 && 128'(w_tn)<128'(w_h)*128'(w_td);
      end
      3'd4,3'd5,3'd6: begin
        if (reg_issue==3'd5)begin w_eb='0;if(w_ab[63])w_ub='0;end
        if (reg_issue==3'd6)begin w_ea='0;if(w_aa[63])w_ua='0;end
        w_td=64'(w_ea-w_eb);w_tn=64'((w_ub-w_ua)*64'd1000000);
        if(w_td[63])begin w_td=64'(~w_td+64'd1);w_tn=64'(~w_tn+64'd1);end
        w_active_a=!(w_aa[63] && 128'(w_va)*128'd1000000*128'(w_td)
          <=128'(w_tn)*128'(f_abs(w_aa)));
        w_active_b=!(w_ab[63] && 128'(w_vb)*128'd1000000*128'(w_td)
          <=128'(w_tn)*128'(f_abs(w_ab)));
        w_point=w_td!=64'd0 && !w_tn[63] && w_tn>64'd0
          && 128'(w_tn)<128'(w_h)*128'(w_td)
          && (reg_issue==3'd6 ? !w_active_a : w_active_a)
          && (reg_issue==3'd5 ? !w_active_b : w_active_b);
      end
      default: w_point=1'b0;
    endcase
    w_disp_0={128'd0,128'd1};w_disp_1={128'd0,128'd1};
    if (w_en && w_point) begin
      w_disp_0=f_disp(w_va,w_aa,w_tn,w_td);
      w_disp_1=f_disp(w_vb,w_ab,w_tn,w_td);
    end
    {w_num_0,w_den_0}=w_disp_0;{w_num_1,w_den_1}=w_disp_1;
    w_result=64'(w_gap+w_q_0[63:0]-w_q_1[63:0]);
    w_busy_nxt=reg_busy;w_done_nxt=reg_done;w_fault_nxt=reg_fault;
    w_issue_nxt=reg_issue;w_recv_nxt=reg_recv;w_q_nxt=reg_q;w_min_nxt=reg_min;
    if (i_req_valid && o_req_ready)begin
      w_busy_nxt=1'b1;w_done_nxt=1'b0;w_fault_nxt=1'b0;w_issue_nxt='0;w_recv_nxt='0;
      w_q_nxt={i_req_data[1823:1760],i_req_data[1663:1600],i_req_data[1503:1440],
        i_req_data[1343:1280],i_req_data[1183:1120],i_req_data[1023:960]};
      w_min_nxt=64'h7fffffffffffffff;
    end
    if(w_en)w_issue_nxt=3'(reg_issue+3'd1);
    if(w_valid_0 && w_valid_1 && reg_recv<3'd7)begin
      w_fault_nxt=reg_fault || w_fault_0 || w_fault_1;
      if(f_lt(w_result,reg_min))w_min_nxt=w_result;
      w_recv_nxt=3'(reg_recv+3'd1);
      if(reg_recv==3'd6)w_done_nxt=1'b1;
    end
    if(reg_done && i_rsp_ready)begin w_busy_nxt=1'b0;w_done_nxt=1'b0;end
  end

  // Asynchronous reset clears all outstanding work and response ownership.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_state
    if(!i_rst_n_core)begin
'''
for n in regs3:t+=f"      reg_{n}<='0;\n"
t+='    end else begin\n'
for n in regs3:t+=f'      reg_{n}<=w_{n}_nxt;\n'
t+='    end\n  end\n\n  // Front floors and rear ceils each use a private fully pipelined rational divider.\n'
for i in range(2):t+=f'''  m_tsmx_arith_div #(.PARA_W(32'd128)) u_arith_div_{i} (
    .i_clk_core(i_clk_core),.i_rst_n_core(i_rst_n_core),.i_valid(w_en),
    .i_num(w_num_{i}),.i_den(w_den_{i}),.i_up(1'b{i}),
    .o_valid(w_valid_{i}),.o_fault(w_fault_{i}),.o_data(w_q_{i})
  );
'''
t+='endmodule\n`default_nettype wire\n'
(P/'m_tsmx_geom_swept.sv').write_text(t)
