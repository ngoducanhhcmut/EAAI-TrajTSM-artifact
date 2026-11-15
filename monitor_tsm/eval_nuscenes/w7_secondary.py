"""Claude 05/11/2026: W7 SECONDARY (post-hoc, not preregistered) analysis of the false-reject causes.

Re-runs the unchanged golden (B4 mrmgen + B3 geom, same LANE / 0.5 s latency / Motion encoding as run_w7.py
evaluate_plan) on the object records and plan states stored in results/frames.jsonl, against the SAME stored oracle
labels. Variants:
  V0  as run_w7 (sanity: must reproduce every stored accept decision)
  VA  sound negative-velocity reduction (adapter, not golden, change). The golden world model admits only objects with
      0 <= v <= 20 m/s, so any object moving against the ego axis (oncoming traffic in the corridor, or annotation
      noise of -0.0x m/s on parked cars) made run_w7 reject the whole frame (object_range). Over a candidate's checked
      horizon H (B4 rows, stop + 2 s hold) plus the 0.5 s latency L, an object with v < 0 is replaced by a STATIONARY
      object covering its swept interval
         ahead  (x > 0): centre x - w2, half-length + w2, w = ceil(|v|(L+H)), w2 = ceil(w/2)
         behind (x <= 0): x, v := 0      -- it only moves further back
      so a certified modelled gap implies the true gap on the checked horizon (proof/adapter_lemmas.py A1-A3).
      05/11: the first version shifted ahead objects by w without inflation -> unsound (lemma N1); results replaced. Candidates are
      checked one at a time with their own H, in the same cid order as select_world.
  VB  VA + ignore objects behind the ego (RSS-style responsibility: rear-end collisions caused by a following vehicle).
      NOT a collision-freedom claim; reported only as an ablation of what the rear check costs.
usage: python -B w7_secondary.py   ->  results/secondary.json + SECONDARY_REPORT.md
"""
import sys, json, math
from pathlib import Path
from collections import Counter
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / 'golden')]
from tsmx_golden.model import (Ego, Motion, propagated_objects, select_world, b4_mrmgen, b3_geom, LIBRARY)

LANE = (-1800000, 1800000)
LAT = 500000
S = 1000000


def fixed(value):
    return int(round(float(value) * 1000000))


def raw_objects(records):
    return tuple(Motion(fixed(o['x']), fixed(o['v']) if o['v'] is not None else -1, 0, fixed(o['length']), 0, 0)
                 for o in records)


def v0(ego, records):
    raw = raw_objects(records)
    ok = all(0 <= o.v <= 20 * S for o in raw)
    objs = propagated_objects(raw, LAT, 0) if ok else raw
    return select_world(ego, objs, LANE)[0]


