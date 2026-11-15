"""Preregistered W7, Windows/Python 3.9, annotation-only open-loop evaluation."""
import sys
sys.dont_write_bytecode = True
import os
from pathlib import Path
HERE = Path(__file__).resolve().parent
BASE = HERE.parents[2]
os.environ.setdefault('OMP_NUM_THREADS', '1')
os.environ.setdefault('MKL_NUM_THREADS', '1')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
os.environ['TEMP'] = os.environ['TMP'] = str(HERE)
sys.path[:0] = [str(BASE / 'eval'), str(HERE.parent / 'golden')]
import argparse
import hashlib
import json
import math
import pickle
import time
from datetime import datetime, timezone
from dataclasses import asdict
from collections import Counter
import numpy as np
from tsmx_golden.model import (Ego, Motion, propagated_objects, select_world,
                              b4_mrmgen, b3_geom)

SEED = 20261104
LANE = (-1800000, 1800000)
PAIRS = [(b, j) for b in (2., 4., 6., 8.) for j in (2., 4., 8.)]
CKPT = Path('F:/vla_archive_2026-10-29/eval/archived_weights/qat_full_bert_gru_120ep.pt')


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(4 << 20), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')
    os.replace(tmp, path)


def stream_array(path):
    """Incremental standard-library JSON decoder; no dataset-side cache writes."""
    dec = json.JSONDecoder()
    with open(path, encoding='utf-8') as f:
        buf, pos, eof = '', 0, False
        while True:
            while pos < len(buf) and buf[pos] in ' \r\n\t[,':
                pos += 1
            if pos < len(buf) and buf[pos] == ']':
                return
            try:
                obj, end = dec.raw_decode(buf, pos)
            except json.JSONDecodeError:
                if eof:
                    raise
                buf = buf[pos:] + f.read(4 << 20)
                pos = 0
                eof = f.tell() == os.fstat(f.fileno()).st_size
                continue
            yield obj
            pos = end


def add_categories(nusc, root):
    cache = HERE / 'annotation_categories.pkl'
    if cache.exists():
        with cache.open('rb') as f:
            cats = pickle.load(f)
    else:
        folder = root / 'v1.0-trainval'
        categories = {r['token']: r['name'] for r in json.loads((folder / 'category.json').read_text())}
        instances = {r['token']: categories[r['category_token']]
                     for r in json.loads((folder / 'instance.json').read_text())}
        cats = {r['token']: instances[r['instance_token']]
                for r in stream_array(folder / 'sample_annotation.json')}
        tmp = cache.with_suffix('.tmp')
        with tmp.open('wb') as f:
            pickle.dump(cats, f, protocol=4)
        os.replace(tmp, cache)
    assert len(cats) == len(nusc._sample_annotation)
    for token, ann in nusc._sample_annotation.items():
        ann['category_name'] = cats[token]


def model_load(nusc):
    import torch
    from model.fp32_model import build_model
    from model.w4a8_inference import W4A8PlanningModel
    from data.nuscenes_loader import load_nuscenes_samples
    torch.set_num_threads(1)
    digest = sha(CKPT)
    cache = HERE / 'w4a8_derived.pkl'
    if cache.exists():
        with cache.open('rb') as f:
            stored = pickle.load(f)
        assert stored['checkpoint_sha256'] == digest
        return stored['model'], digest
    print('Loading original QAT checkpoint (read-only)', flush=True)
    ckpt = torch.load(str(CKPT), map_location='cpu')
    fp = build_model()
    sd = ckpt['model'] if 'model' in ckpt else ckpt
    missing = set(fp.state_dict()) - set(sd)
    assert missing in (set(), {'decoder.wp_proj.weight', 'decoder.wp_proj.bias'}), missing
    for name in missing:
        sd[name] = torch.zeros_like(fp.state_dict()[name])
    fp.load_state_dict(sd, strict=True)
    fp.eval()
    del ckpt
    tokens, masks, _ = load_nuscenes_samples(nusc, num_scenes=200, split='train',
                    scene_offset=0, samples_per_scene=1, include_lane_tokens=True)
    model = W4A8PlanningModel.from_fp32(fp, tokens, masks, symmetric_acts=True)
    tmp = cache.with_suffix('.tmp')
    with tmp.open('wb') as f:
        pickle.dump({'checkpoint_sha256': digest, 'model': model}, f, protocol=4)
    os.replace(tmp, cache)
    return model, digest


