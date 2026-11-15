"""Record an observed exact-match gate failure, without study estimates."""
import plans_hw as p
from collections import Counter

def main():
    start=p.time.monotonic()
    stop_path=p.OUT/'gate_stop_status.json'
    if not stop_path.exists():
        p.dump('gate_stop_status.json',p.json.loads((p.OUT/'status.json').read_text()))
    old_status=p.json.loads(stop_path.read_text())
    rows=[]
    for path in sorted(p.OUT.glob('gate_*.jsonl')):
        with path.open(encoding='utf-8') as f:
            rows.extend(p.json.loads(l) for l in f)
    rows.sort(key=lambda r:r['i'])
    assert len({r['i'] for r in rows})==len(rows)
    mismatches=[r for r in rows if not r['exact']]
    assert mismatches, 'This report requires an observed gate failure'
    check=p.json.loads((p.OUT/'input_check.json').read_text())
    verification=p.json.loads((p.OUT/'mismatch_verification.json').read_text())
    assert verification['unmodified_vs_reference_max_abs_diff']>0
    assert verification['unmodified_vs_accelerated_max_abs_diff']==0
    assert not list(p.OUT.glob('full_*.jsonl')) and not list(p.OUT.glob('replay_*.jsonl'))
    attempts=[p.json.loads(f.read_text()) for f in sorted(p.OUT.glob('attempt_*.json'))]
    with (p.HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        frames=[p.json.loads(l) for l in f]
    scenes=sorted({r['scene'] for r in frames})
    index={s:i for i,s in enumerate(scenes)}
    nn,dd=p.np.zeros(len(scenes)),p.np.zeros(len(scenes))
    for r in frames:
        nn[index[r['scene']]]+=r['odd']; dd[index[r['scene']]]+=1
    draws=p.np.random.default_rng(20261104).multinomial(len(scenes),p.np.full(len(scenes),1/len(scenes)),size=2000)
    bn,bd=draws@nn,draws@dd
    coverage=dict(n=int(nn.sum()),denominator=int(dd.sum()),rate=float(nn.sum()/dd.sum()),ci95=p.np.percentile(bn/bd,[2.5,97.5]).tolist(),scope='Existing W7 frame metadata; unchanged ODD selection, not new planner evaluation')
    hashes={}
    sources=[p.ROOT/'sw/eval_trainval/run_models.py',p.ROOT/'sw/eval_trainval/build_dataset.py',p.ROOT/'sw/eval_trainval/out/dataset.npz',p.ROOT/'sw/eval_trainval/out/pred_hw_new.npy',p.ROOT/'sw/hwspec/hwspec_exact.py',p.ROOT/'sw/hwspec/common.py',p.ROOT/'sw/hwspec/_cache_params.pkl',p.ROOT/'sw/_verify_all_samples_spec.py',p.ROOT/'eval/archived_weights/autoregressive_gru_200ep.pt',p.HERE/'run_w7.py',p.HERE/'PROTOCOL.md',p.HERE/'AMENDMENT_A7.md',p.HERE/'results/frames.jsonl']+list((p.ROOT/'sw/payloads/trained').glob('gru_*.bin'))+list(p.OUT.glob('*.py'))
    for path in sources:
        hashes[str(path.relative_to(p.ROOT))]=p.sha(path) if path.exists() else dict(available=False,sha256=None)
    null=dict(status='NOT_RUN_GATE_FAILED',acceptance=None,aligned_false_reject=None,aligned_false_accept=None,selected_labels=None,selected_risk=None,intervention_precision=None,rejection_frequency=None)
    s=dict(status='GATE_FAILED',full_run_started=False,gate=dict(status='FAILED',required_frames=5419,checked_frames=len(rows),exact_frames=len(rows)-len(mismatches),mismatched_frames=len(mismatches),untested_frames=5419-len(rows),max_abs_diff=max(r['max_abs_diff'] for r in rows),required_max_abs_diff=0.,mismatches=mismatches,early_stop=True),input_check=check,mismatch_verification=verification,odd_coverage=coverage,keyframes=34149,scenes=len(scenes),workers=4,bootstrap=dict(draws=2000,seed=20261104,unit='scene',sampler='multinomial'),count_flow={label:dict(w7_eligible=len(frames),w7_odd=int(nn.sum()),w9a_generated=0,w9a_adapter_valid=None) for label in 'HTU'},aligned_table={variant+'/'+label:dict(null) for variant in ('V0','VA','VB') for label in 'HTU'},registered_oracle={label:dict(acceptance=None,false_reject=None,false_accept=None,status='NOT_RUN_GATE_FAILED') for label in 'HTU'},encoded_input_check=dict(accepted_records=0,sampled_discrepancies=None,minimum_margin_m=None,status='NOT_RUN_GATE_FAILED'),runtime=dict(gate_invocation_seconds=old_status['runtime_seconds'],failed_and_discarded_attempts_seconds=sum(a['runtime_seconds'] for a in attempts),post_stop_verification_seconds=verification['runtime_seconds'],attempts=attempts,scope='Wall time: detached gate invocation, failed/discarded attempts, post-stop unmodified verification, final aggregation/hashing. Concurrent setup probes not double-counted; final serialization excluded.'),provenance=hashes,deviations=['Stopped gate early after observing a nonzero difference; did not compute all required validation predictions or start the full study.','RQ1 builder and current W7 both enable lane tokens; all rebuilt validation inputs and masks exactly match the archived RQ1 dataset.','Encoder INT4xINT8 used protocol A2 exact float32 BLAS with bounds and per-worker kernel checks; unmodified hw_new independently reproduces the same mismatch.','Sequential input rebuild replaced by four resumable input builders; discarded-prefix wall time retained.','Initial bytes-path write guard bug stopped before inference; fixed; failed-attempt wall time retained.','Setup fixes covered Windows null device and run_models module lookup.','H and U are unchanged in prepared replay code; W7 U depends on ego speed and front-object presence, not T. No H/U results were rerun.','W7 reference ODD metadata is reported separately from unavailable W9a plan metrics.','Exact mismatch cause remains unresolved; no tolerance relaxation, reference update, weight change, or target substitution.'])
    s['runtime']['aggregation_hashing_seconds']=p.time.monotonic()-start
    s['deviations'].append('The checkpoint path named by common.py is absent in the current tree. Inference used its existing RQ1 parameter cache and GRU payloads; no checkpoint rebuild or substitution. Checkpoint hash unavailable; cache/payload hashes supplied.')
    s['deviations'].append('Initial report packaging stopped on that missing checkpoint path; corrected to record unavailable provenance. Failed packaging duration is unmeasured and excluded from timed runtime.')
    s['runtime']['failed_initial_packaging_seconds']=None
    s['runtime_seconds']=sum(s['runtime'][k] for k in ('gate_invocation_seconds','failed_and_discarded_attempts_seconds','post_stop_verification_seconds','aggregation_hashing_seconds'))
    p.dump('summary.json',s)
    p.dump('gate.json',s['gate'])
    g=s['gate']; v=s['mismatch_verification']; c=s['odd_coverage']
    lines=['# W9a: RQ1 planner gate FAILED','', 'Full study NOT RUN: required exact-match sanity gate failed; no new T metrics are available.',f"Gate checked {g['checked_frames']}/{g['required_frames']}: exact={g['exact_frames']}, mismatches={g['mismatched_frames']}, untested={g['untested_frames']}.",f"Observed max |diff|={g['max_abs_diff']:.17g}; required=0. Stopped at the first observed failure.",f"All {check['frames']} rebuilt validation inputs/masks match archived RQ1 data; discrepancies={check['discrepancies']}, max token difference={check['max_abs_token_diff']}.",f"Failing RQ1 index {v['i']}, token `{v['token']}`.",f"Unmodified hw_new vs reference max |diff|={v['unmodified_vs_reference_max_abs_diff']:.17g}; unmodified vs accelerated={v['unmodified_vs_accelerated_max_abs_diff']}.",'Cause unresolved. Mismatch evidence, exact arrays and hashes: mismatch_verification.json and summary.json.','', 'Table aligned, part 1. N/R = not run because the exact-match gate failed.','|Variant|Acceptance|Aligned FR|Aligned FA|','|---|---|---|---|']
    for variant in ('V0','VA','VB'):
        lines.extend('|'+variant+'/'+label+'|N/R|N/R|N/R|' for label in 'HTU')
    lines+=['','Table aligned, part 2.','|Variant|Selected S/U/?/Tr|Selected risk|IP|Rejection frequency|','|---|---|---|---|---|']
    for variant in ('V0','VA','VB'):
        lines.extend('|'+variant+'/'+label+'|N/R|N/R|N/R|N/R|' for label in 'HTU')
    lines+=['','Registered oracle: acceptance, FR / SAFE and FA / UNSAFE are N/R for H, T and U. No new denominators.',f"Reference W7 ODD metadata only: {c['n']}/{c['denominator']}; {100*c['rate']:.2f}% [{100*c['ci95'][0]:.2f},{100*c['ci95'][1]:.2f}].",f"Reference inventory: {s['keyframes']} keyframes, {s['scenes']} scenes.",f"Count flow H/T/U: {len(frames)} W7 eligible -> {int(nn.sum())} W7 ODD -> 0 W9a generated; adapter-valid N/R.",'Encoded-input audit: 0 accepted records evaluated; sampled discrepancies and minimum margin N/R.',f"Runtime: {s['runtime_seconds']:.3f} s; detached, four workers. Scope and component times: summary.json.",'Reference ODD CI only: 2,000 shared multinomial scene draws, seed 20261104.','No full planner shards, decisions, library labels or selected labels were produced.','Deviations and execution details:']
    lines.extend('- '+d for d in s['deviations'])
    lines+=['All writes remain under w9a. Rerun code is prepared but cannot pass the current exact gate.','Resume only after resolving the exact-match failure. Check state: `python -B progress.py`.']
    assert len(lines)<=80,len(lines)
    (p.OUT/'W9A_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    p.dump('status.json',dict(status='GATE_FAILED',runtime_seconds=s['runtime_seconds'],checked_frames=g['checked_frames'],max_abs_diff=g['max_abs_diff'],full_run_started=False))
    print(p.json.dumps(dict(status=s['status'],runtime_seconds=s['runtime_seconds'],gate=g)))

if __name__=='__main__':
    main()
