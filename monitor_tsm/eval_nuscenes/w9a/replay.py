"""W9a unchanged W7/W7B/W7C numerical functions, new RQ1 T states."""
import plans_hw as ph
from plans_hw import OUT,HERE,ROOT,np,json,os,time
import sys
import math
import pickle
import ast
from collections import Counter
sys.path[:0] = [str(HERE/'w7b')]
import run_w7 as w
import run_w7b as wb
import w7_secondary as sec
os.environ['TEMP'] = os.environ['TMP'] = str(OUT)
# Load only the selected-audit function definitions; the original module installs
# a write guard rooted in w7c, so its executable module body is not imported.
source = HERE/'w7c/run_w7c.py'
tree = ast.parse(source.read_text(encoding='utf-8'))
names = {'curve_for','with_hold','cv_check','selected_check'}
g = dict(w=w,wb=wb,np=np,TOL=1e-6)
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names],type_ignores=[]),str(source),'exec'),g)

def worker(shard,workers):
    from data.nuscenes_lite import load_nuscenes
    root = Path(json.loads((HERE/'results/manifest.json').read_text())['dataset'])
    nusc = load_nuscenes('v1.0-trainval',str(root))
    with (HERE/'annotation_categories.pkl').open('rb') as f:
        cats = pickle.load(f)
    for token,ann in nusc._sample_annotation.items():
        ann['category_name'] = cats[token]
    scenes = sorted(nusc.scene,key=lambda s:(s['name'],s['token']))
    wanted = {s['name']:s for i,s in enumerate(scenes) if i%workers == shard}
    with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        frames = [json.loads(l) for l in f]
    plans = {}
    for part in range(workers):
        with (OUT/f'full_{part}.jsonl').open(encoding='utf-8') as f:
            for line in f:
                r = json.loads(line)
                plans[r['token']] = np.asarray(r['wp'],np.float32)
    assert len(plans) == len(frames) == 29049
    by_scene = {}
    for r in frames:
        if r['odd'] and r['scene'] in wanted:
            by_scene.setdefault(r['scene'],[]).append(r)
    path = OUT/f'replay_{shard}.jsonl'
    done = set()
    if path.exists():
        done = {(r['token'],r['plan']) for r in ph.recover_records(path)}
    with path.open('a',encoding='utf-8',buffering=1) as out:
        for name,scene in wanted.items():
            assert ph.shutil.disk_usage('C:/').free >= 10_000_000_000, 'C: free space below 10 GB'
            wb.roots.clear()
            samples,pp,tt,aa,tracks = wb.scene_tracks(nusc,scene,cats)
            indices = {s['token']:i for i,s in enumerate(samples)}
            for frame in by_scene.get(name,[]):
                i = indices[frame['token']]
                axis = np.array([math.cos(aa[i]),math.sin(aa[i])])
                side = np.array([-axis[1],axis[0]])
                records,errors = w.objects_at(nusc,samples[i],pp[i],axis,side)
                assert records == frame['objects'] and errors == frame['adapter_errors']
                objects = wb.projected(tracks,pp[i],axis,side,tt[i],{o['token']:o for o in records})
                wp = plans[frame['token']]
                states = {label:d['state_si'] for label,d in frame['plans'].items()}
                states['T'] = (float(wp[0,0]),float(wp[1,0]),float((wp[1,0]-2*wp[0,0])/.25))
                # W7 U is independent of T. Check the registered generation rule.
                v = frame['v_est_mps']
                assert ('U' in states) == any(o['x']>0 for o in records)
                if 'U' in states:
                    assert states['U'] == [.5*v+.25,v+1,2.]
                for label,state in states.items():
                    if (frame['token'],label) in done:
                        continue
                    d,vector = w.evaluate_plan(state,records,errors)
                    if label != 'T':
                        assert d == frame['plans'][label], 'H/U registered replay mismatch'
                    ego = w.Ego(500000,*map(w.fixed,state),0,0)
                    cids = dict(V0=d['cid'],VA=sec.va(ego,records),VB=sec.va(ego,records,True))
                    assert sec.v0(ego,records) == cids['V0']
                    o2 = wb.oracle2(state,objects,float(tt[-1]-tt[i]))
                    accepted = {}
                    for variant in ('V0','VA'):
                        cid = cids[variant]
                        if cid == 15:
                            continue
                        tr,propagated = wb.golden_objects(ego,records,cid,variant)
                        geom = w.b3_geom(tr,propagated,w.LANE)
                        assert geom.accept
                        horizon = tr.rows[-1][0]-tr.rows[0][0]
                        raw = sec.raw_objects(records) if variant == 'V0' else sec.reduce_neg(records,horizon,False)
                        curve = g['curve_for'](state,cid)
                        encoded = [ego.x/1e6,ego.v/1e6,ego.a/1e6]
                        cv = g['cv_check'](g['curve_for'](encoded,cid),raw,[o['token'] for o in records])
                        orig = g['cv_check'](curve,raw,[o['token'] for o in records]) if curve is not None else dict(label='UNKNOWN',margin_m=None)
                        selected = g['selected_check'](curve,objects,float(tt[-1]-tt[i]))
                        accepted[variant] = dict(cid_g=cid,selected=selected,cv=cv,original_cv=orig,encoded_state=encoded)
                    r = dict(scene=name,token=frame['token'],plan=label,state_si=list(state),registered=d,vector=vector,aligned=o2,cids=cids,accepted=accepted,adapter_valid=not errors,odd=True)
                    out.write(json.dumps(r,allow_nan=False)+'\n')
            print('replayed',name,flush=True)

