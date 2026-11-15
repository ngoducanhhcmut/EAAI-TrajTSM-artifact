# -*- coding: utf-8 -*-
"""hwspec_exact — DAC TA CHINH XAC TUNG BIT cua Traj phan cung moi (cau hinh G, muc AI).

Hai phan:
  build_params(m, cal) : moi hang so phan cung (trong so INT4, thang FP32, bias, LN, bang
                         GELU, hang so softmax...). Hang so dan xuat tinh bang float64 roi
                         ep FP32 MOT LAN — RTL doc dung cac gia tri FP32 nay tu bo nho.
  forward(P, tok, pad) : chay tung tang theo DUNG thu tu phep tinh RTL (fp.py), tra ve
                         dict cac tang (de sinh vector testbench) va CLS FP32 sau final_ln.

Thu tu phep tinh (hop dong voi RTL, xem docs/KIEN_TRUC_BERT_V2.md):
  projector : a = fmul(tok0,W0); a = fadd(a, fmul(tok_k,W_k)) k=1..5; a = fadd(a,b); x = fadd(a,pos)
  LN        : s = sum8(x); mu = fmul(s,1/512); d = fsub(x,mu); v = fmul(sum8(fmul(d,d)),1/512)
              r = rsqrt(fadd(v,eps)); y = fadd(fmul(fmul(d,r),w),b)
  chieu     : y = fadd(fmul(i2f(acc),cs[o]),b[o])
  Q/K/V     : q8(y, inv_s)
  softmax   : s = fmul(i2f(acc),c_qk); m = max(s hop le); e = exp_neg(fsub(s,m)) (0 neu pad)
              S = sum8(e); g = fmul(recip(S),255); p = RNE_sat(fmul(e,g),0,255)
  ctx       : c8 = q8(i2f(sum_j p*v8), c_ctx)
  WO/W2     : x = fadd(x, y)
  W1        : g8 = LUT_l[q8(y, inv_s1)]
"""
from __future__ import annotations
import numpy as np
from fp import (F32, fadd, fsub, fmul, i2f, q8, f2i_rne_sat, rsqrt, recip, exp_neg,
                sum_interleaved, check_finite_normal)

N_TOK, D, H, HD, FF = 64, 512, 8, 64, 2048
INV512 = F32(1.0 / 512.0)
EPS = F32(1e-5)


def _f32(x):
    return np.asarray(np.asarray(x, np.float64), F32)


def gelu64(x):
    x = np.asarray(x, np.float64)
    return 0.5 * x * (1.0 + np.tanh(np.sqrt(2.0 / np.pi) * (x + 0.044715 * x ** 3)))


def build_params(m, cal):
    """m: W4A8PlanningModel; cal: dict thang hieu chinh tu HwSpec (q/k/v/w1 moi lop)."""
    P = {
        "proj_w": _f32(m.projector_w),          # (512, 6)
        "proj_b": _f32(m.projector_b),
        "pos": _f32(m.pos_emb[:N_TOK]),          # (64, 512)
        "pln_w": _f32(m.proj_ln_w), "pln_b": _f32(m.proj_ln_b),
        "fln_w": _f32(m.final_ln_w), "fln_b": _f32(m.final_ln_b),
        "layers": [],
    }
    for li, L in enumerate(m.bert_layers):
        s_in, s_ctx, s_gelu = float(L.act_scale_in), float(L.act_scale_ctx), float(L.act_scale_gelu)
        sq, sk, sv, s1 = (float(cal[f"q{li}"]), float(cal[f"k{li}"]), float(cal[f"v{li}"]),
                          float(cal[f"w1_{li}"]))
        lp = {}
        for nm, a_s in (("wq", s_in), ("wk", s_in), ("wv", s_in), ("wo", s_ctx),
                        ("w1", s_in), ("w2", s_gelu)):
            w4 = getattr(L, nm + "_int4").astype(np.int8)
            ws = np.asarray(getattr(L, nm + "_scale"), np.float64)
            b = getattr(L, "b" + nm[1:])
            lp[nm] = w4
            lp["cs_" + nm] = _f32(ws * a_s)
            lp["b_" + nm] = _f32(b) if b is not None else np.zeros(w4.shape[0], F32)
        lp.update({
            "ln1_w": _f32(L.ln1_w), "ln1_b": _f32(L.ln1_b),
            "ln2_w": _f32(L.ln2_w), "ln2_b": _f32(L.ln2_b),
            "inv_s_in": _f32(1.0 / s_in),
            "inv_sq": _f32(1.0 / sq), "inv_sk": _f32(1.0 / sk), "inv_sv": _f32(1.0 / sv),
            "c_qk": _f32(sq * sk / 8.0),
            "c_ctx": _f32(sv / 255.0 / s_ctx),
            "inv_s1": _f32(1.0 / s1),
            "gelu_lut": np.clip(np.rint(gelu64(np.arange(-128, 128) * s1) / s_gelu), -128, 127).astype(np.int8),
        })
        P["layers"].append(lp)
    return P


