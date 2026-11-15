"""Claude 05/11/2026 (W3): B4 -> B3 coupling. The B3 inflation (L10) assumes, inside every B4 row,
    |a_row(r) - cmd| <= J*|r - h/2|/T + 1 LSB     for r in [0, h],  J = row 'bound' = |sgn|
where a_row is the acceleration B4 actually integrates (start + sgn*r/T, clamped at the target -b) and
cmd = profile_a(cid, t-DT+DT/2, a0) is the midpoint value stored in the row (model.py:350-356, 416-431).
profile_a(el) moves from `init` toward -b by floor(j*el/T) and clamps there.  usage: python coupling_lemmas.py
"""
import sys, time
from z3 import Reals, Solver, And, Or, Not, If, unsat, sat

T = 10**6
AMIN, AMAX, JMAX, DT = -8 * 10**6, 2 * 10**6, 8 * 10**6, 100000
RESULTS = []
def check(name, hyp, goal, expect_proof=True):
    h0 = Solver(); h0.add(hyp)
    if h0.check() != sat:
        RESULTS.append((name, False)); print(f"FAILED  {name:<52} hypotheses unsatisfiable"); return
    s = Solver(); s.set('timeout', 600000); s.add(hyp); s.add(Not(goal))
    t0 = time.time(); r = s.check(); dt = time.time() - t0
    ok = (r == unsat) if expect_proof else (r == sat)
    RESULTS.append((name, ok))
    tag = ('PROVEN ' if ok else 'FAILED ') if expect_proof else ('REFUTED' if ok else 'FAILED ')
    print(f"{tag} {name:<52} {dt:6.1f} s{'' if ok or not expect_proof else '  ' + str(s.model() if r == sat else r)}")

init, b, j, el, c0, c1, r = Reals('init b j el c0 c1 r')
h = DT
def toward(x0, ch, tgt):           # profile_a body: move x0 toward tgt by ch >= 0, clamp at tgt
    return If(x0 > tgt, If(x0 - ch > tgt, x0 - ch, tgt), If(x0 + ch < tgt, x0 + ch, tgt))
tgt = -b
dom = And(AMIN <= init, init <= AMAX, 2 * 10**6 <= b, b <= 8 * 10**6, 2 * 10**6 <= j, j <= JMAX,
          0 <= el, el <= 12800000, 0 <= r, r <= h,
          # c0 = floor(j*el/T), c1 = floor(j*(el+h/2)/T): only the defining inequalities are used
          c0 <= j * el / T, j * el / T < c0 + 1, c1 <= j * (el + h / 2) / T, j * (el + h / 2) / T < c1 + 1, c0 >= 0)
start = toward(init, c0, tgt)
cmd = toward(init, c1, tgt)
sgn = If(start == tgt, 0, If(start > tgt, -j, j))
a_row = If(sgn == 0, start, If(sgn < 0, If(start - j * r / T > tgt, start - j * r / T, tgt),
                                        If(start + j * r / T < tgt, start + j * r / T, tgt)))
dev = If(r >= h / 2, r - h / 2, h / 2 - r)
check('C1 |a_row(r) - cmd| <= J|r-h/2|/T + 1 LSB', dom, And(a_row - cmd <= j * dev / T + 1, cmd - a_row <= j * dev / T + 1))
Jrow = If(sgn == 0, 0, j)   # B4 stores bound = |sgn|
check('C1b same with the stored row bound J=|sgn| (0 at target)', dom, And(a_row - cmd <= Jrow * dev / T + 1, cmd - a_row <= Jrow * dev / T + 1))
check('N1 same bound without the +1 LSB', dom, And(a_row - cmd <= j * dev / T, cmd - a_row <= j * dev / T), expect_proof=False)
check('C2 row jerk bound: |a_row(r2)-a_row(r)| <= J|r2-r|/T',
      And(dom, 0 <= Reals('r2')[0], Reals('r2')[0] <= h),
      And(a_row - If(sgn == 0, start, If(sgn < 0, If(start - j * Reals('r2')[0] / T > tgt, start - j * Reals('r2')[0] / T, tgt),
                                                   If(start + j * Reals('r2')[0] / T < tgt, start + j * Reals('r2')[0] / T, tgt)))
          <= j * If(r >= Reals('r2')[0], r - Reals('r2')[0], Reals('r2')[0] - r) / T))
bad = [n for n, ok in RESULTS if not ok]
print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} checks as expected" + (f"; NOT: {bad}" if bad else ''))
sys.exit(1 if bad else 0)
