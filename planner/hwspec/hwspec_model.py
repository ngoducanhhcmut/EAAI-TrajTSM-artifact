# -*- coding: utf-8 -*-
"""hwspec — dac ta so hoc cho BERT phan cung MOI cua Traj (Giai doan 0, docs/KE_HOACH_TRAJ_E2E.md).

Ban nay (0.1/0.2) dung de CHON so hoc: moi lua chon xap xi la mot cong tac trong `opts`,
do anh huong bang ADE tren 35 mau golden_spec. Ban bit-exact theo thu tu phep tinh RTL
se lam o 0.1b sau khi chot lua chon (cung file, them che do `exact_order`).

Quy uoc chung:
  - Trong so INT4 doi xung theo hang (giong W4A8), kich hoat INT8 doi xung (zp=0).
  - Tich INT4 x INT8 -> INT32 chinh xac.
  - Moi phep FP32 la float32 numpy (IEEE RNE). Lam tron luong tu: np.round (RNE).
"""
from __future__ import annotations
import numpy as np

F32 = np.float32


def q8(x, scale):
    """FP32 -> INT8 doi xung, RNE, bao hoa."""
    return np.clip(np.round(x.astype(F32) / F32(scale)), -128, 127).astype(np.int8)


def mm_i32(w_int4, x_int8):
    """(Cout,Cin) int4 x (N,Cin) int8 -> (N,Cout) int32 chinh xac."""
    return (x_int8.astype(np.int32) @ w_int4.astype(np.int32).T).astype(np.int32)


def gelu_f(x):
    x = x.astype(F32)
    return (F32(0.5) * x * (F32(1.0) + np.tanh(F32(np.sqrt(2.0 / np.pi)) * (x + F32(0.044715) * x * x * x)))).astype(F32)


def layer_norm(x, w, b, eps=1e-5):
    x = x.astype(F32)
    mean = x.mean(axis=-1, keepdims=True, dtype=F32)
    var = ((x - mean) ** 2).mean(axis=-1, keepdims=True, dtype=F32)
    return (w * ((x - mean) / np.sqrt(var + F32(eps))) + b).astype(F32)


DEFAULT_OPTS = dict(
    proj_ln=True,        # LN sau projector (mo hinh co)
    final_ln=True,       # final_ln truoc GRU (mo hinh co)
    resid="fp32",        # fp32 | int16 | int8   (dang luu residual giua cac tang)
    attn="fp32",         # fp32 | int8   (Q,K,V luong tu INT8 doi xung theo lop)
    prob="fp32",         # fp32 | u8     (xac suat softmax luong tu 8 bit, thang 1/255)
    gelu="fp32",         # fp32 | lut8   (dau vao GELU luong tu INT8 theo lop, bang 256 o)
    bias=True,           # cong bias cac phep chieu
)


