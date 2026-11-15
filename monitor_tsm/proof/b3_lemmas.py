"""Claude 04/11/2026 (W3): machine-checked soundness lemmas for B3 (golden model.py:311-328, 439-505).

Units: position um, velocity um/s, acceleration um/s^2, time us; T = 1e6 us/s.
True stop-clipped constant-acceleration displacement after u us:
    P(u)   = v*u/T + a*u^2/(2*T^2)                      (parabola)
    s(u)   = P(u)              if a >= 0 or u <= tau    (tau = v*T/(-a), stop time)
           = v^2/(-2a)         otherwise                 (standstill)
Integer rounding in the golden/RTL is modelled conservatively: a floored value q is only known to satisfy
q <= x, a ceiled value c only c >= x. Every lemma is stated for ALL REAL v, a, w, u in the declared ODD
ranges, which is stronger than the integer statement. Each check asks Z3 for a counterexample; `unsat`
means none exists (nonlinear real arithmetic is decidable; Z3 nlsat is complete for it).
usage: python b3_lemmas.py   -> prints one line per lemma and exits non-zero if any is not proven.
"""
import sys, time
from z3 import Reals, Solver, And, Or, Not, If, unsat, sat, set_param

T = 10**6
VMAX = 20 * 10**6          # 20 m/s (B3 row/object range)
AMIN, AMAX = -8 * 10**6, 2 * 10**6
HMAX = 100000              # B3 cell width <= DT
JMAX = 8 * 10**6

def P(v, a, u):
    return v * u / T + a * u * u / (2 * T * T)

def s_clip(v, a, u, s):
    """constraint: s is the true stop-clipped displacement at time u (case split, no division by a)."""
    # a >= 0 or not yet stopped (v*T + a*u >= 0): s = P ; stopped: s*(-2a) = v^2 and v*T + a*u < 0
    return Or(And(Or(a >= 0, v * T + a * u >= 0), s == P(v, a, u)),
              And(a < 0, v * T + a * u < 0, s * (-2 * a) == v * v))

RESULTS = []
def check(name, hyp, goal, note='', expect_proof=True):
    h0 = Solver(); h0.set('timeout', 600000); h0.add(hyp)
    if h0.check() != sat:                       # vacuity guard: the hypotheses must be satisfiable
        RESULTS.append((name, False)); print(f"FAILED  {name:<42} hypotheses unsatisfiable (vacuous)"); return
    s = Solver(); s.set('timeout', 600000)
    s.add(hyp); s.add(Not(goal))
    t0 = time.time(); r = s.check(); dt = time.time() - t0
    ok = (r == unsat) if expect_proof else (r == sat)
    if not expect_proof:                        # negative control: a deliberately wrong lemma must be refuted
        RESULTS.append((name, ok))
        print(f"{'REFUTED' if ok else 'FAILED '} {name:<42} {dt:6.1f} s  (negative control, counterexample expected)")
        return
    RESULTS.append((name, ok))
    extra = '' if ok else f'  model={s.model() if r == sat else r}'
    print(f"{'PROVEN ' if ok else 'FAILED '} {name:<42} {dt:6.1f} s  {note}{extra}")

v, a, w, u, s_u, s_w, q, c, x = Reals('v a w u s_u s_w q c x')
dom = And(0 <= v, v <= VMAX, AMIN <= a, a <= AMAX, 0 < w, w <= HMAX, 0 <= u, u <= w)

# ---- L1/L2: front actor displacement is bounded below by the line la*u/w (swept_lb, model.py:326) ----
# L1 (aa < 0): la = max(0, floor(P(w))) (disp_lb).  Chord of the concave stop-clipped curve.
la = If(q > 0, q, 0)
check('L1 front lower, a<0 (chord, stop-clipped)',
      And(dom, a < 0, s_clip(v, a, u, s_u), q <= P(v, a, w)),
      s_u * w >= la * u, 'disp_lb<=s(w); s concave, s(0)=0')
# L2 (aa >= 0): la = floor(v*w/T). Tangent v*u/T <= P(u).
check('L2 front lower, a>=0 (tangent)',
      And(dom, a >= 0, s_clip(v, a, u, s_u), q <= v * w / T),
      s_u * w >= q * u)

# ---- L3/L4: rear actor displacement is bounded above by ub*u/w ----
# L3 (ab <= 0, incl. stop): ub = ceil(v*w/T) >= v*w/T ; s(u) <= v*u/T.
check('L3 rear upper, a<=0 (tangent, incl. stop)',
      And(dom, a <= 0, s_clip(v, a, u, s_u), c >= v * w / T),
      s_u * w <= c * u)
# L4 (ab > 0): ub = disp_ub = max(0, ceil(P(w))) (first branch, never stopped). Chord of convex curve.
check('L4 rear upper, a>0 (chord, convex)',
      And(dom, a > 0, s_clip(v, a, u, s_u), c >= P(v, a, w)),
      s_u * w <= If(c > 0, c, 0) * u)

# ---- L5: disp_ub(v,a,h) >= s(h) for both branches (used by advance_lb up=True, model.py:314) ----
check('L5a disp_ub branch1 (a>=0 or moving at h)',
      And(dom, Or(a >= 0, v * T + a * w >= 0), s_clip(v, a, w, s_w), c >= P(v, a, w)),
      If(c > 0, c, 0) >= s_w)
check('L5b disp_ub branch2 (stopped before h)',
      And(dom, a < 0, v * T + a * w < 0, s_clip(v, a, w, s_w), c >= v * w / (2 * T)),
      c >= s_w, 'stop at tau<w: s=v*tau/2<=v*w/2')
