"""Spec10.2/9.2: top orchestration against unmodified golden; accepted leaves reused.
All output bits meaningful to each helper operation are compared. No leaf is edited.
"""
import hashlib, random, subprocess, sys, zlib
from dataclasses import replace
from gen_sequences import HERE, ROOT, g, record, cat


def main():
    rng=random.Random(0x11B)
    math=[]; hashes=[]
    for n in range(80):
        e=g.Ego(0,rng.randrange(-1000000,1000000),rng.randrange(10000001),
                -rng.randrange(8000001),rng.randrange(6000000,100000001),rng.randrange(10000001))
        delay=rng.choice([0,1,19999,20000,39999,40000,100000,379999])
        p=g.Plan(n+1,e,0,0,e.x,e.v,e.a,tail=n%16)
        world=tuple(g.Motion(e.x+side*rng.randrange(6000000,90000000),rng.randrange(10000001),
                      -rng.randrange(8000001),4800000,rng.choice([0,20000,50000,100000]),
                      -rng.randrange(4000001)) for side in (-1,1))
        rear=rng.choice([285000,285001,1<<30])
        for op in range(5):
            ok=1; outworld=0; bridge=0; pose=0
            if op==0: ok=g.reaction_safe(e,rear)
            elif op in (1,4):
                if op==1: out=g.propagated_objects(world,delay,e.x)
                else:
                    out=[]
                    for o in world:
                        h=min(delay,o.event);x,v=g.advance(o.x,o.v,o.a,h)
                        x,v=g.advance(x,v,o.after_a,delay-h)
                        out.append(replace(o,x=x,v=v,event=max(0,o.event-delay)))
                outworld=record(g.pack_world(tuple(out)),8200)
            elif op==2:
                xl,vl=g.advance(e.x,e.v,e.a,delay)
                xh,vh=g.advance(e.x,e.v,e.a,delay,True)
                rows=((0,e.x,e.x,e.v,e.v,e.a,0),(delay,xl,xh,vl,vh,e.a,0))
                bridge=cat([(record(g.pack_row(row),352),352) for row in rows])
            else:
                x,v=g.phase_state(p,delay);pose=cat([(x,64),(v,32)])
            math.append(cat([(op,3),(record(g.pack_ego(e),256),256),
                (record(g.pack_world(world),8200),8200),(delay,32),
                (record(g.pack_plan(p),560),560),(rear,32),(ok,1),
                (outworld,8200),(bridge,704),(pose,96)]))
        # Typed packed input is serialized by the owned helper; codec checks exact bytes.
        hw=world*(n%17)
        c=g.certify(p,500000,hw)
        payloads=[g.pack_packet_body(p),g.pack_ego(e),g.pack_plan(p),
                  g.pack_context(hw),g.pack_certificate(c,include_seal=False)]
        for op,data in enumerate(payloads):
            assert len(data)<=1052
            expected=(zlib.crc32(data)<<256) if op==0 else int.from_bytes(hashlib.sha256(data).digest(),'big')
            hashes.append(cat([(op,8),(len(data),11),
                               (int.from_bytes(data.ljust(1052,b'\0'),'big'),8416),(expected,289)]))
    (HERE/'helper_math.mem').write_text(''.join(f'{x:04521x}\n' for x in math))
    (HERE/'helper_hash.mem').write_text(''.join(f'{x:02181x}\n' for x in hashes))
    tb='''`timescale 1ns/1ps
module tb_probe_helpers;
logic clk=0,rst=0,qv=0,qr,sv,ok;
logic [2:0] op; logic [255:0] ego;logic [8199:0] world,ow,ew;
logic [31:0] delay,rear;logic [559:0] plan;logic eok;
logic [703:0] bridge,eb;logic [95:0] pose,ep;
logic [18083:0] jobs[0:399];integer n,c;
always #5 clk=~clk;
m_tsmx_math dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_op(op),
.i_ego(ego),.i_world(world),.i_delay(delay),.i_plan(plan),.i_rear(rear),
.o_req_ready(qr),.o_rsp_valid(sv),.o_ok(ok),.o_world(ow),.o_bridge(bridge),.o_pose(pose));
initial begin
$readmemh("helper_math.mem",jobs);repeat(4)@(negedge clk);rst=1;
for(n=0;n<400;n=n+1)begin
{op,ego,world,delay,plan,rear,eok,ew,eb,ep}=jobs[n];
while(!qr)@(negedge clk);qv=1;@(negedge clk);qv=0;c=0;
while(!sv)begin @(negedge clk);c=c+1;if(c>100000)$fatal(1,"helper hang %0d",n);end
if(ok!==eok || ((op==1 || op==4) && ow!==ew) || (op==2 && bridge!==eb)
 || (op==3 && pose!==ep))$fatal(1,"helper mismatch job=%0d op=%0d pose=%h expected=%h",n,op,pose,ep);
@(negedge clk);
end
$display("PASS helper math jobs=400");$finish;
end
endmodule
'''
    (HERE/'tb_probe_helpers.sv').write_text(tb)
    files=[ROOT/'rtl/arith/m_tsmx_arith_div.sv',ROOT/'rtl/arith/m_tsmx_arith.sv',
           ROOT/'rtl/top/m_tsmx_math.sv',HERE/'tb_probe_helpers.sv']
    for cmd,log in [(['iverilog','-g2012','-s','tb_probe_helpers','-o',str(HERE/'helpers.vvp')]+list(map(str,files)),
                     'helpers_compile.log'),(['vvp','-i',str(HERE/'helpers.vvp')],'helpers_sim.log')]:
        with (HERE/log).open('w') as f:
            f.write('COMMAND: '+subprocess.list2cmdline(cmd)+'\n');f.flush()
            p=subprocess.run(cmd,cwd=HERE,stdout=f,stderr=f)
        if p.returncode: print((HERE/log).read_text()[-2000:]);return p.returncode
    print((HERE/'helpers_sim.log').read_text())
    ht='''`timescale 1ns/1ps
module tb_probe_hash;
logic clk=0,rst=0,qv=0,qr,sv;logic [7:0] op;logic [10:0] len;
logic [8415:0] data;logic [288:0] result,expected;
logic [8723:0] jobs[0:399];integer n,c;
always #5 clk=~clk;
m_tsmx_hash dut(.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(qv),.i_op(op),
.i_len(len),.i_data(data),.o_req_ready(qr),.o_rsp_valid(sv),.o_rsp_data(result));
initial begin
$readmemh("helper_hash.mem",jobs);repeat(4)@(negedge clk);rst=1;
for(n=0;n<400;n=n+1)begin
{op,len,data,expected}=jobs[n];while(!qr)@(negedge clk);
qv=1;@(negedge clk);qv=0;c=0;
while(!sv)begin @(negedge clk);c=c+1;if(c>5000)$fatal(1,"hash hang %0d",n);end
if(result!==expected)$fatal(1,"hash mismatch job=%0d op=%0d actual=%h expected=%h",n,op,result,expected);
@(negedge clk);
end
$display("PASS helper hash jobs=400");$finish;
end
endmodule
'''
    (HERE/'tb_probe_hash.sv').write_text(ht)
    files=[ROOT/'rtl'/x for x in (ROOT/'rtl/filelist_R3.f').read_text().splitlines()
           if x and not x.startswith('//')]+[ROOT/'rtl/top/m_tsmx_hash.sv',HERE/'tb_probe_hash.sv']
    for cmd,log in [(['iverilog','-g2012','-s','tb_probe_hash','-o',str(HERE/'hash.vvp')]+list(map(str,files)),
                     'hash_compile.log'),(['vvp','-i',str(HERE/'hash.vvp')],'hash_sim.log')]:
        with (HERE/log).open('w') as f:
            f.write('COMMAND: '+subprocess.list2cmdline(cmd)+'\n');f.flush()
            p=subprocess.run(cmd,cwd=HERE,stdout=f,stderr=f)
        if p.returncode: print((HERE/log).read_text()[-2000:]);return p.returncode
    print((HERE/'hash_sim.log').read_text())
    return 0

if __name__=='__main__':sys.exit(main())
