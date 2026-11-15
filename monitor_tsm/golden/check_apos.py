# -*- coding: utf-8 -*-
"""A8 (02/11/2026) check of the ODD extension a in [-8,+2] m/s^2.
1. For a<=0 the new golden equals the legacy one (b4_mrmgen, select_world, b2_splice) on random inputs.
2. For 0<a<=2 every mild (finite-jerk) profile starts at a, never steps by more than j*DT between
   100 ms command points while moving, stops and holds 2 s, stays <=20 m/s, and B3 accepts it on an empty road.
  python check_apos.py [N]
"""
import importlib.util, random, sys
from dataclasses import replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from tsmx_golden import model as new  # noqa: E402

spec = importlib.util.spec_from_loader('legacy_model', loader=None)
legacy = importlib.util.module_from_spec(spec)
exec(compile((HERE / 'legacy/model_v_a_nonpositive_2026-11-02.py.txt').read_text(encoding='utf-8'),
             'legacy_model', 'exec'), legacy.__dict__)
S = new.S


def main(n=3000):
    rnd = random.Random(20261102)
    mism = 0
    for _ in range(n):
        x = rnd.randint(-50 * S, 50 * S); v = rnd.choice([0, 10 * S, rnd.randint(0, 10 * S)])
        a = rnd.choice([0, -8 * S, rnd.randint(-8 * S, 0)]); cid = rnd.randrange(16)
        tn, tl = new.b4_mrmgen(x, v, a, cid), legacy.b4_mrmgen(x, v, a, cid)  # different classes: compare fields
        if (tn.accept, tn.rows, tn.stop, tn.reason) != (tl.accept, tl.rows, tl.stop, tl.reason): mism += 1
        ego = new.Ego(0, x, v, a, x + 40 * S, 0)
        objs = tuple(new.Motion(x + rnd.randint(5 * S, 60 * S), rnd.randint(0, 10 * S)) for _ in range(rnd.randint(0, 3)))
        objs_l = tuple(legacy.Motion(o.x, o.v) for o in objs)
        ego_l = legacy.Ego(0, x, v, a, x + 40 * S, 0)
        if new.select_world(ego, objs, (-1800000, 1800000)) != legacy.select_world(ego_l, objs_l, (-1800000, 1800000)): mism += 1
        p = new.Plan(1, ego, 0, new.DT, x + rnd.randint(0, 2 * S), max(0, v + rnd.randint(-S, S)), rnd.randint(-8 * S, 0))
        pl = legacy.Plan(1, ego_l, 0, legacy.DT, p.x, p.v, p.a)
        if new.b2_splice(ego, p) != legacy.b2_splice(ego_l, pl): mism += 1
    print(f'a<=0 equivalence: {3 * n} comparisons, mismatches={mism}')

    bad = 0; checked = 0; vmax = 0
    for _ in range(n):
        x = rnd.randint(-50 * S, 50 * S); v = rnd.choice([0, 10 * S, rnd.randint(0, 10 * S)])
        a = rnd.choice([2 * S, 1, rnd.randint(1, 2 * S)]); cid = rnd.randrange(16)
        b, j, _ = new.LIBRARY[cid]
        if not j: continue
        tr = new.b4_mrmgen(x, v, a, cid)
        checked += 1
        ok = tr.accept and tr.rows[0][5] == a and tr.stop >= 0
        # while moving (vh>0 at both rows); at standstill the command drops to 0, as for a<=0
        moving = [r[5] for r in tr.rows if r[4] > 0]
        ok = ok and all(abs(c1 - c0) <= j * new.DT // new.T + 1 for c0, c1 in zip(moving, moving[1:]))
        ok = ok and all(r[4] <= 20 * S for r in tr.rows) and all(r2[1] >= r1[1] for r1, r2 in zip(tr.rows, tr.rows[1:]))
        ok = ok and tr.rows[-1][4] == 0
        ok = ok and new.b3_geom(tr, ()).accept
        vmax = max(vmax, max(r[4] for r in tr.rows))
        if not ok:
            bad += 1
            if bad <= 3: print('BAD', x, v, a, cid, tr.accept, tr.reason, tr.stop)
    print(f'a>0 mild profiles: {checked} checked, bad={bad}, max speed in envelope={vmax / S:.3f} m/s')
    return mism == 0 and bad == 0


if __name__ == '__main__':
    sys.exit(0 if main(int(sys.argv[1]) if len(sys.argv) > 1 else 3000) else 1)
