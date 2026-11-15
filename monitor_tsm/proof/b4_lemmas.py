"""Claude 04/11/2026 (W3): soundness lemmas for B4 (golden model.py:350-437) — continuous capped jerk ramp.

Within one B4 row (duration h <= DT = 1e5 us) the commanded acceleration is the capped ramp
    a(r) = a0 + j*min(r, tau)/T ,   tau = min(h, |target-a0|*T/|j|)    (j = 0: a(r) = a0)
with j in {0, +-2,4,8 m/s^3}. Same units/conventions as b3_lemmas.py (um, um/s, um/s^2, us, T = 1e6).
usage: python b4_lemmas.py
"""
import sys, time
from z3 import Reals, Solver, And, Or, Not, If, unsat, sat

T = 10**6
VMAX, AMIN, AMAX, HMAX, JMAX = 20 * 10**6, -8 * 10**6, 2 * 10**6, 100000, 8 * 10**6
RESULTS = []
def check(name, hyp, goal, note='', expect_proof=True):
    h0 = Solver(); h0.set('timeout', 600000); h0.add(hyp)
    if h0.check() != sat:
        RESULTS.append((name, False)); print(f"FAILED  {name:<46} hypotheses unsatisfiable (vacuous)"); return
    s = Solver(); s.set('timeout', 600000); s.add(hyp); s.add(Not(goal))
    t0 = time.time(); r = s.check(); dt = time.time() - t0
    ok = (r == unsat) if expect_proof else (r == sat)
    RESULTS.append((name, ok))
    tag = ('PROVEN ' if ok else 'FAILED ') if expect_proof else ('REFUTED' if ok else 'FAILED ')
    print(f"{tag} {name:<46} {dt:6.1f} s  {note}{'' if ok or not expect_proof else '  ' + str(s.model() if r == sat else r)}")

v, a0, j, tg, h, r, d, n = Reals('v a0 j tg h r d n')
# golden: d = |j| (j != 0), n = min(h*d, |tg-a0|*T)  =>  tau = n/d
ramp_dom = And(0 <= v, v <= VMAX, AMIN <= a0, a0 <= AMAX, AMIN <= tg, tg <= AMAX, 0 < h, h <= HMAX,
               j != 0, -JMAX <= j, j <= JMAX, d == If(j > 0, j, -j),
               n == If(h * d <= If(tg - a0 > 0, tg - a0, a0 - tg) * T, h * d, If(tg - a0 > 0, tg - a0, a0 - tg) * T))
tau = n / d
# exact integrals of the capped ramp at time h (piecewise: ramp phase [0,tau], hold phase [tau,h])
V_true = v + a0 * h / T + j * (tau * tau / 2 + tau * (h - tau)) / (T * T)
X_true = (v * h / T + a0 * h * h / (2 * T * T)
          + j * (tau ** 3 / 6 + tau * tau / 2 * (h - tau) + tau * (h - tau) ** 2 / 2) / T ** 3)
# golden numerators/denominators (model.py:358-368)
vd = 2 * T * T * d * d
vn = v * vd + 2 * a0 * h * T * d * d + j * (2 * n * h * d - n * n)
xd = 6 * T ** 3 * d ** 3
xn = 6 * v * h * T * T * d ** 3 + 3 * a0 * h * h * T * d ** 3 + j * ((h * d) ** 3 - (h * d - n) ** 3)
check('B4-1 vn/vd == exact velocity of capped ramp', ramp_dom, vn == V_true * vd)
check('B4-2 xn/xd == exact displacement of capped ramp', ramp_dom, xn == X_true * xd)
check('N1 xn with (h*d+n)^3 (wrong sign)', ramp_dom,
      6 * v * h * T * T * d ** 3 + 3 * a0 * h * h * T * d ** 3 + j * ((h * d) ** 3 - (h * d + n) ** 3) == X_true * xd,
      expect_proof=False)

# ---- B4-3: the ramp is monotone toward the target, so v(r) has at most one zero crossing on [0,h] ----
# a(r) is non-increasing when a0 > tg (j<0) and non-decreasing but <= tg <= 0 when a0 < tg <= 0.
# Case A (j<0, ramp down): v'' = a' <= 0 -> v concave. Case B (j>0): a(r) <= tg; if tg <= 0 then v' <= 0.
# State: if v(0) >= 0, v(h) < 0 and lo<hi with v(lo) >= 0 > v(hi), then v(r) < 0 for all r in [hi, h]
# (no re-crossing), so the root found by bisection is the unique stop time in [lo, hi).
r1, r2 = Reals('r1 r2')
def vel(rr):
    t_ = If(rr <= tau, rr, tau)
    return v + a0 * rr / T + j * (t_ * t_ / 2 + t_ * (rr - t_)) / (T * T)