def enable_exact_blas(model):
    """INT8*INT4 sums fit exactly in binary32; leave all other inference intact."""
    import model.w4a8_inference as module
    original = module.int4x8_matmul_int32
    weights = {}
    def fast(w, x):
        assert x.shape[-1] == w.shape[-1] and x.shape[-1]*128*8 < 2**24
        if id(w) not in weights:
            assert np.min(w) >= -8 and np.max(w) <= 7
            weights[id(w)] = (w, w.astype(np.float32))
        assert np.min(x) >= -128 and np.max(x) <= 127
        return (x.astype(np.float32) @ weights[id(w)][1].T).astype(np.int32)
    rng = np.random.default_rng(SEED)
    for dim in (512, 2048):
        w = rng.integers(-8, 8, (512, dim), dtype=np.int8)
        x = rng.integers(-128, 128, (64, dim), dtype=np.int8)
        assert np.array_equal(original(w, x), fast(w, x)), 'INT4x8 BLAS mismatch'
    x = rng.normal(0, 10, (2, 64, 6)).astype(np.float32)
    mask = np.zeros((2, 64), dtype=bool)
    mask[1, 10:] = True
    before = model.forward(x, mask)
    module.int4x8_matmul_int32 = fast
    after = model.forward(x, mask)
    assert np.array_equal(before, after), 'Full W4A8 forward mismatch'
    # Analytical oracle checks, independent of golden.
    tt, xx = float_profile(0., 10., 0., 2., 2.)
    assert abs(tt[-1]-5.6) < 1e-9 and abs(xx[-1]-(1+10-1/3+81/4)) < 1e-9
    assert np.all(np.diff(xx) >= -1e-9)
    assert oracle((0., 5., 0.), [])['label'] == 'SAFE'
    overlap = {'token': 'synthetic', 'times': [0., 3.], 'xs': [1., 1.],
               'length': 4.8, 'x': 1., 'v': 0., 'track_ends_early': False}
    assert oracle((0., 5., 0.), [overlap])['label'] == 'UNSAFE'
    return {'int4x8_random_shapes_exact': True, 'full_forward_exact': True,
            'waypoints': after.tolist(), 'oracle_analytic_stop': True,
            'oracle_empty_world_and_overlap': True}


def yaw(q):
    w, x, y, z = q
    return math.atan2(2*(w*z+x*y), 1-2*(y*y+z*z))


def scene_data(nusc, scene):
    samples, positions, angles = [], [], []
    token = scene['first_sample_token']
    while token:
        s = nusc.get('sample', token)
        ep = nusc.get('ego_pose', nusc.get('sample_data', s['data']['LIDAR_TOP'])['ego_pose_token'])
        samples.append(s)
        positions.append(ep['translation'][:2])
        angles.append(yaw(ep['rotation']))
        token = s['next']
    p = np.asarray(positions)
    t = np.asarray([s['timestamp'] for s in samples], dtype=np.float64)*1e-6
    v = np.full_like(p, np.nan)
    a = np.full_like(p, np.nan)
    for i in range(1, len(p)-1):
        dl, dr = t[i]-t[i-1], t[i+1]-t[i]
        v[i] = (p[i+1]-p[i-1])/(dl+dr)
        a[i] = 2*((p[i+1]-p[i])/dr-(p[i]-p[i-1])/dl)/(dl+dr)
    return samples, p, t, np.asarray(angles), v, a


