"""Claude 05/11/2026: soundness of the negative-velocity object adapter (eval_nuscenes/w7_secondary.py variant VA,
eval_nuplan/tsmx_nuplan/planner.py).

The golden world model admits only objects with 0 <= v <= 20 m/s. An object with v < 0 is replaced by a STATIONARY
object covering its whole swept interval on the checked window [0, L+H] (H = the candidate's B4 horizon, L = latency, any L in [0, 0.5 s]: nuScenes 0.5 s, nuPlan 0.1 s):
    ahead  (x > 0):  w = ceil(|v|(L+H)/1e6),  centre c = x - floor(w/2) ... modelled as c = x - w2, half-length ln + w2,
                     w2 = ceil(w/2)  (so [c - w2, c + w2] contains [x - w, x])
    behind (x <= 0): unchanged position, v := 0 (it only moves further back)
B3's longitudinal test for a stationary object is |c - e(t)| >= half_length + reserve for the whole horizon (sign decided
by the side, which a stationary object cannot change without failing the test). Units um, us, um/s.

  A1  ahead: the true position x + v t stays within [c - w2, c + w2] for t in [0, L+H]
  A2  ahead: |c - e| >= (ln + w2) + res  =>  |x + v t - e| >= ln + res        (any ego position e)
  A3  behind: x <= 0, v < 0, e >= x + ln + res (modelled certified, object behind) => e - (x + v t) >= ln + res
  N1  control: the earlier SHIFT-ONLY reduction (c = x - w, no length inflation) is UNSOUND: with |c - e| >= ln + res
      the true object can still overlap the ego (it is moved behind the ego and B3 then checks it as a rear object).
      This is the bug found on 05/11 in the first VA run (74 H false accepts on nuScenes); kept as a regression control.
  N2  control: inflation by w2 computed without the latency L is unsound.
usage: python adapter_lemmas.py
"""
import sys
from z3 import Ints, Reals, Solver, And, Or, Not, ToReal, If, unsat, sat

x, v, L, H, w, w2 = Ints('x v L H w w2')
t, e, ln, res = Reals('t e ln res')
X, V = ToReal(x), ToReal(v)
pos = X + V * t / 10**6
dom = And(x > 0, v < 0, v >= -100 * 10**6, L >= 0, L <= 500000, H > 0, H <= 12800000, t >= 0, t <= ToReal(L + H), ln > 0, res >= 0)
ceil_w = And(w * 10**6 >= -v * (L + H), (w - 1) * 10**6 < -v * (L + H), 2 * w2 >= w, 2 * (w2 - 1) < w)
c = ToReal(x - w2)
absr = lambda z: If(z >= 0, z, -z)


def check(name, hyp, concl, expect=unsat):
    s = Solver(); s.set('timeout', 300000)
    s.add(hyp, Not(concl))
    r = s.check()
    ok = r == expect
    print(f"{'PROVEN ' if ok and expect == unsat else 'REFUTED' if ok else 'FAILED '} {name}" + ('' if ok else f'  ({r})'))
    return ok


ok = True
ok &= check('A1 ahead: true position inside the inflated stationary interval', And(dom, ceil_w),
            And(pos >= c - ToReal(w2), pos <= c + ToReal(w2)))
ok &= check('A2 ahead: modelled |c-e| >= ln+w2+res  =>  true |pos-e| >= ln+res',
            And(dom, ceil_w, absr(c - e) >= ln + ToReal(w2) + res), absr(pos - e) >= ln + res)
ok &= check('A3 behind: certified rear gap stays certified', And(x <= 0, v < 0, t >= 0, ln > 0, res >= 0, e - X >= ln + res),
            e - pos >= ln + res)
cs = ToReal(x - w)
ok &= check('N1 control: shift-only reduction (first VA run)', And(dom, ceil_w, absr(cs - e) >= ln + res),
            absr(pos - e) >= ln + res, expect=sat)
noL = And(w * 10**6 >= -v * H, (w - 1) * 10**6 < -v * H, 2 * w2 >= w, 2 * (w2 - 1) < w)
ok &= check('N2 control: inflation without latency L', And(dom, noL, absr(c - e) >= ln + ToReal(w2) + res),
            absr(pos - e) >= ln + res, expect=sat)
print('ALL OK' if ok else 'SOME CHECK FAILED')
sys.exit(0 if ok else 1)
