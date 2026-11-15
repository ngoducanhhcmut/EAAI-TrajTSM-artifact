"""W4b RTL envelopes and reproducible native-Icarus calibration. No fitted constants."""
from pathlib import Path
import argparse, json, re, shutil, subprocess, sys
sys.dont_write_bytecode = True
OUT = Path(__file__).resolve().parent
ROOT = OUT.parent
CAL = OUT / 'cal'

# Public service envelopes include consumption/rearm. See WCET_v2.md for proofs.
A = {0:4,1:87,2:184,3:202,4:2803,5:4,6:215,7:379,8:4}
SU, INFL, GAP = 24, 27, 770

def root_extra(h):
    return (max(1,h)-1).bit_length()*101+202  # arith:808-821

def generator(rows):
    return 4+GAP*rows+2*root_extra(100000)  # mrmgen:192-268

def cell(objects):
    return 30+(SU+4)*objects  # geom:330-400, four SUs in parallel

def geometry(rows,objects):
    return 8+2*objects+max(0,rows-1)*cell(objects)+(SU+2)*objects

def pair(rows,objects):
    # Max-plus recurrence: head + C*max(generator period, cell work).
    # Stop-search bursts and event splits are charged separately, once each.
    return (40+2*objects+GAP+2*root_extra(100000)
            +max(0,rows-1)*max(GAP,cell(objects))+(SU+2)*objects)

def sweep(rows,objects):
    return 2+8*(4+pair(rows,objects))  # sweep:104-145; P=G=2

def hash_cost(length):
    # Serializing SHA and feed is safe even though the two banks overlap them.
    return 4+(length+3)//4+32+66*((length+9+63)//64)

def bound(rows=93,objects=32, reachable_history=True):
    # Certificate checks bound replay to phase<380000 in reachable accepted history.
    steps=19 if reachable_history else 640
    replay=4+(steps+1)+steps*(4+A[7]+root_extra(20000))
    health=(1024+16+generator(33)+2*(33+4+geometry(33,1)))
    terms={
        'fallback_parallel_duplicate':max(sweep(rows,objects),6+pair(rows,objects)),
        'tail':sweep(rows,objects),
        'nominal':6+pair(rows,1),
        'bridge_geometry':6+geometry(2,objects),
        'reaction':4+2*A[3]+2*A[4],
        'nominal_propagation':4+32+(1+2*A[3]),
        'world_propagation':4+32+objects*(1+2*A[3]),
        'bridge_math':4+2*A[3],
        'replay':replay,
        'health_lane':health,
        'hashes':sum(hash_cost(n) for n in [86,1049,32,70,120,70,120]),
        'ingress':2+A[8], 'certificate':3*(1+A[8]),
        'splice':2+16*A[3], 'selection':4,
        'supervisor_recorder_arbiter':6, 'engine_glue':152,
    }
    if not reachable_history:
        # Diagnostic bound if the accepted-history invariant is deliberately dropped.
        terms['late_hash_retry']=sweep(rows,objects)+replay+5+2+2
    return terms

def check_measurements(B):
    paths=sorted((ROOT/'tb/integ/vl_claude_r17_a8_apos').glob('*.txt'))
    paths.append(ROOT/'tb/board/vl_stream_r3/reg300_board.txt')
    records=[]; coverage={}; unmatched=[]
    for p in paths:
        jobs={};timing={}
        for line_no,line in enumerate(p.read_text().splitlines(),1):
            m=re.search(r'JOB (\d+) PASS cycles=(\d+)',line)
            if m:
                key=int(m[1])
                if key in jobs: raise ValueError(f'duplicate JOB {p}:{line_no}')
                jobs[key]=(int(m[2]),line_no)
            m=re.search(r'TIMING job=(\d+) fallback=([0-9a-fA-F]+) tail=([0-9a-fA-F]+) max_rows=(\d+) stream_hits=(\d+) objects=(\d+)',line)
            if m:
                key=int(m[1])
                if key in timing: raise ValueError(f'duplicate TIMING {p}:{line_no}')
                timing[key]=dict(fallback=m[2],tail=m[3],rows=int(m[4]),objects=int(m[6]),line=line_no)
                assert 0<=int(m[4])<=93 and 0<=int(m[6])<=32,(p,line_no,'outside bound domain')
        coverage[str(p.relative_to(ROOT))]=dict(jobs=len(jobs),timing=len(timing))
        for key in jobs.keys() | timing.keys():
            if key not in jobs or key not in timing: unmatched.append([str(p),key])
        for key,(cycles,line_no) in jobs.items():
            assert cycles<=B,(p,key,cycles,B)
            records.append(dict(file=str(p.relative_to(ROOT)),job=key,line=line_no,cycles=cycles,
                                timing=timing.get(key),bound=B,slack=B-cycles))
    assert not unmatched,unmatched
    assert records
    return records,coverage

