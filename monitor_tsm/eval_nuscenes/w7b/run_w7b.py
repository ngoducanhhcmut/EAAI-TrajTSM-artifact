"""Post hoc W7b. All outputs, temporary files and bytecode stay in this directory.

Reuse: run_w7.py:234 float_profile, :302 evaluate_plan encoding, :501 bootstrap;
w7_secondary.py:51 reduce_neg and :72 va; golden/model.py:439 b3 diagnostics.
Run with W7's native Python: python -B .../w7b/run_w7b.py
"""
import sys
sys.dont_write_bytecode = True
import os
from pathlib import Path
OUT = Path(__file__).resolve().parent
HERE = OUT.parent
os.environ['TEMP'] = os.environ['TMP'] = str(OUT)
for name in ('OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'OPENBLAS_NUM_THREADS'):
    os.environ[name] = '1'
sys.path.insert(0, str(HERE))
import run_w7 as w
os.environ['TEMP'] = os.environ['TMP'] = str(OUT)  # W7 import sets these; restore.
import w7_secondary as sec
import argparse
import json
import math
import time
import subprocess
from collections import Counter, defaultdict
import numpy as np

LABELS = ('SAFE', 'UNSAFE', 'UNKNOWN', 'GT_TRUNCATED')


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False), encoding='utf-8')


def scene_tracks(nusc, scene, cats):
    samples, p, times, angles, _, _ = w.scene_data(nusc, scene)
    tracks = defaultdict(list)
    for sample in samples:
        for token in sample['anns']:
            cat = cats[token]
            if cat.startswith(('vehicle.', 'human.')) or 'cycle' in cat:
                ann = nusc.get('sample_annotation', token)
                # Cache omits instance_token: annotation links identify the track.
                root = token
                if ann['prev']:
                    root = roots[ann['prev']]
                roots[token] = root
                tracks[root].append((sample['timestamp']*1e-6, token, ann))
    return samples, p, times, angles, list(tracks.values())


def projected(tracks, origin, axis, side, t0, originals):
    result = []
    for track in tracks:
        tt = np.array([r[0]-t0 for r in track])
        if tt[-1] < 0:
            continue
        pos = np.array([r[2]['translation'][:2] for r in track])-origin
        xx, yy = pos @ axis, pos @ side
        widths = np.array([r[2]['size'][0] for r in track])
        lengths = np.array([r[2]['size'][1] for r in track])
        # At t0 use exactly W7's size and velocity for existing objects.
        at0 = next((r[1] for r in track if abs(r[0]-t0) < 1e-5), None)
        old = originals.get(at0)
        token = at0 or track[0][1]
        x0 = float(np.interp(0., tt, xx)) if tt[0] <= 0 <= tt[-1] else None
        vel = old['v'] if old else None
        if not old and at0:
            k = next(i for i, r in enumerate(track) if r[1] == at0)
            lo, hi = max(0, k-1), min(len(track)-1, k+1)
            if hi > lo:
                vel = float((xx[hi]-xx[lo])/(tt[hi]-tt[lo]))
        result.append(dict(token=token, times=tt, xs=xx, ys=yy, widths=widths,
                           length=old['length'] if old else (4.8+float(np.interp(0, tt, lengths)))/2,
                           x=x0, v=vel, in_w7=bool(old)))
    return result


def relevant(obj, end):
    tt = obj['times']
    lo, hi = max(0., tt[0]), min(end, tt[-1])
    if hi < lo:
        return False
    knots = np.r_[lo, tt[(tt > lo) & (tt < hi)], hi]
    y = np.interp(knots, tt, obj['ys'])
    half = 1.8 + np.interp(knots, tt, obj['widths'])/2
    if np.any(np.abs(y) <= half):
        return True
    # Linear interpolation can cross the corridor with both endpoints outside.
    return bool(np.any(y[:-1]*y[1:] < 0))