# B4 structure (model.py:424): the ramp always heads TOWARD the target: sgn=-j if start>-b else +j
case_ok = Or(And(j < 0, a0 > tg), And(j > 0, a0 < tg))
check('B4-3 single crossing: v(r1)<0, r1<=r2<=h => v(r2)<0',
      And(ramp_dom, case_ok, tg <= 0, 0 <= r1, r1 <= r2, r2 <= h, vel(r1) < 0),
      vel(r2) < 0, 'bisection root is the stop time')
check('N2 single crossing without tg<=0 (positive target)',
      And(ramp_dom, j > 0, tg > 0, a0 < 0, 0 <= r1, r1 <= r2, r2 <= h, vel(r1) < 0),
      vel(r2) < 0, expect_proof=False)

# ---- B4-4: stop-time position bounds used by continuous_advance (model.py:372-380) ----
# lo: v(lo) >= 0, hi = lo + 1 us, v(hi) < 0, true stop tau_s in [lo, lo+1). x is non-decreasing on [0, tau_s].
# lower: floor(x(lo)) <= x(lo) <= x(tau_s).  upper: x(tau_s) <= x(lo) + v(lo)*1us/T  (speed <= v(lo) there).
lo, ts = Reals('lo ts')
def pos(rr):
    t_ = If(rr <= tau, rr, tau)
    return (v * rr / T + a0 * rr * rr / (2 * T * T)
            + j * (t_ ** 3 / 6 + t_ * t_ / 2 * (rr - t_) + t_ * (rr - t_) ** 2 / 2) / T ** 3)
stop_hyp = And(ramp_dom, case_ok, tg <= 0, 0 <= lo, lo + 1 <= h, vel(lo) >= 0, vel(lo + 1) < 0, lo <= ts, ts <= lo + 1, vel(ts) == 0)
check('B4-4a x(lo) <= x(stop)', stop_hyp, pos(lo) <= pos(ts))
# Golden upper bound: ceil(x(lo)) + ceil(v/T), v = row-start speed. The upper path only reaches the stop
# branch with v >= 1 LSB (vh == 0 sets `stopped` -> start = 0, sgn = 0 -> no crossing, model.py:421-424),
# so ceil(v/T) >= 1 um. It suffices that the motion after lo adds <= 1 um (it is < 2e-5 um: |v| < 10 um/s
# within one microsecond of the crossing).
# B4-4b split (direct form times out in nlsat): velocity bounds machine-checked, then the integral step
# x(ts)-x(lo) = int_lo^ts v(r) dr <= (ts-lo)*max v <= 1us*(8+2) um/s = 1e-5 um <= 1 um is by hand.
check('B4-4b1 v(lo) <= v(lo+1) + 8 um/s  (a >= -8 m/s^2)', stop_hyp, vel(lo) <= vel(lo + 1) + 8)
check('B4-4b2 v(r) <= v(lo) + 2 um/s on [lo, lo+1]  (a <= +2 m/s^2)', And(stop_hyp, lo <= r1, r1 <= lo + 1), vel(r1) <= vel(lo) + 2)
check('B4-4b3 hence v < 10 um/s on [lo, lo+1]', And(stop_hyp, lo <= r1, r1 <= lo + 1), vel(r1) < 10)
check('B4-4c lower path: speed stays >= 0 before the stop (x non-decreasing)', And(stop_hyp, 0 <= r1, r1 <= lo), vel(r1) >= 0)
check('N3 x(stop) <= x(lo) (missing +v/T term)', And(stop_hyp, v >= 1000), pos(ts) <= pos(lo), expect_proof=False)
check('N4 x(stop) <= x(lo) + 1e-9 um', And(stop_hyp, v >= 1), pos(ts) <= pos(lo) + 1/10**9, expect_proof=False)

bad = [nm for nm, ok in RESULTS if not ok]
print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} checks as expected" + (f"; NOT: {bad}" if bad else ''))
sys.exit(1 if bad else 0)
