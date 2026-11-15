"""Native, post hoc accepted-candidate audit. Writes confined to this directory."""
import sys
sys.dont_write_bytecode = True
import os
from pathlib import Path
OUT = Path(__file__).resolve().parent
HERE = OUT.parent
os.environ['TEMP'] = os.environ['TMP'] = str(OUT)
for key in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ[key] = '1'


def guard(event, args):
    if event == 'open':
        path, mode, flags = args
        writing = (isinstance(mode, str) and any(c in mode for c in 'wax+')) or (flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC))
        if writing and not isinstance(path, int):
            p = Path(path).resolve()
            if p != OUT and OUT not in p.parents:
                raise PermissionError('W7c write outside output directory: ' + str(p))


sys.addaudithook(guard)
sys.path[:0] = [str(HERE), str(HERE/'w7b')]
import run_w7 as w
os.environ['TEMP'] = os.environ['TMP'] = str(OUT)
import run_w7b as wb
os.environ['TEMP'] = os.environ['TMP'] = str(OUT)
import w7_secondary as sec
import numpy as np
import json
import math
import time
import pickle
from collections import Counter, defaultdict
from dataclasses import asdict

TOL = 1e-6


def dump(path, obj):
    path.write_text(json.dumps(obj, indent=2, allow_nan=False), encoding='utf-8')