from pathlib import Path

def finalize(runtime):
    aggregation_start=time.monotonic()
    inputs=np.load(OUT/'full_inputs.npz')
    input_tokens=inputs['token']
    pred=np.full((29049,4,2),np.nan,np.float32)
    seen=[]
    for path in sorted(OUT.glob('full_*.jsonl')):
        with path.open(encoding='utf-8') as f:
            for line in f:
                r=json.loads(line)
                assert str(input_tokens[r['i']])==r['token']
                pred[r['i']]=r['wp']; seen.append(r['i'])
    assert sorted(seen)==list(range(29049)) and np.isfinite(pred).all()
    np.save(OUT/'plans_hw.npy',pred)
    np.save(OUT/'plan_tokens.npy',input_tokens)
    with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        frames = [json.loads(l) for l in f]
    scenes = sorted({r['scene'] for r in frames})
    assert len(scenes)==850
    index = {s:i for i,s in enumerate(scenes)}
    records = []
    for path in sorted(OUT.glob('replay_*.jsonl')):
        with path.open(encoding='utf-8') as f:
            records.extend(map(json.loads,f))
    assert len({(r['token'],r['plan']) for r in records}) == len(records) == 17445*2+9717
    rng = np.random.default_rng(20261104)
    draws = rng.multinomial(850,np.full(850,1/850),size=2000)
    def rate(rows,num,den):
        nn,dd = np.zeros(850),np.zeros(850)
        for r in rows:
            nn[index[r['scene']]] += bool(num(r))
            dd[index[r['scene']]] += bool(den(r))
        bn,bd = draws@nn,draws@dd
        good = bd>0
        return dict(n=int(nn.sum()),denominator=int(dd.sum()),rate=float(nn.sum()/dd.sum()) if dd.sum() else None,ci95=np.percentile(bn[good]/bd[good],[2.5,97.5]).tolist() if good.any() else [None,None],valid_bootstrap_draws=int(good.sum()))
    metrics,counts,checks = {},{},{}
    for variant in ('V0','VA','VB'):
        metrics[variant] = {}
        for label in 'HTU':
            rows = [r for r in records if r['plan']==label]
            accept = lambda r:r['cids'][variant]!=15
            m = dict(acceptance=rate(rows,accept,lambda r:True),rejection=rate(rows,lambda r:not accept(r),lambda r:True))
            for oracle,key in (('registered','registered'),('aligned','aligned')):
                lab = lambda r:r[key]['oracle']['label'] if key=='registered' else r[key]['label']
                m[oracle] = dict(false_reject=rate(rows,lambda r:lab(r)=='SAFE' and not accept(r),lambda r:lab(r)=='SAFE'),false_accept=rate(rows,lambda r:lab(r)=='UNSAFE' and accept(r),lambda r:lab(r)=='UNSAFE'),labels=dict(Counter(lab(r) for r in rows)))
            unsafe_reject = m['aligned']['false_accept']['denominator']-m['aligned']['false_accept']['n']
            fr = m['aligned']['false_reject']['n']
            m['intervention_precision'] = dict(n=unsafe_reject,denominator=unsafe_reject+fr)
            if variant!='VB':
                ar = [r['accepted'][variant] for r in rows if variant in r['accepted']]
                labels = Counter(r['selected']['label'] for r in ar)
                m['selected_labels'] = {k:labels[k] for k in wb.LABELS}
                m['selected_risk'] = dict(n=labels['UNSAFE'],denominator=labels['SAFE']+labels['UNSAFE'])
                checks[variant+'/'+label] = dict(accepted_records=len(ar),sampled_discrepancies=sum(r['cv']['margin_m'] < -1e-6 for r in ar),minimum_margin_m=min((r['cv']['margin_m'] for r in ar),default=None),original_sampled_discrepancies=sum(r['original_cv']['margin_m'] is not None and r['original_cv']['margin_m'] < -1e-6 for r in ar),original_unknown=sum(r['original_cv']['margin_m'] is None for r in ar))
            metrics[variant][label] = m
            if variant=='V0':
                counts[label] = dict(eligible=29049,odd=17445,generated=len(rows),adapter_valid=sum(r['adapter_valid'] for r in rows),aligned_labels=m['aligned']['labels'],registered_labels=m['registered']['labels'])
    total_checks = dict(accepted_records=sum(c['accepted_records'] for c in checks.values()),sampled_discrepancies=sum(c['sampled_discrepancies'] for c in checks.values()),minimum_margin_m=min(c['minimum_margin_m'] for c in checks.values() if c['minimum_margin_m'] is not None))
    false_accepts = []
    for r in records:
        for variant, cid in r['cids'].items():
            if cid == 15:
                continue
            for key in ('registered', 'aligned'):
                oracle = r[key]['oracle'] if key == 'registered' else r[key]
                if oracle['label'] == 'UNSAFE':
                    false_accepts.append(dict(scene=r['scene'], token=r['token'], plan=r['plan'], variant=variant, oracle_kind=key, cid=cid, state_si=r['state_si'], oracle=oracle))
    ph.dump('false_accepts.json', false_accepts)
    gate = json.loads((OUT/'gate.json').read_text())
    inputs = json.loads((OUT/'input_check.json').read_text())
    attempts = [json.loads(p.read_text()) for p in OUT.glob('attempt_*.json')]
    prior_gate_runtime = json.loads((OUT/'prior_w9a2_summary.json').read_text())['runtime_seconds']
    restarted_runtime = sum(json.loads(p.read_text())['runtime_seconds'] for p in OUT.glob('w9a3_attempt_*.json'))
    failed_runtime = prior_gate_runtime + restarted_runtime
    provenance = {str(p.relative_to(ROOT)):ph.sha(p) for p in (HERE/'PROTOCOL.md',HERE/'AMENDMENT_A7.md',HERE/'run_w7.py',HERE/'w7b/run_w7b.py',HERE/'w7c/run_w7c.py',ROOT/'sw/eval_trainval/run_models.py',ROOT/'sw/eval_trainval/build_dataset.py',ROOT/'sw/hwspec/hwspec_exact.py',ROOT/'sw/hwspec/common.py',ROOT/'sw/hwspec/_cache_params.pkl',ROOT/'sw/_verify_all_samples_spec.py',ROOT/'sw/eval_trainval/out/pred_hw_new.npy',OUT/'plans_hw.py',OUT/'replay.py')}
    for path in [ROOT/'eval/archived_weights/autoregressive_gru_200ep.pt']+list((ROOT/'sw/payloads/trained').glob('gru_*.bin')):
        provenance[str(path.relative_to(ROOT))]=ph.sha(path) if path.exists() else dict(available=False,sha256=None)
    for path in (HERE/'w7_secondary.py', HERE.parent/'golden/tsmx_golden/model.py', ROOT/'eval/data/nuscenes_loader.py', ROOT/'eval/data/nuscenes_lite.py', ROOT/'sw/eval_trainval/out/dataset.npz', HERE/'results/frames.jsonl', OUT/'full_inputs.npz', OUT/'supervisor_decision_w9a3.txt'):
        provenance[str(path.relative_to(ROOT))] = ph.sha(path)
    runtime+=time.monotonic()-aggregation_start
    deviations = ['RQ1 source replaces W7 A1 planner; no other numerical or threshold change.', 'RQ1 builder and current W7 both explicitly enable lane tokens; rebuilt RQ1 inputs checked against archived dataset.', 'Validation gate inputs/predictions reused for identical full-run tokens.', 'Original W7 H/U states and object adapter are replayed and asserted exactly equal.', 'VB selected labels remain unaudited, matching manuscript Table aligned.', 'Initial write-guard bytes-path bug stopped before inference; fixed and restarted; failed runtime included.', 'Sequential input rebuild replaced by four resumable input builders; discarded-prefix elapsed time included.', 'Windows null-device guard compatibility and run_models search path fixed during setup; no numerical changes.', 'Encoder INT4xINT8 matmul uses exact float32 BLAS under protocol A2 bound and per-worker integer-kernel checks; all other hw_new operations unchanged.']
    result = dict(status='COMPLETE',gate=gate,input_check=inputs,metrics=metrics,count_flow=counts,encoded_input_check=total_checks,encoded_input_check_by_group=checks,config=dict(sample_step_s=.001,hold_s=2.,reserve_m=.5,tolerance_m=1e-6,latency_s=.5,reaction_s=.1),odd_coverage=rate(frames,lambda r:r['odd'],lambda r:True),odd_coverage_all_keyframes=sum(r['odd'] for r in frames)/34149,keyframes=34149,scenes=850,workers=4,bootstrap=dict(draws=2000,seed=20261104,unit='scene',sampler='multinomial'),runtime_seconds=runtime+failed_runtime,successful_invocation_runtime_seconds=runtime,failed_attempt_runtime_seconds=failed_runtime,setup_probe=json.loads((OUT/'probe.json').read_text()),deviations=deviations,provenance=provenance)
    result.update(supervisor_decision=(OUT/'supervisor_decision_w9a3.txt').read_text(encoding='utf-8'), rtl_dump_audit=json.loads((OUT/'rtl_dump_audit.json').read_text()), prior_w9a2_runtime_seconds=prior_gate_runtime, w9a3_restarted_runtime_seconds=restarted_runtime, full_study_runtime_seconds=runtime+restarted_runtime, free_bytes_end=ph.shutil.disk_usage('C:/').free, gate_verification=json.loads((OUT/'w9a2_gate_verification.json').read_text()), frame_check=json.loads((OUT/'frame_check.json').read_text()))
    result['execution'] = json.loads((OUT/'w9a3_launch.json').read_text())
    result['false_accepts_artifact'] = dict(path='false_accepts.json', records=len(false_accepts), counts=dict(Counter(r['oracle_kind']+'/'+r['variant']+'/'+r['plan'] for r in false_accepts)))
    result['deviations'].extend(['W9a3 supervisor revised gate to 1e-5 m; all 5419 W9a2 records reused without gate inference; every nonzero difference enumerated.', 'Prior W9a/W9a2 measured runtime included once; restart gaps excluded.', 'Prediction/replay shard recovery discards only an interrupted final line before resuming.', 'W9a3 inference resumed after preloading NPZ arrays once per worker instead of rereading whole arrays per frame; no numerical operations changed; elapsed prior invocation included.', 'Missing original checkpoint path: existing RQ1 parameter cache and GRU payloads used without rebuilding; hashes retained.'])
    ph.dump('summary.json',result)
    report(result)

