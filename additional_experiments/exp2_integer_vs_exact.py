"""Experiment 2 (13/11/2026): cost of the finite-bit (integer, outward-rounded,
linear-envelope) acceptance relative to an exact floating-point check of the SAME model.

Model shared by both checkers: ego follows the candidate's nominal jerk-limited stopping profile
(0.1 s reaction prefix, ramp to -b at jerk j, stop, 2 s hold); objects move at constant velocity
(the nuScenes instantiation); combined half-length L; reserve r = 0.5 m; candidate order = golden order
(finite-jerk candidates 0,1,2,4,5,...,14); a decision is the first admissible candidate or reject.
Integer checker: unchanged golden select_world (b4_mrmgen + b3_geom).
Exact checker: closed-form float trajectory sampled every 0.25 ms with the same horizon rule.

Part A: random scenarios over the operational domain.  Part B: the 300 stored nuScenes frames
(eval_nuscenes/results/serial_partial_vectors.jsonl), all plan sources, encoded inputs as given to the golden.
Counts: both accept / both reject / integer-only reject (conservatism) / integer-only accept (soundness
violation of the reference function w.r.t. this exact check; expected 0).
"""
import json, math, sys, random
from pathlib import Path
from multiprocessing import Pool
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / 'tsmx_hw' / 'golden'))
from tsmx_golden.model import select_world, LIBRARY, Motion, S

FIN = [c for c in range(16) if LIBRARY[c][1]]
R = 0.5


class E:  # minimal ego carrier for select_world
    def __init__(self, x, v, a):
        self.x, self.v, self.a = x, v, a


def ego_curve(x0, v0, a0, b, j, dt=0.00025):
    """Exact nominal profile, returns (t, x) samples until stop + 2 s hold, or None if horizon > 12.8 s."""
    def state(t):
        p = np.minimum(t, .1)
        vp = v0 + a0 * p; xp = x0 + v0 * p + .5 * a0 * p * p
        ramp = abs(a0 + b) / j; jerk = -j if a0 > -b else j
        u = np.clip(t - .1, 0, ramp); tail = np.maximum(t - .1 - ramp, 0)
        vr = vp + a0 * u + .5 * jerk * u * u
        xr = xp + vp * u + .5 * a0 * u * u + jerk * u ** 3 / 6
        return xr + vr * tail - .5 * b * tail * tail, vr - b * tail
    if v0 == 0 and a0 <= 0:
        stop = 0.0
    else:
        # find first time speed reaches 0 (prefix may already stop)
        ts = np.arange(0, 60, 0.001); _, vs = state(ts)
        idx = np.argmax(vs <= 0) if np.any(vs <= 0) else None
        if idx is None:
            return None
        lo, hi = max(0, ts[idx] - 0.001), ts[idx]
        for _ in range(40):
            mid = (lo + hi) / 2
            if state(np.array(mid))[1] > 0: lo = mid
            else: hi = mid
        stop = hi
    end = stop + 2.0
    if end > 12.8 + 1e-9:
        return None
    t = np.arange(0, end + dt / 2, dt)
    xs, _ = state(np.minimum(t, stop))
    return t, xs


def exact_decision(x0, v0, a0, objs):
    for cid in FIN:
        b, j = LIBRARY[cid][0] / S, LIBRARY[cid][1] / S
        cur = ego_curve(x0, v0, a0, b, j)
        if cur is None:
            continue
        t, ex = cur
        ok = True
        for (ox, ov, L) in objs:
            o = ox + ov * t
            g = (o - ex - L) if ox >= x0 else (ex - o - L)
            if g.min() < R:
                ok = False; break
        if ok:
            return cid
    return 15


def integer_decision(x0, v0, a0, objs):
    ego = E(int(round(x0 * S)), int(round(v0 * S)), int(round(a0 * S)))
    mo = tuple(Motion(int(round(ox * S)), int(round(ov * S)), 0, int(round(L * S)), 0, 0) for ox, ov, L in objs)
    return select_world(ego, mo, (-1800000, 1800000))[0]


def case(seed):
    rng = random.Random(seed)
    v0 = rng.uniform(0, 10); a0 = rng.uniform(-8, 2)
    objs = []
    for _ in range(rng.randint(1, 3)):
        L = rng.uniform(2.0, 6.0)
        if rng.random() < 0.6:
            objs.append((rng.uniform(L + 0.6, 80.0), rng.uniform(0, 20), L))
        else:
            objs.append((-rng.uniform(L + 0.6, 60.0), rng.uniform(0, 20), L))
    return integer_decision(0.0, v0, a0, objs), exact_decision(0.0, v0, a0, objs)


def tally(pairs):
    c = dict(both_accept=0, both_reject=0, integer_only_reject=0, integer_only_accept=0, same_decision_diff_cid=0)
    for i, e in pairs:
        if i != 15 and e != 15:
            c['both_accept'] += 1
            if i != e: c['same_decision_diff_cid'] += 1
        elif i == 15 and e == 15: c['both_reject'] += 1
        elif i == 15: c['integer_only_reject'] += 1
        else: c['integer_only_accept'] += 1
    c['n'] = len(pairs)
    return c


def nuscenes_pairs():
    out = []
    for line in open(HERE.parents[2] / 'tsmx_hw/eval_nuscenes/results/serial_partial_vectors.jsonl', encoding='utf-8'):
        rec = json.loads(line)
        for name, vec in rec['plans'].items():
            eg = vec['ego']
            objs = [(o['x'] / S, o['v'] / S, o['length'] / S) for o in vec['objects']]
            if vec.get('adapter_errors') or any(not (0 <= o['v'] <= 20 * S) for o in vec['objects']):
                continue  # out-of-domain inputs are rejected identically by construction
            mo = tuple(Motion(o['x'], o['v'], o['a'], o['length'], o['event'], o['after_a']) for o in vec['objects'])
            i = select_world(E(eg['x'], eg['v'], eg['a']), mo, tuple(vec['lane']))[0]
            assert (i != 15) == vec['expected']['accept'], (rec['token'], name)
            e = exact_decision(eg['x'] / S, eg['v'] / S, eg['a'] / S, [(ox - 0.0, ov, L) for ox, ov, L in objs]) \
                if eg['v'] >= 0 else 15
            out.append((i, e))
    return out


if __name__ == '__main__':
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
    with Pool(6) as p:
        A = p.map(case, range(N), chunksize=50)
    B = nuscenes_pairs()
    res = {'A_random_domain': tally(A), 'B_nuscenes_300_frames': tally(B)}
    (HERE / 'exp2_results.json').write_text(json.dumps(res, indent=1), encoding='utf-8')
    print(json.dumps(res, indent=1))
