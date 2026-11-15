"""Reproduce CSR RTL from the immutable register contract; no golden/spec writes."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[3]
regs=json.loads((ROOT/'spec/tsmx_csr.json').read_text())['registers']
def val(r):
    result=0
    for f in r['fields']:
        lo=int(re.findall(r'\d+',f['bits'])[-1]);result|=int(f['reset'],0)<<lo
    return result
def mask(r,types):
    result=0
    for f in r['fields']:
        b=list(map(int,re.findall(r'\d+',f['bits'])));lo=b[-1];hi=b[0]
        if f['type'] in types:result|=((1<<(hi-lo+1))-1)<<lo
    return result
def lp(name):return 'LPARA_'+name.upper().replace('STATUS','STS').replace('ENABLE','EN')
ports=[('input wire','i_clk_core',1),('input wire','i_rst_n_core',1)]
for name,w in [('awaddr','PARA_ADDR_W'),('awprot',3),('awvalid',1),('wdata','PARA_DATA_W'),('wstrb',4),('wvalid',1),('bready',1),('araddr','PARA_ADDR_W'),('arprot',3),('arvalid',1),('rready',1)]:ports.append(('input wire','i_axi_'+name,w))
ports += [('input wire','i_sts_valid',1),('input wire','i_sts_data',115)]
for name,w in [('awready',1),('wready',1),('bvalid',1),('bresp',2),('arready',1),('rvalid',1),('rresp',2),('rdata','PARA_DATA_W')]:ports.append(('output logic','o_axi_'+name,w))
ports += [('output logic','o_config_data',4),('output logic','o_int_irq',1)]
params=[]
for r in regs:
    n=lp(r['name']);params += [f"  localparam logic [31:0] {n}_ADDR = 32'h{int(r['offset'],0):08x}",f"  localparam logic [31:0] {n}_RST = 32'h{val(r):08x}"]
params += ["  localparam logic [31:0] LPARA_CONFIG_IRQ = 32'h20"]
params += [f"  localparam logic [31:0] LPARA_{n} = 32'd{v}" for n,v in
           [('BYTE_W',8),('MODE_L3',3),('REASON_CRC',9),('REASON_CLK',1),
            ('REASON_SAMPLE',2),('REASON_EGO',11),('REASON_FRESH',12),
            ('REASON_FREEZE',13),('COMMIT_OK',0),('COMMIT_DONE',31),
            ('COMMIT_PENDING',32),('COMMIT_NONE',35)]]
text='''/*
 * Project      : TSM-X
 * Author       : TSMX project (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-10-29
 * Version      : 0.1
 * Description  : AXI4-Lite CSR subordinate, atomic status and sticky diagnostics.
 * Assumptions  : See R4_DECISIONS.md; reset release is synchronized by the wrapper.
 * Protocol     : AXI4-Lite; PROT accepted; spec fixes axi rather than axil names.
 */
`timescale 1ns/1ps
`default_nettype none
module m_tsmx_csr #(
  // Parameter Description: project byte address width; Config1 fixes this width.
  // Parameter values: 16 only; default 16.
  // Parameter unit: bit
  parameter logic [31:0] PARA_ADDR_W = 32'd16,
  // Parameter Description: project bus word width; byte strobes are fixed at four.
  // Parameter values: 32 only; default 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_DATA_W = 32'd32,
'''+',\n'.join(params)+'\n) (\n'
text+=',\n'.join('  '+t+' '+('' if w==1 else f'[{w}-1:0] ')+n for t,n,w in ports)+'\n);\n'
state={'aw_full':1,'w_full':1,'awaddr':'PARA_ADDR_W','wdata':'PARA_DATA_W','wstrb':4,'bvalid':1,'bresp':2,'rvalid':1,'rresp':2,'rdata':'PARA_DATA_W','en':1,'config_valid':1,'bist_wait':1,'soft_rst':1,'bist_start':1,'irq_en':8,'irq_sts':8,'sts':32,'fault_cnt':32,'crc_cnt':32,'fresh_cnt':32,'cert_cnt':32,'health_cnt':32,'lost':32,'reason':8,'cycles':32}
for n,w in state.items():
    dim='' if w==1 else f'[{w}-1:0] '
    text+=f'  logic {dim}reg_{n};\n  logic {dim}w_{n}_nxt;\n'
text+='''  logic w_wr;
  logic w_bad;
  logic w_active;
  logic [31:0] w_mask;
  logic [31:0] w_rd_data;
  logic [1:0] w_rd_resp;
  logic [7:0] w_irq_set;
  logic [7:0] w_reason;
  logic [7:0] w_commit;
  logic [2:0] w_mode;
  logic w_healthy;

  // Single slots accept AW and W independently; B backpressure blocks only writes.
  assign o_axi_awready = i_rst_n_core && !reg_aw_full && !reg_bvalid;
  assign o_axi_wready = i_rst_n_core && !reg_w_full && !reg_bvalid;
  assign o_axi_arready = i_rst_n_core && !reg_rvalid;
  assign o_axi_bvalid = i_rst_n_core && reg_bvalid;
  assign o_axi_bresp = o_axi_bvalid ? reg_bresp : 2'b00;
  assign o_axi_rvalid = i_rst_n_core && reg_rvalid;
  assign o_axi_rresp = o_axi_rvalid ? reg_rresp : 2'b00;
  assign o_axi_rdata = o_axi_rvalid ? reg_rdata : '0;
  assign o_config_data = {reg_config_valid, reg_en, reg_soft_rst, reg_bist_start};
  assign o_int_irq = |(reg_irq_en & reg_irq_sts);
  assign w_wr = reg_aw_full && reg_w_full && !reg_bvalid;
  assign w_active = reg_en || reg_sts[0] || (i_sts_valid && i_sts_data[76]);
  assign w_reason = i_sts_data[113:106];
  assign w_mode = i_sts_data[105:103];
  assign w_commit = i_sts_data[85:78];
  assign w_healthy = i_sts_data[73];
  assign w_irq_set = i_sts_valid ? i_sts_data[7:0] : 8'h00;

  // Enabled byte lanes only; no arithmetic divider or multiplier is inferred.
  always_comb begin : p_com_mask
    w_mask = '0;
    for (int idx = 0; idx < 4; idx++) begin
      w_mask[idx*8 +: 8] = {8{reg_wstrb[idx]}};
    end
  end

  // Read captures the pre-edge snapshot, including on a simultaneous status/write edge.
  always_comb begin : p_com_rd
    w_rd_data = '0;
    w_rd_resp = 2'b00;
    case (32'(i_axi_araddr))
'''
special={'ctrl':"{31'b0,reg_en}",'status':'reg_sts','irq_enable':"{24'b0,reg_irq_en}",'irq_status':"{24'b0,reg_irq_sts}",'fault_count':'reg_fault_cnt','crc_count':'reg_crc_cnt','fresh_count':'reg_fresh_cnt','cert_count':'reg_cert_cnt','health_count':'reg_health_cnt','log_lost':'reg_lost','last_reason':"{24'b0,reg_reason}",'decision_cycles':'reg_cycles','config_valid':"{31'b0,reg_config_valid}"}
for r in regs:text+=f"      {lp(r['name'])}_ADDR: w_rd_data = {special.get(r['name'],lp(r['name'])+'_RST')};\n"
text+='''      default: w_rd_resp = 2'b10;
    endcase
  end

  // Slot next state and register writes; a rejected access never modifies its target.
  always_comb begin : p_com_nxt
'''
for n in state:text+=f'    w_{n}_nxt = reg_{n};\n'
text+='''    w_bad = 1'b0;
    w_soft_rst_nxt = 1'b0;
    w_bist_start_nxt = 1'b0;
    if (o_axi_awready && i_axi_awvalid) begin
      w_aw_full_nxt = 1'b1;
      w_awaddr_nxt = i_axi_awaddr;
    end
    if (o_axi_wready && i_axi_wvalid) begin
      w_w_full_nxt = 1'b1;
      w_wdata_nxt = i_axi_wdata;
      w_wstrb_nxt = i_axi_wstrb;
    end
    if (o_axi_bvalid && i_axi_bready) w_bvalid_nxt = 1'b0;
    if (o_axi_rvalid && i_axi_rready) w_rvalid_nxt = 1'b0;
    if (o_axi_arready && i_axi_arvalid) begin
      w_rvalid_nxt = 1'b1;
      w_rdata_nxt = w_rd_data;
      w_rresp_nxt = w_rd_resp;
    end
    if (i_sts_valid) begin
      w_sts_nxt = '0;
      w_sts_nxt[0] = i_sts_data[76];
      w_sts_nxt[1] = w_healthy;
      w_sts_nxt[2] = !w_healthy || (w_mode == 3'd3) || i_sts_data[86];
      w_sts_nxt[5:3] = w_mode;
      w_sts_nxt[6] = i_sts_data[75];
      w_sts_nxt[7] = i_sts_data[74];
      w_sts_nxt[8] = i_sts_data[72];
      w_sts_nxt[17:16] = i_sts_data[88:87];
      w_lost_nxt = i_sts_data[39:8];
      if (reg_sts[1] && !w_healthy && (reg_health_cnt != 32'hffffffff))
        w_health_cnt_nxt = 32'(reg_health_cnt + 32'd1);
      if (i_sts_data[7]) begin
        w_reason_nxt = w_reason;
        w_cycles_nxt = i_sts_data[71:40];
        if (!i_sts_data[114] && (reg_fault_cnt != 32'hffffffff))
          w_fault_cnt_nxt = 32'(reg_fault_cnt + 32'd1);
        if ((w_reason == 8'd9) && (reg_crc_cnt != 32'hffffffff))
          w_crc_cnt_nxt = 32'(reg_crc_cnt + 32'd1);
        case (w_reason)
          8'd1,8'd2,8'd11,8'd12,8'd13: begin
            if (reg_fresh_cnt != 32'hffffffff)
              w_fresh_cnt_nxt = 32'(reg_fresh_cnt + 32'd1);
          end
          default: begin end
        endcase
        case (w_commit)
          8'd0,8'd31,8'd32,8'd35: begin end
          default: begin
            if (reg_cert_cnt != 32'hffffffff)
              w_cert_cnt_nxt = 32'(reg_cert_cnt + 32'd1);
          end
        endcase
      end
      if (reg_bist_wait && i_sts_data[72] && w_healthy) begin
        w_config_valid_nxt = 1'b1;
        w_bist_wait_nxt = 1'b0;
      end
    end
    if (w_wr) begin
      w_aw_full_nxt = 1'b0;
      w_w_full_nxt = 1'b0;
      w_bvalid_nxt = 1'b1;
      w_bresp_nxt = 2'b00;
      case (32'(reg_awaddr))
        LPARA_CTRL_ADDR: begin
          if (reg_wstrb[0]) begin
            if ((reg_wdata[2] && (w_active || reg_wdata[1] || reg_wdata[0])) ||
                (reg_wdata[1] && (w_active || reg_wdata[0])) ||
                (reg_wdata[0] && (w_active || !reg_config_valid))) begin
              w_bad = 1'b1;
            end else begin
              w_en_nxt = reg_wdata[0];
              w_soft_rst_nxt = reg_wdata[1];
              w_bist_start_nxt = reg_wdata[2];
              if (reg_wdata[2] || reg_wdata[1]) begin
                w_config_valid_nxt = 1'b0;
                w_bist_wait_nxt = reg_wdata[2];
                w_sts_nxt[8] = 1'b0;
              end
            end
          end
        end
        LPARA_IRQ_ENABLE_ADDR: begin
          if (reg_wstrb[0]) w_irq_en_nxt = reg_wdata[7:0];
        end
        LPARA_IRQ_STATUS_ADDR: begin
          if (reg_wstrb[0]) w_irq_sts_nxt = reg_irq_sts & ~reg_wdata[7:0];
        end
'''
for r in regs:
    if r['name'] in ('ctrl','irq_enable','irq_status') or not mask(r,('rw',)):continue
    n=lp(r['name']);m=mask(r,('rw',))
    text+=f'''        {n}_ADDR: begin
          if (|(w_mask & 32'h{m:08x})) begin
            if (w_active ||
                ((reg_wdata & w_mask & 32'h{m:08x}) != ({n}_RST & w_mask)))
              w_bad = 1'b1;
            w_config_valid_nxt = 1'b0;
            w_bist_wait_nxt = 1'b0;
          end
        end
'''
text+='''        default: w_bad = 1'b1;
      endcase
    end
    if (w_wr && w_bad) w_bresp_nxt = 2'b10;
    if (o_axi_arready && i_axi_arvalid && (w_rd_resp != 2'b00)) w_bad = 1'b1;
    if (w_bad) begin

      w_config_valid_nxt = 1'b0;
      w_bist_wait_nxt = 1'b0;
    end
    w_irq_sts_nxt = w_irq_sts_nxt | w_irq_set | (w_bad ? 8'(LPARA_CONFIG_IRQ) : 8'h00);
  end

  // Asynchronous invalidation; next-state is sampled only on the rising core edge.
  always_ff @(posedge i_clk_core or negedge i_rst_n_core) begin : p_ff_regs
    if (!i_rst_n_core) begin
'''
for n in state:text+=f"      reg_{n} <= {'LPARA_STATUS_RST' if n=='sts' else chr(39)+'0'};\n"
text+='    end else begin\n'
for n in state:text+=f'      reg_{n} <= w_{n}_nxt;\n'
text+='    end\n  end\nendmodule\n`default_nettype wire\n'
text=text.replace('LPARA_STATUS','LPARA_STS').replace('LPARA_IRQ_ENABLE','LPARA_IRQ_EN').replace('LPARA_IRQ_STATUS','LPARA_IRQ_STS')
text=text.replace('idx*8 +: 8','idx*LPARA_BYTE_W +: LPARA_BYTE_W').replace('{8{reg_wstrb[idx]}}','{LPARA_BYTE_W{reg_wstrb[idx]}}')
text=text.replace("3'd3","3'(LPARA_MODE_L3)")
for v,n in [(9,'REASON_CRC'),(1,'REASON_CLK'),(2,'REASON_SAMPLE'),(11,'REASON_EGO'),(12,'REASON_FRESH'),(13,'REASON_FREEZE'),(0,'COMMIT_OK'),(31,'COMMIT_DONE'),(32,'COMMIT_PENDING'),(35,'COMMIT_NONE')]:
    text=re.sub(r"8'd"+str(v)+r'\b',"8'(LPARA_"+n+")",text)
(ROOT/'rtl/csr/m_tsmx_csr.sv').write_text(text)
print('Generated m_tsmx_csr:',len(text.splitlines()),'lines')


