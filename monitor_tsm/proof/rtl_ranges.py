"""Claude 05/11/2026 (W3): no-silent-overflow check of the RTL arithmetic unit rtl/arith/m_tsmx_arith.sv.

The unit's input guard and its output fit checks raise a fault (=> REJECT, fail-safe). What is NOT checked:
  * MUL/ADD/SUB results are taken modulo 2^160,
  * TRZ/TRS micro-ops keep only 88/96/112/128 bits,
  * the divider masks numerator/denominator to its width class (96/128/160 bits).
If any of these could change a value, the RTL could silently differ from the golden. This script parses the
micro-programs and MOV prologues directly from the RTL text and runs them in interval arithmetic (exact Python
integers) from the guard ranges of each operation; every silent truncation point must provably keep its value.
Interval arithmetic over-approximates, so PASS is sound; a FAIL is a *possible* overflow to be refined.
usage: python rtl_ranges.py [path/to/m_tsmx_arith.sv]
"""
import re, sys
from pathlib import Path

SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'rtl/arith/m_tsmx_arith.sv'
text = SRC.read_text()
CONST = {'LPARA_C0': 0, 'LPARA_C1': 1, 'LPARA_C1E6': 10**6, 'LPARA_C2E6': 2 * 10**6, 'LPARA_C3E6': 3 * 10**6,
         'LPARA_C2E12': 2 * 10**12, 'LPARA_C6E12': 6 * 10**12, 'LPARA_C6E18': 6 * 10**18}
SLOT = {'LPARA_C0': 52, 'LPARA_C1': 53, 'LPARA_C1E6': 54, 'LPARA_C2E6': 55, 'LPARA_C3E6': 56,
        'LPARA_C2E12': 57, 'LPARA_C6E12': 58, 'LPARA_C6E18': 59}
INV = {v: k for k, v in SLOT.items()}
TRW = {0: 88, 1: 96, 2: 112, 3: 128}

def operand(tok):
    tok = tok.strip()
    m = re.fullmatch(r"6'd(\d+)", tok)
    if m: return int(m[1])
    m = re.fullmatch(r"6'\(LPARA_Q0\+6'd(\d+)\)", tok)
    if m: return 40 + int(m[1])
    if tok in SLOT: return SLOT[tok]
    raise ValueError(tok)

def parse_block(name):
    """micro-op lists of `name:` case blocks (programs LPARA_P_*, prologues LPARA_L_*)."""
    m = re.search(r'\n\s*' + name + r': case \(w_(?:pc|i)\)(.*?)endcase', text, re.S)
    ops = []
    for k, d, a, b in re.findall(r"f_u\(LPARA_K_(\w+),([^,]+),([^,]+),([^)]+(?:\))?)\);", m[1]):
        if b.count('(') > b.count(')'): b += ')'
        ops.append((k, operand(d), operand(a), operand(b)))
    return ops

PROGS = {p: parse_block('LPARA_P_' + p) for p in ('RAMP', 'DISP', 'DINT', 'PT23', 'PTX')}
LODS = {l: parse_block('LPARA_L_' + l) for l in ('OP2', 'OP3', 'OP6', 'OP7', 'PT0', 'PT1', 'PT2', 'PT3', 'WD0', 'WD1')}

S160 = (-(1 << 159), (1 << 159) - 1)
FAILS, NOTES = [], []
def flag(ctx, msg): FAILS.append(f'{ctx}: {msg}')

def mul(a, b):
    c = [a[0] * b[0], a[0] * b[1], a[1] * b[0], a[1] * b[1]]
    return (min(c), max(c))
def union(a, b): return (min(a[0], b[0]), max(a[1], b[1]))
def fits_s(iv, w): return -(1 << (w - 1)) <= iv[0] and iv[1] < (1 << (w - 1))

def run(ctx, q, lod, prog, env=None, stop_before=None):
    """interval-execute prologue `lod` then program `prog`; returns the temporary environment."""
    t = dict(env or {})
    def val(i):
        if i < 40:
            if i not in t: flag(ctx, f'read of unwritten T{i}'); return (0, 0)
            return t[i]
        if i < 52: return q[i - 40]
        return (CONST.get(INV.get(i, ''), 0),) * 2
    seq = (LODS[lod] if lod else []) + (PROGS[prog] if prog else [])
    for pc, (k, d, a, b) in enumerate(seq):
        if stop_before and k == stop_before: break
        where = f'{ctx} {k} T{d}'
        if k == 'MOV': t[d] = val(a)
        elif k in ('MUL', 'ADD', 'SUB'):
            x, y = val(a), val(b)
            r = mul(x, y) if k == 'MUL' else ((x[0] + y[0], x[1] + y[1]) if k == 'ADD' else (x[0] - y[1], x[1] - y[0]))
            if not fits_s(r, 160): flag(where, f'{k} wraps mod 2^160: {r}')
            t[d] = r
        elif k == 'ABS':
            x = val(a)
            t[d] = x if x[0] >= 0 else ((-x[1], -x[0]) if x[1] <= 0 else (0, max(-x[0], x[1])))
        elif k == 'TRZ':
            x, w = val(a), TRW[b & 3]
            if not (x[0] >= 0 and x[1] < (1 << w)): flag(where, f'TRZ{w} changes value: {x}')
            t[d] = x
        elif k == 'TRS':
            x, w = val(a), TRW[b & 3]
            if not fits_s(x, w): flag(where, f'TRS{w} changes value: {x} (limit 2^{w-1}={1 << (w-1):.3e})')
            else: NOTES.append(f'{where}: TRS{w} margin {max(-x[0], x[1]) / (1 << (w - 1)):.4f} of the limit')
            t[d] = x
        elif k == 'RD':                       # d = |j|, or 1 when j == 0
            x = val(2); m = max(abs(x[0]), abs(x[1]))
            lo = 1 if x[0] <= 0 <= x[1] else min(abs(x[0]), abs(x[1]))
            t[5] = (min(lo, 1), m)
        elif k == 'RN':                       # n = min(T6, T7), or 0 when j == 0
            x6, x7 = val(6), val(7)
            t[8] = (min(0, x6[0], x7[0]), min(x6[1], x7[1]))
        elif k == 'DSEL':                     # T24/T25 may take T29/T30 (stop clip)
            t[d] = union(val(d), val(29 if d == 24 else 30))
        elif k == 'NEGIF':
            src = val(23) if d == 23 else val(22)
            t[d] = union(src, (-src[1], -src[0])) if val(23)[0] < 0 else src
        elif k == 'EAB':
            slot = {34: 2, 35: 4, 36: 1, 37: 3}[d]
            t[d] = union(q[slot], (0, 0))
        elif k in ('ENDVN', 'V23', 'VX', 'END'): pass
        else: flag(where, f'unknown micro-op {k}')
    return t