def layer_norm(x, w, b):
    s = sum_interleaved(x)                                   # (N,)
    mu = fmul(s, INV512)[:, None]
    d = fsub(x, mu)
    v = fmul(sum_interleaved(fmul(d, d)), INV512)
    r = rsqrt(fadd(v, EPS))[:, None]
    return fadd(fmul(fmul(d, r), w[None, :]), b[None, :])


def mm(w4, x8):
    """(Cout,Cin) INT4 x (N,Cin) INT8 -> (N,Cout) INT32 chinh xac."""
    return (x8.astype(np.int64) @ w4.astype(np.int64).T).astype(np.int32)


def proj(lp, nm, x8):
    acc = mm(lp[nm], x8)
    return acc, fadd(fmul(i2f(acc), lp["cs_" + nm][None, :]), lp["b_" + nm][None, :])


def projector(P, tok):
    W = P["proj_w"]
    a = fmul(tok[:, 0:1], W[None, :, 0])
    for k in range(1, 6):
        a = fadd(a, fmul(tok[:, k:k + 1], W[None, :, k]))
    a = fadd(a, P["proj_b"][None, :])
    return fadd(a, P["pos"])


def softmax_u8(acc, c_qk, valid):
    """acc: (H,N,N) INT32; valid: (N,) bool (khoa hop le). Tra p8 (H,N,N) uint8."""
    s = fmul(i2f(acc), c_qk)
    sm = np.where(valid[None, None, :], s, F32(-np.inf))
    mx = sm.max(axis=-1, keepdims=True)
    e = np.where(valid[None, None, :], exp_neg(fsub(s, mx)), F32(0.0)).astype(F32)
    S = sum_interleaved(e)                                    # (H,N)
    g = fmul(recip(S), F32(255.0))[..., None]
    return f2i_rne_sat(fmul(e, g), 0, 255).astype(np.uint8)


def bert_layer(lp, x, valid, st=None, li=0):
    def rec(k, v):
        if st is not None:
            st[f"L{li}_{k}"] = v
    h8 = q8(layer_norm(x, lp["ln1_w"], lp["ln1_b"]), lp["inv_s_in"]); rec("ln1q", h8)
    accq, q = proj(lp, "wq", h8); acck, k = proj(lp, "wk", h8); accv, v = proj(lp, "wv", h8)
    q8_, k8_, v8_ = q8(q, lp["inv_sq"]), q8(k, lp["inv_sk"]), q8(v, lp["inv_sv"])
    rec("q8", q8_); rec("k8", k8_); rec("v8", v8_)
    Q = q8_.reshape(N_TOK, H, HD).transpose(1, 0, 2).astype(np.int64)
    K = k8_.reshape(N_TOK, H, HD).transpose(1, 0, 2).astype(np.int64)
    V = v8_.reshape(N_TOK, H, HD).transpose(1, 0, 2).astype(np.int64)
    acc_qk = (Q @ K.transpose(0, 2, 1)).astype(np.int32); rec("qk", acc_qk)
    p8 = softmax_u8(acc_qk, lp["c_qk"], valid); rec("p8", p8)
    acc_pv = (p8.astype(np.int64) @ V).astype(np.int32)                 # (H,N,HD)
    acc_pv = acc_pv.transpose(1, 0, 2).reshape(N_TOK, D)
    c8 = q8(i2f(acc_pv), lp["c_ctx"]); rec("ctx8", c8)
    _, yo = proj(lp, "wo", c8)
    x = fadd(x, yo); rec("res1", x)
    h28 = q8(layer_norm(x, lp["ln2_w"], lp["ln2_b"]), lp["inv_s_in"]); rec("ln2q", h28)
    _, y1 = proj(lp, "w1", h28)
    g8 = lp["gelu_lut"][q8(y1, lp["inv_s1"]).astype(np.int32) + 128]; rec("gelu8", g8)
    _, y2 = proj(lp, "w2", g8)
    x = fadd(x, y2); rec("res2", x)
    check_finite_normal(x, f"L{li} res2")
    return x


def forward(P, tok, pad, st=None):
    """tok (64,6) FP32; pad (64,) bool True = dem. Tra CLS (512,) FP32 sau final_ln."""
    valid = ~np.asarray(pad, bool)
    tok = np.asarray(tok, F32)
    x = projector(P, tok)
    if st is not None:
        st["proj"] = x
    x = layer_norm(x, P["pln_w"], P["pln_b"])
    if st is not None:
        st["proj_ln"] = x
    for li, lp in enumerate(P["layers"]):
        x = bert_layer(lp, x, valid, st, li)
    cls = layer_norm(x[0:1], P["fln_w"], P["fln_b"])[0]
    if st is not None:
        st["cls"] = cls
    return cls