def reduce_neg(records, horizon_us, drop_rear):
    out = []
    for o in records:
        if drop_rear and o['x'] <= 0:
            continue
        if o['v'] is None:
            return None                                   # unknown speed: still fail closed
        x, v, ln = fixed(o['x']), fixed(o['v']), fixed(o['length'])
        if v < 0:
            if x > 0:
                # 05/11 fix: cover the whole swept interval [x - w, x] (w = ceil(|v|(L+H)/1e6)) by a stationary object
                # centred at x - w2 with half-length + w2. The first version only shifted it by w, which can move an
                # oncoming object BEHIND the ego and hide the pass-through (proof/adapter_lemmas.py N1).
                w = -((v * (LAT + horizon_us)) // S)
                w2 = -(-w // 2)
                x, ln = x - w2, ln + w2
            v = 0
        out.append(Motion(x, v, 0, ln, 0, 0))
    return tuple(out)


def va(ego, records, drop_rear=False):
    for cid in range(16):
        if not LIBRARY[cid][1]:
            continue
        tr = b4_mrmgen(ego.x, ego.v, ego.a, cid)
        if not tr.accept:
            continue
        horizon = tr.rows[-1][0] - tr.rows[0][0]
        raw = reduce_neg(records, horizon, drop_rear)
        if raw is None or not all(0 <= o.v <= 20 * S for o in raw):
            return 15
        objs = propagated_objects(raw, LAT, 0)
        if b3_geom(tr, objs, LANE).accept:
            return cid
    return 15


def boot(scenes, num, den, n=2000, seed=20261104):
    """scene bootstrap CI of sum(num)/sum(den); num/den per frame arrays."""
    keys = sorted(set(scenes))
    idx = {k: [] for k in keys}
    for i, s in enumerate(scenes):
        idx[s].append(i)
    N = np.array([sum(num[i] for i in idx[k]) for k in keys], float)
    D = np.array([sum(den[i] for i in idx[k]) for k in keys], float)
    rng = np.random.default_rng(seed)
    r = []
    for _ in range(n):
        pick = rng.integers(0, len(keys), len(keys))
        d = D[pick].sum()
        if d:
            r.append(N[pick].sum() / d)
    return [float(np.percentile(r, 2.5) * 100), float(np.percentile(r, 97.5) * 100)]


def main():
    rows = [json.loads(l) for l in open(HERE / 'results' / 'frames.jsonl', encoding='utf-8')]
    rows = [r for r in rows if r.get('odd')]
    if len(sys.argv) > 1:
        rows = rows[:int(sys.argv[1])]
    acc = {v: {p: [] for p in 'HTU'} for v in ('V0', 'VA', 'VB')}
    mism = 0
    for r in rows:
        for p, d in r['plans'].items():
            if 'state_si' not in d:
                continue
            x, v, a = d['state_si']
            ego = Ego(LAT, fixed(x), fixed(v), fixed(a), 0, 0)
            lab = d['oracle']['label']
            c0 = v0(ego, r['objects'])
            if (c0 != 15) != d['accept']:
                mism += 1
            ca = va(ego, r['objects'])
            cb = va(ego, r['objects'], True)
            for name, c in (('V0', c0), ('VA', ca), ('VB', cb)):
                acc[name][p].append((r['scene'], lab, c != 15, r['token']))
    out = {'sanity_V0_mismatches': mism, 'frames': len(rows), 'variants': {}}
    for name, per in acc.items():
        out['variants'][name] = {}
        for p, lst in per.items():
            sc = [s for s, _, _, _ in lst]
            a_ = [int(ac) for _, _, ac, _ in lst]
            safe = [int(l == 'SAFE') for _, l, _, _ in lst]
            uns = [int(l == 'UNSAFE') for _, l, _, _ in lst]
            fr = [int(l == 'SAFE' and not ac) for _, l, ac, _ in lst]
            fa = [int(l == 'UNSAFE' and ac) for _, l, ac, _ in lst]
            fas = [(s, t) for s, l, ac, t in lst if l == 'UNSAFE' and ac]
            out['variants'][name][p] = dict(
                n=len(lst), accept=sum(a_), accept_pct=100 * sum(a_) / max(1, len(lst)), accept_ci=boot(sc, a_, [1] * len(lst)),
                safe=sum(safe), false_reject=sum(fr), fr_pct=100 * sum(fr) / max(1, sum(safe)), fr_ci=boot(sc, fr, safe),
                unsafe=sum(uns), false_accept=sum(fa), fa_pct=100 * sum(fa) / max(1, sum(uns)), fa_ci=boot(sc, fa, uns),
                false_accept_cases=fas)
    (HERE / 'results' / 'secondary.json').write_text(json.dumps(out, indent=1), encoding='utf-8')
    L = ['# W7 secondary (post-hoc) analysis — Claude 05/11/2026', '',
         'Not preregistered. Same frames, plan states, stored oracle labels and unchanged golden as W7_REPORT.md; only the',
         'object ADAPTER differs (see w7_secondary.py docstring). V0 reproduces the primary run: '
         f'{mism} decision mismatches over all plans.', '',
         '| Variant | Plan | Acceptance | False reject / SAFE | False accept / UNSAFE |', '|---|---|---|---|---|']
    for name, per in out['variants'].items():
        for p, m in per.items():
            L.append(f"| {name} | {p} | {m['accept_pct']:.2f}% [{m['accept_ci'][0]:.2f}, {m['accept_ci'][1]:.2f}] | "
                     f"{m['fr_pct']:.2f}% [{m['fr_ci'][0]:.2f}, {m['fr_ci'][1]:.2f}] ({m['false_reject']}/{m['safe']}) | "
                     f"{m['fa_pct']:.2f}% [{m['fa_ci'][0]:.2f}, {m['fa_ci'][1]:.2f}] ({m['false_accept']}/{m['unsafe']}) |")
    L += ['', 'V0 = primary adapter; VA = sound negative-velocity reduction (proof/adapter_lemmas.py);',
          'VB = VA without rear objects (RSS-style responsibility ablation, NOT a collision-freedom claim).',
          'CI: scene bootstrap, 2000 replicates, seed 20261104.']
    (HERE / 'SECONDARY_REPORT.md').write_text('\n'.join(L) + '\n', encoding='utf-8')
    print('\n'.join(L))


if __name__ == '__main__':
    main()