def profile_check(curve, objects, scene_end, hold, relevance_end=None):
    ts, xs = curve
    stop = float(ts[-1])
    if hold:
        tail = np.minimum(np.arange(1, 2001)*.001, 2.)+stop
        ts, xs = np.r_[ts, tail], np.r_[xs, np.full(2000, xs[-1])]
    end = float(ts[-1]+.5)
    selected = [o for o in objects if relevant(o, end if relevance_end is None else relevance_end)]
    truncated = scene_end+1e-7 < end or any(o['times'][0] > 1e-7 or o['times'][-1]+1e-7 < end for o in selected)
    if truncated:
        return dict(label='GT_TRUNCATED', end_s=end,
                    missing_tracks=[o['token'] for o in selected if o['times'][0] > 1e-7 or o['times'][-1]+1e-7 < end],
                    scene_end=scene_end+1e-7 < end)
    minimum, culprit = 1e4, None
    for obj in selected:
        ox = np.interp(ts+.5, obj['times'], obj['xs'])
        gaps = np.abs(ox-xs)-obj['length']-.5
        i = int(np.argmin(gaps))
        gap = float(gaps[i])
        if gap < minimum:
            minimum = gap
            at = float(ts[i]+.5)
            deviation = None if obj['x'] is None or obj['v'] is None else float(ox[i]-obj['x']-obj['v']*at)
            culprit = dict(object=obj['token'], time_from_t0_s=at,
                           gt_minus_constant_v_m=deviation,
                           deviation_status='measured' if deviation is not None else 'UNRESOLVED: no t0 velocity',
                           side='ahead' if ox[i] >= xs[i] else 'behind', in_w7_object_set=obj['in_w7'],
                           during_hold=bool(ts[i] > stop+1e-9))
    return dict(label='SAFE' if minimum >= 0 else 'UNSAFE', margin_m=minimum,
                culprit=culprit, stop_s=stop, end_s=end, relevant_objects=len(selected),
                entering_objects=sum(not o['in_w7'] for o in selected))


def oracle2(plan, objects, scene_end, hold=True, fixed_hold_relevance=False):
    profiles = []
    for k, (b, j) in enumerate(w.PAIRS):
        curve = w.float_profile(*plan, b, j)
        if curve is None:
            return dict(label='UNKNOWN', reason='negative_speed_nonfinite_or_60s_limit')
        check = profile_check(curve, objects, scene_end, hold,
                              float(curve[0][-1]+2.5) if fixed_hold_relevance else None)
        check['cid'] = k//3*4+k%3
        profiles.append(check)
        if check['label'] == 'SAFE':
            return dict(check, profiles=profiles)
    complete = [p for p in profiles if p['label'] == 'UNSAFE']
    if len(complete) == len(w.PAIRS):
        best = max(complete, key=lambda p: p['margin_m'])
        return dict(best, profiles=profiles)
    return dict(label='GT_TRUNCATED', profiles=profiles,
                reason='No complete SAFE profile; at least one candidate lacks full GT coverage')


def golden_objects(ego, records, cid, variant):
    tr = w.b4_mrmgen(ego.x, ego.v, ego.a, cid)
    horizon = tr.rows[-1][0]-tr.rows[0][0] if tr.rows else 0
    raw = sec.raw_objects(records) if variant == 'V0' else sec.reduce_neg(records, horizon, False)
    if raw is None:
        return tr, None
    return tr, w.propagated_objects(raw, 500000, 0) if all(0 <= o.v <= 20000000 for o in raw) else raw


