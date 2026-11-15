"""Experiment 3 (13/11/2026): on the 17,445 in-domain nuScenes keyframes of the
RQ1-planner decision-core replay (eval_nuscenes/w9a/replay_*.jsonl, variant V0, plan sources H and T), compare
  * TSM   : the registered integer decision (unchanged golden, as in the paper);
  * EXACT : the same model checked in floating point (exp2_integer_vs_exact.exact_decision) -> share of TSM false
            rejections caused by finite-bit conservatism;
  * RSS   : responsibility-sensitive longitudinal rule, front objects only (rear vehicles are responsible),
            reaction 0.1 s, ego max accel 2, ego min brake 4, lead max brake 8 m/s^2, plus the 0.5 m reserve;
  * TTC   : constant-velocity time-to-collision >= 2 s to every listed object (front and rear).
All four use the same encoded inputs (ego apply state, object list incl. out-of-domain objects for RSS/TTC) and the
same labels: pre-specified oracle (registered) and aligned library oracle.
Output: exp3_results.json.
"""
import json, glob, sys
from pathlib import Path
from multiprocessing import Pool
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from exp2_integer_vs_exact import exact_decision

S = 1e6
W9A = HERE.parents[2] / 'tsmx_hw' / 'eval_nuscenes' / 'w9a'


def objects_at_apply(vec):
    out = []
    for o in vec['objects']:
        x, v, L = o['x'] / S, o['v'] / S, o['length'] / S
        if not vec.get('propagation_done'):
            x = x + v * 0.5
        out.append((x, v, L))
    return out


def rss_ok(ex, ev, objs, rho=0.1, amax=2.0, bmin=4.0, bmax=8.0, r=0.5):
    for ox, ov, L in objs:
        if ox < ex:
            continue  # rear vehicle is responsible under RSS
        vr = ev
        d = vr * rho + .5 * amax * rho ** 2 + (vr + rho * amax) ** 2 / (2 * bmin) - ov * abs(ov) / (2 * bmax)
        if (ox - ex - L) < max(d, 0.0) + r:
            return False
    return True


def ttc_ok(ex, ev, objs, thr=2.0):
    for ox, ov, L in objs:
        gap = abs(ox - ex) - L
        if gap <= 0:
            return False
        closing = (ev - ov) if ox >= ex else (ov - ev)
        if closing > 0 and gap / closing < thr:
            return False
    return True


def work(rec):
    vec = rec['vector']; eg = vec['ego']
    ex, ev, ea = eg['x'] / S, eg['v'] / S, eg['a'] / S
    objs = objects_at_apply(vec)
    tsm = rec['registered']['accept']
    if vec.get('adapter_errors') or any(not (0 <= ov <= 20) for _, ov, _ in objs) or ev < 0:
        exact = False  # outside the shared model's domain: rejected by construction
    else:
        exact = exact_decision(ex, ev, ea, objs) != 15
    return dict(plan=rec['plan'], scene=rec['scene'], pre=rec['registered']['oracle']['label'],
                ali=rec['aligned']['label'], tsm=tsm, exact=exact,
                rss=rss_ok(ex, ev, objs), ttc=ttc_ok(ex, ev, objs))


def rows():
    for f in sorted(glob.glob(str(W9A / 'replay_*.jsonl'))):
        for line in open(f, encoding='utf-8'):
            if line.strip():
                r = json.loads(line)
                if r['odd'] and r['plan'] in ('H', 'T'):
                    yield r


def metrics(R, key, val_scenes=None):
    out = {}
    for plan in ('H', 'T'):
        P = [r for r in R if r['plan'] == plan and (val_scenes is None or r['scene'] in val_scenes)]
        safe = [r for r in P if r['pre'] == 'SAFE']; uns = [r for r in P if r['pre'] == 'UNSAFE']
        auns = [r for r in P if r['ali'] == 'UNSAFE']
        out[plan] = dict(n=len(P), acceptance=sum(r[key] for r in P) / len(P),
                         FR=sum(not r[key] for r in safe) / len(safe), FR_n=f"{sum(not r[key] for r in safe)}/{len(safe)}",
                         FA_pre=f"{sum(r[key] for r in uns)}/{len(uns)}",
                         FA_aligned=sum(r[key] for r in auns) / len(auns), FA_aligned_n=f"{sum(r[key] for r in auns)}/{len(auns)}")
    return out


if __name__ == '__main__':
    import numpy as np
    val = set(np.load(HERE.parents[3] / 'sw/eval_trainval/out/dataset.npz', allow_pickle=True)['scene'].tolist())
    with Pool(6) as p:
        R = p.map(work, list(rows()), chunksize=40)
    res = {k: {'all': metrics(R, k), 'validation': metrics(R, k, val)} for k in ('tsm', 'exact', 'rss', 'ttc')}
    for plan in ('H', 'T'):
        fr = [r for r in R if r['plan'] == plan and r['pre'] == 'SAFE' and not r['tsm']]
        res.setdefault('conservatism', {})[plan] = dict(
            tsm_false_rejects=len(fr), exact_would_accept=sum(r['exact'] for r in fr),
            tsm_accepts_exact_rejects=sum(1 for r in R if r['plan'] == plan and r['tsm'] and not r['exact']))
    (HERE / 'exp3_results.json').write_text(json.dumps(res, indent=1), encoding='utf-8')
    print(json.dumps(res, indent=1))
