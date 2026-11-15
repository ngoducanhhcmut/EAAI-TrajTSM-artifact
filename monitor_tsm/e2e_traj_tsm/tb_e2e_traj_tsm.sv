`timescale 1ns/1ps
module tb_e2e_traj_tsm;
  parameter integer ENCODING=2;
  `include "vector_count.svh"
  `include "firmware_fit.svh"
  e2e_planner_driver planner();
  e2e_tsm_driver tsm();
  logic [VW-1:0] vectors[0:JOBS-1];
  logic [31:0] frame_map[0:JOBS-1];
  logic [44672:0] request_ref, request_fw;
  logic [720:0] packet_ref, packet_fw;
  logic [559:0] plan_fw;
  logic [31:0] wp[0:7];
  integer frame, completed=0, packet_errors=0;
  string vecdir="./";
  bit mutate;
  // Python round(): nearest integer, ties to even, including negative values.
  function automatic longint round_even(input real r);
    longint n;
    real f;
    n=longint'($floor(r)); f=r-real'(n);
    if(f>0.5 || (f==0.5 && n[0])) n++;
    return n;
  endfunction
  function automatic longint floor_div(input longint n,input longint d);
    return n/d - ((n<0 && n%d!=0) ? 1:0);
  endfunction
  function automatic logic [31:0] packet_crc(input logic [559:0] p,input logic [127:0] ids_schema);
    logic [687:0] body;
    logic [31:0] c;
    logic [7:0] b;
    body={p,ids_schema};c=32'hffffffff;
    for(integer k=0;k<86;k++) begin
      b=body[687-8*k -:8];c=c^b;
      for(integer bitidx=0;bitidx<8;bitidx++) c=(c>>1) ^ (c[0] ? 32'hedb88320:0);
    end
    return ~c;
  endfunction
  task firmware_packet;
    longint x,v,a,dx,pv,pa;
    real alpha, raw_x,raw_v;
    logic [255:0] snap;
    plan_fw=packet_ref[719:160];snap=plan_fw[527:272];
    x=$signed(snap[223:160]);v=$signed(snap[159:128]);a=$signed(snap[127:96]);
    alpha=FIT_A0*planner.f2r(wp[0])+FIT_A1*planner.f2r(wp[2])+
          FIT_A2*planner.f2r(wp[4])+FIT_A3*planner.f2r(wp[6]);
    pa=round_even((2.0*alpha < -8.0 ? -8.0 : 2.0*alpha > 2.0 ? 2.0:2.0*alpha)*1000000.0);
    if(v>=0 && v<=20000000 && a>=-8000000 && a<=2000000) begin
      if(a<0 && 100000*(-a)>=v*1000000) dx=floor_div(v*v,-2*a);
      else dx=floor_div(20*v+a,200);
      pv=floor_div(10*v+a,10);if(pv<0) pv=0;
      x=x+dx;
    end else begin
      raw_x=real'(x)+real'(v)*0.1+0.5*real'(a)*0.1*0.1;
      raw_v=real'(v)+real'(a)*0.1;
      x=round_even(raw_x);pv=round_even(raw_v);
    end
    plan_fw[207:144]=64'(x);plan_fw[143:112]=32'(pv);plan_fw[111:80]=32'(pa);
    packet_fw={1'b1,plan_fw,packet_crc(plan_fw,packet_ref[127:0]),packet_ref[127:0]};
  endtask
  initial begin
    if(ENCODING!=2) $fatal(1,"W10a selected E2; regenerate vectors for any encoding change");
    if($value$plusargs("VECTORS=%s",vecdir)) begin end
    mutate=$test$plusargs("MUTANT_WAYPOINT");
    $readmemh({vecdir,"vectors.mem"},vectors);
    $readmemh({vecdir,"frames.mem"},frame_map);
    // Recorded planner output anchors firmware inputs; TSM oracle is golden only.
    fork planner.boot(); tsm.boot(); join
    for(integer j=0;j<JOBS;j++) begin
      request_ref=vectors[j][VW-2 -:44673];request_fw=request_ref;
      if(frame_map[j]!=0) begin
        frame=int'(frame_map[j])-1;
        if(frame!=completed) $fatal(1,"frame sequence");
        planner.run_frame(frame);completed++;
        for(integer k=0;k<8;k++) wp[k]=planner.observed_wp[k];
        // Corrupt a CSR-read waypoint after the planner's independent checks.
        if(mutate && frame==MUTANT_FRAME) begin
          wp[0]=MUTANT_WORD;$display("MUTANT_INJECTED frame=%0d word=0",frame);
        end
        packet_ref=request_ref[44384:43664];firmware_packet();
        if(packet_fw!==packet_ref) begin
          packet_errors++;
          $display("PACKET_BYTES_MISMATCH frame=%0d actual=%h expected=%h",frame,packet_fw,packet_ref);
        end
        // Always send the observed-waypoint packet, including on mismatch.
        // Certificate and expected decisions stay golden-generated.
        request_fw[44384:43664]=packet_fw;
      end
      tsm.run_job(j,vectors[j],request_fw);
    end
    if(completed!=35) $fatal(1,"missing planner frames");
    if(packet_errors!=0) $fatal(1,"exact packet checks failed: %0d",packet_errors);
    if(mutate) $fatal(1,"mutant survived");
    $display("E2E_PASS frames=35 jobs=%0d",JOBS);$finish;
  end
  // Bounded global timeout, including the planner and all bus/stream waits.
  initial begin #20000000000; $fatal(1,"E2E global timeout"); end
endmodule