def decomposition(ego, records, stored, variant):
    if variant == 'V0' and any(o['v'] is not None and o['v'] < 0 for o in records):
        return dict(cause='adapter_invalid_negative_velocity')
    if variant == 'V0':
        diag = next(d for d in stored['diagnostics'] if d['cid'] == stored['diagnostic_cid'])
    else:
        ds = []
        for cid in range(16):
            if cid % 4 == 3:
                continue
            tr, objs = golden_objects(ego, records, cid, variant)
            if objs is None:
                continue
            g = w.b3_geom(tr, objs, w.LANE)
            ds.append(dict(cid=cid, margin=g.margin, reason=g.reason, steps=g.steps))
        if not ds:
            return dict(cause='lane_or_other', reason='unknown_velocity')
        diag = max(ds, key=lambda d: d['margin'])
    if diag['reason'] != 'separation':
        return dict(cause='lane_or_other', diagnostic=diag)
    tr, objs = golden_objects(ego, records, diag['cid'], variant)
    singles = [(w.b3_geom(tr, (o,), w.LANE), i, o) for i, o in enumerate(objs)]
    failing = [(g, i, o) for g, i, o in singles if g.reason == 'separation']
    if not failing:
        return dict(cause='lane_or_other', reason='UNRESOLVED: no singleton separation', diagnostic=diag)
    # Golden exits on the first failing interval/object. Restrict to that interval,
    # then choose the minimum singleton margin, avoiding object-order attribution.
    step = min(g.steps for g, _, _ in failing)
    g, i, o = min((v for v in failing if v[0].steps == step), key=lambda v: (v[0].margin, v[1]))
    row = tr.rows[step-1]
    # Match B3's repeated outward rounding at every row, rather than one
    # multiplication by elapsed time (objects here all have zero acceleration).
    ox = o.x + sum(o.v*(b[0]-a[0])//1000000
                   for a, b in zip(tr.rows[:step-1], tr.rows[1:step]))
    ahead = ox >= row[2]
    return dict(cause='front_object_separation' if ahead else 'rear_object_separation',
                diagnostic=diag, culprit=records[i]['token'], side='ahead' if ahead else 'behind',
                singleton_margin=g.margin, interval=step)


roots = {}