def curve_for(state, cid):
    return w.float_profile(*state, *w.PAIRS[cid//4*3+cid%4])


def with_hold(curve):
    ts, xs = curve
    stop = float(ts[-1])
    return np.r_[ts, stop+np.arange(1, 2001)*.001], np.r_[xs, np.full(2000, xs[-1])], stop


def cv_check(curve, raw, tokens):
    ts, xs, stop = with_hold(curve)
    at = ts+.5
    minimum, culprit = 1e4, None
    for o, token in zip(raw, tokens):
        ox = o.x/1e6+o.v/1e6*at
        gaps = np.abs(ox-xs)-o.length/1e6-.5
        i = int(np.argmin(gaps))
        if float(gaps[i]) < minimum:
            minimum = float(gaps[i])
            culprit = dict(object=token, time_from_t0_s=float(at[i]), side='ahead' if ox[i]>=xs[i] else 'behind',
                           during_hold=bool(ts[i]>stop+1e-9), object_x_m=float(ox[i]), ego_x_m=float(xs[i]))
    return dict(label='SAFE' if minimum>=-TOL else 'UNSAFE', margin_m=minimum, culprit=culprit,
                stop_from_apply_s=stop, end_from_t0_s=float(at[-1]), objects=len(raw))


def selected_check(curve, objects, scene_end):
    if curve is None:
        return dict(label='UNKNOWN', margin_m=None, culprit=None, reason='invalid_float_plan', evidence_status='UNRESOLVED')
    result = wb.profile_check(curve, objects, scene_end, True)
    if result['label']=='GT_TRUNCATED':
        result.update(margin_m=None, culprit=None, evidence_status='UNRESOLVED: full selected-candidate minimum lacks GT coverage')
    return result


def attribution(check, objects, records, raw, curve):
    c = check.get('culprit')
    if check['label']!='UNSAFE' or c is None:
        return None
    token, at = c['object'], c['time_from_t0_s']
    obj = next(o for o in objects if o['token']==token)
    matches = [i for i,o in enumerate(records) if o['token']==token]
    detail = dict(during_hold=c['during_hold'], side=c['side'], object=token,
                  in_golden_input=bool(matches), time_from_t0_s=at)
    if not matches:
        detail.update(cause='a_not_in_input_A5', reason='outside t0 corridor or later-born track',
                      gt_minus_golden_cv_m=None, predicted_margin_at_time_m=None)
        return detail
    i = matches[0]
    o, r = raw[i], records[i]
    gt = float(np.interp(at, obj['times'], obj['xs']))
    pred = o.x/1e6+o.v/1e6*at
    ts, xs, stop = with_hold(curve)
    ex = float(np.interp(at-.5, ts, xs))
    pm = abs(pred-ex)-o.length/1e6-.5
    d = gt-pred
    # Use the same footprint as the golden to distinguish cover inflation from
    # a geometry convention. VA covers are intentionally larger than GT bodies.
    gt_same_extent_margin = abs(gt-ex)-o.length/1e6-.5
    original_cv = r['x']+r['v']*at
    if gt_same_extent_margin >= -TOL:
        cause = 'c_footprint_lateral_convention'
    elif pm >= -TOL and abs(d)>TOL:
        cause = 'b_in_input_GT_deviates'
    else:
        cause = 'd_other_UNRESOLVED'
    detail.update(cause=cause, gt_minus_golden_cv_m=d, abs_gt_minus_golden_cv_m=abs(d),
                  gt_minus_original_cv_m=gt-original_cv, predicted_margin_at_time_m=pm,
                  gt_margin_with_golden_extent_m=gt_same_extent_margin,
                  gt_x_m=gt, golden_cv_x_m=pred, original_cv_x_m=original_cv, ego_x_m=ex,
                  golden_half_length_m=o.length/1e6, gt_half_length_m=obj['length'],
                  original_velocity_mps=r['v'], golden_velocity_mps=o.v/1e6,
                  negative_velocity_cover=bool(w.fixed(r['v'])<0))
    return detail


def distribution(values):
    if not values:
        return dict(n=0, min=None, p25=None, median=None, p75=None, p95=None, max=None)
    q = np.percentile(values, [0,25,50,75,95,100]).tolist()
    return dict(n=len(values), **dict(zip(('min','p25','median','p75','p95','max'),q)))


def summary(rows, selector):
    chosen = [r for r in rows if selector(r)]
    causes = Counter()
    signed, absolute, original, predicted = [], [], [], []
    for r in chosen:
        a = r['attribution']
        if a is None:
            causes['UNRESOLVED_selected_'+r['o2_selected']['label']] += 1
            continue
        causes[a['cause']+'/'+('hold' if a['during_hold'] else 'before_hold')] += 1
        if a.get('gt_minus_golden_cv_m') is not None:
            signed.append(a['gt_minus_golden_cv_m'])
            absolute.append(abs(a['gt_minus_golden_cv_m']))
            original.append(a['gt_minus_original_cv_m'])
            predicted.append(a['predicted_margin_at_time_m'])
    return dict(n=len(chosen), causes=dict(causes), signed_d_m=distribution(signed),
                abs_d_m=distribution(absolute), original_input_signed_d_m=distribution(original),
                golden_predicted_margin_at_culprit_time_m=distribution(predicted))


def main():
    start = time.monotonic()
    from data.nuscenes_lite import load_nuscenes
    manifest = json.loads((HERE/'results/manifest.json').read_text())
    root = Path(manifest['dataset'])
    assert (root/'v1.0-trainval/_nuscenes_lite_v2.pkl').exists()
    nusc = load_nuscenes('v1.0-trainval', str(root))
    with (HERE/'annotation_categories.pkl').open('rb') as f:
        cats = pickle.load(f)
    frames = defaultdict(list)
    with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        for r in map(json.loads,f):
            if r['odd']:
                frames[r['scene']].append(r)
    previous = {}
    for path in sorted((HERE/'w7b').glob('plans_*.jsonl')):
        with path.open(encoding='utf-8') as f:
            for r in map(json.loads,f):
                previous[r['token'],r['plan']] = dict(o2=r['o2']['label'], decisions=r['decisions'])
    rows, violations = [], []
    mismatches = []
    path = OUT/'accepted.jsonl'
    with path.open('w', encoding='utf-8', buffering=1) as log:
        for scene in sorted(nusc.scene, key=lambda s:(s['name'],s['token'])):
            name = scene['name']
            if name not in frames:
                continue
            wb.roots.clear()
            samples, pp, tt, aa, tracks = wb.scene_tracks(nusc, scene, cats)
            indices = {s['token']:i for i,s in enumerate(samples)}
            for frame in frames[name]:
                i = indices[frame['token']]
                axis = np.array([math.cos(aa[i]),math.sin(aa[i])])
                objects = None
                records = frame['objects']
                for plan,d in frame['plans'].items():
                    state = d['state_si']
                    ego = w.Ego(500000,*map(w.fixed,state),0,0)
                    cids = dict(V0=sec.v0(ego,records),VA=sec.va(ego,records))
                    old = previous[frame['token'],plan]
                    for variant,cid in cids.items():
                        if (cid!=15)!=old['decisions'][variant] or (variant=='V0' and cid!=d['cid']):
                            mismatches.append(dict(token=frame['token'],plan=plan,variant=variant,cid=cid))
                        if cid==15:
                            continue
                        if objects is None:
                            objects = wb.projected(tracks, pp[i], axis, np.array([-axis[1],axis[0]]), tt[i], {o['token']:o for o in records})
                        tr, propagated = wb.golden_objects(ego,records,cid,variant)
                        horizon = tr.rows[-1][0]-tr.rows[0][0]
                        raw = sec.raw_objects(records) if variant=='V0' else sec.reduce_neg(records,horizon,False)
                        geom = w.b3_geom(tr,propagated,w.LANE)
                        assert geom.accept
                        curve = curve_for(state,cid)
                        check = selected_check(curve,objects,float(tt[-1]-tt[i]))
                        tokens = [o['token'] for o in records]
                        encoded_state = [ego.x/1e6,ego.v/1e6,ego.a/1e6]
                        cv = cv_check(curve_for(encoded_state,cid),raw,tokens)
                        original_cv = cv_check(curve,raw,tokens) if curve is not None else dict(label='UNKNOWN',margin_m=None,
                            reason='UNRESOLVED original float profile: original velocity can be negative but rounds to valid zero in golden')
                        r = dict(scene=name,token=frame['token'],plan=plan,variant=variant,cid_g=cid,
                                 state_si=state, old_oracle_label=d['oracle']['label'],o2_library_label=old['o2'],
                                 o2_selected=check,cv_replay=cv,original_plan_cv_replay=original_cv,encoded_state_si=encoded_state,golden_margin_m=geom.margin/1e6,
                                 golden_end_from_t0_s=.5+horizon/1e6)
                        r['attribution'] = attribution(check,objects,records,raw,curve)
                        if d['oracle']['label']=='UNSAFE':
                            # The old oracle uses only t0 W7 objects, no hold, and
                            # its original 3 s cap/last-pose convention. Same cid_g.
                            old_objects = [dict(o, times=np.array(o['times']), xs=np.array(o['xs']),
                                                ys=np.zeros(len(o['times'])),widths=np.ones(len(o['times'])),in_w7=True) for o in records]
                            # Extend explicitly to reproduce OLD extrapolation only.
                            end = float(curve[0][-1]+.5)
                            for o in old_objects:
                                if o['times'][-1]<end:
                                    o['times']=np.r_[o['times'],end]
                                    o['xs']=np.r_[o['xs'],o['xs'][-1]]
                                    o['ys']=np.r_[o['ys'],0.]
                                    o['widths']=np.r_[o['widths'],1.]
                            oldcheck = wb.profile_check(curve,old_objects,max(end,3.),False)
                            r['old_selected'] = oldcheck
                            r['old_selected_attribution'] = attribution(oldcheck,old_objects,records,raw,curve)
                        if cv['margin_m'] < -TOL or (original_cv['margin_m'] is not None and original_cv['margin_m'] < -TOL):
                            encoded = cv
                            violation = dict(r, golden_raw_t0_inputs=[dict(token=t,**asdict(o)) for t,o in zip(tokens,raw)],
                                             golden_propagated_inputs=[asdict(o) for o in propagated],
                                             golden_rows=[list(x) for x in tr.rows], encoded_state_si=encoded_state,
                                             encoded_state_cv=encoded)
                            violation['explanation'] = ('Original float versus rounded encoded ego state mismatch' if encoded['margin_m']>=-TOL
                                                        else 'UNRESOLVED: encoded replay also violates; inspect full golden rows and input states')
                            violations.append(violation)
                        rows.append(r)
                        log.write(json.dumps(r,allow_nan=False)+'\n')
            print(f'{name}: accepted variant/plans={len(rows)}, CV violations={len(violations)}, elapsed={time.monotonic()-start:.1f}s',flush=True)
    result = dict(post_hoc=True, tolerance_m=TOL,
                  tolerance_reason='Golden interval arithmetic rounds outward; only 1e-6 m numerical/encoding tolerance is allowed. Larger negatives are violations.',
                  config=dict(step_s=.001,latency_s=.5,reaction_s=.1,reserve_m=.5,hold_s=2.,
                              cv_inputs='Exact fixed-point t0 V0 inputs or cid-specific VA covers, SI constant velocities and encoded ego state. Original float ego CV replay also supplied for every valid profile.',
                              o2='Unchanged W7b relevance, footprints, coverage and profile_check, cid_g ONLY; missing GT minima UNRESOLVED.',
                              deviation='d = GT longitudinal position minus adapted golden t0 centre + velocity*time; original pre-cover CV also reported.',
                              prediction='Float margin for adapted golden object at the GT minimising time, same selected ego curve; golden_margin_m is the certified global interval lower bound.',
                              classification='a absent input; c GT unsafe only under different extent; b adapted CV safe but GT unsafe; d otherwise. Nonexclusive physical attribution remains limited to minimiser.',
                              hold='Strictly after exact float stop; no hold in old-selected consistency replay.'),
                  counts={}, classifications={}, old_false_accepts=[], cv_violations=violations,
                  original_float_profile_unresolved=[r for r in rows if r['original_plan_cv_replay']['label']=='UNKNOWN'],
                  validation=dict(selection_mismatches=mismatches), accepted_records='accepted.jsonl')
    prior = json.loads((HERE/'w7b/results.json').read_text())
    secondary = json.loads((HERE/'results/secondary.json').read_text())
    for variant in ('V0','VA'):
        for plan in 'HTU':
            key = variant+'/'+plan
            group = [r for r in rows if r['variant']==variant and r['plan']==plan]
            assert len(group)==secondary['variants'][variant][plan]['accept']
            assert sum(r['o2_library_label']=='UNSAFE' for r in group)==prior['metrics'][variant][plan]['O2']['false_accept']['n']
            assert sum(r['old_oracle_label']=='UNSAFE' for r in group)==secondary['variants'][variant][plan]['false_accept']
            result['counts'][key] = dict(accepted=len(group),selected_labels=dict(Counter(r['o2_selected']['label'] for r in group)),
                                         cv_violations=sum(r['cv_replay']['margin_m'] < -TOL for r in group),
                                         original_plan_cv_violations=sum(r['original_plan_cv_replay']['margin_m'] is not None and r['original_plan_cv_replay']['margin_m'] < -TOL for r in group),
                                         original_plan_cv_unknown=sum(r['original_plan_cv_replay']['label']=='UNKNOWN' for r in group),
                                         min_cv_margin_m=min(r['cv_replay']['margin_m'] for r in group),
                                         o2_library_false_accepts=sum(r['o2_library_label']=='UNSAFE' for r in group),
                                         old_false_accepts=sum(r['old_oracle_label']=='UNSAFE' for r in group))
            result['classifications'][key] = dict(
                selected_unsafe=summary(group,lambda r:r['o2_selected']['label']=='UNSAFE'),
                o2_library_false_accepts=summary(group,lambda r:r['o2_library_label']=='UNSAFE'),
                old_false_accepts_using_O2_selected=summary(group,lambda r:r['old_oracle_label']=='UNSAFE'))
            for period in (True,False):
                result['classifications'][key]['selected_unsafe_'+('hold' if period else 'before_hold')] = summary(group,lambda r:r['attribution'] is not None and r['attribution']['during_hold']==period)
    result['old_false_accepts'] = [r for r in rows if r['old_oracle_label']=='UNSAFE']
    result['validation'].update(accepted_counts_match=True,old_and_O2_library_FA_counts_match=True,
                                write_scope='Python audit hook rejects file writes outside w7c',python=sys.version,executable=sys.executable,dataset=str(root))
    assert not mismatches
    sources = [Path(__file__), HERE/'run_w7.py',HERE/'w7_secondary.py',HERE/'w7b/run_w7b.py',HERE/'w7b/fa_causes.py',
               HERE.parent/'golden/tsmx_golden/model.py',HERE/'results/frames.jsonl',HERE/'results/manifest.json',HERE/'results/secondary.json',HERE/'w7b/results.json']
    result['sha256'] = {os.path.relpath(p,OUT):w.sha(p) for p in sources}
    result['runtime_wall_seconds'] = time.monotonic()-start
    result['status'] = 'COMPLETE' if not any(v['explanation'].startswith('UNRESOLVED') for v in violations) else 'UNRESOLVED_CV_MISMATCH'
    dump(OUT/'results.json',result)
    report(result)
    print(json.dumps(dict(status=result['status'],counts=result['counts'],runtime_s=result['runtime_wall_seconds'])),flush=True)


def report(r):
    lines = ['# W7c accepted-candidate audit — POST HOC', '',
             'Each accepted V0/VA plan is replayed using its own golden cid_g; all records: accepted.jsonl. Golden and W7/W7b unchanged.',
             'O2: original float plan; apply +0.5 s, reaction 0.1 s, 1 ms samples, reserve 0.5 m, exact stop +2 s hold; W7b full-window relevance/coverage.',
             'CV: exact encoded ego/t0 objects after V0/VA adapter, same velocities/covers, through stop + hold; also replay original float ego. Tolerance 1e-6 m: golden rounds outward.',
             'Missing GT coverage: GT_TRUNCATED, minimum/object/time UNRESOLVED; no extrapolation. SAFE/UNSAFE labels below apply only to cid_g.', '',
             '|Variant/plan|Accepted|Selected SAFE/UNSAFE/UNKNOWN/TRUNCATED|CV violations|min CV margin m|O2 library FA|Old FA|',
             '|---|---:|---|---:|---:|---:|---:|']
    for key,c in r['counts'].items():
        labs = '/'.join(str(c['selected_labels'].get(k,0)) for k in wb.LABELS)
        lines.append(f"|{key}|{c['accepted']}|{labs}|{c['cv_violations']}|{c['min_cv_margin_m']:.9f}|{c['o2_library_false_accepts']}|{c['old_false_accepts']}|")
    lines += ['', 'Selected-UNSAFE attribution: a = absent from golden input (A5); b = in input, GT deviates from adapted CV; c = footprint/lateral convention; d = other/UNRESOLVED.',
              'd is signed longitudinal GT minus adapted golden CV at the selected minimiser; original pre-cover d is also stored. Predicted margins use that same object/time.',
              '|Variant/plan|a before/hold|b before/hold|c before/hold|d before/hold|median / p95 abs d m|',
              '|---|---|---|---|---|---|']
    for key,entry in r['classifications'].items():
        s=entry['selected_unsafe']; c=s['causes']; a=s['abs_d_m']
        cells = ['/'.join(str(c.get(cause+'/'+period,0)) for period in ('before_hold','hold')) for cause in
                 ('a_not_in_input_A5','b_in_input_GT_deviates','c_footprint_lateral_convention','d_other_UNRESOLVED')]
        ds = f"{a['median']:.6f} / {a['p95']:.6f}" if a['n'] else 'UNRESOLVED (no in-input minimisers)'
        lines.append('|'+key+'|'+'|'.join(cells)+'|'+ds+'|')
    lines += ['', 'Full distributions (signed/absolute d and predicted margin), split by hold, plus original O2-library FA and old-FA subsets: results.json:classifications.',
              'Every old-oracle FA is listed in results.json:old_false_accepts with cid_g O2 audit, CV audit, and old-selected no-hold replay (including old 3 s cap).',
              f"CV violations (encoded or original): {len(r['cv_violations'])}; full inputs/rows/explanation: results.json:cv_violations. Original-profile UNKNOWN: {len(r['original_float_profile_unresolved'])}; all listed with encoded replay in results.json.",
              'Citations: ../run_w7.py:189 (corridor/combined half-length), :234 (float profile), :278 (old oracle), :302 (encoding/latency); ../w7_secondary.py:51 (VA covers), :72 (selection).',
              'Citations: ../w7b/run_w7b.py:52 (projection), :93 (selected profile coverage/minimum); ../w7b/fa_causes.py:26 (old best-candidate attribution); ../../golden/tsmx_golden/model.py:406 (B4), :439 (B3), :683 (select_world).',
              f"Status {r['status']}; native Python {sys.version.split()[0]}; measured runtime {r['runtime_wall_seconds']:.3f} s (load, replay, aggregation, hashes; final serialization excluded).",
              'Reproduce: `python -B tsmx_hw/eval_nuscenes/w7c/run_w7c.py`. Selection and accepted/FA count checks passed; source/input hashes in results.json.']
    assert len(lines)<=40,len(lines)
    (OUT/'W7C_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