def objects_at(nusc, sample, origin, axis, side):
    records = []
    errors = []
    for token in sample['anns']:
        ann = nusc.get('sample_annotation', token)
        cat = ann['category_name']
        if not (cat.startswith(('vehicle.', 'human.')) or 'cycle' in cat):
            continue
        delta = np.asarray(ann['translation'][:2])-origin
        x, y = float(delta @ axis), float(delta @ side)
        if abs(y) > 1.8 + ann['size'][0]/2:
            continue
        first = nusc.get('sample_annotation', ann['prev']) if ann['prev'] else ann
        last = nusc.get('sample_annotation', ann['next']) if ann['next'] else ann
        dt = (nusc.get('sample', last['sample_token'])['timestamp']-
              nusc.get('sample', first['sample_token'])['timestamp'])*1e-6
        vel = float((np.asarray(last['translation'][:2])-first['translation'][:2]) @ axis / dt) if dt > 0 else None
        length = (4.8 + ann['size'][1])/2
        err = ('object_velocity_unknown' if vel is None else
               'object_range' if not (0 <= vel <= 20 and 0 < length <= 20 and abs(x) <= 10000) else None)
        if err:
            errors.append({'token': token, 'reason': err, 'v': vel})
        times, xs = [], []
        cur = ann
        while True:
            rel = (nusc.get('sample', cur['sample_token'])['timestamp']-sample['timestamp'])*1e-6
            times.append(rel)
            xs.append(float((np.asarray(cur['translation'][:2])-origin) @ axis))
            if rel >= 3 or not cur['next']:
                break
            cur = nusc.get('sample_annotation', cur['next'])
        # Explicit knot at 3 seconds, hold there beyond 3 seconds.
        at3 = float(np.interp(3., times, xs))
        keep = [k for k, tt in enumerate(times) if tt < 3.]
        end_early = times[-1] < 3.
        times = [times[k] for k in keep] + [3.]
        xs = [xs[k] for k in keep] + [at3]
        records.append({'token': token, 'category': cat, 'x': x, 'y': y, 'v': vel,
                        'length': length, 'times': times, 'xs': xs, 'track_ends_early': end_early})
    records.sort(key=lambda r: (abs(r['x']), r['token']))
    if len(records) > 32:
        errors.append({'reason': 'object_overflow', 'count': len(records)})
    return records, errors


def float_profile(x0, v0, a0, b, j):
    """Independent capped jerk integration; exact float stop + 1 ms samples."""
    if not all(math.isfinite(z) for z in (x0, v0, a0)) or v0 < 0:
        return None
    if v0 == 0 and a0 <= 0:
        return np.array([0.]), np.array([x0])
    ramp = abs(a0+b)/j
    jerk = -j if a0 > -b else j
    def state(t):
        prefix = np.minimum(t, .1)
        u = np.clip(np.asarray(t)-.1, 0, ramp)
        tail = np.maximum(np.asarray(t)-.1-ramp, 0)
        vp = v0 + a0*prefix
        xp = x0 + v0*prefix + .5*a0*prefix**2
        vr = vp + a0*u + .5*jerk*u*u
        xr = xp + vp*u + .5*a0*u*u + jerk*u**3/6
        return xr+vr*tail-.5*b*tail**2, vr-b*tail
    if a0 < 0 and v0/(-a0) <= .1:
        stop = v0/(-a0)
    elif state(.1+ramp)[1] <= 0:
        lo, hi = .1, .1+ramp
        for _ in range(48):
            mid = (lo+hi)/2
            if state(mid)[1] > 0:
                lo = mid
            else:
                hi = mid
        stop = hi
    else:
        stop = .1+ramp+float(state(.1+ramp)[1])/b
    if stop > 60 or not math.isfinite(stop):
        return None
    ts = np.minimum(np.arange(int(math.ceil(stop/.001))+1)*.001, stop)
    return ts, state(ts)[0]


