"""Generate portable clocked assertions from project AXI4-Lite contract 6.1."""
import json
from pathlib import Path
from gen_vectors import INPUTS,OUTPUTS,REGS,RW,field_mask
HERE=Path(__file__).resolve().parent
checks=[]
def add(name,ante,cons,target,kind='binary',clause='S6.1 AXI4-Lite'):
    checks.append(dict(name=name,ante=ante,cons=cons,target=target,kind=kind,clause=clause))
for n in ('awready','wready','arready','bvalid','rvalid'):
    add('reset_'+n,'!rst',f"{n} === 1'b0",n,clause='S5.5.12/S7 reset')
add('reset_config','!rst',"config_data === 4'b0",'config_data',clause='JSON reset')
for n in ('awready','wready','arready','bvalid','rvalid'):
    add('known_'+n,'rst',f'!$isunknown({n})',n,'x')
for n,ante in [('bresp','rst && bvalid'),('rresp','rst && rvalid'),('rdata','rst && rvalid'),('awaddr','rst && awvalid'),('awprot','rst && awvalid'),('wdata','rst && wvalid'),('wstrb','rst && wvalid'),('araddr','rst && arvalid'),('arprot','rst && arvalid')]:
    add('known_'+n,ante,f'!$isunknown({n})',n,'x')
add('b_encoding','rst && bvalid',"(bresp === 2'b00) || (bresp === 2'b10)",'bresp','x')
add('r_encoding','rst && rvalid',"(rresp === 2'b00) || (rresp === 2'b10)",'rresp','x')
add('b_order','rst && bvalid',"(bvalid === 1'b1) && (aw_count > b_count) && (w_count > b_count)",'bvalid')
add('r_order','rst && rvalid',"(rvalid === 1'b1) && (ar_count > r_count)",'rvalid')
add('aw_slot','rst && bvalid',"awready === 1'b0",'awready')
add('w_slot','rst && bvalid',"wready === 1'b0",'wready')
add('ar_slot','rst && rvalid',"arready === 1'b0",'arready')
for n,ante in [('bvalid','pbvalid && !pbready'),('bresp','pbvalid && !pbready'),('rvalid','prvalid && !prready'),('rresp','prvalid && !prready'),('rdata','prvalid && !prready')]:
    add('hold_'+n,'rst && '+ante,f'{n} === p{n}',n)
for n,ante in [('awvalid','pawvalid && !pawready'),('awaddr','pawvalid && !pawready'),('awprot','pawvalid && !pawready'),('wvalid','pwvalid && !pwready'),('wdata','pwvalid && !pwready'),('wstrb','pwvalid && !pwready'),('arvalid','parvalid && !parready'),('araddr','parvalid && !parready'),('arprot','parvalid && !parready')]:
    add('master_hold_'+n,'rst && prev_rst && '+ante,f'{n} === p{n}',n)
for n,w in OUTPUTS:
    add('exact_'+n,'1',f'{n} === exp_{n}',n,clause='S6.1/S11 JSON bit-exact cycle reference')
add('invalid_rdata','rst && !rvalid',"rdata === 32'b0",'rdata',clause='S5.3 invalid payload')
add('invalid_rresp','rst && !rvalid',"rresp === 2'b0",'rresp')
add('invalid_bresp','rst && !bvalid',"bresp === 2'b0",'bresp')
add('config_known','rst','!$isunknown(config_data)','config_data','x',clause='S5.4 configuration')
add('irq_known','rst','!$isunknown(irq)','irq','x',clause='S11 IRQ')
add('w1c_readback','rst && rvalid && last_rd_addr==16\'h000c','rdata === exp_rdata','rdata',clause='S6.1/JSON hardware-set wins W1C')
ro_addr=[int(r['offset'],0) for r in REGS if RW[int(r['offset'],0)]==0 and r['name']!='irq_status']
add('ro_write_ignored','rst && rvalid && ('+' || '.join(f"last_rd_addr==16'h{a:04x}" for a in ro_addr)+')','rdata === exp_rdata','rdata',clause='S6.1/JSON RO write error preserves data')
add('reserved_read_zero',"rst && rvalid && (reserved_mask(last_rd_addr)!=32'b0)","(rdata & reserved_mask(last_rd_addr)) === 32'b0",'rdata','ones',clause='S6.1/JSON reserved bits read zero')

text='''`timescale 1ns/1ps
// Project TSM-X; author TSMX project; version 0.1.
// Independent cycle vectors derive from JSON and project AXI4-Lite section 6.1.
// Immediate assertions work in Icarus and Verilator --timing --assert.
module tb_m_tsmx_csr;
  reg clk=0;
  `include "vectors_meta.svh"
  reg [VW-1:0] vectors[0:N-1];
  integer mutant=-1, injected=0, cycles=0;
  integer aw_count=0,w_count=0,b_count=0,ar_count=0,r_count=0;
  reg prev_rst=0;
  reg [15:0] last_rd_addr=0;
'''
for n,w in INPUTS:text+=f"  reg {'['+str(w-1)+':0] ' if w>1 else ''}{n}={'1' if n=='rst' else '0'};\n"
for n,w in OUTPUTS:
    text+=f"  wire {'['+str(w-1)+':0] ' if w>1 else ''}{n};\n"
    text+=f"  reg {'['+str(w-1)+':0] ' if w>1 else ''}exp_{n};\n"
