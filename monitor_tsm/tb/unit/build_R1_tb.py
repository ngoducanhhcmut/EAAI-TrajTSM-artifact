"""Emit standalone Icarus-compatible immediate assertion testbenches.

Checks derive from spec clauses, semantic expectations from convert_R1_vectors.py.
+MUTANT=N injects an X fault on the actual DUT output net when assertion N is active.
Every fault must cause that named immediate assertion to fail with nonzero exit.
"""
from pathlib import Path
import json

BASE=Path(__file__).resolve().parent

def make(blk,iw,ow):
    rec=blk=='rec'
    props=[]
    def prop(name,ante,condition,net):
        props.append((name,ante,condition,net))
    prop('S5_3_reset_ready','!rst','ready === 1\'b0','ready')
    prop('S5_3_reset_valid','!rst','valid === 1\'b0','valid')
    prop('S5_3_reset_data','!rst',"data === '0",'data')
    prop('S5_3_invalid_zero','rst && !valid',"data === '0",'data')
    prop('S5_3_ready_known','rst','!$isunknown(ready)','ready')
    prop('S5_3_valid_known','rst','!$isunknown(valid)','valid')
    prop('S5_3_valid_data_known','rst && valid','!$isunknown(data)','data')
    prop('S5_3_single_outstanding','rst && valid',"ready === 1'b0",'ready')
    prop('S5_3_accept_completes_1cy','rst && take',"valid === 1'b1",'valid')
    prop('S5_3_atomic_response','rst && take','data === expected','data')
    prop('S5_3_stall_valid','rst && pv && !pc',"valid === 1'b1",'valid')
    prop('S5_3_stall_payload','rst && pv && !pc','data === pd','data')
    prop('S5_3_stall_blocks_req','rst && pv && !pc',"ready === 1'b0",'ready')
    prop('S5_3_consume_valid','rst && pv && pc',"valid === 1'b0",'valid')
    prop('S5_3_consume_payload','rst && pv && pc',"data === '0",'data')
    prop('S5_3_no_unsolicited','rst && !pv && !take',"valid === 1'b0",'valid')
    prop('S5_3_idle_ready','rst && pr && !pq',"ready === 1'b1",'ready')
    prop('S5_3_release_ready','rst && !pr && !pv',"ready === 1'b1",'ready')
    if blk=='sel':
        prop('B7_candidate_range','rst && valid','data[15:8] <= 8\'d15','data')
        prop('B7_finite_jerk','rst && valid && data[15:8]!=15',"data[9:8] != 2'b11",'data')
        prop('B7_label_conditional','rst && valid && data[15:8]!=15',"data[7:0] === 8'd1",'data')
        prop('B7_empty_mitigation','rst && valid && (saved_req & 16\'h7777)==0',"data === 16'h0f02",'data')
        prop('B7_selected_accepted','rst && valid && (saved_req & 16\'h7777)!=0',"saved_req[data[15:8]] === 1'b1",'data')
        prop('B7_library_priority','rst && valid && (saved_req & 16\'h7777)!=0',"(saved_req & 16'h7777 & ((16'h1 << data[15:8])-1)) === 16'd0",'data')
        prop('B7_candidate_exact','rst && valid','data[15:8] === pending_exp[15:8]','data')
        prop('B7_label_exact','rst && valid','data[7:0] === pending_exp[7:0]','data')
    elif blk=='supervisor':
        normal="!saved_req[1] && saved_req[0] && saved_req[43:41]<=5"
        fault="(saved_req[1] || !saved_req[0] || saved_req[43:41]>5)"
        prop('B8_mode_legal','rst && valid',"data[7:5] <= 3'd5",'data')
        prop('B8_clear_order','rst && valid && data[0]',"data[1] === 1'b1",'data')
        prop('B8_reset_mode',f'rst && valid && {fault}',"data[7:5] === (saved_req[36:5]==0 ? 3'd4 : 3'd3)",'data')
        prop('B8_reset_good',f'rst && valid && {fault}',"data[4:3] === 2'd0",'data')
        prop('B8_accept_good',f'rst && valid && {normal} && saved_req[37]',"data[4:3] === (saved_req[40:39]==3 ? 2'd3 : saved_req[40:39]+2'd1)",'data')
        prop('B8_accept_fault',f'rst && valid && {normal} && saved_req[37]',"data[2:0] === 3'b000",'data')
        prop('B8_reject_fault',f'rst && valid && {normal} && !saved_req[37]',"data[4:1] === 4'b0011",'data')
        prop('B8_backup_retention',f'rst && valid && {normal}',"data[0] === 1'b0",'data')
        prop('B8_stopped_hold',f'rst && valid && {normal} && !saved_req[37] && saved_req[36:5]==0',"data[7:5] === 3'd4",'data')
        prop('B8_reuse_priority',f'rst && valid && {normal} && !saved_req[37] && saved_req[36:5]!=0 && saved_req[4] && saved_req[2]',"data[7:5] === 3'd1",'data')
        prop('B8_recovery_threshold',f'rst && valid && {normal} && saved_req[37]',"data[7:5] === (saved_req[40:39]>=2 ? 3'd0 : 3'd5)",'data')
        prop('B8_capability_gates',f'rst && valid && {normal} && !saved_req[37] && saved_req[36:5]!=0 && !saved_req[2]',"data[7:5] === 3'd3",'data')
    else:
        prop('B10_lost_exact','rst && valid','data === pending_exp','data')
        prop('B10_saturation','rst && valid && pending_exp==32\'hffffffff',"data === 32'hffffffff",'data')
        prop('B10_reset_log_ready','!rst',"log_ready === 1'b0",'log_ready')
        prop('B10_reset_log_valid','!rst',"log_valid === 1'b0",'log_valid')
        prop('B10_reset_log_data','!rst',"log_data === '0",'log_data')
        prop('B10_log_invalid_zero','rst && !log_valid',"log_data === '0",'log_data')
        prop('B10_log_ready_known','rst','!$isunknown(log_ready)','log_ready')
        prop('B10_log_valid_known','rst','!$isunknown(log_valid)','log_valid')
        prop('B10_log_data_known','rst && log_valid','!$isunknown(log_data)','log_data')
        prop('B10_log_single','rst && log_valid',"log_ready === 1'b0",'log_ready')
        prop('B10_read_completes_1cy','rst && lt',"log_valid === 1'b1",'log_valid')
        prop('B10_prewrite_snapshot','rst && lt','log_data === log_expected','log_data')
        prop('B10_log_stall_valid','rst && lv && !lc',"log_valid === 1'b1",'log_valid')
        prop('B10_log_stall_data','rst && lv && !lc','log_data === ld','log_data')
        prop('B10_log_consumed_valid','rst && lv && lc',"log_valid === 1'b0",'log_valid')
        prop('B10_log_consumed_data','rst && lv && lc',"log_data === '0",'log_data')
        prop('B10_write_while_log_stall','rst && take && lv && !lc',"valid === 1'b1",'valid')
        prop('B10_invalid_index','rst && lt && log_idx==1023 && DEPTH<1024',"log_data === '0",'log_data')
    n=len(props)
    declarations=f'''`timescale 1ns/1ps
// TSM-X / TSMX project / v0.1. Assertions: spec 5.3, 5.5.7/8/10, 7, 9.2.
// No standard bus exists on these ports. These are project valid/ready channels.
// MUTANT uses verification-only force on DUT-driven nets, never assertion operands.
module tb_m_tsmx_{blk};
  reg clk=0, rst=0, req_valid=0, rsp_ready=0;
  reg [{iw-1}:0] req_data=0;
  wire ready, valid;
  wire [{ow-1}:0] data;
  reg [{ow-1}:0] expected=0, pending_exp=0;
  reg [{iw-1}:0] saved_req=0;
  reg pr,pv,pq,pc,take;
  reg [{ow-1}:0] pd;
  integer hits[0:{n-1}];
  string assertion_name[0:{n-1}];
  string assertion_clause[0:{n-1}];
  integer mutant=-1, injected=0, cycles=0, requests=0, responses=0;
  integer wait_count;
  `include "vectors_meta.svh"
'''
    if rec:
        declarations+='''  reg [9:0] log_idx=0;
  reg log_req=0, log_consume=0;
  wire log_ready,log_valid;
  wire [1055:0] log_data;
  reg [1055:0] log_expected=0, ld;
  reg lv,lc,lt;
  reg [2156:0] vectors[0:N-1];
  reg [1:0] op;
  reg [1055:0] event_data;
  reg [31:0] event_lost;
  reg do_reset;
  reg [31:0] depth_case=4;
  reg [1055:0] depth_event;
  // The same TB also elaborates depths 1,3,64,1024 in the runner.
  parameter integer DEPTH=4;
'''
    else: declarations+=f'  reg [{iw+ow-1}:0] vectors[0:N-1];\n'
    declarations+=f'''  m_tsmx_{blk} '''+('#(.PARA_LOG_DEPTH(DEPTH)) ' if rec else '')+'''dut (
    .i_clk_core(clk), .i_rst_n_core(rst), .i_req_valid(req_valid), .i_req_data(req_data),
    .i_rsp_ready(rsp_ready), .o_req_ready(ready), .o_rsp_valid(valid), .o_rsp_data(data)'''
    if rec: declarations+=''',
    .i_log_idx(log_idx), .i_log_valid(log_req), .i_log_ready(log_consume),
    .o_log_ready(log_ready), .o_log_valid(log_valid), .o_log_data(log_data)'''
    declarations+='\n  );\n'
    monitor='''
  // Clocked immediate assertions sample before and after the acceptance edge.
  // One accepted request produces a response immediately after that edge: latency one cycle.
  task tick;
    begin
      pr=ready; pv=valid; pq=req_valid; pc=rsp_ready; pd=data;
      take=rst && pr && pq;
      if (take) begin
        saved_req=req_data; pending_exp=expected; requests=requests+1;
      end
      if (rst && pv && pc) responses=responses+1;
'''
    if rec: monitor+='      lv=log_valid; lc=log_consume; ld=log_data; lt=rst && log_req && log_ready;\n'
    monitor+='      #4; clk=1; #1; cycles=cycles+1;\n'
    for j,(name,ante,cond,net) in enumerate(props):
        monitor+=f'''      if ({ante}) begin : {name}
        hits[{j}]=hits[{j}]+1;
        if (mutant=={j} && !injected) begin
          force {net} = 'x;
          injected=1;
          $display("INJECT {j} {name}: DUT output {net} stuck-X");
          #1;
        end
        assert ({cond}) else begin
          $display("ASSERT_FAIL {j} {name} cycle=%0d actual=%h expected=%h",cycles,data,expected);
          $fatal(1,"R-025 assertion failed");
        end
      end
'''
    monitor+='      #5; clk=0; #1;\n    end\n  endtask\n'
    tasks='''
  task reset_dut;
    begin
      rst=0;req_valid=0;rsp_ready=0;
'''
    if rec: tasks+='      log_req=0;log_consume=0;\n'
    tasks+='''      #1;tick;tick;rst=1;tick;
    end
  endtask

  // Bounded waits make dead handshakes fail rather than hang a regression.
  task wait_ready;
    begin
      wait_count=0;
      while (!ready && wait_count<8) begin tick;wait_count=wait_count+1;end
      if (!ready) $fatal(1,"request timeout");
    end
  endtask
  task drain_write;
    begin
      req_valid=0;
      // Exercise long response stalls with a changing invalid input payload.
      repeat(3) begin req_data=~req_data;tick;end
      rsp_ready=1;tick;rsp_ready=0;tick;
    end
  endtask
'''
    if rec:
        tasks+='''  task drain_log;
    begin
      log_req=0;
      repeat(3) tick;
      log_consume=1;tick;log_consume=0;tick;
    end
  endtask
'''
    initial=f'''  initial begin
    for(integer j=0;j<{n};j=j+1) hits[j]=0;
'''
    for j,p in enumerate(props):
        clause='5.3' if j<18 else {'sel':'5.5.7/9.2','supervisor':'5.5.8/9.2','rec':'5.5.10/9.2'}[blk]
        initial+=f'    assertion_name[{j}]="{p[0]}";assertion_clause[{j}]="spec {clause}";\n'
    initial+='''    if ($value$plusargs("MUTANT=%d",mutant)) begin end
    $readmemh("vectors.mem",vectors);
    reset_dut;
'''
    if not rec:
        initial+=f'''    for(integer j=0;j<N;j=j+1) begin
      wait_ready;
      req_data=vectors[j][{iw+ow-1}:{ow}];expected=vectors[j][{ow-1}:0];
      req_valid=1;rsp_ready=0;tick;
      drain_write;
    end
'''
    else:
        initial+='''    if (DEPTH==4) begin
      for(integer j=0;j<N;j=j+1) begin
        {do_reset,op,event_data,event_lost,log_idx,log_expected}=vectors[j];
        if(do_reset) reset_dut;
        case(op)
          2'd0: begin
            wait_ready; req_data=event_data;expected=event_lost;req_valid=1;tick;
            drain_write;
          end
          2'd1: begin
            log_req=1;tick;drain_log;
          end
          2'd2: begin
            wait_ready;req_data=event_data;expected=event_lost;
            req_valid=1;log_req=1;tick;
            req_valid=0;log_req=0;
            // Writes must complete while the independent log response stays stalled.
            drain_write;drain_log;
          end
          2'd3: begin
            // Verification-only deposit avoids four billion writes for saturation.
            dut.reg_lost=event_lost;
            #1;
          end
          default: $fatal(1,"bad operation");
        endcase
      end
      // Hold an indexed snapshot and append a new event while it remains stalled.
      log_idx=0;log_req=1;tick;log_req=0;
      wait_ready;req_data={1'b1,3'd0,1052'd0};expected=0;req_valid=1;tick;
      drain_write;drain_log;
    end else begin
      // Independent non-power-of-two/depth boundary test, preserving oldest order.
      for(integer k=0;k<DEPTH+3;k=k+1) begin
        depth_event={1'b1,3'd1,7'd0,192'd0,64'(k),789'd0};
        wait_ready;req_data=depth_event;expected=(k<DEPTH)?0:k-DEPTH+1;
        req_valid=1;tick;drain_write;
      end
      for(integer k=0;k<DEPTH;k=k+1) begin
        log_idx=10'(k);log_expected={1'b1,3'd1,7'd0,192'd0,64'(k+3),789'd0};
        log_req=1;tick;drain_log;
      end
    end
'''
    # Exercise reset mid-response, including held read snapshot for B10.
    initial+='''    wait_ready;req_data=0;expected=0;
'''
    # do not accept request with wrong expected: use last known req/expected
    if rec: initial+='    req_data={1\'b1,3\'d0,1052\'d0};expected=(DEPTH==4)?0:4;\n'
    elif blk=='sel': initial+="    req_data=16'hffff;expected=16'h0001;\n"
    else: initial+="    req_data=44'd0;expected=8'h87;\n" # unhealthy stopped =HOLD +7
    initial+='''    req_valid=1;tick;req_valid=0;
    reset_dut;
'''
    # Consecutive requests: the next payload/valid is held through stall and consumption.
    initial+='''    // Spec5.3: hold the second request until ready after response drain.
    wait_ready;
'''
    if rec: initial+="    req_data={1'b1,3'd0,1052'd0};expected=0;\n"
    elif blk=='sel': initial+="    req_data=16'hffff;expected=16'h0001;\n"
    else: initial+="    req_data=44'd0;expected=8'h87;\n"
    initial+='    req_valid=1;tick;\n'
    if rec: initial+="    req_data={1'b1,3'd0,1052'd0};expected=(DEPTH==1)?1:0;\n"
    elif blk=='sel': initial+="    req_data=16'h8888;expected=16'h0f02;\n"
    else: initial+="    req_data={3'd0,2'd0,1'b0,1'b1,32'd1,1'b0,1'b0,1'b1,1'b0,1'b1};expected=8'ha8;\n"
    initial+='''    repeat(3) tick;
    rsp_ready=1;tick;rsp_ready=0;
    // Valid and the second payload remain unchanged until this acceptance.
    tick;drain_write;
'''
    # rec additional depth may not hit saturation and invalid index cases; subset counts explicitly
    initial+=f'''    for(integer j=0;j<{n};j=j+1) begin
      $display("ASSERT_HITS %0d %s %s hits=%0d",j,assertion_name[j],assertion_clause[j],hits[j]);
'''
    if rec: initial+='      if (DEPTH==4 && hits[j]==0) $fatal(1,"R-025 assertion never exercised: %0d",j);\n'
    else: initial+='      if (hits[j]==0) $fatal(1,"R-025 assertion never exercised: %0d",j);\n'
    initial+='''    end
    if(mutant>=0) $fatal(1,"mutant survived: %0d",mutant);
'''
    if rec:
        initial+=f'''    if(DEPTH==4) begin
      $display("PASS rec: golden=%0d/%0d rows=%0d assertions={n} requests=%0d responses=%0d cycles=%0d",GOLDEN,GOLDEN,N,requests,responses,cycles);
      $display("assertion failures: 0, assertions never exercised: 0");
    end else begin
      $display("PASS rec supplementary depth=%0d: %0d boundary writes, %0d indexed reads",DEPTH,DEPTH+3,DEPTH);
      $display("Supplementary assertion activity is a subset; full activity checked at depth=4.");
    end
'''
    else:
        initial+=f'''    $display("PASS {blk}: golden=%0d/%0d rows=%0d assertions={n} requests=%0d responses=%0d cycles=%0d",GOLDEN,GOLDEN,N,requests,responses,cycles);
    $display("assertion failures: 0, assertions never exercised: 0");
'''
    initial+='''
    $finish;
  end
  initial begin #100000000; $fatal(1,"watchdog timeout");end
endmodule
'''
    (BASE/blk/f'tb_m_tsmx_{blk}.sv').write_text(declarations+monitor+tasks+initial,encoding='ascii')
    (BASE/blk/'assertions.json').write_text(json.dumps([dict(id=i,name=p[0],clause='5.3' if i<18 else {'sel':'5.5.7 / 9.2','supervisor':'5.5.8 / 9.2','rec':'5.5.10 / 9.2'}[blk],injected_net=p[3]) for i,p in enumerate(props)],indent=2)+'\n')

if __name__=='__main__':
    for args in [('sel',16,16),('supervisor',44,8),('rec',1056,32)]: make(*args)