def oracle(plan, records):
    best, culprit = -1e30, None
    for k, (b, j) in enumerate(PAIRS):
        curve = float_profile(*plan, b, j)
        if curve is None:
            return {'label': 'UNKNOWN', 'reason': 'negative_speed_or_horizon'}
        ts, xs = curve
        minimum, who, at, error = 1e4, None, 0., 0.
        for obj in records:
            ox = np.interp(ts+.5, obj['times'], obj['xs'])
            gaps = np.abs(ox-xs)-obj['length']-.5
            idx = int(np.argmin(gaps))
            gap = float(gaps[idx])
            if gap < minimum:
                minimum, who, at = gap, obj['token'], float(ts[idx]+.5)
                pred = obj['x']+(obj['v'] or 0)*at
                error = float(ox[idx]-pred)
        if minimum > best:
            best = minimum
            culprit = {'object': who, 'time_from_t0_s': at, 'gt_minus_constant_v_m': error}
        if minimum >= 0:
            return {'label': 'SAFE', 'cid': k//3*4+k%3, 'margin_m': minimum,
                    'stop_s': float(ts[-1])}
    return {'label': 'UNSAFE', 'best_margin_m': best, 'culprit': culprit,
            'reason': 'No finite-jerk profile clears GT tracks; constant-v mismatch and/or footprint overlap',
            'track_ends_early': any(o['track_ends_early'] for o in records)}


def fixed(value):
    return int(round(float(value)*1000000))


def evaluate_plan(plan, records, errors):
    x, v, a = plan
    ego = Ego(500000, fixed(x), fixed(v), fixed(a), 0, 0)
    raw = tuple(Motion(fixed(o['x']), fixed(o['v']) if o['v'] is not None else -1,
                       0, fixed(o['length']), 0, 0) for o in records)
    # Preserve invalid values in diagnostics; never send invalid motion into advance.
    can_propagate = all(0 <= o.v <= 20000000 for o in raw)
    objects = propagated_objects(raw, 500000, 0) if can_propagate else raw
    diagnostics = []
    cid, reason = select_world(ego, objects, LANE)
    if errors:
        assert cid == 15, 'Invalid object adapter input must fail closed'
    for cc in range(16):
        if cc % 4 == 3:
            continue
        tr = b4_mrmgen(ego.x, ego.v, ego.a, cc)
        geom = b3_geom(tr, objects, LANE)
        diagnostics.append({'cid': cc, 'accept': geom.accept, 'margin': geom.margin,
                            'reason': geom.reason, 'rows': len(tr.rows), 'steps': geom.steps})
        if cc == cid:
            break
    diag = next((d for d in diagnostics if d['cid'] == cid),
                max(diagnostics, key=lambda d: d['margin']))
    margin, rows, gcid = diag['margin'], diag['rows'], diag['cid']
    result = {'state_si': list(map(float, plan)), 'accept': cid != 15, 'cid': cid,
              'margin': margin, 'reason': reason, 'rows': rows, 'diagnostic_cid': gcid,
              'diagnostic_reason': diag['reason'],
              'diagnostics': diagnostics, 'oracle': oracle(plan, records)}
    vector = {'ego': asdict(ego), 'objects': [asdict(o) for o in objects], 'lane': list(LANE),
              'adapter_errors': errors, 'select_world_called': True,
              'propagation_done': can_propagate,
              'expected': {k: result[k] for k in ('accept', 'cid', 'margin', 'reason', 'rows')}}
    return result, vector


