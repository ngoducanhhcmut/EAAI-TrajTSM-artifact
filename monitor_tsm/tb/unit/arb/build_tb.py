"""Build portable immediate assertions from spec5.3/5.5.13/6.2/9.2.
TSM-X / TSMX project / version0.1. No RTL behavior is used as an oracle.
"""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
props=[]


def prop(name,ante,condition,net,bit=0,clause='5.3'):
    props.append(dict(id=len(props),name=name,ante=ante,condition=condition,net=net,bit=bit,clause=clause))


prop('reset_ready','!rst',"ready === 1'b0",'ready')
prop('reset_valid','!rst',"valid === 1'b0",'valid')
prop('reset_payload','!rst',"data === 1997'd0",'data')
prop('reset_brake','!rst',"brake === 1'b1",'brake',clause='5.5.13')
prop('invalid_zero','rst && !raw_valid',"data === 1997'd0",'data')
prop('no_overlap','rst && raw_valid',"ready === 1'b0",'ready')
prop('latency_one','take',"valid === 1'b1",'valid')
prop('whole_command','take',"data === pending_exp",'data',clause='5.5.13/9.2')
prop('hold_valid','rst && pv && !pc',"valid === 1'b1",'valid')
prop('hold_payload','rst && pv && !pc',"data === pd",'data')
prop('consume_valid','rst && pv && pc',"valid === 1'b0",'valid')
prop('consume_zero','rst && pv && pc',"data === 1997'd0",'data')
prop('idle_ready','rst && !raw_valid',"ready === 1'b1",'ready')
prop('idle_no_spurious_response','rst && !pv && !take',"valid === 1'b0",'valid')
prop('accepted_busy','take',"ready === 1'b0",'ready')
prop('brake_model','1',"brake === (!rst || ov || model_brake)",'brake',clause='5.5.13/6.2')
prop('override_immediate','ov',"brake === 1'b1",'brake',clause='6.2')
prop('sticky_revocation','rst && revoked && !ov',"brake === 1'b1",'brake',clause='6.2')
prop('override_frame_stable','rst && pv && !pc && ov',"data === pd",'data',clause='6.2')
# Every physical field, including all nested certificate/hash bits, gets its own assertion.
prop('reserved_zero','take',"data[1996:1897] === 100'd0",'data',1996,'9.2')
# Recompute field positions from the actual golden1897-bit record, with100 MSB spare.
fields=[]; offset=1897
for name,width in [('source',3),('mode',3),('label',8),('candidate',8),('seq',32),
                   ('apply',32),('expiry',32),('plan',560),('certificate',1217),('parking',1),('override',1)]:
    hi=offset-1; offset-=width; fields.append((name,hi,offset))
assert offset==0
for name,hi,lo in fields:
    prop('field_'+name,'take',f'data[{hi}:{lo}] === pending_exp[{hi}:{lo}]','data',lo,'9.2/5.5.13')
prop('L3_fixed15','take && pending_exp[1896:1894]==3',
     "data[1873:1866] === pending_exp[1873:1866]",'data',1866,'REQ-TSMX-024')
# Source-specific binding checks use computed field slices, independent of RTL.
fd={name:(hi,lo) for name,hi,lo in fields}
for name,source in [('nominal_record',0),('backup_epoch',1),('fallback_candidate',2),('parking_hold',4)]:
    hi,lo=fd['apply' if source==1 else 'plan' if source==0 else 'candidate' if source==2 else 'parking']
    prop(name,f'take && pending_exp[1896:1894]=={source}',
         f'data[{hi}:{lo}] === pending_exp[{hi}:{lo}]','data',lo,'5.5.13')
# Fix L3 candidate slice through computed ABI positions.
hi,lo=fd['candidate']; p=next(p for p in props if p['name']=='L3_fixed15')
p.update(condition=f'data[{hi}:{lo}] === 8\'d15',bit=lo)

