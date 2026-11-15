"""TSM-X / TSMX project / 0.1. Reproducible integration RTL emitter.

Only writes the I1-owned top directory. Handshake FSMs follow VLSIT Mealy example.
"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / 'rtl/top'
HEADER = '''/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : DESCRIPTION
 * Assumptions  : Section 9.2 packed ABI and Config1 SI constants are fixed.
 * Deviations   : HIE-02 functional children contain logic; m_tsmx_top is structural.
 *                PAR-03 literal ABI slices and SI constants preserve golden packing.
 */
`timescale 1ns/1ps
`default_nettype none
'''

def param(name, value, desc='replicated private candidate resources', values='1,2,4,8'):
    return (f'  // Parameter Description: {desc}.\n'
            f'  // Parameter values: {values}; default {value}.\n'
            f'  // Parameter unit: count\n'
            f"  parameter logic [31:0] PARA_{name} = 32'd{value}")

def expand_names(s):
    """Expand emitter shorthand into the VLSIT naming vocabulary; ports stay fixed."""
    stems=dict(pv='pending_valid',pp='pending_plan',pc='pending_cert',bv='backup_valid',
        bp='backup_plan',bc='backup_cert',cv='cmd_valid',rvalid='resp_valid',rsp='resp_data',
        hb='heartbeat',hb_en='heartbeat_en',hbtime='heartbeat_time',snap='snapshot',
        traj='trajectory',newplan='new_plan',newcert='new_cert',nomlead='nominal_lead',
        ingpar='ing_par',pppar='pending_plan_par',pcpar='pending_cert_par',
        bppar='backup_plan_par',bcpar='backup_cert_par',ctrlpar='ctrl_par',
        rf='rx_count',tf='tx_count',rhead='rx_head',rtail='rx_tail',thead='tx_head',
        ttail='tx_tail',tw='tx_word_idx',word='rx_word_idx',rx0='rx_data_0',rx1='rx_data_1',
        tx0='tx_data_0',tx1='tx_data_1',err0='rx_err_0',err1='rx_err_1',
        gsent='mrm_sent',msent='geom_sent',epoch='phase')
    for old,new in stems.items():
        s=re.sub(r'\breg_'+old+r'\b','reg_'+new,s)
        s=re.sub(r'\bw_'+old+r'_nxt\b','w_'+new+'_nxt',s)
    roles=dict(qv='req_valid',qr='req_ready',sv='resp_valid',sr='resp_ready',
               qd='req_data',sd='resp_data')
    s=re.sub(r'\bw_(\w+)_(qv|qr|sv|sr|qd|sd)\b',lambda m:'w_'+m[1]+'_'+roles[m[2]],s)
    arrays=dict(gqv='mrm_req_valid',gqr='mrm_req_ready',grv='mrm_row_valid',
        grr='mrm_row_ready',gsv='mrm_resp_valid',gsr='mrm_resp_ready',gqd='mrm_req_data',
        grd='mrm_row_data',gsd='mrm_resp_data',mqv='geom_req_valid',mqr='geom_req_ready',
        mrv='geom_row_valid',mrr='geom_row_ready',mtv='geom_terminal_valid',
        mtr='geom_terminal_ready',msv='geom_resp_valid',mqd='geom_req_data',
        mrd='geom_row_data',mtd='geom_terminal_data',msd='geom_resp_data',
        qv='req_valid',qr='req_ready',qd='req_data',cv='cmd_valid',cr='cmd_ready',cd='cmd_data')
    for old,new in arrays.items():s=re.sub(r'\bw_'+old+r'\b','w_'+new,s)
    s=re.sub(r'\bw_ar_','w_arith_',s)
    s=re.sub(r'\bu_ar\b','u_arith',s)
    s=re.sub(r'\bi_epoch\b','i_phase',s)
    return s.replace('LPARA_N','LPARA_PAIR_NUM')

class Module:
    def __init__(self, name, ports, params='', desc='Golden-ordered integration controller.'):
        self.name=name; self.ports=ports; self.params=params; self.desc=desc
        self.regs={}; self.states={}; self.decl=''; self.pre=''; self.defaults=''; self.tail=''; self.global_ctrl=''
    def reg(self,name,width=1,reset="'0"):
        self.regs[name]=(width,reset); return 'reg_'+name
    def state(self,name,body): self.states[name]=body
    def emit(self):
        width=len(self.states)
        s=HEADER.replace('DESCRIPTION',self.desc)
        s+=f'module {self.name}' + (' #(\n'+self.params+'\n)' if self.params else '')+' (\n'+self.ports+'\n);\n'
        s+='  typedef enum logic [%d:0] {\n'%(width-1)
        s+=',\n'.join(f"    ENUM_ST_{k} = {width}'h{1<<i:x}" for i,k in enumerate(self.states))
        s+='\n  } ctrl_state_type_def;\n  ctrl_state_type_def reg_fsm_ctrl_current_state, w_fsm_ctrl_nxt_state;\n'
        for n,(w,r) in self.regs.items():
            ran='' if w==1 else f'[{w-1}:0] '
            s+=f'  logic {ran}reg_{n}, w_{n}_nxt;\n'
        s+=self.decl+'\n'+self.pre+'\n'
        s+='  // Defaults retain state; unused FSM encodings recover through BOOT.\n  always_comb begin : p_com_ctrl\n'
        s+='    w_fsm_ctrl_nxt_state = reg_fsm_ctrl_current_state;\n'
        for n in self.regs: s+=f'    w_{n}_nxt = reg_{n};\n'
        s+=self.defaults+'\n    case (reg_fsm_ctrl_current_state)\n'
        for n,b in self.states.items(): s+=f'      ENUM_ST_{n}: begin\n{b}\n      end\n'
        s+='      default: w_fsm_ctrl_nxt_state = ENUM_ST_BOOT;\n    endcase\n'+self.global_ctrl+'\n  end\n'
        s+='  // Asynchronous assertion; the enclosing reset synchronizer releases this domain.\n'
        s+='  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ctrl\n'
        s+='    if (!i_rst_n_core) begin\n      reg_fsm_ctrl_current_state <= ENUM_ST_BOOT;\n'
        for n,(w,r) in self.regs.items(): s+=f'      reg_{n} <= {r};\n'
        s+='    end else begin\n      reg_fsm_ctrl_current_state <= w_fsm_ctrl_nxt_state;\n'
        for n in self.regs: s+=f'      reg_{n} <= w_{n}_nxt;\n'
        s+='    end\n  end\n'+self.tail+'\nendmodule\n`default_nettype wire\n'
        s=s.replace('w_reset','w_rst')
        (OUT/(self.name+'.sv')).write_text(expand_names(s))

CLOCK='  input wire i_clk_core,\n  input wire i_rst_n_core,\n'
def go(s): return '        w_fsm_ctrl_nxt_state = ENUM_ST_'+s+';'
def put(n,x): return f'        w_{n}_nxt = {x};'
def inst(mod,name,signals,params=''):
    return f'  {mod} '+(f'#({params}) ' if params else '')+f'u_{name} (\n'+',\n'.join(f'    .{p}({v})' for p,v in signals.items())+'\n  );\n'
def leaf(mod,name,reqw,rspw,extra=None,params=''):
    decl=f'  logic w_{name}_qv, w_{name}_qr, w_{name}_sv;\n'
    decl+=f'  logic [{reqw-1}:0] w_{name}_qd;\n  logic [{rspw-1}:0] w_{name}_sd;\n'
    sig=dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid=f'w_{name}_qv',
             i_req_data=f'w_{name}_qd',o_req_ready=f'w_{name}_qr',o_rsp_valid=f'w_{name}_sv',
             o_rsp_data=f'w_{name}_sd',i_rsp_ready="1'b1")
    if extra:sig.update(extra)
    return decl,inst(mod,name,sig,params)

def make_hash():
    m=Module('m_tsmx_hash',CLOCK+'''  input wire i_req_valid,
  input wire [7:0] i_op,
  input wire [10:0] i_len,
  input wire [8415:0] i_data,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [288:0] o_rsp_data''',desc='Top-owned canonical byte serializer and accepted codec.')
    for n,w in [('op',8),('len',11),('data',8416),('idx',11)]:m.reg(n,w)
    m.decl,m.tail=leaf('m_tsmx_codec','codec',45,289)
    m.defaults='''    o_req_ready = i_rst_n_core && reg_fsm_ctrl_current_state == ENUM_ST_IDLE;
    o_rsp_valid = i_rst_n_core && w_codec_sv;
    o_rsp_data = o_rsp_valid ? w_codec_sd : 289'd0;
    w_codec_qv = 1'b0; w_codec_qd = '0;'''
    m.state('BOOT',go('IDLE'))
    m.state('IDLE',"        if (i_req_valid) begin\n"+put('op','i_op')+put('len','i_len')+put('data','i_data')+put('idx',"11'd0")+go('SEND')+'\n        end')
    m.state('SEND','''        w_codec_qv = 1'b1;
        w_codec_qd = {reg_op, reg_idx==11'd0, reg_idx+11'd4>=reg_len,
          3'((reg_len-reg_idx>=11'd4) ? 11'd4 : reg_len-reg_idx),
          reg_data[8415-32'(reg_idx)*8 -:32]};
        if (w_codec_qr) begin
          if (reg_idx+11'd4>=reg_len) w_fsm_ctrl_nxt_state = ENUM_ST_WAIT;
          else w_idx_nxt = 11'(reg_idx+11'd4);
        end''')
    m.state('WAIT',"        if (w_codec_sv) w_fsm_ctrl_nxt_state = ENUM_ST_IDLE;")
    m.emit()

def make_sweep():
    m=Module('m_tsmx_sweep',CLOCK+'''  input wire i_req_valid,
  input wire [127:0] i_pose,
  input wire [31:0] i_epoch,
  input wire [8199:0] i_world,
  input wire [383:0] i_lane,
  input wire [1:0] i_kind,
  input wire [703:0] i_bridge,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [15:0] o_rsp_data''',param('G',8)+',\n'+param('P',8)+",\n  localparam logic [31:0] LPARA_N = (PARA_G<PARA_P) ? PARA_G : PARA_P",
             'All sixteen candidates, paired streaming contexts with terminal validation.')
    for n,w in [('pose',128),('epoch',32),('world',8200),('lane',384),('kind',2),('bridge',704),('base',8),('mask',16),('gsent',8),('msent',8),('done',8),('row',2)]: m.reg(n,w)
    m.decl='''  logic [PARA_G-1:0] w_gqv,w_gqr,w_grv,w_grr,w_gsv,w_gsr;
  logic [PARA_G*176-1:0] w_gqd;
  logic [PARA_G*401-1:0] w_grd;
  logic [PARA_G*50-1:0] w_gsd;
  logic [PARA_P-1:0] w_mqv,w_mqr,w_mrv,w_mrr,w_mtv,w_mtr,w_msv;
  logic [PARA_P*8624-1:0] w_mqd;
  logic [PARA_P*401-1:0] w_mrd;
  logic [PARA_P*50-1:0] w_mtd;
  logic [PARA_P*81-1:0] w_msd;
  logic [7:0] w_active;
'''
    m.defaults='''    o_req_ready = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
    o_rsp_valid = i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_RESP;
    o_rsp_data = o_rsp_valid ? reg_mask : 16'd0;
    w_gqv='0; w_gqd='0; w_grr='0; w_gsr='0;
    w_mqv='0; w_mqd='0; w_mrv='0; w_mrd='0; w_mtv='0; w_mtd='0;
    w_active='0;
    for (int idx=0;idx<LPARA_N;idx++) begin
      w_active[idx] = (reg_kind==2'd0) || idx==0;
    end'''
    m.state('BOOT',go('IDLE'))
    m.state('IDLE',"        if(i_req_valid) begin\n"+''.join(put(n,'i_'+n) for n in ['pose','epoch','world','lane','kind','bridge'])+put('base',"i_kind==2'd1 ? 8'd15 : 8'd0")+put('mask',"16'd0")+put('gsent',"8'd0")+put('msent',"8'd0")+put('done',"8'd0")+put('row',"2'd0")+go('RUN')+'\n        end')
    m.state('RUN','''        for(int idx=0;idx<LPARA_N;idx++) begin
          if(w_active[idx]) begin
            w_mqv[idx]=!reg_msent[idx];
            w_mqd[8624*idx +:8624]={8'(reg_base+8'(idx)),reg_epoch,reg_world,reg_lane};
            if(w_mqv[idx] && w_mqr[idx]) w_msent_nxt[idx]=1'b1;
            if(reg_kind!=2'd2) begin
              w_gqv[idx]=reg_msent[idx] && !reg_gsent[idx];
              w_gqd[176*idx +:176]={reg_pose,8'(reg_base+8'(idx)),reg_epoch,8'd128};
              if(w_gqv[idx] && w_gqr[idx]) w_gsent_nxt[idx]=1'b1;
              w_mrv[idx]=w_grv[idx]; w_mrd[401*idx +:401]=w_grd[401*idx +:401];
              w_grr[idx]=w_mrr[idx];
              w_mtv[idx]=w_gsv[idx]; w_mtd[50*idx +:50]=w_gsd[50*idx +:50];
              w_gsr[idx]=w_mtr[idx];
            end
            if(w_msv[idx] && !reg_done[idx]) begin
              w_done_nxt[idx]=1'b1;
              w_mask_nxt[reg_base+8'(idx)]=w_msd[81*idx+80];
            end
          end
        end
        if(reg_kind==2'd2 && reg_msent[0]) begin
          w_mrv[0]=reg_row<2'd2;
          w_mrd[0 +:401]={8'd0,reg_epoch,8'(reg_row),
            reg_bridge[703-352*32'(reg_row[0]) -:352],reg_row==2'd1};
          if(w_mrv[0] && w_mrr[0]) w_row_nxt=2'(reg_row+2'd1);
          w_mtv[0]=reg_row==2'd2;
          w_mtd[0 +:50]={1'b1,8'd0,1'b0,32'd0,8'd2};
        end
        if((reg_done & w_active)==w_active) begin
          if(reg_kind==2'd0 && reg_base+8'(LPARA_N)<8'd16) begin
            w_base_nxt=8'(reg_base+8'(LPARA_N));
            w_gsent_nxt='0; w_msent_nxt='0; w_done_nxt='0;
          end else w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        end''')
    m.state('RESP',go('IDLE'))
    m.tail='''  // B3 stores up to 129 endpoints while consuming cells, exceeding the 35-slot bound.
  for(genvar gen_idx=0;gen_idx<PARA_G;gen_idx++) begin : gen_mrm
'''+inst('m_tsmx_mrmgen','tsmx_mrmgen',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid='w_gqv[gen_idx]',i_req_data='w_gqd[176*gen_idx +:176]',o_req_ready='w_gqr[gen_idx]',i_row_ready='w_grr[gen_idx]',o_row_valid='w_grv[gen_idx]',o_row_data='w_grd[401*gen_idx +:401]',i_rsp_ready='w_gsr[gen_idx]',o_rsp_valid='w_gsv[gen_idx]',o_rsp_data='w_gsd[50*gen_idx +:50]'))+'  end\n'+'''  for(genvar gen_idx=0;gen_idx<PARA_P;gen_idx++) begin : gen_geom
'''+inst('m_tsmx_geom','tsmx_geom',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid='w_mqv[gen_idx]',i_req_data='w_mqd[8624*gen_idx +:8624]',o_req_ready='w_mqr[gen_idx]',i_row_valid='w_mrv[gen_idx]',i_row_data='w_mrd[401*gen_idx +:401]',o_row_ready='w_mrr[gen_idx]',i_terminal_valid='w_mtv[gen_idx]',i_terminal_data='w_mtd[50*gen_idx +:50]',o_terminal_ready='w_mtr[gen_idx]',i_rsp_ready="1'b1",o_rsp_valid='w_msv[gen_idx]',o_rsp_data='w_msd[81*gen_idx +:81]'))+'  end\n'
    m.emit()

EXT='''  // Explicit unsigned-vector sign extension and serial comparison.
  function automatic logic [159:0] f_s32(input logic [31:0] w_x);
    f_s32={{128{w_x[31]}},w_x};
  endfunction
  function automatic logic [159:0] f_s64(input logic [63:0] w_x);
    f_s64={{96{w_x[63]}},w_x};
  endfunction
  function automatic logic f_lt(input logic [63:0] w_a,w_b);
    f_lt=(w_a[63]!=w_b[63]) ? w_a[63] : w_a<w_b;
  endfunction
  function automatic logic [31:0] f_diff(input logic [31:0] w_a,w_b);
    f_diff=32'(w_a-w_b);
  endfunction
  function automatic logic [63:0] f_abs(input logic [63:0] w_x);
    f_abs=w_x[63] ? 64'(~w_x+64'd1) : w_x;
  endfunction
'''

def make_math():
    m=Module('m_tsmx_math',CLOCK+'''  input wire i_req_valid,
  input wire [2:0] i_op,
  input wire [255:0] i_ego,
  input wire [8199:0] i_world,
  input wire [31:0] i_delay,
  input wire [559:0] i_plan,
  input wire [31:0] i_rear,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic o_ok,
  output logic [8199:0] o_world,
  output logic [703:0] o_bridge,
  output logic [95:0] o_pose''',desc='Golden reaction, world propagation, bridge and original-epoch replay helpers.')
    for n,w in [('op',3),('ego',256),('world',8200),('delay',32),('plan',560),('rear',32),('ok',1),('idx',8),('x',64),('v',32),('a',32),('xh',64),('vh',32),('lx',64),('lv',32),('first',32),('up',1),('event',32),('bridge',704),('t',32),('h',32),('target',32),('jerk',32)]:m.reg(n,w)
    m.decl,m.tail=leaf('m_tsmx_arith','ar',1928,641)
    m.decl+='  logic [255:0] w_object;\n  logic [31:0] w_pa,w_j;\n'
    m.pre=EXT+'''  // Only initialized object slots are addressed.
  assign w_object=(reg_idx<8'd32) ? reg_world[8191-256*32'(reg_idx) -:256] : 256'd0;
  // Separate pure decodes avoid transient default writes retriggering their consumers.
  assign w_pa=(reg_t>=32'd100000 && reg_jerk==32'd0) ? reg_target : reg_a;
  assign w_j=(reg_t>=32'd100000 && w_pa!=reg_target && reg_jerk!=32'd0)
    ? (((w_pa[31]!=reg_target[31]) ? w_pa[31] : w_pa<reg_target)
       ? reg_jerk : 32'(-reg_jerk)) : 32'd0;
'''
    m.defaults='''    o_req_ready=i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE;
    o_rsp_valid=i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_RESP;
    o_ok=o_rsp_valid && reg_ok;
    o_world=o_rsp_valid ? reg_world : 8200'd0;
    o_bridge=o_rsp_valid ? reg_bridge : 704'd0;
    o_pose=o_rsp_valid ? {reg_x,reg_v} : 96'd0;
'''
    ar_decode=[]
    def ar(state,op,qs,body,nxt):
        ar_decode.append(f"      ENUM_ST_{state}: begin w_ar_qv=1'b1; w_ar_qd={{8'd{op},"+','.join(qs+["160'd0"]*(12-len(qs)))+"}; end")
        m.state(state,"        if(w_ar_qr) w_fsm_ctrl_nxt_state=ENUM_ST_"+state+'W;')
        m.state(state+'W',"        if(w_ar_sv) begin\n          if(w_ar_sd[640]) begin\n"+put('ok',"1'b0")+go('RESP')+'\n          end else begin\n'+body+'\n'+go(nxt)+'\n          end\n        end')
    xout='w_ar_sd[543:480]';vout='w_ar_sd[351:320]'
    m.state('BOOT',go('IDLE'))
    m.state('IDLE',"        if(i_req_valid) begin\n"+''.join(put(n,'i_'+n) for n in ['op','ego','world','delay','plan','rear'])+put('ok',"1'b1")+put('bridge',"704'd0")+put('idx',"8'd0")+go('START')+'\n        end')
    m.state('START','''        case(reg_op)
          2'd0: begin
            if(reg_rear<=32'd285000) begin w_ok_nxt=1'b0;
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
            else w_fsm_ctrl_nxt_state=ENUM_ST_REGO;
          end
          3'd1,3'd4: begin
            if(reg_world[8199:8192]>8'd32) begin w_ok_nxt=1'b0;
              w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
            else w_fsm_ctrl_nxt_state=ENUM_ST_OBJ;
          end
          2'd2: w_fsm_ctrl_nxt_state=ENUM_ST_BLOW;
          2'd3: begin
            w_x_nxt=reg_plan[207:144]; w_v_nxt=reg_plan[143:112];
            w_t_nxt=32'd0;
            w_target_nxt=32'(-32'd2000000*(32'(reg_plan[79:72] >> 2)+32'd1));
            case(reg_plan[73:72])
              2'd0: w_jerk_nxt=32'd2000000;
              2'd1: w_jerk_nxt=32'd4000000;
              2'd2: w_jerk_nxt=32'd8000000;
              default: w_jerk_nxt=32'd0;
            endcase
            if(reg_delay[31] || reg_delay==32'd0) w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
            else w_fsm_ctrl_nxt_state=ENUM_ST_PHASE;
          end
          default: begin w_ok_nxt=1'b0; w_fsm_ctrl_nxt_state=ENUM_ST_RESP; end
        endcase''')
    ar('REGO',3,['f_s64(reg_ego[223:160])','f_s32(reg_ego[159:128])',"160'd0","160'd285000","160'd1"],put('xh',xout)+put('vh',vout),'RLEAD')
    ar('RLEAD',3,['f_s64(reg_ego[95:32])','f_s32(reg_ego[31:0])',"f_s32(32'(-32'd4000000))","160'd285000","160'd0"],put('lx',xout)+put('lv',vout),'RGAP')
    ar('RGAP',4,["f_s64(64'(reg_ego[95:32]-reg_ego[223:160]-64'd4800000))",'f_s32(reg_ego[31:0])',"f_s32(32'(-32'd4000000))",'f_s32(reg_ego[159:128])',"160'd0","160'd285000"],put('ok',"!f_lt(w_ar_sd[543:480],64'd500000)"),'RGAP2')
    ar('RGAP2',4,["f_s64(64'(reg_lx-reg_xh-64'd4800000))",'f_s32(reg_lv)',"f_s32(32'(-32'd4000000))",'f_s32(reg_vh)',"f_s32(32'(-32'd8000000))","160'd3000000"],put('ok',"reg_ok && !f_lt(w_ar_sd[543:480],64'd500000)"),'RESP')
    m.state('OBJ','''        if(reg_idx>=reg_world[8199:8192]) w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        else begin
          w_x_nxt=w_object[255:192]; w_v_nxt=w_object[191:160];
          w_a_nxt=w_object[159:128]; w_event_nxt=w_object[63:32];
          w_first_nxt=(reg_delay<w_object[63:32]) ? reg_delay : w_object[63:32];
          w_up_nxt=reg_op!=3'd4 && f_lt(w_object[255:192],reg_ego[223:160]);
          w_fsm_ctrl_nxt_state=ENUM_ST_OADV;
        end''')
    ar('OADV',3,['f_s64(reg_x)','f_s32(reg_v)','f_s32(reg_a)',"{128'd0,reg_first}","{159'd0,reg_up}"],put('x',xout)+put('v',vout),'OADV2')
    ar('OADV2',3,['f_s64(reg_x)','f_s32(reg_v)','f_s32(w_object[31:0])',"{128'd0,32'(reg_delay-reg_first)}","{159'd0,reg_up}"],f'''        w_world_nxt[8191-256*32'(reg_idx) -:256]={{ {xout},{vout},
          w_object[159:64],reg_event>reg_delay ? 32'(reg_event-reg_delay):32'd0,
          w_object[31:0] }};
        w_idx_nxt=8'(reg_idx+8'd1);''','OBJ')
    ar('BLOW',3,['f_s64(reg_ego[223:160])','f_s32(reg_ego[159:128])','f_s32(reg_ego[127:96])',"{128'd0,reg_delay}","160'd0"],put('x',xout)+put('v',vout),'BHIGH')
    ar('BHIGH',3,['f_s64(reg_ego[223:160])','f_s32(reg_ego[159:128])','f_s32(reg_ego[127:96])',"{128'd0,reg_delay}","160'd1"],f'''        w_bridge_nxt={{
          64'd0,32'd0,reg_ego[223:160],reg_ego[223:160],
          reg_ego[159:128],reg_ego[159:128],reg_ego[127:96],32'd0,
          64'd0,reg_delay,reg_x,{xout},reg_v,{vout},reg_ego[127:96],32'd0}};''','RESP')
    m.state('PHASE','''        w_h_nxt=(reg_delay-reg_t>32'd20000) ? 32'd20000 : 32'(reg_delay-reg_t);
        if(reg_t>=reg_delay || reg_t>=32'd12800000) w_fsm_ctrl_nxt_state=ENUM_ST_RESP;
        else begin
          if(reg_t<32'd100000) begin w_a_nxt=reg_plan[111:80];
            w_fsm_ctrl_nxt_state=ENUM_ST_CONT; end
          else w_fsm_ctrl_nxt_state=ENUM_ST_PROF;
        end''')
    ar('PROF',5,["{152'd0,reg_plan[79:72]}","{128'd0,32'(reg_t-32'd100000)}",'f_s32(reg_plan[111:80])'],put('a','w_ar_sd[511:480]'),'CONT')
    ar('CONT',7,['f_s64(reg_x)','f_s32(reg_v)','f_s32(w_pa)','f_s32(w_j)','f_s32(reg_target)',"{128'd0,reg_h}","160'd0"],put('x',xout)+put('v',vout)+put('t',"32'(reg_t+reg_h)"),'PHASE')
    m.state('RESP',go('IDLE'))
    m.pre+='''  // State-only request decode isolates the primitive's ready from its request payload.
  always_comb begin : p_com_ar_req
    w_ar_qv=1'b0; w_ar_qd='0;
    case(reg_fsm_ctrl_current_state)
'''+ '\n'.join(ar_decode)+"\n      default: begin end\n    endcase\n  end\n"
    m.emit()

AXI='''  input wire [15:0] i_axi_awaddr,
  input wire [2:0] i_axi_awprot,
  input wire i_axi_awvalid,
  input wire [31:0] i_axi_wdata,
  input wire [3:0] i_axi_wstrb,
  input wire i_axi_wvalid,
  input wire i_axi_bready,
  input wire [15:0] i_axi_araddr,
  input wire [2:0] i_axi_arprot,
  input wire i_axi_arvalid,
  input wire i_axi_rready,
  output logic o_axi_awready,
  output logic o_axi_wready,
  output logic o_axi_bvalid,
  output logic [1:0] o_axi_bresp,
  output logic o_axi_arready,
  output logic o_axi_rvalid,
  output logic [1:0] o_axi_rresp,
  output logic [31:0] o_axi_rdata,
  output logic o_int_irq,
  input wire [9:0] i_log_idx,
  input wire i_log_valid,
  input wire i_log_ready,
  output logic o_log_ready,
  output logic [1055:0] o_log_data,
  output logic o_log_valid'''
DIRECT='''  input wire i_req_valid,
  input wire [44672:0] i_req_data,
  input wire i_rsp_ready,
  output logic o_req_ready,
  output logic o_rsp_valid,
  output logic [37:0] o_rsp_data,
  input wire [31:0] i_time_us,
  input wire i_ack_valid,
  input wire [31:0] i_ack_seq,
  output logic o_brake,
  output logic o_heartbeat,
'''

def make_engine():
    m=Module('m_tsmx_engine',CLOCK+DIRECT+'''  input wire [7:0] i_parse_reason,
  output logic o_cmd_valid,
  output logic [1896:0] o_cmd_data,
  input wire i_cmd_ready,
'''+AXI,param('G',8)+',\n'+param('P',8)+',\n'+param('DIRECT',0,'direct semantic port selection','0,1'),
        'Golden-ordered state ownership, admission, helpers, reseal and independent timers.')
    regs=[('req',44673),('parse_reason',8),('active',1),('ing',332),('proposal',332),('mode',3),('good',2),('fault',1),
          ('pv',1),('pp',560),('pc',1217),('issued',32),('bv',1),('bp',560),('bc',1217),
          ('reason',8),('commit',8),('cid',8),('label',8),('tail',8),('healthy',1),('reuse',1),
          ('world',8200),('future',8200),('lane',384),('lead',8200),('nomlead',8200),('bridge',704),
          ('context',256),('snap',256),('traj',256),('seal',256),('newplan',560),('newcert',1217),
          ('rsp',38),('final_rsp',38),('rvalid',1),('cmd',1897),('cv',1),('count',32),('lost',32),('deadline',1),
          ('override',1),('live_bad',1),('tick',32),('tick_valid',1),('hbtime',32),('hb',1),('hb_en',1),
          ('timer_code',8),('timer_valid',1),('ingpar',1),('pppar',1),('pcpar',1),
          ('bppar',1),('bcpar',1),('ctrlpar',1),('bist_wait',1),('csr_rst',1),
          ('dup_sent',1),('main_sent',1),('dup_done',1),('main_done',1),
          ('dup_result',1),('lane_good',1),('replay_full',1),('replay_event',1056),('log_drops',32)]
    for n,w in regs:
        reset="3'd3" if n=='mode' else "1'b1" if n in ('override','lane_good') else "'0"
        m.reg(n,w,reset)
    for mod,name,qw,sw in [('m_tsmx_ingress','b1',1374,340),('m_tsmx_splice','b2',816,1),('m_tsmx_cert','b9',2904,8),('m_tsmx_sel','b7',16,16),('m_tsmx_supervisor','b8',44,8),('m_tsmx_arb','arb',3863,1997),('m_tsmx_rec','rec',1056,32),('m_tsmx_health_lane','health',33824,1)]:
        extra={}
        if name=='arb': extra=dict(i_override="reg_override && reg_mode!=3'd4",o_brake='w_arb_brake')
        if name=='rec':extra={x:x for x in re.findall(r'\b[io]_log_\w+',AXI)}
        d,t=leaf(mod,name,qw,sw,extra);m.decl+=d;m.tail+=t
    m.decl+='''  logic w_arb_brake;
  logic [3:0] w_config;
  logic w_sts_valid;
  logic [114:0] w_sts_data;
  logic [31:0] w_now,w_delay,w_phase,w_n,w_xerr;
  logic [255:0] w_ego;
  logic [720:0] w_packet;
  logic [559:0] w_plan;
  logic [1216:0] w_cert;
  logic [31:0] w_tickdiff,w_remaining,w_ackage,w_applydiff;
  logic w_explicit,w_cap,w_reset,w_live,w_clockbad,w_tick,w_timer;
  logic [7:0] w_timer_code;
  logic w_ack;
  logic w_replay;
  logic w_fsm_valid;
  logic w_hash_qv,w_hash_qr,w_hash_sv;
  logic [7:0] w_hash_op;
  logic [10:0] w_hash_len;
  logic [8415:0] w_hash_data;
  logic [288:0] w_hash_sd;
  logic w_math_qv,w_math_qr,w_math_sv,w_math_ok;
  logic [2:0] w_math_op;
  logic [8199:0] w_math_world,w_math_out;
  logic [31:0] w_math_delay;
  logic [559:0] w_math_plan;
  logic [703:0] w_math_bridge;
  logic [95:0] w_math_pose;
  logic w_sweep_qv,w_sweep_qr,w_sweep_sv;
  logic [127:0] w_sweep_pose;
  logic [8199:0] w_sweep_world;
  logic [383:0] w_sweep_lane;
  logic [1:0] w_sweep_kind;
  logic [15:0] w_sweep_mask;
  logic w_dup_qv,w_dup_qr,w_dup_sv;
  logic [15:0] w_dup_mask;
  logic [255:0] w_event_reason,w_event_mode;
  logic [5:0] w_reason_len,w_mode_len;
'''
    m.pre=EXT+'''  // Immutable direct request field offsets follow spec 9.2 exactly.
  assign {w_now,w_ego,w_packet,w_cert} = reg_req[44672:42447];
  assign w_plan=w_packet[719:160];
  assign w_explicit=reg_req[33862] || reg_req[33861];
  assign w_cap=reg_req[33859];
  assign w_reset=reg_req[33857] || w_config[1] || reg_csr_rst;
  assign w_delay=f_diff(w_plan[239:208],w_ego[255:224]);
  assign w_phase=f_diff(w_now,reg_bp[239:208]);
  assign w_n=(w_phase+32'd19999)/32'd20000;
  assign w_xerr=(w_n+(w_n*(w_n-32'd1)+32'd99)/32'd100+32'd11>32'd640)
    ? w_n+(w_n*(w_n-32'd1)+32'd99)/32'd100+32'd11 : 32'd640;
  // Live state is admitted before codec, motion or candidate work.
  assign w_live=w_ego[255:224]==w_now
    && f_abs(w_ego[223:160])<=64'd10000000000
    && f_abs(w_ego[95:32])<=64'd10000000000
    && w_ego[159:128]<=32'd10000000 && w_ego[31:0]<=32'd10000000
    && !f_lt({{32{w_ego[127]}},w_ego[127:96]},64'(-64'd8000000))
    && !f_lt(64'd0,{{32{w_ego[127]}},w_ego[127:96]});
  // Rollback uses only the last committed decision epoch.
  assign w_clockbad=reg_ing[298] && f_diff(w_now,reg_ing[297:266])>=32'h80000000;
  // Tick arithmetic uses serial half-wrap ordering; no unsigned epoch ordering is substituted.
  assign w_tickdiff=f_diff(i_time_us,reg_tick);
  assign w_tick=reg_tick_valid && !w_tickdiff[31] && w_tickdiff>=32'd20000;
  assign w_remaining=f_diff(reg_pc[671:640],i_time_us);
  assign w_ackage=f_diff(i_time_us,reg_issued);
  assign w_applydiff=f_diff(i_time_us,reg_pp[239:208]);
  assign w_ack=(i_ack_valid && i_ack_seq==reg_pp[559:528])
    || (PARA_DIRECT!=32'd0 && i_req_valid && o_req_ready && i_req_data[33856]);
  assign w_replay=reg_pv && i_ack_valid && i_ack_seq!=reg_pp[559:528];
  // Regular subcycle service is supplemented at exact safety boundaries (spec6.2).
  assign w_timer=reg_pv && (w_tick || w_ack || w_timer_code==8'd29 || w_timer_code==8'd30);
  // Cached immutable records were hashed at admission; timer service has no codec dependency.
  always_comb begin : p_com_timer
    w_timer_code=8'd32;
    casez({w_remaining[31] || w_remaining==32'd0,
           !w_ack && !w_ackage[31] && w_ackage>=32'd40000,
           w_ack && !w_applydiff[31]})
      3'b1??: w_timer_code=8'd29;
      3'b01?: w_timer_code=8'd30;
      3'b001: w_timer_code=8'd31;
      default: w_timer_code=8'd32;
    endcase
  end
'''
    # ASCII event schema follows pack_event, independent of codec byte order.
    import sys
    sys.path.insert(0,str(ROOT/'golden'))
    from tsmx_golden.model import REASONS,MODES
    m.pre+='  // Golden Event string payloads, zero padded on the right.\n  always_comb begin : p_com_event\n'
    m.pre+="    w_event_reason='0; w_reason_len='0; w_event_mode='0; w_mode_len='0;\n    case(reg_reason)\n"
    for i,r in enumerate(REASONS):m.pre+=f"      8'd{i}: begin w_reason_len=6'd{len(r)}; w_event_reason=256'h{r.encode().ljust(32,bytes([0])).hex()}; end\n"
    m.pre+="      default: begin w_reason_len=6'd7; w_event_reason={56'h6e756d65726963,200'd0}; end\n    endcase\n    case(reg_mode)\n"
    for i,r in enumerate(MODES):m.pre+=f"      3'd{i}: begin w_mode_len=6'd{len(r)}; w_event_mode=256'h{r.encode().ljust(32,bytes([0])).hex()}; end\n"
    m.pre+="      default: begin w_mode_len=6'd2; w_event_mode={16'h4c33,240'd0}; end\n    endcase\n  end\n"
    m.defaults='''    o_req_ready=i_rst_n_core && reg_fsm_ctrl_current_state==ENUM_ST_IDLE
      && !reg_rvalid && !reg_cv && !reg_bist_wait && (PARA_DIRECT!=32'd0 || !w_config[0])
      && !reg_replay_full && reg_log_drops==32'd0 && !w_replay
      && (PARA_DIRECT!=32'd0 || (w_config[3] && w_config[2]));
    o_rsp_valid=i_rst_n_core && reg_rvalid;
    o_rsp_data=o_rsp_valid ? reg_rsp : 38'd0;
    o_cmd_valid=i_rst_n_core && reg_cv;
    o_cmd_data=o_cmd_valid ? reg_cmd : 1897'd0;
    o_brake=!i_rst_n_core || reg_override || w_arb_brake || reg_final_rsp[9];
    o_heartbeat=i_rst_n_core && reg_hb_en && reg_hb;
    w_hash_qv=1'b0; w_hash_op='0; w_hash_len='0; w_hash_data='0;
    w_math_qv=1'b0; w_math_op='0; w_math_world=reg_world;
    w_math_delay='0; w_math_plan=reg_bp;
    w_sweep_qv=1'b0; w_sweep_pose={w_ego[223:160],w_ego[159:128],w_ego[127:96]};
    w_dup_qv=1'b0;
    w_sweep_world=reg_world; w_sweep_lane=reg_lane; w_sweep_kind=2'd0;
    w_b1_qv=1'b0; w_b1_qd='0; w_b2_qv=1'b0; w_b2_qd='0;
    w_b9_qv=1'b0; w_b9_qd='0; w_b7_qv=1'b0; w_b7_qd='0;
    w_b8_qv=1'b0; w_b8_qd='0; w_arb_qv=1'b0; w_arb_qd='0;
    w_rec_qv=1'b0; w_rec_qd='0; w_health_qv=1'b0; w_health_qd='0;
    w_sts_valid=1'b0; w_sts_data='0;
    if(w_config[0]) w_bist_wait_nxt=1'b1;
    if(w_replay) begin
      if(!reg_replay_full) begin
        w_replay_full_nxt=1'b1;
        w_replay_event_nxt={1'b1,3'd4,1'b0,6'd0,224'd0,i_time_us,
          1'b1,6'd6,48'h7265706c6179,208'd0,1'b1,w_mode_len,w_event_mode,
          1'b0,6'd0,248'd0,reg_cid};
      end else if(reg_log_drops!=32'hffffffff) w_log_drops_nxt=32'(reg_log_drops+32'd1);
    end
    if(reg_rvalid && i_rsp_ready) begin w_rvalid_nxt=1'b0; w_rsp_nxt='0; end
    if(reg_cv && i_cmd_ready) begin w_cv_nxt=1'b0; w_cmd_nxt='0; end
    if(w_tick) w_tick_nxt=32'(i_time_us-(w_tickdiff%32'd20000));
    if((reg_mode==3'd1 || (!reg_pv && (reg_mode==3'd0 || reg_mode==3'd5)))
      && reg_bv && (f_diff(reg_bc[671:640],i_time_us)==32'd0
      || f_diff(reg_bc[671:640],i_time_us)>=32'h80000000)) w_override_nxt=1'b1;
    if(reg_hb_en && !f_diff(i_time_us,reg_hbtime)[31]
       && f_diff(i_time_us,reg_hbtime)>=32'd1000) begin
      w_hb_nxt=!reg_hb; w_hbtime_nxt=i_time_us;
    end
    if(w_timer && w_timer_code!=8'd32) begin
      w_timer_valid_nxt=1'b1; w_timer_code_nxt=w_timer_code;
      w_pv_nxt=1'b0;
      if(w_timer_code==8'd31) begin w_bv_nxt=1'b1; w_bp_nxt=reg_pp; w_bc_nxt=reg_pc; end
      else w_override_nxt=1'b1;
      w_sts_valid=1'b1;
      w_sts_data={{reg_final_rsp[37:10],w_timer_code!=8'd31,w_timer_code,reg_hb_en},
        reg_active,1'b0,w_timer_code==8'd31 || reg_bv,reg_healthy,reg_healthy,
        reg_count,reg_lost,8'h04};
    end'''
    # Helper call builders keep request and wait states separate, with no repeated consumption.
    def call(n,unit,data,body,nxt):
        m.state(n,f"        w_{unit}_qv=1'b1; w_{unit}_qd={data};\n        if(w_{unit}_qr) w_fsm_ctrl_nxt_state=ENUM_ST_{n}W;")
        m.state(n+'W',f"        if(w_{unit}_sv) begin\n{body}\n{go(nxt)}\n        end")
    def hashjob(n,op,length,data,body,nxt):
        m.state(n,f"        w_hash_qv=1'b1; w_hash_op=8'd{op}; w_hash_len=11'd{length};\n        w_hash_data={{ {data}, {8416-length*8}'d0 }};\n        if(w_hash_qr) w_fsm_ctrl_nxt_state=ENUM_ST_{n}W;")
        fault="" if n=='CRC' else "          if(w_hash_sd[288]) begin w_reason_nxt=8'd4; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end"
        m.state(n+'W',f"        if(w_hash_sv) begin\n{body}\n{go(nxt)}\n{fault}\n        end")
    def mathjob(n,op,args,body,nxt):
        m.state(n,f"        w_math_qv=1'b1; w_math_op=3'd{op};\n{args}\n        if(w_math_qr) w_fsm_ctrl_nxt_state=ENUM_ST_{n}W;")
        m.state(n+'W',f"        if(w_math_sv) begin\n{body}\n{go(nxt)}\n        end")
    def sweep(n,args,body,nxt):
        m.state(n,"        w_sweep_qv=1'b1;\n"+args+f'\n        if(w_sweep_qr) w_fsm_ctrl_nxt_state=ENUM_ST_{n}W;')
        m.state(n+'W',f'        if(w_sweep_sv) begin\n{body}\n{go(nxt)}\n        end')
    m.state('BOOT',go('IDLE'))
    m.state('IDLE',"        if(i_req_valid && o_req_ready) begin\n"+put('req','i_req_data')+put('parse_reason','i_parse_reason')+put('active',"1'b1")+put('count',"32'd1")+put('deadline',"1'b0")+put('live_bad',"1'b0")+put('reason',"8'd0")+put('commit',"8'd35")+put('reuse',"1'b0")+put('cid',"8'd15")+put('label',"8'd2")+put('tail',"8'd15")+'''        if(!reg_tick_valid) begin
          w_tick_valid_nxt=1'b1;
          w_tick_nxt=32'(i_time_us-(i_time_us%32'd20000));
          w_hbtime_nxt=i_time_us;
        end
        w_sts_valid=1'b1;
        w_sts_data={{reg_final_rsp[37:29],reg_mode,reg_cid,reg_label,reg_override,8'd35,reg_hb_en},
          1'b1,w_pv_nxt,w_bv_nxt,reg_healthy,reg_healthy,32'd0,reg_lost,8'd0};
'''+go('START')+'\n        end')
    m.state('START','''        if(!w_live || w_clockbad || reg_parse_reason!=8'd0) begin
          w_reason_nxt=reg_parse_reason!=8'd0 ? reg_parse_reason : (w_clockbad ? 8'd1 : 8'd43);
          w_commit_nxt=w_reason_nxt;
          w_timer_valid_nxt=1'b0;
          if(w_clockbad) begin
            w_tick_valid_nxt=1'b1;
            w_tick_nxt=32'(i_time_us-(i_time_us%32'd20000));
            w_hbtime_nxt=i_time_us;
          end
          w_healthy_nxt=1'b0; w_live_bad_nxt=1'b1;
          w_override_nxt=1'b1; w_hb_en_nxt=1'b0; w_hb_nxt=1'b0;
          w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;
        end else begin
          w_world_nxt='0;
          w_world_nxt[8199:8192]=8'd1;
          w_world_nxt[8191:7936]={w_ego[95:32],w_ego[31:0],32'd0,64'd4800000,
            w_ego[255:224]<32'd500000 ? 32'(32'd500000-w_ego[255:224]):32'd0,
            reg_req[33860] ? 32'(-32'd4000000):32'd0};
          w_lead_nxt=w_world_nxt;
          if(reg_req[33862]) w_world_nxt=reg_req[42446:34247];
          w_lane_nxt={64'hffffffffffe488c0,64'd1800000,64'd0,
            64'd950000,64'd50000,64'd500000};
          if(reg_req[33861]) w_lane_nxt=reg_req[34246:33863];
          if(!reg_req[33858]) begin
            w_healthy_nxt=1'b0; w_override_nxt=1'b1;
            w_hb_en_nxt=1'b0; w_hb_nxt=1'b0;
            w_fsm_ctrl_nxt_state=ENUM_ST_PENDING;
          end else w_fsm_ctrl_nxt_state=ENUM_ST_HEALTH;
        end''')
    prodhealth="{1'b1,11'd6,11'd6,31'd0,(^reg_ing),31'd0,(^reg_pp),31'd0,(^reg_pc),31'd0,(^reg_bp),31'd0,(^reg_bc),31'd0,(^{reg_mode,reg_good,reg_fault}),32576'd0,reg_ingpar,reg_pppar,reg_pcpar,reg_bppar,reg_bcpar,reg_ctrlpar,1018'd0,reg_lane_good,1'b1,(6'b000001 << reg_mode),1'b1}"
    m.states['IDLE']+='\n        if(reg_bist_wait && !reg_cv && !reg_rvalid) w_fsm_ctrl_nxt_state=ENUM_ST_BIST;'
    m.states['IDLE']+='\n        if((reg_replay_full || reg_log_drops!=32\'d0) && !reg_cv && !reg_rvalid) w_fsm_ctrl_nxt_state=ENUM_ST_TLOG;'
    m.state('TLOG','''        w_rec_qv=1'b1;
        w_rec_qd=reg_replay_full ? reg_replay_event : 1056'd0;
        if(w_rec_qr) begin
          if(reg_replay_full) w_replay_full_nxt=1'b0;
          else w_log_drops_nxt=32'(reg_log_drops-32'd1);
          w_fsm_ctrl_nxt_state=ENUM_ST_TLOGW;
        end''')
    m.state('TLOGW','''        if(w_rec_sv) begin
          w_lost_nxt=w_rec_sd;
          w_sts_valid=1'b1;
          w_sts_data={{reg_final_rsp[37:29],reg_mode,reg_cid,reg_label,reg_override,
            8'd26,reg_hb_en},1'b0,reg_pv,reg_bv,reg_healthy,reg_healthy,reg_count,w_rec_sd,8'h08};
          w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        end''')
    m.state('BIST',"        w_health_qv=1'b1; w_health_qd="+prodhealth+";\n        if(w_health_qr) w_fsm_ctrl_nxt_state=ENUM_ST_BISTW;")
    m.state('BISTW','''        if(w_health_sv) begin
          w_bist_wait_nxt=1'b0; w_healthy_nxt=w_health_sd[0];
          w_sts_valid=1'b1;
          w_sts_data={{1'b0,8'd0,reg_mode,8'd15,8'd2,!w_health_sd[0],8'd35,w_health_sd[0]},
            1'b0,reg_pv,reg_bv,w_health_sd[0],1'b1,32'd0,reg_lost,8'h10};
          if(!w_health_sd[0]) begin
            w_override_nxt=1'b1; w_pv_nxt=1'b0; w_bv_nxt=1'b0;
            w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1;
            w_hb_en_nxt=1'b0; w_hb_nxt=1'b0;
          end
          w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        end''')
    call('HEALTH','health',"PARA_DIRECT!=32'd0 ? reg_req[33823:0] : "+prodhealth,put('healthy','w_health_sd[0] && reg_req[33858]'),'PENDING')
    m.state('PENDING','''        if(reg_timer_valid) begin w_commit_nxt=reg_timer_code;
          w_timer_valid_nxt=1'b0; end
        if(reg_pv) w_fsm_ctrl_nxt_state=ENUM_ST_OLDCHK;
        else w_fsm_ctrl_nxt_state=ENUM_ST_CRC;
        if(reg_healthy==1'b0) begin w_hb_en_nxt=1'b0; w_hb_nxt=1'b0;
          w_override_nxt=1'b1; end''')
    call('OLDCHK','b9',"{1'b1,reg_pp,reg_pc,w_now,1'b1,1'b1,reg_issued,(PARA_DIRECT!=32'd0 ? reg_req[33856] : w_ack),1'b1,reg_pp[559:528],1'b0,256'd0,1'b0,reg_pc[1215:960],reg_pc[959:704],reg_pc[255:0]}",'''        w_commit_nxt=w_b9_sd;
        if(w_b9_sd==8'd31) begin w_bv_nxt=1'b1; w_bp_nxt=reg_pp; w_bc_nxt=reg_pc; end
        if(w_b9_sd!=8'd32) w_pv_nxt=1'b0;''','CRC')
    m.states['OLDCHK']+='''
        if(!reg_pv) begin
          w_b9_qv=1'b0;
          if(reg_timer_valid) begin w_commit_nxt=reg_timer_code; w_timer_valid_nxt=1'b0; end
          w_fsm_ctrl_nxt_state=ENUM_ST_CRC;
        end'''
    m.states['OLDCHKW']='''        if(w_b9_sv) begin
          casez({w_timer && w_timer_code!=8'd32,reg_timer_valid})
            2'b1?: begin w_commit_nxt=w_timer_code; w_timer_valid_nxt=1'b0; end
            2'b01: begin w_commit_nxt=reg_timer_code; w_timer_valid_nxt=1'b0; end
            default: begin
              w_commit_nxt=w_b9_sd;
              if(w_b9_sd==8'd31) begin w_bv_nxt=1'b1; w_bp_nxt=reg_pp; w_bc_nxt=reg_pc; end
              if(w_b9_sd!=8'd32) w_pv_nxt=1'b0;
            end
          endcase
          w_fsm_ctrl_nxt_state=ENUM_ST_CRC;
        end'''
    hashjob('CRC',0,86,'w_plan,w_packet[127:0]',put('seal',"{224'd0,w_hash_sd[287:256]}"),'INGRESS')
    call('INGRESS','b1',"{reg_ing,w_now,w_ego,w_packet,reg_seal[31:0],1'b1}",put('proposal','w_b1_sd[339:8]')+put('reason','w_b1_sd[7:0]'),'ADMIT')
    m.state('ADMIT',"        if(reg_reason==8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_CONTEXT;\n        else w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;")
    # Context objects remain empty when only the legacy effective lead is synthesized.
    hashjob('CONTEXT',3,1049,"(reg_req[33862] ? reg_req[42446:34247] : 8200'd0),reg_lane[383:256],32'd1,32'd1",put('context','w_hash_sd[255:0]'),'SNAP')
    hashjob('SNAP',1,32,'w_plan[527:272]',put('snap','w_hash_sd[255:0]'),'TRAJ')
    hashjob('TRAJ',2,70,'w_plan',put('traj','w_hash_sd[255:0]'),'SEAL')
    hashjob('SEAL',4,120,'w_cert[1215:256]',put('seal','w_hash_sd[255:0]'),'NEWCHK')
    call('NEWCHK','b9',"{w_packet[720],w_plan,w_cert,w_now,1'b0,1'b0,32'd0,1'b0,1'b0,32'd0,1'b1,reg_context,1'b0,reg_snap,reg_traj,reg_seal}",put('reason','w_b9_sd'),'SPLICE0')
    m.state('SPLICE0',"        if(reg_reason==8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_SPLICE;\n        else w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;")
    call('SPLICE','b2','{w_ego,w_plan}',"        if(!w_b2_sd[0]) w_reason_nxt=8'd36;",'REACT0')
    m.state('REACT0',"        if(reg_reason==8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_REACT;\n        else w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;")
    mathjob('REACT',0,'',"        if(!w_math_ok) w_reason_nxt=8'd37;",'NOM0')
    m.state('NOM0','''        if(reg_reason!=8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE;
        else begin
          w_math_delay='0;
          if(!f_diff(w_plan[239:208],w_plan[527:496])[31]
             && f_diff(w_plan[239:208],w_plan[527:496])>32'd500000) begin
            w_reason_nxt=8'd38; w_fsm_ctrl_nxt_state=ENUM_ST_OVERRIDE; end
          else w_fsm_ctrl_nxt_state=ENUM_ST_NPROP;
        end''')
    mathjob('NPROP',4,'''        w_math_world='0; w_math_world[8199:8192]=8'd1;
        w_math_world[8191:7936]={w_plan[367:304],w_plan[303:272],32'd0,64'd4800000,
          w_plan[527:496]<32'd500000 ? 32'(32'd500000-w_plan[527:496]):32'd0,
          reg_req[33860] ? 32'(-32'd4000000):32'd0};
        w_math_delay=f_diff(w_plan[239:208],w_plan[527:496]);
        if(w_math_delay[31]) w_math_delay=32'd0;''',put('nomlead','w_math_out'),'NOM')
    sweep('NOM',"        w_sweep_pose=w_plan[207:80]; w_sweep_world=reg_nomlead;\n        w_sweep_kind=2'd1; w_sweep_lane={64'hffffffffffe488c0,64'd1800000,64'd0,64'd950000,64'd50000,64'd500000};", "        if(!w_sweep_mask[15]) w_reason_nxt=8'd38;",'OVERRIDE')
    m.state('OVERRIDE','''        if(!w_cap) w_reason_nxt=8'd39;
        if(!reg_healthy) w_reason_nxt=8'd40;
        if(w_reset) w_reason_nxt=8'd41;
        w_dup_sent_nxt=1'b0; w_main_sent_nxt=1'b0;
        w_dup_done_nxt=1'b0; w_main_done_nxt=1'b0;
        w_fsm_ctrl_nxt_state=ENUM_ST_FALLBACK;''')
    sweep('FALLBACK','',put('context',"{240'd0,w_sweep_mask}"),'SEL')
    m.states['FALLBACK']='''        w_sweep_qv=!reg_main_sent;
        w_dup_qv=!reg_dup_sent;
        if(w_sweep_qv && w_sweep_qr) w_main_sent_nxt=1'b1;
        if(w_dup_qv && w_dup_qr) w_dup_sent_nxt=1'b1;
        if((reg_main_sent || w_sweep_qr) && (reg_dup_sent || w_dup_qr))
          w_fsm_ctrl_nxt_state=ENUM_ST_FALLBACKW;'''
    m.states['FALLBACKW']='''        if(w_sweep_sv) begin
          w_context_nxt={240'd0,w_sweep_mask}; w_main_done_nxt=1'b1;
        end
        if(w_dup_sv) begin w_dup_result_nxt=w_dup_mask[0]; w_dup_done_nxt=1'b1; end
        if((reg_main_done || w_sweep_sv) && (reg_dup_done || w_dup_sv)) begin
          w_lane_good_nxt=w_context_nxt[0]==w_dup_result_nxt;
          if(!w_lane_good_nxt && PARA_DIRECT==32'd0) begin
            w_healthy_nxt=1'b0; w_reason_nxt=w_reset ? 8'd41:8'd40;
            w_override_nxt=1'b1; w_hb_en_nxt=1'b0; w_hb_nxt=1'b0;
          end
          w_fsm_ctrl_nxt_state=ENUM_ST_SEL;
        end'''
    call('SEL','b7','reg_context[15:0]',put('cid','w_b7_sd[15:8]')+put('label','w_b7_sd[7:0]'),'TAIL0')
    m.state('TAIL0','''        if(reg_reason!=8'd0) w_fsm_ctrl_nxt_state=ENUM_ST_REUSE0;
        else begin
          if(!w_explicit && (f_diff(w_plan[239:208],w_plan[527:496])>=32'h80000000
             || f_diff(w_plan[239:208],w_plan[527:496])>32'd100000)) begin
            w_reason_nxt=8'd42; w_fsm_ctrl_nxt_state=ENUM_ST_REUSE0; end
          else begin
            if(w_explicit) w_fsm_ctrl_nxt_state=ENUM_ST_BRIDGE;
            else begin w_future_nxt=reg_nomlead; w_fsm_ctrl_nxt_state=ENUM_ST_TAIL; end
          end
        end''')
    mathjob('BRIDGE',2,"        w_math_delay=w_delay[31] ? 32'd0 : w_delay;",put('bridge','w_math_bridge'),'BRIDGE0')
    m.state('BRIDGE0',"        if(w_delay==32'd0 || w_delay[31]) w_fsm_ctrl_nxt_state=ENUM_ST_PROP;\n        else w_fsm_ctrl_nxt_state=ENUM_ST_BGEOM;")
    sweep('BGEOM',"        w_sweep_kind=2'd2;", "        if(!w_sweep_mask[0]) w_reason_nxt=8'd42;",'PROP')
    mathjob('PROP',1,"        w_math_delay=w_delay[31] ? 32'd0 : w_delay;",put('future','w_math_out'),'TAIL')
    sweep('TAIL',"        w_sweep_pose=w_plan[207:80]; w_sweep_world=reg_future;",put('context',"{240'd0,w_sweep_mask}"),'TSEL')
    call('TSEL','b7','reg_context[15:0]',put('tail','w_b7_sd[15:8]')+"        if(w_b7_sd[15:8]==8'd15) w_reason_nxt=8'd42;",'REUSE0')
    m.state('REUSE0','''        w_reuse_nxt=1'b0;
        if(reg_bv && !w_phase[31] && w_cap && reg_healthy)
          w_fsm_ctrl_nxt_state=ENUM_ST_RECHK;
        else w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;''')
    call('RECHK','b9',"{1'b1,reg_bp,reg_bc,w_now,1'b0,1'b0,32'd0,1'b0,1'b0,32'd0,1'b0,256'd0,1'b1,reg_bc[1215:960],reg_bc[959:704],reg_bc[255:0]}",put('reuse',"w_b9_sd==8'd0 && !f_diff(reg_bc[671:640],w_now)[31] && f_diff(reg_bc[671:640],w_now)>32'd120000"),'REPLAY0')
    m.state('REPLAY0',"        if(reg_reuse) w_fsm_ctrl_nxt_state=ENUM_ST_REPLAY;\n        else w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;")
    mathjob('REPLAY',3,"        w_math_delay=w_phase;",'''        w_reuse_nxt=w_math_ok
          && f_abs(64'(w_ego[223:160]-w_math_pose[95:32]))+64'd50000+64'(w_xerr)<=64'd160000
          && f_abs(64'({32'd0,w_ego[159:128]}-{32'd0,w_math_pose[31:0]}))+64'd50640<=64'd200000;''','SUPER')
    call('SUPER','b8',"{reg_mode,reg_good,reg_fault,reg_reason==8'd0,(reg_live_bad || reg_deadline) ? 32'd1000000 : w_ego[159:128],reg_reuse,reg_cid!=8'd15,w_cap,w_reset || reg_deadline,reg_healthy && !reg_live_bad}",'''        w_mode_nxt=w_b8_sd[7:5]; w_good_nxt=w_b8_sd[4:3]; w_fault_nxt=w_b8_sd[2];
        w_csr_rst_nxt=1'b0;
        if(w_b8_sd[1]) w_pv_nxt=1'b0;
        if(w_b8_sd[0]) w_bv_nxt=1'b0;''','COMMIT0')
    m.state('COMMIT0','''        w_ing_nxt[298]=1'b1; w_ing_nxt[297:266]=w_now;
        if(reg_reason==8'd0) begin
          w_newplan_nxt=w_plan; w_newplan_nxt[79:72]=reg_tail;
          w_ing_nxt=reg_proposal;
          w_fsm_ctrl_nxt_state=ENUM_ST_NEWHASH;
        end else w_fsm_ctrl_nxt_state=ENUM_ST_RECORD;''')
    hashjob('NEWHASH',2,70,'reg_newplan',put('traj','w_hash_sd[255:0]'),'NEWCERT')
    m.state('NEWCERT',put('newcert',"{1'b1,reg_snap,reg_traj,reg_newplan[239:208],w_cert[671:640],32'd1,32'd1,32'd1,32'd1,w_cert[511:256],256'd0}")+go('RESEAL'))
    hashjob('RESEAL',4,120,'reg_newcert[1215:256]',put('newcert',"{reg_newcert[1216:256],w_hash_sd[255:0]}")+put('pc',"{reg_newcert[1216:256],w_hash_sd[255:0]}")+put('pp','reg_newplan')+put('pv',"1'b1")+put('issued','w_now'),'RECORD')
    call('RECORD','rec',"{1'b1,3'd4,1'b0,6'd0,224'd0,w_now,1'b1,w_reason_len,w_event_reason,1'b1,w_mode_len,w_event_mode,1'b0,6'd0,248'd0,reg_cid}",put('lost','w_rec_sd'),'ARB0')
    m.state('ARB0','''        w_override_nxt=reg_live_bad || reg_deadline || !reg_healthy || reg_mode==3'd3;
        if((reg_mode==3'd0 || reg_mode==3'd5) && reg_pv
          && (f_diff(reg_pc[671:640],i_time_us)==32'd0
            || f_diff(reg_pc[671:640],i_time_us)>=32'h80000000)) w_override_nxt=1'b1;
        if(reg_mode==3'd1 && reg_bv
          && (f_diff(reg_bc[671:640],i_time_us)==32'd0
            || f_diff(reg_bc[671:640],i_time_us)>=32'h80000000)) w_override_nxt=1'b1;
        w_hb_en_nxt=reg_healthy && !reg_live_bad;
        if(!reg_hb_en && reg_healthy && !reg_live_bad) begin
          w_hbtime_nxt=i_time_us; w_hb_nxt=1'b0;
        end
        if(!reg_healthy || reg_live_bad) w_hb_nxt=1'b0;
        w_fsm_ctrl_nxt_state=ENUM_ST_ARB;''')
    call('ARB','arb',"{reg_mode,reg_cid,reg_label,w_now,reg_pv,reg_pp,reg_pc,reg_bv,reg_bp,reg_bc,w_ego}",put('cmd','w_arb_sd[1896:0]')+put('cv',"!reg_deadline"),'DELIVER')
    m.state('DELIVER','''        if(!reg_cv || i_cmd_ready) begin
          w_active_nxt=1'b0;
          if(!reg_deadline) begin
            w_rsp_nxt={reg_reason==8'd0,reg_reason,reg_mode,reg_cid,reg_label,
              reg_reason!=8'd0,reg_commit,reg_healthy && !reg_live_bad};
            w_final_rsp_nxt=w_rsp_nxt;
            w_rvalid_nxt=1'b1;
          end
          w_sts_valid=1'b1;
          w_sts_data={reg_deadline ? reg_final_rsp : w_rsp_nxt,1'b0,reg_pv,reg_bv,
            reg_healthy && !reg_live_bad,reg_healthy,
            reg_deadline ? 32'd1875000:32'(reg_count+32'd1),reg_lost,8'h81};
          w_fsm_ctrl_nxt_state=ENUM_ST_IDLE;
        end''')
    # All leaf response sinks remain ready; no hidden leaf reset is used on timeout.
    m.state('DRAIN','''        if(w_sweep_qr && w_dup_qr && w_math_qr && w_hash_qr && w_health_qr
          && w_b1_qr && w_b2_qr && w_b9_qr && w_b7_qr && w_b8_qr && w_arb_qr && w_rec_qr)
          w_fsm_ctrl_nxt_state=ENUM_ST_SUPER;''')
    m.global_ctrl='''    // Timers and deadline never depend on host, executor or recorder backpressure.
    if(reg_active && !reg_deadline) begin
      w_count_nxt=32'(reg_count+32'd1);
      if(reg_count==32'd1874999 && !w_rvalid_nxt) begin
        w_deadline_nxt=1'b1; w_reason_nxt=8'd7; w_commit_nxt=8'd35;
        w_timer_valid_nxt=1'b0;
        w_active_nxt=1'b0;
        w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1;
        w_pv_nxt=1'b0; w_bv_nxt=1'b0; w_override_nxt=1'b1;
        w_cv_nxt=1'b0; w_cmd_nxt='0;
        w_rsp_nxt={1'b0,8'd7,3'd3,8'd15,8'd2,1'b1,8'd35,reg_healthy};
        w_final_rsp_nxt=w_rsp_nxt;
        w_rvalid_nxt=1'b1; w_fsm_ctrl_nxt_state=ENUM_ST_DRAIN;
        w_sts_valid=1'b1; w_sts_data={w_rsp_nxt,1'b0,1'b0,1'b0,
          reg_healthy,reg_healthy,32'd1875000,reg_lost,8'h81};
      end
    end'''
    m.global_ctrl+='''
    // CSR reset revokes authority immediately and drains accepted work before reuse.
    if(w_config[1] && !w_deadline_nxt) begin
      w_timer_valid_nxt=1'b0;
      w_override_nxt=1'b1; w_pv_nxt=1'b0; w_bv_nxt=1'b0;
      w_hb_en_nxt=1'b0; w_hb_nxt=1'b0;
      w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1;
      if(reg_fsm_ctrl_current_state==ENUM_ST_IDLE) w_ing_nxt='0;
      else if(reg_fsm_ctrl_current_state!=ENUM_ST_BOOT
        && reg_fsm_ctrl_current_state!=ENUM_ST_BIST
        && reg_fsm_ctrl_current_state!=ENUM_ST_BISTW
        && reg_fsm_ctrl_current_state!=ENUM_ST_TLOG
        && reg_fsm_ctrl_current_state!=ENUM_ST_TLOGW) begin
        w_csr_rst_nxt=1'b1; w_reason_nxt=8'd41; w_commit_nxt=8'd35;
        w_live_bad_nxt=1'b1; w_cv_nxt=1'b0; w_cmd_nxt='0;
        w_fsm_ctrl_nxt_state=ENUM_ST_DRAIN;
      end
    end
    // Stored parity follows intentional writes after all fault/reset priorities resolve.
    if(w_ing_nxt!=reg_ing) w_ingpar_nxt=^w_ing_nxt;
    if(w_pp_nxt!=reg_pp) w_pppar_nxt=^w_pp_nxt;
    if(w_pc_nxt!=reg_pc) w_pcpar_nxt=^w_pc_nxt;
    if(w_bp_nxt!=reg_bp) w_bppar_nxt=^w_bp_nxt;
    if(w_bc_nxt!=reg_bc) w_bcpar_nxt=^w_bc_nxt;
    if({w_mode_nxt,w_good_nxt,w_fault_nxt}!={reg_mode,reg_good,reg_fault})
      w_ctrlpar_nxt=^{w_mode_nxt,w_good_nxt,w_fault_nxt};
'''
    # Elaboration-friendly function result sign tests (part-select on call unsupported in Icarus).
    m.defaults=m.defaults.replace('!f_diff(i_time_us,reg_hbtime)[31]',"f_diff(i_time_us,reg_hbtime)<32'h80000000")
    for n,b in m.states.items():
        b=b.replace('!f_diff(w_plan[239:208],w_plan[527:496])[31]',"f_diff(w_plan[239:208],w_plan[527:496])<32'h80000000")
        b=b.replace('!f_diff(reg_bc[671:640],w_now)[31]',"f_diff(reg_bc[671:640],w_now)<32'h80000000")
        m.states[n]=b
    m.tail+=inst('m_tsmx_hash','tsmx_hash',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid='w_hash_qv',i_op='w_hash_op',i_len='w_hash_len',i_data='w_hash_data',o_req_ready='w_hash_qr',o_rsp_valid='w_hash_sv',o_rsp_data='w_hash_sd'))
    m.tail+=inst('m_tsmx_math','tsmx_math',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid='w_math_qv',i_op='w_math_op',i_ego='w_ego',i_world='w_math_world',i_delay='w_math_delay',i_plan='w_math_plan',i_rear='reg_req[33855:33824]',o_req_ready='w_math_qr',o_rsp_valid='w_math_sv',o_ok='w_math_ok',o_world='w_math_out',o_bridge='w_math_bridge',o_pose='w_math_pose'))
    m.tail+=inst('m_tsmx_sweep','tsmx_sweep_0',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid='w_sweep_qv',i_pose='w_sweep_pose',i_epoch="32'd0",i_world='w_sweep_world',i_lane='w_sweep_lane',i_kind='w_sweep_kind',i_bridge='reg_bridge',o_req_ready='w_sweep_qr',o_rsp_valid='w_sweep_sv',o_rsp_data='w_sweep_mask'),'.PARA_G(PARA_G),.PARA_P(PARA_P)')
    m.tail+=inst('m_tsmx_sweep','tsmx_sweep_1',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_req_valid='w_dup_qv',i_pose="{w_ego[223:160],w_ego[159:128],w_ego[127:96]}",i_epoch="32'd0",i_world='reg_world',i_lane='reg_lane',i_kind="2'd3",i_bridge="704'd0",o_req_ready='w_dup_qr',o_rsp_valid='w_dup_sv',o_rsp_data='w_dup_mask'),".PARA_G(32'd1),.PARA_P(32'd1)")
    csr={x:x for x in re.findall(r'\b[io]_axi_\w+|o_int_irq',AXI)}
    csr.update(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',i_sts_valid='w_sts_valid',i_sts_data='w_sts_data',o_config_data='w_config')
    m.tail+=inst('m_tsmx_csr','tsmx_csr',csr)
    m.pre+='''  // Only declared one-hot controller encodings can retain transaction authority.
  always_comb begin : p_com_fsm_guard
    w_fsm_valid=1'b0;
    case(reg_fsm_ctrl_current_state)
'''+',\n'.join('      ENUM_ST_'+n for n in m.states)+''': w_fsm_valid=1'b1;
      default: w_fsm_valid=1'b0;
    endcase
  end
'''
    fault='''    // An invalid controller encoding revokes authority before safe drain/recovery.
    if(!w_fsm_valid) begin
      w_timer_valid_nxt=1'b0;
      w_override_nxt=1'b1; w_pv_nxt=1'b0; w_bv_nxt=1'b0;
      w_mode_nxt=3'd3; w_good_nxt=2'd0; w_fault_nxt=1'b1; w_healthy_nxt=1'b0;
      w_hb_en_nxt=1'b0; w_hb_nxt=1'b0; w_cv_nxt=1'b0; w_cmd_nxt='0;
      if(!reg_deadline) begin w_reason_nxt=8'd40; w_commit_nxt=8'd35; w_live_bad_nxt=1'b1; end
      if(reg_active || reg_deadline) w_fsm_ctrl_nxt_state=ENUM_ST_DRAIN;
      else w_fsm_ctrl_nxt_state=ENUM_ST_BOOT;
    end
'''
    m.global_ctrl=m.global_ctrl.replace('    // Stored parity follows',fault+'    // Stored parity follows')
    m.emit()

STREAM='''  input wire i_rx_valid,
  input wire [31:0] i_rx_data,
  input wire [3:0] i_rx_keep,
  input wire i_rx_last,
  output logic o_rx_ready,
  output logic o_tx_valid,
  output logic [31:0] o_tx_data,
  output logic [3:0] o_tx_keep,
  output logic o_tx_last,
  input wire i_tx_ready'''

def make_io():
    # Two complete receive slots and two complete command slots; each slot carries its own framing.
    m=Module('m_tsmx_io',CLOCK+'''  input wire i_req_valid,
  input wire [44672:0] i_req_data,
  output logic o_req_ready,
  output logic o_core_valid,
  output logic [44672:0] o_core_data,
  output logic [7:0] o_core_reason,
  input wire i_core_ready,
  input wire [31:0] i_time_us,
  input wire i_cmd_valid,
  input wire [1896:0] i_cmd_data,
  output logic o_cmd_ready,
'''+STREAM,param('DIRECT',0,'direct semantic port selection','0,1'),
        'Two-slot custom frame transport; immutable commands survive brake override.')
    for n,w in [('rx0',44673),('rx1',44673),('err0',8),('err1',8),('rf',2),('rhead',1),('rtail',1),('word',11),('partial',44673),('bad',1),('age',15),('tx0',1897),('tx1',1897),('tf',2),('thead',1),('ttail',1),('tw',7)]:m.reg(n,w)
    m.decl='  logic [31:0] w_rxword;\n  logic [1903:0] w_txbytes;\n'
    m.pre='''  // The exact semantic record is outer-padded at its LSB to a whole byte.
  assign w_txbytes={(reg_thead ? reg_tx1:reg_tx0),7'd0};
'''
    m.defaults='''    o_req_ready=1'b0; o_core_valid=1'b0; o_core_data='0; o_core_reason='0;
    o_rx_ready=i_rst_n_core && reg_rf<2'd2 && PARA_DIRECT==32'd0;
    if(PARA_DIRECT!=32'd0) begin
      o_core_valid=i_rst_n_core && i_req_valid;
      o_core_data=o_core_valid ? i_req_data:44673'd0;
      o_req_ready=i_rst_n_core && i_core_ready;
    end else begin
      o_core_valid=i_rst_n_core && reg_rf!=2'd0;
      if(o_core_valid) begin
        o_core_data=reg_rhead ? reg_rx1:reg_rx0;
        o_core_reason=reg_rhead ? reg_err1:reg_err0;
      end
    end
    o_cmd_ready=i_rst_n_core && reg_tf<2'd2;
    o_tx_valid=i_rst_n_core && reg_tf!=2'd0;
    o_tx_data='0; o_tx_keep='0; o_tx_last=1'b0;
    w_rxword=i_rx_data;
    if(o_tx_valid) begin
      o_tx_keep=4'hf;
      case(reg_tw)
        7'd0: o_tx_data=32'd2;
        7'd1: o_tx_data=32'd238;
        default: begin
          // Byte zero is the first canonical big-endian payload byte, in bus bits 7:0.
          for(int idx=0;idx<4;idx++) begin
            if(4*(32'(reg_tw)-2)+idx<238)
              o_tx_data[8*idx +:8]=w_txbytes[1903-8*(4*(32'(reg_tw)-2)+idx) -:8];
          end
          if(reg_tw==7'd61) begin o_tx_keep=4'b0011; o_tx_last=1'b1; end
        end
      endcase
    end
    if(PARA_DIRECT==32'd0 && o_core_valid && i_core_ready) begin
      w_rf_nxt=2'(reg_rf-2'd1); w_rhead_nxt=!reg_rhead;
    end
    if(i_cmd_valid && o_cmd_ready) begin
      if(reg_ttail) w_tx1_nxt=i_cmd_data; else w_tx0_nxt=i_cmd_data;
      w_ttail_nxt=!reg_ttail; w_tf_nxt=2'(reg_tf+2'd1);
    end
    if(o_tx_valid && i_tx_ready) begin
      if(o_tx_last) begin
        w_tw_nxt='0; w_thead_nxt=!reg_thead;
        w_tf_nxt=2'(w_tf_nxt-2'd1);
      end else w_tw_nxt=7'(reg_tw+7'd1);
    end'''
    m.state('BOOT',go('RUN'))
    m.state('RUN','''        if(reg_word!=11'd0) begin
          w_age_nxt=15'(reg_age+15'd1);
          if(reg_age==15'd16383) begin
            w_partial_nxt[44672:44641]=i_time_us;
            if(reg_rtail) begin w_rx1_nxt=w_partial_nxt; w_err1_nxt=8'd3; end
            else begin w_rx0_nxt=w_partial_nxt; w_err0_nxt=8'd3; end
            w_rtail_nxt=!reg_rtail; w_rf_nxt=2'(w_rf_nxt+2'd1);
            w_word_nxt='0; w_partial_nxt='0; w_bad_nxt=1'b0; w_age_nxt='0;
          end
        end
        if(i_rx_valid && o_rx_ready && reg_age!=15'd16383) begin
          if(reg_word==11'd0) w_age_nxt='0;
          case(reg_word)
            11'd0: begin w_bad_nxt=i_rx_data!=32'd1 || i_rx_keep!=4'hf || i_rx_last;
              w_partial_nxt='0; w_word_nxt=11'd1; end
            11'd1: begin w_bad_nxt=reg_bad || i_rx_data!=32'd5585
                || i_rx_keep!=4'hf || i_rx_last; w_word_nxt=11'd2; end
            default: begin
              for(int idx=0;idx<4;idx++) begin
                for(int bidx=0;bidx<8;bidx++) begin
                  if(8*(4*(32'(reg_word)-2)+idx)+bidx<44673)
                    w_partial_nxt[44672-(8*(4*(32'(reg_word)-2)+idx)+bidx)]
                      =i_rx_data[8*idx+7-bidx];
                end
              end
              w_bad_nxt=reg_bad || i_rx_last!=(reg_word==11'd1398)
                || i_rx_keep!=(reg_word==11'd1398 ? 4'b0001:4'hf)
                || (reg_word==11'd1398 && i_rx_data[6:0]!=7'd0);
              if(i_rx_last || reg_word==11'd1398) begin
                // Parser provenance is carried separately; no malformed value can authorize motion.
                if(reg_rtail) begin w_rx1_nxt=w_partial_nxt; w_err1_nxt=w_bad_nxt ? 8'd4:8'd0; end
                else begin w_rx0_nxt=w_partial_nxt; w_err0_nxt=w_bad_nxt ? 8'd4:8'd0; end
                w_rtail_nxt=!reg_rtail; w_rf_nxt=2'(w_rf_nxt+2'd1);
                w_word_nxt='0; w_partial_nxt='0; w_bad_nxt=1'b0; w_age_nxt='0;
              end else w_word_nxt=11'(reg_word+11'd1);
            end
          endcase
        end''')
    m.emit()

def make_top():
    p=param('G',8)+',\n'+param('P',8)+',\n'+param('DIRECT',0,'direct semantic port selection','0,1')
    ports=CLOCK+DIRECT+AXI+',\n'+STREAM
    s=HEADER.replace('DESCRIPTION','Structural top, synchronized reset, transport and all accepted block composition.')
    s+='module m_tsmx_top #(\n'+p+'\n) (\n'+ports+'\n);\n'
    s+='''  logic w_rst_n;
  logic w_qv,w_qr,w_cv,w_cr;
  logic [44672:0] w_qd;
  logic [1896:0] w_cd;
  logic [7:0] w_parse_reason;
'''
    s+='  // Reset release is synchronized once for the entire core domain.\n'
    s+=inst('m_tsmx_rst','tsmx_rst',dict(i_clk_core='i_clk_core',i_rst_n_core='i_rst_n_core',o_rst_n_core='w_rst_n'))
    sig={x:x for x in re.findall(r'\b[io]_\w+',DIRECT+AXI)}
    sig.update(i_clk_core='i_clk_core',i_rst_n_core='w_rst_n',i_req_valid='w_qv',i_req_data='w_qd',i_parse_reason='w_parse_reason',o_req_ready='w_qr',o_cmd_valid='w_cv',o_cmd_data='w_cd',i_cmd_ready='w_cr')
    s+='  // Engine owns all persistent semantic state and all accepted leaf transactions.\n'
    s+=inst('m_tsmx_engine','tsmx_engine',sig,'.PARA_G(PARA_G),.PARA_P(PARA_P),.PARA_DIRECT(PARA_DIRECT)')
    sig={x:x for x in re.findall(r'\b[io]_\w+',STREAM)}
    sig.update(i_clk_core='i_clk_core',i_rst_n_core='w_rst_n',i_req_valid='i_req_valid',i_req_data='i_req_data',o_req_ready='o_req_ready',o_core_valid='w_qv',o_core_data='w_qd',o_core_reason='w_parse_reason',i_time_us='i_time_us',i_core_ready='w_qr',i_cmd_valid='w_cv',i_cmd_data='w_cd',o_cmd_ready='w_cr')
    s+='  // Parameter selection changes only the request source, never decision arithmetic.\n'
    s+=inst('m_tsmx_io','tsmx_io',sig,'.PARA_DIRECT(PARA_DIRECT)')
    s+='endmodule\n`default_nettype wire\n';(OUT/'m_tsmx_top.sv').write_text(expand_names(s))
    s=HEADER.replace('DESCRIPTION','Asynchronous assertion and two-flop synchronous core reset release.')
    s+='''module m_tsmx_rst (
  input wire i_clk_core,
  input wire i_rst_n_core,
  output logic o_rst_n_core
);
  logic [1:0] reg_release;
  // Both stages assert asynchronously; only stage two releases functional state.
  assign o_rst_n_core=reg_release[1];
  // The core domain samples release on two successive rising edges.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_release
    if(!i_rst_n_core) reg_release<=2'b00;
    else reg_release<={reg_release[0],1'b1};
  end
endmodule
`default_nettype wire
''';(OUT/'m_tsmx_rst.sv').write_text(s)

if __name__=='__main__':
    make_hash(); make_sweep(); make_math(); make_engine(); make_io(); make_top()