def evaluate_frame(nusc, model, data, i):
    from data.nuscenes_loader import build_tokens_for_sample
    samples, p, times, angles, vg, ag = data
    sample = samples[i]
    axis = np.array([math.cos(angles[i]), math.sin(angles[i])])
    side = np.array([-axis[1], axis[0]])
    row = {'scene': nusc.get('scene', sample['scene_token'])['name'], 'token': sample['token'],
           'timestamp': sample['timestamp'], 'odd': False, 'plans': {}}
    if i == 0:
        row['exclusion'] = 'central_difference_unavailable'
        return row, None
    v, a = float(vg[i] @ axis), float(ag[i] @ axis)
    future = p[i:i+7]-p[i]
    lateral = float(np.max(np.abs(future @ side)))
    heading = float(np.max(np.abs(np.arctan2(np.sin(angles[i:i+7]-angles[i]), np.cos(angles[i:i+7]-angles[i]))))*180/math.pi)
    row.update(v_est_mps=v, a_est_mps2=a, lateral_m=lateral, heading_deg=heading)
    if not (0 <= v <= 10 and -8 <= a <= 2 and lateral <= 1 and heading <= 10):
        row['exclusion'] = 'odd_filter'
        return row, None
    row['odd'] = True
    records, errors = objects_at(nusc, sample, p[i], axis, side)
    row.update(object_count=len(records), adapter_errors=errors,
               objects=records, object_overflow=len(records) > 32)
    tokens, mask = build_tokens_for_sample(nusc, sample['token'], include_lane_tokens=True)
    wp = model.forward(tokens[None], mask[None])[0]
    assert np.isfinite(wp).all(), 'nonfinite model output'
    row['traj_waypoints'] = wp.tolist()
    plans = {'H': (float((p[i+1]-p[i]) @ axis), float(vg[i+1] @ axis), float(ag[i+1] @ axis)),
             'T': (float(wp[0, 0]), float(wp[1, 0]), float((wp[1, 0]-2*wp[0, 0])/.25))}
    if any(o['x'] > 0 for o in records):
        plans['U'] = (.5*v+.25, v+1, 2.)
    vectors = {}
    for label, plan in plans.items():
        row['plans'][label], vectors[label] = evaluate_plan(plan, records, errors)
    return row, {'scene': row['scene'], 'token': row['token'], 'plans': vectors}


def recover(path):
    if not path.exists():
        return []
    data = path.read_bytes()
    end = data.rfind(b'\n')+1
    if end != len(data):
        with path.open('r+b') as f:
            f.truncate(end)
    rows = [json.loads(line) for line in data[:end].splitlines()]
    assert len({r['token'] for r in rows}) == len(rows), 'duplicate frames'
    return rows