def worker(shard, shards):
    start = time.monotonic()
    import pickle
    from data.nuscenes_lite import load_nuscenes
    root = Path(json.loads((HERE/'results/manifest.json').read_text())['dataset'])
    assert (root/'v1.0-trainval/_nuscenes_lite_v2.pkl').exists()
    nusc = load_nuscenes('v1.0-trainval', str(root))
    with (HERE/'annotation_categories.pkl').open('rb') as f:
        cats = pickle.load(f)
    scenes = sorted(nusc.scene, key=lambda s: (s['name'], s['token']))
    wanted = {s['name']: s for i, s in enumerate(scenes) if i % shards == shard}
    path = OUT/f'plans_{shard}.jsonl'
    done = set()
    if path.exists():
        with path.open(encoding='utf-8') as f:
            done = {(r['token'], r['plan']) for r in map(json.loads, f)}
    frames = defaultdict(list)
    with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        for row in map(json.loads, f):
            if row['odd'] and row['scene'] in wanted:
                frames[row['scene']].append(row)
    with path.open('a', encoding='utf-8', buffering=1) as ff:
        for name, scene in wanted.items():
            roots.clear()
            samples, pp, tt, aa, tracks = scene_tracks(nusc, scene, cats)
            indices = {s['token']: i for i, s in enumerate(samples)}
            for r in frames[name]:
                i = indices[r['token']]
                axis = np.array([math.cos(aa[i]), math.sin(aa[i])])
                side = np.array([-axis[1], axis[0]])
                objects = projected(tracks, pp[i], axis, side, tt[i], {o['token']: o for o in r['objects']})
                for plan, d in r['plans'].items():
                    if (r['token'], plan) in done:
                        continue
                    state = d['state_si']
                    ego = w.Ego(500000, *map(w.fixed, state), 0, 0)
                    ca = sec.va(ego, r['objects'])
                    cb = sec.va(ego, r['objects'], True)
                    o2 = oracle2(state, objects, float(tt[-1]-tt[i]))
                    stop_only = oracle2(state, objects, float(tt[-1]-tt[i]), False)
                    decisions = dict(V0=d['accept'], VA=ca != 15, VB=cb != 15)
                    record = dict(scene=name, token=r['token'], plan=plan, old=d['oracle']['label'],
                                  o2=o2, stop_only=stop_only['label'], decisions=decisions,
                                  adapter_valid=not bool(r['adapter_errors']), decomposition={})
                    if o2['label'] == 'SAFE':
                        for variant in ('V0', 'VA'):
                            if not decisions[variant]:
                                record['decomposition'][variant] = decomposition(ego, r['objects'], d, variant)
                    if o2['label'] == 'UNSAFE' and decisions['VA'] and not decisions['V0']:
                        # Evidence on the VA-selected curve as well as the best oracle curve.
                        b, j = w.PAIRS[ca//4*3+ca%4]
                        record['va_selected_profile'] = profile_check(w.float_profile(*state, b, j), objects, float(tt[-1]-tt[i]), True)
                        record['va_cid'] = ca
                    ff.write(json.dumps(record, allow_nan=False)+'\n')
            print(f'{name} complete; shard={shard}; elapsed={time.monotonic()-start:.1f}s', flush=True)
    dump(OUT/f'runtime_{shard}.json', dict(elapsed_s=time.monotonic()-start))


def summarize(runtime):
    records = []
    for path in sorted(OUT.glob('plans_*.jsonl')):
        with path.open(encoding='utf-8') as f:
            records.extend(map(json.loads, f))
    records.sort(key=lambda r: (r['scene'], r['token'], r['plan']))
    assert len({(r['token'], r['plan']) for r in records}) == len(records)
    with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        frames = [json.loads(l) for l in f]
    assert len(records) == sum(len(r['plans']) for r in frames)
    names = sorted({r['scene'] for r in frames})
    idx = {s: i for i, s in enumerate(names)}
    draws = np.random.default_rng(w.SEED).multinomial(len(names), np.full(len(names), 1/len(names)), size=2000)
    def rate(lst, num, den):
        nn, dd = np.zeros(len(names)), np.zeros(len(names))
        for r in lst:
            nn[idx[r['scene']]] += int(num(r))
            dd[idx[r['scene']]] += int(den(r))
        bn, bd = draws@nn, draws@dd
        valid = bd > 0
        return dict(n=int(nn.sum()), denominator=int(dd.sum()), rate=float(nn.sum()/dd.sum()) if dd.sum() else None,
                    ci95=np.percentile(bn[valid]/bd[valid], [2.5,97.5]).tolist() if valid.any() else [None,None],
                    valid_bootstrap_draws=int(valid.sum()))
    result = dict(post_hoc=True, status='COMPLETE', runtime_wall_seconds=runtime, plans=len(records),
                  runtime_scope='Successful resumed orchestration, including dataset loading and replay. Earlier failed attempt duration: UNRESOLVED (not timed persistently).',
                  oracle_config=dict(step_s=.001, latency_s=.5, reaction_s=.1, reserve_m=.5, hold_s=2.,
                                     candidate_ids=[k//3*4+k%3 for k in range(len(w.PAIRS))],
                                     relevance='Any observed corridor intersection in [t0,candidate end], retain for entire window; includes later entrants and future-born tracks.',
                                     interpolation='Full linked annotated tracks; no extrapolation; complete coverage t0 through candidate end required.',
                                     plan_label='First complete SAFE candidate; UNSAFE only when every candidate has complete GT and fails; otherwise GT_TRUNCATED. Invalid float plans UNKNOWN.',
                                     combined_half_length='(4.8+t0 annotation length)/2; earliest annotation size for future-born tracks'),
                  bootstrap=dict(unit='scene', scenes=len(names), replicates=2000, seed=w.SEED,
                                 draws='W7 multinomial; identical draws across every metric'),
                  count_flow={}, metrics={}, decomposition={}, paired={}, hold_conversions={},
                  oracle_transition={}, newly_accepted_unsafe=[], validation={})
    secondary = json.loads((HERE/'results/secondary.json').read_text())
    for p in 'HTU':
        lst = [r for r in records if r['plan'] == p]
        labs = Counter(r['o2']['label'] for r in lst)
        valid = [r for r in lst if r['adapter_valid']]
        result['count_flow'][p] = dict(eligible_keyframes=len(frames), odd_keyframes=sum(r['odd'] for r in frames),
                                      odd_plans=len(lst), adapter_valid_V0=len(valid),
                                      o2_all_ODD={l:labs[l] for l in LABELS},
                                      o2_adapter_valid_V0={l:sum(r['o2']['label']==l for r in valid) for l in LABELS},
                                      denominator_note='Acceptance: all ODD plans; FR: SAFE; FA: UNSAFE, including adapter-invalid plans; UNKNOWN/truncated excluded only from oracle denominators. U exists only with a front object at t0.')
        result['oracle_transition'][p] = dict(Counter(r['old']+'->'+r['o2']['label'] for r in lst))
        result['hold_conversions'][p] = dict(old_SAFE_to_O2_UNSAFE=sum(r['old']=='SAFE' and r['o2']['label']=='UNSAFE' for r in lst),
            attributable_to_hold=sum(r['old']=='SAFE' and r['o2']['label']=='UNSAFE' and r['stop_only_aligned_relevance']=='SAFE' for r in lst))
        for variant in ('V0','VA','VB'):
            result['metrics'].setdefault(variant,{})[p] = {}
            for oracle in ('old','O2'):
                lab = lambda r: r['old'] if oracle=='old' else r['o2']['label']
                ac = lambda r: r['decisions'][variant]
                m = dict(acceptance=rate(lst, ac, lambda r:True),
                         false_reject=rate(lst, lambda r:lab(r)=='SAFE' and not ac(r), lambda r:lab(r)=='SAFE'),
                         false_accept=rate(lst, lambda r:lab(r)=='UNSAFE' and ac(r), lambda r:lab(r)=='UNSAFE'),
                         decisions_by_oracle_label={l:dict(accept=sum(lab(r)==l and ac(r) for r in lst),
                             reject=sum(lab(r)==l and not ac(r) for r in lst)) for l in LABELS})
                result['metrics'][variant][p][oracle] = m
            old = result['metrics'][variant][p]['old']
            s = secondary['variants'][variant][p]
            assert (old['acceptance']['n'], old['false_reject']['n'], old['false_accept']['n']) == (s['accept'],s['false_reject'],s['false_accept']), (variant,p,'secondary mismatch')
        for variant in ('V0','VA'):
            fr = [r for r in lst if variant in r['decomposition']]
            counts = Counter(r['decomposition'][variant]['cause'] for r in fr)
            result['decomposition'].setdefault(variant,{})[p] = dict(total=len(fr), causes={c:dict(n=counts[c], pct=100*counts[c]/len(fr) if fr else None) for c in ('adapter_invalid_negative_velocity','rear_object_separation','front_object_separation','lane_or_other')})
        result['paired'][p] = {l:dict(accept_to_reject=sum(r['o2']['label']==l and r['decisions']['V0'] and not r['decisions']['VA'] for r in lst), reject_to_accept=sum(r['o2']['label']==l and not r['decisions']['V0'] and r['decisions']['VA'] for r in lst)) for l in LABELS}
    for r in records:
        if 'va_selected_profile' in r:
            result['newly_accepted_unsafe'].append({k:r[k] for k in ('scene','token','plan','va_cid','va_selected_profile','o2')})
    result['validation']['secondary_all_count_matches'] = True
    manifest=json.loads((HERE/'results/manifest.json').read_text())
    result['validation']['primary_code_matches_W7_manifest']=w.sha(HERE/'run_w7.py')==manifest['code_sha256']
    result['validation']['protocol_matches_W7_manifest']=w.sha(HERE/'PROTOCOL.md')==manifest['protocol_sha256']
    for name in ('selftest','validation','hold_validation'):
        path=OUT/(name+'.json')
        if path.exists():
            result['validation'][name]=json.loads(path.read_text())
    result['provenance'] = {os.path.relpath(p,HERE):w.sha(p) for p in (HERE/'run_w7.py', HERE/'w7_secondary.py', HERE/'results/manifest.json', HERE/'results/secondary.json', HERE/'results/frames.jsonl', HERE.parent/'golden/tsmx_golden/model.py', Path(__file__), OUT/'audit_w7b.py', OUT/'hold_audit.py')}
    dump(OUT/'results.json',result)
    report(result)
    print(json.dumps(dict(plans=len(records),runtime_s=runtime,flow=result['count_flow'])),flush=True)


def report(r):
    def fmt(m):
        if m['rate'] is None:
            return 'N/A (0 denominator)'
        return f"{100*m['rate']:.2f}% [{100*m['ci95'][0]:.2f},{100*m['ci95'][1]:.2f}] ({m['n']}/{m['denominator']})"
    lines=['# W7b aligned-horizon remeasurement — POST HOC', '',
           'Primary W7 results, golden and proof unchanged. Offline estimators retain A7 lookahead.',
           'O2: independent float 1 ms, original plan, apply t0+0.5 s, reaction 0.1 s, 0.5 m reserve; W7 finite-jerk library order.',
           'Checks apply through exact float stop + 2 s stationary hold. No GT extrapolation or last-pose holding.',
           'Relevance: all scene vehicle/human/cycle tracks intersecting |y|<=1.8+width/2 at any time in [t0,end], including later entrants; then retain them throughout.',
           'Full linked annotations are interpolated in fixed t0 ego axes with W7 axis-aligned footprints; retain t0 combined half-length (earliest size for future-born tracks).',
           'Each candidate needs scene and relevant-track coverage from t0 through its end. SAFE: a complete safe candidate; UNSAFE: all complete and unsafe; otherwise GT_TRUNCATED.',
           'UNKNOWN: invalid float plan or >60 s stop. Missing tracks take precedence over collision evidence for that candidate.',
           'No t0 longitudinal range cap. Golden variants retain W7 objects; VB drops rear objects as the existing ablation.', '',
           '|Variant/plan|Acceptance (both)|Old FR / SAFE|O2 FR / SAFE|Old FA / UNSAFE|O2 FA / UNSAFE|',
           '|---|---|---|---|---|---|']
    for v in ('V0','VA','VB'):
        for p in 'HTU':
            m=r['metrics'][v][p]
            lines.append('|'+v+'/'+p+'|'+'|'.join([fmt(m['O2']['acceptance']),fmt(m['old']['false_reject']),fmt(m['O2']['false_reject']),fmt(m['old']['false_accept']),fmt(m['O2']['false_accept'])])+'|')
    lines += ['', 'CI: original W7 scene bootstrap (all scenes), 2000 shared multinomial draws, seed 20261104. Secondary report CIs used a different sampler; counts must match.',
              'Count flow H/T/U: eligible keyframes -> ODD keyframes -> generated plans -> V0 adapter-valid; O2 labels below cover all generated ODD plans.', '']
    for p,c in r['count_flow'].items():
        lines.append(f"- {p}: {c['eligible_keyframes']} -> {c['odd_keyframes']} -> {c['odd_plans']} -> {c['adapter_valid_V0']}; SAFE/UNSAFE/UNKNOWN/TRUNCATED="+'/'.join(str(c['o2_all_ODD'][l]) for l in LABELS)+'.')
    lines += ['', 'Acceptance denominator includes every ODD plan; FR uses SAFE, FA uses UNSAFE, including adapter-invalid. UNKNOWN/truncated are excluded only from oracle denominators.',
              'O2 FR/FA describe the labelable subset; GT_TRUNCATED is a separate unresolved class. Per-label accepted/rejected counts are in results.json.',
              'FR first-cause priority: negative-velocity adapter (V0), rear separation, front separation, lane/other. Selected diagnostic = greatest-margin finite-jerk candidate.',
              'Separation side: minimum singleton golden margin in the earliest failing interval of that diagnostic; ahead/behind at interval start. Details are in plans_*.jsonl.', '']
    for v in ('V0','VA'):
        for p,d in r['decomposition'][v].items():
            lines.append(f"- {v}/{p} FR={d['total']}: "+'; '.join(c.replace('_object_separation','').replace('adapter_invalid_negative_velocity','adapter')+f" {m['n']} ({m['pct']:.2f}%)" if m['pct'] is not None else c+' 0 (N/A)' for c,m in d['causes'].items())+'.')
    lines.append('')
    lines.append('Old SAFE -> O2 UNSAFE / isolated hold conversions H/T/U (remove hold, retain each candidate\'s full-window relevance set): '+'; '.join(p+f" {c['old_SAFE_to_O2_UNSAFE']}/{c['attributable_to_hold']}" for p,c in r['hold_conversions'].items())+'.')
    lines.append('Paired V0->VA changes by O2 label (accept->reject / reject->accept): '+'; '.join(p+' '+', '.join(l+f" {c['accept_to_reject']}/{c['reject_to_accept']}" for l,c in per.items()) for p,per in r['paired'].items())+'.')
    lines.append(f"Every newly VA-accepted O2-UNSAFE plan ({len(r['newly_accepted_unsafe'])}) is listed with scene/token/plan, culprit and GT-minus-constant-v in results.json:newly_accepted_unsafe.")
    lines += ['Reuse citations: ../run_w7.py:30 (12 finite-jerk cids in the 16-entry library), :168 (scene poses), :189 (categories/footprints), :234 (float profile), :302 (encoding), :501 (bootstrap); ../w7_secondary.py:51 (reduction), :72 (VA/VB); ../../golden/tsmx_golden/model.py:439 (diagnostics).',
              f"Status COMPLETE; measured orchestration wall runtime {r['runtime_wall_seconds']:.1f} s; secondary aggregate count replay verified. Full counts, CIs, transitions, paired cases and input/code hashes: results.json.",
              'Runtime covers the successful resumed invocation; duration of the earlier failed diagnostic replay is UNRESOLVED (not timed persistently).',
              'Reproduce: native W7 Python, `python -B tsmx_hw/eval_nuscenes/w7b/run_w7b.py`; workers resume only within w7b.']
    assert len(lines)<=50, len(lines)
    (OUT/'W7B_REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')


def selftest():
    curve=w.float_profile(0.,10.,0.,2.,2.)
    assert abs(curve[0][-1]-5.6)<1e-9
    assert oracle2((0.,0.,0.),[],10)['label']=='SAFE'
    assert oracle2((0.,0.,0.),[],1)['label']=='GT_TRUNCATED'
    assert oracle2((0.,-1.,0.),[],10)['label']=='UNKNOWN'
    obj=dict(token='rear',times=np.array([0.,10.]),xs=np.array([-10.,10.]),ys=np.zeros(2),widths=np.ones(2),length=4.8,x=-10.,v=2.,in_w7=True)
    assert profile_check(w.float_profile(0.,0.,0.,2.,2.),[obj],10,False)['label']=='SAFE'
    obj['xs']=np.array([-6.,14.]); obj['x']=-6.
    assert profile_check(w.float_profile(0.,0.,0.,2.,2.),[obj],10,True)['label']=='UNSAFE'
    obj['ys']=np.array([-10.,10.])
    assert relevant(obj,10)
    obj['times']=np.array([0.,1.])
    assert profile_check(w.float_profile(0.,0.,0.,2.,2.),[obj],10,True)['label']=='GT_TRUNCATED'
    obj.update(times=np.array([0.,10.]),xs=np.array([1.,1.]),ys=np.array([10.,-30.]),x=1.,v=0.,in_w7=False)
    assert oracle2((0.,0.,0.),[obj],10,False)['label']=='SAFE'
    assert oracle2((0.,0.,0.),[obj],10,False,True)['label']=='UNSAFE'
    dump(OUT/'selftest.json',dict(analytic_stop=True,empty_scene=True,scene_truncation=True,negative_speed=True,hold_collision=True,corridor_crossing=True,lost_track_truncation=True,fixed_relevance_hold_counterfactual=True))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--shard',type=int)
    parser.add_argument('--shards',type=int,default=3)
    parser.add_argument('--summarize',action='store_true',help='Rebuild aggregate files from a completed replay')
    args=parser.parse_args()
    if args.summarize:
        prior=json.loads((OUT/'results.json').read_text())
        start=time.monotonic()
        selftest()
        from hold_audit import main as hold_audit
        hold_audit()
        from audit_w7b import main as audit
        audit()
        summarize(prior['runtime_wall_seconds'])
        latest=json.loads((OUT/'results.json').read_text())
        latest['runtime_wall_seconds'] += time.monotonic()-start
        dump(OUT/'results.json',latest)
        report(latest)
    elif args.shard is not None:
        worker(args.shard,args.shards)
    else:
        import ctypes
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
        start=time.monotonic()
        selftest()
        children=[]
        logs=[]
        for i in range(args.shards):
            log=(OUT/f'worker_{i}.log').open('w',encoding='utf-8')
            logs.append(log)
            children.append(subprocess.Popen([sys.executable,'-B',str(Path(__file__)), '--shard',str(i),'--shards',str(args.shards)],stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW))
        codes=[p.wait() for p in children]
        for log in logs:
            log.close()
        assert codes==[0]*args.shards,codes
        from hold_audit import main as hold_audit
        hold_audit()
        from audit_w7b import main as audit
        audit()
        summarize(time.monotonic()-start)