head='''`timescale 1ns/1ps
// Project TSM-X; author TSMX project; version0.1.
// REQ-TSMX-024; spec5.3,5.5.13,6.2,9.2. Custom valid/ready, no standard bus.
// Mutations flip actual DUT observation wires; assertion operands are unchanged.
module tb_m_tsmx_arb;
  logic clk=0, rst=0, req_valid=0, rsp_ready=0, ov=0;
  logic [3862:0] req_data='0;
  wire raw_ready,raw_valid,raw_brake;
  wire [1996:0] raw_data;
  wire ready,valid,brake;
  wire [1996:0] data;
  logic flip_ready=0,flip_valid=0,flip_brake=0;
  logic [1996:0] flip_data='0;
  assign ready=raw_ready ^ flip_ready;
  assign valid=raw_valid ^ flip_valid;
  assign brake=raw_brake ^ flip_brake;
  assign data=raw_data ^ flip_data;
  `include "vectors_meta.svh"
  logic [5861:0] vectors[0:N-1];
  logic [1996:0] expected,pending_exp,pd;
  logic pr,pv,pc,take,model_brake=1,revoked=0,expected_brake;
  integer cycles=0,requests=0,responses=0,mutant=-1,injected=0;
  integer accepted_cycle=0,last_accept=0,min_ii=999999,max_ii=0,ii;
  integer min_latency=999999,max_latency=0,latency;
  integer hits[0:PROPCOUNT-1];
  m_tsmx_arb dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req_valid),
    .i_req_data(req_data),.i_rsp_ready(rsp_ready),.i_override(ov),
    .o_req_ready(raw_ready),.o_rsp_valid(raw_valid),.o_rsp_data(raw_data),.o_brake(raw_brake));
  task tick;
    begin
      pr=raw_ready; pv=raw_valid; pc=rsp_ready; pd=raw_data;
      take=rst && pr && req_valid;
      if (take) begin
        pending_exp=expected; requests++;
        accepted_cycle=cycles+1;
        if (last_accept!=0) begin
          ii=accepted_cycle-last_accept;
          if (ii<min_ii) min_ii=ii;
          if (ii>max_ii) max_ii=ii;
        end
        last_accept=accepted_cycle;
      end
      if (rst && pv && pc) responses++;
      if (!rst) begin model_brake=1; revoked=0; end
      else begin
        if (take) begin model_brake=expected_brake; revoked=0; end
        if (ov) begin model_brake=1; revoked=1; end
      end
      #4; clk=1; #1; cycles++;
      if(take && raw_valid) begin
        latency=cycles-accepted_cycle+1;
        if(latency<min_latency) min_latency=latency;
        if(latency>max_latency) max_latency=latency;
      end
ASSERTIONS
      #4; clk=0; #1;
    end
  endtask
  initial begin
    for(integer i=0;i<PROPCOUNT;i++) hits[i]=0;
    if($value$plusargs("MUTANT=%d",mutant)) begin end
    $readmemh("vectors.mem",vectors);
    expected='0; expected_brake=1;
    tick(); tick(); rst=1; tick();
    for(integer i=0;i<N;i++) begin
      if(!raw_ready) $fatal(1,"unexpected busy");
      {req_data,expected,ov,expected_brake}=vectors[i];
      req_valid=1; rsp_ready=0; tick(); req_valid=0;
      // Bounded stalls and noisy inactive input cannot change a held frame.
      for(integer j=0;j<(i%4);j++) begin
        req_data=~req_data; tick();
      end
      // Timer/watchdog overrides a stalled response at subcycle granularity.
      if(i%19==0 || i==EXPIRY_STALL) begin
        if(i==EXPIRY_STALL) begin
          if(raw_brake!==1'b0) $fatal(1,"nominal command was not authorized");
          $display("DIRECTED B9 expiry_at_executor while command stalled: now=100000");
        end
        ov=1; #1;
        if(raw_brake!==1'b1) $fatal(1,"asynchronous override missed");
        tick(); ov=0; tick();
      end
      rsp_ready=1; tick(); rsp_ready=0; ov=0;
    end
    // Queued producer keeps valid/data stable through response stalls and consumption.
    {req_data,expected,ov,expected_brake}=vectors[0];
    req_valid=1; tick();
    tick(); tick(); rsp_ready=1; tick();
    // The held second request is now accepted; it did not replace the first on consume.
    rsp_ready=0; tick(); req_valid=0;
    rsp_ready=1; tick(); rsp_ready=0;
    // Reset aborts an accepted/stalled job without a stale response after release.
    {req_data,expected,ov,expected_brake}=vectors[0];
    req_valid=1; tick(); req_valid=0; rst=0; tick(); rst=1; tick(); tick();
    if(raw_valid) $fatal(1,"stale response after reset");
    if(requests!=responses+1) $fatal(1,"request accounting");
PRINTS
    $display("assertion failures: 0, assertions never exercised: 0");
    $display("MEASURED cycles/job=%0d..%0d II=%0d..%0d (includes stalls) jobs=%0d cycles=%0d",min_latency,max_latency,min_ii,max_ii,requests,cycles);
    $display("PASS arb: golden=%0d/%0d edges=%0d/%0d extra=%0d/%0d all=%0d/%0d assertions=PROPCOUNT",GOLDEN,GOLDEN,EDGES,EDGES,N-GOLDEN-EDGES,N-GOLDEN-EDGES,N,N);
    $finish;
  end
endmodule
'''
blocks=[]; prints=[]
for p in props:
    i=p['id']; net=p['net']; bit=p['bit']
    injection=f"flip_data[{bit}]=1'b1;" if net=='data' else f"flip_{net}=1'b1;"
    blocks.append(f'''      if ({p['ante']}) begin : a_{p['name']}
        // spec{p['clause']}
        hits[{i}]++;
        if(mutant=={i} && !injected) begin {injection} injected=1; #1; end
        assert ({p['condition']}) else begin
          $display("ASSERT_FAIL {i} {p['name']} cycle=%0d actual=%h expected=%h",cycles,data,pending_exp);
          $fatal(1,"R-025 assertion failed");
        end
      end''')
    prints.append(f'''    if(hits[{i}]==0) $fatal(1,"unexercised assertion {i}");
    $display("ASSERT {i} {p['name']} spec{p['clause']} hits=%0d",hits[{i}]);''')
sv=head.replace('ASSERTIONS','\n'.join(blocks)).replace('PRINTS','\n'.join(prints)).replace('PROPCOUNT',str(len(props)))
(HERE/'tb_m_tsmx_arb.sv').write_text(sv,encoding='ascii')
(HERE/'assertions.json').write_text(json.dumps(props,indent=2)+'\n',encoding='ascii')
print(f'Built {len(props)} assertions')
