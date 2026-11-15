"""W10b3: recorded planner outputs feed firmware; TSM expectations use golden only."""
import sys
sys.dont_write_bytecode = True
import argparse, hashlib, json, struct
from pathlib import Path
from dataclasses import replace, asdict

HERE = Path(__file__).resolve().parent
HW = HERE.parent
BASE = HW.parents[1]
sys.path[:0] = [str(HW/'golden'), str(HW/'tb/integ'), str(HW/'eval_nuscenes/w10a')]
import packetizer_v2 as fw
import gen_sequences as enc
g = fw.g

def words(path):
    return [int(w,16) for w in path.read_text().split()]

def floats(ws):
    return [struct.unpack('>f', w.to_bytes(4,'big'))[0] for w in ws]

def packed(s,d,reset):
    ns,o = g.tsmx_cycle(s,d)
    fields = [(reset,1),(enc.request(d),44673),(enc.record(g.pack_top_rsp(o),38),38),
              (enc.command(ns,o,d),1897),(enc.record(g.pack_ingress(ns.ingress),332),332),
              (g.MODES.index(ns.mode),3),(ns.good,2),(ns.fault_latched,1),
              (bool(ns.pending),1),(bool(ns.backup),1),(ns.events_lost,32),
              (enc.record(g.pack_event(ns.events[-1]),1056),1056)]
    return ns,o,enc.cat(fields)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--planner-vec',type=Path,default=BASE/'tb/e2e/vec')
    ap.add_argument('--from-reference',action='store_true',help='Documentation only: old reference-waypoint packets')
    args=ap.parse_args()
    src=HW/'eval_nuscenes/w9b/cosim_0103.json'
    old=json.loads(src.read_text())
    assert old['frames']==35 and old['jobs']==207
    fw.ENCODING='E2'
    s=g.Supervisor(); frame=0; records=[]; vectors=[]; frames=[]; hashes={}
    mutant=None; saved_packet_differences=[]; recorded_words=[]
    for j,row in enumerate(old['jobs_meta']):
        d=enc.inputs(row['input'])
        if row['kind']=='admission':
            path=args.planner_vec/f's{frame:02d}_wp.hex'
            refws=words(path); assert len(refws)==8
            dump=BASE/f'tb/e2e/results/final_35/wp_rtl_s{frame:02d}.txt'
            dumpwords=words(dump)
            assert len(dumpwords)==9 and dumpwords[8]==0, dump
            rtlws=dumpwords[:8]; recorded_words.extend(rtlws)
            assert max(abs(a-b) for a,b in zip(floats(refws),floats(rtlws)))<=0.000021
            ws=refws if args.from_reference else rtlws
            wp=floats(ws)[::2]
            p0=d['pkt'].plan
            # E2 x/v depend only on the preserved measured snapshot; offset cancels.
            x,v,a=fw.encode_state(wp,p0.snapshot,0,'E2')
            p=replace(p0,x=fw.fixed(x),v=fw.fixed(v),a=fw.fixed(a))
            d['pkt']=g.packet(p,(p.seq,)*3)
            if d.get('cert') is not None:
                d['cert']=g.certify(p,d['cert'].t_e,d['objects'],d['lane'])
            assert g.pack_packet(d['pkt']) == g.pack_packet(g.packet(p,(p.seq,)*3))
            hashes[str(path.relative_to(BASE))]=hashlib.sha256(path.read_bytes()).hexdigest()
            hashes[str(dump.relative_to(BASE))]=hashlib.sha256(dump.read_bytes()).hexdigest()
            frames.append(dict(frame=frame,job=j,token=row['token'],firmware_words=ws,
                               planner_reference_words=refws,recorded_rtl_words=rtlws,
                               packet=asdict(d['pkt'])))
            refa=fw.fixed(fw.encode_state(floats(refws)[::2],p.snapshot,0,'E2')[2])
            rtla=fw.fixed(fw.encode_state(floats(rtlws)[::2],p.snapshot,0,'E2')[2])
            if refa != rtla: saved_packet_differences.append(frame)
            fi=frame; frame+=1
        else:
            fi=-1
            # Same W9b service timestamps, but track the command from this E2 history.
            if executor and 0<=executor.v<=10*g.S and -8*g.S<=executor.a<=2*g.S:
                x,v=g.phase_state(executor,d['now'])
                a=executor.a if d['now']-executor.apply<g.DT else g.profile_a(executor.tail,d['now']-executor.apply-g.DT,executor.a)
                ahead=[o for o in d['objects'] if o.x>x]
                lead=min(ahead,key=lambda o:o.x-o.length) if ahead else None
                d['ego']=g.Ego(d['now'],x,v,a,lead.x-lead.length+4800000 if lead else 9999*g.S,lead.v if lead else 0)
        ns,o,bits=packed(s,d,j==0)
        if fi==7:
            # A single binary32 word (+/-4096 m) forces the opposite E2 acceleration clamp.
            mw=0x45800000 if d['pkt'].plan.a<0 else 0xc5800000
            wmut=list(frames[-1]['firmware_words']); wmut[0]=mw
            ma=fw.fixed(fw.encode_state(floats(wmut)[::2],d['pkt'].plan.snapshot,0,'E2')[2])
            md=dict(d,pkt=g.packet(replace(d['pkt'].plan,a=ma),(d['pkt'].plan.seq,)*3))
            _,mo,mb=packed(s,md,j==0)
            mutant=dict(frame=fi,job=j,word=0,value=mw,
                        expected_accept=o['accept'],mutated_accept=mo['accept'],
                        expected_reason=o['reason'],mutated_reason=mo['reason'],
                        packet_changed=g.pack_packet(md['pkt'])!=g.pack_packet(d['pkt']),
                        golden_output_changed=(mb & ((1<<3363)-1)) != (bits & ((1<<3363)-1)))
            assert mutant['packet_changed']
        vectors.append(f'{bits:012010x}\n')
        serialized={k:(asdict(v) if hasattr(v,'__dataclass_fields__') else
                    [asdict(z) for z in v] if k=='objects' else v) for k,v in d.items()}
        records.append(dict(job=j,frame=fi,now=d['now'],kind=row['kind'],input=serialized,response=o))
        s=ns
        if s.pending: executor=s.pending[1]
        elif s.mode=='L1' and s.backup: executor=s.backup[0]
        else:
            e=d['ego']; cid=o['candidate'] if s.mode=='L2' else 15
            executor=g.Plan(0,e,d['now'],d['now'],e.x,e.v,e.a,tail=cid)
    assert frame==35 and mutant is not None
    # Hash every external planner memory input used by the driver. Reuse the
    # established payload files rather than copying tens of MB into this harness.
    planner_inputs=list(args.planner_vec.glob('ddr_*.hex'))
    planner_inputs += [args.planner_vec/f's{i:02d}_{kind}.hex' for i in range(35) for kind in ('wm','cls')]
    for path in planner_inputs:
        hashes[str(path.relative_to(BASE))]=hashlib.sha256(path.read_bytes()).hexdigest()
    (HERE/'vectors.mem').write_text(''.join(vectors),encoding='ascii')
    (HERE/'frames.mem').write_text(''.join(f'{r["frame"]+1:08x}\n' for r in records),encoding='ascii')
    (HERE/'recorded_wp.mem').write_text(''.join(f'{w:08x}\n' for w in recorded_words),encoding='ascii')
    (HERE/'firmware_fit.svh').write_text(''.join(f'localparam real FIT_A{k}={fw._fit[1,k]:.17g};\n' for k in range(4)),encoding='ascii')
    (HERE/'vector_count.svh').write_text(f'localparam integer JOBS={len(vectors)}, VW=48037;\nlocalparam integer MUTANT_FRAME={mutant["frame"]};\nlocalparam logic [31:0] MUTANT_WORD=32\'h{mutant["value"]:08x};\n',encoding='ascii')
    manifest=dict(encoding='E2',waypoint_source='reference_documentation_only' if args.from_reference else 'recorded_final_35',frames=frames,jobs=records,mutant=mutant,
                  reference_sha256=hashes,source_manifest_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),
                  diagnostic_saved_rtl_packet_differences=saved_packet_differences,
                  cycle_oracle='tsmx_cycle is semantic, has no hardware cycle count; measure CSR and assert deadline')
    (HERE/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    # Portable lists: relative paths are interpreted from this harness directory.
    planner=(BASE/'reports/unit/e2e_files_f.txt').read_text().split()
    planner=[p for p in planner if not p.startswith('tb/')]
    files=[BASE/'rtl/include/planning_pkg.sv']+[BASE/p for p in planner]
    import os
    files += [HW/'rtl'/p for p in (HW/'rtl/filelist_top.f').read_text().splitlines() if p and not p.startswith('//')]
    files += [HERE/'e2e_planner_driver.sv',HERE/'e2e_tsm_driver.sv',HERE/'tb_e2e_traj_tsm.sv']
    (HERE/'sources.f').write_text('\n'.join(os.path.relpath(p,HERE).replace('\\','/') for p in files)+'\n',encoding='ascii')
    print(json.dumps(dict(frames=frame,jobs=len(vectors),mutant=mutant,saved_rtl_packet_differences=saved_packet_differences)))

if __name__=='__main__': main()
