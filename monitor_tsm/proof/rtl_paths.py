"""Claude 05/11/2026 (W3): path-sensitive refinement of the 4 TRZ findings of rtl_ranges.py.

DISP (ops 2/4) and DINT (op 3) compute the moving-branch numerator 2*v*n*T*d + a*n^2 (DINT: d = 1,
n = h) and TRZ it to 128 / 96 bits BEFORE the stop-clip select DSEL. A negative value would be zero-extended
(changed), but DSEL then overwrites T24/T25 with v^2 / 2|a| exactly when the clip condition holds
(RTL: T21 < 0 and T27 = n*|a| >= T28 = v*T*d; golden disp(): a < 0 and n*(-a) >= v*T*d).
So it suffices that in the NON-clip branch the numerator lies in [0, 2^W).  usage: python rtl_paths.py
"""
import sys
from z3 import Ints, Solver, And, Or, Not, unsat, sat

T = 10**6
v, a, n, d = Ints('v a n d')
base = And(0 <= v, v <= 20 * T, -8 * T <= a, a <= 2 * T)
num = 2 * v * n * T * d + a * n * n
clip = And(a < 0, n * (-a) >= v * T * d)
CASES = [
    ('op2 DISP (guard n<2^46, 0<d<2^24)', And(0 <= n, n < 2**46, 0 < d, d < 2**24), 128),
    ('op4 DISP (valid points n<=2e13, 1<=d<=1e7)', And(0 <= n, n <= 2 * 10**13, 1 <= d, d <= 10**7), 128),
    ('op3 DINT (d=1, n=h<=12.8e6)', And(d == 1, 0 <= n, n <= 12800000), 96),
]
ok_all = True
for name, dom, w in CASES:
    s = Solver(); s.set('timeout', 600000)
    s.add(base, dom, Not(clip), Not(And(0 <= num, num < 2**w)))
    r = s.check()
    neg = Solver(); neg.add(base, dom, num < 0)          # control: negative values do exist (then clip holds)
    rn = neg.check()
    ok = r == unsat and rn == sat
    ok_all &= ok
    print(f"{'PROVEN ' if r == unsat else 'FAILED '} {name}: non-clip numerator in [0, 2^{w})"
          f"   (control: negative numerator reachable = {rn == sat}, and only under clip)")
    s2 = Solver(); s2.add(base, dom, num < 0, Not(clip))
    if s2.check() != unsat: ok_all = False; print('   FAILED: a negative numerator outside the clip branch:', s2.model())
sys.exit(0 if ok_all else 1)