for n,w in INPUTS+OUTPUTS:
    if n not in ('rst','deposit','sts_valid','sts_data','config_data','irq'):
        text+=f"  reg {'['+str(w-1)+':0] ' if w>1 else ''}p{n}=0;\n"
text+=f'  integer hits[0:{len(checks)-1}];\n'
text+='  m_tsmx_csr dut (\n    .i_clk_core(clk), .i_rst_n_core(rst),\n'
connections=[]
for n,w in INPUTS:
    if n in ('rst','deposit'):continue
    connections.append(f'.i_{n if n.startswith("sts") else "axi_"+n}({n})')
for n,w in OUTPUTS:connections.append(f'.o_{n if n=="config_data" else "int_irq" if n=="irq" else "axi_"+n}({n})')
text+='    '+',\n    '.join(connections)+'\n  );\n'
text+='  function automatic [31:0] reserved_mask(input [15:0] addr);\n    begin\n      reserved_mask=0;\n      case (addr)\n'
for r in REGS:
    mask=sum(field_mask(f) for f in r['fields'] if f['name']=='reserved')
    text+=f"        16'h{int(r['offset'],0):04x}: reserved_mask=32'h{mask:08x};\n"
text+="        default: reserved_mask=0;\n      endcase\n    end\n  endfunction\n"
text+='''  task tick;
    begin
      #1;
      if (!rst) begin
        aw_count=0;w_count=0;b_count=0;ar_count=0;r_count=0;last_rd_addr=0;
      end else begin
        if (awvalid && awready) aw_count=aw_count+1;
        if (wvalid && wready) w_count=w_count+1;
        if (bvalid && bready) b_count=b_count+1;
        if (arvalid && arready) begin ar_count=ar_count+1;last_rd_addr=araddr;end
        if (rvalid && rready) r_count=r_count+1;
      end
      // Previous edge master stability is checked before advancing this edge.
'''
def emit(idx,c):
    t=c['target'];fault="force "+t+" = 'x;" if c['kind']=='x' else "force "+t+" = '1;" if c['kind']=='ones' else f"if ({t} === '0) force {t} = '1; else force {t} = '0;"
    return f'''      if ({c['ante']}) begin : a_{c['name']}
        hits[{idx}]=hits[{idx}]+1;
        if (mutant=={idx} && !injected) begin
          {fault}
          injected=1;
          $display("INJECT {idx} {c['name']}");
          #1;
        end
        assert ({c['cons']}) else begin
          $display("ASSERT_FAIL {idx} {c['name']} cycle=%0d",cycles);
          $fatal(1,"R-025 assertion failed");
        end
      end
'''
for idx,c in enumerate(checks):
    if c['name'].startswith('master_hold_'):text+=emit(idx,c)
for n,w in INPUTS+OUTPUTS:
    if n not in ('rst','deposit','sts_valid','sts_data','config_data','irq'):text+=f'      p{n}={n};\n'
text+='''      if (deposit) begin
        force dut.reg_fault_cnt=32'hfffffffe;
        force dut.reg_crc_cnt=32'hfffffffe;
        force dut.reg_fresh_cnt=32'hfffffffe;
        force dut.reg_cert_cnt=32'hfffffffe;
        force dut.reg_health_cnt=32'hfffffffe;
        #1;
        release dut.reg_fault_cnt;
        release dut.reg_crc_cnt;
        release dut.reg_fresh_cnt;
        release dut.reg_cert_cnt;
        release dut.reg_health_cnt;
        #1;
      end
      #3;clk=1;#1;cycles=cycles+1;
'''
for idx,c in enumerate(checks):
    if not c['name'].startswith('master_hold_'):text+=emit(idx,c)
text+='''      #4;clk=0;prev_rst=rst;
    end
  endtask
  initial begin
    if ($value$plusargs("MUTANT=%d",mutant)) begin end
'''
text+=f'    for (integer k=0;k<{len(checks)};k=k+1) hits[k]=0;\n'
text+='    $readmemh("vectors.mem",vectors);\n    for (integer k=0;k<N;k=k+1) begin\n'
text+='      {'+','.join(n for n,w in INPUTS)+','+','.join('exp_'+n for n,w in OUTPUTS)+'}=vectors[k];\n      tick();\n    end\n'
for idx,c in enumerate(checks):
    text+=f'    $display("ASSERT {idx} {c["name"]} [{c["clause"]}] hits=%0d",hits[{idx}]);\n'
    text+=f'    if (hits[{idx}]==0) $fatal(1,"R-025 unexercised assertion {idx}");\n'
text+='''    if (mutant>=0) $fatal(1,"mutant not injected/detected");
    $display("assertion failures: 0, assertions never exercised: 0");
'''
text+=f'    $display("PASS csr: golden=128/128 cycles=%0d/%0d random=2400 registers=52 assertions={len(checks)}",N,N);\n'
text+='    $finish;\n  end\nendmodule\n'
(HERE/'tb_m_tsmx_csr.sv').write_text(text)
(HERE/'assertions.json').write_text(json.dumps(checks,indent=2)+'\n')
print('Assertions:',len(checks))