def summarize(rows, scene_names, total_eligible, total_keyframes):
    index = {s: i for i, s in enumerate(scene_names)}
    rng = np.random.default_rng(SEED)
    draws = rng.multinomial(len(scene_names), np.full(len(scene_names), 1/len(scene_names)), size=2000)
    def rate(num, den):
        nums, dens = np.zeros(len(index)), np.zeros(len(index))
        for scene, nn, dd in zip(scene_names, num, den):
            nums[index[scene]], dens[index[scene]] = nn, dd
        bn, bd = draws @ nums, draws @ dens
        valid = bd > 0
        intervals = np.percentile(bn[valid]/bd[valid], [2.5, 97.5]).tolist() if valid.any() else [None, None]
        return {'n': int(nums.sum()), 'denominator': int(dens.sum()),
                'rate': float(nums.sum()/dens.sum()) if dens.sum() else None,
                'ci95': intervals, 'valid_bootstrap_draws': int(valid.sum())}
    def grouped_rate(entries, numfn, denfn):
        nn, dd = Counter(), Counter()
        for scene, item in entries:
            nn[scene] += int(numfn(item))
            dd[scene] += int(denfn(item))
        return rate([nn[s] for s in scene_names], [dd[s] for s in scene_names])
    def stats(subset):
        result = {}
        for label in ('H', 'T', 'U'):
            entries = [(r['scene'], r['plans'][label]) for r in subset if label in r['plans']]
            safe = lambda p: p['oracle']['label'] == 'SAFE'
            unsafe = lambda p: p['oracle']['label'] == 'UNSAFE'
            result[label] = {
                'acceptance': grouped_rate(entries, lambda p: p['accept'], lambda p: True),
                'false_reject': grouped_rate(entries, lambda p: safe(p) and not p['accept'], safe),
                'false_accept': grouped_rate(entries, lambda p: unsafe(p) and p['accept'], unsafe),
                'false_accept_per_accept': grouped_rate(entries, lambda p: unsafe(p) and p['accept'], lambda p: p['accept']),
                'oracle_unknown': sum(p['oracle']['label'] == 'UNKNOWN' for _, p in entries)}
            if label == 'U':
                result[label]['recall'] = grouped_rate(entries, lambda p: unsafe(p) and not p['accept'], unsafe)
        return result
    odd = [r for r in rows if r['odd']]
    coverage = grouped_rate([(r['scene'], r) for r in rows], lambda r: r['odd'], lambda r: True)
    failures = []
    for r in odd:
        for label, plan in r['plans'].items():
            if plan['accept'] and plan['oracle']['label'] == 'UNSAFE':
                failures.append({'scene': r['scene'], 'token': r['token'], 'plan': label,
                                 'cid': plan['cid'], 'golden_margin': plan['margin'],
                                 'oracle': plan['oracle']})
    return {'complete': len(rows) == total_eligible, 'processed_frames': len(rows),
            'total_eligible': total_eligible, 'total_keyframes': total_keyframes,
            'scenes_total': len(scene_names), 'scenes_processed': len({r['scene'] for r in rows}),
            'odd_frames': len(odd), 'odd_coverage': coverage,
            'odd_coverage_all_keyframes': len(odd)/total_keyframes,
            'object_overflow_frames': sum(r.get('object_overflow', False) for r in odd),
            'adapter_error_frames': sum(bool(r.get('adapter_errors')) for r in odd),
            'exclusions': dict(Counter(r.get('exclusion', 'none') for r in rows)),
            'metrics': stats(odd), 'by_speed': {
                name: stats([r for r in odd if lo <= r['v_est_mps'] < hi])
                for name, lo, hi in [('0-2', 0, 2), ('2-5', 2, 5), ('5-10', 5, 10.000001)]},
            'by_object_count': {name: stats([r for r in odd if lo <= r['object_count'] <= hi])
                for name, lo, hi in [('0', 0, 0), ('1-4', 1, 4), ('5-16', 5, 16), ('17+', 17, 100000)]},
            'false_accept_cases': failures, 'bootstrap': {'unit': 'scene', 'replicates': 2000, 'seed': SEED}}