def calibration_summary():
    result={}
    for unit in ['arith','mrmgen','geom','geom_su','sweep']:
        path=CAL/unit/'simulation.log'
        if not path.exists(): result[unit]={'status':'UNRESOLVED'};continue
        text=path.read_text()
        result[unit]={'pass':('PASS' in text if unit!='sweep' else 'CAL_PAIR' in text),
            'summary':[l for l in text.splitlines() if any(k in l for k in ['LATENCY','ACTOR_II','PASS','CAL_PAIR'])]}
        for label,pattern in [('row_gap',r'CAL_ROW index=\d+ gap=(\d+)'),
                              ('actor',r'CAL_ACTOR cycles=(\d+)'),('cell',r'CAL_CELL cycles=(\d+)')]:
            values=[int(x) for x in re.findall(pattern,text)]
            if values: result[unit][label+'_max']=max(values)
        if unit=='geom_su':
            result[unit]['max_by_mode']={str(m):max(map(int,re.findall(fr'CAL_SU mode={m} latency=(\d+)',text))) for m in [0,1]}
    return result

def report():
    terms=bound(); B=sum(terms.values())
    jobs,coverage=check_measurements(B)
    result=dict(bound=B,ms_100MHz=B/100000,ms_187_5MHz=B/187500,
        tightness=947256/B,target_met=B<=1875000,terms=terms,
        external_command_stall='add W_cmd; B assumes W_cmd=0',
        arbitrary_internal_state_diagnostic=sum(bound(reachable_history=False).values()),
        jobs_checked=len(jobs),worst_measured=max(j['cycles'] for j in jobs),
        coverage=coverage,calibration=calibration_summary(),jobs=jobs)
    CAL.mkdir(exist_ok=True)
    (CAL/'results_v2.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='jobs'},indent=2))
    return result

def calibrate_pair():
    """Adapt the unit mrmgen parameter harness to its paired streaming caller."""
    dst=CAL/'sweep'
    dst.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'tb/unit/mrmgen/tb_mrmgen_param.sv',dst/'original_tb_mrmgen_param.sv')
    code='''`timescale 1ns/1ps
module tb_pair;
reg clk=0,rst=0,req=0;
reg [8199:0] world=0;
wire ready,valid;
wire [15:0] mask;
integer cyc=0,beginc=0,basec=0;
m_tsmx_sweep #(.PARA_G(2),.PARA_P(2)) dut(
.i_clk_core(clk),.i_rst_n_core(rst),.i_req_valid(req),
.i_pose({64'd0,32'd10000000,32'd2000000}),.i_epoch(32'd0),.i_world(world),
.i_lane({64'hffffffffffe488c0,64'd1800000,64'd0,64'd950000,64'd50000,64'd500000}),
.i_kind(2'd0),.i_bridge(704'd0),.o_req_ready(ready),.o_rsp_valid(valid),.o_rsp_data(mask));
always #5 clk=~clk;
always @(posedge clk) begin
cyc=cyc+1;
if(rst && ready && req) beginc=cyc;
if(rst && dut.reg_base==2) begin
$display("CAL_PAIR candidates=0,1 rows_max=93 objects=32 cycles=%0d",cyc-beginc);
$finish;
end
end
initial begin
rst=1;#1;rst=0;
world[8199:8192]=32;
for(integer k=0;k<32;k=k+1)
world[8191-256*k -:256]={64'd1000000000,32'd0,32'd0,64'd4800000,32'd0,32'd0};
repeat(4) @(negedge clk);rst=1;
while(!ready) @(negedge clk);
req=1;@(negedge clk);req=0;
end
initial begin #20000000; $fatal(1,"pair timeout"); end
endmodule
'''
    target=dst/'tb_pair.sv';target.write_text(code)
    sweep=CAL/'icarus_rtl/m_tsmx_sweep.sv'
    sweep.write_text((ROOT/'rtl/top/m_tsmx_sweep.sv').read_text().replace('always_comb','always @*'))
    sources=[str(p) for p in (CAL/'icarus_rtl').glob('*.sv')]
    cp=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_pair','-o',str(dst/'sim.vvp'),str(target),*sources],capture_output=True,text=True)
    (dst/'compile.log').write_text(cp.stdout+cp.stderr)
    if cp.returncode: raise RuntimeError('pair compile')
    with (dst/'simulation.log').open('w') as f:
        cp=subprocess.run(['C:/iverilog/bin/vvp.exe',str(dst/'sim.vvp')],cwd=dst,stdout=f,stderr=subprocess.STDOUT)
    if cp.returncode: raise RuntimeError('pair simulation')
    print((dst/'simulation.log').read_text())