def report(s):
    def fmt(m):
        if m['rate'] is None:
            return f"{m['n']}/{m['denominator']}; N/A"
        return f"{m['n']}/{m['denominator']}; {m['rate']*100:.2f}% [{m['ci95'][0]*100:.2f},{m['ci95'][1]*100:.2f}]"
    def frac(m):
        return f"{m['n']}/{m['denominator']}"
    lines = ['# W9a3: RQ1 planner certification rerun','', 'Status: COMPLETE. T = unchanged RQ1 hw_new encoder + RTL-equivalent GRU; no zero-filled wp_proj.',f"Gate reused without inference: 5419/5419 within 1e-5 m; {s['gate']['exact_frames']} exact; max |diff|={s['gate']['max_abs_diff']} m; rebuilt-input discrepant frames={s['input_check']['discrepancies']}.",f"ODD coverage: {fmt(s['odd_coverage'])}; all-keyframe coverage={100*s['odd_coverage_all_keyframes']:.2f}%.",'','Table aligned, part 1 (count/denominator; percent [95% CI]).','|Variant|Acceptance|Aligned FR|Aligned FA|','|---|---|---|---|']
    for variant in ('V0','VA','VB'):
        for label in 'HTU':
            m = s['metrics'][variant][label]
            lines.append('|'+variant+'/'+label+'|'+'|'.join(fmt(x) for x in (m['acceptance'],m['aligned']['false_reject'],m['aligned']['false_accept']))+'|')
    lines += ['','Table aligned, part 2. Selected S/U/?/Tr; risk=U/(S+U); IP among labelable rejects.','|Variant|Selected S/U/?/Tr|Selected risk|IP|Rejection frequency|','|---|---|---|---|---|']
    for variant in ('V0','VA','VB'):
        for label in 'HTU':
            m=s['metrics'][variant][label]
            selected='/'.join(str(m['selected_labels'][k]) for k in wb.LABELS) if variant!='VB' else '--'
            risk=frac(m['selected_risk']) if variant!='VB' else '--'
            lines.append('|'+variant+'/'+label+'|'+selected+'|'+risk+'|'+frac(m['intervention_precision'])+'|'+frac(m['rejection'])+'|')
    lines += ['','Registered oracle (V0), as W7:','|Plan|Acceptance|FR / SAFE|FA / UNSAFE|','|---|---|---|---|']
    for label in 'HTU':
        m=s['metrics']['V0'][label]
        lines.append('|'+label+'|'+'|'.join(fmt(x) for x in (m['acceptance'],m['registered']['false_reject'],m['registered']['false_accept']))+'|')
    lines += ['','Count flow: eligible -> ODD -> generated -> V0 adapter-valid; aligned S/U/?/Tr.']
    for label,c in s['count_flow'].items():
        lines.append(f"{label}: {c['eligible']} -> {c['odd']} -> {c['generated']} -> {c['adapter_valid']}; "+'/'.join(str(c['aligned_labels'].get(k,0)) for k in wb.LABELS)+'.')
    c=s['encoded_input_check']
    lines.append(f"C: free bytes before full launch/end={s['execution']['free_bytes_before_launch']}/{s['free_bytes_end']}; >=10 GB before large writes.")
    lines.append(f"Full W9a3 measured runtime={s['full_study_runtime_seconds']:.3f} s; prior W9a/W9a2={s['prior_w9a2_runtime_seconds']:.3f} s; subsequent accounting verification timed separately in summary.json.")
    lines += ['',f"Encoded-input check: accepted records={c['accepted_records']}; sampled discrepancies={c['sampled_discrepancies']}; minimum margin={c['minimum_margin_m']:.9f} m (reserve included).",'1 ms samples, encoded ego, V0/VA cid-specific adapted objects; tolerance 1e-6 m; stop +2 s hold.', 'Shared selection/adapter and finite sampling: regression evidence, not an independent continuous-time theorem check.',f"Runtime: {s['runtime_seconds']:.3f} s including failed/discarded attempts ({s['failed_attempt_runtime_seconds']:.3f} s); detached, four workers.",'Runtime includes aggregation/hashing; final report/summary serialization excluded.','CI: 2,000 shared multinomial scene draws, seed 20261104, all 850 scenes.', 'A7 offline estimator lookahead retained; no online or closed-loop safety claim.', 'Acceptance covers all generated ODD plans; oracle denominators exclude UNKNOWN/TRUNCATED.', 'Deviations and execution details:']
    lines.extend('- '+d for d in s['deviations'])
    lines += ['Reproduce/resume: `python -B plans_hw.py --workers 4`; shards flush each record.','Full precision, all report values, checks and source hashes: summary.json; per-plan evidence: replay_*.jsonl.', 'Every registered/aligned false accept, with scene/token/variant/plan and full oracle evidence: false_accepts.json.']
    lines = [l for l in lines if not l.startswith('- ')] + ['Execution deviations (full list in summary.json): ' + ' '.join(s['deviations']), '', 'Supervisor decision (Claude, 06/11), verbatim:', s['supervisor_decision'].rstrip(), 'Nonzero gate differences (zero-based index: max absolute size in m): ' + '; '.join(str(r['i'])+': '+str(r['max_abs_diff']) for r in s['gate']['mismatches'])+'.', 'Read-only W9b audit: all 35 current dumps equal final_35 byte-for-byte; they do not predate final bert_v2. Original final runs: 2026-10-03; s00..02 regression rewrites: 2026-10-04 (local +07).', 'Same 35 scene-0103 frames, RQ1 indices 822..856; max vs saved hw_new=0.026161670684814453 m (s16/index 838), vs actual TB references=0.0000209808349609375 m. All masks match; all token arrays differ.', 'Audit file paths, dates, hashes, every frame token and evidence citations: rtl_dump_audit.json; RTL_DUMP_AUDIT.md. No paper numbers changed.']
    assert len('\n'.join(lines).splitlines())<=80,len('\n'.join(lines).splitlines())
    (OUT/'W9A_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

if __name__=='__main__':
    ap=ph.argparse.ArgumentParser()
    ap.add_argument('--stage')
    ap.add_argument('--shard',type=int,required=True)
    ap.add_argument('--workers',type=int,default=4)
    a=ap.parse_args()
    worker(a.shard,a.workers)