class HwSpec:
    def __init__(self, m, calib_tokens, calib_masks, opts=None):
        """m: W4A8PlanningModel (trong so INT4, thang, bias, LN, GRU)."""
        self.m = m
        self.o = dict(DEFAULT_OPTS, **(opts or {}))
        self.cal = {}
        self._calibrate(calib_tokens, calib_masks)

    # ── hieu chinh: chay duong FP32 tren tap hieu chinh, lay max|.| moi tensor ──
    def _calibrate(self, toks, masks):
        stats = {}
        saved = self.o
        self.o = dict(DEFAULT_OPTS)          # duong tham chieu FP32 de lay thong ke
        for t, mk in zip(toks, masks):
            self._forward_tokens(t, mk, stats=stats)
        self.o = saved
        self.cal = {k: max(v / 127.0, 1e-8) for k, v in stats.items()}
        # Thang residual INT16: cung max, chia 32767
        self.cal16 = {k: max(v / 32767.0, 1e-8) for k, v in stats.items()}

    @staticmethod
    def _st(stats, key, x):
        if stats is not None:
            stats[key] = max(stats.get(key, 0.0), float(np.max(np.abs(x))))

    def _store_resid(self, x, key):
        r = self.o["resid"]
        if r == "fp32":
            return x
        if r == "int16":
            s = F32(self.cal16[key])
            return (np.clip(np.round(x / s), -32768, 32767) * s).astype(F32)
        s = F32(self.cal[key])
        return (np.clip(np.round(x / s), -128, 127) * s).astype(F32)

    def _layer(self, L, li, x, pmask, stats):
        o = self.o
        x = self._store_resid(x, f"x{li}_in")
        self._st(stats, f"x{li}_in", x)

        h = layer_norm(x, L.ln1_w, L.ln1_b)
        h8 = q8(h, L.act_scale_in)
        def proj(w, ws, xin8, a_s, b):
            y = mm_i32(w, xin8).astype(F32) * (ws * F32(a_s)).astype(F32)[None, :]
            if o["bias"] and b is not None:
                y = y + b
            return y.astype(F32)
        q = proj(L.wq_int4, L.wq_scale, h8, L.act_scale_in, L.bq)
        k = proj(L.wk_int4, L.wk_scale, h8, L.act_scale_in, L.bk)
        v = proj(L.wv_int4, L.wv_scale, h8, L.act_scale_in, L.bv)
        self._st(stats, f"q{li}", q); self._st(stats, f"k{li}", k); self._st(stats, f"v{li}", v)

        N = x.shape[0]; H, d = L.num_heads, L.head_dim
        if o["attn"] == "int8":
            sq, sk, sv = self.cal[f"q{li}"], self.cal[f"k{li}"], self.cal[f"v{li}"]
            qi, ki, vi = q8(q, sq), q8(k, sk), q8(v, sv)
            Q = qi.reshape(N, H, d).transpose(1, 0, 2).astype(np.int32)
            K = ki.reshape(N, H, d).transpose(1, 0, 2).astype(np.int32)
            sc = (Q @ K.transpose(0, 2, 1)).astype(F32) * F32(sq * sk / 8.0)
            Vf = vi.reshape(N, H, d).transpose(1, 0, 2).astype(F32)
            vscale = F32(sv)
        else:
            Q = q.reshape(N, H, d).transpose(1, 0, 2)
            K = k.reshape(N, H, d).transpose(1, 0, 2)
            sc = (Q @ K.transpose(0, 2, 1)).astype(F32) * F32(0.125)
            Vf = v.reshape(N, H, d).transpose(1, 0, 2)
            vscale = F32(1.0)
        if pmask is not None:
            sc[:, :, pmask] = F32(-1e9)
        sc = sc - sc.max(axis=-1, keepdims=True)
        e = np.exp(sc).astype(F32)
        p = (e / e.sum(axis=-1, keepdims=True, dtype=F32)).astype(F32)
        if o["prob"] == "u8":
            p = (np.round(p * F32(255.0)) / F32(255.0)).astype(F32)
        ctx = ((p @ Vf) * vscale).transpose(1, 0, 2).reshape(N, H * d).astype(F32)
        self._st(stats, f"ctx{li}", ctx)

        c8 = q8(ctx, L.act_scale_ctx)
        wo = proj(L.wo_int4, L.wo_scale, c8, L.act_scale_ctx, L.bo)
        x = self._store_resid((x + wo).astype(F32), f"r1_{li}")
        self._st(stats, f"r1_{li}", x)

        h2 = layer_norm(x, L.ln2_w, L.ln2_b)
        h28 = q8(h2, L.act_scale_in)
        w1 = proj(L.w1_int4, L.w1_scale, h28, L.act_scale_in, L.b1)
        self._st(stats, f"w1_{li}", w1)
        if o["gelu"] == "lut8":
            s1 = F32(self.cal[f"w1_{li}"])
            idx = q8(w1, s1).astype(np.int32)
            table = q8(gelu_f(np.arange(-128, 128).astype(F32) * s1), L.act_scale_gelu)
            g8 = table[idx + 128]
        else:
            g8 = q8(gelu_f(w1), L.act_scale_gelu)
        w2 = proj(L.w2_int4, L.w2_scale, g8, L.act_scale_gelu, L.b2)
        x = (x + w2).astype(F32)
        return x

    def _forward_tokens(self, tok, pmask, stats=None, trace=None):
        m, o = self.m, self.o
        N = tok.shape[0]
        x = (tok.astype(F32) @ m.projector_w.T.astype(F32) + m.projector_b).astype(F32)
        x = (x + m.pos_emb[np.arange(N)]).astype(F32)
        if o["proj_ln"]:
            x = layer_norm(x, m.proj_ln_w, m.proj_ln_b)
        for li, L in enumerate(m.bert_layers):
            x = self._layer(L, li, x, pmask, stats)
        self._st(stats, "x_out", x)
        cls = x[0:1]
        if o["final_ln"]:
            cls = layer_norm(cls, m.final_ln_w, m.final_ln_b)
        if trace is not None:
            trace["cls"] = cls[0].copy()
        return cls

    def waypoints(self, tok, pmask, trace=None):
        cls = self._forward_tokens(tok, pmask, trace=trace)
        return self.m.gru.forward(cls.astype(F32))[0]
