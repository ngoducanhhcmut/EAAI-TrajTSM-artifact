# -*- coding: utf-8 -*-
"""Vector cho tb_fp32_units: chuan = sw/hwspec/fp.py (numpy IEEE + FTZ).

Ra tb/unit/bert_v2/vec/:
  fadd.hex : a b r     fmul.hex : a b r     i2f.hex : x r
  f2i_s8.hex : x r (LO=-128,HI=127)         f2i_u8.hex : x r (LO=0,HI=255)
Moi loai gom: ngau nhien rong dai, triet tieu, hoa lam tron, +-0, gan 2^-126, gia tri du lieu that.
"""
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fp import fadd, fmul, i2f, f2i_rne_sat, bits, from_bits, F32

OUT = Path(__file__).resolve().parents[2] / "tb" / "unit" / "bert_v2" / "vec"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(12345)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 300000


def rnd_f(n, emin=-60, emax=60):
    e = rng.integers(emin + 127, emax + 127, n).astype(np.uint32)
    m = rng.integers(0, 1 << 23, n).astype(np.uint32)
    s = rng.integers(0, 2, n).astype(np.uint32)
    return from_bits((s << 31) | (e << 23) | m)


def normalize_in(x):
    """dau vao khong denormal: denormal -> 0 co dau."""
    x = np.asarray(x, F32)
    return np.where((bits(x) & 0x7F800000) == 0, np.copysign(F32(0), x), x).astype(F32)


def pairs():
    A, B = [], []
    A.append(rnd_f(N)); B.append(rnd_f(N))                         # rong
    a = rnd_f(N // 4, -10, 10); A.append(a)
    B.append(from_bits(bits(-a) + rng.integers(-3, 4, a.size).astype(np.uint32)))   # triet tieu
    a = rnd_f(N // 4, -10, 10); A.append(a)
    B.append(rnd_f(N // 4, -10, 10) * F32(2.0 ** -24))             # lech mu ~24 (hoa/sticky)
    a = rnd_f(N // 8, -10, 10); A.append(a)
    sh = rng.integers(20, 30, a.size)
    B.append((a.astype(np.float64) * (2.0 ** -sh.astype(np.float64)) * rng.choice([-1, 1], a.size)).astype(F32))
    a = rnd_f(N // 8, -126, -120); A.append(a); B.append(rnd_f(N // 8, -126, -120))   # gan 2^-126
    a = rnd_f(N // 8, -70, -55); A.append(a); B.append(rnd_f(N // 8, -70, -55))       # tich duoi 2^-126
    z = np.array([0.0, -0.0, 1.0, -1.0, 3.0], F32)
    zz = np.array(np.meshgrid(z, z)).reshape(2, -1).astype(F32)
    A.append(zz[0]); B.append(zz[1])
    a = np.concatenate(A).astype(F32); b = np.concatenate(B).astype(F32)
    return normalize_in(a), normalize_in(b)


def w(name, cols):
    with open(OUT / name, "w") as f:
        for row in zip(*cols):
            f.write(" ".join("%08x" % (int(v) & 0xFFFFFFFF) for v in row) + "\n")
    print(name, len(cols[0]))


a, b = pairs()
with np.errstate(over="ignore"):
    w("fadd.hex", [bits(a), bits(b), bits(fadd(a, b))])
    w("fmul.hex", [bits(a), bits(b), bits(fmul(a, b))])

x = np.concatenate([rng.integers(-2**31, 2**31, N, dtype=np.int64),
                    rng.integers(-2**24 - 100, 2**24 + 100, N // 4),
                    np.array([0, 1, -1, 2**31 - 1, -2**31, 16777217, -16777217, 16777219])]).astype(np.int32)
w("i2f.hex", [x.view(np.uint32), bits(i2f(x))])

f = np.concatenate([rnd_f(N, -4, 18),
                    (np.arange(-600, 600) * 0.5).astype(F32),            # hoa .5
                    np.array([0.0, -0.0, 127.49999, 127.5, -128.5, -128.49998, 255.5, 254.5, 1e30, -1e30], F32)])
f = normalize_in(f)
w("f2i_s8.hex", [bits(f), f2i_rne_sat(f, -128, 127).astype(np.int64) & 0xFFFF])
w("f2i_u8.hex", [bits(f), f2i_rne_sat(f, 0, 255).astype(np.int64) & 0xFFFF])