def div_check(ctx, num, den, w):
    if not fits_s(num, w) or num[0] == -(1 << (w - 1)): flag(ctx, f'divider numerator masked to {w} bits: {num}')
    if not (den[1] < (1 << (w - 1))): flag(ctx, f'divider denominator masked to {w} bits: {den}')
    NOTES.append(f'{ctx}: div{w} numerator uses {max(abs(num[0]), abs(num[1])).bit_length()} bits, '
                 f'denominator {den[1].bit_length()} bits')

S = 10**6
V, A, J = (0, 20 * S), (-8 * S, 2 * S), (-8 * S, 8 * S)
X64 = (-(1 << 63) + 1, (1 << 63) - 1)

def op2():                     # rational displacement disp(v,a,n,d) (guard: n < 2^46, 0 < d < 2^24)
    q = [V, A, (0, (1 << 46) - 1), (1, (1 << 24) - 1), (0, 1)] + [(0, 0)] * 7
    t = run('op2', q, 'OP2', 'DISP')
    div_check('op2 D_DIV', t[24], t[25], 128)

def op3():                     # integer-time advance (h <= 12.8e6)
    q = [X64, V, A, (0, 12800000), (0, 1)] + [(0, 0)] * 7
    t = run('op3', q, 'OP3', 'DINT')
    div_check('op3 A_DIV0', t[24], t[25], 96)
    div_check('op3 A_DIV1', t[31], (S, S), 96)

def op4():                     # swept minimum gap: candidate times n/d from phases PT0..PT6
    q = [X64, V, A, V, A, (0, 12800000)] + [(0, 0)] * 6
    nd = {}
    nd['PT0'] = run('op4 PT0', q, 'PT0', None)
    nd['PT1'] = run('op4 PT1', q, 'PT1', None)
    nd['PT2'] = run('op4 PT2', q, 'PT2', 'PT23')
    nd['PT3'] = run('op4 PT3', q, 'PT3', 'PT23')
    nd['PTX'] = run('op4 PTX', q, None, 'PTX')
    n = d = None
    for ph, t in nd.items():
        n = t[22] if n is None else union(n, t[22]); d = t[23] if d is None else union(d, t[23])
    # DISP only runs for a VALID point (V23/VX): 0 < n, n < d*h, d > 0  -> clip to the valid domain
    n = (0, n[1]); d = (1, d[1])
    NOTES.append(f'op4 candidate time n in {n}, d in {d} (union over the 7 phases, valid points only)')
    for lod, (vs, as_) in (('WD0', (1, 2)), ('WD1', (3, 4))):
        t = run(f'op4 {lod}', q, lod, 'DISP', env={22: n, 23: d})
        div_check(f'op4 {lod} divider', t[24], t[25], 128)

def ramp(op, hmax):
    base = [V, A, J, A, (0, hmax)]
    q = (base if op == 6 else [X64] + base + [(0, 1)]) + [(0, 0)] * (7 if op == 6 else 5)
    t = run(f'op{op} h<={hmax}', q, f'OP{op}', 'RAMP')
    div_check(f'op{op} h<={hmax} R_DIV0 xn/xd', t[16], t[15], 160)
    div_check(f'op{op} h<={hmax} R_DIV1 vn/vd', t[11], t[10], 160)

op2(); op3(); op4(); ramp(6, 100000); ramp(7, 100000)
nfail_used = len(FAILS)
ramp(7, 12800000)             # the guard admits h up to 12.8e6 for op 7: is that range also overflow-free?
print('micro-programs parsed:', {k: len(v) for k, v in PROGS.items()})
for n_ in NOTES: print('  note:', n_)
print()
if FAILS:
    for f in FAILS: print('POSSIBLE OVERFLOW', f)
print(f"\nused ranges (h <= DT=1e5 for ops 6/7, as issued by B4): {'PASS' if nfail_used == 0 else 'FAIL'} "
      f"({nfail_used} findings); full op-7 guard range h <= 12.8e6: {len(FAILS) - nfail_used} findings")
sys.exit(1 if nfail_used else 0)