def calibrate(only=None):
    CAL.mkdir(exist_ok=True)
    sources = []
    port = CAL/'icarus_rtl'
    port.mkdir(exist_ok=True)
    for d in ['arith','geom','mrmgen']:
        for p in (ROOT/'rtl'/d).glob('*.sv'):
            code=p.read_text().replace('always_comb', 'always @*')
            code=code.replace('w_fsm_ctrl_nxt_state=reg_pvalid ? ENUM_ST_W_D0 : ENUM_ST_W_NEXT;',
                'if(reg_pvalid) w_fsm_ctrl_nxt_state=ENUM_ST_W_D0; else w_fsm_ctrl_nxt_state=ENUM_ST_W_NEXT;')
            target=port/p.name
            target.write_text(code)
            sources.append(str(target))
    for unit in ['arith', 'mrmgen', 'geom', 'geom_su']:
        if only and unit != only: continue
        src = ROOT/'tb/unit'/unit
        dst = CAL/unit
        dst.mkdir(exist_ok=True)
        for p in src.iterdir():
            if p.suffix in ['.mem', '.svh']:
                shutil.copy2(p, dst/p.name)
        # Deterministic calibration subset; preserve original row offsets.
        if unit == 'arith':
            lines=(src/'vectors.mem').read_text().splitlines()
            groups={i:[] for i in range(9)}
            for line in lines:
                value=int(line,16); groups.setdefault((value >> (641+1920)) & 255,[]).append(line)
            selected=[]
            for group in groups.values():
                if group:
                    selected.extend(group[i] for i in sorted({0,len(group)-1,*[j*(len(group)-1)//15 for j in range(16)]}))
            (dst/'vectors.mem').write_text('\n'.join(selected)+'\n')
            (dst/'vectors_meta.svh').write_text(f'localparam integer N={len(selected)};\n')
        elif unit in ['mrmgen','geom']:
            lines=(src/'jobs.mem').read_text().splitlines()
            ids=sorted({0,len(lines)-1,*[j*(len(lines)-1)//15 for j in range(16)]})
            # Include largest endpoint-count workloads as well as broad sampling.
            ids=sorted(set(ids+sorted(range(len(lines)),key=lambda i:int(lines[i],16)&(0xffffffff if unit=='mrmgen' else 255),reverse=True)[:8]))
            (dst/'jobs.mem').write_text('\n'.join(lines[i] for i in ids)+'\n')
            meta=(src/'vectors_meta.svh').read_text()
            (dst/'vectors_meta.svh').write_text(re.sub(r'N=\d+',f'N={len(ids)}',meta))
            (dst/'selected_indices.json').write_text(json.dumps(ids))
        bench = src/f'tb_m_tsmx_{unit}.sv' 
        code = bench.read_text()
        if unit in ['mrmgen','geom','geom_su']:
            # A real reset edge before the copied four-state reset assertions.
            code=code.replace('$readmemh(', 'rst=1; #1; rst=0; #1; $readmemh(',1)
        # Independent edge counter, in addition to the benches' existing counters.
        monitor = '''
  integer cal_cycle=0, cal_begin=0;
  reg cal_pending=0;
  always @(posedge clk) begin
    cal_cycle=cal_cycle+1;
    if (!rst) cal_pending=0;
    else begin
      if (dut.i_req_valid && dut.o_req_ready) begin cal_begin=cal_cycle; cal_pending=1; end
      if (dut.o_rsp_valid && cal_pending) begin
        $display("CAL job_cycles=%0d",cal_cycle-cal_begin); cal_pending=0;
      end
    end
  end
'''
        if unit == 'geom_su':
            monitor = monitor.replace('dut.i_req_valid && dut.o_req_ready', 'start').replace('dut.o_rsp_valid', 'done')
            code = code.replace('if (lat>maxlat)', '$display("CAL_SU mode=%0d latency=%0d",mode,lat);\n      if (lat>maxlat)')
        if unit == 'mrmgen':
            code = code.replace('gap=cycle-last_row_at;', '$display("CAL_ROW index=%0d gap=%0d",pos,cycle-last_row_at);gap=cycle-last_row_at;')
        if unit == 'geom':
            monitor += '''
  integer cal_actor_at=0, cal_cell_at=0;
  always @(posedge clk) if(rst) begin
    if(dut.reg_fsm_ctrl_current_state==4'd5) cal_actor_at=cal_cycle;
    if(dut.reg_fsm_ctrl_current_state==4'd8)
      $display("CAL_ACTOR cycles=%0d",cal_cycle-cal_actor_at+1);
    if(dut.reg_fsm_ctrl_current_state==4'd3) cal_cell_at=cal_cycle;
    if(dut.reg_fsm_ctrl_current_state==4'd8 && dut.reg_actor+1>=dut.reg_world[8199:8192])
      $display("CAL_CELL cycles=%0d",cal_cycle-cal_cell_at+1);
  end
'''
        code = code.replace('endmodule', monitor+'\nendmodule')
        target = dst/bench.name
        target.write_text(code)
        args = ['C:/iverilog/bin/iverilog.exe','-g2012','-s',f'tb_m_tsmx_{unit}','-I',str(dst),'-o',str(dst/'sim.vvp'),str(target),*sources]
        cp = subprocess.run(args,capture_output=True,text=True)
        (dst/'compile.log').write_text(cp.stdout+cp.stderr)
        if cp.returncode: raise RuntimeError(f'{unit}: compile failed')
        args = ['C:/iverilog/bin/vvp.exe',str(dst/'sim.vvp')]
        if unit in ['mrmgen','geom']: args += ['+NOSTALL=1']
        with (dst/'simulation.log').open('w') as f:
            cp = subprocess.run(args,cwd=dst,stdout=f,stderr=subprocess.STDOUT)
        print(unit, 'exit',cp.returncode,flush=True)
        if cp.returncode: raise RuntimeError(f'{unit}: simulation failed')

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--calibrate',action='store_true')
    parser.add_argument('--unit', choices=['arith','mrmgen','geom','geom_su'])
    parser.add_argument('--pair',action='store_true')
    args=parser.parse_args()
    if args.calibrate: calibrate(args.unit)
    if args.pair: calibrate_pair()
    if not args.calibrate and not args.pair: report()