# ---- L6: disp_lb(v,a,h) <= s(h) for every a (advance_lb up=False) ----
check('L6 disp_lb <= s(h)',
      And(dom, s_clip(v, a, w, s_w), q <= P(v, a, w)),
      If(q > 0, q, 0) <= s_w)

# ---- L7: displacement is monotone in the initial speed (lower state uses vl, upper uses vh) ----
v2, s2 = Reals('v2 s2')
check('L7 s(u) monotone in v',
      And(dom, v <= v2, v2 <= VMAX, s_clip(v, a, u, s_u), s_clip(v2, a, u, s2)),
      s_u <= s2)

# ---- L11/L12: monotone in the acceleration (B2 splice 8-corner box, model.py:330-347; propagated_objects) ----
a2 = Reals('a2')[0]
check('L11 s(u) monotone in a',
      And(dom, a <= a2, a2 <= AMAX, s_clip(v, a, u, s_u), s_clip(v, a2, u, s2)), s_u <= s2)
check('L12 v(u) monotone in a and v',
      And(dom, a <= a2, a2 <= AMAX, v <= v2, v2 <= VMAX),
      If(v * T + a * u >= 0, v + a * u / T, 0) <= If(v2 * T + a2 * u >= 0, v2 + a2 * u / T, 0))
check('N6 s(u) monotone in a, reversed',
      And(dom, a2 < a - 1000, AMIN <= a2, u >= 1000, v >= 1000, s_clip(v, a, u, s_u), s_clip(v, a2, u, s2)),
      s_u <= s2, expect_proof=False)

# ---- L8: speed update bounds (advance_lb nv, model.py:322) ----
vt = Reals('vt')[0]
true_v = If(v * T + a * w >= 0, v + a * w / T, 0)
check('L8a nv lower: max(0,floor((vT+ah)/T)) <= v(h)',
      And(dom, q <= (v * T + a * w) / T), If(q > 0, q, 0) <= true_v)
check('L8b nv upper: max(0,ceil((vT+ah)/T)) >= v(h)',
      And(dom, c >= (v * T + a * w) / T), If(c > 0, c, 0) >= true_v)

# ---- L9: endpoint minimum of the linear gap envelope (swept_lb return value) ----
G0, la_, ub_ = Reals('G0 la ub')
check('L9 G0+(la-ub)u/w >= min(G0, G0+la-ub)',
      And(0 < w, 0 <= u, u <= w),
      G0 + (la_ - ub_) * u / w >= If(G0 < G0 + la_ - ub_, G0, G0 + la_ - ub_))

# ---- L10: jerk inflation (model.py:480-482). Deviation of the true ego position from the midpoint
# quadratic, with |a(r)-a_mid| <= J|r-h/2| + 1 LSB, is <= J*h^3/8/T^3 + h^2/(2 T^2) for every u in [0,h].
# Closed form of the worst-case double integral for u <= h (piecewise in u vs h/2):
J, h = Reals('J h')
def worst(u_, h_, J_):
    # integral_0^u (u-r)*(J|r-h/2|)/T^3 dr, split at r=h/2 (u<=h/2 or u>h/2), plus the 1-LSB term u^2/(2T^2)
    m = h_ / 2
    lo = J_ * (m * u_ * u_ / 2 - u_ ** 3 / 6) / T ** 3            # u <= h/2
    hi = J_ * (u_ * m * m / 2 - m ** 3 / 6 + (u_ - m) ** 3 / 6) / T ** 3   # u > h/2
    return If(u_ <= m, lo, hi) + u_ * u_ / (2 * T * T)
check('L10 inflate covers jerk deviation on [0,h]',
      And(0 < h, h <= HMAX, 0 <= u, u <= h, 0 <= J, J <= JMAX, c >= J * h ** 3 / (8 * T ** 3) + h * h / (2 * T * T)),
      worst(u, h, J) <= c, 'closed form of int_0^u (u-r) J|r-h/2| dr')

# ---- negative controls: wrong variants must be refuted (show the checks are not vacuous) ----
check('N1 front lower with CEIL instead of floor',
      And(dom, a < 0, s_clip(v, a, u, s_u), c >= P(v, a, w), c <= P(v, a, w) + 1, w >= 1000),
      s_u * w >= If(c > 0, c, 0) * u, expect_proof=False)
check('N2 rear upper a>0 with tangent v*u/T',
      And(dom, a > 0, s_clip(v, a, u, s_u), c >= v * w / T, c <= v * w / T + 1, w >= 1000, u == w),
      s_u * w <= c * u, expect_proof=False)
check('N3 inflate with h^3/16 (half the bound)',
      And(0 < h, h <= HMAX, 0 <= u, u <= h, 0 <= J, J <= JMAX, c >= J * h ** 3 / (16 * T ** 3) + h * h / (2 * T * T),
          c <= J * h ** 3 / (16 * T ** 3) + h * h / (2 * T * T) + 1),
      worst(u, h, J) <= c, expect_proof=False)
check('N4 disp_ub branch2 with v*w/(4T)',
      And(dom, a < 0, v * T + a * w < 0, s_clip(v, a, w, s_w), c >= v * w / (4 * T), c <= v * w / (4 * T) + 1),
      c >= s_w, expect_proof=False)
check('N5 monotone in v with v2 < v',
      And(dom, v2 < v - 1000, 0 <= v2, s_clip(v, a, u, s_u), s_clip(v2, a, u, s2), u >= 1000),
      s_u <= s2, expect_proof=False)

bad = [n for n, ok in RESULTS if not ok]
print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} lemmas proven" + (f"; NOT proven: {bad}" if bad else ''))
sys.exit(1 if bad else 0)