def report(summary, output):
    def fmt(m):
        if m['rate'] is None:
            return 'N/A (0 denominator)'
        lo, hi = m['ci95']
        return f"{100*m['rate']:.2f}% [{100*lo:.2f}, {100*hi:.2f}] ({m['n']}/{m['denominator']})"
    lines = ['# W7 — nuScenes trainval, open-loop', '',
        f"Status: {'COMPLETE' if summary['complete'] else 'INCOMPLETE'}; T = checkpoint W4A8, no GT substitution.",
        f"Frames: {summary['processed_frames']}/{summary['total_eligible']} eligible; {summary['total_keyframes']} keyframes; {summary['scenes_total']} scenes.",
        'Ego v/a are central-difference estimates from ego_pose; not CAN measurements.',
        'ODD coverage: '+fmt(summary['odd_coverage'])+'.',
        f"Coverage over all keyframes: {100*summary['odd_coverage_all_keyframes']:.2f}%.", '',
        '| Plan | Acceptance | False reject / SAFE | False accept / UNSAFE | Recall U |',
        '|---|---|---|---|---|']
    for label, metrics in summary['metrics'].items():
        lines.append('| '+label+' | '+' | '.join([fmt(metrics[k]) for k in ('acceptance', 'false_reject', 'false_accept')])+' | '+(fmt(metrics['recall']) if label == 'U' else '—')+' |')
    lines += ['', 'CI: scene bootstrap, 2000 replicates, seed 20261104. N/A means no denominator.',
        'Recall U uses oracle-UNSAFE U only; synthetic U is not automatically unsafe.',
        f"Adapter errors: {summary['adapter_error_frames']}; overflow: {summary['object_overflow_frames']}; oracle UNKNOWN H/T/U: "+'/'.join(str(summary['metrics'][x]['oracle_unknown']) for x in ('H','T','U'))+'.',
        'Speed and object-count strata, with all CIs: results/summary.json (by_speed, by_object_count).',
        'ASSUMPTION: axis-aligned center coordinates; combined half-length=(4.8+object length)/2; ego_pose treated as center.',
        'Oracle: independent float 1 ms, GT object interpolation to 3 s then hold; lost tracks hold last pose.',
        'Golden: constant nonnegative longitudinal object speed; invalid observations reject without clipping.',
        'Oracle checks until stop; golden additionally holds 2 s. No closed-loop safety claim.', '',
        f"False accepts: {len(summary['false_accept_cases'])}. Every case, including token and GT mismatch reason: [false_accepts.jsonl](results/false_accepts.jsonl)."]
    if len(summary['false_accept_cases']) <= 25:
        for c in summary['false_accept_cases']:
            lines.append(f"- {c['scene']} / {c['token']} / {c['plan']}: {c['oracle']['reason']}; {json.dumps(c['oracle']['culprit'])}")
    lines += ['', f"Measured runtime across invocations (load, evaluation, summary): {summary['runtime_seconds']:.1f} s.",
        f"RTL vectors: {summary['rtl_frame_count']} frames, all available H/T/U inputs per frame, in rtl_cases.jsonl.",
        'Pilot: `python -B tsmx_hw/eval_nuscenes/run_w7.py --limit 200`.',
        'Reproduce/resume full: `python -B tsmx_hw/eval_nuscenes/run_w7.py` (automatic bounded child batches).',
        'One bounded batch: `python -B tsmx_hw/eval_nuscenes/run_w7.py --batch`.',
        'Protocol: PROTOCOL.md; provenance hashes and full counts in results/summary.json.',
        'Checkpoint compatibility AMENDMENT A1: missing wp_proj tensors set to zero; board bit-exactness unverified.',
        'Not done here: RTL/board execution (vectors provided for Claude).']
    assert len(lines) <= 80
    (output / 'W7_REPORT.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--limit', type=int, default=0, help='Pilot prefix of eligible frames; isolated output')
    parser.add_argument('--batch', action='store_true', help='One resumable <=20 minute batch')
    parser.add_argument('--minutes', type=float, default=20)
    parser.add_argument('--nuscenes-root', type=Path, default=BASE / 'eval/data/nuscenes')
    args = parser.parse_args()
    if not 0 < args.minutes <= 25:
        parser.error('--minutes must be in (0,25]')
    if not args.batch and not args.limit:
        import subprocess
        pilot = json.loads((HERE / 'results/pilot/summary.json').read_text(encoding='utf-8'))
        assert pilot['processed_frames'] == 200, 'Complete --limit 200 before full evaluation'
        while True:
            command = [sys.executable, '-B', str(Path(__file__).resolve()), '--batch',
                       '--minutes', str(args.minutes), '--nuscenes-root', str(args.nuscenes_root)]
            subprocess.run(command, check=True, timeout=39*60, cwd=str(BASE / 'journalQ1'))
            if json.loads((HERE / 'results/summary.json').read_text(encoding='utf-8'))['complete']:
                return
    start = time.monotonic()
    from data.nuscenes_lite import load_nuscenes
    root = args.nuscenes_root.resolve()
    assert (root / 'v1.0-trainval/_nuscenes_lite_v2.pkl').exists(), 'Read-only dataset requires existing cache'
    result_dir = HERE / 'results' / ('pilot' if args.limit else '')
    result_dir.mkdir(parents=True, exist_ok=True)
    frame_path = result_dir / 'frames.jsonl'
    rows = recover(frame_path)
    done = {r['token'] for r in rows}
    fingerprint = {'code_sha256': sha(Path(__file__)), 'protocol_sha256': sha(HERE / 'PROTOCOL.md'),
                   'checkpoint_sha256': sha(CKPT), 'limit': args.limit, 'dataset': str(root)}
    manifest = result_dir / 'manifest.json'
    if manifest.exists():
        assert json.loads(manifest.read_text()) == fingerprint, 'Resume provenance mismatch'
    else:
        write_json(manifest, fingerprint)
    nusc = load_nuscenes('v1.0-trainval', dataroot=str(root))
    assert len(nusc.scene) == 850
    add_categories(nusc, root)
    model, _ = model_load(nusc)
    write_json(result_dir / 'validation.json', enable_exact_blas(model))
    scenes = sorted(nusc.scene, key=lambda s: (s['name'], s['token']))
    total_keyframes = sum(s['nbr_samples'] for s in scenes)
    total_eligible = sum(s['nbr_samples']-6 for s in scenes)
    vector_path = (result_dir / 'rtl_cases.jsonl') if args.limit else HERE / 'rtl_cases.jsonl'
    vectors = recover(vector_path)
    vector_tokens = {v['token'] for v in vectors}
    budget_end = start + args.minutes*60
    early_odd = {r['token']: r for r in rows if r['odd']}
    stop = False
    with frame_path.open('a', encoding='utf-8', buffering=1) as ff, vector_path.open('a', encoding='utf-8', buffering=1) as vf:
        ordinal = 0
        for scene in scenes:
            data = scene_data(nusc, scene)
            for i in range(len(data[0])-6):
                ordinal += 1
                if args.limit and ordinal > args.limit:
                    stop = True
                    break
                token = data[0][i]['token']
                if token in done:
                    # Repair a missing vector after interruption between frame and vector writes.
                    old = early_odd.get(token)
                    if old and old['odd'] and len(vector_tokens) < 300 and token not in vector_tokens:
                        _, vec = evaluate_frame(nusc, model, data, i)
                        vf.write(json.dumps(vec, allow_nan=False)+'\n')
                        vector_tokens.add(token)
                    continue
                if time.monotonic() >= budget_end and len(rows) > len(done):
                    stop = True
                    break
                row, vec = evaluate_frame(nusc, model, data, i)
                ff.write(json.dumps(row, allow_nan=False)+'\n')
                rows.append(row)
                if vec and len(vector_tokens) < 300:
                    vf.write(json.dumps(vec, allow_nan=False)+'\n')
                    vector_tokens.add(token)
                if len(rows) % 100 == 0:
                    print(f"frames={len(rows)}/{total_eligible} elapsed={time.monotonic()-start:.1f}s", flush=True)
            if stop:
                break
    summary = summarize(rows, [s['name'] for s in scenes], total_eligible, total_keyframes)
    previous = json.loads((result_dir / 'summary.json').read_text()) if (result_dir / 'summary.json').exists() else {}
    summary.update(provenance=fingerprint, rtl_frame_count=len(vector_tokens),
                   utc=datetime.now(timezone.utc).isoformat(),
                   runtime_seconds=previous.get('runtime_seconds', 0)+time.monotonic()-start)
    write_json(result_dir / 'summary.json', summary)
    with (result_dir / 'false_accepts.jsonl').open('w', encoding='utf-8') as f:
        for case in summary['false_accept_cases']:
            f.write(json.dumps(case)+'\n')
    report(summary, result_dir if args.limit else HERE)
    print(json.dumps({k: summary[k] for k in ('complete', 'processed_frames', 'odd_frames', 'runtime_seconds')}), flush=True)


if __name__ == '__main__':
    main()
