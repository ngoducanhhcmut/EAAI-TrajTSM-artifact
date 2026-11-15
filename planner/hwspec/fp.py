# -*- coding: utf-8 -*-
"""Nguyen thuy so hoc FP32 cua BERT phan cung moi — dinh nghia CHINH XAC TUNG BIT.

RTL phai khop tung bit voi cac ham nay. Quy uoc (giong fp32_add_f/fp32_mul_f trong
rtl/include/planning_pkg.sv):
  - IEEE-754 single, lam tron round-to-nearest-even.
  - Ket qua |r| < 2^-126 -> 0 co dau (flush-to-zero). Dau vao khong bao gio la denormal
    (moi nguon deu da FTZ) — `check_no_denormal` dung de khang dinh dieu do.
  - Tran so -> +-inf (khong xay ra voi du lieu that; co kiem).
Moi ham nhan/tra mang np.float32 (vector hoa duoc).
"""
import numpy as np

F32 = np.float32
U32 = np.uint32
TINY = F32(2.0 ** -126)


def ftz(x):
    x = np.asarray(x, dtype=F32)
    return np.where(np.abs(x) < TINY, np.copysign(F32(0.0), x), x).astype(F32)


def fadd(a, b):
    r = ftz(np.asarray(a, F32) + np.asarray(b, F32))
    # IEEE: x + (-x) = +0 ; RTL fp32_add_f cung tra +0 -> np cho +0 khi RNE. Giu nguyen.
    return r


def fsub(a, b):
    return fadd(a, -np.asarray(b, F32))


def fmul(a, b):
    return ftz(np.asarray(a, F32) * np.asarray(b, F32))


def i2f(x):
    """INT32 -> FP32, RNE (numpy int32->float32 la RNE)."""
    return np.asarray(x, dtype=np.int32).astype(F32)


def f2i_rne_sat(x, lo, hi):
    """FP32 -> so nguyen, RNE, bao hoa [lo, hi]. NaN khong xay ra."""
    x = np.asarray(x, F32).astype(np.float64)       # float64 chua du FP32 chinh xac
    return np.clip(np.rint(x), lo, hi).astype(np.int32)


def q8(x, inv_s):
    """Luong tu INT8 doi xung: RNE(x * inv_s), bao hoa [-128,127]."""
    return f2i_rne_sat(fmul(x, inv_s), -128, 127).astype(np.int8)


def bits(x):
    return np.asarray(x, F32).view(U32)


def from_bits(u):
    return np.asarray(u, U32).view(F32)


def check_finite_normal(x, name=""):
    x = np.asarray(x, F32)
    assert np.all(np.isfinite(x)), f"{name}: co inf/nan"
    nz = x[x != 0]
    assert np.all(np.abs(nz) >= TINY), f"{name}: co denormal"


# ── Bang tra hat giong (du lieu ROM trong RTL) ──────────────────────────────────
# rsqrt: chi so = {bit chan/le cua so mu (1 bit), 6 bit cao cua mantissa} -> 128 o.
#   v = 1.m * 2^E ; neu E chan: rsqrt = rsqrt(1.m) * 2^(-E/2)
#                   neu E le : rsqrt = rsqrt(2*1.m) * 2^(-(E-1)/2)
def _build_rsqrt_seed():
    t = np.zeros(128, F32)
    for odd in (0, 1):
        for k in range(64):
            m = 1.0 + (k + 0.5) / 64.0
            t[odd * 64 + k] = F32(1.0 / np.sqrt(m * (2.0 if odd else 1.0)))
    return t


RSQRT_SEED = _build_rsqrt_seed()

# recip: chi so = 6 bit cao mantissa -> 64 o; 1/(1.m) in (0.5, 1]
RECIP_SEED = np.array([F32(1.0 / (1.0 + (k + 0.5) / 64.0)) for k in range(64)], F32)

# exp2 phan le: 2^(k/1024), k = 0..1023
EXP2_FRAC = np.array([F32(2.0 ** (k / 1024.0)) for k in range(1024)], F32)

LOG2E = F32(1.4426950408889634)
HALF, ONE_HALF, TWO = F32(0.5), F32(1.5), F32(2.0)


def _pow2_int(n):
    """2^n chinh xac (n nguyen trong [-126,127]) duoi dang FP32."""
    n = np.asarray(n, np.int64)
    return from_bits(((n + 127).astype(np.int64) << 23).astype(U32))


def rsqrt(v):
    """v > 0 (chuan hoa). Hat giong 6 bit + 2 vong Newton: y = y*(1.5 - (0.5v)*y*y)."""
    v = np.asarray(v, F32)
    u = bits(v).astype(np.int64)
    E = ((u >> 23) & 0xFF) - 127
    odd = (E & 1)
    k = (u >> 17) & 0x3F
    seed = RSQRT_SEED[odd * 64 + k]
    y = fmul(seed, _pow2_int(-((E - odd) // 2)))
    h = fmul(v, HALF)
    for _ in range(2):
        t = fmul(y, y)
        t = fmul(h, t)
        t = fsub(ONE_HALF, t)
        y = fmul(y, t)
    return y


def recip(s):
    """s > 0 (chuan hoa). Hat giong 6 bit + 2 vong Newton: y = y*(2 - s*y)."""
    s = np.asarray(s, F32)
    u = bits(s).astype(np.int64)
    E = ((u >> 23) & 0xFF) - 127
    k = (u >> 17) & 0x3F
    y = fmul(RECIP_SEED[k], _pow2_int(-E))
    for _ in range(2):
        t = fmul(s, y)
        t = fsub(TWO, t)
        y = fmul(y, t)
    return y


def exp_neg(x):
    """exp(x) voi x <= 0. t = fmul(x, log2e); T = floor(t*1024) (so nguyen, CHINH XAC —
    RTL lay tu bit FP32 bang dich mantissa); n = T >> 10 (so hoc), k = T & 1023;
    ket qua = fmul(EXP2_FRAC[k], 2^n); t < -126 -> 0."""
    x = np.asarray(x, F32)
    t = fmul(x, LOG2E)
    under = t < F32(-126.0)
    tt = np.where(under, F32(0.0), t).astype(F32)
    T = np.floor(tt.astype(np.float64) * 1024.0).astype(np.int64)   # chinh xac voi FP32
    n = T >> 10
    k = T & 1023
    out = fmul(EXP2_FRAC[k], _pow2_int(np.maximum(n, -126)))
    return np.where(under, F32(0.0), out).astype(F32)


def sum_interleaved(x, P=8, axis=-1):
    """Tong FP32 theo thu tu RTL: P tong rieng xen ke (phan tu c vao tong c mod P, cong
    tuan tu), roi cay ((s0+s1)+(s2+s3))+((s4+s5)+(s6+s7)). P=8."""
    x = np.moveaxis(np.asarray(x, F32), axis, -1)
    n = x.shape[-1]
    assert n % P == 0
    s = [np.zeros(x.shape[:-1], F32) for _ in range(P)]
    for c in range(n):
        s[c % P] = fadd(s[c % P], x[..., c])
    a = [fadd(s[0], s[1]), fadd(s[2], s[3]), fadd(s[4], s[5]), fadd(s[6], s[7])]
    return fadd(fadd(a[0], a[1]), fadd(a[2], a[3]))
