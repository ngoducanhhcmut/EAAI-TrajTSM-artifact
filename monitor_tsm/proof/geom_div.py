"""Claude 05/11/2026 (W3): B3 RTL (rtl/geom/m_tsmx_geom_su.sv v0.6) constant divisions are exact.

The unit divides by D = 2^k * D' without a divider: N' = N >> k, q0 = (N' * M) >> s with M = floor(2^s/D'),
then q = q0 + [(N' - q0*D') mod 2^b >= D'] using only b low bits of N' and of q0*D' (b = 15 or 43).
Ceilings are formed as floor((N + D - 1)/D). Each instance below is modelled from the RTL lines cited and
checked against floor(N/D) for EVERY integer N in its range (Z3, linear integer arithmetic; `unsat` = no
counterexample). Ranges come from the START guard (v <= 2e7, |a| <= 8e6, 0 < w <= 1e5, 0 <= j < 2^32).
usage: python geom_div.py
"""
import sys
from z3 import Int, Solver, And, Not, If, unsat, sat

T = 10**6
def rtl_quot(N, k, Dp, s, M, b):
    Np = N / (2**k)                                   # N >> k   (N >= 0, Z3 integer division = floor)
    q0 = (Np * M) / (2**s)
    low = (Np - q0 * Dp) % (2**b)                     # (dn[b-1:0] - (q0*D')[b-1:0]) mod 2^b
    return q0 + If(low >= Dp, 1, 0), Np, q0

CASES = [  # name, N range (inclusive), k, D', s, M, b, D, RTL lines
    ('lin   floor(v*w/T)  (+999999 for ceil)', 0, 20 * T * 100000 + 999999, 6, 5**6, 35, 2199023, 15, 10**6, 'S5,S8,S12'),
    ('velq  |a|*w/T       (+999999 outward)',   0, 8 * T * 100000 + 999999, 6, 5**6, 35, 2199023, 15, 10**6, 'S6,S9,S12'),
    ('disp  (2vwT +- |a|w^2)/2T^2 (+2e12-1)',   1, 2 * 20 * T * 100000 * T + 8 * T * 100000**2 + 2 * 10**12 - 1,
                                                 13, 5**12, 49, 2305843, 43, 2 * 10**12, 'S10,S11,S12'),
    ('disp stopped  ceil(v*w/2T)',             0, 20 * T * 100000 + 1999999, 7, 5**6, 35, 2199023, 43, 2 * 10**6, 'S10 stopped'),
    ('infl  ceil(ceil(Jw^3/2^21)/5^18)',       0, (2**82) // 2**21 + 1 + 5**18 - 1, 0, 5**18, 62, 1208925, 43, 5**18, 'I3,I4,I5'),
]
ok_all = True
for name, lo, hi, k, Dp, s, M, b, D, lines in CASES:
    assert M == 2**s // Dp, (name, M, 2**s // Dp)
    assert D == 2**k * Dp
    N = Int('N')
    q, Np, q0 = rtl_quot(N, k, Dp, s, M, b)
    hyp = And(lo <= N, N <= hi)
    s_ = Solver(); s_.set('timeout', 900000)
    s_.add(hyp, Not(q == N / D))
    r = s_.check()
    # side conditions used by the RTL: N' < 2^s (premise of the q0 in {q-1,q} lemma), q0 < 2^22 (22-bit field)
    side = Solver(); side.add(hyp, Not(And(Np < 2**s, q0 < 2**22)))
    rs = side.check()
    ok = r == unsat and rs == unsat
    ok_all &= ok
    print(f"{'PROVEN ' if ok else 'FAILED '} {name:<42} N<=2^{hi.bit_length()}  [{lines}]"
          + ('' if ok else f'  eq={r} side={rs}'))
    # negative control: one fewer correction bit (b-1) must break exactness for this instance
    qbad, _, _ = rtl_quot(N, k, Dp, s, M, b - 1 if 2 * Dp > 2**(b - 1) else b)
    if 2 * Dp > 2**(b - 1):
        nc = Solver(); nc.set('timeout', 300000); nc.add(hyp, Not(qbad == N / D))
        print(f"   control b-1 bits: {'REFUTED (breaks, as expected)' if nc.check() == sat else 'not refuted'}")
sys.exit(0 if ok_all else 1)
